import 'dart:io';
import 'dart:typed_data';
import 'package:smart_lock/services/api_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

// Report Period Enum
enum ReportPeriod {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  custom,
}

class TodayReportData {
  String? device;
  String? routeStart;
  String? routeEnd;
  String? routeLength;
  String? moveDuration;
  String? stopDuration;
  String? topSpeed;
  String? averageSpeed;
  String? overspeedCount;
  String? engineHours;
  String? engineWork;
  String? engineIdle;
  String? odometer;
  String? fuelConsumption;

  TodayReportData({
    this.device,
    this.routeStart,
    this.routeEnd,
    this.routeLength,
    this.moveDuration,
    this.stopDuration,
    this.topSpeed,
    this.averageSpeed,
    this.overspeedCount,
    this.engineHours,
    this.engineWork,
    this.engineIdle,
    this.odometer,
    this.fuelConsumption,
  });

  bool get isEmpty =>
      (routeLength == null || routeLength!.isEmpty) &&
          (moveDuration == null || moveDuration!.isEmpty) &&
          (stopDuration == null || stopDuration!.isEmpty) &&
          (topSpeed == null || topSpeed!.isEmpty) &&
          (engineHours == null || engineHours!.isEmpty);

  bool get isNotEmpty => !isEmpty;

  Map<String, dynamic> toJson() {
    return {
      'device': device,
      'routeStart': routeStart,
      'routeEnd': routeEnd,
      'routeLength': routeLength,
      'moveDuration': moveDuration,
      'stopDuration': stopDuration,
      'topSpeed': topSpeed,
      'averageSpeed': averageSpeed,
      'overspeedCount': overspeedCount,
      'engineHours': engineHours,
      'engineWork': engineWork,
      'engineIdle': engineIdle,
      'odometer': odometer,
      'fuelConsumption': fuelConsumption,
    };
  }

  factory TodayReportData.fromJson(Map<String, dynamic> json) {
    return TodayReportData(
      device: json['device'],
      routeStart: json['routeStart'],
      routeEnd: json['routeEnd'],
      routeLength: json['routeLength'],
      moveDuration: json['moveDuration'],
      stopDuration: json['stopDuration'],
      topSpeed: json['topSpeed'],
      averageSpeed: json['averageSpeed'],
      overspeedCount: json['overspeedCount'],
      engineHours: json['engineHours'],
      engineWork: json['engineWork'],
      engineIdle: json['engineIdle'],
      odometer: json['odometer'],
      fuelConsumption: json['fuelConsumption'],
    );
  }

  TodayReportData copyWith({
    String? device,
    String? routeStart,
    String? routeEnd,
    String? routeLength,
    String? moveDuration,
    String? stopDuration,
    String? topSpeed,
    String? averageSpeed,
    String? overspeedCount,
    String? engineHours,
    String? engineWork,
    String? engineIdle,
    String? odometer,
    String? fuelConsumption,
  }) {
    return TodayReportData(
      device: device ?? this.device,
      routeStart: routeStart ?? this.routeStart,
      routeEnd: routeEnd ?? this.routeEnd,
      routeLength: routeLength ?? this.routeLength,
      moveDuration: moveDuration ?? this.moveDuration,
      stopDuration: stopDuration ?? this.stopDuration,
      topSpeed: topSpeed ?? this.topSpeed,
      averageSpeed: averageSpeed ?? this.averageSpeed,
      overspeedCount: overspeedCount ?? this.overspeedCount,
      engineHours: engineHours ?? this.engineHours,
      engineWork: engineWork ?? this.engineWork,
      engineIdle: engineIdle ?? this.engineIdle,
      odometer: odometer ?? this.odometer,
      fuelConsumption: fuelConsumption ?? this.fuelConsumption,
    );
  }

  @override
  String toString() {
    return 'TodayReportData(\n'
        '  device: $device,\n'
        '  routeStart: $routeStart,\n'
        '  routeEnd: $routeEnd,\n'
        '  routeLength: $routeLength,\n'
        '  moveDuration: $moveDuration,\n'
        '  stopDuration: $stopDuration,\n'
        '  topSpeed: $topSpeed,\n'
        '  averageSpeed: $averageSpeed,\n'
        '  engineHours: $engineHours,\n'
        '  engineWork: $engineWork,\n'
        '  engineIdle: $engineIdle,\n'
        '  overspeedCount: $overspeedCount,\n'
        '  odometer: $odometer,\n'
        '  fuelConsumption: $fuelConsumption\n'
        ')';
  }
}

