/// Menu-studio role-based access control.
///
/// Roles come from the workspace membership (see `SessionContext.role`).
/// Pure Dart — no Flutter dependency — so the rules stay unit-testable and
/// identical on every flavor.
///
/// Product spec:
/// - Owner / Manager: full menu control + publish.
/// - Head Chef: edits items/recipes, NO prices, CAN use the 86 toggle.
/// - Secretary / Kitchen / Driver: no menu rights (kitchen staff *request*
///   an 86 through the approvals inbox instead of toggling directly).
abstract final class MenuRoles {
  static const String owner = 'owner';
  static const String manager = 'manager';
  static const String headChef = 'head_chef';
  static const String secretary = 'secretary';
  static const String kitchen = 'kitchen';
  static const String driver = 'driver';

  static const List<String> all = [
    owner,
    manager,
    headChef,
    secretary,
    kitchen,
    driver,
  ];
}

abstract final class MenuPermissions {
  /// Edit item name / description / photo / tags / categories / dayparts.
  static bool canEditItems(String? role) =>
      role == MenuRoles.owner ||
      role == MenuRoles.manager ||
      role == MenuRoles.headChef;

  /// Edit prices (FCFA). Head chef is explicitly excluded.
  static bool canEditPrices(String? role) =>
      role == MenuRoles.owner || role == MenuRoles.manager;

  /// Publish a new immutable menu snapshot.
  static bool canPublish(String? role) =>
      role == MenuRoles.owner || role == MenuRoles.manager;

  /// Flip the 86 (sold-out) toggle directly. Head chef can; kitchen staff
  /// cannot — they file a `menu/request_86` for manager approval instead.
  static bool canToggle86(String? role) =>
      role == MenuRoles.owner ||
      role == MenuRoles.manager ||
      role == MenuRoles.headChef;

  /// Review the approvals inbox (price changes >10%, 86 requests).
  static bool canReviewApprovals(String? role) =>
      role == MenuRoles.owner || role == MenuRoles.manager;

  /// File an 86 request (kitchen role). Not a "menu right" per se — a
  /// request routed to the approvals inbox.
  static bool canRequest86(String? role) => role == MenuRoles.kitchen;
}
