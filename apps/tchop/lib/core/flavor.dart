import 'package:flutter/material.dart';

import '../features/customer/customer_shell.dart';
import '../features/driver/driver_deliveries_screen.dart';
import '../features/kitchen/kitchen_shell.dart';
import '../features/manager/manager_dashboard_screen.dart';

/// Build flavor of the app. One codebase, four role-specific binaries.
///
/// Android: selected via `productFlavors` in `android/app/build.gradle.kts`
///   e.g. `flutter run --flavor customer -t lib/main_customer.dart`
/// iOS: flavors are mapped to Xcode schemes (see README) that pass
///   `--dart-define=FLAVOR=<flavor>`; [resolveFlavor] reads it in `main.dart`.
enum AppFlavor { customer, driver, kitchen, manager }

/// Reads the flavor passed via `--dart-define=FLAVOR=<name>`.
/// Falls back to [AppFlavor.customer] when absent or unknown.
AppFlavor resolveFlavor() {
  final raw =
      String.fromEnvironment('FLAVOR', defaultValue: 'customer').toLowerCase();
  return AppFlavor.values.firstWhere(
    (f) => f.name == raw,
    orElse: () => AppFlavor.customer,
  );
}

extension AppFlavorX on AppFlavor {
  /// Human-readable label used for the OS app name / store listing.
  /// NOTE: "Tchop" is a working codename — rename before public launch.
  String get appLabel => switch (this) {
        AppFlavor.customer => 'Tchop',
        AppFlavor.driver => 'Tchop Driver',
        AppFlavor.kitchen => 'Tchop Kitchen',
        AppFlavor.manager => 'Tchop Manager',
      };

  /// Root screen for this flavor. Each role gets its own home.
  ///
  /// Customer and kitchen use the adaptive shell (bottom bar on phones,
  /// navigation rail on tablet/desktop); driver and manager shells live
  /// inside their own home screens.
  Widget get homeScreen => switch (this) {
        AppFlavor.customer => const CustomerShell(),
        AppFlavor.driver => const DriverDeliveriesScreen(),
        AppFlavor.kitchen => const KitchenShell(),
        AppFlavor.manager => const ManagerDashboardScreen(),
      };
}