class ReportService {
  static final HttpClient _httpClient = HttpClient();

  static final Map<String, TodayReportData> _cache = {};
  static DateTime? _lastCacheTime;
  static const int _cacheDurationSeconds = 30;

  static Future<TodayReportData> getReportForPeriod({
    required int deviceId,
    required ReportPeriod period,
    DateTime? customStart,
    DateTime? customEnd,
    bool forceRefresh = false,
  }) async {
    final dates = _getDateRangeForPeriod(period, customStart, customEnd);
    return getTodayReportDataWithDates(
      deviceId: deviceId,
      fromDate: dates['from']!,
      toDate: dates['to']!,
      forceRefresh: forceRefresh,
    );
  }

  static Map<String, DateTime> _getDateRangeForPeriod(
      ReportPeriod period,
      DateTime? customStart,
      DateTime? customEnd,
      ) {
    final now = DateTime.now();
    DateTime from, to;

    switch (period) {
      case ReportPeriod.today:
        from = DateTime(now.year, now.month, now.day);
        to = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;

      case ReportPeriod.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        from = DateTime(yesterday.year, yesterday.month, yesterday.day);
        to = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
        break;

      case ReportPeriod.thisWeek:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        from = DateTime(monday.year, monday.month, monday.day);
        to = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;

      case ReportPeriod.thisMonth:
        from = DateTime(now.year, now.month, 1);
        to = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;

      case ReportPeriod.custom:
        from = customStart ?? DateTime(now.year, now.month, now.day);
        to = customEnd ?? DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
    }

    return {'from': from, 'to': to};
  }

  static Future<TodayReportData> getTodayReportDataWithDates({
    required int deviceId,
    required DateTime fromDate,
    required DateTime toDate,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'device_${deviceId}_${_formatDate(fromDate)}_${_formatDate(toDate)}';

    if (!forceRefresh &&
        _cache.containsKey(cacheKey) &&
        _lastCacheTime != null &&
        DateTime.now().difference(_lastCacheTime!).inSeconds < _cacheDurationSeconds) {
      return _cache[cacheKey]!;
    }

    try {
      final fromDateStr = _formatDate(fromDate);
      final toDateStr = _formatDate(toDate.add(const Duration(days: 1)));

      final reportResponse = await APIService.getReport(
        deviceId.toString(),
        fromDateStr,
        toDateStr,
        1,
      );

      if (reportResponse == null || reportResponse.url == null) {
        return TodayReportData();
      }

      final pdfFile = await _downloadPdf(reportResponse.url!);
      if (pdfFile == null) return TodayReportData();

      final text = await _extractText(pdfFile.path);
      if (text == null || text.isEmpty) return TodayReportData();

      final data = _parseMultiLineText(text);

      _cache[cacheKey] = data;
      _lastCacheTime = DateTime.now();

      return data;
    } catch (e) {
      return TodayReportData();
    }
  }

  static Future<TodayReportData> getTodayReportData({
    required int deviceId,
    bool forceRefresh = false,
  }) async {
    return getReportForPeriod(
      deviceId: deviceId,
      period: ReportPeriod.today,
      forceRefresh: forceRefresh,
    );
  }

  static String _formatDate(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return "${date.year}-$m-$d";
  }

  static Future<File?> _downloadPdf(String url) async {
    try {
      String cleanUrl = Uri.decodeFull(url);
      cleanUrl = cleanUrl.replaceAll('%5B0%5D', '[]');
      cleanUrl = cleanUrl.replaceAll('[0]', '[]');
      cleanUrl = cleanUrl.replaceAll('send_to_email[]=', 'send_to_email=');

      final request = await _httpClient.getUrl(Uri.parse(cleanUrl));
      final response = await request.close();

      if (response.statusCode != 200) return null;

      final bytes = await response.fold<List<int>>(
        <int>[],
            (prev, element) => prev..addAll(element),
      );

      if (bytes.isEmpty) return null;

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/report_$timestamp.pdf');
      await file.writeAsBytes(bytes);

      return file;
    } catch (e) {
      return null;
    }
  }

  static Future<String?> _extractText(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final document = PdfDocument(inputBytes: Uint8List.fromList(bytes));
      final extractor = PdfTextExtractor(document);

      String text = '';
      for (int i = 0; i < document.pages.count; i++) {
        final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
        text += pageText ?? '';
        text += '\n';
      }

      document.dispose();

      try {
        await file.delete();
      } catch (_) {}

      return text;
    } catch (e) {
      return null;
    }
  }

