import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/services/tracksolid_client.dart';
import 'package:gpspro/services/tracksolid_mapper.dart';
import 'package:gpspro/services/model/device.dart';
import 'package:gpspro/services/model/device_item.dart';
import 'package:gpspro/services/model/event.dart';

/// High‑level repository that orchestrates token lifecycle, caching and error handling.
class TracksolidRepository {
  final TracksolidClient _client = TracksolidClient();

  // ---------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------
  Future<bool> login(String account, String password) async {
    final token = await _client.login(account: account, password: password);
    if (token == null) return false;
    // Persist token & account for later API calls.
    UserRepository.setTracksolidToken(token);
    UserRepository.setTracksolidAccount(account);
    UserRepository.setApiMode('tracksolid');
    return true;
  }

  // ---------------------------------------------------------------------
  // Device list with real‑time data
  // ---------------------------------------------------------------------
  Future<List<Device>?> getDevices() async {
    final token = UserRepository.getTracksolidToken();
    if (token == null) return null;

    // 1️⃣ fetch device catalogue
    final target = UserRepository.getTracksolidAccount() ?? '';
    final devices = await _client.deviceList(token, target);
    if (devices.isEmpty) return [];

    // 2️⃣ fetch real‑time info for all IMEIs (batched internally)
    final imeis = devices
        .map((d) => d['imei']?.toString() ?? '')
        .where((i) => i.isNotEmpty)
        .toList();
    final infos = await _client.currentInfo(token, imeis);

    // 3️⃣ merge catalogue + real‑time info into a single list of DeviceItem
    final merged = devices.map((device) {
      final imei = device['imei']?.toString() ?? '';
      final info = infos.firstWhere((e) => e['imei']?.toString() == imei,
          orElse: () => {});
      return TracksolidMapper.mapDeviceItem(device, info);
    }).toList();

    // 4️⃣ Wrap into a single group for UI consumption.
    return [Device(id: 1, title: 'All Devices', items: merged)];
  }

  // ---------------------------------------------------------------------
  // History (playback)
  // ---------------------------------------------------------------------
  Future<List<DeviceItem>?> getHistory(String imei, DateTime from, DateTime to) async {
    final token = UserRepository.getTracksolidToken();
    if (token == null) return null;
    final raw = await _client.history(
        token,
        imei,
        '${from.year}-${_pad(from.month)}-${_pad(from.day)} ${_pad(from.hour)}:${_pad(from.minute)}:${_pad(from.second)}',
        '${to.year}-${_pad(to.month)}-${_pad(to.day)} ${_pad(to.hour)}:${_pad(to.minute)}:${_pad(to.second)}');
    return TracksolidMapper.mapHistory(raw);
  }

  // ---------------------------------------------------------------------
  // Alarms / events
  // ---------------------------------------------------------------------
  Future<List<Event>?> getAlarms({String? imei}) async {
    final token = UserRepository.getTracksolidToken();
    if (token == null) return null;
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 2));
    final raw = await _client.alarms(
        token,
        imei: imei,
        from: from,
        to: now,
        page: 1,
        limit: 50);
    return TracksolidMapper.mapAlarms(raw);
  }

  // ---------------------------------------------------------------------
  // Engine control (lock/unlock)
  // ---------------------------------------------------------------------
  Future<bool> controlEngine(String imei, bool lock) async {
    final token = UserRepository.getTracksolidToken();
    if (token == null) return false;
    final command = lock ? 'close_relay' : 'open_relay';
    return await _client.control(token, imei, command);
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
