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
import 'package:smart_lock/screens/common_method.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class DeviceDetailsScreen extends StatefulWidget {
  final DeviceItem device;

  const DeviceDetailsScreen({super.key, required this.device});

  @override
  State<DeviceDetailsScreen> createState() => _DeviceDetailsScreenState();
}

class _DeviceDetailsScreenState extends State<DeviceDetailsScreen> {
  // ── Theme colors ─────────────────────────────────────────────────────────
  static const Color _primary = Color(0xFFC0392B);
  static const Color _green = Color(0xFF27AE60);
  static const Color _orange = Color(0xFFE67E22);
  static const Color _grey = Color(0xFF888888);
  static const Color _red = Color(0xFFE74C3C);

  late DeviceItem device;

  @override
  void initState() {
    super.initState();
    device = widget.device;
  }

  // ── Status helpers ────────────────────────────────────────────────────────

  bool _isDeviceOnline() {
    final online = device.online?.toLowerCase().trim() ?? '';
    if (online.contains('offline')) return false;
    if (online.contains('online')) return true;
    final iconColor = device.iconColor?.toLowerCase().trim() ?? '';
    if (iconColor == 'green' || iconColor == 'yellow') return true;
    if (device.timestamp != null && device.timestamp! > 0) {
      try {
        final lastUpdate =
        DateTime.fromMillisecondsSinceEpoch(device.timestamp! * 1000);
        return DateTime.now().difference(lastUpdate).inMinutes < 5;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  bool _isEngineOn() {
    final speed = double.tryParse(device.speed.toString()) ?? 0;
    if (speed > 0) return true;
    if (device.engineStatus != null) {
      final s = device.engineStatus;
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
    if (device.sensors != null) {
      for (var sensor in device.sensors!) {
        try {
          final type = (sensor['type'] ?? '').toString().toLowerCase();
          final name = (sensor['name'] ?? '').toString().toLowerCase();
          final value = sensor['value'];
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
    final iconColor = device.iconColor?.toLowerCase().trim() ?? '';
    return iconColor == 'yellow' || iconColor == 'green';
  }

  String _getStatusText() {
    if (!_isDeviceOnline()) return 'OFFLINE';
    final speed = double.tryParse(device.speed.toString()) ?? 0;
    if (speed > 0) return 'RUNNING';
    if (_isEngineOn()) return 'IDLE';
    return 'STOPPED';
  }

  Color _getStatusColor() {
    final s = _getStatusText();
    switch (s) {
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

  String _getLockStatus() {
    // Customize based on your DeviceItem lock field
    final lock = device.deviceData?.lockStatus?.toLowerCase() ?? '';
    if (lock == 'locked' || lock == '1' || lock == 'true') return 'Locked';
    return 'Unlocked';
  }

  Color _getLockColor() {
    return _getLockStatus() == 'Locked' ? _red : _green;
  }

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

  String _getTodayMileage() {
    final d = device.deviceData?.todayMileage;
    if (d == null) return '0.00 km';
    final val = double.tryParse(d.toString()) ?? 0.0;
    return '${val.toStringAsFixed(2)} km';
  }

  String _getOdometer() {
    final t = device.totalDistance;
    if (t == null) return '0.00 km';
    return '${t.toStringAsFixed(2)} km';
  }

  String _getTodayFuelCost() {
    final f = device.deviceData?.fuelQuantity;
    if (f == null || f.isEmpty) return '0.00 L';
    final val = double.tryParse(f) ?? 0.0;
    return '${val.toStringAsFixed(2)} L';
  }

  // ── Actions ───────────────────────────────────────────────────────────────

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

  Future<void> _openMaps() async {
    if (device.lat == null || device.lng == null) return;
    final url = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${device.lat},${device.lng}');
    if (await canLaunchUrl(url))
      launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _navigate() async {
    if (device.lat == null || device.lng == null) return;
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${device.lat},${device.lng}&travelmode=driving');
    if (await canLaunchUrl(url))
      launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _callSim() async {
    final sim = device.deviceData?.simNumber ?? '';
    if (sim.isEmpty) return;
    final url = Uri(scheme: 'tel', path: sim);
    if (await canLaunchUrl(url)) launchUrl(url);
  }

  void _openPlayback() {
    Get.to(() => PlaybackScreen(
      id: device.id,
      name: device.name,
      device: device,
    ));
  }

  void _openTracking() {
    Get.to(() => TrackDevicePage(device.id, device.name, device));
  }

  void _openLockUnlock() {
    Get.to(() => LockUnlockScreen(device: device));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Device Details',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
      ),
      body: ListView(
        children: [
          // ── Section 1: Identity ─────────────────────────────────────────
          _Section(children: [
            _Row(
              icon: Icons.settings_input_antenna,
              label: 'Device Name',
              value: device.name ?? 'N/A',
              hasChevron: true,
              onTap: () => _copyToClipboard(device.name ?? ''),
            ),
            _Row(
              icon: Icons.badge_outlined,
              label: 'IMEI',
              value: device.deviceData?.imei ?? 'N/A',
              onTap: () => _copyToClipboard(device.deviceData?.imei ?? ''),
            ),
            _Row(
              icon: Icons.access_time_outlined,
              label: 'Expiration',
              value: _formatDate(device.deviceData?.expirationDate),
            ),
            _Row(
              icon: Icons.sim_card_outlined,
              label: 'SIM',
              value: device.deviceData?.simNumber ?? 'N/A',
              valueColor: _primary,
              hasChevron: true,
              onTap: _callSim,
            ),
            _Row(
              icon: Icons.grid_view_rounded,
              label: 'Device Icons',
              value: '',
              hasChevron: true,
              customTrailing: device.icon?.path != null
                  ? Padding(
                padding: const EdgeInsets.only(right: 4),
                child: CachedNetworkImage(
                  imageUrl:
                  "${UserRepository.getServerUrl()}/${device.icon!.path!}",
                  width: 28,
                  height: 28,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              )
                  : null,
              onTap: () {},
            ),
          ]),

          const _Separator(),

          // ── Section 2: Status ───────────────────────────────────────────
          _Section(children: [
            _Row(
              icon: Icons.error_outline,
              label: 'Status',
              value: _getStatusText(),
              valueColor: _getStatusColor(),
            ),
            _Row(
              icon: Icons.settings_outlined,
              label: 'ACC',
              value: _isEngineOn() ? 'ON' : 'OFF',
              valueColor: _isEngineOn() ? _green : _grey,
            ),
            _Row(
              icon: Icons.lock_outline,
              label: 'Lock status',
              value: _getLockStatus(),
              valueColor: _getLockColor(),
            ),
          ]),

          const _Separator(),

          // ── Section 3: Location & Time ──────────────────────────────────
          _Section(children: [
            _Row(
              icon: Icons.my_location,
              label: 'Location Time',
              value: device.timestamp != null
                  ? _formatTimestamp(device.timestamp!)
                  : 'N/A',
            ),
            _Row(
              icon: Icons.show_chart,
              label: 'Latest Update',
              value: device.deviceData?.updatedAt != null
                  ? _formatDate(device.deviceData!.updatedAt!)
                  : (device.timestamp != null
                  ? _formatTimestamp(device.timestamp!)
                  : 'N/A'),
            ),
            _Row(
              icon: Icons.storage_outlined,
              label: 'Server Time',
              value: device.timestamp != null
                  ? _formatTimestamp(device.timestamp!)
                  : 'N/A',
            ),
            _AddressRow(
              lat: device.lat?.toString() ?? '',
              lng: device.lng?.toString() ?? '',
              onTap: _openMaps,
            ),
          ]),

          const _Separator(),

          // ── Section 4: Stats ────────────────────────────────────────────
          _Section(children: [
            _Row(
              icon: Icons.speed_outlined,
              label: 'Today Mileage',
              value: _getTodayMileage(),
            ),
            _Row(
              icon: Icons.show_chart,
              label: 'Odometer',
              value: _getOdometer(),
              hasChevron: true,
              onTap: () {},
            ),
            _Row(
              icon: Icons.local_gas_station_outlined,
              label: 'Today Fuel Cost',
              value: _getTodayFuelCost(),
              hasChevron: true,
              onTap: () {},
            ),
          ]),

          const SizedBox(height: 8),

          // ── Action Buttons ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Navigate',
                    color: _primary,
                    onPressed: _navigate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    label: 'Track Live',
                    color: _green,
                    onPressed: _openTracking,
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
                    onPressed: _openPlayback,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    label: 'Lock / Unlock',
                    color: _primary,
                    outlined: true,
                    onPressed: _openLockUnlock,
                  ),
                ),
              ],
            ),
          ),
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
                const Divider(
                    height: 1, indent: 56, color: Color(0xFFF0F0F0)),
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
              child: Text(
                label,
                style:
                const TextStyle(fontSize: 14, color: Color(0xFF222222)),
              ),
            ),
            if (customTrailing != null) customTrailing!,
            if (value.isNotEmpty)
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: valueColor ?? const Color(0xFF444444),
                  ),
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

  const _AddressRow({
    required this.lat,
    required this.lng,
    this.onTap,
  });

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
            const Text(
              'Address',
              style: TextStyle(fontSize: 14, color: Color(0xFF222222)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: addressLoadMarque(lat, lng),
            ),
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
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600)),
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
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }
}