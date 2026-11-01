import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/session/auth_repository.dart';
import '../../core/session/session_context.dart';
import '../../core/session/slugify.dart';
import '../../core/ui/state_views.dart';
import '../../data/supabase_client.dart';
import '../../design_system/brand_widgets.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import 'onboarding_repository.dart';

/// Creates a restaurant workspace (owner only — the creator becomes owner).
///
/// Steps: restaurant name → slug with LIVE availability check → brand
/// colors (presets) → optional logo → atomic server creation.
///
/// Creation REQUIRES connectivity (slug uniqueness is server-side): when
/// offline the form explains it instead of failing silently.
class CreateWorkspaceScreen extends StatefulWidget {
  const CreateWorkspaceScreen({super.key});

  @override
  State<CreateWorkspaceScreen> createState() => _CreateWorkspaceScreenState();
}

enum _SlugState { idle, checking, available, taken, invalid }

class _CreateWorkspaceScreenState extends State<CreateWorkspaceScreen> {
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _auth = AuthRepository();

  bool _slugTouched = false;
  _SlugState _slugState = _SlugState.idle;
  Timer? _slugDebounce;

  String _primaryColor = '#E8641B';
  String _secondaryColor = '#2A2118';

  XFile? _logo;
  bool _submitting = false;
  String? _error;

  static const _primaryPresets = [
    '#E8641B', // tchop orange
    '#C0392B', // braisé red
    '#1E7A34', // plantain green
    '#0E7CC4', // ocean blue
    '#8E44AD', // bissap purple
    '#B8860B', // gold
    '#2A2118', // charcoal
    '#E84393', // hibiscus pink
  ];

