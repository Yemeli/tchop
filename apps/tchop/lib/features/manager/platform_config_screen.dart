import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_config.dart';
import '../../core/session/platform_admin.dart';
import '../../core/ui/state_views.dart';
import '../../data/supabase_client.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import '../dispatch/mqtt_dispatch_service.dart';

/// Super-admin **Configuration** screen — paste-and-go platform keys.
///
/// Gated EXACTLY like [SuperAdminScreen]: [PlatformAdmin.isAdmin]
/// (fail-closed) before anything renders. Sections:
///
/// - **Backend Supabase** — URL + clé anon, "Tester la connexion" runs a
///   real lightweight query; saving re-creates the backend client live.
/// - **Google Maps** — clé API. Honest note: the native map view reads the
///   key from the platform manifest AT BUILD TIME, so a pasted key only
///   lights up the in-app map after a rebuild (it works immediately for
///   HTTP-based Maps calls).
/// - **MQTT** — URL du broker; "Tester la connexion" attempts a real
///   handshake with a 10 s timeout. Empty = SIMULATION mode.
///
/// Values are masked (`••••9f2a`) and stored in the OS secure storage
/// (Keychain / Keystore) — never in the database, never in logs.
class PlatformConfigScreen extends StatelessWidget {
  const PlatformConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: PlatformAdmin.isAdmin(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Configuration')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data != true) {
          return Scaffold(
            appBar: AppBar(title: const Text('Configuration')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Accès réservé à l’administrateur de la plateforme.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return const _ConfigConsole();
      },
    );
  }
}

class _ConfigConsole extends StatefulWidget {
  const _ConfigConsole();

  @override
  State<_ConfigConsole> createState() => _ConfigConsoleState();
}

