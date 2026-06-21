// lib/screens/report/get_today_report.dart

import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:gpspro/services/api_service.dart';
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

  /// Get report for a specific period (today, yesterday, this week, this month)
  static Future<TodayReportData> getReportForPeriod({
    required int deviceId,
    required ReportPeriod period,
    DateTime? customStart,
    DateTime? customEnd,
    bool forceRefresh = false,
  }) async {
    final dates = _getDateRangeForPeriod(period, customStart, customEnd);

    log('📅 [ReportService] Getting report for period: $period');
    log('📅 [ReportService] From: ${dates['from']}, To: ${dates['to']}');

    return getTodayReportDataWithDates(
      deviceId: deviceId,
      fromDate: dates['from']!,
      toDate: dates['to']!,
      forceRefresh: forceRefresh,
    );
  }

  /// Helper method to get date ranges based on period
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
        final yesterday = now.subtract(Duration(days: 1));
        from = DateTime(yesterday.year, yesterday.month, yesterday.day);
        to = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
        break;

      case ReportPeriod.thisWeek:
      // Get Monday of current week
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

  /// Get report with specific dates
  static Future<TodayReportData> getTodayReportDataWithDates({
    required int deviceId,
    required DateTime fromDate,
    required DateTime toDate,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'device_${deviceId}_${_formatDate(fromDate)}_${_formatDate(toDate)}';

    // Check cache
    if (!forceRefresh &&
        _cache.containsKey(cacheKey) &&
        _lastCacheTime != null &&
        DateTime.now().difference(_lastCacheTime!).inSeconds < _cacheDurationSeconds) {
      log('📦 [ReportService] Using cached data for $cacheKey');
      return _cache[cacheKey]!;
    }

    try {
      log('🔄 [ReportService] Fetching report for device $deviceId');

      final fromDateStr = _formatDate(fromDate);
      final toDateStr = _formatDate(toDate.add(const Duration(days: 1)));

      log('📅 [ReportService] Date range: $fromDateStr to $toDateStr');

      final reportResponse = await APIService.getReport(
        deviceId.toString(),
        fromDateStr,
        toDateStr,
        1,
      );

      if (reportResponse == null || reportResponse.url == null) {
        log('❌ [ReportService] No report URL received');
        return TodayReportData();
      }

      log('📥 [ReportService] Report URL: ${reportResponse.url}');

      final pdfFile = await _downloadPdf(reportResponse.url!);
      if (pdfFile == null) {
        log('❌ [ReportService] Failed to download PDF');
        return TodayReportData();
      }

      log('📄 [ReportService] PDF downloaded successfully');

      final text = await _extractText(pdfFile.path);
      if (text == null || text.isEmpty) {
        log('❌ [ReportService] No text extracted from PDF');
        return TodayReportData();
      }

      log('📝 [ReportService] Text extracted (${text.length} characters)');

      // Parse the extracted text
      final data = _parseMultiLineText(text);

      log('✅ [ReportService] Report parsed successfully');
      log('📊 [ReportService] Data: $data');

      // Cache the result
      _cache[cacheKey] = data;
      _lastCacheTime = DateTime.now();

      return data;
    } catch (e, stack) {
      log('❌ [ReportService] Error fetching report: $e');
      log('❌ [ReportService] Stack trace: $stack');
      return TodayReportData();
    }
  }

  /// Get today's report (backward compatibility)
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

  /// Format date to YYYY-MM-DD
  static String _formatDate(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return "${date.year}-$m-$d";
  }

  /// Download PDF from URL
  static Future<File?> _downloadPdf(String url) async {
    try {
      // Clean and format URL
      String cleanUrl = Uri.decodeFull(url);
      cleanUrl = cleanUrl.replaceAll('%5B0%5D', '[]');
      cleanUrl = cleanUrl.replaceAll('[0]', '[]');
      cleanUrl = cleanUrl.replaceAll('send_to_email[]=', 'send_to_email=');

      log('📥 [ReportService] Downloading PDF from: $cleanUrl');

      final request = await _httpClient.getUrl(Uri.parse(cleanUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        log('❌ [ReportService] Download failed with status: ${response.statusCode}');
        return null;
      }

      final bytes = await response.fold<List<int>>(
        <int>[],
            (prev, element) => prev..addAll(element),
      );

      log('📥 [ReportService] Downloaded ${bytes.length} bytes');

      if (bytes.isEmpty) {
        log('❌ [ReportService] Downloaded file is empty');
        return null;
      }

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/report_$timestamp.pdf');
      await file.writeAsBytes(bytes);

      log('💾 [ReportService] PDF saved to: ${file.path}');

      return file;
    } catch (e, stack) {
      log('❌ [ReportService] Download error: $e');
      log('❌ [ReportService] Stack trace: $stack');
      return null;
    }
  }

  /// Extract text from PDF file
  static Future<String?> _extractText(String path) async {
    try {
      log('📖 [ReportService] Extracting text from: $path');

      final file = File(path);
      if (!await file.exists()) {
        log('❌ [ReportService] PDF file does not exist');
        return null;
      }

      final bytes = await file.readAsBytes();

      final document = PdfDocument(inputBytes: Uint8List.fromList(bytes));
      final extractor = PdfTextExtractor(document);

      String text = '';
      for (int i = 0; i < document.pages.count; i++) {
        final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
        text += pageText ?? '';
        text += '\n';
        log('📄 [ReportService] Page ${i + 1} extracted (${pageText.length ?? 0} chars)');
      }

      document.dispose();

      // Clean up temporary file
      try {
        await file.delete();
        log('🗑️ [ReportService] Temporary PDF deleted');
      } catch (e) {
        log('⚠️ [ReportService] Could not delete temp file: $e');
      }

      return text;
    } catch (e, stack) {
      log('❌ [ReportService] Text extraction error: $e');
      log('❌ [ReportService] Stack trace: $stack');
      return null;
    }
  }

  /// Parse multi-line format where key and value are on separate lines
  /// Format:
  /// Route length:
  /// 52.12 Km
  static TodayReportData _parseMultiLineText(String text) {
    final data = TodayReportData();

    log('🔍 [ReportService] Parsing multi-line text...');

    // Split into lines and clean them
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    log('📋 [ReportService] Total lines: ${lines.length}');

    // Define keys to look for
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

    // Iterate through lines
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lowerLine = line.toLowerCase();

      // Check each key
      for (final entry in keyMap.entries) {
        final key = entry.key;
        final setter = entry.value;

        if (lowerLine == key || lowerLine.endsWith(key)) {
          // Key found! Get value from next line(s)
          String value = '';

          // Check if value is on the same line after the key
          if (lowerLine != key && line.toLowerCase().contains(key)) {
            final idx = lowerLine.indexOf(key);
            value = line.substring(idx + key.length).trim();
          }

          // If value is empty, get it from the next line
          if (value.isEmpty && i + 1 < lines.length) {
            final nextLine = lines[i + 1];
            // Make sure next line is not another key
            final isNextLineKey = keyMap.keys.any(
                  (k) => nextLine.toLowerCase() == k || nextLine.toLowerCase().endsWith(k),
            );
            if (!isNextLineKey) {
              value = nextLine;
            }
          }

          if (value.isNotEmpty) {
            setter(value);
            log('  ✓ ${key.replaceAll(':', '')}: $value');
          }
          break;
        }
      }
    }

    // If still empty, try alternative parsing methods
    if (data.isEmpty) {
      log('🔍 [ReportService] Primary parsing failed, trying alternative methods...');
      _parseAlternative(text, data);
    }

    log('📊 [ReportService] Parsing complete. isEmpty: ${data.isEmpty}');
    return data;
  }

  /// Alternative parsing using regex patterns
  static void _parseAlternative(String text, TodayReportData data) {
    log('🔧 [ReportService] Using regex-based parsing...');

    // Try to find patterns like "Route length:\n52.12 Km" or "Route length: 52.12 Km"
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

    // Normalize text - replace newlines with spaces for regex matching
    final normalizedText = text.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');

    int matchCount = 0;
    for (final entry in patterns.entries) {
      final regex = RegExp(entry.key, caseSensitive: false);
      final match = regex.firstMatch(normalizedText);
      if (match != null && match.group(1) != null) {
        final value = match.group(1)!.trim();
        entry.value(value);
        matchCount++;
        log('  ✓ Regex match found: ${entry.key} = $value');
      }
    }

    log('🔧 [ReportService] Regex parsing found $matchCount matches');
  }

  /// Clear all cached reports
  static void clearCache() {
    log('🗑️ [ReportService] Clearing cache...');
    _cache.clear();
    _lastCacheTime = null;
  }

  /// Clear cache for specific device
  static void clearCacheForDevice(int deviceId) {
    log('🗑️ [ReportService] Clearing cache for device $deviceId');
    _cache.removeWhere((key, value) => key.startsWith('device_$deviceId'));
  }

  /// Get cache status
  static Map<String, dynamic> getCacheStatus() {
    return {
      'cacheSize': _cache.length,
      'lastCacheTime': _lastCacheTime?.toIso8601String(),
      'cachedKeys': _cache.keys.toList(),
    };
  }

  /// Dispose and cleanup
  static void dispose() {
    log('🔌 [ReportService] Disposing service...');
    _httpClient.close();
    clearCache();
  }
}

