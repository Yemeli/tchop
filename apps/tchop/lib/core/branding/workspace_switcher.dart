import 'package:flutter/material.dart';

import '../../core/session/roles.dart';
import '../../core/session/session_context.dart';
import '../../core/session/workspace_membership.dart';
import '../../data/supabase_client.dart';
import '../../design_system/brand_widgets.dart';
import '../../design_system/tchop_colors.dart';
import '../../features/onboarding/create_workspace_screen.dart';
import 'sample_brands.dart';
import 'tenant_branding_scope.dart';

/// Lets a signed-in user hop between their REAL workspaces (memberships).
///
/// Each tap calls [SessionContext.switchTenant], which reloads the
/// memberships and re-themes the whole app via
/// [TenantBrandingController.switchToWorkspace].
///
/// The bundled sample workspaces are kept ONLY as a fallback when the
/// backend is unconfigured (offline demo mode).
Future<void> showWorkspaceSwitcher(BuildContext context) {
  if (!TchopSupabase.isConfigured) {
    return _showDemoSwitcher(context);
  }
  return _showRealSwitcher(context);
}

Future<void> _showRealSwitcher(BuildContext context) {
  final session = SessionScope.of(context, listen: false);
  final memberships = session.memberships;
  final activeId = session.tenantId;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Mes restaurants',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            if (memberships.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Aucun restaurant pour le moment.',
                  style: TextStyle(color: TchopColors.textSecondary),
                ),
              ),
            for (final m in memberships)
              _WorkspaceTile(
                membership: m,
                active: m.tenantId == activeId,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await session.switchTenant(m.tenantId);
                  } catch (e) {
                    if (sheetContext.mounted) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        SnackBar(content: Text('Changement impossible : $e')),
                      );
                    }
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.add_business_outlined),
              title: const Text('Créer un nouveau restaurant'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CreateWorkspaceScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.membership,
    required this.active,
    required this.onTap,
  });

  final WorkspaceMembership membership;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: BrandLogo(
        brandName: membership.tenantName,
        background: TenantBrandingScope.of(context, listen: false).primary,
      ),
      title: Text(membership.tenantName),
      subtitle: Text(roleLabelFr(membership.role)),
      trailing: active
          ? const Icon(Icons.check_circle, color: TchopColors.success)
          : null,
      onTap: onTap,
    );
  }
}

/// Demo fallback: backend unconfigured → the bundled sample brands.
Future<void> _showDemoSwitcher(BuildContext context) {
  final controller = TenantBrandingScope.controllerOf(context);
  final activeId = TenantBrandingScope.of(context, listen: false).restaurantId;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Mes restaurants (démo)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            for (final workspace in sampleWorkspaces)
              ListTile(
                leading: BrandLogo(
                  brandName: workspace.name,
                  logoUrl: workspace.logoUrl,
                  background: workspace.primary,
                ),
                title: Text(workspace.name),
                subtitle:
                    workspace.tagline == null ? null : Text(workspace.tagline!),
                trailing: workspace.restaurantId == activeId
                    ? const Icon(Icons.check_circle, color: TchopColors.success)
                    : null,
                onTap: () async {
                  await controller.switchWorkspace(workspace);
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}
