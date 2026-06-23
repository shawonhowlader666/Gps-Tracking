import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:smart_lock/screens/report/get_today_report.dart';

/// MileageReportScreen
/// Shows a 7-day bar chart of daily mileage + a custom date-range KM report.
/// Usage: Navigator.push(context, MaterialPageRoute(builder: (_) => MileageReportScreen(deviceId: device.id)));
class MileageReportScreen extends StatefulWidget {
  final int deviceId;
  final String? deviceName;

  const MileageReportScreen({
    super.key,
    required this.deviceId,
    this.deviceName,
  });

  @override
  State<MileageReportScreen> createState() => _MileageReportScreenState();
}

class _MileageReportScreenState extends State<MileageReportScreen> {
  // ── Colors ─────────────────────────────────────────────────────────────────
  static const Color _red = Color(0xFFE53935);
  static const Color _green = Color(0xFF43A047);
  static const Color _cardBg = Colors.white;
  static const Color _pageBg = Color(0xFFF2F2F2);

  // ── State ──────────────────────────────────────────────────────────────────
  bool _loadingChart = true;
  bool _loadingCustom = false;

  /// Daily mileage for the last 7 days  {date-label -> km}
  final List<_DayMileage> _weekData = [];

  DateTime? _fromDate;
  DateTime? _toDate;
  double? _customTotalKm;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadWeekData();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  /// Fetch last-7-days mileage by calling ReportService for each day.
  Future<void> _loadWeekData() async {
    setState(() => _loadingChart = true);
    _weekData.clear();

    final today = DateTime.now();

    for (int i = 6; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      try {
        final data = await ReportService.getTodayReportDataWithDates(
          deviceId: widget.deviceId,
          fromDate: DateTime(day.year, day.month, day.day),
          toDate: DateTime(day.year, day.month, day.day, 23, 59, 59),
        );

        double km = 0;
        if (data.routeLength != null && data.routeLength!.isNotEmpty) {
          // e.g. "52.12 Km" or "52.12"
          final numStr = data.routeLength!.replaceAll(RegExp(r'[^0-9.]'), '');
          km = double.tryParse(numStr) ?? 0;
        }

        _weekData.add(_DayMileage(
          label: _dayLabel(day),
          fullLabel: _fullDateLabel(day),
          km: km,
        ));
      } catch (e) {
        log('⚠️ MileageReportScreen: error for day $day – $e');
        _weekData.add(_DayMileage(
          label: _dayLabel(day),
          fullLabel: _fullDateLabel(day),
          km: 0,
        ));
      }
    }

    if (mounted) setState(() => _loadingChart = false);
  }

  /// Fetch custom range total mileage.
  Future<void> _loadCustomReport() async {
    if (_fromDate == null || _toDate == null) return;

    setState(() {
      _loadingCustom = true;
      _customTotalKm = null;
    });

    try {
      final data = await ReportService.getTodayReportDataWithDates(
        deviceId: widget.deviceId,
        fromDate: _fromDate!,
        toDate: _toDate!,
        forceRefresh: true,
      );

      double km = 0;
      if (data.routeLength != null && data.routeLength!.isNotEmpty) {
        final numStr = data.routeLength!.replaceAll(RegExp(r'[^0-9.]'), '');
        km = double.tryParse(numStr) ?? 0;
      }

      if (mounted) {
        setState(() {
          _customTotalKm = km;
          _loadingCustom = false;
        });
      }
    } catch (e) {
      log('❌ MileageReportScreen custom report error: $e');
      if (mounted) {
        setState(() {
          _customTotalKm = 0;
          _loadingCustom = false;
        });
      }
    }
  }

