import 'package:flutter/material.dart';

class ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const ScaleButton({super.key, required this.child, this.onTap});

  @override
  State<ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<ScaleButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: 0.95, // Scales down to 95% of its size when pressed
      upperBound: 1.0,
    );
    _scale = _controller;
    _controller.value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isInteractive = widget.onTap != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        if (isInteractive) {
          _controller.reverse();
        }
      },
      onTapUp: (_) {
        if (isInteractive) {
          _controller.forward();
          widget.onTap!();
        }
      },
      onTapCancel: () {
        if (isInteractive) {
          _controller.forward();
        }
      },
      child: ScaleTransition(
        scale: _scale,
        child: IgnorePointer(
          ignoring: isInteractive, // Intercept touches at ScaleButton level
          child: widget.child,
        ),
      ),
    );
  }
}
