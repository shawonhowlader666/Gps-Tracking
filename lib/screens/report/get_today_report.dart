// lib/screens/report/get_today_report.dart
//
// Industry-level report service using GPSWox get_history API directly.
// No PDF generation — raw GPS positions → computed stats, instant loading.

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/storage/user_repository.dart';

// ─── Period enum ──────────────────────────────────────────────────────────────
enum ReportPeriod { today, yesterday, thisWeek, thisMonth, custom }

// ─── Report Data Model ────────────────────────────────────────────────────────
class TodayReportData {
  final String? device;
  final String? routeStart;
  final String? routeEnd;
  final String? routeLength;
  final String? moveDuration;
  final String? stopDuration;
  final String? topSpeed;
  final String? averageSpeed;
  final String? overspeedCount;
  final String? engineHours;
  final String? engineWork;
  final String? engineIdle;
  final String? odometer;
  final String? fuelConsumption;
  final int? totalPoints;

  const TodayReportData({
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
    this.totalPoints,
  });

  bool get isEmpty =>
      (routeLength == null || routeLength!.isEmpty || routeLength == '0 km') &&
      (moveDuration == null || moveDuration!.isEmpty) &&
      (topSpeed == null || topSpeed!.isEmpty);

  bool get isNotEmpty => !isEmpty;

  Map<String, dynamic> toJson() => {
        'routeLength': routeLength,
        'moveDuration': moveDuration,
        'stopDuration': stopDuration,
        'topSpeed': topSpeed,
        'averageSpeed': averageSpeed,
        'overspeedCount': overspeedCount,
        'engineHours': engineHours,
        'fuelConsumption': fuelConsumption,
      };

  factory TodayReportData.fromJson(Map<String, dynamic> json) =>
      TodayReportData(
        routeLength: json['routeLength'],
        moveDuration: json['moveDuration'],
        stopDuration: json['stopDuration'],
        topSpeed: json['topSpeed'],
        averageSpeed: json['averageSpeed'],
        overspeedCount: json['overspeedCount'],
        engineHours: json['engineHours'],
        fuelConsumption: json['fuelConsumption'],
      );

  TodayReportData copyWith({
    String? routeLength,
    String? moveDuration,
    String? stopDuration,
    String? topSpeed,
    String? averageSpeed,
    String? overspeedCount,
    String? routeStart,
    String? routeEnd,
  }) =>
      TodayReportData(
        device: device,
        routeStart: routeStart ?? this.routeStart,
        routeEnd: routeEnd ?? this.routeEnd,
        routeLength: routeLength ?? this.routeLength,
        moveDuration: moveDuration ?? this.moveDuration,
        stopDuration: stopDuration ?? this.stopDuration,
        topSpeed: topSpeed ?? this.topSpeed,
        averageSpeed: averageSpeed ?? this.averageSpeed,
        overspeedCount: overspeedCount ?? this.overspeedCount,
        engineHours: engineHours,
        fuelConsumption: fuelConsumption,
        totalPoints: totalPoints,
      );
}

// ─── Cache Entry ──────────────────────────────────────────────────────────────
class _CacheEntry {
  final TodayReportData data;
  final DateTime fetchedAt;
  _CacheEntry(this.data, this.fetchedAt);

  bool get isValid =>
      DateTime.now().difference(fetchedAt).inMinutes < 30;
}

// ─── Report Service ───────────────────────────────────────────────────────────
class ReportService {
  // In-memory cache keyed by "deviceId_fromDate_toDate"
  static final Map<String, _CacheEntry> _cache = {};

  // In-flight request deduplication
  static final Map<String, Future<TodayReportData>> _inFlight = {};

  // ── Public API ──────────────────────────────────────────────────────────────

  static Future<TodayReportData> getReportForPeriod({
    required int deviceId,
    required ReportPeriod period,
    DateTime? customStart,
    DateTime? customEnd,
    bool forceRefresh = false,
  }) {
    final range = _dateRange(period, customStart, customEnd);
    return getTodayReportDataWithDates(
      deviceId: deviceId,
      fromDate: range.$1,
      toDate: range.$2,
      forceRefresh: forceRefresh,
    );
  }