  // ── Date helpers ──────────────────────────────────────────────────────────
  String _dayLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  String _fullDateLabel(DateTime d) => _dayLabel(d);

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => _redTheme(ctx, child),
    );
    if (picked == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _fromDate?.hour ?? 0,
        minute: _fromDate?.minute ?? 0,
      ),
      builder: (ctx, child) => _redTheme(ctx, child),
    );

    setState(() {
      _fromDate = DateTime(
        picked.year, picked.month, picked.day,
        time?.hour ?? 0, time?.minute ?? 0,
      );
      _customTotalKm = null;
    });
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (ctx, child) => _redTheme(ctx, child),
    );
    if (picked == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _toDate?.hour ?? 23,
        minute: _toDate?.minute ?? 59,
      ),
      builder: (ctx, child) => _redTheme(ctx, child),
    );

    setState(() {
      _toDate = DateTime(
        picked.year, picked.month, picked.day,
        time?.hour ?? 23, time?.minute ?? 59,
      );
      _customTotalKm = null;
    });
  }

  Widget _redTheme(BuildContext ctx, Widget? child) => Theme(
    data: Theme.of(ctx).copyWith(
      colorScheme: const ColorScheme.light(primary: _red),
    ),
    child: child!,
  );

  String _formatDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$d-$mo-${dt.year}  $h:$mi';
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: const Text(
          'Mileage Report',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: _red,
        onRefresh: _loadWeekData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ── Chart card ─────────────────────────────────────────────
              _ChartCard(
                loading: _loadingChart,
                data: _weekData,
                barColor: _green,
              ),
              const SizedBox(height: 16),
              // ── Custom range card ──────────────────────────────────────
              _CustomRangeCard(
                fromDate: _fromDate,
                toDate: _toDate,
                totalKm: _customTotalKm,
                loading: _loadingCustom,
                onPickFrom: _pickFrom,
                onPickTo: _pickTo,
                onFetch: _loadCustomReport,
                formatDateTime: _formatDateTime,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Chart Card ────────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final bool loading;
  final List<_DayMileage> data;
  final Color barColor;

  const _ChartCard({
    required this.loading,
    required this.data,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        children: [
          const Text(
            'Last 7 Days Mileage (km)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          if (loading)
            const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator(color: Color(0xFFE53935))),
            )
          else
            SizedBox(
              height: 220,
              child: _BarChart(data: data, barColor: barColor),
            ),
        ],
      ),
    );
  }
}

// ── Bar Chart ─────────────────────────────────────────────────────────────────

class _BarChart extends StatelessWidget {
  final List<_DayMileage> data;
  final Color barColor;

