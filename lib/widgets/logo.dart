import 'package:flutter/material.dart';

import '../theme.dart';

/// The Funds app icon (white wallet on blue), drawn in code so it matches
/// the launcher icon exactly. Same geometry as assets/icon/funds-icon.svg.
class FundsLogo extends StatelessWidget {
  const FundsLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Funds',
      image: true,
      child: CustomPaint(size: Size.square(size), painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Work on the 108 x 108 grid of the SVG.
    canvas.scale(size.width / 108);

    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 108, 108), const Radius.circular(24)),
      Paint()..color = C.accent,
    );

    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Flap
    canvas.drawPath(
      Path()
        ..moveTo(30, 42)
        ..lineTo(30, 40)
        ..arcToPoint(const Offset(38, 32), radius: const Radius.circular(8))
        ..lineTo(64, 32),
      stroke,
    );
    // Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(30, 38, 48, 38), const Radius.circular(8)),
      stroke,
    );
    // Clasp
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(60, 50, 18, 14), const Radius.circular(5)),
      stroke,
    );
    // Button
    canvas.drawCircle(const Offset(67, 57), 2.6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
