import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/screens/report/get_today_report.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/util/app_lang.dart';

// Persisted settings keys (global so one setting applies to all user vehicles)
String _priceKey([int? id]) => 'global_fuel_price';
String _rateKey([int? id])  => 'global_fuel_rate';

class DeviceFuelScreen extends StatefulWidget {
  final DeviceItem device;
  const DeviceFuelScreen({super.key, required this.device});

  @override
  State<DeviceFuelScreen> createState() => _DeviceFuelScreenState();
}

enum _Period { today, thisWeek, thisMonth, custom }

class _DeviceFuelScreenState extends State<DeviceFuelScreen> {
  // ── settings controllers ────────────────────────────────────────────────────
  late TextEditingController _priceCtrl;
  late TextEditingController _rateCtrl;
  bool _isSaving = false;

  // ── period / report ─────────────────────────────────────────────────────────
  _Period _period = _Period.today;
  DateTime? _customStart;
  DateTime? _customEnd;

  bool _isLoadingReport = true;
  String? _errorMsg;
  TodayReportData? _reportData;

  // local fuel price & rate (persisted or from server)
  double _fuelPrice = 0;
  double _fuelRate  = 0; // L / 100 km

  // ── breakdown ───────────────────────────────────────────────────────────────
  List<DayReport> _breakdown = [];
  bool _isLoadingBreakdown = false;

  // ── colours ─────────────────────────────────────────────────────────────────
  static const _red    = Color(0xFFCC0000);
  static const _gold   = Color(0xFFD99E30);
  static const _blue   = Color(0xFF2563EB);
  static const _green  = Color(0xFF16A34A);
  static const _border = Color(0xFFE5E7EB);

  // Raw API report data (unchanged) - used for live recalculation
  TodayReportData? _rawReportData;
  List<DayReport> _rawBreakdown = [];

