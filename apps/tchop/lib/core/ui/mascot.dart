import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart';

import '../../design_system/tchop_colors.dart';
import 'app_settings_scope.dart';

/// Brand mascot slots — the emotional beats where a short looping
/// animation earns its keep.
///
/// Expected assets live in `assets/rive/` (registered in `pubspec.yaml`):
///
/// | Slot              | Asset file             | Use                              |
/// |-------------------|------------------------|----------------------------------|
/// | splash            | `splash.riv`           | App launch splash                |
/// | orderSuccess      | `order-success.riv`    | Order confirmed sheet            |
/// | emptyCart         | `empty-cart.riv`       | Cart empty state / onboarding    |
/// | deliveryArrived   | `delivery-arrived.riv` | Driver arrived / onboarding      |
///
/// Asset budget: **< 500 KB per file**, vector-only (no embedded bitmaps),
/// 1–2 s seamless loops, dark-background safe. Files are pending brand
/// artwork — until they land, [MascotWidget] renders the drawn fallback
/// and everything still ships.
enum MascotSlot {
  splash,
  orderSuccess,
  emptyCart,
  deliveryArrived,
}

/// Documents which slots have real Rive artwork and where it lives.
///
/// Call [MascotRegistry.register] once brand artwork lands (e.g. in
/// `main.dart` before `bootstrap`, or per flavor entrypoint). Until a
/// slot is registered, [MascotWidget] uses the built-in drawn fallback —
/// so the UI is complete with zero `.riv` files in the repo.
abstract final class MascotRegistry {
  static final Map<MascotSlot, String> _assets = {};

  /// Expected on-disk filename for a slot (convention, for the docs and
  /// for designers exporting from Rive).
  static String expectedFile(MascotSlot slot) => switch (slot) {
        MascotSlot.splash => 'assets/rive/splash.riv',
        MascotSlot.orderSuccess => 'assets/rive/order-success.riv',
        MascotSlot.emptyCart => 'assets/rive/empty-cart.riv',
        MascotSlot.deliveryArrived => 'assets/rive/delivery-arrived.riv',
      };

  /// Register a finished artwork file for a slot. Keep each file
  /// under 500 KB (see the slot table above).
  static void register(MascotSlot slot, [String? assetPath]) {
    _assets[slot] = assetPath ?? expectedFile(slot);
  }

  static String? assetFor(MascotSlot slot) => _assets[slot];

  static bool isRegistered(MascotSlot slot) => _assets.containsKey(slot);
}

/// Brand mascot with graceful degradation:
///
/// 1. Slot registered **and** asset loadable **and** motion allowed →
///    plays the Rive file from `assets/rive/`.
/// 2. Otherwise → a static drawn illustration ([_MascotPainter]:
///    serving cloche in brand colors, no emoji) + optional caption.
/// 3. Reduced-motion or lite mode → always the static frame, even when
///    artwork exists.
///
/// Missing assets can never break a screen: the `rootBundle.load` probe
/// decides before `RiveAnimation` is ever constructed.
class MascotWidget extends StatelessWidget {
  const MascotWidget({
    super.key,
    required this.slot,
    this.size = 96,
    this.caption,
    this.brandColor,
  });

  final MascotSlot slot;
  final double size;
  final String? caption;
  final Color? brandColor;

  /// Probe futures cached per asset path — a rebuild must never restart
  /// the bundle lookup (or the Rive widget would flicker back to the
  /// fallback on every parent rebuild).
  static final Map<String, Future<ByteData?>> _probes = {};

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.maybeOf(context)?.value;
    final motionAllowed = settings == null ||
        (!settings.reducedMotion && !settings.liteMode);
    final asset = MascotRegistry.assetFor(slot);
    final color = brandColor ?? Theme.of(context).colorScheme.primary;

    Widget art;
    if (motionAllowed && asset != null) {
      art = FutureBuilder<ByteData?>(
        future: _probes.putIfAbsent(asset, () => _probeAsset(asset)),
        builder: (context, snap) {
          if (snap.data == null) {
            // Still probing (or asset missing) → draw the static frame
            // immediately so layout never jumps when the .riv arrives.
            return _fallback(color);
          }
          return RiveAnimation.asset(
            asset,
            fit: BoxFit.contain,
          );
        },
      );
    } else {
      art = _fallback(color);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: art,
        ),
        if (caption != null) ...[
          const SizedBox(height: 8),
          Text(
            caption!,
            style: TextStyle(
              color: TchopColors.textSecondary,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// Returns non-null only when the asset actually exists in the bundle.
  /// A missing `.riv` (pending brand artwork) resolves to null → the
  /// drawn fallback, no exception, no red screen.
  Future<ByteData?> _probeAsset(String asset) async {
    try {
      return await rootBundle.load(asset);
    } catch (_) {
      return null;
    }
  }

  Widget _fallback(Color color) => CustomPaint(
        painter: _MascotPainter(color: color),
      );
}

/// Drawn fallback: a warm serving cloche (dome + plate + steam) in the
/// tenant's brand color with a gold accent. Emoji-free by design.
class _MascotPainter extends CustomPainter {
  _MascotPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final platePaint = Paint()
      ..color = TchopColors.surfaceMuted
      ..style = PaintingStyle.fill;
    final domePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final accentPaint = Paint()
      ..color = TchopColors.defaultAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;
    final steamPaint = Paint()
      ..color = TchopColors.textSecondary.withValues(alpha: 204)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.03
      ..strokeCap = StrokeCap.round;

    // Plate.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, h * 0.78), width: w * 0.9, height: h * 0.16),
      platePaint,
    );
    // Dome.
    final domeRect = Rect.fromCenter(
        center: Offset(cx, h * 0.72), width: w * 0.68, height: h * 0.52);
    canvas.drawArc(domeRect, 3.14159, 3.14159, true, domePaint);
    // Dome highlight.
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(cx - w * 0.06, h * 0.72),
          width: w * 0.5,
          height: h * 0.38),
      3.14159 * 1.15,
      3.14159 * 0.5,
      false,
      accentPaint,
    );
    // Handle.
    canvas.drawCircle(
        Offset(cx, h * 0.40), w * 0.045, domePaint);
    canvas.drawCircle(
        Offset(cx, h * 0.40), w * 0.045, accentPaint);
    // Steam wisps.
    for (final dx in [-0.14, 0.02, 0.16]) {
      final x = cx + w * dx;
      final path = Path()
        ..moveTo(x, h * 0.30)
        ..cubicTo(x - w * 0.06, h * 0.24, x + w * 0.06, h * 0.18, x,
            h * 0.10);
      canvas.drawPath(path, steamPaint);
    }
  }

  @override
  bool shouldRepaint(_MascotPainter oldDelegate) =>
      oldDelegate.color != color;
}
