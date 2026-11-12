import 'package:flutter/material.dart';
import 'package:web_crypt/app/theme/app_colors.dart';

/// the shield and keyhole from the app icon, in the theme's accent
class AppLogo extends StatelessWidget {
  const AppLogo({this.size = 34, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CustomPaint(
      size: Size.square(size),
      painter: _LogoPainter(tile: colors.accent, ink: colors.accentText),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({required this.tile, required this.ink});

  final Color tile;
  final Color ink;

  // the same 24 unit grid and shapes as tool/interop/brand.mjs
  static final _shield = Path()
    ..moveTo(12, 2.6)
    ..lineTo(19, 5.3)
    ..lineTo(19, 10.9)
    ..cubicTo(19, 15.5, 16.1, 19.5, 12, 21.4)
    ..cubicTo(7.9, 19.5, 5, 15.5, 5, 10.9)
    ..lineTo(5, 5.3)
    ..close();

  static final _keyhole = Path()
    ..addOval(Rect.fromCircle(center: const Offset(12, 10.3), radius: 2.15))
    ..addPolygon(const [
      Offset(11.25, 11.4),
      Offset(12.75, 11.4),
      Offset(13.5, 15.7),
      Offset(10.5, 15.7),
    ], true);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    canvas.drawRRect(
      RRect.fromLTRBR(0, 0, 24, 24, const Radius.circular(5.3)),
      Paint()..color = tile,
    );
    canvas
      ..translate(12, 12)
      ..scale(0.72)
      ..translate(-12, -12);
    // stroked as well as filled, which rounds off the corners
    final edge = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(_shield, Paint()..color = ink)
      ..drawPath(_shield, edge)
      ..drawPath(_keyhole, Paint()..color = tile);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.tile != tile || old.ink != ink;
}
