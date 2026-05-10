import 'package:flutter/material.dart';

class AppConstants {
  // App Name
  static const String appName = 'SmartLock GPS';
  static const String appTagline = 'Advanced Tracking Solution';

  // Logo Path
  static const String logoPath = 'icons/banner_logo.png';
  static const String appIcon = 'icons/app_logo.png';
}

class ShimmerAppTitle extends StatelessWidget {
  static const Color _primaryColor = Color(0xFF1D4888);
  static const Color _lightAccent = Color(0xFFE4B34E);

  final Animation<double> animation;
  final String title;
  final double fontSize;
  final double letterSpacing;

  const ShimmerAppTitle({
    super.key,
    required this.animation,
    required this.title,
    this.fontSize = 40,
    this.letterSpacing = 6,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                _primaryColor,
                _lightAccent,
                _primaryColor,
              ],
              stops: [
                (animation.value - 0.3).clamp(0.0, 1.0),
                animation.value.clamp(0.0, 1.0),
                (animation.value + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: letterSpacing,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}
