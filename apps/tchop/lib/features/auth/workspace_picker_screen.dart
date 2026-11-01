import 'package:flutter/material.dart';

import '../../core/branding/tenant_branding_scope.dart';
import '../../core/session/roles.dart';
import '../../core/session/session_context.dart';
import '../../design_system/brand_widgets.dart';
import '../../design_system/tchop_typography.dart';
import '../onboarding/create_workspace_screen.dart';

/// Shown after sign-in when the user belongs to several workspaces (or when
/// the auto-select did not apply). Tapping a workspace switches to it and
/// re-themes the app; the route gate then shows the flavor's home screen.
class WorkspacePickerScreen extends StatelessWidget {
  const WorkspacePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final workspaces = session.workspaces;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes restaurants'),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => session.signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choisissez le restaurant à gérer',
            style: TchopTypography.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text(
            'Chaque restaurant a son propre espace, son menu et ses paiements.',
            style: TchopTypography.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (final ws in workspaces)
            Card(
              child: ListTile(
                leading: BrandLogo(
                  brandName: ws['name'] ?? '?',
                  background:
                      TenantBrandingScope.of(context, listen: false).primary,
                ),
                title: Text(ws['name'] ?? 'Restaurant'),
                subtitle: Text(roleLabelFr(ws['role'] ?? '')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => session.switchTenant(ws['id']!),
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Créer un nouveau restaurant'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CreateWorkspaceScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
