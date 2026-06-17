import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const ScaleButton({super.key, required this.child, this.onTap});

  @override
  State<ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<ScaleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 60),    // press: fast
      reverseDuration: const Duration(milliseconds: 200), // release: spring-back
      lowerBound: 0.0,
      upperBound: 1.0,
    );

    // Spring-feel on release: easeOutBack gives a tiny overshoot
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      ),
    );

    _controller.value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap == null) return;
    HapticFeedback.lightImpact(); // Premium tactile feel
    _controller.reverse(); // animate to 0.92 scale
  }

  void _onTapUp(TapUpDetails _) {
    if (widget.onTap == null) return;
    _controller.forward(); // spring-back to 1.0
    widget.onTap!();
  }

  void _onTapCancel() {
    if (widget.onTap == null) return;
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(
          scale: _scale.value,
          child: child,
        ),
        child: IgnorePointer(
          ignoring: widget.onTap != null,
          child: widget.child,
        ),
      ),
    );
  }
}
