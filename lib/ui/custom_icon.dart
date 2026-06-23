import 'package:flutter/material.dart';
import 'package:smart_lock/theme/custom_color.dart';

class CustomIcon extends CustomPainter {
  final String _label;
  final String _icon;

  CustomIcon(this._label, this._icon);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint();

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final RRect rRect = RRect.fromRectAndRadius(rect, Radius.circular(10));

    paint.color = MAPS_IMAGES_COLOR;
    paint.strokeWidth = 2;

    canvas.drawRRect(rRect, paint);

    final textPainter = TextPainter(
        text: TextSpan(
          text: _label,
          style: TextStyle(fontSize: 30, color: Colors.white),
        ),
        textDirection: TextDirection.ltr);

    textPainter.layout(minWidth: 0, maxWidth: size.width);
    textPainter.paint(
        canvas, Offset(15, size.height / 2 - textPainter.size.height / 2));

    IconData icon;
    if (_icon == 'man') {
      icon = Icons.directions_walk;
    } else if (_icon == 'woman') {
      icon = Icons.face;
    } else if (_icon == 'pregnant') {
      icon = Icons.pregnant_woman;
    } else if (_icon == 'child') {
      icon = Icons.child_care;
    } else if (_icon == 'disability') {
      icon = Icons.accessible;
    } else if (_icon == 'pet') {
      icon = Icons.pets;
    } else if (_icon == 'car') {
      icon = Icons.directions_car;
    } else if (_icon == 'bike') {
      icon = Icons.motorcycle;
    } else if (_icon == 'truck') {
      icon = Icons.local_shipping;
    } else if (_icon == 'boat') {
      icon = Icons.directions_boat;
    } else if (_icon == 'marker') {
      icon = Icons.pin_drop;
    } else {
      icon = Icons.directions_walk;
    }
    TextPainter textPainter2 = TextPainter(textDirection: TextDirection.rtl);
    textPainter2.text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
            fontSize: 50.0,
            fontFamily: icon.fontFamily,
            color: MAPS_IMAGES_COLOR));
    textPainter2.layout();
    textPainter2.paint(canvas,
        Offset(size.width / 2 - textPainter2.size.width / 2, size.height));
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
