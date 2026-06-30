// lib/screens/report/tabs/monthly_report_tab.dart

import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:gpspro/screens/report/get_today_report.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/theme/custom_color.dart';
import 'package:intl/intl.dart';

import '../../playback.dart';

class MonthlyReportTab extends StatefulWidget {
  final int deviceId;
  final String deviceName;
  final DeviceItem? device;

  const MonthlyReportTab({
    super.key,
    required this.deviceId,
    required this.deviceName,
    this.device,
  });

  @override
  State<MonthlyReportTab> createState() => _MonthlyReportTabState();
}

class _MonthlyReportTabState extends State<MonthlyReportTab>
    with AutomaticKeepAliveClientMixin {
  late DateTime _selectedMonth;
  bool _isLoading = true;
  bool _isLoadingDaily = false;
  TodayReportData? _monthlyData;
  List<DayReport> _dailyReports = [];
  String? _errorMessage;

  // Loading progress
  int _loadedDays = 0;
  int _totalDays = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
    _loadMonthlyReport();
  }

  Future<void> _loadMonthlyReport() async {
    setState(() {
      _isLoading = true;
      _isLoadingDaily = false;
      _errorMessage = null;
      _dailyReports = [];
      _loadedDays = 0;
    });

    try {
      final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
      final today = DateTime.now();
      final effectiveLastDay = lastDay.isAfter(today) ? today : lastDay;

      _totalDays = effectiveLastDay.day;

      // Step 1: Get monthly total FAST
      final monthlyReport = await ReportService.getReportForPeriod(
        deviceId: widget.deviceId,
        period: ReportPeriod.custom,
        customStart: firstDay,
        customEnd: effectiveLastDay,
        forceRefresh: true,
      );

      setState(() {
        _monthlyData = monthlyReport;
        _isLoading = false;
        _isLoadingDaily = true;
      });

      // Step 2: Load daily reports in parallel (FAST)
      await _loadDailyReportsFast(effectiveLastDay);

    } catch (e) {
      log('Error loading monthly report: $e');
      setState(() {
        _isLoading = false;
        _isLoadingDaily = false;
        _errorMessage = 'Failed to load report';
      });
    }
  }

  Future<void> _loadDailyReportsFast(DateTime effectiveLastDay) async {
    final today = DateTime.now();
    final dailyReports = <DayReport>[];

    // Create list of dates (most recent first)
    final datesToLoad = <DateTime>[];
    for (int day = effectiveLastDay.day; day >= 1; day--) {
      final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
      if (!date.isAfter(today)) {
        datesToLoad.add(date);
      }
    }

    _totalDays = datesToLoad.length;

    // Load ALL days in parallel (much faster!)
    final futures = datesToLoad.map((date) => _loadSingleDay(date));
    final results = await Future.wait(futures);

    for (int i = 0; i < results.length; i++) {
      if (results[i] != null) {
        dailyReports.add(results[i]!);
      }
      _loadedDays = i + 1;

      // Update UI every 5 days for smooth progress
      if (i % 5 == 0 && mounted) {
        setState(() {
          _dailyReports = List.from(dailyReports);
        });
      }
    }

    if (mounted) {
      setState(() {
        _isLoadingDaily = false;
        _dailyReports = dailyReports;
      });
    }
  }

  Future<DayReport?> _loadSingleDay(DateTime date) async {
    try {
      final dayReport = await ReportService.getReportForPeriod(
        deviceId: widget.deviceId,
        period: ReportPeriod.custom,
        customStart: date,
        customEnd: DateTime(date.year, date.month, date.day, 23, 59, 59),
        fetchPdfInBackground: false,
      );

      if (dayReport.isNotEmpty) {
        return DayReport(date: date, data: dayReport);
      }
    } catch (e) {
      log('Error loading day ${date.day}: $e');
    }
    return null;
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
        1,
      );
    });
    _loadMonthlyReport();
  }

  void _openPlayback(DateTime date) {
    final fromDate = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final toDate = DateTime(date.year, date.month, date.day, 23, 59, 59);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlaybackScreen(
          id: widget.deviceId,
          name: widget.deviceName,
          device: widget.device,
          initialFromDate: fromDate,
          initialToDate: toDate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;

    return RefreshIndicator(
      onRefresh: _loadMonthlyReport,
      color: CustomColor.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Month Selector
          _buildMonthSelector(isCurrentMonth),
          const SizedBox(height: 16),

          // Content
          if (_isLoading)
            _buildLoadingState()
          else if (_errorMessage != null)
            _buildErrorState()
          else
            _buildReportContent(),
        ],
      ),
    );
  }

  Widget _buildMonthSelector(bool isCurrentMonth) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          _buildNavButton(Icons.chevron_left, () => _changeMonth(-1)),
          Expanded(
            child: Column(
              children: [
                Text(
                  DateFormat('MMMM').format(_selectedMonth),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _selectedMonth.year.toString(),
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          _buildNavButton(
            Icons.chevron_right,
            isCurrentMonth ? null : () => _changeMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: onTap != null
              ? CustomColor.primary.withValues(alpha: 0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 20,
          color: onTap != null ? CustomColor.primary : Colors.grey,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(60),
      child: const Center(
        child: CircularProgressIndicator(
          color: CustomColor.primary,
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
          const SizedBox(height: 12),
          Text(_errorMessage!, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _loadMonthlyReport,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent() {
    return Column(
      children: [
        // Monthly Summary
        if (_monthlyData != null && _monthlyData!.isNotEmpty)
          _buildMonthlySummary(),

        const SizedBox(height: 16),

        // Loading Progress
        if (_isLoadingDaily) _buildLoadingProgress(),

        // Daily Reports Header
        Row(
          children: [
            Text(
              'Daily Breakdown',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const Spacer(),
            Text(
              '${_dailyReports.length} days',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Daily Reports List
        if (_dailyReports.isEmpty && !_isLoadingDaily)
          _buildEmptyDays()
        else
          ..._dailyReports.map((day) => _buildDayCard(day)),
      ],
    );
  }

  Widget _buildLoadingProgress() {
    final progress = _totalDays > 0 ? _loadedDays / _totalDays : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation(CustomColor.primary),
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$_loadedDays/$_totalDays',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlySummary() {
    final data = _monthlyData!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [CustomColor.primary, Color(0xFFFF5252)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            DateFormat('MMMM yyyy').format(_selectedMonth),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            data.routeLength ?? '0 km',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Text(
            'Total Distance',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem('Moving', data.moveDuration ?? '-'),
              _buildSummaryItem('Stopped', data.stopDuration ?? '-'),
              _buildSummaryItem('Top Speed', data.topSpeed ?? '-'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white60),
        ),
      ],
    );
  }

  Widget _buildEmptyDays() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.calendar_today, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'No daily data available',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(DayReport day) {
    final isWeekend = day.date.weekday == 6 || day.date.weekday == 7;
    final isToday = DateUtils.isSameDay(day.date, DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isToday ? CustomColor.primary : Colors.grey.shade200,
          width: isToday ? 2 : 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isToday
                  ? CustomColor.primary
                  : isWeekend
                  ? Colors.orange.withValues(alpha: 0.1)
                  : CustomColor.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  day.date.day.toString(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isToday
                        ? Colors.white
                        : isWeekend
                        ? Colors.orange
                        : CustomColor.primary,
                  ),
                ),
                Text(
                  DateFormat('E').format(day.date),
                  style: TextStyle(
                    fontSize: 10,
                    color: isToday
                        ? Colors.white70
                        : isWeekend
                        ? Colors.orange
                        : CustomColor.primary,
                  ),
                ),
              ],
            ),
          ),
          title: Row(
            children: [
              Text(
                day.data.routeLength ?? '0 km',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'TODAY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            'Moving: ${day.data.moveDuration ?? '-'}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Playback Button
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 20),
            ],
          ),
          children: [
            _buildDayDetails(day.data, day.date),
          ],
        ),
      ),
    );
  }

  // Widget _buildPlaybackButton(DateTime date) {
  //   return GestureDetector(
  //     onTap: () => _openPlayback(date),
  //     child: Container(
  //       padding: const EdgeInsets.all(8),
  //       decoration: BoxDecoration(
  //         color: Colors.orange.withOpacity(0.1),
  //         borderRadius: BorderRadius.circular(8),
  //         border: Border.all(color: Colors.orange.withOpacity(0.3)),
  //       ),
  //       child: const Icon(
  //         Icons.play_circle_fill,
  //         color: Colors.orange,
  //         size: 22,
  //       ),
  //     ),
  //   );
  // }

  Widget _buildDayDetails(TodayReportData data, DateTime date) {
    return Column(
      children: [
        const Divider(),
        const SizedBox(height: 8),

        // Stats Row
        Row(
          children: [
            Expanded(
              child: _buildDetailItem('Stop', data.stopDuration ?? '-', Icons.local_parking),
            ),
            Expanded(
              child: _buildDetailItem('Top', data.topSpeed ?? '-', Icons.speed),
            ),
            Expanded(
              child: _buildDetailItem('Avg', data.averageSpeed ?? '-', Icons.trending_up),
            ),
          ],
        ),

        if (data.engineHours != null || data.fuelConsumption != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (data.engineHours != null)
                Expanded(
                  child: _buildDetailItem('Engine', data.engineHours!, Icons.engineering),
                ),
              if (data.fuelConsumption != null)
                Expanded(
                  child: _buildDetailItem('Fuel', data.fuelConsumption!, Icons.local_gas_station),
                ),
              if (data.engineHours == null || data.fuelConsumption == null)
                const Expanded(child: SizedBox()),
            ],
          ),
        ],

        const SizedBox(height: 12),

        // Full Playback Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _openPlayback(date),
            icon: const Icon(Icons.play_circle_outline, size: 20),
            label: Text(
              'View Playback - ${DateFormat('dd MMM').format(date)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class DayReport {
  final DateTime date;
  final TodayReportData data;

  DayReport({required this.date, required this.data});
}