  static TodayReportData _parseMultiLineText(String text) {
    final data = TodayReportData();

    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final keyMap = <String, void Function(String)>{
      'device:': (v) => data.device = v,
      'route start:': (v) => data.routeStart = v,
      'route end:': (v) => data.routeEnd = v,
      'route length:': (v) => data.routeLength = v,
      'move duration:': (v) => data.moveDuration = v,
      'stop duration:': (v) => data.stopDuration = v,
      'top speed:': (v) => data.topSpeed = v,
      'average speed:': (v) => data.averageSpeed = v,
      'overspeed count:': (v) => data.overspeedCount = v,
      'engine hours:': (v) => data.engineHours = v,
      'engine work:': (v) => data.engineWork = v,
      'engine idle:': (v) => data.engineIdle = v,
      'odometer:': (v) => data.odometer = v,
      'fuel consumption:': (v) => data.fuelConsumption = v,
    };

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lowerLine = line.toLowerCase();

      for (final entry in keyMap.entries) {
        final key = entry.key;
        final setter = entry.value;

        if (lowerLine == key || lowerLine.endsWith(key)) {
          String value = '';

          if (lowerLine != key && line.toLowerCase().contains(key)) {
            final idx = lowerLine.indexOf(key);
            value = line.substring(idx + key.length).trim();
          }

          if (value.isEmpty && i + 1 < lines.length) {
            final nextLine = lines[i + 1];
            final isNextLineKey = keyMap.keys.any(
                  (k) => nextLine.toLowerCase() == k || nextLine.toLowerCase().endsWith(k),
            );
            if (!isNextLineKey) value = nextLine;
          }

          if (value.isNotEmpty) setter(value);
          break;
        }
      }
    }

    if (data.isEmpty) _parseAlternative(text, data);

    return data;
  }

  static void _parseAlternative(String text, TodayReportData data) {
    final patterns = <String, void Function(String)>{
      r'Route\s+length[:\s]+([0-9.]+\s*(?:Km|km|KM|mi|Mi))': (v) => data.routeLength = v,
      r'Move\s+duration[:\s]+([0-9hms\s:]+)': (v) => data.moveDuration = v,
      r'Stop\s+duration[:\s]+([0-9hms\s:]+)': (v) => data.stopDuration = v,
      r'Top\s+speed[:\s]+([0-9.]+\s*(?:kph|km/h|Kph|mph))': (v) => data.topSpeed = v,
      r'Average\s+speed[:\s]+([0-9.]+\s*(?:kph|km/h|Kph|mph))': (v) => data.averageSpeed = v,
      r'Overspeed\s+count[:\s]+([0-9]+)': (v) => data.overspeedCount = v,
      r'Engine\s+hours[:\s]+([0-9hms\s:]+)': (v) => data.engineHours = v,
      r'Engine\s+work[:\s]+([0-9hms\s:]+)': (v) => data.engineWork = v,
      r'Engine\s+idle[:\s]+([0-9hms\s:]+)': (v) => data.engineIdle = v,
      r'Odometer[:\s]+([0-9.]+\s*(?:Km|km|KM|mi|Mi)?)': (v) => data.odometer = v,
      r'Fuel\s+consumption[:\s]+([0-9.]+\s*(?:L|l|gal)?)': (v) => data.fuelConsumption = v,
    };

    final normalizedText = text.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');

    for (final entry in patterns.entries) {
      final regex = RegExp(entry.key, caseSensitive: false);
      final match = regex.firstMatch(normalizedText);
      if (match != null && match.group(1) != null) {
        entry.value(match.group(1)!.trim());
      }
    }
  }

  static void clearCache() {
    _cache.clear();
    _lastCacheTime = null;
  }

  static void clearCacheForDevice(int deviceId) {
    _cache.removeWhere((key, value) => key.startsWith('device_$deviceId'));
  }

  static Map<String, dynamic> getCacheStatus() {
    return {
      'cacheSize': _cache.length,
      'lastCacheTime': _lastCacheTime?.toIso8601String(),
      'cachedKeys': _cache.keys.toList(),
    };
  }

  static void dispose() {
    _httpClient.close();
    clearCache();
  }
}