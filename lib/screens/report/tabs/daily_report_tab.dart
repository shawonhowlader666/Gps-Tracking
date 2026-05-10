// lib/screens/report/tabs/daily_report_tab.dart

import 'package:flutter/material.dart';
import 'package:smart_lock/screens/report/get_today_report.dart';
import 'package:intl/intl.dart';

class DailyReportTab extends StatefulWidget {
  final int deviceId;
  final String deviceName;

  const DailyReportTab({
    Key? key,
    required this.deviceId,
    required this.deviceName,
  }) : super(key: key);

  @override
  State<DailyReportTab> createState() => _DailyReportTabState();
}

class _DailyReportTabState extends State<DailyReportTab>
    with AutomaticKeepAliveClientMixin {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  TodayReportData? _reportData;
  String? _errorMessage;

  static const _red = Color(0xFFD32F2F);
  static const _deepRed = Color(0xFFB71C1C);
  static const _lightRed = Color(0xFFEF5350);
  static const _surface = Color(0xFFFFFFFF);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final report = await ReportService.getReportForPeriod(
        deviceId: widget.deviceId,
        period: ReportPeriod.custom,
        customStart: DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        ),
        customEnd: DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          23,
          59,
          59,
        ),
        forceRefresh: true,
      );

      setState(() {
        _reportData = report;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load report';
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: _red),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadReport();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return RefreshIndicator(
      onRefresh: _loadReport,
      color: _red,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          _buildDateSelector(),
          const SizedBox(height: 20),
          if (_isLoading)
            _buildLoadingState()
          else if (_errorMessage != null)
            _buildErrorState()
          else if (_reportData == null || _reportData!.isEmpty)
              _buildEmptyState()
            else
              _buildReportContent(),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: _surface,
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
          _buildNavBtn(Icons.chevron_left_rounded, () {
            setState(() =>
            _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
            _loadReport();
          }),
          Expanded(
            child: GestureDetector(
              onTap: _selectDate,
              child: Column(
                children: [
                  Text(
                    isToday ? 'Today' : DateFormat('EEEE').format(_selectedDate),
                    style: TextStyle(
                      fontSize: 12,
                      color: isToday ? _red : Colors.grey[500],
                      fontWeight:
                      isToday ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('dd MMM yyyy').format(_selectedDate),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.expand_more_rounded,
                          size: 18, color: Colors.grey[400]),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _buildNavBtn(
            Icons.chevron_right_rounded,
            isToday
                ? null
                : () {
              setState(() => _selectedDate =
                  _selectedDate.add(const Duration(days: 1)));
              _loadReport();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavBtn(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled
              ? _red.withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
            size: 22, color: enabled ? _red : Colors.grey[300]),
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
    return _ReportPlaceholder(
      icon: Icons.wifi_off_rounded,
      iconColor: Colors.red[300]!,
      title: 'Connection Error',
      subtitle: _errorMessage!,
      action: TextButton.icon(
        onPressed: _loadReport,
        icon: const Icon(Icons.refresh_rounded, size: 18, color: _red),
        label: const Text('Retry', style: TextStyle(color: _red)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return _ReportPlaceholder(
      icon: Icons.inbox_outlined,
      iconColor: Colors.grey[400]!,
      title: 'No Data Available',
      subtitle: 'No activity recorded for this date',
    );
  }

  Widget _buildReportContent() {
    final data = _reportData!;
    return Column(
      children: [
        _buildHeroCard(data),
        const SizedBox(height: 16),
        _buildSpeedCard(data),
        const SizedBox(height: 16),
        if (data.engineHours != null ||
            data.engineWork != null ||
            data.engineIdle != null) ...[
          _buildEngineCard(data),
          const SizedBox(height: 16),
        ],
        if (data.odometer != null || data.fuelConsumption != null) ...[
          _buildOtherCard(data),
          const SizedBox(height: 16),
        ],
        if (data.routeStart != null || data.routeEnd != null)
          _buildRouteCard(data),
      ],
    );
  }

  Widget _buildHeroCard(TodayReportData data) {
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
          // Distance
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.route_rounded,
                  color: Colors.white.withValues(alpha: 0.7), size: 22),
              const SizedBox(width: 10),
              Text(
                data.routeLength ?? '0 km',
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Total Distance',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                  child: _buildMiniStat(
                      'Moving',
                      data.moveDuration ?? '—',
                      Icons.directions_car_rounded)),
              Container(
                  width: 1,
                  height: 44,
                  color: Colors.white.withValues(alpha: 0.2)),
              Expanded(
                  child: _buildMiniStat(
                      'Stopped',
                      data.stopDuration ?? '—',
                      Icons.local_parking_rounded)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.65), size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildSpeedCard(TodayReportData data) {
    return _InfoCard(
      title: 'Speed',
      icon: Icons.speed_rounded,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _StatTile(
                      label: 'Top Speed',
                      value: data.topSpeed ?? '—',
                      color: _red)),
              const SizedBox(width: 12),
              Expanded(
                  child: _StatTile(
                      label: 'Avg Speed',
                      value: data.averageSpeed ?? '—',
                      color: const Color(0xFF43A047))),
            ],
          ),
          if (data.overspeedCount != null && data.overspeedCount != '0') ...[
            const SizedBox(height: 12),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: Colors.orange[700]),
                  const SizedBox(width: 10),
                  Text(
                    'Overspeed detected: ${data.overspeedCount} times',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEngineCard(TodayReportData data) {
    return _InfoCard(
      title: 'Engine',
      icon: Icons.engineering_rounded,
      child: Column(
        children: [
          if (data.engineHours != null)
            _DataRow(label: 'Engine Hours', value: data.engineHours!),
          if (data.engineWork != null)
            _DataRow(label: 'Engine Work', value: data.engineWork!),
          if (data.engineIdle != null)
            _DataRow(label: 'Engine Idle', value: data.engineIdle!, last: true),
        ],
      ),
    );
  }

  Widget _buildOtherCard(TodayReportData data) {
    return _InfoCard(
      title: 'Other',
      icon: Icons.info_outline_rounded,
      child: Row(
        children: [
          if (data.odometer != null)
            Expanded(
                child: _StatTile(
                    label: 'Odometer',
                    value: data.odometer!,
                    color: const Color(0xFF5C6BC0))),
          if (data.odometer != null && data.fuelConsumption != null)
            const SizedBox(width: 12),
          if (data.fuelConsumption != null)
            Expanded(
                child: _StatTile(
                    label: 'Fuel',
                    value: data.fuelConsumption!,
                    color: const Color(0xFFFF7043))),
        ],
      ),
    );
  }

  Widget _buildRouteCard(TodayReportData data) {
    return _InfoCard(
      title: 'Route',
      icon: Icons.map_outlined,
      child: Column(
        children: [
          if (data.routeStart != null)
            _RoutePoint(
                label: 'Start',
                value: data.routeStart!,
                color: const Color(0xFF43A047)),
          if (data.routeStart != null && data.routeEnd != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: SizedBox(
                height: 22,
                child: VerticalDivider(
                    color: Colors.grey[300], thickness: 1.5),
              ),
            ),
          if (data.routeEnd != null)
            _RoutePoint(
                label: 'End', value: data.routeEnd!, color: _red),
        ],
      ),
    );
  }
}

// ─── Shared Widgets ────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _InfoCard(
      {required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFD32F2F).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: const Color(0xFFD32F2F)),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatTile(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  final bool last;

  const _DataRow(
      {required this.label, required this.value, this.last = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style:
                  TextStyle(fontSize: 13, color: Colors.grey[600])),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
        ),
        if (!last)
          Divider(height: 1, color: Colors.grey[100]),
      ],
    );
  }
}

class _RoutePoint extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _RoutePoint(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            label == 'Start'
                ? Icons.play_arrow_rounded
                : Icons.stop_rounded,
            size: 16,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                  TextStyle(fontSize: 11, color: Colors.grey[500])),
              Text(
                value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReportPlaceholder extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? action;

  const _ReportPlaceholder({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 44, color: iconColor),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}