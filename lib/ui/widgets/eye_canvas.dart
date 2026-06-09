import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/robi_state.dart';

/// Paints the eye. Position (`offset`) comes from the widget tree; the
/// expression inputs (`amplitude`, `wordPulse`, `crescent`) are passed as a
/// merged `repaint` Listenable so they trigger only a cheap repaint and never
/// rebuild the position-smoothing layer above.
class EyePainter extends CustomPainter {
  final Offset offset;
  final ValueListenable<double> amplitude;
  final Animation<double> wordPulse;
  final Animation<double> crescent;
  final RobiState state;
  final Size eyeSize;

  EyePainter({
    required this.offset,
    required this.amplitude,
    required this.wordPulse,
    required this.crescent,
    required this.state,
    this.eyeSize = const Size(80, 160),
  }) : super(repaint: Listenable.merge([amplitude, wordPulse, crescent]));

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final double x = size.width * offset.dx;
    final double y = size.height * offset.dy;

    final double scale = switch (state) {
      // Amplitude floor keeps animation alive; word pulse adds a spike per word
      RobiState.speaking =>
        (amplitude.value + wordPulse.value * 0.4).clamp(0.12, 1.0),
      RobiState.thinking => 0.0,
      RobiState.idle => amplitude.value,
    };

    double width = eyeSize.width;
    double height = eyeSize.height;
    if (scale > 0.05) {
      // Squash and stretch: loud → thin and tall, quiet → wide and short
      width = width * (1.0 - (scale * 0.3));
      height = height * (1.0 + (scale * 0.4));
    }

    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y), width: width, height: height),
      paint,
    );

    // Crescent: occlude with a same-size black oval shifted down
    final double crescentProgress = crescent.value;
    if (crescentProgress > 0) {
      final blackPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y + crescentProgress * 35),
          width: width,
          height: height,
        ),
        blackPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant EyePainter oldDelegate) =>
      oldDelegate.offset != offset || oldDelegate.state != state;
}
