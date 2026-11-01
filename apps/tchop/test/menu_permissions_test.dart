import 'package:flutter_test/flutter_test.dart';
import 'package:tchop/features/menu/menu_permissions.dart';

void main() {
  group('MenuPermissions', () {
    test('owner has full menu control', () {
      const role = MenuRoles.owner;
      expect(MenuPermissions.canEditItems(role), isTrue);
      expect(MenuPermissions.canEditPrices(role), isTrue);
      expect(MenuPermissions.canPublish(role), isTrue);
      expect(MenuPermissions.canToggle86(role), isTrue);
      expect(MenuPermissions.canReviewApprovals(role), isTrue);
    });

    test('manager has full menu control', () {
      const role = MenuRoles.manager;
      expect(MenuPermissions.canEditItems(role), isTrue);
      expect(MenuPermissions.canEditPrices(role), isTrue);
      expect(MenuPermissions.canPublish(role), isTrue);
      expect(MenuPermissions.canToggle86(role), isTrue);
      expect(MenuPermissions.canReviewApprovals(role), isTrue);
    });

    test('head chef: edits items and 86s, but no prices and no publish', () {
      const role = MenuRoles.headChef;
      expect(MenuPermissions.canEditItems(role), isTrue);
      expect(MenuPermissions.canEditPrices(role), isFalse);
      expect(MenuPermissions.canPublish(role), isFalse);
      expect(MenuPermissions.canToggle86(role), isTrue);
      expect(MenuPermissions.canReviewApprovals(role), isFalse);
      expect(MenuPermissions.canRequest86(role), isFalse);
    });

    test('secretary has no menu rights', () {
      const role = MenuRoles.secretary;
      expect(MenuPermissions.canEditItems(role), isFalse);
      expect(MenuPermissions.canEditPrices(role), isFalse);
      expect(MenuPermissions.canPublish(role), isFalse);
      expect(MenuPermissions.canToggle86(role), isFalse);
      expect(MenuPermissions.canReviewApprovals(role), isFalse);
      expect(MenuPermissions.canRequest86(role), isFalse);
    });

    test('kitchen staff cannot toggle directly but can request an 86', () {
      const role = MenuRoles.kitchen;
      expect(MenuPermissions.canEditItems(role), isFalse);
      expect(MenuPermissions.canEditPrices(role), isFalse);
      expect(MenuPermissions.canPublish(role), isFalse);
      expect(MenuPermissions.canToggle86(role), isFalse);
      expect(MenuPermissions.canReviewApprovals(role), isFalse);
      expect(MenuPermissions.canRequest86(role), isTrue);
    });

    test('driver has no menu rights', () {
      const role = MenuRoles.driver;
      expect(MenuPermissions.canEditItems(role), isFalse);
      expect(MenuPermissions.canEditPrices(role), isFalse);
      expect(MenuPermissions.canPublish(role), isFalse);
      expect(MenuPermissions.canToggle86(role), isFalse);
      expect(MenuPermissions.canReviewApprovals(role), isFalse);
      expect(MenuPermissions.canRequest86(role), isFalse);
    });

    test('null and unknown roles get nothing', () {
      for (final role in <String?>[null, '', 'superadmin', 'OWNER']) {
        expect(MenuPermissions.canEditItems(role), isFalse,
            reason: 'canEditItems($role)');
        expect(MenuPermissions.canEditPrices(role), isFalse,
            reason: 'canEditPrices($role)');
        expect(MenuPermissions.canPublish(role), isFalse,
            reason: 'canPublish($role)');
        expect(MenuPermissions.canToggle86(role), isFalse,
            reason: 'canToggle86($role)');
        expect(MenuPermissions.canReviewApprovals(role), isFalse,
            reason: 'canReviewApprovals($role)');
        expect(MenuPermissions.canRequest86(role), isFalse,
            reason: 'canRequest86($role)');
      }
    });
  });
}
