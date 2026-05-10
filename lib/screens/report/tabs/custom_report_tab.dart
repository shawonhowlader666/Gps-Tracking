// lib/screens/report/tabs/custom_report_tab.dart

import 'package:flutter/material.dart';
import 'package:smart_lock/screens/report/get_today_report.dart';
import 'package:intl/intl.dart';

class CustomReportTab extends StatefulWidget {
  final int deviceId;
  final String deviceName;
  final String? presetPeriod;

  const CustomReportTab({
    Key? key,
    required this.deviceId,
    required this.deviceName,
    this.presetPeriod,
  }) : super(key: key);

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
  String? _activePreset;

  static const _red = Color(0xFFD32F2F);
  static const _deepRed = Color(0xFFB71C1C);
  static const _lightRed = Color(0xFFEF5350);

  @override
  bool get wantKeepAlive => true;

  final List<_Preset> _presets = [
    _Preset('Today', 'today', Icons.wb_sunny_rounded),
    _Preset('Yesterday', 'yesterday', Icons.history_rounded),
    _Preset('This Week', 'thisWeek', Icons.view_week_rounded),
    _Preset('This Month', 'thisMonth', Icons.calendar_month_rounded),
    _Preset('Last 7 Days', 'last7days', Icons.date_range_rounded),
    _Preset('Last 30 Days', 'last30days', Icons.date_range_rounded),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.presetPeriod != null) {
      _applyPreset(widget.presetPeriod!);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _generateReport());
    }
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    setState(() => _activePreset = preset);
    switch (preset) {
      case 'today':
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = now;
        break;
      case 'yesterday':
        final y = now.subtract(const Duration(days: 1));
        _startDate = DateTime(y.year, y.month, y.day);
        _endDate = DateTime(y.year, y.month, y.day, 23, 59, 59);
        break;
      case 'thisWeek':
        final mon = now.subtract(Duration(days: now.weekday - 1));
        _startDate = DateTime(mon.year, mon.month, mon.day);
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
    } catch (_) {
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
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _red),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _activePreset = null;
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
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        _buildPresetsSection(),
        const SizedBox(height: 20),
        _buildDateRangeCard(),
        const SizedBox(height: 20),
        _buildGenerateButton(),
        const SizedBox(height: 20),
        if (_isLoading)
          const SizedBox(
            height: 200,
            child: Center(
                child: CircularProgressIndicator(
                    color: _red, strokeWidth: 2.5)),
          )
        else if (_errorMessage != null)
          _buildErrorState()
        else if (_reportData != null && _reportData!.isNotEmpty)
            _buildResults(),
      ],
    );
  }

  Widget _buildPresetsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Select',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey[600],
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _presets
              .map((p) => _buildPresetChip(p))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildPresetChip(_Preset preset) {
    final isActive = _activePreset == preset.key;
    return GestureDetector(
      onTap: () {
        _applyPreset(preset.key);
        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? _red : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isActive ? _red : Colors.grey.withValues(alpha: 0.2)),
          boxShadow: isActive
              ? [
            BoxShadow(
              color: _red.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 3),
            )
          ]
              : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              preset.icon,
              size: 14,
              color: isActive ? Colors.white : Colors.grey[600],
            ),
            const SizedBox(width: 6),
            Text(
              preset.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeCard() {
    final days = _endDate.difference(_startDate).inDays + 1;

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
        children: [
          Row(
            children: [
              Expanded(
                  child: _DatePickerBox(
                    label: 'From',
                    date: _startDate,
                    onTap: () => _selectDate(true),
                  )),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 18, color: Colors.grey[400]),
              ),
              Expanded(
                  child: _DatePickerBox(
                    label: 'To',
                    date: _endDate,
                    onTap: () => _selectDate(false),
                  )),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: _red.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.date_range_rounded, size: 16, color: _red),
                const SizedBox(width: 8),
                Text(
                  '$days day${days > 1 ? 's' : ''} selected',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _generateReport,
        style: ElevatedButton.styleFrom(
          backgroundColor: _red,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _red.withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          shadowColor: _red.withValues(alpha: 0.4),
        ),
        child: _isLoading
            ? Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(
              'Generating...',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        )
            : Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.analytics_rounded, size: 20),
            SizedBox(width: 10),
            Text(
              'Generate Report',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 44, color: Colors.red[300]),
          const SizedBox(height: 12),
          Text(_errorMessage!,
              style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _generateReport,
            icon: const Icon(Icons.refresh_rounded, size: 18, color: _red),
            label: const Text('Retry', style: TextStyle(color: _red)),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final data = _reportData!;

    return Container(
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
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_deepRed, _lightRed],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
              BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.assessment_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Report Results',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${DateFormat('dd MMM').format(_startDate)} – ${DateFormat('dd MMM yy').format(_endDate)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Data rows
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (data.routeLength != null)
                  _ResultRow('Distance', data.routeLength!,
                      Icons.route_rounded, const Color(0xFF3F51B5)),
                if (data.moveDuration != null)
                  _ResultRow('Move Duration', data.moveDuration!,
                      Icons.directions_car_rounded,
                      const Color(0xFF43A047)),
                if (data.stopDuration != null)
                  _ResultRow('Stop Duration', data.stopDuration!,
                      Icons.local_parking_rounded,
                      const Color(0xFFFF9800)),
                if (data.topSpeed != null)
                  _ResultRow('Top Speed', data.topSpeed!,
                      Icons.speed_rounded, _red),
                if (data.averageSpeed != null)
                  _ResultRow('Avg Speed', data.averageSpeed!,
                      Icons.trending_up_rounded,
                      const Color(0xFF00BCD4)),
                if (data.engineHours != null)
                  _ResultRow('Engine Hours', data.engineHours!,
                      Icons.engineering_rounded,
                      const Color(0xFF9C27B0)),
                if (data.fuelConsumption != null)
                  _ResultRow('Fuel', data.fuelConsumption!,
                      Icons.local_gas_station_rounded,
                      const Color(0xFFFF7043)),
                if (data.odometer != null)
                  _ResultRow('Odometer', data.odometer!,
                      Icons.speed_rounded, const Color(0xFF5C6BC0)),
                if (data.overspeedCount != null &&
                    data.overspeedCount != '0')
                  _ResultRow('Overspeed',
                      '${data.overspeedCount} times',
                      Icons.warning_amber_rounded,
                      const Color(0xFFE91E63),
                      last: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────

class _Preset {
  final String label;
  final String key;
  final IconData icon;
  const _Preset(this.label, this.key, this.icon);
}

class _DatePickerBox extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DatePickerBox(
      {required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey[500])),
            const SizedBox(height: 5),
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 14, color: Color(0xFFD32F2F)),
                const SizedBox(width: 6),
                Text(
                  DateFormat('dd MMM yy').format(date),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool last;

  const _ResultRow(this.label, this.value, this.icon, this.color,
      {this.last = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14, color: Colors.grey[700])),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
        ),
        if (!last) Divider(height: 1, color: Colors.grey[100]),
      ],
    );
  }
}