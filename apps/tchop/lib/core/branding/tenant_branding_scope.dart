import 'package:flutter/widgets.dart';

import 'tenant_brand.dart';
import 'tenant_branding_controller.dart';

/// Exposes the [TenantBrandingController] (and the current [TenantBrand])
/// to the widget tree without adding a state-management dependency.
///
/// Usage:
/// ```dart
/// final brand = TenantBrandingScope.of(context).brand;
/// ```
class TenantBrandingScope extends InheritedNotifier<TenantBrandingController> {
  const TenantBrandingScope({
    super.key,
    required TenantBrandingController branding,
    required super.child,
  }) : super(notifier: branding);

  static TenantBrand of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<TenantBrandingScope>()
        : context
            .getElementForInheritedWidgetOfExactType<TenantBrandingScope>()
            ?.widget as TenantBrandingScope?;
    assert(scope != null, 'TenantBrandingScope not found in widget tree');
    return scope!.notifier!.brand;
  }

  static TenantBrandingController controllerOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<TenantBrandingScope>();
    assert(scope != null, 'TenantBrandingScope not found in widget tree');
    return scope!.notifier!;
  }
}
