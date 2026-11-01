import 'package:flutter_test/flutter_test.dart';
import 'package:tchop/core/session/roles.dart';
import 'package:tchop/core/session/workspace_membership.dart';

/// Pure-Dart tests for the session layer's role rules and membership
/// mapping — the logic [SessionContext] relies on for invites, the
/// workspace picker and the auto-select rule.
/// Run: `flutter test test/session_context_test.dart`
void main() {
  group('canInviteRole', () {
    test('owner may invite every role', () {
      for (final target in tchopRoles) {
        expect(canInviteRole('owner', target), isTrue,
            reason: 'owner → $target');
      }
    });

    test('manager may invite everyone except owner', () {
      for (final target in tchopRoles) {
        expect(canInviteRole('manager', target), target != 'owner',
            reason: 'manager → $target');
      }
    });

    test('head_chef, secretary, kitchen and driver may invite nobody', () {
      for (final inviter in ['head_chef', 'secretary', 'kitchen', 'driver']) {
        for (final target in tchopRoles) {
          expect(canInviteRole(inviter, target), isFalse,
              reason: '$inviter → $target');
        }
      }
    });

    test('fails closed on unknown roles', () {
      expect(canInviteRole('owner', 'superadmin'), isFalse);
      expect(canInviteRole('superadmin', 'driver'), isFalse);
      expect(canInviteRole('', 'driver'), isFalse);
      expect(canInviteRole('owner', ''), isFalse);
    });
  });

  group('invitableRoles', () {
    test('owner sees all six roles', () {
      expect(invitableRoles('owner'), hasLength(6));
    });

    test('manager dropdown excludes owner', () {
      final roles = invitableRoles('manager');
      expect(roles, isNot(contains('owner')));
      expect(roles, hasLength(5));
    });

    test('kitchen staff get an empty dropdown', () {
      expect(invitableRoles('kitchen'), isEmpty);
    });
  });

  group('roleLabelFr', () {
    test('every role has a French label', () {
      const expected = {
        'owner': 'Propriétaire',
        'manager': 'Gérant',
        'head_chef': 'Chef cuisinier',
        'secretary': 'Secrétaire',
        'kitchen': 'Cuisine',
        'driver': 'Livreur',
      };
      expected.forEach((role, label) {
        expect(roleLabelFr(role), label);
      });
    });

    test('unknown role falls back to the raw string', () {
      expect(roleLabelFr('mystery'), 'mystery');
    });
  });

  group('roleRank', () {
    test('orders owner above manager above staff', () {
      expect(roleRank('owner'), greaterThan(roleRank('manager')));
      expect(roleRank('manager'), greaterThan(roleRank('head_chef')));
      expect(roleRank('head_chef'), greaterThan(roleRank('kitchen')));
    });

    test('unknown roles rank below everything', () {
      expect(roleRank('superadmin'), -1);
    });
  });

  group('WorkspaceMembership.fromSupabaseRow', () {
    test('parses a row with an embedded tenant map', () {
      final m = WorkspaceMembership.fromSupabaseRow({
        'id': 'm-1',
        'tenant_id': 't-1',
        'role': 'owner',
        'tenants': {'id': 't-1', 'name': 'Le Baobab Gourmand'},
      });
      expect(m.id, 'm-1');
      expect(m.tenantId, 't-1');
      expect(m.tenantName, 'Le Baobab Gourmand');
      expect(m.role, 'owner');
    });

    test('parses a row with an embedded tenant list', () {
      final m = WorkspaceMembership.fromSupabaseRow({
        'id': 'm-2',
        'tenant_id': 't-2',
        'role': 'driver',
        'tenants': [
          {'id': 't-2', 'name': 'Ocean Grill Kribi'}
        ],
      });
      expect(m.tenantName, 'Ocean Grill Kribi');
    });

    test('degrades gracefully on missing data', () {
      final m = WorkspaceMembership.fromSupabaseRow({});
      expect(m.id, isEmpty);
      expect(m.tenantId, isEmpty);
      expect(m.tenantName, 'Restaurant');
      expect(m.role, 'kitchen');
    });

    test('toWorkspacesEntry matches the SessionContext contract', () {
      const m = WorkspaceMembership(
        id: 'm-1',
        tenantId: 't-1',
        tenantName: 'Le Baobab',
        role: 'manager',
      );
      expect(
        m.toWorkspacesEntry(),
        {'id': 't-1', 'name': 'Le Baobab', 'role': 'manager'},
      );
    });
  });

  group('pickDefaultWorkspaceId', () {
    const one = [
      WorkspaceMembership(
          id: 'm-1', tenantId: 't-1', tenantName: 'A', role: 'owner'),
    ];
    const two = [
      WorkspaceMembership(
          id: 'm-1', tenantId: 't-1', tenantName: 'A', role: 'owner'),
      WorkspaceMembership(
          id: 'm-2', tenantId: 't-2', tenantName: 'B', role: 'manager'),
    ];

    test('auto-selects when exactly one workspace', () {
      expect(pickDefaultWorkspaceId(one), 't-1');
    });

    test('returns null for zero or several workspaces', () {
      expect(pickDefaultWorkspaceId([]), isNull);
      expect(pickDefaultWorkspaceId(two), isNull);
    });
  });
}
