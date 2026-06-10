import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:smart_lock/screens/lock_unlock_screen.dart';
import 'package:smart_lock/screens/playback.dart';
import 'package:smart_lock/screens/track_device.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
import 'package:smart_lock/widgets/address.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:smart_lock/storage/user_repository.dart';

class DeviceDetailsScreen extends StatefulWidget {
  final DeviceItem device;

  const DeviceDetailsScreen({super.key, required this.device});

  @override
  State<DeviceDetailsScreen> createState() => _DeviceDetailsScreenState();
}

class _DeviceDetailsScreenState extends State<DeviceDetailsScreen> {
  static const Color _primary = Color(0xFFC0392B);
  static const Color _green = Color(0xFF27AE60);
  static const Color _orange = Color(0xFFE67E22);
  static const Color _grey = Color(0xFF888888);
  static const Color _red = Color(0xFFE74C3C);

  late Rx<DeviceItem> _device;

  @override
  void initState() {
    super.initState();
    _device = widget.device.obs;
  }

  // ── Status helpers ──────────────────────────────────────────────────────

  bool _isDeviceOnline(DeviceItem d) {
    final online = d.online?.toLowerCase().trim() ?? '';
    if (online.contains('offline')) return false;
    if (online.contains('online')) return true;
    final iconColor = d.iconColor?.toLowerCase().trim() ?? '';
    if (iconColor == 'green' || iconColor == 'yellow') return true;
    if (d.timestamp != null && d.timestamp! > 0) {
      try {
        final lastUpdate =
        DateTime.fromMillisecondsSinceEpoch(d.timestamp! * 1000);
        return DateTime.now().difference(lastUpdate).inMinutes < 5;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  bool _isEngineOn(DeviceItem d) {
    final speed = double.tryParse(d.speed.toString()) ?? 0;
    if (speed > 0) return true;
    if (d.engineStatus != null) {
      final s = d.engineStatus;
      if (s is bool) return s;
      if (s is int) return s == 1;
      if (s is String) {
        final v = s.toLowerCase().trim();
        if (['on', '1', 'true', 'ign on', 'engine on', 'acc on'].contains(v))
          return true;
        if (['off', '0', 'false', 'ign off', 'engine off', 'acc off']
            .contains(v)) return false;
      }
    }
    if (d.sensors != null) {
      for (var sensor in d.sensors!) {
        try {
          if (sensor is! Map) continue;
          final sensorMap = Map<String, dynamic>.from(sensor);
          final type = (sensorMap['type'] ?? '').toString().toLowerCase();
          final name = (sensorMap['name'] ?? '').toString().toLowerCase();
          final value = sensorMap['value'];
          if (type == 'acc' ||
              type == 'ignition' ||
              name.contains('acc') ||
              name.contains('ignition')) {
            if (value == null) continue;
            if (value is bool) return value;
            if (value is int) return value == 1;
            if (value is String) {
              final v = value.toLowerCase().trim();
              if (['on', '1', 'true'].contains(v)) return true;
              if (['off', '0', 'false'].contains(v)) return false;
            }
          }
        } catch (_) {
          continue;
        }
      }
    }
    final iconColor = d.iconColor?.toLowerCase().trim() ?? '';
    return iconColor == 'yellow' || iconColor == 'green';
  }

  String _getStatusText(DeviceItem d) {
    if (!_isDeviceOnline(d)) return 'OFFLINE';
    final speed = double.tryParse(d.speed.toString()) ?? 0;
    if (speed > 0) return 'RUNNING';
    if (_isEngineOn(d)) return 'IDLE';
    return 'STOPPED';
  }

  Color _getStatusColor(DeviceItem d) {
    switch (_getStatusText(d)) {
      case 'RUNNING':
        return _green;
      case 'IDLE':
        return _orange;
      case 'OFFLINE':
        return _red;
      default:
        return _grey;
    }
  }

  bool _isUnlocked(DeviceItem d) {
    final status = d.engineStatus;
    if (status == null) return false;
    if (status is bool) return status;
    if (status is int) return status == 1;
    if (status is String) {
      final v = status.toLowerCase().trim();
      return ['on', '1', 'true', 'ign on', 'engine on', 'acc on'].contains(v);
    }
    return false;
  }

  String _getLockStatus(DeviceItem d) =>
      _isUnlocked(d) ? 'Unlocked' : 'Locked';

  Color _getLockColor(DeviceItem d) => _isUnlocked(d) ? _green : _red;

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is String && date.isNotEmpty) {
      try {
        return DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.parse(date));
      } catch (_) {
        return date;
      }
    }
    return date.toString();
  }

