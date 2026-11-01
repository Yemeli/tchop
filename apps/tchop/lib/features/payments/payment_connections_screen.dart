import 'package:flutter/material.dart';

import '../../core/services_scope.dart';
import '../../core/session/session_context.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import 'payment_providers.dart';
import 'payment_repository.dart';

/// Bring-your-own payment credentials, per workspace (manager flavor).
///
/// Each restaurant connects its OWN MTN MoMo / Orange Money / Wave / card
/// accounts: money settles directly into the restaurant's accounts — the
/// platform never holds funds.
///
/// Security contract (UI side):
///   - owner/manager ONLY (role gate mirrors the membership_rbac pattern;
///     the sync edge function enforces it server-side too);
///   - credential values live in [TextEditingController]s — device memory
///     only — and are cleared the moment the outbox op is enqueued;
///   - the UI only ever displays masked fingerprints ("mtn••••9f2a");
///   - "Tester la connexion" never fakes a success: an unreachable sandbox
///     is labeled "Mode démo — vérification simulée".
class PaymentConnectionsScreen extends StatefulWidget {
  const PaymentConnectionsScreen({super.key, this.repository});

  /// Injected for tests; otherwise built from [ServicesScope].
  final PaymentRepository? repository;

  @override
  State<PaymentConnectionsScreen> createState() =>
      _PaymentConnectionsScreenState();
}

class _PaymentConnectionsScreenState extends State<PaymentConnectionsScreen> {
  List<PaymentCredential>? _credentials;
  String? _error;

