import 'dart:convert';
import 'package:gpspro/services/model/device.dart';
import 'package:gpspro/services/model/device_item.dart';
import 'package:gpspro/services/model/event.dart';

/// Mapper that converts raw Tracksolid JSON maps into the app's data models.
class TracksolidMapper {
  // ------------------------------- Device ---------------------------------
  static Device mapDevices(List<Map<String, dynamic>> list) {
    // The UI expects a single group titled "All Devices"
    final items = list.map((d) => mapDeviceItem(d, {})).toList();
    return Device(id: 1, title: 'All Devices', items: items);
  }

  // ---------------------------- Real‑time info ----------------------------
  static DeviceItem mapDeviceItem(
      Map<String, dynamic> device, Map<String, dynamic> info) {
    final imei = device['imei']?.toString() ?? '';
    final name = device['deviceName']?.toString() ??
        device['name']?.toString() ??
        imei;

    // deterministic id from last 9 digits of IMEI (fallback to hash)
    int id = 0;
    if (imei.length >= 9) {
      id = int.tryParse(imei.substring(imei.length - 9)) ?? imei.hashCode.abs();
    } else {
      id = imei.hashCode.abs();
    }

    // Raw values may be missing – safe‑guard with helper conversions.
    double _d(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
    int _i(dynamic v) => v == null ? 0 : int.tryParse(v.toString()) ?? 0;

    final lat = _d(info['lat'] ?? device['lat']);
    final lng = _d(info['lng'] ?? device['lng']);
    final speed = _d(info['speed'] ?? device['speed']);
    final course = _d(info['direction'] ?? device['direction'] ?? device['course']);
    final altitude = _d(info['altitude'] ?? device['altitude']);
    final String timestampStr = (info['gpsTime'] ?? info['hbTime'] ?? device['gpsTime'] ?? device['time'] ?? '')?.toString() ?? '';
    final int timestamp = _parseTimestamp(timestampStr);
    final int acc = _i(info['accStatus'] ?? device['accStatus']);

    // Resolve online/offline by comparing last update time with current time (10 minutes tolerance)
    bool isOnline = false;
    if (timestamp > 0) {
      try {
        final lastUpdate = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
        final nowUtc = DateTime.now().toUtc();
        
        final diffUtc = nowUtc.difference(lastUpdate).inMinutes.abs();
        
        final lastUpdateGmt8 = lastUpdate.subtract(const Duration(hours: 8));
        final diffGmt8 = nowUtc.difference(lastUpdateGmt8).inMinutes.abs();
        
        final localOffset = DateTime.now().timeZoneOffset;
        final lastUpdateLocal = lastUpdate.subtract(localOffset);
        final diffLocal = nowUtc.difference(lastUpdateLocal).inMinutes.abs();

        isOnline = diffUtc < 10 || diffGmt8 < 10 || diffLocal < 10;
      } catch (_) {}
    }

    // Resolve status: 0=offline, 1=stop, 2=move, 3=idle
    int status = 0; // default offline
    if (isOnline) {
      if (speed > 0) {
        status = 2; // moving
      } else if (acc == 1) {
        status = 3; // idle
      } else {
        status = 1; // stopped/parked
      }
    } else {
      status = 0; // offline
    }

    final speedVal = status == 0 ? 0.0 : speed;

    final String iconColor = _statusToIconColor(status);
    final String online = status == 0 ? 'offline' : 'online';

    final String power = (info['voltage'] ?? device['voltage'])?.toString() ?? '';
    final int alarm = _i(info['alarm'] ?? device['alarm']);
    final dynamic mileage = info['currentMileage'] ?? device['currentMileage'] ?? info['mileage'] ?? device['mileage'];

    final Map<String, dynamic> otherMap = {
      ...device,
      ...info,
      'ignition': acc,
      'engine': acc,
      'power': info['powerValue'] ?? device['powerValue'] ?? '',
      'voltage': info['powerValue'] ?? device['powerValue'] ?? '',
      'battery': info['batteryPowerVal'] ?? device['batteryPowerVal'] ?? '',
      'batterylevel': info['batteryPowerVal'] ?? device['batteryPowerVal'] ?? '',
      'sat': info['gpsNum'] ?? device['gpsNum'] ?? '',
      'rssi': info['gpsSignal'] ?? device['gpsSignal'] ?? '',
      'mileage': mileage ?? '',
    };
    final String otherJson = json.encode(otherMap);

    final List<Map<String, dynamic>> sensorsList = [
      {'name': 'Ignition', 'value': acc == 1 ? 'On' : 'Off'},
      {'name': 'Engine', 'value': acc == 1 ? 'On' : 'Off'},
      {'name': 'Power', 'value': (info['powerValue'] ?? device['powerValue'] ?? '').toString()},
      {'name': 'Voltage', 'value': (info['powerValue'] ?? device['powerValue'] ?? '').toString()},
      {'name': 'Battery', 'value': (info['batteryPowerVal'] ?? device['batteryPowerVal'] ?? '').toString()},
      {'name': 'Odometer', 'value': (mileage ?? '').toString()},
      {'name': 'Odo', 'value': (mileage ?? '').toString()},
      {'name': 'Satellites', 'value': (info['gpsNum'] ?? device['gpsNum'] ?? '').toString()},
      {'name': 'Sat', 'value': (info['gpsNum'] ?? device['gpsNum'] ?? '').toString()},
    ];

    final deviceData = DeviceData(
      id: id,
      name: name,
      imei: imei,
      simNumber: device['simNumber']?.toString() ?? device['sim']?.toString() ?? '',
      expirationDate: device['expireTime']?.toString() ?? device['expiration']?.toString() ?? '',
      time: timestampStr,
      speed: speedVal.toInt(),
      course: course.toInt(),
      active: 1,
      traccar: Traccar(
        id: id,
        name: name,
        uniqueId: imei,
        lastValidLatitude: lat,
        lastValidLongitude: lng,
        speed: speedVal.toString(),
        time: timestampStr,
        course: course,
        altitude: altitude,
        other: otherJson,
      ),
    );

    return DeviceItem(
      id: id,
      alarm: alarm,
      name: name,
      imei: imei,
      online: online,
      time: timestampStr,
      timestamp: timestamp,
      lat: lat,
      lng: lng,
      course: course,
      speed: speedVal,
      altitude: altitude,
      iconColor: iconColor,
      power: power,
      engineStatus: acc,
      totalDistance: mileage,
      sensors: sensorsList,
      deviceData: deviceData,
    );
  }

  static String _statusToIconColor(int status) {
    switch (status) {
      case 2:
        return 'green'; // moving
      case 3:
        return 'yellow'; // idle (ACC on)
      case 1:
        return 'yellow'; // stopped/parked
      case 0:
      default:
        return 'red'; // offline
    }
  }

  static int _parseTimestamp(String time) {
    if (time.isEmpty) return 0;
    try {
      // Tracksolid returns "2023-09-01 12:34:56". Parse as UTC by default to avoid local phone timezone shift.
      String iso = time.replaceAll(' ', 'T');
      if (!iso.endsWith('Z') && !iso.contains('+') && !iso.contains('-')) {
        iso += 'Z';
      }
      return DateTime.parse(iso).millisecondsSinceEpoch ~/ 1000;
    } catch (_) {
      return 0;
    }
  }

  // ------------------------------- History ---------------------------------
  static List<DeviceItem> mapHistory(List<Map<String, dynamic>> raw) {
    return raw.map((e) => mapDeviceItem(e, {})).toList();
  }

  // ------------------------------- Alarms ----------------------------------
  static List<Event> mapAlarms(List<Map<String, dynamic>> raw) {
    return raw.map((item) {
      final imei = item['imei']?.toString() ?? '';
      int devId = 0;
      if (imei.length >= 9) {
        devId = int.tryParse(imei.substring(imei.length - 9)) ??
            imei.hashCode.abs();
      }
      return Event(
        id: item['id'] ?? DateTime.now().millisecondsSinceEpoch,
        message: item['alarmType']?.toString() ??
            item['content']?.toString() ??
            'Alarm',
        device_name: item['deviceName']?.toString() ?? imei,
        latitude: _d(item['lat']),
        longitude: _d(item['lng']),
        speed: _d(item['speed']),
      )..time = item['alarmTime']?.toString() ?? '';
    }).toList();
  }

  static double _d(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
}
