import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../design_system/tchop_colors.dart';
import '../../core/session/phone.dart';
import '../../core/session/roles.dart';
import '../../core/session/session_context.dart';
import '../../design_system/brand_widgets.dart';
import '../../design_system/tchop_typography.dart';

/// Invites staff by phone number (owner / manager only).
///
/// The invite is a membership row with `user_id = null` and `invited_phone`
/// set, enqueued through the offline-capable outbox op `membership/invite`.
/// The invited person sees the workspace after their first OTP sign-in, when
/// `claim_invited_memberships()` links the invite to their user id by phone.
class InviteStaffScreen extends StatefulWidget {
  const InviteStaffScreen({super.key});

  @override
  State<InviteStaffScreen> createState() => _InviteStaffScreenState();
}

class _InviteStaffScreenState extends State<InviteStaffScreen> {
  static const _uuid = Uuid();

  final _phoneController = TextEditingController();
  String _role = 'kitchen';
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    final session = SessionScope.of(context, listen: false);
    final tenantId = session.tenantId;
    final inviterRole = session.role;
    if (tenantId == null || inviterRole == null) {
      setState(() => _error = 'Aucun restaurant actif.');
      return;
    }
    final phone = normalizeCmPhone(_phoneController.text);
    if (phone == null) {
      setState(() => _error =
          'Numéro invalide. Entrez un numéro mobile camerounais (ex. 6 12 34 56 78).');
      return;
    }
    final allowed = invitableRoles(inviterRole);
    final role = allowed.contains(_role) ? _role : allowed.first;
    if (!canInviteRole(inviterRole, role)) {
      setState(() => _error =
          'Vous ne pouvez pas inviter avec le rôle « ${roleLabelFr(role)} ».');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await session.enqueueMutation(
        tenantId: tenantId,
        op: 'invite',
        entity: 'membership',
        entityId: _uuid.v4(),
        payload: {'phone': phone, 'role': role},
      );
      if (!mounted) return;
      _phoneController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invitation enregistrée pour ${prettyCmPhone(phone)} '
            '(${roleLabelFr(role)}). Elle sera synchronisée automatiquement.',
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = 'L’invitation a échoué : $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    if (!session.canManageStaff) {
      return Scaffold(
        appBar: AppBar(title: const Text('Inviter du personnel')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Seuls le propriétaire et le gérant peuvent inviter du personnel.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // The dropdown's value must be one of its items; fall back to the
    // first invitable role without mutating state during build.
    final allowedRoles = invitableRoles(session.role ?? '');
    final effectiveRole = allowedRoles.contains(_role)
        ? _role
        : (allowedRoles.isEmpty ? 'kitchen' : allowedRoles.first);

    return Scaffold(
      appBar: AppBar(title: const Text('Inviter du personnel')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Numéro mobile / WhatsApp',
                  style: TchopTypography.titleMedium),
              const SizedBox(height: 8),
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
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Rôle', style: TchopTypography.titleMedium),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: effectiveRole,
                decoration:
                    const InputDecoration(border: OutlineInputBorder()),
                items: [
                  for (final r in allowedRoles)
                    DropdownMenuItem(
                        value: r, child: Text(roleLabelFr(r))),
                ],
                onChanged: (v) =>
                    setState(() => _role = v ?? _role),
              ),
              const SizedBox(height: 12),
              const Text(
                'La personne invitée verra ce restaurant après sa première '
                'connexion avec ce numéro.',
                style: TextStyle(fontSize: 13, color: TchopColors.textSecondary),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13)),
              ],
              const SizedBox(height: 16),
              BrandButton(
                label: _sending ? 'Envoi…' : 'Envoyer l’invitation',
                icon: Icons.person_add_outlined,
                onPressed: _sending ? null : _invite,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