  String _getTodayMileage(DeviceItem d) {
    final v = d.deviceData?.todayMileage;
    if (v == null) return '0.00 km';
    return '${(double.tryParse(v.toString()) ?? 0.0).toStringAsFixed(2)} km';
  }

  String _getOdometer(DeviceItem d) {
    final t = d.totalDistance;
    if (t == null) return '0.00 km';
    return '${(double.tryParse(t.toString()) ?? 0.0).toStringAsFixed(2)} km';
  }

  String _getTodayFuelCost(DeviceItem d) {
    final f = d.deviceData?.fuelQuantity;
    if (f == null || f.isEmpty) return '0.00 L';
    return '${(double.tryParse(f) ?? 0.0).toStringAsFixed(2)} L';
  }

  List<Map<String, dynamic>> _parseSensors(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return [];
    final result = <Map<String, dynamic>>[];
    for (final s in raw) {
      try {
        if (s is Map) {
          result.add(Map<String, dynamic>.from(s));
        }
      } catch (_) {
        continue;
      }
    }
    return result;
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied: $text'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Future<void> _openMaps(DeviceItem d) async {
    if (d.lat == null || d.lng == null) return;
    final url = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${d.lat},${d.lng}');
    if (await canLaunchUrl(url))
      launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _navigate(DeviceItem d) async {
    if (d.lat == null || d.lng == null) return;
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${d.lat},${d.lng}&travelmode=driving');
    if (await canLaunchUrl(url))
      launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _callSim(DeviceItem d) async {
    final sim = d.deviceData?.simNumber ?? '';
    if (sim.isEmpty) return;
    final url = Uri(scheme: 'tel', path: sim);
    if (await canLaunchUrl(url)) launchUrl(url);
  }

  void _openPlayback(DeviceItem d) {
    Get.to(() => PlaybackScreen(id: d.id, name: d.name, device: d));
  }

  void _openTracking(DeviceItem d) {
    Get.to(() => TrackDevicePage(d.id, d.name, d));
  }

  // ── FIX: LockUnlockScreen এখন DeviceItem return করে, LockUnlockResult নয় ──
  void _openLockUnlock(DeviceItem d) async {
    final result = await Get.to<DeviceItem>(
          () => LockUnlockScreen(device: d),
    );
    if (result != null && mounted) {
      _device.value = result;
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final d = _device.value;

      final rawSensors = d.sensors?.isNotEmpty == true
          ? d.sensors!
          : (d.deviceData?.sensors ?? []);
      final sensorList = _parseSensors(rawSensors);

      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _device.value),
          ),
          title: const Text(
            'Device Details',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          ),
        ),
        body: ListView(
          children: [
            // ── Section 1: Identity ─────────────────────────────────────
            _Section(children: [
              _Row(
                icon: Icons.settings_input_antenna,
                label: 'Device Name',
                value: d.name ?? 'N/A',
                hasChevron: true,
                onTap: () => _copyToClipboard(d.name ?? ''),
              ),
              _Row(
                icon: Icons.badge_outlined,
                label: 'IMEI',
                value: d.deviceData?.imei ?? 'N/A',
                onTap: () => _copyToClipboard(d.deviceData?.imei ?? ''),
              ),
              _Row(
                icon: Icons.access_time_outlined,
                label: 'Expiration',
                value: _formatDate(d.deviceData?.expirationDate),
              ),
              _Row(
                icon: Icons.sim_card_outlined,
                label: 'SIM',
                value: d.deviceData?.simNumber ?? 'N/A',
                valueColor: _primary,
                hasChevron: true,
                onTap: () => _callSim(d),
              ),
              _Row(
                icon: Icons.grid_view_rounded,
                label: 'Device Icons',
                value: '',
                hasChevron: true,
                customTrailing: d.icon?.path != null
                    ? Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: CachedNetworkImage(
                    imageUrl:
                    "${UserRepository.getServerUrl()}/${d.icon!.path!}",
                    width: 28,
                    height: 28,
                    errorWidget: (_, __, ___) =>
                    const SizedBox.shrink(),
                  ),
                )
                    : null,
                onTap: () {},
              ),
            ]),

            const _Separator(),

            // ── Section 2: Status ───────────────────────────────────────
            _Section(children: [
              _Row(
                icon: Icons.error_outline,
                label: 'Status',
                value: _getStatusText(d),
                valueColor: _getStatusColor(d),
              ),
              _Row(
                icon: Icons.settings_outlined,
                label: 'ACC',
                value: _isEngineOn(d) ? 'ON' : 'OFF',
                valueColor: _isEngineOn(d) ? _green : _grey,
              ),
              _Row(
                icon: Icons.lock_outline,
                label: 'Lock status',
                value: _getLockStatus(d),
                valueColor: _getLockColor(d),
              ),
            ]),

            const _Separator(),

            // ── Section 3: Location & Time ──────────────────────────────
            _Section(children: [
              _Row(
                icon: Icons.my_location,
                label: 'Location Time',
                value: d.timestamp != null
                    ? _formatTimestamp(d.timestamp!)
                    : 'N/A',
              ),
              _Row(
                icon: Icons.show_chart,
                label: 'Latest Update',
                value: d.deviceData?.updatedAt != null
                    ? _formatDate(d.deviceData!.updatedAt!)
                    : (d.timestamp != null
                    ? _formatTimestamp(d.timestamp!)
                    : 'N/A'),
              ),
              _Row(
                icon: Icons.storage_outlined,
                label: 'Server Time',
                value: d.timestamp != null
                    ? _formatTimestamp(d.timestamp!)
                    : 'N/A',
              ),
              _AddressRow(
                lat: d.lat?.toString() ?? '',
                lng: d.lng?.toString() ?? '',
                onTap: () => _openMaps(d),
              ),
            ]),

            const _Separator(),

            // ── Section 4: Stats ────────────────────────────────────────
            _Section(children: [
              _Row(
                icon: Icons.speed_outlined,
                label: 'Today Mileage',
                value: _getTodayMileage(d),
              ),
              _Row(
                icon: Icons.show_chart,
                label: 'Odometer',
                value: _getOdometer(d),
                hasChevron: true,
                onTap: () {},
              ),
              _Row(
                icon: Icons.local_gas_station_outlined,
                label: 'Today Fuel Cost',
                value: _getTodayFuelCost(d),
                hasChevron: true,
                onTap: () {},
              ),
            ]),

            // ── Section 5: Sensors ──────────────────────────────────────
            if (sensorList.isNotEmpty) ...[
              const _Separator(),
              _SensorsSection(sensors: sensorList),
            ],

            const SizedBox(height: 8),

            // ── Action Buttons ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'Navigate',
                      color: _primary,
                      onPressed: () => _navigate(d),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionButton(
                      label: 'Track Live',
                      color: _green,
                      onPressed: () => _openTracking(d),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'Playback',
                      color: _orange,
                      outlined: true,
                      onPressed: () => _openPlayback(d),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionButton(
                      label: 'Lock / Unlock',
                      color: _primary,
                      outlined: true,
                      onPressed: () => _openLockUnlock(d),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ── Sensors Section ───────────────────────────────────────────────────────────

class _SensorsSection extends StatelessWidget {
  final List<Map<String, dynamic>> sensors;

  const _SensorsSection({required this.sensors});

  IconData _getSensorIcon(String type, String name) {
    final t = type.toLowerCase();
    final n = name.toLowerCase();

    if (t == 'acc' ||
        t == 'ignition' ||
        n.contains('ignition') ||
        n.contains('acc')) {
      return Icons.power_settings_new_outlined;
    }
    if (t == 'fuel' || n.contains('fuel')) {
      return Icons.local_gas_station_outlined;
    }
    if (t == 'temp' || t == 'temperature' || n.contains('temp')) {
      return Icons.thermostat_outlined;
    }
    if (t == 'door' || n.contains('door')) {
      return Icons.door_front_door_outlined;
    }
    if (t == 'voltage' ||
        t == 'battery' ||
        n.contains('voltage') ||
        n.contains('battery')) {
      return Icons.battery_charging_full_outlined;
    }
    if (t == 'rpm' || n.contains('rpm')) {
      return Icons.speed_outlined;
    }
    if (t == 'gsm' || n.contains('gsm') || n.contains('signal')) {
      return Icons.signal_cellular_alt_outlined;
    }
    if (t == 'gps' || n.contains('gps') || n.contains('sat')) {
      return Icons.gps_fixed_outlined;
    }
    if (t == 'odometer' || n.contains('odometer') || n.contains('mileage')) {
      return Icons.route_outlined;
    }
    if (n.contains('engine') || t.contains('engine')) {
      return Icons.engineering_outlined;
    }
    if (n.contains('speed')) {
      return Icons.speed_outlined;
    }
    if (n.contains('alarm') || t.contains('alarm')) {
      return Icons.notifications_outlined;
    }
    return Icons.sensors;
  }

  String _formatSensorValue(dynamic value, String type, String name) {
    if (value == null) return 'N/A';

    final t = type.toLowerCase();
    final n = name.toLowerCase();
    final isBooleanType = t == 'acc' ||
        t == 'ignition' ||
        t == 'door' ||
        n.contains('ignition') ||
        n.contains('acc') ||
        n.contains('door') ||
        n.contains('alarm');

    if (value is bool) return value ? 'ON' : 'OFF';

    if (value is int) {
      if (isBooleanType) return value == 1 ? 'ON' : 'OFF';
      return value.toString();
    }

    if (value is double) {
      return value.toStringAsFixed(2);
    }

    if (value is String) {
      final lower = value.toLowerCase().trim();
      if (['1', 'true', 'on', 'yes', 'active'].contains(lower)) return 'ON';
      if (['0', 'false', 'off', 'no', 'inactive'].contains(lower)) return 'OFF';
      final num = double.tryParse(value);
      if (num != null) return num.toStringAsFixed(2);
      return value;
    }

    return value.toString();
  }

  String _getUnit(String type, String name) {
    final t = type.toLowerCase();
    final n = name.toLowerCase();
    if (t == 'fuel' || n.contains('fuel')) return ' L';
    if (t == 'temp' || t == 'temperature' || n.contains('temp')) return ' °C';
    if (t == 'voltage' || n.contains('voltage')) return ' V';
    if (t == 'rpm' || n.contains('rpm')) return ' RPM';
    if (n.contains('speed')) return ' km/h';
    if (n.contains('mileage') || n.contains('odometer')) return ' km';
    if (n.contains('gsm') || n.contains('signal')) return ' dBm';
    return '';
  }

  Color _getValueColor(String formatted) {
    if (formatted == 'ON') return const Color(0xFF27AE60);
    if (formatted == 'OFF') return const Color(0xFF888888);
    if (formatted == 'N/A') return const Color(0xFFAAAAAA);
    return const Color(0xFF444444);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Text(
              'SENSORS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey[500],
                letterSpacing: 1.2,
              ),
            ),
          ),
          ...List.generate(sensors.length, (i) {
            final sensorMap = sensors[i];

            final type = (sensorMap['type'] ?? '').toString();
            final name =
            (sensorMap['name'] ?? 'Sensor ${i + 1}').toString();
            final value = sensorMap['value'];

            final formatted = _formatSensorValue(value, type, name);
            final unit = (formatted == 'ON' ||
                formatted == 'OFF' ||
                formatted == 'N/A')
                ? ''
                : _getUnit(type, name);

            return Column(
              children: [
                _Row(
                  icon: _getSensorIcon(type, name),
                  label: name,
                  value: '$formatted$unit',
                  valueColor: _getValueColor(formatted),
                ),
                if (i < sensors.length - 1)
                  const Divider(
                    height: 1,
                    indent: 56,
                    color: Color(0xFFF0F0F0),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ── Reusable Widgets ──────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final List<Widget> children;

  const _Section({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: List.generate(children.length, (i) {
          return Column(
            children: [
              children[i],
              if (i < children.length - 1)
                const Divider(height: 1, indent: 56, color: Color(0xFFF0F0F0)),
            ],
          );
        }),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 8, child: ColoredBox(color: Color(0xFFF5F5F5)));
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool hasChevron;
  final VoidCallback? onTap;
  final Widget? customTrailing;

  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.hasChevron = false,
    this.onTap,
    this.customTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFC0392B), size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style:
                  const TextStyle(fontSize: 14, color: Color(0xFF222222))),
            ),
            if (customTrailing != null) customTrailing!,
            if (value.isNotEmpty)
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                      fontSize: 14,
                      color: valueColor ?? const Color(0xFF444444)),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            if (hasChevron) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  color: Color(0xFFCCCCCC), size: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final String lat;
  final String lng;
  final VoidCallback? onTap;

  const _AddressRow({required this.lat, required this.lng, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on_outlined,
                color: Color(0xFFC0392B), size: 22),
            const SizedBox(width: 14),
            const Text('Address',
                style: TextStyle(fontSize: 14, color: Color(0xFF222222))),
            const SizedBox(width: 12),
            Expanded(child: addressLoadMarque(lat, lng)),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool outlined;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.label,
    required this.color,
    this.outlined = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label,
            style:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );
    }
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }
}