import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/model/geofence_model.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/arguments/fence_args.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;

class GeofenceListPage extends StatefulWidget {
  const GeofenceListPage({super.key});

  @override
  State<GeofenceListPage> createState() => _GeofenceListPageState();
}

class _GeofenceListPageState extends State<GeofenceListPage> {
  List<Geofence> fenceList = [];
  Map<int, List<Map<String, dynamic>>> fenceDevices = {};
  bool isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';
  String filterType = 'all';
  DataController dataController = Get.find<DataController>();
  DeviceItem? activeDevice;
  bool _argsChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsChecked) {
      _argsChecked = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is ReportArguments) {
        activeDevice = args.deviceItem;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    getFences();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> getFences() async {
    setState(() => isLoading = true);

    try {
      final value = await APIService.getGeoFences();
      if (value != null && value.isNotEmpty) {
        fenceList = value;
        _fetchDeviceAssociations();
      } else {
        fenceList = [];
      }
    } catch (e) {
      _showToast('Failed to load geofences: ${e.toString()}', Colors.red);
      fenceList = [];
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _fetchDeviceAssociations() async {
    try {
      final futures = fenceList.map((fence) async {
        final idStr = fence.id?.toString();
        if (idStr == null) return;
        final fenceId = int.tryParse(idStr);
        if (fenceId == null) return;

        try {
          final devices = await APIService.getGeofenceDevices(fenceId);
          if (devices != null && devices.isNotEmpty) {
            List<Map<String, dynamic>> deviceList = [];
            for (var deviceData in devices) {
              final deviceId = deviceData['device_id'] ?? deviceData['id'];
              final deviceName = _getDeviceNameById(deviceId);
              deviceList.add({
                'id': deviceId,
                'name': deviceName ?? deviceData['name'] ?? 'Unknown Device',
              });
            }
            fenceDevices[fenceId] = deviceList;
          } else {
            fenceDevices[fenceId] = [];
          }
        } catch (e) {
          debugPrint('Error fetching associations for fence $fenceId: $e');
          fenceDevices[fenceId] = [];
        }
      }).toList();

      await Future.wait(futures);

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error fetching device associations: $e');
    }
  }

  String? _getDeviceNameById(dynamic deviceId) {
    try {
      for (var group in dataController.devices) {
        if (group.items != null) {
          for (var device in group.items!) {
            if (device.id.toString() == deviceId.toString()) {
              return device.name;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting device name: $e');
    }
    return null;
  }

  Future<void> _toggleFenceStatus(Geofence fence, bool activate) async {
    try {
      Map<String, String> requestBody = {
        'id': fence.id.toString(),
        'active': activate ? "true" : "false",
      };

      final response = await APIService.activateFence(requestBody);

      if (response.statusCode == 200) {
        setState(() {
          fence.active = activate ? 1 : 0;
        });
        _showToast(
          activate ? 'Geofence activated' : 'Geofence deactivated',
          Colors.green,
        );
      } else {
        _showToast('Failed to update geofence', Colors.red);
      }
    } catch (e) {
      _showToast('Error: ${e.toString()}', Colors.red);
    }
  }

  // ✅ IMPROVED DELETE CONFIRMATION
  Future<void> _deleteFence(Geofence fence) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.delete_outline, color: Colors.red.shade600, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Delete Geofence',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to delete this geofence?',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    fence.type == 'polygon'
                        ? Icons.pentagon_outlined
                        : Icons.radio_button_unchecked,
                    color: CustomColor.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      fence.name ?? 'Unnamed Fence',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade600, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This action cannot be undone',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Deleting geofence...'),
            ],
          ),
        ),
      ),
    );

    try {
      final response = await APIService.destroyGeofence(fence.id);

      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200 || response.statusCode == 204) {
        setState(() {
          fenceList.removeWhere((f) => f.id == fence.id);
          fenceDevices.remove(int.tryParse(fence.id.toString()));
        });
        _showToast('Geofence deleted successfully', Colors.green);
      } else {
        _showToast('Failed to delete geofence', Colors.red);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showToast('Error: ${e.toString()}', Colors.red);
    }
  }

  void _showToast(String message, Color color) {
    Fluttertoast.showToast(
      msg: message,
      backgroundColor: color,
      textColor: Colors.white,
      gravity: ToastGravity.BOTTOM,
      toastLength: Toast.LENGTH_SHORT,
    );
  }

  List<Geofence> get filteredList {
    List<Geofence> result = fenceList;

    if (filterType == 'active') {
      result = result.where((f) => f.active.toString() == "1").toList();
    } else if (filterType == 'inactive') {
      result = result.where((f) => f.active.toString() != "1").toList();
    } else if (filterType == 'circle') {
      result = result.where((f) => f.type == 'circle').toList();
    } else if (filterType == 'polygon') {
      result = result.where((f) => f.type == 'polygon').toList();
    }

    if (searchQuery.isNotEmpty) {
      result = result.where((fence) {
        final nameMatch = fence.name?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false;
        final deviceMatch = fenceDevices[int.tryParse(fence.id.toString())]?.any(
                (device) => device['name'].toString().toLowerCase().contains(searchQuery.toLowerCase())
        ) ?? false;
        return nameMatch || deviceMatch;
      }).toList();
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredList.isEmpty
                ? _buildEmptyState()
                : _buildList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.pushNamed(
            context,
            "/geofenceAdd",
            arguments: FenceArguments(fenceModel: Geofence(), device: activeDevice),
          );
          if (result == true) {
            getFences();
          }
        },
        backgroundColor: CustomColor.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Geofence',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Geofences',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          if (!isLoading)
            Text(
              '${fenceList.length} total',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.normal,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search geofences or vehicles...',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 22),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
            icon: Icon(Icons.clear, color: Colors.grey.shade400, size: 20),
            onPressed: () {
              _searchController.clear();
              setState(() => searchQuery = '');
            },
          )
              : null,
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('All', 'all', Icons.grid_view),
            _buildFilterChip('Active', 'active', Icons.check_circle_outline),
            _buildFilterChip('Inactive', 'inactive', Icons.cancel_outlined),
            _buildFilterChip('Circle', 'circle', Icons.radio_button_unchecked),
            _buildFilterChip('Polygon', 'polygon', Icons.pentagon_outlined),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, IconData icon) {
    final isSelected = filterType == value;
    final count = _getFilterCount(value);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
            const SizedBox(width: 6),
            Text(label),
            if (count > 0 && !isSelected) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: CustomColor.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: CustomColor.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
        onSelected: (selected) => setState(() => filterType = value),
        selectedColor: CustomColor.primary,
        backgroundColor: Colors.grey.shade100,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.grey.shade700,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          fontSize: 13,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? CustomColor.primary : Colors.grey.shade300,
          ),
        ),
      ),
    );
  }

  int _getFilterCount(String filter) {
    switch (filter) {
      case 'all':
        return fenceList.length;
      case 'active':
        return fenceList.where((f) => f.active.toString() == "1").length;
      case 'inactive':
        return fenceList.where((f) => f.active.toString() != "1").length;
      case 'circle':
        return fenceList.where((f) => f.type == 'circle').length;
      case 'polygon':
        return fenceList.where((f) => f.type == 'polygon').length;
      default:
        return 0;
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: CustomColor.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  searchQuery.isNotEmpty ? Icons.search_off : Icons.location_off_outlined,
                  size: 80,
                  color: CustomColor.primary.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                searchQuery.isNotEmpty ? 'No Results Found' : 'No Geofences Yet',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                searchQuery.isNotEmpty
                    ? 'Try adjusting your search or filters'
                    : 'Create your first geofence to monitor locations',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              if (searchQuery.isEmpty) ...[
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.pushNamed(
                      context,
                      "/geofenceAdd",
                      arguments: FenceArguments(fenceModel: Geofence(), device: activeDevice),
                    );
                    if (result == true) {
                      getFences();
                    }
                  },
                  icon: const Icon(Icons.add, size: 22),
                  label: const Text('Create Geofence', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CustomColor.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: getFences,
      color: CustomColor.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredList.length,
        itemBuilder: (context, index) => _buildCleanFenceCard(filteredList[index]),
      ),
    );
  }

  Widget _buildCleanFenceCard(Geofence fence) {
    final bool isActive = fence.active.toString() == "1";
    final String fenceType = fence.type ?? 'circle';
    final int fenceId = int.tryParse(fence.id.toString()) ?? 0;
    final List<Map<String, dynamic>>? devices = fenceDevices[fenceId];
    final int deviceCount = devices?.length ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Stack(
        children: [
          // 3D Bottom Base Layer (depth thickness)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: isActive 
                    ? CustomColor.primary.withValues(alpha: 0.8) 
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          // Top Face Layer (shifts down slightly when active/pressed)
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: EdgeInsets.only(bottom: isActive ? 1.5 : 4.5),
            child: CustomPaint(
              foregroundPainter: GappedBorderPainter(
                color: isActive ? CustomColor.primary : Colors.grey.shade400,
                strokeWidth: isActive ? 1.8 : 1.2,
                borderRadius: 14,
                gapSize: 24,
              ),
              child: ReflectiveAnimationWrapper(
                borderRadius: 14,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Main Content
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Icon
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: isActive ? CustomColor.primary.withValues(alpha: 0.1) : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                fenceType == 'polygon' ? Icons.pentagon_outlined : Icons.radio_button_unchecked,
                                color: isActive ? CustomColor.primary : Colors.grey.shade500,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Name and Status
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          fence.name ?? 'Unnamed Fence',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Status Badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: isActive ? Colors.green : Colors.grey,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              isActive ? 'Active' : 'Inactive',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: isActive ? Colors.green.shade700 : Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  // Info Chips
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _buildInfoChip(
                                        icon: fenceType == 'polygon' ? Icons.pentagon_outlined : Icons.radio_button_unchecked,
                                        label: fenceType.toUpperCase(),
                                        color: CustomColor.primary,
                                      ),
                                      if (fence.radius != null && fence.radius.toString().isNotEmpty && fenceType == 'circle')
                                        _buildInfoChip(
                                          icon: Icons.straighten,
                                          label: '${fence.radius}m',
                                          color: Colors.orange.shade700,
                                        ),
                                      _buildInfoChip(
                                        icon: Icons.directions_car,
                                        label: '$deviceCount ${deviceCount == 1 ? "vehicle" : "vehicles"}',
                                        color: deviceCount > 0 ? Colors.blue.shade700 : Colors.grey.shade600,
                                      ),
                                    ],
                                  ),

                                  // Vehicle Names
                                  if (devices != null && devices.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.directions_car, size: 14, color: Colors.blue.shade700),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Vehicles:',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.blue.shade900,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 4,
                                            runSpacing: 4,
                                            children: [
                                              ...devices.take(3).map((device) => Text(
                                                '• ${device['name']}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.blue.shade800,
                                                ),
                                              )),
                                              if (devices.length > 3)
                                                Text(
                                                  ' +${devices.length - 3} more',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.grey.shade700,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Divider
                      Divider(height: 1, color: Colors.grey.shade200),

                      // Actions
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            // Toggle Switch
                            Expanded(
                              child: Row(
                                children: [
                                  Transform.scale(
                                    scale: 0.85,
                                    child: Switch(
                                      value: isActive,
                                      onChanged: (value) => _toggleFenceStatus(fence, value),
                                      activeThumbColor: CustomColor.primary,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  Text(
                                    isActive ? 'Active' : 'Inactive',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Edit Button
                            IconButton(
                              icon: Icon(Icons.edit_outlined, color: Colors.blue.shade600, size: 20),
                              onPressed: () async {
                                final result = await Navigator.pushNamed(
                                  context,
                                  "/geofenceAdd",
                                  arguments: FenceArguments(fenceModel: fence, device: activeDevice),
                                );
                                if (result == true) {
                                  getFences();
                                }
                              },
                              tooltip: 'Edit',
                            ),

                            // Delete Button
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.red.shade600, size: 20),
                              onPressed: () => _deleteFence(fence),
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class GappedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double borderRadius;
  final double gapSize;

  GappedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.borderRadius,
    required this.gapSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final halfStroke = strokeWidth / 2;
    final w = size.width - halfStroke;
    final h = size.height - halfStroke;
    final startOffset = halfStroke;
    final r = borderRadius;
    final g = gapSize;

    // Segment 1: Top and Right (from x = g on top side, around top-right, down to y = h - g on right side)
    final path1 = Path();
    path1.moveTo(g, startOffset);
    path1.lineTo(w - r, startOffset);
    path1.arcToPoint(
      Offset(w, startOffset + r),
      radius: Radius.circular(r),
      clockwise: true,
    );
    path1.lineTo(w, h - g);

    // Segment 2: Bottom and Left (from x = w - g on bottom side, around bottom-left, up to y = g on left side)
    final path2 = Path();
    path2.moveTo(w - g, h);
    path2.lineTo(startOffset + r, h);
    path2.arcToPoint(
      Offset(startOffset, h - r),
      radius: Radius.circular(r),
      clockwise: true,
    );
    path2.lineTo(startOffset, g);

    canvas.drawPath(path1, paint);
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant GappedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.gapSize != gapSize;
  }
}

class ReflectiveAnimationWrapper extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final bool isAnimated;

  const ReflectiveAnimationWrapper({
    super.key,
    required this.child,
    this.borderRadius = 5,
    this.isAnimated = true,
  });

  @override
  State<ReflectiveAnimationWrapper> createState() => _ReflectiveAnimationWrapperState();
}

class _ReflectiveAnimationWrapperState extends State<ReflectiveAnimationWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    if (widget.isAnimated) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAnimated) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  child: CustomPaint(
                    painter: _ReflectionSweepPainter(
                      progress: _controller.value,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ReflectionSweepPainter extends CustomPainter {
  final double progress;

  _ReflectionSweepPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    final widthOfSweep = 80.0;
    final startX = -widthOfSweep * 2;
    final endX = size.width + widthOfSweep * 3;
    final currentX = startX + (endX - startX) * progress;

    paint.shader = LinearGradient(
      begin: const Alignment(-2.0, -1.0),
      end: const Alignment(2.0, 1.0),
      colors: [
        Colors.white.withValues(alpha: 0.0),
        Colors.white.withValues(alpha: 0.02),
        Colors.white.withValues(alpha: 0.22), // Shine peak
        Colors.white.withValues(alpha: 0.02),
        Colors.white.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
    ).createShader(
      Rect.fromLTWH(currentX - widthOfSweep / 2, 0, widthOfSweep, size.height),
    );

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _ReflectionSweepPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
