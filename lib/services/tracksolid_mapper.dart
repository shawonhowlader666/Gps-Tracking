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

    final lat = _d(info['lat']);
    final lng = _d(info['lng']);
    final speed = _d(info['speed']);
    final course = _d(info['direction']);
    final altitude = _d(info['altitude']);
    final status = _i(info['status']); // 0=offline,1=stop,2=move,3=idle

    final String iconColor = _statusToIconColor(status);
    final String online = status == 0 ? 'ack' : 'online';

    final int acc = _i(info['accStatus']);
    final String power = info['voltage']?.toString() ?? '';
    final int alarm = _i(info['alarm']);
    final String timestampStr = info['gpsTime']?.toString() ?? '';
    final int timestamp = _parseTimestamp(timestampStr);
    final dynamic mileage = info['mileage'];

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
      speed: speed,
      altitude: altitude,
      iconColor: iconColor,
      power: power,
      engineStatus: acc,
      totalDistance: mileage,
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
      // Tracksolid returns "2023-09-01 12:34:56"
      return DateTime.parse(time.replaceAll(' ', 'T')).millisecondsSinceEpoch ~/
          1000;
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
