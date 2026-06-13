import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:line_icons/line_icons.dart';
import 'package:gpspro/screens/home_screen.dart';
import 'package:gpspro/screens/devices.dart';
import 'package:gpspro/screens/map_home.dart';
import 'package:gpspro/screens/report/recent_events.dart';
import 'package:gpspro/screens/settings.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';

class MainBottomNav extends StatefulWidget {
  const MainBottomNav({super.key});

  @override
  State<StatefulWidget> createState() => _MainBottomNavState();
}

class _MainBottomNavState extends State<MainBottomNav>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 2;
  late AnimationController _bounceController;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
    _bounceController.value = 1.0;
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  final List<_NavItem> _navItems = [
    _NavItem("homePage", LineIcons.home),
    _NavItem("map", LineIcons.mapMarked),
    _NavItem("vehicles", LineIcons.car),
    _NavItem("events", LineIcons.bell),
    _NavItem("settings", LineIcons.cog),
  ];

  final List<Widget> _screens = [
    HomeScreen(),
    const MapPage(),
    const DevicePage(),
    EventsPage(),
    SettingsPage(),
  ];

  static const Color _kPrimaryColor = Color(0xFF1B851C);
  static const double _kBarHeight = 70.0;
  static const double _kCircleSize  = 52.0;
  static const double _kCircleRise  = 18.0; // how high circle floats above bar
  static const double _kNotchWidth  = 96.0; // wider notch = visible gap around circle

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    HapticFeedback.lightImpact();

    _bounceController.forward(from: 0.0);

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: GetX<DataController>(
        init: DataController(),
        builder: (controller) {
          return !controller.isLoading.value
              ? IndexedStack(index: _selectedIndex, children: _screens)
              : const Center(child: CircularProgressIndicator());
        },
      ),
      bottomNavigationBar: _buildNav(),
    );
  }

  Widget _buildNav() {
    return BottomAppBar(
      color: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _kBarHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width    = constraints.maxWidth;
              final tabWidth = width / _navItems.length;
              final targetX  = tabWidth * _selectedIndex + tabWidth / 2;

              return TweenAnimationBuilder<double>(
                tween: Tween<double>(end: targetX),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOutCubic,
                builder: (context, notchX, _) {
                  return AnimatedBuilder(
                    animation: _bounceController,
                    builder: (context, child) {
                      final double u = _bounceController.value;

                      // Physics calculations based on animation progress 'u' (0.0 to 1.0)
                      double yOffset = 0.0;
                      double scaleX = 1.0;
                      double scaleY = 1.0;

                      // u goes from 0.0 to 1.0 (over 1150ms total).
                      // Staggered delay: first 400ms (u < 0.35) is flat horizontal sliding.
                      if (u >= 0.35) {
                        // Normalize bounce timeline 't' from 0.0 to 1.0 (over the remaining 750ms)
                        final double t = (u - 0.35) / 0.65;

                        // Physical constants for damped harmonic oscillation
                        final double decay = 2.0;
                        final double A = 20.0;
                        final double freq = 2.0;

                        final double val = t * freq * pi;
                        yOffset = A * exp(-decay * t) * sin(val);

                        // Velocity-based squash/stretch calculation
                        final double vel = A * exp(-decay * t) *
                            (freq * pi * cos(val) - decay * sin(val));

                        // S is positive for horizontal squash, negative for vertical stretch
                        double S = (0.012 * yOffset) - (0.0012 * vel.abs());
                        S = S.clamp(-0.2, 0.25);
                        scaleX = 1.0 + S;
                        scaleY = 1.0 - S;
                      }

                      // Elastic notch depth (deforms down when circle drops/cushions)
                      final double dynamicDepth = (26.0 + yOffset).clamp(0.0, 50.0);

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // ── 1. White notched bar (deforms dynamically!) ──
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _NotchPainter(
                                notchX: notchX,
                                notchDepth: dynamicDepth,
                              ),
                            ),
                          ),

                          // ── 2. Circle (squash-and-stretch bounce) ──
                          Positioned(
                            left: notchX - _kCircleSize / 2,
                            top: -_kCircleRise + yOffset,
                            child: Transform(
                              alignment: Alignment.bottomCenter,
                              transform: Matrix4.diagonal3Values(scaleX, scaleY, 1.0),
                              child: _buildCircle(),
                            ),
                          ),

                          // ── 3. Tab row ──
                          Positioned.fill(
                            child: Row(
                              children: List.generate(
                                _navItems.length,
                                (i) => Expanded(
                                  child: _buildTab(i, notchX, tabWidth),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // White circle with green icon — same material as the bar
  Widget _buildCircle() {
    return Container(
      width: _kCircleSize,
      height: _kCircleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: _kPrimaryColor.withValues(alpha: 0.25), width: 2.0),
        boxShadow: [
          BoxShadow(
            color: _kPrimaryColor.withValues(alpha: 0.16),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          );
        },
        child: Icon(
          _navItems[_selectedIndex].icon,
          key: ValueKey<int>(_selectedIndex),
          color: _kPrimaryColor,
          size: 25,
        ),
      ),
    );
  }

  Widget _buildTab(int index, double notchX, double tabWidth) {
    final isSelected = _selectedIndex == index;
    const inactiveColor = Color(0xFF9CA3AF);

    // Calculate distance of the notch to this tab's horizontal center
    final tabCenterX = tabWidth * index + tabWidth / 2;
    final distance = (notchX - tabCenterX).abs();

    // factor is 0.0 when notch is exactly on this tab, 1.0 when notch is far
    final double factor = (distance / tabWidth).clamp(0.0, 1.0);

    // Icon opacity and scale go to 0.0 as notch approaches, preventing duplicate overlapping shadows
    final double iconOpacity = Curves.easeIn.transform(factor);
    final double iconScale = Curves.easeIn.transform(factor);

    // Label opacity and active dot width go to maximum as notch approaches
    final double labelOpacity = Curves.easeIn.transform(1.0 - factor);
    final double activeDotWidth = 14.0 * (1.0 - factor);

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon — visible when inactive, mathematically fades and scales out as the floating circle arrives
          Opacity(
            opacity: iconOpacity,
            child: Transform.scale(
              scale: iconScale,
              child: Icon(
                _navItems[index].icon,
                size: 22,
                color: inactiveColor,
              ),
            ),
          ),
          const SizedBox(height: 3),
          // Label — fades in as the floating circle arrives
          Opacity(
            opacity: labelOpacity,
            child: Text(
              _navItems[index].label.tr,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _kPrimaryColor,
                letterSpacing: 0.3,
              ),
            ),
          ),
          // Active dot — expands as the floating circle arrives
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: activeDotWidth,
            height: 3,
            decoration: BoxDecoration(
              color: _kPrimaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  _NavItem(this.label, this.icon);
}

class _NotchPainter extends CustomPainter {
  final double notchX;
  final double notchDepth;

  const _NotchPainter({required this.notchX, required this.notchDepth});

  static const double _notchWidth = 96.0;  // gap around circle
  static const double _cornerR    = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _makePath(size);

    // Soft ambient shadow
    canvas.drawPath(
      path.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
        ..style = PaintingStyle.fill,
    );
    // Key shadow
    canvas.drawPath(
      path.shift(const Offset(0, 1)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.04)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
        ..style = PaintingStyle.fill,
    );
    // Main bar
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    // Hairline top border
    canvas.drawPath(
      _makeBorderPath(size),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  Path _makePath(Size size) {
    final nx = notchX;
    const nw = _notchWidth;
    final nd = notchDepth;
    const r  = _cornerR;
    final s  = nx - nw / 2;
    final e  = nx + nw / 2;

    return Path()
      ..moveTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(s, 0)
      ..cubicTo(s + nw * 0.20, 0, nx - nw * 0.20, nd, nx, nd)
      ..cubicTo(nx + nw * 0.20, nd, e - nw * 0.20, 0, e, 0)
      ..lineTo(size.width - r, 0)
      ..quadraticBezierTo(size.width, 0, size.width, r)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  Path _makeBorderPath(Size size) {
    final nx = notchX;
    const nw = _notchWidth;
    final nd = notchDepth;
    const r  = _cornerR;
    final s  = nx - nw / 2;
    final e  = nx + nw / 2;

    return Path()
      ..moveTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(s, 0)
      ..cubicTo(s + nw * 0.20, 0, nx - nw * 0.20, nd, nx, nd)
      ..cubicTo(nx + nw * 0.20, nd, e - nw * 0.20, 0, e, 0)
      ..lineTo(size.width - r, 0)
      ..quadraticBezierTo(size.width, 0, size.width, r);
  }

  @override
  bool shouldRepaint(covariant _NotchPainter old) =>
      old.notchX != notchX || old.notchDepth != notchDepth;
}
