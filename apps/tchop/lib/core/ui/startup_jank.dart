import 'package:flutter/scheduler.dart';

/// Honest startup-jank heuristic feeding the lite-mode suggestion.
///
/// Measures the gaps between the first frames after launch. If the median
/// inter-frame gap stays above ~50 ms (sustained < 20 fps while the app
/// settles) or the app takes more than 4 s to reach a settled frame, the
/// device is a candidate for lite mode.
///
/// This is a *suggestion only*: [onComplete] fires once, `bootstrap`
/// records it via `AppSettingsController.suggestLiteMode()`, and the
/// Paramètres screen shows a one-time banner. Lite mode is never
/// auto-enabled — the user always decides. The toggle stays manual and
/// the heuristic is documented as approximate in `docs/design-tokens.md`.
abstract final class StartupJankMeter {
  static DateTime? _t0;
  static DateTime? _last;
  static final List<int> _gapsMicros = [];

  /// Called once with the verdict. Set by `bootstrap.dart`.
  static void Function(bool janky)? onComplete;

  static void begin() {
    _t0 = DateTime.now();
    _last = null;
    _gapsMicros.clear();
    SchedulerBinding.instance.addPostFrameCallback((_) => _sample(0));
  }

  static void _sample(int n) {
    final now = DateTime.now();
    if (_last != null) {
      _gapsMicros.add(now.difference(_last!).inMicroseconds);
    }
    _last = now;
    if (n < 12) {
      // Chain post-frame callbacks: 13 frames ≈ the launch settle window.
      SchedulerBinding.instance.addPostFrameCallback((_) => _sample(n + 1));
    } else {
      final gaps = List<int>.of(_gapsMicros)..sort();
      final medianMs =
          gaps.isEmpty ? 0.0 : gaps[gaps.length ~/ 2] / 1000.0;
      final settleMs =
          _t0 == null ? 0 : now.difference(_t0!).inMilliseconds;
      onComplete?.call(medianMs > 50 || settleMs > 4000);
    }
  }
}