  const _BarChart({required this.data, required this.barColor});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(
        child: Text('No data available', style: TextStyle(color: Colors.grey)),
      );
    }

    final maxKm = data.map((e) => e.km).fold(0.0, (a, b) => a > b ? a : b);
    // Nice rounded ceiling for Y axis
    final yMax = maxKm == 0 ? 150.0 : _roundUp(maxKm * 1.2);

    return LayoutBuilder(builder: (ctx, constraints) {
      final chartWidth = constraints.maxWidth;
      final chartHeight = constraints.maxHeight;
      const labelHeight = 36.0; // room for x-axis date labels
      const valueHeight = 20.0; // room for value above bar
      const yAxisWidth = 40.0;
      final barAreaHeight = chartHeight - labelHeight - valueHeight;
      final barAreaWidth = chartWidth - yAxisWidth;
      final barSlotWidth = barAreaWidth / data.length;
      final barWidth = barSlotWidth * 0.55;

      return CustomPaint(
        size: Size(chartWidth, chartHeight),
        painter: _GridPainter(
          yMax: yMax,
          yAxisWidth: yAxisWidth,
          barAreaHeight: barAreaHeight,
          valueHeight: valueHeight,
        ),
        child: Stack(
          children: [
            // Y-axis labels
            ..._buildYLabels(yMax, yAxisWidth, barAreaHeight, valueHeight),
            // Bars + value labels + date labels
            ...List.generate(data.length, (i) {
              final item = data[i];
              final barH = maxKm == 0 ? 0.0 : (item.km / yMax) * barAreaHeight;
              final left = yAxisWidth + i * barSlotWidth + (barSlotWidth - barWidth) / 2;
              final top = valueHeight + (barAreaHeight - barH);

              return Stack(
                children: [
                  // Bar
                  Positioned(
                    left: left,
                    top: top,
                    width: barWidth,
                    height: barH.clamp(2.0, barAreaHeight),
                    child: Container(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  ),
                  // Value label above bar
                  Positioned(
                    left: left - 8,
                    top: top - 18,
                    width: barWidth + 16,
                    child: Text(
                      item.km == 0 ? '0' : item.km.toStringAsFixed(2),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  // Date label below
                  Positioned(
                    left: left - 8,
                    top: valueHeight + barAreaHeight + 4,
                    width: barWidth + 16,
                    child: Text(
                      item.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 8.5, color: Colors.black54),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      );
    });
  }

  List<Widget> _buildYLabels(
      double yMax, double yAxisWidth, double barAreaHeight, double valueHeight) {
    const steps = 3;
    return List.generate(steps + 1, (i) {
      final value = (yMax / steps * (steps - i)).round();
      final top = valueHeight + (i / steps) * barAreaHeight - 8;
      return Positioned(
        left: 0,
        top: top,
        width: yAxisWidth - 4,
        child: Text(
          value.toString(),
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 10, color: Colors.black45),
        ),
      );
    });
  }

  double _roundUp(double v) {
    if (v <= 0) return 150;
    final mag = (v / 50).ceil() * 50;
    return mag.toDouble();
  }
}

double _roundUp(double v) {
  if (v <= 0) return 150;
  return ((v / 50).ceil() * 50).toDouble();
}

class _GridPainter extends CustomPainter {
  final double yMax;
  final double yAxisWidth;
  final double barAreaHeight;
  final double valueHeight;

  _GridPainter({
    required this.yMax,
    required this.yAxisWidth,
    required this.barAreaHeight,
    required this.valueHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.18)
      ..strokeWidth = 1;

    const steps = 3;
    for (int i = 0; i <= steps; i++) {
      final y = valueHeight + (i / steps) * barAreaHeight;
      canvas.drawLine(Offset(yAxisWidth, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => false;
}

// ── Custom Range Card ─────────────────────────────────────────────────────────

class _CustomRangeCard extends StatelessWidget {
  final DateTime? fromDate;
  final DateTime? toDate;
  final double? totalKm;
  final bool loading;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onFetch;
  final String Function(DateTime) formatDateTime;

  const _CustomRangeCard({
    required this.fromDate,
    required this.toDate,
    required this.totalKm,
    required this.loading,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onFetch,
    required this.formatDateTime,
  });

  static const Color _red = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // From
          const Text(
            'From Data & Time',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          _DateButton(
            label: fromDate != null ? formatDateTime(fromDate!) : 'From Date & Time',
            onTap: onPickFrom,
            selected: fromDate != null,
          ),
          const SizedBox(height: 16),

          // To
          const Text(
            'To Data & Time',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          _DateButton(
            label: toDate != null ? formatDateTime(toDate!) : 'To Date & Time',
            onTap: onPickTo,
            selected: toDate != null,
          ),
          const SizedBox(height: 20),

          // KM Report button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              onPressed: (fromDate != null && toDate != null && !loading) ? onFetch : null,
              child: loading
                  ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
                  : const Text(
                'KM Report',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Total mileage
          Center(
            child: Text(
              'Total Mileage: ${totalKm != null ? '${totalKm!.toStringAsFixed(2)} km' : '0.00 km'}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool selected;

  const _DateButton({
    required this.label,
    required this.onTap,
    required this.selected,
  });

  static const Color _red = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          border: Border.all(color: _red, width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: _red,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ── Model ─────────────────────────────────────────────────────────────────────

class _DayMileage {
  final String label;     // "08-05-2026"
  final String fullLabel;
  final double km;

  _DayMileage({required this.label, required this.fullLabel, required this.km});
}