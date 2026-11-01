/// Staff roles for the Tchop workspace model.
///
/// Pure Dart (no Flutter import) so it can be unit-tested without the SDK.
///
/// Roles, weakest → strongest:
/// `driver`, `kitchen`, `secretary`, `head_chef`, `manager`, `owner`.
library;

/// All roles recognized by the platform, in ascending privilege order.
const List<String> tchopRoles = <String>[
  'driver',
  'kitchen',
  'secretary',
  'head_chef',
  'manager',
  'owner',
];

/// French labels shown in role pickers and workspace lists.
const Map<String, String> roleLabelsFr = <String, String>{
  'owner': 'Propriétaire',
  'manager': 'Gérant',
  'head_chef': 'Chef cuisinier',
  'secretary': 'Secrétaire',
  'kitchen': 'Cuisine',
  'driver': 'Livreur',
};

/// French label for [role]; falls back to the raw role string.
String roleLabelFr(String role) => roleLabelsFr[role] ?? role;

/// Numeric privilege rank. Unknown roles rank below everything (-1) so they
/// can never accidentally gain rights.
int roleRank(String role) {
  switch (role) {
    case 'driver':
      return 0;
    case 'kitchen':
      return 1;
    case 'secretary':
      return 2;
    case 'head_chef':
      return 3;
    case 'manager':
      return 4;
    case 'owner':
      return 5;
    default:
      return -1;
  }
}

/// Whether [inviterRole] may invite someone as [targetRole].
///
/// - `owner` may invite any role (including another owner);
/// - `manager` may invite any role except `owner`;
/// - every other role may invite nobody.
///
/// Unknown roles on either side always return false (fail closed).
bool canInviteRole(String inviterRole, String targetRole) {
  if (!tchopRoles.contains(targetRole)) return false;
  switch (inviterRole) {
    case 'owner':
      return true;
    case 'manager':
      return targetRole != 'owner';
    default:
      return false;
  }
}

/// The roles [inviterRole] is allowed to invite — drives the invite-screen
/// dropdown so disallowed roles are never even offered.
List<String> invitableRoles(String inviterRole) =>
    tchopRoles.where((role) => canInviteRole(inviterRole, role)).toList();
