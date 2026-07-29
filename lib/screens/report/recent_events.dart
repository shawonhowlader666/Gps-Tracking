import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:smart_lock/services/model/event.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/util/app_lang.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  // Industry practice: Get.find() — existing singleton reuse
  // Get.put() never here — it can create a new empty instance
  DataController get controller => Get.find<DataController>();

  @override
  void initState() {
    super.initState();
    // Screen open হলে fresh fetch করো — কিন্তু existing events সাথে সাথে show হবে
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.getEvents();
    });
  }

  Future<void> _onRefresh() async {
    await controller.getEvents();
  }

  String _filterCategory = 'all';
  String _searchQuery = '';

  List<Event> _getFilteredEvents() {
    return controller.events.where((e) {
      final msg = (e.message ?? '').toLowerCase();
      // Completely exclude Idle events from events list
      if (msg.contains('idle')) return false;

      if (_filterCategory != 'all') {
        if (_filterCategory == 'engine') {
          if (!msg.contains('ignition') &&
              !msg.contains('engine') &&
              !msg.contains('acc')) return false;
        }
        if (_filterCategory == 'idle' && !msg.contains('idle')) return false;
        if (_filterCategory == 'speed') {
          final bool isSpeedMsg = msg.contains('speed') ||
              msg.contains('overspeed') ||
              msg.contains('fast');
          if (!isSpeedMsg) return false;
        }
        if (_filterCategory == 'geofence' &&
            !msg.contains('geofence') &&
            !msg.contains('zone')) return false;
        if (_filterCategory == 'sos' &&
            !msg.contains('sos') &&
            !msg.contains('alarm')) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final devName = (e.device_name ?? '').toLowerCase();
        final msg = (e.message ?? '').toLowerCase();
        final time = (e.time ?? '').toLowerCase();
        if (!devName.contains(q) && !msg.contains(q) && !time.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'recentEvents'.tr,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3142),
            ),
          ),
          Obx(() => Text(
                '${controller.events.length} ${'notifications'.tr}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey[500],
                ),
              )),
        ],
      ),
      actions: [
        if (controller.events.isNotEmpty)
          TextButton(
            onPressed: () => _showClearAllDialog(),
            child: Text(
              'clearAll'.tr,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE53935),
              ),
            ),
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: _buildAppBar(),
      body: Obx(() {
        final isLoading = controller.isEventLoading.value;
        final hasEvents = controller.events.isNotEmpty;

        if (isLoading && !hasEvents) {
          return _buildLoadingState();
        }

        final filtered = _getFilteredEvents();

        return RefreshIndicator(
          onRefresh: _onRefresh,
          color: const Color(0xFFC0392B),
          child: Column(
            children: [
              if (hasEvents) _buildFilterBar(),
              Expanded(
                child: filtered.isNotEmpty
                    ? _buildEventsList(filtered)
                    : _buildEmptyState(),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('all', 'All', Icons.grid_view_rounded),
            const SizedBox(width: 6),
            _buildFilterChip('engine', 'Engine', Icons.key_rounded),
            const SizedBox(width: 6),
            _buildFilterChip('speed', 'Speed', Icons.speed_rounded),
            const SizedBox(width: 6),
            _buildFilterChip('geofence', 'Geofence', Icons.location_on_rounded),
            const SizedBox(width: 6),
            _buildFilterChip('sos', 'SOS', Icons.sos_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String id, String label, IconData icon) {
    final bool isSelected = _filterCategory == id;
    return ChoiceChip(
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _filterCategory = id);
      },
      avatar: Icon(icon,
          size: 14,
          color: isSelected ? Colors.white : const Color(0xFF6B7280)),
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : const Color(0xFF374151),
      ),
      selectedColor: const Color(0xFFC0392B),
      backgroundColor: const Color(0xFFF3F4F6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    );
  }

  Widget _buildEventsList(List<Event> filteredList) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: filteredList.length,
      itemBuilder: (context, index) {
        final event = filteredList[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _SwipeableEventCard(
            event: event,
            onDelete: () => _deleteEvent(index),
            onTap: () {
              Navigator.pushNamed(
                context,
                "/notificationMap",
                arguments: ReportEventArgument(event),
              );
            },
          ),
        );
      },
    );
  }

  void _deleteEvent(int index) {
    final deletedEvent = controller.events[index];
    // Remove event
    controller.events.removeAt(index);

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Show undo snackbar
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.delete_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Event deleted',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: const Color(0xFF2D3142),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: const Color(0xFF6C63FF),
          onPressed: () {
            controller.events.insert(index, deletedEvent);
          },
        ),
      ),
    );
  }

  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Clear All Events?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              controller.events.clear();
              Navigator.pop(context);
              HapticFeedback.mediumImpact();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              elevation: 0,
            ),
            child:
                const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: 5,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        height: 14, width: 120, color: Colors.grey[200]),
                    const SizedBox(height: 8),
                    Container(
                        height: 12, width: 200, color: Colors.grey[100]),
                    const SizedBox(height: 6),
                    Container(
                        height: 10, width: 80, color: Colors.grey[100]),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
        Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 46,
              color: Color(0xFF6C63FF),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'noEvents'.tr,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3142),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'re all caught up!',
            style: TextStyle(fontSize: 15, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          // Pull down to refresh hint
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.arrow_downward_rounded,
                  size: 16, color: Colors.grey[400]),
              const SizedBox(width: 6),
              Text(
                'Pull down to refresh',
                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Swipeable Event Card Widget
class _SwipeableEventCard extends StatelessWidget {
  final Event event;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _SwipeableEventCard({
    required this.event,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(event.id.toString() + DateTime.now().toString()),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      confirmDismiss: (direction) async {
        HapticFeedback.lightImpact();
        return true;
      },
      background: _buildDeleteBackground(),
      child: _buildCard(context),
    );
  }

  Widget _buildDeleteBackground() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.delete_outline_rounded,
            color: Colors.white,
            size: 28,
          ),
          SizedBox(height: 4),
          Text(
            'Delete',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Formats raw time string to 12-hour AM/PM format without double timezone offset shifting
  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      // 1. If server already sent 12-hour formatted time (e.g. "29-07-2026 04:10:00 PM")
      if (raw.contains('AM') || raw.contains('PM') || raw.contains('am') || raw.contains('pm')) {
        final parts = raw.trim().split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          final datePart = parts[0];
          final timePart = parts[1];
          final period = parts[2].toUpperCase();
          final timeSegments = timePart.split(':');
          if (timeSegments.length >= 2) {
            final h = int.tryParse(timeSegments[0]) ?? 12;
            final m = timeSegments[1];
            final displayH = h % 12 == 0 ? 12 : h % 12;
            return '${AppLang.num(datePart)} ${AppLang.num('$displayH:$m')} $period';
          }
        }
        return AppLang.num(raw);
      }

      // 2. Parse ISO/Standard Date Format "2026-07-29 16:10:00"
      final cleanRaw = raw.replaceAll('Z', '').replaceAll('T', ' ');
      final dt = DateTime.parse(cleanRaw);
      final int h = dt.hour;
      final int m = dt.minute;
      final String period = h >= 12 ? 'PM' : 'AM';
      final int displayH = h % 12 == 0 ? 12 : h % 12;
      final String datePart =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final String timeStr = '$datePart $displayH:${m.toString().padLeft(2, '0')} $period';
      return AppLang.num(timeStr);
    } catch (_) {
      return AppLang.num(raw);
    }
  }

  Widget _buildCard(BuildContext context) {
    final eventStyle = _getEventStyle(event.message ?? '');

    return Material(
      color: Colors.grey,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
            border: Border.all(color: Colors.grey),
          ),
          child: Row(
            children: [
              // Event Icon
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      eventStyle.color,
                      eventStyle.color.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: eventStyle.color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  eventStyle.icon,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.device_name ?? 'Unknown Device',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2D3142),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: eventStyle.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            eventStyle.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: eventStyle.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      event.message?.tr ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(event.time),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[500],
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: Colors.grey[400],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _EventStyle _getEventStyle(String message) {
    message = message.toLowerCase();

    if (message.contains('alarm') ||
        message.contains('sos') ||
        message.contains('alert')) {
      return _EventStyle(
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFF64A46),
        label: 'ALERT',
      );
    } else if (message.contains('speed')) {
      return _EventStyle(
        icon: Icons.speed_rounded,
        color: const Color(0xFFF88A62),
        label: 'SPEED',
      );
    } else if (message.contains('geofence')) {
      return _EventStyle(
        icon: Icons.location_on_rounded,
        color: const Color(0xFFDF58F6),
        label: 'ZONE',
      );
    } else if (message.contains('idle')) {
      return _EventStyle(
        icon: Icons.pause_circle_filled_rounded,
        color: const Color(0xFFFFD600),
        label: 'IDLE',
      );
    } else if (message.contains('ignition')) {
      return _EventStyle(
        icon: Icons.power_settings_new_rounded,
        color: const Color(0xFF81F4B1),
        label: 'ENGINE',
      );
    } else if (message.contains('online')) {
      return _EventStyle(
        icon: Icons.wifi_rounded,
        color: const Color(0xFF3CDCF1),
        label: 'ONLINE',
      );
    } else if (message.contains('offline')) {
      return _EventStyle(
        icon: Icons.wifi_off_rounded,
        color: const Color(0xFF6E8A98),
        label: 'OFFLINE',
      );
    } else if (message.contains('fuel')) {
      return _EventStyle(
        icon: Icons.local_gas_station_rounded,
        color: const Color(0xFFFBC74E),
        label: 'FUEL',
      );
    } else if (message.contains('battery')) {
      return _EventStyle(
        icon: Icons.battery_alert_rounded,
        color: const Color(0xFFFA538B),
        label: 'BATTERY',
      );
    }

    return _EventStyle(
      icon: Icons.notifications_rounded,
      color: const Color(0xFF7A72FB),
      label: 'INFO',
    );
  }
}

class _EventStyle {
  final IconData icon;
  final Color color;
  final String label;

  _EventStyle({
    required this.icon,
    required this.color,
    required this.label,
  });
}

class ReportEventArgument {
  final Event event;
  ReportEventArgument(this.event);
}
