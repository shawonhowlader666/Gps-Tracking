// lib/screens/report/tabs/custom_report_tab.dart

import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:gpspro/screens/report/get_today_report.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:intl/intl.dart';

class CustomReportTab extends StatefulWidget {
  final int deviceId;
  final String deviceName;
  final String? presetPeriod;

  const CustomReportTab({
    super.key,
    required this.deviceId,
    required this.deviceName,
    this.presetPeriod,
  });

  @override
  State<CustomReportTab> createState() => _CustomReportTabState();
}

class _CustomReportTabState extends State<CustomReportTab>
    with AutomaticKeepAliveClientMixin {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  bool _isLoading = false;
  TodayReportData? _reportData;
  String? _errorMessage;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.presetPeriod != null) {
      _applyPreset(widget.presetPeriod!);
      WidgetsBinding.instance.addPostFrameCallback((_) => _generateReport());
    }
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    switch (preset) {
      case 'today':
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = now;
        break;
      case 'yesterday':
        final yesterday = now.subtract(const Duration(days: 1));
        _startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
        _endDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
        break;
      case 'thisWeek':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        _startDate = DateTime(monday.year, monday.month, monday.day);
        _endDate = now;
        break;
      case 'thisMonth':
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = now;
        break;
      case 'last7days':
        _startDate = now.subtract(const Duration(days: 7));
        _endDate = now;
        break;
      case 'last30days':
        _startDate = now.subtract(const Duration(days: 30));
        _endDate = now;
        break;
    }
  }

  Future<void> _generateReport() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final report = await ReportService.getReportForPeriod(
        deviceId: widget.deviceId,
        period: ReportPeriod.custom,
        customStart: _startDate,
        customEnd: _endDate,
        forceRefresh: true,
      );

      setState(() {
        _reportData = report;
        _isLoading = false;
      });
    } catch (e) {
      log('Error generating report: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to generate report';
      });
    }
  }

  Future<void> _selectDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: CustomColor.primary),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_startDate.isAfter(_endDate)) _endDate = _startDate;
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) _startDate = _endDate;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Quick Presets
        _buildQuickPresets(),
        const SizedBox(height: 16),

        // Date Range Selector
        _buildDateRange(),
        const SizedBox(height: 16),

        // Generate Button
        _buildGenerateButton(),
        const SizedBox(height: 16),

        // Results
        if (_isLoading)
          _buildLoadingState()
        else if (_errorMessage != null)
          _buildErrorState()
        else if (_reportData != null && _reportData!.isNotEmpty)
            _buildReportResults(),
      ],
    );
  }

  Widget _buildQuickPresets() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildPresetChip('Today', 'today'),
        _buildPresetChip('Yesterday', 'yesterday'),
        _buildPresetChip('This Week', 'thisWeek'),
        _buildPresetChip('This Month', 'thisMonth'),
        _buildPresetChip('Last 7 Days', 'last7days'),
        _buildPresetChip('Last 30 Days', 'last30days'),
      ],
    );
  }

  Widget _buildPresetChip(String label, String preset) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: () {
        _applyPreset(preset);
        setState(() {});
      },
    );
  }

  Widget _buildDateRange() {
    final days = _endDate.difference(_startDate).inDays + 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildDatePicker('From', _startDate, () => _selectDate(true))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.arrow_forward, size: 20, color: Colors.grey),
              ),
              Expanded(child: _buildDatePicker('To', _endDate, () => _selectDate(false))),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: CustomColor.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.date_range, size: 16, color: CustomColor.primary),
                const SizedBox(width: 6),
                Text(
                  '$days day${days > 1 ? 's' : ''} selected',
                  style: const TextStyle(
                    fontSize: 13,
                    color: CustomColor.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker(String label, DateTime date, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 14, color: CustomColor.primary),
                const SizedBox(width: 6),
                Text(
                  DateFormat('dd MMM yy').format(date),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _generateReport,
        icon: _isLoading
            ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
            : const Icon(Icons.analytics, size: 20),
        label: Text(_isLoading ? 'Generating...' : 'Generate Report'),
        style: ElevatedButton.styleFrom(
          backgroundColor: CustomColor.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: const Center(
        child: CircularProgressIndicator(color: CustomColor.primary, strokeWidth: 2),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 40, color: Colors.red[300]),
          const SizedBox(height: 12),
          Text(_errorMessage!, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _generateReport,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportResults() {
    final data = _reportData!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CustomColor.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.assessment, color: CustomColor.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Report Results',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${DateFormat('dd MMM').format(_startDate)} - ${DateFormat('dd MMM yy').format(_endDate)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          // Data Rows
          if (data.routeLength != null)
            _buildResultRow('Distance', data.routeLength!, Icons.route, CustomColor.primary),
          if (data.moveDuration != null)
            _buildResultRow('Move Duration', data.moveDuration!, Icons.directions_car, const Color(0xFF43A047)),
          if (data.stopDuration != null)
            _buildResultRow('Stop Duration', data.stopDuration!, Icons.local_parking, const Color(0xFFFF9800)),
          if (data.topSpeed != null)
            _buildResultRow('Top Speed', data.topSpeed!, Icons.speed, const Color(0xFFE53935)),
          if (data.averageSpeed != null)
            _buildResultRow('Avg Speed', data.averageSpeed!, Icons.trending_up, const Color(0xFF00BCD4)),
          if (data.engineHours != null)
            _buildResultRow('Engine Hours', data.engineHours!, Icons.engineering, const Color(0xFF9C27B0)),
          if (data.fuelConsumption != null)
            _buildResultRow('Fuel', data.fuelConsumption!, Icons.local_gas_station, const Color(0xFFFF7043)),
          if (data.odometer != null)
            _buildResultRow('Odometer', data.odometer!, Icons.speed, const Color(0xFFFF5252)),
          if (data.overspeedCount != null && data.overspeedCount != '0')
            _buildResultRow('Overspeed', '${data.overspeedCount} times', Icons.warning_amber, const Color(0xFFE91E63)),
        ],
      ),
    );
  }

  Widget _buildResultRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[700])),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}