  static Future<TodayReportData> getTodayReportData({
    required int deviceId,
    bool forceRefresh = false,
  }) =>
      getReportForPeriod(
        deviceId: deviceId,
        period: ReportPeriod.today,
        forceRefresh: forceRefresh,
      );

  static Future<TodayReportData> getTodayReportDataWithDates({
    required int deviceId,
    required DateTime fromDate,
    required DateTime toDate,
    bool forceRefresh = false,
  }) {
    final key =
        '${deviceId}_${_fmt(fromDate)}_${_fmt(toDate)}';

    // 1. Serve from cache if valid
    if (!forceRefresh) {
      final cached = _cache[key];
      if (cached != null && cached.isValid) return Future.value(cached.data);
    }

    // 2. Request deduplication — return the ongoing future if one exists
    if (_inFlight.containsKey(key)) return _inFlight[key]!;

    final future = _fetch(deviceId, fromDate, toDate).then((data) {
      _cache[key] = _CacheEntry(data, DateTime.now());
      _inFlight.remove(key);
      return data;
    }).catchError((e) {
      _inFlight.remove(key);
      return const TodayReportData();
    });

    _inFlight[key] = future;
    return future;
  }

  // ── Core fetch via get_history API ─────────────────────────────────────────
  static Future<TodayReportData> _fetch(
    int deviceId,
    DateTime from,
    DateTime to,
  ) async {
    try {
      final serverUrl = APIService.serverURL;
      final hash = UserRepository.getHash();
      final lang = UserRepository.getLanguage() ?? 'en';

      if (serverUrl == null || hash == null) return const TodayReportData();

      final fromDate = _fmt(from);           // yyyy-MM-dd
      final fromTime = _fmtTime(from);       // HH:mm:ss
      final toDate   = _fmt(to);
      final toTime   = _fmtTime(to);

      final uri = Uri.parse(
        '$serverUrl/api/get_history'
        '?user_api_hash=$hash'
        '&lang=$lang'
        '&from_date=$fromDate'
        '&from_time=$fromTime'
        '&to_date=$toDate'
        '&to_time=$toTime'
        '&device_id=$deviceId',
      );

      debugPrint('[Report] GET $uri');

      final response = await http
          .get(uri, headers: APIService.headers)
          .timeout(const Duration(seconds: 20));

      debugPrint('[Report] Status ${response.statusCode}, '
          'body length ${response.body.length}');

      if (response.statusCode != 200 || response.body.isEmpty) {
        return const TodayReportData();
      }

      final body = response.body.replaceAll('﻿', '');
      final decoded = json.decode(body);

      return _compute(decoded);
    } catch (e) {
      debugPrint('[Report] Error: $e');
      return const TodayReportData();
    }
  }

