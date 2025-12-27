import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/model/geofence_model.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/theme/custom_color.dart';

class GeofenceListPage extends StatefulWidget {
  const GeofenceListPage({Key? key}) : super(key: key);

  @override
  State<GeofenceListPage> createState() => _GeofenceListPageState();
}

class _GeofenceListPageState extends State<GeofenceListPage> {
  List<Geofence> fenceList = [];
  Map<int, List<Map<String, dynamic>>> fenceDevices = {}; // Store device info
  bool isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';
  String filterType = 'all';
  DataController dataController = Get.find<DataController>();

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

  // Get all geofences with device associations
  Future<void> getFences() async {
    setState(() => isLoading = true);

    try {
      final value = await APIService.getGeoFences();
      if (value != null && value.isNotEmpty) {
        fenceList = value;
        // Fetch device associations for each fence
        await _fetchDeviceAssociations();
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

  // Fetch device associations for geofences
  Future<void> _fetchDeviceAssociations() async {
    try {
      for (var fence in fenceList) {
        if (fence.id != null) {
          final devices = await APIService.getGeofenceDevices(int.tryParse(fence.id.toString()));
          if (devices != null && devices.isNotEmpty) {
            List<Map<String, dynamic>> deviceList = [];
            for (var deviceData in devices) {
              // Match with actual device names from DataController
              final deviceId = deviceData['device_id'] ?? deviceData['id'];
              final deviceName = _getDeviceNameById(deviceId);
              deviceList.add({
                'id': deviceId,
                'name': deviceName ?? deviceData['name'] ?? 'Unknown Device',
              });
            }
            fenceDevices[int.parse(fence.id.toString())] = deviceList;
          } else {
            fenceDevices[int.parse(fence.id.toString())] = [];
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching device associations: $e');
    }
  }

  // Get device name by ID from DataController
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

  // Toggle fence active status
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

  // Delete fence
  Future<void> _deleteFence(Geofence fence) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.delete_outline, color: Colors.red[700], size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Delete Geofence')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to delete this geofence?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    fence.type == 'polygon'
                        ? Icons.pentagon_outlined
                        : Icons.radio_button_unchecked,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      fence.name ?? 'Unnamed Fence',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red[700],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          margin: const EdgeInsets.all(50),
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Deleting geofence...'),
              ],
            ),
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
        _showToast('Failed to delete: ${response.body}', Colors.red);
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
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          // if (!isLoading && fenceList.isNotEmpty) _buildStatsCard(),
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
            arguments: FenceArguments(fenceModel: Geofence()),
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
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [CustomColor.primary, CustomColor.primary.withValues(alpha: 0.4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      foregroundColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Geofences',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Colors.white,
            ),
          ),
          if (!isLoading)
            Text(
              '${fenceList.length} total',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.normal,
              ),
            ),
        ],
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, size: 20),
        onPressed: () => Navigator.pop(context),
      ),

      actions: [

        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: getFences,
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(left: 12,right: 12, top: 8,bottom: 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() => searchQuery = value);
        },
        decoration: InputDecoration(
          hintText: 'Search by geofence or vehicle name...',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
            icon: Icon(Icons.clear, color: Colors.grey[400]),
            onPressed: () {
              _searchController.clear();
              setState(() => searchQuery = '');
            },
          )
              : null,
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('All', 'all', Icons.grid_view),
            _buildFilterChip('Active', 'active', Icons.check_circle),
            _buildFilterChip('Inactive', 'inactive', Icons.cancel),
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
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
            const SizedBox(width: 6),
            Text(label),
            if (count > 0 && !isSelected) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: CustomColor.primary.withValues(alpha: 0.2),
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
        onSelected: (selected) {
          setState(() {
            filterType = value;
          });
        },
        selectedColor: CustomColor.primary,
        backgroundColor: Colors.grey[100],
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          fontSize: 13,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? CustomColor.primary : Colors.grey[300]!,
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

  Widget _buildStatsCard() {
    final activeCount = fenceList.where((f) => f.active.toString() == "1").length;
    final circleCount = fenceList.where((f) => f.type == 'circle').length;
    final polygonCount = fenceList.where((f) => f.type == 'polygon').length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [CustomColor.primary, CustomColor.primary.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: CustomColor.primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(Icons.check_circle, 'Active', activeCount.toString()),
          _buildStatDivider(),
          _buildStatItem(Icons.radio_button_unchecked, 'Circle', circleCount.toString()),
          _buildStatDivider(),
          _buildStatItem(Icons.pentagon_outlined, 'Polygon', polygonCount.toString()),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(
      height: 50,
      width: 1,
      color: Colors.white.withValues(alpha: 0.3),
    );
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
                  color: Colors.grey[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  searchQuery.isNotEmpty ? Icons.search_off : Icons.location_off_outlined,
                  size: 80,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                searchQuery.isNotEmpty ? 'No results found' : 'No geofences yet',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.grey[800],
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
                  color: Colors.grey[600],
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
                      arguments: FenceArguments(fenceModel: Geofence()),
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
        itemBuilder: (context, index) {
          return _buildFenceCard(filteredList[index]);
        },
      ),
    );
  }

