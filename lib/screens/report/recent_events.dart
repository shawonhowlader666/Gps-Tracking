import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:gpspro/services/model/event.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/theme/custom_color.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final DataController controller = Get.put(DataController());
  late AnimationController _pulseController;
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  List<Event> _getFilteredEvents() {
    final rawEvents = controller.events;
    if (_selectedFilter == 'all') {
      return rawEvents;
    }
    return rawEvents.where((event) {
      final msg = (event.message ?? '').toLowerCase();
      if (_selectedFilter == 'engine') {
        return msg.contains('ignition') || msg.contains('engine');
      } else if (_selectedFilter == 'speed') {
        return msg.contains('speed');
      } else if (_selectedFilter == 'zone') {
        return msg.contains('geofence') || msg.contains('zone') || msg.contains('fence');
      } else if (_selectedFilter == 'alarm') {
        return msg.contains('alarm') || msg.contains('sos') || msg.contains('alert') || msg.contains('cut') || msg.contains('vibration') || msg.contains('battery');
      }
      return true;
    }).toList();
  }

  Widget _buildFilterBar() {
    final filters = [
      {'id': 'all', 'label': 'All'},
      {'id': 'engine', 'label': 'Engine'},
      {'id': 'speed', 'label': 'Speed'},
      {'id': 'zone', 'label': 'Zone'},
      {'id': 'alarm', 'label': 'Alarms'},
    ];

    return Container(
      height: 48,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _selectedFilter == filter['id'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedFilter = filter['id']!;
                });
                HapticFeedback.selectionClick();
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isSelected ? CustomColor.primary : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? CustomColor.primary : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  filter['label']!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GetBuilder<DataController>(
      init: controller,
      builder: (dataCtrl) {
        final filteredEvents = _getFilteredEvents();
        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          appBar: _buildAppBar(dataCtrl),
          body: Column(
            children: [
              _buildFilterBar(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    dataCtrl.getEvents(showError: true);
                  },
                  color: Theme.of(context).primaryColor,
                  child: filteredEvents.isEmpty
                      ? (dataCtrl.isEventLoading.value
                          ? _buildSkeletonLoader()
                          : ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: MediaQuery.of(context).size.height * 0.6,
                                  child: _buildEmptyState(),
                                ),
                              ],
                            ))
                      : _buildEventsList(filteredEvents),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(DataController dataCtrl) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: CustomColor.primary,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
      title: const Text(
        'Notification',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF2D3142),
        ),
      ),
      actions: [
        if (dataCtrl.events.isNotEmpty)
          TextButton(
            onPressed: () => _showClearAllDialog(),
            child: const Text(
              'Clear All',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: CustomColor.primary,
              ),
            ),
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildEventsList(List<Event> filteredList) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: filteredList.length,
      itemBuilder: (context, index) {
        final event = filteredList[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _SwipeableEventCard(
            event: event,
            onDelete: () => _deleteEvent(event),
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

  void _deleteEvent(Event deletedEvent) {
    final index = controller.events.indexOf(deletedEvent);
    if (index == -1) return;

    // Remove from in-memory list
    controller.events.removeAt(index);

    // Also remove from local persistent storage (if it's a local alert event)
    controller.deleteLocalEvent(deletedEvent.id);

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Show undo snackbar
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Expanded(
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
            // Re-insert into memory and re-save to local storage
            controller.events.insert(index, deletedEvent);
            controller.localEvents.removeWhere((e) => e.id == deletedEvent.id);
            controller.localEvents.insert(0, deletedEvent);
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
              // Clear both in-memory list AND persistent local storage
              controller.events.clear();
              controller.clearLocalEvents();
              Navigator.pop(context);
              HapticFeedback.mediumImpact();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: CustomColor.primary,
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
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              size: 50,
              color: Theme.of(context).primaryColor,
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

  Widget _buildSkeletonLoader() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Opacity(
          opacity: Tween<double>(begin: 0.35, end: 0.8).evaluate(_pulseController),
          child: child,
        );
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: 8,
        itemBuilder: (context, index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 100,
                            height: 14,
                            color: Colors.grey.shade300,
                          ),
                          Container(
                            width: 50,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        height: 12,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 150,
                        height: 12,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 80,
                            height: 10,
                            color: Colors.grey.shade300,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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

  Map<String, String> _formatDateTime(String? rawTime) {
    if (rawTime == null || rawTime.isEmpty) {
      return {'date': '', 'time': ''};
    }
    
    final parts = rawTime.trim().split(' ');
    if (parts.length >= 2) {
      final datePart = parts[0];
      final timePart = parts.sublist(1).join(' ');
      if (datePart.contains('-') && datePart.split('-').first.length == 2) {
        return {'date': datePart, 'time': timePart};
      }
    }
    
    try {
      DateTime? dt = DateTime.tryParse(rawTime);
      if (dt == null) {
        final reg = RegExp(r'^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})');
        final match = reg.firstMatch(rawTime.trim());
        if (match != null) {
          final year = int.parse(match.group(1)!);
          final month = int.parse(match.group(2)!);
          final day = int.parse(match.group(3)!);
          final hour = int.parse(match.group(4)!);
          final minute = int.parse(match.group(5)!);
          final second = int.parse(match.group(6)!);
          dt = DateTime(year, month, day, hour, minute, second);
        }
      }
      
      if (dt != null) {
        final localDt = dt.toLocal();
        final dateStr = "${localDt.day.toString().padLeft(2, '0')}-${localDt.month.toString().padLeft(2, '0')}-${localDt.year}";
        
        int hour = localDt.hour;
        final period = hour >= 12 ? 'PM' : 'AM';
        if (hour > 12) hour -= 12;
        if (hour == 0) hour = 12;
        final timeStr = "${hour.toString().padLeft(2, '0')}:${localDt.minute.toString().padLeft(2, '0')}:${localDt.second.toString().padLeft(2, '0')} $period";
        
        return {'date': dateStr, 'time': timeStr};
      }
    } catch (_) {}
    
    if (parts.length >= 2) {
      return {'date': parts[0], 'time': parts.sublist(1).join(' ')};
    }
    return {'date': rawTime, 'time': ''};
  }

  Map<String, dynamic> _getSemanticEventStyle(String message) {
    // Return uniform layout style for all alerts, exactly as shown in the screenshot mockup
    return {
      'bg': const Color(0xFFE0F2FE), // Blue 100 / Sky 100
      'iconColor': const Color(0xFF0284C7), // Sky 700 / Blue
      'icon': Icons.notifications_active_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(event.id),
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
        color: CustomColor.primary.withValues(alpha: 0.4),
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
    final dtParts = _formatDateTime(event.time);
    final dateStr = dtParts['date'] ?? '';
    final timeStr = dtParts['time'] ?? '';
    final semanticStyle = _getSemanticEventStyle(event.message ?? '');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // Semantic light background with matching icon color
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: semanticStyle['bg'] as Color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      semanticStyle['icon'] as IconData,
                      color: semanticStyle['iconColor'] as Color,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Content (Title = Alert msg, Subtitle = Device name)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        event.message?.tr ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        event.device_name ?? 'Unknown Vehicle',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Date and Time stacked on the right
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReportEventArgument {
  final Event event;
  ReportEventArgument(this.event);
}