  // ── Parse & compute stats from the API response ────────────────────────────
  // GPSWox get_history confirmed structure (from playback.dart):
  // {
  //   "distance_sum": "25.50 km",  ← already has unit
  //   "top_speed": "75 kph",       ← already has unit
  //   "move_duration": "2h 15m",
  //   "stop_duration": "45m",
  //   "items": [                   ← trip segments
  //     { "time":..., "top_speed":..., "average_speed":...,
  //       "items": [               ← nested GPS points
  //         { "latitude":..., "longitude":..., "speed":..., "course":..., "raw_time":... }
  //       ]
  //     }
  //   ]
  // }
  static TodayReportData _compute(dynamic decoded) {
    String? routeLength;
    String? moveDuration;
    String? stopDuration;
    String? topSpeed;
    String? averageSpeed;
    String? fuelConsumption;
    String? routeStart;
    String? routeEnd;
    int? totalPoints;

    if (decoded is! Map) return const TodayReportData();

    // --- Top-level server pre-computed fields (already have units) ---
    final distSum = decoded['distance_sum'];
    if (distSum != null && distSum.toString().trim().isNotEmpty) {
      routeLength = distSum.toString().trim();
    }

    final tSpeed = decoded['top_speed'];
    if (tSpeed != null && tSpeed.toString().trim().isNotEmpty) {
      // normalize: "75 kph" → "75 km/h"
      topSpeed = tSpeed.toString().trim().replaceAll('kph', 'km/h');
    }

    final moveDur = decoded['move_duration'];
    if (moveDur != null && moveDur.toString().trim().isNotEmpty) {
      moveDuration = moveDur.toString().trim();
    }

    final stopDur = decoded['stop_duration'];
    if (stopDur != null && stopDur.toString().trim().isNotEmpty) {
      stopDuration = stopDur.toString().trim();
    }

    final fuel = decoded['fuel_consumption'];
    if (fuel != null && fuel.toString().trim().isNotEmpty) {
      fuelConsumption = fuel.toString().trim();
    }

    // --- Flatten nested GPS positions from trip segments ---
    // Structure: items[trip].items[gps_point] { latitude, longitude, speed }
    final segments = decoded['items'];
    if (segments is List && segments.isNotEmpty) {
      final allPositions = <Map<String, dynamic>>[];

      for (final segment in segments) {
        if (segment is! Map) continue;

        // Collect per-segment average_speed for averaging
        final segAvgSpeed = segment['average_speed'];

        final innerItems = segment['items'];
        if (innerItems is List) {
          for (final pt in innerItems) {
            if (pt is Map && pt['latitude'] != null) {
              final pos = Map<String, dynamic>.from(pt);
              // Inject segment-level average speed if missing
              if (segAvgSpeed != null) pos['_seg_avg_speed'] = segAvgSpeed;
              allPositions.add(pos);
            }
          }
        }
      }

      totalPoints = allPositions.length;

      if (allPositions.isNotEmpty) {
        // Distance from positions if server didn't give it
        if (routeLength == null || routeLength == '0' || routeLength == '0 km') {
          routeLength = _calcDistance(allPositions);
        }

        // Top speed from positions if server didn't give it
        if (topSpeed == null) {
          final top = _calcTopSpeed(allPositions);
          if (top > 0) topSpeed = '${top.toStringAsFixed(0)} km/h';
        }

        // Average speed — use segment average_speed values
        double avgSum = 0;
        int avgCount = 0;
        for (final segment in segments) {
          if (segment is! Map) continue;
          final sa = double.tryParse(
              segment['average_speed']?.toString() ?? '');
          if (sa != null && sa > 0) {
            avgSum += sa;
            avgCount++;
          }
        }
        if (avgCount > 0) {
          averageSpeed ??= '${(avgSum / avgCount).toStringAsFixed(0)} km/h';
        } else {
          final avg = _calcAvgSpeed(allPositions);
          if (avg > 0) averageSpeed ??= '${avg.toStringAsFixed(0)} km/h';
        }


        // Move duration from positions if server didn't give it
        moveDuration ??= _calcMoveDuration(allPositions);

        // Route start = first GPS point, route end = last GPS point
        final first = allPositions.first;
        final last = allPositions.last;
        final sLat = first['latitude']?.toString().trim();
        final sLng = first['longitude']?.toString().trim();
        final eLat = last['latitude']?.toString().trim();
        final eLng = last['longitude']?.toString().trim();

        if (sLat != null && sLng != null && sLat.isNotEmpty) {
          routeStart = '$sLat, $sLng';
        }
        if (eLat != null && eLng != null && eLat.isNotEmpty) {
          routeEnd = '$eLat, $eLng';
        }
      }
    }

    return TodayReportData(
      routeLength: routeLength,
      moveDuration: moveDuration,
      stopDuration: stopDuration,
      topSpeed: topSpeed,
      averageSpeed: averageSpeed,
      fuelConsumption: fuelConsumption,
      routeStart: routeStart,
      routeEnd: routeEnd,
      totalPoints: totalPoints,
    );
  }

  // ── Local calculation helpers ───────────────────────────────────────────────

