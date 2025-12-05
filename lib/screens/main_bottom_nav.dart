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
  @override
  State<StatefulWidget> createState() => _MainBottomNavState();
}

class _MainBottomNavState extends State<MainBottomNav> {
  int _selectedIndex = 0;

  final List<_NavItem> _navItems = [
    _NavItem("homePage", LineIcons.home),
    _NavItem("vehicles", LineIcons.car),
    _NavItem("map", LineIcons.mapMarked),
    _NavItem("events", LineIcons.bell),
    _NavItem("settings", LineIcons.cog),
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFFF5F6FA),
      body: GetX<DataController>(
        init: DataController(),
        builder: (controller) {
          return !controller.isLoading.value
              ? IndexedStack(
            index: _selectedIndex,
            children: [
              HomeScreen(),
              const DevicePage(),
              const MapPage(),
              EventsPage(),
              SettingsPage(),
            ],
          )
              : const Center(child: CircularProgressIndicator());
        },
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    double width = MediaQuery.of(context).size.width;
    double itemWidth = width / _navItems.length;
    double centerX = (itemWidth * _selectedIndex) + (itemWidth / 2);

    return Container(
      height: 75,
      decoration: BoxDecoration(
        // Add outer shadow for the entire nav bar
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -8),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: const Color(0xFF3E6FB8).withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, -5),
            spreadRadius: 5,
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Curved Background with Shadow and Color
          Positioned.fill(
            child: CustomPaint(
              painter: CurvedBackgroundPainter(centerX: centerX),
            ),
          ),

          // Floating Selected Icon
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            left: centerX - 26,
            top: -5,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF3E6FB8),
                    const Color(0xFF5C8ACF),
                  ],
                ),
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3E6FB8).withValues(alpha: 0.5),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                _navItems[_selectedIndex].icon,
                size: 24,
                color: Colors.white,
              ),
            ),
          ),

          // Navigation Items
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 65,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(
                  _navItems.length,
                      (index) => _buildNavItem(index),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index) {
    final item = _navItems[index];
    final isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: MediaQuery.of(context).size.width / _navItems.length,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon - Hidden when selected
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isSelected ? 0 : 1,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[100],
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  item.icon,
                  size: 24,
                  color: Colors.grey[600],
                ),
              ),
            ),


            // Label - Hidden when selected
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isSelected ? 0 : 1,
              child: Text(
                item.label.tr,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  _NavItem(this.label, this.icon);
}

class CurvedBackgroundPainter extends CustomPainter {
  final double centerX;

  CurvedBackgroundPainter({required this.centerX});

  @override
  void paint(Canvas canvas, Size size) {
    // Main background gradient paint
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFE4B34E),
          const Color(0xFFF8F9FC),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    // Shadow paint - darker
    final shadowPaint1 = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    // Shadow paint - lighter/softer
    final shadowPaint2 = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    // Blue tint shadow
    final blueShadowPaint = Paint()
      ..color = const Color(0xFF3E6FB8).withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    // Border paint
    final borderPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    Path path = Path();

    double bumpWidth = 65;
    double bumpHeight = 20;
    double baseY = bumpHeight + 10;

    path.moveTo(0, baseY);

    // Before bump - smooth line
    path.lineTo(centerX - bumpWidth / 2 - 15, baseY);

    // Smooth curve into bump
    path.cubicTo(
      centerX - bumpWidth / 2 - 5,
      baseY,
      centerX - bumpWidth / 2,
      baseY - 5,
      centerX - bumpWidth / 3,
      baseY - bumpHeight * 0.7,
    );

    // Top of bump (smooth arc)
    path.quadraticBezierTo(
      centerX,
      -5,
      centerX + bumpWidth / 3,
      baseY - bumpHeight * 0.7,
    );

    // Smooth curve out of bump
    path.cubicTo(
      centerX + bumpWidth / 2,
      baseY - 5,
      centerX + bumpWidth / 2 + 5,
      baseY,
      centerX + bumpWidth / 2 + 15,
      baseY,
    );

    // After bump
    path.lineTo(size.width, baseY);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    // Draw shadows (multiple layers for depth)
    canvas.drawPath(path.shift(const Offset(0, -10)), blueShadowPaint);
    canvas.drawPath(path.shift(const Offset(0, -5)), shadowPaint1);
    canvas.drawPath(path.shift(const Offset(0, -2)), shadowPaint2);

    // Draw main background
    canvas.drawPath(path, gradientPaint);

    // Draw subtle border on top edge
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CurvedBackgroundPainter oldDelegate) {
    return oldDelegate.centerX != centerX;
  }
}