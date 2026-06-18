import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:line_icons/line_icons.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:gpspro/screens/home_screen.dart';
import 'package:gpspro/screens/devices.dart';
import 'package:gpspro/screens/map_home.dart';
import 'package:gpspro/screens/report/recent_events.dart';
import 'package:gpspro/screens/settings.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/payment_service.dart';
import 'package:gpspro/screens/payment_block_screen.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gpspro/screens/payment_list.dart';

class MainBottomNav extends StatefulWidget {
  const MainBottomNav({super.key});

  @override
  State<StatefulWidget> createState() => _MainBottomNavState();
}

class _MainBottomNavState extends State<MainBottomNav> {
  int _selectedIndex = 0;
  late final PageController _pageController = PageController(initialPage: _selectedIndex);
  double _dueAmount = 0.0;
  bool _isLoadingDue = true;
  bool _isHardLocked = false;
  bool _warningShownThisSession = false;

  @override
  void initState() {
    super.initState();
    _checkDue();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkDue() async {
    try {
      final stats = await PaymentService.getStats();
      final due = stats?.due ?? 0.0;
      bool hardLocked = false;

      if (due > 0) {
        final bills = await PaymentService.getBills();
        if (bills != null && bills.isNotEmpty) {
          final unpaidBills = bills.where((b) => b.status.toLowerCase() != 'paid').toList();
          if (unpaidBills.isNotEmpty) {
            DateTime? oldestDate;
            for (final bill in unpaidBills) {
              try {
                final date = DateTime.parse(bill.billingMonth);
                if (oldestDate == null || date.isBefore(oldestDate)) {
                  oldestDate = date;
                }
              } catch (_) {}
            }

            if (oldestDate != null) {
              final days = DateTime.now().difference(oldestDate).inDays;
              if (days > 10) {
                hardLocked = true;
              }
            } else {
              hardLocked = true;
            }
          }
        } else {
          hardLocked = true;
        }
      }

      if (mounted) {
        setState(() {
          _dueAmount = due;
          _isHardLocked = hardLocked;
          _isLoadingDue = false;
        });

        if (due > 0 && !hardLocked && !_warningShownThisSession) {
          _warningShownThisSession = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showGracePeriodWarningDialog();
          });
        }
      }
    } catch (e) {
      debugPrint("Error checking due: $e");
      if (mounted) {
        setState(() {
          _isLoadingDue = false;
        });
      }
    }
  }

  void _showGracePeriodWarningDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text(
              'বকেয়া বিল পরিশোধের অনুরোধ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'আপনার অ্যাকাউন্টে মোট ৳${_dueAmount.toStringAsFixed(0)} বকেয়া বিল রয়েছে। সাময়িক ছাড়ের সময়সীমা পার হওয়ার আগেই অনুগ্রহ করে বিলটি পরিশোধ করুন। অন্যথায় আপনার ট্র্যাকিং সেবা সাময়িকভাবে স্থগিত করা হবে।',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[700],
            ),
            child: const Text(
              'পরে করুন',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Get.to(() => const PaymentListScreen())?.then((_) {
                setState(() {
                  _isLoadingDue = true;
                });
                _checkDue();
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'পরিশোধ করুন',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }



  final List<Widget> _screens = [
    HomeScreen(),
    const MapPage(),
    const DevicePage(),
    EventsPage(),
    SettingsPage(),
  ];

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    HapticFeedback.lightImpact();

    setState(() {
      _selectedIndex = index;
    });

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFFF0000),
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ));

    if (_isLoadingDue) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F6FA),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isHardLocked && _dueAmount > 0) {
      return PaymentBlockScreen(
        dueAmount: _dueAmount,
        onRefresh: () {
          setState(() {
            _isLoadingDue = true;
          });
          _checkDue();
        },
      );
    }

    final DataController controller = Get.isRegistered<DataController>()
        ? Get.find<DataController>()
        : Get.put(DataController());

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: _screens,
          ),
          Obx(() {
            if (controller.isLoading.value) {
              return Container(
                color: const Color(0xFFF5F6FA),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              );
            }
            return const SizedBox.shrink();
          }),
        ],
      ),
      bottomNavigationBar: _buildGNav(),
    );
  }

  Widget _buildGNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            blurRadius: 15,
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: GNav(
            gap: 8,
            activeColor: Colors.white,
            iconSize: 22,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            duration: const Duration(milliseconds: 300),
            tabBackgroundColor: const Color(0xFFFF0000),
            color: const Color(0xFF9E9E9E),
            tabs: [
              GButton(
                icon: LineIcons.home,
                text: 'homePage'.tr,
              ),
              GButton(
                icon: LineIcons.mapMarked,
                text: 'map'.tr,
              ),
              GButton(
                icon: LineIcons.car,
                text: 'vehicles'.tr,
              ),
              GButton(
                icon: LineIcons.bell,
                text: 'events'.tr,
              ),
              GButton(
                icon: LineIcons.cog,
                text: 'settings'.tr,
              ),
            ],
            selectedIndex: _selectedIndex,
            onTabChange: _onItemTapped,
          ),
        ),
      ),
    );
  }
}
