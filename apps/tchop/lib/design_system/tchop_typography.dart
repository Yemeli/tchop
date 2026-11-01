import 'package:flutter/material.dart';

import 'tchop_colors.dart';

/// Typography system: expressive display serif + clean grotesque body.
///
/// Font files are NOT bundled yet — add them under `assets/fonts/` and
/// register in `pubspec.yaml`, or add the `google_fonts` package and swap
/// these families for `GoogleFonts.frauncesTextTheme(...)`.
/// The `fontFamily` strings below compile fine either way.
abstract final class TchopTypography {
  static const String displayFont = 'Fraunces';
  static const String bodyFont = 'Plus Jakarta Sans';

  static const TextStyle displayLarge = TextStyle(
    fontFamily: displayFont,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: TchopColors.textPrimary,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: displayFont,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.25,
    color: TchopColors.textPrimary,
  );

  static const TextStyle titleLarge = TextStyle(
    fontFamily: bodyFont,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.25,
    color: TchopColors.textPrimary,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: TchopColors.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: TchopColors.textSecondary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: TchopColors.textSecondary,
  );

  /// Prices always use tabular figures so columns align.
  static const TextStyle price = TextStyle(
    fontFamily: bodyFont,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
    color: TchopColors.textPrimary,
  );
}
