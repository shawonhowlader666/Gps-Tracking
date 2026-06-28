// lib/services/road_snap_service.dart
//
// Road snapping using OSRM (Open Source Routing Machine) — 100% free.
// Uses OpenStreetMap data, works perfectly in Bangladesh/Dhaka.
//
// Strategy (live tracking):
//   1. Each new GPS point → OSRM /nearest → snapped to closest road point
//   2. LRU cache avoids duplicate API calls for same area
//   3. Falls back to raw GPS instantly if API unreachable
//
// OSRM public server: router.project-osrm.org
// Uses lon,lat order (opposite of Google Maps lat,lon)

import 'dart:convert';
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class RoadSnapService {
  // OSRM servers - Primary (public demo) and Backup (OSM Germany)
  static const String _osrmBasePrimary = 'https://router.project-osrm.org';
  static const String _osrmBaseBackup = 'https://routing.openstreetmap.de/routed-car';

  // Helper to request from primary with fallback to backup on timeout or error
  static Future<http.Response> _getWithFailover(String urlPath, {Duration timeout = const Duration(milliseconds: 1500)}) async {
    try {
      final uri = Uri.parse('$_osrmBasePrimary$urlPath');
      final resp = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(timeout);
      if (resp.statusCode == 200) return resp;
      throw Exception('Primary status code ${resp.statusCode}');
    } catch (_) {
      // Primary failed, fall back to backup
      try {
        final uri = Uri.parse('$_osrmBaseBackup$urlPath');
        return await http.get(
          uri,
          headers: {'Accept': 'application/json'},
        ).timeout(timeout);
      } catch (e) {
        rethrow;
      }
    }
  }

  // ─── LRU cache ────────────────────────────────────────────────────────────
  // Key = "lat4,lng4" (4 decimal places ≈ 11m precision), Value = snapped pt
  static final Map<String, LatLng> _cache = {};
  static const int _maxCacheSize = 500;

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Snap a single live GPS point to the nearest road using OSRM /nearest.
  /// Falls back to [raw] on error or timeout.
  static Future<LatLng> snapSingleLivePoint(
    LatLng raw, {
    LatLng? previousPoint,
  }) async {
    // Check cache first
    final cached = _getCached(raw);
    if (cached != null) return cached;

    try {
      // OSRM uses lon,lat order
      final lon = raw.longitude.toStringAsFixed(6);
      final lat = raw.latitude.toStringAsFixed(6);
      final path = '/nearest/v1/driving/$lon,$lat?number=1';

      final response = await _getWithFailover(path);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['code'] == 'Ok') {
          final waypoints = json['waypoints'] as List<dynamic>?;
          if (waypoints != null && waypoints.isNotEmpty) {
            final location = waypoints.first['location'] as List<dynamic>;
            // OSRM returns [longitude, latitude]
            final snapped = LatLng(
              (location[1] as num).toDouble(),
              (location[0] as num).toDouble(),
            );

            // Only use snapped if it's within 150m of raw GPS
            // (avoids snapping to wrong road on the other side)
            if (distanceMeters(raw, snapped) < 150) {
              _cachePoint(raw, snapped);
              return snapped;
            }
          }
        }
      }
    } catch (_) {
      // Network error, timeout — fall back to raw GPS silently
    }

    return raw;
  }

  /// Gets a list of LatLng points representing the road route between start and end.
  /// Falls back to [start, end] on error.
  static Future<List<LatLng>> getRoutePath(LatLng start, LatLng end) async {
    if (distanceMeters(start, end) < 1.0) {
      return [start, end];
    }
    try {
      final lon1 = start.longitude.toStringAsFixed(6);
      final lat1 = start.latitude.toStringAsFixed(6);
      final lon2 = end.longitude.toStringAsFixed(6);
      final lat2 = end.latitude.toStringAsFixed(6);
      final path = '/route/v1/driving/$lon1,$lat1;$lon2,$lat2?overview=full&geometries=geojson';

      final response = await _getWithFailover(path);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['code'] == 'Ok') {
          final routes = json['routes'] as List<dynamic>?;
          if (routes != null && routes.isNotEmpty) {
            final geometry = routes.first['geometry'] as Map<String, dynamic>?;
            if (geometry != null) {
              final coordinates = geometry['coordinates'] as List<dynamic>?;
              if (coordinates != null && coordinates.isNotEmpty) {
                final List<LatLng> path = [];
                for (final coord in coordinates) {
                  path.add(LatLng(
                    (coord[1] as num).toDouble(),
                    (coord[0] as num).toDouble(),
                  ));
                }
                return path;
              }
            }
          }
        }
      }
    } catch (_) {
      // Fallback
    }
    return [start, end];
  }

  /// Snaps sequential GPS points to the road network and returns the interpolated road geometry between them.
  static Future<List<LatLng>> snapAndInterpolateHistory(List<LatLng> points) async {
    if (points.length < 2) return points;

    final List<LatLng> interpolatedPath = [];
    const chunkSize = 50;

    for (int i = 0; i < points.length; i += chunkSize - 1) {
      final endIdx = math.min(i + chunkSize, points.length);
      final chunk = points.sublist(i, endIdx);
      if (chunk.length < 2) break;

      try {
        final coordsStr = chunk
            .map((pt) => '${pt.longitude.toStringAsFixed(6)},${pt.latitude.toStringAsFixed(6)}')
            .join(';');
        final path = '/route/v1/driving/$coordsStr?overview=full&geometries=geojson';
        final response = await _getWithFailover(path, timeout: const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          if (json['code'] == 'Ok') {
            final routes = json['routes'] as List<dynamic>?;
            if (routes != null && routes.isNotEmpty) {
              final geometry = routes.first['geometry'] as Map<String, dynamic>?;
              if (geometry != null) {
                final coordinates = geometry['coordinates'] as List<dynamic>?;
                if (coordinates != null && coordinates.isNotEmpty) {
                  for (final coord in coordinates) {
                    final pt = LatLng(
                      (coord[1] as num).toDouble(),
                      (coord[0] as num).toDouble(),
                    );
                    if (interpolatedPath.isEmpty || interpolatedPath.last != pt) {
                      interpolatedPath.add(pt);
                    }
                  }
                  continue;
                }
              }
            }
          }
        }
      } catch (_) {
        // Fallback to raw for this chunk
      }

      for (final pt in chunk) {
        if (interpolatedPath.isEmpty || interpolatedPath.last != pt) {
          interpolatedPath.add(pt);
        }
      }
    }

    return interpolatedPath.isNotEmpty ? interpolatedPath : points;
  }

  // ─── Distance (Haversine) ─────────────────────────────────────────────────

  /// Distance between two LatLng points in meters.
  static double distanceMeters(LatLng a, LatLng b) {
    const R = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  // ─── Cache helpers ────────────────────────────────────────────────────────

  static String _key(LatLng p) =>
      '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}';

  static LatLng? _getCached(LatLng p) => _cache[_key(p)];

  static void _cachePoint(LatLng raw, LatLng snapped) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first); // simple LRU eviction
    }
    _cache[_key(raw)] = snapped;
  }

  static void clearCache() => _cache.clear();
}