  /// Haversine distance from flattened GPS positions
  /// Field names: 'latitude', 'longitude' (confirmed from PlayBackRoute model)
  static String _calcDistance(List<Map<String, dynamic>> pts) {
    double totalKm = 0;
    for (int i = 1; i < pts.length; i++) {
      final lat1 = double.tryParse(pts[i - 1]['latitude']?.toString() ?? '') ?? 0;
      final lng1 = double.tryParse(pts[i - 1]['longitude']?.toString() ?? '') ?? 0;
      final lat2 = double.tryParse(pts[i]['latitude']?.toString() ?? '') ?? 0;
      final lng2 = double.tryParse(pts[i]['longitude']?.toString() ?? '') ?? 0;
      if (lat1 != 0 && lng1 != 0) totalKm += _haversine(lat1, lng1, lat2, lng2);
    }
    return '${totalKm.toStringAsFixed(2)} km';
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;

  static double _calcTopSpeed(List<Map<String, dynamic>> pts) {
    double top = 0;
    for (final p in pts) {
      final s = double.tryParse(p['speed']?.toString() ?? '') ?? 0;
      if (s > top) top = s;
    }
    return top;
  }

  static double _calcAvgSpeed(List<Map<String, dynamic>> pts) {
    if (pts.isEmpty) return 0;
    double sum = 0;
    int count = 0;
    for (final p in pts) {
      final s = double.tryParse(p['speed']?.toString() ?? '') ?? 0;
      if (s > 0) {
        sum += s;
        count++;
      }
    }
    return count > 0 ? sum / count : 0;
  }

  static String? _calcMoveDuration(List<Map<String, dynamic>> pts) {
    int moveSecs = 0;
    for (int i = 1; i < pts.length; i++) {
      final speed = double.tryParse(pts[i]['speed']?.toString() ?? '') ?? 0;
      if (speed > 2) {
        // 'raw_time' is confirmed GPS point field; 'time' as fallback
        final t1 = _parseTime(pts[i - 1]['raw_time']?.toString()
            ?? pts[i - 1]['time']?.toString());
        final t2 = _parseTime(pts[i]['raw_time']?.toString()
            ?? pts[i]['time']?.toString());
        if (t1 != null && t2 != null) {
          final diff = t2.difference(t1).inSeconds.abs();
          if (diff < 3600) moveSecs += diff;
        }
      }
    }
    if (moveSecs == 0) return null;
    return _formatDuration(moveSecs);
  }

  static DateTime? _parseTime(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  static String _formatDuration(int totalSecs) {
    final h = totalSecs ~/ 3600;
    final m = (totalSecs % 3600) ~/ 60;
    final s = totalSecs % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  // ── Date helpers ────────────────────────────────────────────────────────────
  static (DateTime, DateTime) _dateRange(
    ReportPeriod period,
    DateTime? customStart,
    DateTime? customEnd,
  ) {
    final now = DateTime.now();
    switch (period) {
      case ReportPeriod.today:
        return (
          DateTime(now.year, now.month, now.day),
          DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case ReportPeriod.yesterday:
        final y = now.subtract(const Duration(days: 1));
        return (
          DateTime(y.year, y.month, y.day),
          DateTime(y.year, y.month, y.day, 23, 59, 59),
        );
      case ReportPeriod.thisWeek:
        final mon = now.subtract(Duration(days: now.weekday - 1));
        return (
          DateTime(mon.year, mon.month, mon.day),
          DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case ReportPeriod.thisMonth:
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case ReportPeriod.custom:
        return (
          customStart ?? DateTime(now.year, now.month, now.day),
          customEnd ?? DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
    }
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

  // ── Cache management ────────────────────────────────────────────────────────
  static void clearCache() => _cache.clear();

  static void clearCacheForDevice(int deviceId) =>
      _cache.removeWhere((k, _) => k.startsWith('${deviceId}_'));

  static Map<String, dynamic> getCacheStatus() => {
        'size': _cache.length,
        'keys': _cache.keys.toList(),
        'inFlight': _inFlight.keys.toList(),
      };

  static void dispose() => clearCache();
}
