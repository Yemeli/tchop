import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/session/auth_repository.dart';
import '../../core/session/phone.dart';
import '../../core/session/session_context.dart';
import '../../design_system/brand_widgets.dart';
import '../../design_system/tchop_typography.dart';

/// Second step of phone sign-in: the 6-digit SMS code.
///
/// On success the Supabase session is established (the auth-state listener
/// in [SessionContext] loads memberships); we also trigger an explicit
/// refresh so the route gate reacts immediately, then pop back to the gate.
class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key, required this.phone});

  /// Normalized E.164 number the code was sent to.
  final String phone;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _codeController = TextEditingController();
  final _auth = AuthRepository();
  bool _verifying = false;
  bool _resending = false;
  String? _error;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _codeController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 30);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendCooldown = _resendCooldown - 1);
      if (_resendCooldown <= 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Entrez le code à 6 chiffres reçu par SMS.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await _auth.verifyOtp(phone: widget.phone, token: code);
      if (!mounted) return;
      // Make the gate react now; the auth-state listener does the same as
      // a backstop.
      await SessionScope.of(context, listen: false).refreshMemberships();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await _auth.requestOtp(widget.phone);
      _startResendCooldown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nouveau code envoyé par SMS.')),
        );
      }
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vérification')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                'Entrez le code reçu par SMS',
                style: TchopTypography.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Envoyé au ${prettyCmPhone(widget.phone)}',
                style: TchopTypography.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  letterSpacing: 12,
                  fontWeight: FontWeight.w700,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  hintText: '––––––',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _verify(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13),
                    textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),
              BrandButton(
                label: _verifying ? 'Vérification…' : 'Vérifier',
                icon: Icons.check_circle_outline,
                onPressed: _verifying ? null : _verify,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed:
                    (_resending || _resendCooldown > 0) ? null : _resend,
                child: Text(
                  _resendCooldown > 0
                      ? 'Renvoyer le code (${_resendCooldown}s)'
                      : _resending
                          ? 'Envoi…'
                          : 'Renvoyer le code',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
