import 'package:flutter/material.dart';

class SaltShakerIcon extends StatelessWidget {
  const SaltShakerIcon({super.key, required this.color, this.size = 18});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SaltShakerPainter(color)),
    );
  }
}

class _SaltShakerPainter extends CustomPainter {
  const _SaltShakerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final cap = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.28,
        size.height * 0.18,
        size.width * 0.44,
        size.height * 0.18,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(cap, stroke);

    final bodyPath = Path()
      ..moveTo(size.width * 0.32, size.height * 0.42)
      ..lineTo(size.width * 0.68, size.height * 0.42)
      ..quadraticBezierTo(
        size.width * 0.74,
        size.height * 0.42,
        size.width * 0.72,
        size.height * 0.52,
      )
      ..lineTo(size.width * 0.62, size.height * 0.82)
      ..quadraticBezierTo(
        size.width * 0.59,
        size.height * 0.88,
        size.width * 0.50,
        size.height * 0.88,
      )
      ..quadraticBezierTo(
        size.width * 0.41,
        size.height * 0.88,
        size.width * 0.38,
        size.height * 0.82,
      )
      ..lineTo(size.width * 0.28, size.height * 0.52)
      ..quadraticBezierTo(
        size.width * 0.26,
        size.height * 0.42,
        size.width * 0.32,
        size.height * 0.42,
      )
      ..close();
    canvas.drawPath(bodyPath, stroke);

    final holeRadius = size.width * 0.035;
    final holes = [
      Offset(size.width * 0.41, size.height * 0.27),
      Offset(size.width * 0.50, size.height * 0.24),
      Offset(size.width * 0.59, size.height * 0.27),
    ];
    for (final hole in holes) {
      canvas.drawCircle(hole, holeRadius, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _SaltShakerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
