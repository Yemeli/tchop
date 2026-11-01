import 'package:flutter/material.dart';

import 'dispatch_models.dart';

/// Controller for [SignaturePad]: owns the strokes, exposes the SVG.
class SignaturePadController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];

  List<List<Offset>> get strokes =>
      List.unmodifiable(_strokes.map(List.unmodifiable));

  bool get isEmpty => _strokes.every((s) => s.isEmpty);

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  /// Encodes the strokes as an inline SVG document for the
  /// `delivery/complete` payload (`signature_svg`).
  String toSvg({double width = 300, double height = 150}) =>
      signatureStrokesToSvg(
        [
          for (final s in _strokes)
            [for (final o in s) SigPoint(o.dx, o.dy)],
        ],
        width: width,
        height: height,
      );

  void _addStroke() {
    _strokes.add([]);
  }

  void _addPoint(Offset point) {
    if (_strokes.isEmpty) _strokes.add([]);
    _strokes.last.add(point);
    notifyListeners();
  }
}

/// Hand-rolled signature pad (CustomPainter, no new dependency).
///
/// Sized by its parent; the controller's SVG uses the pad's logical
/// pixels as its coordinate space, so strokes scale with the rendered pad.
class SignaturePad extends StatefulWidget {
  const SignaturePad({
    super.key,
    required this.controller,
    this.height = 150,
  });

  final SignaturePadController controller;
  final double height;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onPanStart: (d) {
            widget.controller._addStroke();
            widget.controller._addPoint(d.localPosition);
          },
          onPanUpdate: (d) => widget.controller._addPoint(d.localPosition),
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => CustomPaint(
              painter: _SignaturePainter(widget.controller.strokes),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      // A single tap still leaves a dot.
      if (stroke.length == 1) {
        path.addOval(Rect.fromCircle(center: stroke.first, radius: 1.5));
      }
      canvas.drawPath(path, paint);
    }
    // Baseline hint.
    final hint = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(16, size.height - 24),
      Offset(size.width - 16, size.height - 24),
      hint,
    );
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => true;
}
