import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:gpspro/services/model/event.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';

class EventsPage extends StatefulWidget {
  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  final DataController controller = Get.put(DataController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: _buildAppBar(),
      body: Obx(() {
        if (controller.events.isEmpty) {
          return _buildEmptyState();
        }
        return _buildEventsList();
      }),
    );
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
        // In EventsPage AppBar actions
        // FloatingActionButton(
        //   mini: true,
        //   onPressed: () {
        //     final DataController controller = Get.find();
        //     controller.sendTestNotification();
        //   },
        //   child: Icon(Icons.notification_add),
        // )
      ],
    );

  }

  Widget _buildEventsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: controller.events.length,
      itemBuilder: (context, index) {
        final event = controller.events[index];
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
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 50,
              color: Color(0xFF6C63FF),
            ),
          ),
          const SizedBox(height: 24),
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
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[500],
            ),
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
                          event.time ?? '',
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

    if (message.contains('alarm') || message.contains('sos') || message.contains('alert')) {
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