  Widget _buildFenceCard(Geofence fence) {
    final bool isActive = fence.active.toString() == "1";
    final String fenceType = fence.type ?? 'circle';
    final int fenceId = int.tryParse(fence.id.toString()) ?? 0;
    final List<Map<String, dynamic>>? devices = fenceDevices[fenceId];
    final int deviceCount = devices?.length ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? CustomColor.primary.withValues(alpha: 0.3) : Colors.grey[200]!,
          width: isActive ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isActive
                ? CustomColor.primary.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isActive
                              ? [CustomColor.primary, CustomColor.primary.withValues(alpha: 0.7)]
                              : [Colors.grey[300]!, Colors.grey[400]!],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: isActive ? [
                          BoxShadow(
                            color: CustomColor.primary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ] : null,
                      ),
                      child: Icon(
                        fenceType == 'polygon'
                            ? Icons.pentagon_outlined
                            : Icons.radio_button_unchecked,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  fence.name ?? 'Unnamed Fence',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                    color: Colors.grey[900],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Status badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: isActive ? Colors.green[50] : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isActive ? Colors.green[200]! : Colors.grey[300]!,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: isActive ? Colors.green : Colors.grey,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isActive ? 'Active' : 'Inactive',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isActive ? Colors.green[700] : Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              // Type chip
                              _buildInfoChip(
                                icon: fenceType == 'polygon' ? Icons.pentagon_outlined : Icons.radio_button_unchecked,
                                label: fenceType.toUpperCase(),
                                color: CustomColor.primary,
                              ),
                              // Radius (if circle)
                              if (fence.radius != null && fence.radius.toString().isNotEmpty && fenceType == 'circle')
                                _buildInfoChip(
                                  icon: Icons.straighten,
                                  label: '${fence.radius}m',
                                  color: Colors.orange[700]!,
                                ),
                              // Device count
                              _buildInfoChip(
                                icon: Icons.directions_car,
                                label: '$deviceCount ${deviceCount == 1 ? "vehicle" : "vehicles"}',
                                color: deviceCount > 0 ? Colors.blue[700]! : Colors.grey[600]!,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Show vehicle names if available
                if (devices != null && devices.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue[100]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.directions_car, size: 16, color: Colors.blue[700]),
                            const SizedBox(width: 6),
                            Text(
                              'Assigned Vehicles:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.blue[900],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            // First 3 devices
                            ...devices.take(3).map((device) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.blue[200]!),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.circle, size: 8, color: Colors.blue[600]),
                                    const SizedBox(width: 6),
                                    Text(
                                      device['name'] ?? 'Unknown',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue[800],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            // Show "+X more" if there are more than 3 devices
                            if (devices.length > 3)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '+${devices.length - 3} more',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                          ],
                        )
                      ],
                    ),
                  ),
                ],

                // No vehicles assigned message
                if (deviceCount == 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No vehicles assigned to this geofence',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange[900],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Divider
          Divider(height: 1, color: Colors.grey[200], thickness: 1),

          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                // Toggle
                Expanded(
                  child: Row(
                    children: [
                      Transform.scale(
                        scale: 0.9,
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
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),

                // Edit Button
                _buildActionButton(
                  icon: Icons.edit_outlined,
                  color: Colors.blue[600]!,
                  onPressed: () async {
                    final result = await Navigator.pushNamed(
                      context,
                      "/geofenceAdd",
                      arguments: FenceArguments(fenceModel: fence),
                    );
                    if (result == true) {
                      getFences();
                    }
                  },
                  tooltip: 'Edit',
                ),

                // Delete Button
                _buildActionButton(
                  icon: Icons.delete_outline,
                  color: Colors.red[600]!,
                  onPressed: () => _deleteFence(fence),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return IconButton(
      icon: Icon(icon, color: color, size: 22),
      onPressed: onPressed,
      tooltip: tooltip,
      splashRadius: 20,
    );
  }
}

class FenceArguments {
  final Geofence? fenceModel;

  FenceArguments({this.fenceModel});
}