class _ConfigConsoleState extends State<_ConfigConsole> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration')),
      body: ListenableBuilder(
        listenable: AppConfig.current,
        builder: (context, _) {
          final cfg = AppConfig.current;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const OfflineBanner(),
              const _InfoBanner(
                text: 'Les clés sont stockées chiffrées sur cet appareil. '
                    'Aucun rebuild n’est nécessaire — l’application '
                    'recharge la configuration dès l’enregistrement.',
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Backend Supabase',
                icon: Icons.cloud_outlined,
                children: [
                  _KeyRow(
                    label: 'URL Supabase',
                    masked: cfg.supabaseUrlMasked,
                    source: cfg.supabaseUrlSource,
                    obscure: false,
                    onEdit: () => _editKey(
                      title: 'URL Supabase',
                      hint: 'https://xyzcompany.supabase.co',
                      obscure: false,
                      onSave: (v) => _saveSupabase(url: v),
                    ),
                  ),
                  _KeyRow(
                    label: 'Clé anon Supabase',
                    masked: cfg.supabaseAnonKeyMasked,
                    source: cfg.supabaseAnonKeySource,
                    obscure: true,
                    onEdit: () => _editKey(
                      title: 'Clé anon Supabase',
                      hint: 'eyJhbGciOi…',
                      obscure: true,
                      onSave: (v) => _saveSupabase(anonKey: v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _TestButton(
                    label: 'Tester la connexion',
                    onPressed: _testSupabase,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Après un changement de backend, reconnectez-vous : '
                    'la session précédente ne suit pas.',
                    style: TextStyle(
                        color: TchopColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Google Maps',
                icon: Icons.map_outlined,
                children: [
                  _KeyRow(
                    label: 'Clé API Google Maps',
                    masked: cfg.mapsApiKeyMasked,
                    source: cfg.mapsApiKeySource,
                    obscure: true,
                    onEdit: () => _editKey(
                      title: 'Clé API Google Maps',
                      hint: 'AIza…',
                      obscure: true,
                      onSave: (v) async {
                        await AppConfig.current
                            .updateAndPersist(mapsApiKey: v);
                        _toast('Clé Google Maps enregistrée.');
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  _TestButton(
                    label: 'Vérifier',
                    onPressed: _mapsNote,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Note : la carte native lit la clé au moment du build '
                    '(AndroidManifest). Une clé collée ici est conservée et '
                    'active la carte après rebuild ; elle fonctionne '
                    'immédiatement pour les appels Maps en HTTP.',
                    style: TextStyle(
                        color: TchopColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Broker MQTT (GPS livreurs)',
                icon: Icons.sensors_outlined,
                children: [
                  _KeyRow(
                    label: 'URL du broker',
                    masked: cfg.mqttBrokerUrlMasked,
                    source: cfg.mqttBrokerUrlSource,
                    obscure: false,
                    onEdit: () => _editKey(
                      title: 'URL du broker MQTT',
                      hint: 'wss://broker.emqx.io:8084/mqtt',
                      obscure: false,
                      onSave: (v) async {
                        await AppConfig.current
                            .updateAndPersist(mqttBrokerUrl: v);
                        _toast('URL du broker enregistrée. Les prochaines '
                            'connexions l’utiliseront.');
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  _TestButton(
                    label: 'Tester la connexion',
                    onPressed: _testMqtt,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Vide = mode SIMULATION (positions de démonstration, '
                    'badge « SIMULATION » dans l’app).',
                    style: TextStyle(
                        color: TchopColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Les clés de paiement des restaurants (MTN MoMo, Orange '
                'Money, Wave…) se configurent par restaurant dans '
                'Paiements → Connexions, pas ici.',
                style:
                    TextStyle(color: TchopColors.textSecondary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------
  // Editing
  // ------------------------------------------------------------------

  Future<void> _editKey({
    required String title,
    required String hint,
    required bool obscure,
    required Future<void> Function(String?) onSave,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: obscure,
          enableSuggestions: !obscure,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('__clear__'),
            child: const Text('Effacer',
                style: TextStyle(color: TchopColors.error)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return; // cancelled
    if (result == '__clear__') {
      await onSave('');
      return;
    }
    if (result.trim().isEmpty) return;
    await onSave(result);
  }

  Future<void> _saveSupabase({String? url, String? anonKey}) async {
    await AppConfig.current.updateAndPersist(
      supabaseUrl: url,
      supabaseAnonKey: anonKey,
    );
    final cfg = AppConfig.current;
    if (cfg.supabaseConfigured) {
      await TchopSupabase.reinitialize();
      _toast('Backend enregistré et reconnecté.');
    } else {
      TchopSupabase.dropRuntimeClient();
      _toast('Enregistré. Complétez l’URL et la clé pour activer le backend.');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ------------------------------------------------------------------
  // Connection tests
  // ------------------------------------------------------------------

  Future<void> _testSupabase() async {
    final cfg = AppConfig.current;
    if (!cfg.supabaseConfigured) {
      _showTestResult(
          false, 'Renseignez l’URL et la clé anon avant de tester.');
      return;
    }
    _showTesting('Connexion à Supabase…');
    bool reachable = false;
    String detail;
    try {
      final probe = SupabaseClient(cfg.supabaseUrl, cfg.supabaseAnonKey);
      // Any HTTP response — even 401/403 from RLS — proves the host is
      // reachable. Only network-level failures mean "unreachable".
      await probe
          .from('tenants')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 10));
      reachable = true;
      detail = 'Réponse reçue du backend.';
    } on TimeoutException {
      detail = 'Délai dépassé — l’hôte ne répond pas.';
    } on SocketException {
      detail = 'Hôte injoignable — vérifiez l’URL et la connexion.';
    } on HttpException {
      detail = 'Erreur réseau HTTP — vérifiez l’URL.';
    } catch (e) {
      // PostgrestException (401/403/404…) or any other API-level error:
      // the server answered, so the connection itself works.
      reachable = true;
      detail = 'Backend joignable (réponse API : ${e.runtimeType}).';
    }
    if (mounted) Navigator.of(context).pop(); // close the progress dialog
    _showTestResult(reachable, detail);
  }

  Future<void> _testMqtt() async {
    final url = AppConfig.current.mqttBrokerUrl.trim();
    if (url.isEmpty || url == MqttConfig.defaultBrokerUrl) {
      _showTestResult(false,
          'Aucun broker configuré — l’app reste en mode SIMULATION.');
      return;
    }
    _showTesting('Connexion au broker MQTT…');
    final ok = await MqttConfig.testConnection(url);
    if (mounted) Navigator.of(context).pop();
    _showTestResult(
      ok,
      ok
          ? 'Poignée de main MQTT réussie.'
          : 'Échec — vérifiez l’URL, le port et le TLS (wss://).',
    );
  }

  void _mapsNote() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clé Google Maps'),
        content: const Text(
          'Il n’y a pas de test réseau pour cette clé : la carte native '
          'lit la clé au moment du build (AndroidManifest / AppDelegate). '
          'Une clé collée ici est conservée en sécurité et activera la '
          'carte après rebuild.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }

  void _showTesting(String label) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }

  void _showTestResult(bool ok, String detail) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              ok ? Icons.check_circle : Icons.error,
              color: ok ? TchopColors.success : TchopColors.error,
            ),
            const SizedBox(width: 8),
            Text(ok ? 'Connexion réussie' : 'Échec de connexion'),
          ],
        ),
        content: Text(detail),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Pieces
// ----------------------------------------------------------------------

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TchopColors.info.withValues(alpha: 31),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: TchopColors.info.withValues(alpha: 128)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outlined, color: TchopColors.info, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(title, style: TchopTypography.titleMedium),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({
    required this.label,
    required this.masked,
    required this.source,
    required this.obscure,
    required this.onEdit,
  });
  final String label;
  final String masked;
  final ConfigSource source;
  final bool obscure;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(obscure ? Icons.key_outlined : Icons.link_outlined),
      title: Text(label),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              masked,
              style: TextStyle(fontFamily: 'monospace', fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _SourceChip(source: source),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined),
        tooltip: 'Modifier',
        onPressed: onEdit,
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source});
  final ConfigSource source;

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (source) {
      case ConfigSource.runtime:
        color = TchopColors.success;
      case ConfigSource.build:
        color = TchopColors.info;
      case ConfigSource.none:
        color = TchopColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 38),
        borderRadius: BorderRadius.circular(TchopRadius.chip),
      ),
      child: Text(
        AppConfig.sourceLabelFr(source),
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TestButton extends StatelessWidget {
  const _TestButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.bolt_outlined, size: 18),
        label: Text(label),
      ),
    );
  }
}
