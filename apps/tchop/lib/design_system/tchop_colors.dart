import 'package:flutter/material.dart';

/// Fixed design tokens for the "dark premium + warm appetite" language.
///
/// These never change per tenant. Tenants only control *brand* colors
/// ([TenantBrand.primary]/secondary/accent); functional colors below stay
/// constant so a tenant theme can never break usability or accessibility.
abstract final class TchopColors {
  // Surfaces — near-black grounds that make food imagery pop.
  static const Color background = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFF161616);
  static const Color surfaceMuted = Color(0xFF1F1F1F);
  static const Color border = Color(0xFF2A2A2A);

  // Text on dark grounds.
  static const Color textPrimary = Color(0xFFF5F1EA);
  static const Color textSecondary = Color(0xFFA8A29A);

  // Functional — fixed, never tenant-controlled.
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFFB340);
  static const Color error = Color(0xFFFF5A5A);
  static const Color info = Color(0xFF4DA3FF);

  // Default brand seed (used before a workspace brand loads).
  static const Color defaultPrimary = Color(0xFFE8641B); // warm appetite orange
  static const Color defaultAccent = Color(0xFFD4AF37); // gold
}

/// Corner radii — one scale for the whole app.
abstract final class TchopRadius {
  static const double card = 16;
  static const double cardLarge = 20;
  static const double button = 14;
  static const double sheet = 20;
  static const double chip = 999;
  static const double small = 8;
  static const double tiny = 4;
}

/// Spacing scale — prefer these over ad-hoc numbers.
abstract final class TchopSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double section = 32;
}

/// Fixed brand colors of the payment providers shown in the connections
/// screen. These are the providers' own identities (MTN yellow, Orange
/// orange…), not tenant branding — hence fixed tokens, not theme colors.
abstract final class TchopProviderColors {
  static const Color mtnMomo = Color(0xFFFFCC00);
  static const Color orangeMoney = Color(0xFFFF7900);
  static const Color wave = Color(0xFF1DC8FF);
  static const Color cinetpay = Color(0xFF7C3AED);
  static const Color flutterwave = Color(0xFFF5A623);

  /// Provider id (see `PaymentProvider.id`) → rail color.
  static Color forProvider(String providerId) => switch (providerId) {
        'mtn_momo' => mtnMomo,
        'orange_money' => orangeMoney,
        'wave' => wave,
        'cinetpay' => cinetpay,
        'flutterwave' => flutterwave,
        _ => TchopColors.textSecondary,
      };
}