  static const _secondaryPresets = [
    '#2A2118',
    '#14231A',
    '#10222F',
    '#3B2F2F',
    '#1A1A2E',
    '#4A4A4A',
    '#FFFFFF',
    '#F5F0E8',
  ];

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
    _slugController.addListener(_onSlugChanged);
    // Best-effort: finish any logo upload left pending by an earlier attempt.
    unawaited(_retryPendingLogos());
  }

  Future<void> _retryPendingLogos() async {
    try {
      final session = SessionScope.of(context, listen: false);
      final uploaded =
          await OnboardingRepository(auth: _auth).retryPendingLogos();
      var synced = 0;
      for (final entry in uploaded.entries) {
        try {
          await session.enqueueMutation(
            tenantId: entry.key,
            op: 'update',
            entity: 'branding',
            entityId: entry.key,
            payload: {'logo_url': entry.value},
          );
          synced++;
        } catch (_) {
          // stays out of the pending file; the URL is uploaded, the
          // branding row will converge on the next retry
        }
      }
      if (synced > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logo en attente téléversé avec succès.'),
          ),
        );
      }
    } catch (_) {
      // silent — the create form stays usable
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _slugDebounce?.cancel();
    super.dispose();
  }

  void _onNameChanged() {
    if (_slugTouched) return;
    final suggestion = slugify(_nameController.text);
    if (suggestion != _slugController.text) {
      _slugController.text = suggestion;
    }
  }

  void _onSlugChanged() {
    _slugDebounce?.cancel();
    final slug = _slugController.text.trim().toLowerCase();
    if (slug != _slugController.text) {
      // keep the field normalized as the user types
      _slugController.value = TextEditingValue(
        text: slug,
        selection: TextSelection.collapsed(offset: slug.length),
      );
      return;
    }
    if (slug.isEmpty) {
      setState(() => _slugState = _SlugState.idle);
      return;
    }
    if (!isValidSlug(slug)) {
      setState(() => _slugState = _SlugState.invalid);
      return;
    }
    setState(() => _slugState = _SlugState.checking);
    _slugDebounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final available = await _auth.slugAvailable(slug);
        if (!mounted) return;
        setState(() => _slugState =
            available ? _SlugState.available : _SlugState.taken);
      } catch (_) {
        // Offline or backend hiccup — the submit path re-checks and shows
        // the explicit offline message.
        if (mounted) setState(() => _slugState = _SlugState.idle);
      }
    });
  }

  Future<void> _pickLogo() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file != null) setState(() => _logo = file);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d’ouvrir la galerie photo.'),
          ),
        );
      }
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final slug = _slugController.text.trim().toLowerCase();
    if (name.isEmpty) {
      setState(() => _error = 'Donnez un nom à votre restaurant.');
      return;
    }
    if (!isValidSlug(slug)) {
      setState(() => _error =
          'Nom court invalide : lettres minuscules, chiffres et tirets (3 à 40 caractères).');
      return;
    }
    if (!TchopSupabase.isConfigured) {
      setState(() => _error =
          'La création d’un restaurant nécessite une connexion Internet et un backend configuré.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // Final server-side availability check (the live indicator may be stale).
      final available = await _auth.slugAvailable(slug);
      if (!available) {
        setState(() => _slugState = _SlugState.taken);
        throw const AuthFailure(
          'Ce nom court vient d’être pris. Essayez-en un autre.',
        );
      }
      final session = SessionScope.of(context, listen: false);
      final result = await OnboardingRepository(auth: _auth).createWorkspace(
        name: name,
        slug: slug,
        primaryColor: _primaryColor,
        secondaryColor: _secondaryColor,
        logoFile: _logo,
      );
      // Persist the logo URL through the offline-capable branding op.
      if (result.logoUrl != null) {
        try {
          await session.enqueueMutation(
            tenantId: result.tenantId,
            op: 'update',
            entity: 'branding',
            entityId: result.tenantId,
            payload: {'logo_url': result.logoUrl},
          );
        } catch (_) {
          // Non-fatal: the logo is uploaded; the URL syncs on the next
          // drain.
        }
      }
      await session.refreshMemberships();
      await session.switchTenant(result.tenantId);
      if (!mounted) return;
      if (result.logoPending) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Restaurant créé ! Le logo sera téléversé automatiquement dès que possible.',
            ),
          ),
        );
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'La création a échoué : $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer mon restaurant')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (!TchopSupabase.isConfigured)
              const OfflineBanner(
                message: 'La création d’un restaurant nécessite une '
                    'connexion Internet. Reconnectez-vous pour continuer.',
              ),
            Text('Nom du restaurant', style: TchopTypography.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Ex. Le Baobab Gourmand',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text('Nom court (adresse)', style: TchopTypography.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Il apparaîtra dans l’adresse de votre restaurant, ex. lapalmeraie.tchop.cm',
              style: TextStyle(fontSize: 13, color: TchopColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _slugController,
              onChanged: (_) => _slugTouched = true,
              decoration: InputDecoration(
                hintText: 'le-baobab-gourmand',
                border: const OutlineInputBorder(),
                suffixIcon: _slugSuffix(),
              ),
            ),
            _slugHint(),
            const SizedBox(height: 20),
            Text('Couleur principale', style: TchopTypography.titleMedium),
            const SizedBox(height: 8),
            _ColorRow(
              colors: _primaryPresets,
              selected: _primaryColor,
              onSelect: (c) => setState(() => _primaryColor = c),
            ),
            const SizedBox(height: 16),
            Text('Couleur secondaire', style: TchopTypography.titleMedium),
            const SizedBox(height: 8),
            _ColorRow(
              colors: _secondaryPresets,
              selected: _secondaryColor,
              onSelect: (c) => setState(() => _secondaryColor = c),
            ),
            const SizedBox(height: 20),
            Text('Logo', style: TchopTypography.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: _hexColor(_primaryColor),
                  backgroundImage:
                      _logo == null ? null : FileImage(File(_logo!.path)),
                  child: _logo == null
                      ? Text(
                          _nameController.text.trim().isEmpty
                              ? '?'
                              : _nameController.text.trim()[0].toUpperCase(),
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(_logo == null
                            ? 'Choisir un logo'
                            : 'Changer le logo'),
                        onPressed: _pickLogo,
                      ),
                      if (_logo != null)
                        TextButton(
                          onPressed: () => setState(() => _logo = null),
                          child: const Text('Retirer'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: TchopColors.error.withValues(alpha: 31),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: TchopColors.error.withValues(alpha: 102)),
                ),
                child: Text(_error!,
                    style: TextStyle(
                        color: TchopColors.error, fontSize: 13)),
              ),
            ],
            const SizedBox(height: 24),
            BrandButton(
              label: _submitting ? 'Création en cours…' : 'Créer mon restaurant',
              icon: Icons.storefront_outlined,
              onPressed: _submitting ? null : _submit,
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Essai gratuit de 30 jours, sans carte bancaire.',
                style: TextStyle(fontSize: 12, color: TchopColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _slugSuffix() {
    switch (_slugState) {
      case _SlugState.checking:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case _SlugState.available:
        return const Icon(Icons.check_circle, color: TchopColors.success);
      case _SlugState.taken:
        return const Icon(Icons.cancel, color: TchopColors.error);
      case _SlugState.invalid:
        return const Icon(Icons.warning_amber, color: TchopColors.warning);
      case _SlugState.idle:
        return null;
    }
  }

  Widget _slugHint() {
    final style = const TextStyle(fontSize: 13);
    switch (_slugState) {
      case _SlugState.available:
        return const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Disponible ✓', style: TextStyle(fontSize: 13, color: TchopColors.success, fontWeight: FontWeight.w600)),
        );
      case _SlugState.taken:
        return const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Déjà pris — essayez une variante.',
              style: TextStyle(fontSize: 13, color: TchopColors.error)),
        );
      case _SlugState.invalid:
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Lettres minuscules, chiffres et tirets uniquement.',
              style: style.copyWith(color: TchopColors.warning)),
        );
      case _SlugState.checking:
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Vérification…', style: style.copyWith(color: TchopColors.textSecondary)),
        );
      case _SlugState.idle:
        return const SizedBox.shrink();
    }
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.colors,
    required this.selected,
    required this.onSelect,
  });

  final List<String> colors;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final hex in colors)
          GestureDetector(
            onTap: () => onSelect(hex),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _hexColor(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected == hex
                      ? Theme.of(context).colorScheme.primary
                      : TchopColors.border,
                  width: selected == hex ? 3 : 1,
                ),
              ),
              child: selected == hex
                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                  : null,
            ),
          ),
      ],
    );
  }
}

Color _hexColor(String hex) {
  final cleaned = hex.replaceAll('#', '');
  final value = int.tryParse(
    cleaned.length == 6 ? 'FF$cleaned' : cleaned,
    radix: 16,
  );
  return value == null ? TchopColors.defaultPrimary : Color(value);
}
