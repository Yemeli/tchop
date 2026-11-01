import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/branding/tenant_branding_scope.dart';
import '../../core/session/auth_repository.dart';
import '../../core/session/phone.dart';
import '../../core/session/session_context.dart';
import '../../data/supabase_client.dart';
import '../../design_system/brand_widgets.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import 'otp_verification_screen.dart';

/// Phone + OTP sign-in (Supabase Auth, MTN/Orange SMS).
///
/// French-first: "Se connecter", "Entrez le numéro WhatsApp / mobile".
/// The number is normalized to E.164 (default country code +237) before the
/// OTP request. When the backend is unconfigured the screen degrades to the
/// offline demo entry point instead of a dead form.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _phoneController = TextEditingController();
  final _auth = AuthRepository();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final e164 = normalizeCmPhone(_phoneController.text);
    if (e164 == null) {
      setState(() => _error =
          'Numéro invalide. Entrez un numéro mobile camerounais (ex. 6 12 34 56 78).');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _auth.requestOtp(e164);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(phone: e164),
        ),
      );
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } on StateError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = TenantBrandingScope.of(context);
    final configured = TchopSupabase.isConfigured;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: BrandLogo(
                  brandName: brand.name,
                  logoUrl: brand.logoUrl,
                  background: brand.primary,
                  radius: 44,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Se connecter',
                  style: TchopTypography.displayMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'Entrez le numéro WhatsApp / mobile',
                  style: TchopTypography.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: TchopColors.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('+237',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9\s.\-]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Numéro mobile',
                        hintText: '6 12 34 56 78',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _requestCode(),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 16),
              BrandButton(
                label: _sending ? 'Envoi en cours…' : 'Recevoir le code SMS',
                icon: Icons.sms_outlined,
                onPressed: (_sending || !configured) ? null : _requestCode,
              ),
              if (!configured) ...[
                const SizedBox(height: 16),
                const _DemoBanner(),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Explorer la démo hors-ligne'),
                  onPressed: () =>
                      SessionScope.of(context, listen: false).signInDemo(),
                ),
              ],
              const Spacer(),
              const Center(
                child: Text(
                  'En vous connectant, vous acceptez les conditions d’utilisation de Tchop.',
                  style: TextStyle(fontSize: 12, color: TchopColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TchopColors.error.withValues(alpha: 31),
        borderRadius: BorderRadius.circular(TchopRadius.small),
        border:
            Border.all(color: TchopColors.error.withValues(alpha: 102)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: TchopColors.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style:
                    const TextStyle(color: TchopColors.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TchopColors.warning.withValues(alpha: 31),
        borderRadius: BorderRadius.circular(TchopRadius.small),
        border: Border.all(
            color: TchopColors.warning.withValues(alpha: 102)),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 20, color: TchopColors.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Mode démo : le backend n’est pas configuré sur cet appareil. '
              'La connexion par SMS est désactivée.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
