// lib/screens/report/tabs/monthly_report_tab.dart

import 'package:flutter/material.dart';
import 'package:smart_lock/screens/report/get_today_report.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
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
  int _loadedDays = 0;
  int _totalDays = 0;

  static const _red = Color(0xFFD32F2F);
  static const _deepRed = Color(0xFFB71C1C);
  static const _lightRed = Color(0xFFEF5350);

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
      final lastDay =
      DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
      final today = DateTime.now();
      final effectiveLastDay = lastDay.isAfter(today) ? today : lastDay;
      _totalDays = effectiveLastDay.day;

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

      await _loadDailyReportsFast(effectiveLastDay);
    } catch (_) {
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
    final datesToLoad = <DateTime>[];

    for (int day = effectiveLastDay.day; day >= 1; day--) {
      final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
      if (!date.isAfter(today)) datesToLoad.add(date);
    }

    _totalDays = datesToLoad.length;

    final futures = datesToLoad.map((date) => _loadSingleDay(date));
    final results = await Future.wait(futures);

    for (int i = 0; i < results.length; i++) {
      if (results[i] != null) dailyReports.add(results[i]!);
      _loadedDays = i + 1;
      if (i % 5 == 0 && mounted) {
        setState(() => _dailyReports = List.from(dailyReports));
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
      );
      if (dayReport.isNotEmpty) return DayReport(date: date, data: dayReport);
    } catch (_) {}
    return null;
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta, 1);
    });
    _loadMonthlyReport();
  }

  void _openPlayback(DateTime date) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaybackScreen(
          id: widget.deviceId,
          name: widget.deviceName,
          device: widget.device,
          initialFromDate: DateTime(date.year, date.month, date.day),
          initialToDate: DateTime(date.year, date.month, date.day, 23, 59, 59),
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
      color: _red,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          _buildMonthSelector(isCurrentMonth),
          const SizedBox(height: 20),
          if (_isLoading)
            _buildLoadingState()
          else if (_errorMessage != null)
            _buildErrorState()
          else
            _buildContent(),
        ],
      ),
    );
  }

  Widget _buildMonthSelector(bool isCurrentMonth) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _NavBtn(icon: Icons.chevron_left_rounded, onTap: () => _changeMonth(-1)),
          Expanded(
            child: Column(
              children: [
                Text(
                  DateFormat('MMMM').format(_selectedMonth),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  _selectedMonth.year.toString(),
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          _NavBtn(
            icon: Icons.chevron_right_rounded,
            onTap: isCurrentMonth ? null : () => _changeMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const SizedBox(
      height: 300,
      child: Center(
        child: CircularProgressIndicator(color: _red, strokeWidth: 2.5),
      ),
    );
  }

  Widget _buildErrorState() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Icon(Icons.wifi_off_rounded, size: 52, color: Colors.red[300]),
        const SizedBox(height: 12),
        Text(_errorMessage!,
            style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: _loadMonthlyReport,
          icon: const Icon(Icons.refresh_rounded, size: 18, color: _red),
          label: const Text('Retry', style: TextStyle(color: _red)),
        ),
      ],
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        if (_monthlyData != null && _monthlyData!.isNotEmpty) ...[
          _buildSummaryCard(),
          const SizedBox(height: 20),
        ],
        if (_isLoadingDaily) _buildProgressBar(),
        _buildDailyHeader(),
        const SizedBox(height: 12),
        if (_dailyReports.isEmpty && !_isLoadingDaily)
          _buildEmptyDays()
        else
          ..._dailyReports.map((day) => _buildDayCard(day)),
      ],
    );
  }

  Widget _buildSummaryCard() {
    final data = _monthlyData!;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_deepRed, _lightRed],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _red.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            DateFormat('MMMM yyyy').format(_selectedMonth),
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            data.routeLength ?? '0 km',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
          Text(
            'Total Distance',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65), fontSize: 13),
          ),
          const SizedBox(height: 20),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SummaryItem(label: 'Moving', value: data.moveDuration ?? '—'),
              _SummaryItem(label: 'Stopped', value: data.stopDuration ?? '—'),
              _SummaryItem(label: 'Top Speed', value: data.topSpeed ?? '—'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final progress = _totalDays > 0 ? _loadedDays / _totalDays : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation(_red),
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$_loadedDays / $_totalDays days',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyHeader() {
    return Row(
      children: [
        Text(
          'Daily Breakdown',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.grey[800],
          ),
        ),
        const Spacer(),
        Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${_dailyReports.length} days',
            style: const TextStyle(
                fontSize: 12, color: _red, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyDays() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.calendar_today_outlined,
              size: 44, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text('No daily data available',
              style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildDayCard(DayReport day) {
    final isWeekend = day.date.weekday == 6 || day.date.weekday == 7;
    final isToday = DateUtils.isSameDay(day.date, DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isToday ? _red : Colors.transparent,
          width: isToday ? 1.5 : 0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding:
          const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isToday
                  ? _red
                  : isWeekend
                  ? Colors.orange.withValues(alpha: 0.1)
                  : _red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  day.date.day.toString(),
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: isToday
                        ? Colors.white
                        : isWeekend
                        ? Colors.orange
                        : _red,
                  ),
                ),
                Text(
                  DateFormat('E').format(day.date),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isToday
                        ? Colors.white70
                        : isWeekend
                        ? Colors.orange
                        : _red,
                  ),
                ),
              ],
            ),
          ),
          title: Row(
            children: [
              Text(
                day.data.routeLength ?? '0 km',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 17),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'TODAY',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            'Moving: ${day.data.moveDuration ?? '—'}',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          trailing: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 22, color: Color(0xFFD32F2F)),
          children: [_buildDayDetails(day.data, day.date)],
        ),
      ),
    );
  }

  Widget _buildDayDetails(TodayReportData data, DateTime date) {
    return Column(
      children: [
        Divider(height: 1, color: Colors.grey[100]),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
                child: _MiniDetail(
                    label: 'Stop',
                    value: data.stopDuration ?? '—',
                    icon: Icons.local_parking_rounded)),
            Expanded(
                child: _MiniDetail(
                    label: 'Top',
                    value: data.topSpeed ?? '—',
                    icon: Icons.speed_rounded)),
            Expanded(
                child: _MiniDetail(
                    label: 'Avg',
                    value: data.averageSpeed ?? '—',
                    icon: Icons.trending_up_rounded)),
          ],
        ),
        if (data.engineHours != null || data.fuelConsumption != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if (data.engineHours != null)
                Expanded(
                    child: _MiniDetail(
                        label: 'Engine',
                        value: data.engineHours!,
                        icon: Icons.engineering_rounded)),
              if (data.fuelConsumption != null)
                Expanded(
                    child: _MiniDetail(
                        label: 'Fuel',
                        value: data.fuelConsumption!,
                        icon: Icons.local_gas_station_rounded)),
              if (data.engineHours == null || data.fuelConsumption == null)
                const Expanded(child: SizedBox()),
            ],
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _openPlayback(date),
            icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
            label: Text(
              'View Playback · ${DateFormat('dd MMM').format(date)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _NavBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFFD32F2F).withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
            size: 22,
            color: enabled
                ? const Color(0xFFD32F2F)
                : Colors.grey[300]),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style:
          TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
        ),
      ],
    );
  }
}

class _MiniDetail extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _MiniDetail(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              Text(
                value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
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