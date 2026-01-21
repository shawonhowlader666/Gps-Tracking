// lib/screens/report/report_screen.dart

import 'package:flutter/material.dart';
import 'package:gpspro/screens/report/tabs/daily_report_tab.dart';
import 'package:gpspro/screens/report/tabs/monthly_report_tab.dart';
import 'package:gpspro/screens/report/tabs/custom_report_tab.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;

class ReportScreen extends StatefulWidget {
  final int deviceId;
  final String deviceName;
  final DeviceItem? device;  // ADD THIS
  final int initialTab;
  final String? presetPeriod;

  const ReportScreen({
    Key? key,
    required this.deviceId,
    required this.deviceName,
    this.device,  // ADD THIS
    this.initialTab = 0,
    this.presetPeriod,
  }) : super(key: key);

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4B5FCC),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reports',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              widget.deviceName,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          tabs: [
            Tab(icon: Icon(Icons.today, size: 20), text: 'Daily'),
            Tab(icon: Icon(Icons.calendar_month, size: 20), text: 'Monthly'),
            Tab(icon: Icon(Icons.tune, size: 20), text: 'Custom'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          DailyReportTab(
            deviceId: widget.deviceId,
            deviceName: widget.deviceName,
          ),
          MonthlyReportTab(
            deviceId: widget.deviceId,
            deviceName: widget.deviceName,
            device: widget.device,  // PASS DEVICE
          ),
          CustomReportTab(
            deviceId: widget.deviceId,
            deviceName: widget.deviceName,
            presetPeriod: widget.presetPeriod,
          ),
        ],
      ),
    );
  }
}