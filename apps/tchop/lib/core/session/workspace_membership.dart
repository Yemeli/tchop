/// A restaurant workspace the signed-in user belongs to.
///
/// Pure Dart (no Flutter import) so the mapping + auto-select rules can be
/// unit-tested without the SDK. [SessionContext] owns the live list; this
/// file owns the shape and the pure rules.
library;

/// One row of the user's `memberships` (joined with `tenants`).
class WorkspaceMembership {
  const WorkspaceMembership({
    required this.id,
    required this.tenantId,
    required this.tenantName,
    required this.role,
  });

  final String id;
  final String tenantId;
  final String tenantName;
  final String role;

  /// Parses a Supabase PostgREST row from:
  /// `memberships.select('id, tenant_id, role, tenants(id, name)')`.
  ///
  /// The joined `tenants` payload may arrive as a Map (single FK join) or a
  /// one-element List depending on the PostgREST embedding; both are
  /// handled. Missing data degrades to safe defaults instead of throwing.
  factory WorkspaceMembership.fromSupabaseRow(Map<String, dynamic> row) {
    final tenant = row['tenants'];
    String name = '';
    if (tenant is Map) {
      name = tenant['name'] as String? ?? '';
    } else if (tenant is List && tenant.isNotEmpty && tenant.first is Map) {
      name = (tenant.first as Map)['name'] as String? ?? '';
    }
    if (name.isEmpty) {
      name = row['tenant_name'] as String? ?? 'Restaurant';
    }
    return WorkspaceMembership(
      id: row['id'] as String? ?? '',
      tenantId: row['tenant_id'] as String? ?? '',
      tenantName: name,
      role: row['role'] as String? ?? 'kitchen',
    );
  }

  /// The `{id, name, role}` map shape exposed by `SessionContext.workspaces`.
  Map<String, String> toWorkspacesEntry() =>
      {'id': tenantId, 'name': tenantName, 'role': role};
}

/// Auto-select rule after sign-in: when the user belongs to exactly one
/// workspace, return its tenant id so the app can skip the picker.
/// Zero or several workspaces → null (onboarding / picker decides).
String? pickDefaultWorkspaceId(List<WorkspaceMembership> memberships) =>
    memberships.length == 1 ? memberships.first.tenantId : null;