  PaymentRepository _repo(BuildContext context) =>
      widget.repository ??
      PaymentRepository(syncEngine: ServicesScope.of(context).syncEngine);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_credentials == null && _error == null) _load();
  }

  Future<void> _load() async {
    final tenantId = SessionScope.of(context, listen: false).tenantId;
    if (tenantId == null) return;
    try {
      final creds = await _repo(context).listCredentials(tenantId);
      if (mounted) setState(() => _credentials = creds);
    } catch (e) {
      if (mounted) setState(() => _error = 'Chargement impossible : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    if (!session.canManageStaff) {
      return Scaffold(
        appBar: AppBar(title: const Text('Comptes de paiement')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Seuls le propriétaire et le gérant peuvent gérer les '
              'comptes de paiement.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Comptes de paiement')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _credentials == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _credentials = null);
                    await _load();
                  },
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Connectez vos propres comptes. Les paiements clients '
                        'arrivent directement sur vos comptes — Tchop ne '
                        'touche jamais votre argent. Vos clés sont chiffrées '
                        'côté serveur avant stockage.',
                        style: TchopTypography.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      for (final provider in paymentProviders)
                        _ProviderCard(
                          provider: provider,
                          credentials: _credentials!
                              .where((c) => c.provider == provider.id)
                              .toList(),
                          onChanged: _load,
                          repo: _repo(context),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.credentials,
    required this.onChanged,
    required this.repo,
  });

  final PaymentProvider provider;
  final List<PaymentCredential> credentials;
  final Future<void> Function() onChanged;
  final PaymentRepository repo;

  Color get _railColor =>
      TchopProviderColors.forProvider(provider.id);

  @override
  Widget build(BuildContext context) {
    final connected = credentials.any((c) => c.isActive);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _railColor.withValues(alpha: 51),
                  child: Text(
                    provider.nameFr.isNotEmpty ? provider.nameFr[0] : '?',
                    style: TextStyle(
                        color: _railColor, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(provider.nameFr,
                          style: TchopTypography.titleMedium),
                      Text(provider.subtitleFr,
                          style: TchopTypography.bodySmall),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    connected ? 'Connecté' : 'Non connecté',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: connected
                      ? TchopColors.success.withValues(alpha: 38)
                      : TchopColors.surfaceMuted,
                ),
              ],
            ),
            for (final cred in credentials) ...[
              const Divider(height: 24),
              _CredentialRow(
                credential: cred,
                onChanged: onChanged,
                repo: repo,
              ),
            ],
            if (provider.fields.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _CredentialFormScreen(
                        provider: provider,
                        repo: repo,
                        rotateOf: null,
                      ),
                    ));
                    await onChanged();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(
                      connected ? 'Ajouter un autre compte' : 'Connecter'),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Les cartes transitent par CinetPay ou Flutterwave : '
                'connectez l’un de ces agrégateurs ci-dessus.',
                style: TchopTypography.bodySmall
                    .copyWith(color: TchopColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CredentialRow extends StatefulWidget {
  const _CredentialRow({
    required this.credential,
    required this.onChanged,
    required this.repo,
  });

  final PaymentCredential credential;
  final Future<void> Function() onChanged;
  final PaymentRepository repo;

  @override
  State<_CredentialRow> createState() => _CredentialRowState();
}

class _CredentialRowState extends State<_CredentialRow> {
  bool _verifying = false;

  String _frDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _verify() async {
    setState(() => _verifying = true);
    final tenantId =
        SessionScope.of(context, listen: false).tenantId ?? '';
    final result = await widget.repo.verifyConnection(
      tenantId: tenantId,
      credentialId: widget.credential.id,
    );
    if (!mounted) return;
    setState(() => _verifying = false);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(result.verified
            ? 'Connexion vérifiée'
            : result.demo
                ? 'Mode démo — vérification simulée'
                : 'Échec de la vérification'),
        content: Text(
          result.verified
              ? (result.detail ??
                  'Le bac à sable du fournisseur a accepté vos clés.')
              : result.demo
                  ? 'Le bac à sable du fournisseur est indisponible ou non '
                      'configuré. Ce test est SIMULÉ : il ne prouve pas que '
                      'vos clés fonctionnent. Vérifiez vos clés dans le '
                      'portail du fournisseur avant d’encaisser.'
                  : 'Le bac à sable a refusé ces clés. Vérifiez-les dans le '
                      'portail du fournisseur.',
        ),
        icon: Icon(
          result.verified
              ? Icons.check_circle
              : result.demo
                  ? Icons.science_outlined
                  : Icons.error_outline,
          color: result.verified
              ? TchopColors.success
              : result.demo
                  ? TchopColors.textSecondary
                  : TchopColors.error,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleActive(bool value) async {
    final tenantId =
        SessionScope.of(context, listen: false).tenantId ?? '';
    if (!value) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Révoquer ce compte ?'),
          content: Text(
            '« ${widget.credential.label} » ne recevra plus de paiements. '
            'La révocation est conservée dans le journal d’audit.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Révoquer'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      await widget.repo.revokeCredentials(
          tenantId: tenantId, credentialId: widget.credential.id);
      await widget.repo.syncNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compte révoqué.')),
        );
      }
    } else {
      // Reactivation = fresh keys (rotation also flips is_active=true).
      final provider = paymentProviderById(widget.credential.provider);
      if (provider == null || !mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _CredentialFormScreen(
          provider: provider,
          repo: widget.repo,
          rotateOf: widget.credential,
        ),
      ));
    }
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cred = widget.credential;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(cred.label,
                        style: TchopTypography.titleMedium),
                  ),
                  const SizedBox(width: 8),
                  if (!cred.isActive)
                    const Chip(
                      label: Text('Révoqué',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Clé : ${cred.keyFingerprint}',
                style: TchopTypography.bodySmall.copyWith(
                  fontFamily: 'monospace',
                  color: TchopColors.textSecondary,
                ),
              ),
              Text(
                'Ajouté le ${_frDate(cred.createdAt.toLocal())}',
                style: TchopTypography.bodySmall
                    .copyWith(color: TchopColors.textSecondary),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Switch(
              value: cred.isActive,
              onChanged: _toggleActive,
            ),
            TextButton(
              onPressed: _verifying ? null : _verify,
              child: _verifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Tester'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Add / rotate credential form. Values live in controllers (device memory
/// only) and are cleared immediately after the outbox op is enqueued —
/// plaintext is NEVER written to the local database.
class _CredentialFormScreen extends StatefulWidget {
  const _CredentialFormScreen({
    required this.provider,
    required this.repo,
    required this.rotateOf,
  });

  final PaymentProvider provider;
  final PaymentRepository repo;
  final PaymentCredential? rotateOf;

  @override
  State<_CredentialFormScreen> createState() => _CredentialFormScreenState();
}

class _CredentialFormScreenState extends State<_CredentialFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(
        text: widget.rotateOf?.label ?? '');
    _controllers = {
      for (final f in widget.provider.fields) f.key: TextEditingController(),
    };
  }

  @override
  void dispose() {
    _labelController.dispose();
    // Wipe plaintext from memory.
    for (final c in _controllers.values) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final tenantId =
        SessionScope.of(context, listen: false).tenantId ?? '';
    final label = _labelController.text.trim();
    final fields = {
      for (final e in _controllers.entries) e.key: e.value.text.trim(),
    };
    try {
      if (widget.rotateOf != null) {
        await widget.repo.rotateCredentials(
          tenantId: tenantId,
          credentialId: widget.rotateOf!.id,
          fields: fields,
        );
      } else {
        await widget.repo.saveCredentials(
          tenantId: tenantId,
          provider: widget.provider.id,
          label: label,
          fields: fields,
        );
      }
      await widget.repo.syncNow();
      // Clear plaintext from memory the moment the op is queued.
      for (final c in _controllers.values) {
        c.clear();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Clés envoyées — chiffrement côté serveur avant stockage.'),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec de l’envoi : $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rotateOf != null
            ? 'Renouveler · ${provider.nameFr}'
            : 'Connecter · ${provider.nameFr}'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.rotateOf == null)
              TextFormField(
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: 'Nom du compte',
                  hintText: 'Ex. MTN MoMo principal',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
            if (widget.rotateOf == null) const SizedBox(height: 16),
            for (final field in provider.fields) ...[
              TextFormField(
                controller: _controllers[field.key],
                obscureText: field.obscure,
                decoration: InputDecoration(labelText: field.labelFr),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 16),
                child: Text(
                  field.helperFr,
                  style: TchopTypography.bodySmall
                      .copyWith(color: TchopColors.textSecondary),
                ),
              ),
            ],
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TchopColors.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Vos clés sont chiffrées côté serveur avant stockage et ne '
                'sont jamais affichées en clair — seul un identifiant masqué '
                '(« ${provider.id.split('_').first}••••9f2a ») sera visible.',
                style: TchopTypography.bodySmall
                    .copyWith(color: TchopColors.textSecondary),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.rotateOf != null
                      ? 'Renouveler les clés'
                      : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