  // ────────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController();
    _rateCtrl  = TextEditingController();
    // Live recalculate whenever user types without pressing Save
    _priceCtrl.addListener(_onSettingsChanged);
    _rateCtrl.addListener(_onSettingsChanged);
    _loadSettings();
  }

  @override
  void dispose() {
    _priceCtrl.removeListener(_onSettingsChanged);
    _rateCtrl.removeListener(_onSettingsChanged);
    _priceCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  // Called whenever price or rate field changes — recompute live & auto-persist
  void _onSettingsChanged() {
    final newPrice = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    final newRate  = double.tryParse(_rateCtrl.text.trim())  ?? 0;
    if (newPrice == _fuelPrice && newRate == _fuelRate) return;
    _fuelPrice = newPrice;
    _fuelRate  = newRate;

    // Immediately persist locally on change so leaving page preserves values!
    SharedPreferences.getInstance().then((prefs) {
      final devId = widget.device.id!;
      prefs.setString(_priceKey(devId), _priceCtrl.text.trim());
      prefs.setString(_rateKey(devId),  _rateCtrl.text.trim());
    });

    // Recompute main stat from stored raw data
    if (_rawReportData != null) {
      setState(() {
        _reportData = _recomputeFuel(_rawReportData!);
        // Recompute breakdown rows too
        _breakdown = _rawBreakdown
            .map((d) => DayReport(date: d.date, data: _recomputeFuel(d.data)))
            .toList();
      });
    }
  }

  // ── load persisted settings (local first, then server fallback) ─────────────
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final devId = widget.device.id!;

    // 1. Try locally saved value (user explicitly set or typed)
    String priceStr = prefs.getString(_priceKey(devId)) ?? '';
    String rateStr  = prefs.getString(_rateKey(devId))  ?? '';

    // 2. Fall back to server value if nothing local
    if (priceStr.isEmpty || priceStr == '0') priceStr = widget.device.deviceData?.fuelPrice ?? '';
    if (rateStr.isEmpty  || rateStr == '0')  rateStr  = widget.device.deviceData?.fuelPerKm  ?? '';

    _fuelPrice = double.tryParse(priceStr) ?? 0;
    _fuelRate  = double.tryParse(rateStr)  ?? 0;

    String formatCleanNumber(double val, String original) {
      if (val <= 0) return '';
      if (val == val.toInt()) {
        return val.toInt().toString();
      }
      return val.toString();
    }

    _priceCtrl.removeListener(_onSettingsChanged);
    _rateCtrl.removeListener(_onSettingsChanged);

    _priceCtrl.text = formatCleanNumber(_fuelPrice, priceStr);
    _rateCtrl.text  = formatCleanNumber(_fuelRate, rateStr);

    _priceCtrl.addListener(_onSettingsChanged);
    _rateCtrl.addListener(_onSettingsChanged);

    if (mounted) setState(() {});
    _loadReport();
  }

  // ── save settings both locally and to server ────────────────────────────────
  Future<void> _saveSettings() async {
    FocusScope.of(context).unfocus();
    final priceStr = _priceCtrl.text.trim();
    final rateStr  = _rateCtrl.text.trim();

    final newPrice = double.tryParse(priceStr) ?? 0;
    final newRate  = double.tryParse(rateStr)  ?? 0;

    if (newPrice <= 0 || newRate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter valid Fuel Price and Rate'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1. Persist locally (survives restarts)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_priceKey(widget.device.id!), priceStr);
      await prefs.setString(_rateKey(widget.device.id!),  rateStr);

      // 2. Send to WOX server
      final res = await APIService.editDevice({
        'name':                widget.device.name ?? '',
        'fuel_measurement_id': '1',
        'fuel_price':          priceStr,
        'fuel_per_km':         rateStr,
        'device_id':           widget.device.id.toString(),
      });

      // 3. Update in-memory device object
      widget.device.deviceData?.fuelPrice = priceStr;
      widget.device.deviceData?.fuelPerKm  = rateStr;
      _fuelPrice = newPrice;
      _fuelRate  = newRate;

      // 4. Refresh global device list so home screen updates
      Get.find<DataController>().getDevices();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.statusCode == 200 ? 'settingsSaved'.tr : 'savedLocallyOnly'.tr),
          backgroundColor: res.statusCode == 200 ? Colors.green : Colors.orange,
        ));
        // Recalculate with new settings
        _loadReport();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to save settings'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── date range helpers ──────────────────────────────────────────────────────
  (DateTime, DateTime) _dateRange() {
    final now = DateTime.now();
    switch (_period) {
      case _Period.today:
        return (DateTime(now.year, now.month, now.day),
                DateTime(now.year, now.month, now.day, 23, 59, 59));
      case _Period.thisWeek:
        final start = now.subtract(Duration(days: now.weekday - 1));
        return (DateTime(start.year, start.month, start.day),
                DateTime(now.year, now.month, now.day, 23, 59, 59));
      case _Period.thisMonth:
        return (DateTime(now.year, now.month, 1),
                DateTime(now.year, now.month, now.day, 23, 59, 59));
      case _Period.custom:
        final s = _customStart ?? DateTime(now.year, now.month, now.day);
        final e = _customEnd   ?? DateTime(now.year, now.month, now.day, 23, 59, 59);
        return (s, DateTime(e.year, e.month, e.day, 23, 59, 59));
    }
  }

  // ── load report ─────────────────────────────────────────────────────────────
  Future<void> _loadReport() async {
    setState(() {
      _isLoadingReport = true;
      _errorMsg        = null;
      _reportData      = null;
      _breakdown       = [];
    });

    try {
      final (start, end) = _dateRange();
      final data = await ReportService.getTodayReportDataWithDates(
        deviceId:    widget.device.id!,
        fromDate:    start,
        toDate:      end,
        device:      widget.device,
        forceRefresh: true,
      );

      // Recalculate fuel cost using locally persisted price/rate
      final recomputed = _recomputeFuel(data);

      setState(() {
        _rawReportData   = data;          // keep raw API data
        _reportData      = recomputed;
        _isLoadingReport = false;
      });

      if (_period == _Period.thisWeek || _period == _Period.thisMonth || _period == _Period.custom) {
        _loadBreakdown(start, end);
      }
    } catch (e) {
      setState(() {
        _isLoadingReport = false;
        _errorMsg        = 'Failed to load report';
      });
    }
  }

  // Re-compute fuel litres & cost from routeLength using local settings
  TodayReportData _recomputeFuel(TodayReportData d) {
    final distKm = double.tryParse(
        (d.routeLength ?? '0').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;

    final litres = _fuelRate > 0 ? (distKm * _fuelRate) / 100.0 : 0.0;
    final cost   = (_fuelRate > 0 && _fuelPrice > 0) ? litres * _fuelPrice : 0.0;

    return TodayReportData(
      device:          d.device,
      routeStart:      d.routeStart,
      routeEnd:        d.routeEnd,
      routeLength:     d.routeLength ?? '0 km',
      moveDuration:    d.moveDuration,
      stopDuration:    d.stopDuration,
      topSpeed:        d.topSpeed,
      averageSpeed:    d.averageSpeed,
      overspeedCount:  d.overspeedCount,
      engineHours:     d.engineHours,
      engineWork:      d.engineWork,
      engineIdle:      d.engineIdle,
      odometer:        d.odometer,
      fuelConsumption: '${litres.toStringAsFixed(2)} L',
      fuelLitres:      litres.toStringAsFixed(2),
      fuelCost:        _fuelPrice > 0 ? '৳ ${cost.toStringAsFixed(2)}' : '—',
      totalPoints:     d.totalPoints,
    );
  }

  // ── daily breakdown for multi-day periods ────────────────────────────────────
  Future<void> _loadBreakdown(DateTime rangeStart, DateTime rangeEnd) async {
    setState(() {
      _isLoadingBreakdown = true;
      _breakdown          = [];
      _rawBreakdown       = [];
    });

    try {
      final dates = <DateTime>[];
      var cur = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
      final endDay = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
      while (!cur.isAfter(endDay)) {
        dates.insert(0, cur); // newest first
        cur = cur.add(const Duration(days: 1));
      }

      const batch = 3;
      final rawTmp = <DayReport>[];  // raw API data
      final cmpTmp = <DayReport>[];  // computed with fuel settings
      for (int i = 0; i < dates.length; i += batch) {
        final slice = dates.skip(i).take(batch);
        final results = await Future.wait(slice.map(_fetchDay));
        for (final r in results) {
          if (r != null) {
            rawTmp.add(r);                                          // store raw
            cmpTmp.add(DayReport(date: r.date, data: _recomputeFuel(r.data))); // computed
          }
        }
        if (!mounted) return;
        setState(() {
          _rawBreakdown = List.from(rawTmp);
          _breakdown    = List.from(cmpTmp);
        });
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoadingBreakdown = false);
  }

  // Returns raw API day report (without fuel applied) for caching
  Future<DayReport?> _fetchDay(DateTime date) async {
    try {
      final d = await ReportService.getTodayReportDataWithDates(
        deviceId: widget.device.id!,
        device:   widget.device,
        fromDate: DateTime(date.year, date.month, date.day),
        toDate:   DateTime(date.year, date.month, date.day, 23, 59, 59),
      );
      if (d.isNotEmpty) return DayReport(date: date, data: d); // raw, no fuel
    } catch (_) {}
    return null;
  }

  // ── custom date picker ──────────────────────────────────────────────────────
  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate:   DateTime(2020),
      lastDate:    now,
      initialDateRange: _customStart != null && _customEnd != null
          ? DateTimeRange(start: _customStart!, end: _customEnd!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 6)), end: now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _red,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (range == null) return;
    setState(() {
      _customStart = range.start;
      _customEnd   = range.end;
      _period      = _Period.custom;
    });
    _loadReport();
  }

  // ────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: _red,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text('fuel'.tr,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: RefreshIndicator(
        onRefresh: _loadReport,
        color: _red,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          children: [
            _buildSettingsCard(),
            const SizedBox(height: 20),
            _buildPeriodSelector(),
            const SizedBox(height: 16),
            _buildSummary(),
            const SizedBox(height: 20),
            _buildBreakdown(),
          ],
        ),
      ),
    );
  }

  // ── settings card ────────────────────────────────────────────────────────────
  Widget _buildSettingsCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.tune_rounded, color: _red, size: 18),
            const SizedBox(width: 8),
            Text('settingsTitle'.tr,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937))),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _InputField(
                label: 'Fuel Rate (L/100 km)',
                controller: _rateCtrl,
                hint: '10.5',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InputField(
                label: 'Fuel Price (৳/L)',
                controller: _priceCtrl,
                hint: '130',
              ),
            ),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
                elevation: 1,
                shadowColor: _red.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text('save'.tr,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          if (_fuelPrice > 0 || _fuelRate > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA7F3D0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF059669).withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFD1FAE5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded,
                        size: 16, color: Color(0xFF059669)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppLang.num(
                          '${_fuelRate % 1 == 0 ? _fuelRate.toInt() : _fuelRate} L/100km  •  ৳${_fuelPrice % 1 == 0 ? _fuelPrice.toInt() : _fuelPrice}/L'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF047857),
                        letterSpacing: 0.2,
                      ),
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

  // ── period selector ──────────────────────────────────────────────────────────
  Widget _buildPeriodSelector() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        _PeriodTab(
            label: 'today'.tr,
            selected: _period == _Period.today,
            onTap: () => _selectPeriod(_Period.today)),
        _PeriodTab(
            label: 'thisWeek'.tr,
            selected: _period == _Period.thisWeek,
            onTap: () => _selectPeriod(_Period.thisWeek)),
        _PeriodTab(
            label: 'thisMonth'.tr,
            selected: _period == _Period.thisMonth,
            onTap: () => _selectPeriod(_Period.thisMonth)),
        // Custom date-range picker tab
        _PeriodTab(
          label: _period == _Period.custom && _customStart != null
              ? '${DateFormat('dd/MM').format(_customStart!)} – ${DateFormat('dd/MM').format(_customEnd!)}'
              : 'customTab'.tr,
          selected: _period == _Period.custom,
          onTap: _pickCustomRange,
          icon: Icons.calendar_month_rounded,
        ),
      ]),
    );
  }

  void _selectPeriod(_Period p) {
    if (_period == p) return;
    setState(() => _period = p);
    _loadReport();
  }

  // ── summary stats ────────────────────────────────────────────────────────────
  Widget _buildSummary() {
    if (_isLoadingReport) {
      return const SizedBox(
          height: 120,
          child: Center(
              child: CircularProgressIndicator(color: _red)));
    }
    if (_errorMsg != null) {
      return SizedBox(
          height: 80,
          child: Center(
              child: Text(_errorMsg!,
                  style: const TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w600))));
    }

    final dist   = _reportData?.routeLength    ?? '0 km';
    final litres = _reportData?.fuelConsumption ?? '0 L';
    final cost   = _reportData?.fuelCost        ?? '—';

    return Row(children: [
      Expanded(
          child: _StatCard(
              icon: Icons.alt_route_rounded,
              label: 'totalMileage'.tr,
              value: AppLang.num(dist),
              color: _blue)),
      const SizedBox(width: 8),
      Expanded(
          child: _StatCard(
              icon: Icons.local_gas_station_rounded,
              label: 'fuel'.tr,
              value: AppLang.num(litres),
              color: _red)),
      const SizedBox(width: 8),
      Expanded(
          child: _StatCard(
              icon: Icons.payments_rounded,
              label: 'fuelCost'.tr,
              value: AppLang.num(cost),
              color: _green)),
    ]);
  }

  // ── daily breakdown ──────────────────────────────────────────────────────────
  Widget _buildBreakdown() {
    if (_period == _Period.today) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: _border, height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('history'.tr,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937))),
            if (_isLoadingBreakdown)
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: _red)),
          ],
        ),
        const SizedBox(height: 12),
        if (_breakdown.isEmpty && !_isLoadingBreakdown)
          Container(
              height: 80,
              alignment: Alignment.center,
              child: Text('noRecords'.tr,
                  style: const TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.w600))),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _breakdown.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final day   = _breakdown[i];
            final dist  = day.data.routeLength     ?? '0 km';
            final litres = day.data.fuelConsumption ?? '0 L';
            final cost  = day.data.fuelCost         ?? '—';
            final dateStr = DateFormat('dd MMM yyyy').format(day.date);

            return _Card(
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLang.num(dateStr),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1F2937))),
                      const SizedBox(height: 4),
                      Text(
                          '${'totalMileage'.tr}: ${AppLang.num(dist)}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280))),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(AppLang.num(litres),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1F2937))),
                    const SizedBox(height: 2),
                    Text(AppLang.num(cost),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _green)),
                  ],
                ),
              ]),
            );
          },
        ),
      ],
    );
  }
}

// ── Shared small widgets ─────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: child,
      );
}

class _InputField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  const _InputField(
      {required this.label, required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFFE5E7EB))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFCC0000))),
          ),
        ),
      ],
    );
  }
}

class _PeriodTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const _PeriodTab(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 2))
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 11,
                    color: selected
                        ? const Color(0xFFCC0000)
                        : const Color(0xFF4B5563)),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: selected
                            ? const Color(0xFFCC0000)
                            : const Color(0xFF4B5563))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 12),
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280))),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1F2937)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
