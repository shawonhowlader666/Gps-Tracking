import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:line_icons/line_icons.dart';
import 'package:smart_lock/screens/home_screen.dart';
import 'package:smart_lock/screens/devices.dart';
import 'package:smart_lock/screens/map_home.dart';
import 'package:smart_lock/screens/report/recent_events.dart';
import 'package:smart_lock/screens/settings.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';

class MainBottomNav extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _MainBottomNavState();
}

class _MainBottomNavState extends State<MainBottomNav> {
  int _selectedIndex = 1;

  final List<_NavItem> _navItems = [
    _NavItem("homePage", LineIcons.home),
    _NavItem("vehicles", LineIcons.car),
    _NavItem("map", LineIcons.mapMarked),
    _NavItem("events", LineIcons.bell),
    _NavItem("settings", LineIcons.cog),
  ];

  final List<Widget> _screens = [
    HomeScreen(),
    const DevicePage(),
    const MapPage(),
    EventsPage(),
    SettingsPage(),
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
      backgroundColor: const Color(0xFFF5F6FA),
      body: GetX<DataController>(
        init: DataController(),
        builder: (controller) {
          return !controller.isLoading.value
              ? IndexedStack(
            index: _selectedIndex,
            children: _screens,
          )
              : const Center(child: CircularProgressIndicator());
        },
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(
              _navItems.length,
                  (index) => _buildNavItem(index),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index) {
    final item = _navItems[index];
    final isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 14 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFE0E0) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              size: 22,
              color: isSelected ? const Color(0xFFE53935) : Colors.grey[500],
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(
                item.label.tr,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE53935),
                ),
              ),
            ],
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