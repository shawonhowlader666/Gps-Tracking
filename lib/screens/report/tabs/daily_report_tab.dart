import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:gpspro/screens/report/get_today_report.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:intl/intl.dart';


class DailyReportTab extends StatefulWidget {
  final int deviceId;
  final String deviceName;

  const DailyReportTab({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  @override
  State<DailyReportTab> createState() => _DailyReportTabState();
}

class _DailyReportTabState extends State<DailyReportTab>
    with AutomaticKeepAliveClientMixin {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  TodayReportData? _reportData;
  String? _errorMessage;

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
    } catch (e) {
      log('Error loading report: $e');
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
            colorScheme: const ColorScheme.light(
              primary: CustomColor.primary,
            ),
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
      color: CustomColor.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Date Selector
          _buildDateSelector(),
          const SizedBox(height: 16),

          // Content
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildDateButton(
            icon: Icons.chevron_left,
            onTap: () {
              setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
              _loadReport();
            },
          ),
          Expanded(
            child: GestureDetector(
              onTap: _selectDate,
              child: Column(
                children: [
                  Text(
                    isToday ? 'Today' : DateFormat('EEEE').format(_selectedDate),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('dd MMM yyyy').format(_selectedDate),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildDateButton(
            icon: Icons.chevron_right,
            onTap: isToday
                ? null
                : () {
              setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
              _loadReport();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDateButton({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: onTap != null ? CustomColor.primary.withValues(alpha: 0.1) : Colors.grey.shade100,
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
          Text(
            _errorMessage!,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _loadReport,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'No data for this date',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try selecting a different date',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent() {
    final data = _reportData!;

    return Column(
      children: [
        // Main Stats - Distance & Duration
        _buildMainStatsCard(data),
        const SizedBox(height: 12),

        // Speed Stats
        _buildSpeedCard(data),
        const SizedBox(height: 12),

        // Engine Stats
        _buildEngineCard(data),
        const SizedBox(height: 12),

        // Other Stats
        _buildOtherStatsCard(data),
        const SizedBox(height: 12),

        // Route Info
        if (data.routeStart != null || data.routeEnd != null)
          _buildRouteCard(data),
      ],
    );
  }

  Widget _buildMainStatsCard(TodayReportData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [CustomColor.primary, Color(0xFFFF5252)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: CustomColor.primary.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFFFF5252).withValues(alpha: 0.15),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          // Distance
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.route, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text(
                data.routeLength ?? '0 km',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Total Distance',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          // Duration Row
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  'Moving',
                  data.moveDuration ?? '-',
                  Icons.directions_car,
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white24),
              Expanded(
                child: _buildMiniStat(
                  'Stopped',
                  data.stopDuration ?? '-',
                  Icons.local_parking,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildSpeedCard(TodayReportData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Speed', Icons.speed),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Top Speed',
                  data.topSpeed ?? '-',
                  const Color(0xFFE53935),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  'Avg Speed',
                  data.averageSpeed ?? '-',
                  const Color(0xFF43A047),
                ),
              ),
            ],
          ),
          if (data.overspeedCount != null && data.overspeedCount != '0') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 18, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Text(
                    'Overspeed: ${data.overspeedCount} times',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w500,
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
    final hasEngineData = data.engineHours != null ||
        data.engineWork != null ||
        data.engineIdle != null;

    if (!hasEngineData) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Engine', Icons.engineering),
          const SizedBox(height: 12),
          if (data.engineHours != null)
            _buildDataRow('Engine Hours', data.engineHours!),
          if (data.engineWork != null)
            _buildDataRow('Engine Work', data.engineWork!),
          if (data.engineIdle != null)
            _buildDataRow('Engine Idle', data.engineIdle!),
        ],
      ),
    );
  }

  Widget _buildOtherStatsCard(TodayReportData data) {
    final hasData = data.odometer != null || data.fuelConsumption != null;

    if (!hasData) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Other', Icons.info_outline),
          const SizedBox(height: 12),
          Row(
            children: [
              if (data.odometer != null)
                Expanded(
                  child: _buildStatItem(
                    'Odometer',
                    data.odometer!,
                    const Color(0xFFFF5252),
                  ),
                ),
              if (data.odometer != null && data.fuelConsumption != null)
                const SizedBox(width: 12),
              if (data.fuelConsumption != null)
                Expanded(
                  child: _buildStatItem(
                    'Fuel',
                    data.fuelConsumption!,
                    const Color(0xFFFF7043),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(TodayReportData data) {
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
          _buildSectionHeader('Route', Icons.map_outlined),
          const SizedBox(height: 12),
          if (data.routeStart != null)
            _buildRoutePoint('Start', data.routeStart!, const Color(0xFF43A047)),
          if (data.routeStart != null && data.routeEnd != null)
            Container(
              margin: const EdgeInsets.only(left: 11),
              height: 20,
              child: VerticalDivider(
                color: Colors.grey[300],
                thickness: 2,
              ),
            ),
          if (data.routeEnd != null)
            _buildRoutePoint('End', data.routeEnd!, const Color(0xFFE53935)),
        ],
      ),
    );
  }

  Widget _buildRoutePoint(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            label == 'Start' ? Icons.play_arrow : Icons.stop,
            size: 14,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: CustomColor.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: CustomColor.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}