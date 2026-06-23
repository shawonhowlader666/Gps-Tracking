import 'dart:math';

import 'package:flutter/material.dart';

class SpeedometerScreen extends StatefulWidget {
  const SpeedometerScreen({super.key});

  @override
  State<SpeedometerScreen> createState() => _SpeedometerScreenState();
}

class _SpeedometerScreenState extends State<SpeedometerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _currentSpeed = 0;
  final double _targetSpeed = 57; // starting speed

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _animateTo(_targetSpeed);
  }

  void _animateTo(double newSpeed) {
    _animation = Tween<double>(
      begin: _currentSpeed,
      end: newSpeed,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ))
      ..addListener(() {
        setState(() {});
      });

    _controller.forward(from: 0);
    _currentSpeed = newSpeed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CustomPaint(
          size: const Size(300, 300),
          painter: SpeedometerPainter(speed: _animation.value),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.speed),
        onPressed: () {
          // Randomly change speed for testing
          final randomSpeed = (20 + Random().nextInt(160)).toDouble();
          _animateTo(randomSpeed);
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class SpeedometerPainter extends CustomPainter {
  final double speed;
  SpeedometerPainter({required this.speed});

  @override
  void paint(Canvas canvas, Size size) {
    double radius = size.width / 2;
    Offset center = Offset(radius, radius);

    // Arc angles
    double startAngle = pi * 0.75;
    double sweepAngle = pi * 1.5;

    double maxSpeed = 180;
    double sweepTo = (speed / maxSpeed) * sweepAngle;

    // Dynamic color
    Color activeColor = speed > 100 ? Colors.red : Colors.deepOrange;

    // Background arc
    Paint bgPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 20),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Active arc
    Paint activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 20),
      startAngle,
      sweepTo,
      false,
      activePaint,
    );

    // Tick marks with padding
    int majorTickStep = 20;
    int minorTickStep = 4;
    Paint majorTickPaint = Paint()
      ..strokeWidth = 2
      ..color = Colors.grey.shade400;
    Paint minorTickPaint = Paint()
      ..strokeWidth = 1
      ..color = Colors.grey.shade400;

    double tickOuterRadius = radius - 26; // padding from arc
    for (int i = 0; i <= maxSpeed; i += minorTickStep) {
      double angle = startAngle + (i / maxSpeed) * sweepAngle;
      double x1 = center.dx + tickOuterRadius * cos(angle);
      double y1 = center.dy + tickOuterRadius * sin(angle);

      double tickLength = (i % majorTickStep == 0) ? 20 : 10;
      double x2 = center.dx + (tickOuterRadius - tickLength) * cos(angle);
      double y2 = center.dy + (tickOuterRadius - tickLength) * sin(angle);

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2),
          i % majorTickStep == 0 ? majorTickPaint : minorTickPaint);

      // Draw labels at major ticks
      if (i % majorTickStep == 0 && i != 0) {
        TextPainter tp = TextPainter(
          text: TextSpan(
            text: "$i",
            style: const TextStyle(fontSize: 14, color: Colors.black),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        double lx = center.dx + (radius - 65) * cos(angle);
        double ly = center.dy + (radius - 65) * sin(angle);
        tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
      }
    }

    // Circle around speed text
    Paint circlePaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, 60, circlePaint);

    // Center speed value
    TextPainter tpSpeed = TextPainter(
      text: TextSpan(
        text: speed.toInt().toString(),
        style: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.bold,
          color: activeColor,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tpSpeed.layout();
    tpSpeed.paint(
        canvas, Offset(center.dx - tpSpeed.width / 2, center.dy - 25));

    // Km/h label
    TextPainter tpUnit = TextPainter(
      text: const TextSpan(
        text: "Km/h",
        style: TextStyle(fontSize: 18, color: Colors.black),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tpUnit.layout();
    tpUnit.paint(canvas, Offset(center.dx - tpUnit.width / 2, center.dy + 15));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
