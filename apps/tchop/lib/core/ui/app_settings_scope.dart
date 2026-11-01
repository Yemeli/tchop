import 'package:flutter/widgets.dart';

import '../settings/app_settings.dart';

/// Exposes the device-level [AppSettingsController] to the widget tree.
///
/// Created once in `bootstrap.dart` (settings are loaded *before* the
/// first frame so the customer onboarding gate reads the persisted flag).
/// The bootstrap wraps the tree in a `ListenableBuilder` on the controller,
/// so any toggle rebuilds the whole app and every
/// `AppSettingsScope.of(context).value` read stays fresh — screens honor
/// reduced-motion / lite-mode without their own listeners (the kitchen
/// board is the exception: it recreates its tick timer on change).
class AppSettingsScope extends InheritedWidget {
  const AppSettingsScope({
    super.key,
    required this.settings,
    required super.child,
  });

  final AppSettingsController settings;

  static AppSettingsController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'AppSettingsScope not found above this widget.');
    return scope!.settings;
  }

  static AppSettingsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSettingsScope>()?.settings;

  @override
  bool updateShouldNotify(AppSettingsScope oldWidget) =>
      oldWidget.settings.value != settings.value;
}
