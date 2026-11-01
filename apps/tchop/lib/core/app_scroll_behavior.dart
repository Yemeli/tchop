import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// App-wide scroll behavior.
///
/// Extends [MaterialScrollBehavior] so lists, grids and boards can be
/// dragged with a **mouse** or **trackpad** — required for web and desktop,
/// where users expect click-drag scrolling. Touch and stylus behavior is
/// unchanged.
class TchopScrollBehavior extends MaterialScrollBehavior {
  const TchopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
