import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/services/model/geofence_model.dart';
import 'package:smart_lock/services/api_service.dart';

class GeofenceListPage extends StatefulWidget {
  const GeofenceListPage({super.key});

  @override
  State<GeofenceListPage> createState() => _GeofenceListPageState();
}

class _GeofenceListPageState extends State<GeofenceListPage> {
  // ✅ RED COLOR SCHEME
  static const Color _primaryRed = Color(0xFFC0392B);
  static const Color _greyText = Color(0xFF6B7280);
  static const Color _darkText = Color(0xFF1F2937);

  List<Geofence> fenceList = [];
  Map<int, List<Map<String, dynamic>>> fenceDevices = {};
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

  Future<void> getFences() async {
    setState(() => isLoading = true);

    try {
      final value = await APIService.getGeoFences();
      if (value != null && value.isNotEmpty) {
        fenceList = value;
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

  Future<void> _fetchDeviceAssociations() async {
    try {
      for (var fence in fenceList) {
        if (fence.id != null) {
          final devices = await APIService.getGeofenceDevices(int.tryParse(fence.id.toString()));
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

  Future<void> _deleteFence(Geofence fence) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Geofence?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${fence.name ?? 'this geofence'}"?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: _greyText)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await APIService.destroyGeofence(fence.id);

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
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator(color: _primaryRed))
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
        backgroundColor: _primaryRed,
        icon: const Icon(Icons.add_location_alt, color: Colors.white),
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
      backgroundColor: _primaryRed,
      foregroundColor: Colors.white,
      centerTitle: true,
      title: const Text(
        'Geofences',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search geofences...',
          hintStyle: TextStyle(color: _greyText.withValues(alpha: 0.6), fontSize: 14),
          prefixIcon: Icon(Icons.search, color: _primaryRed, size: 22),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear, size: 20),
            onPressed: () {
              _searchController.clear();
              setState(() => searchQuery = '');
            },
          )
              : null,
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primaryRed, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          _buildFilterChip('All', 'all'),
          const SizedBox(width: 8),
          _buildFilterChip('Active', 'active'),
          const SizedBox(width: 8),
          _buildFilterChip('Inactive', 'inactive'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = filterType == value;
    final count = _getFilterCount(value);

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => filterType = value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _primaryRed : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? _primaryRed : Colors.grey.shade300,
            ),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : _darkText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : _greyText,
                ),
              ),
            ],
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
      default:
        return 0;
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: _primaryRed.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              searchQuery.isNotEmpty ? Icons.search_off : Icons.location_off_outlined,
              size: 60,
              color: _primaryRed.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            searchQuery.isNotEmpty ? 'No Results Found' : 'No Geofences Yet',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              searchQuery.isNotEmpty
                  ? 'Try adjusting your search'
                  : 'Create your first geofence to monitor locations',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _greyText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: getFences,
      color: _primaryRed,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredList.length,
        itemBuilder: (context, index) => _buildFenceCard(filteredList[index]),
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isActive ? _primaryRed.withValues(alpha: 0.1) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    fenceType == 'polygon' ? Icons.pentagon_outlined : Icons.radio_button_unchecked,
                    color: isActive ? _primaryRed : _greyText,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),

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
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isActive ? Colors.green.shade700 : _greyText,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.directions_car, size: 14, color: _greyText),
                          const SizedBox(width: 4),
                          Text(
                            '$deviceCount ${deviceCount == 1 ? "vehicle" : "vehicles"}',
                            style: TextStyle(fontSize: 12, color: _greyText),
                          ),
                          if (fence.radius != null && fenceType == 'circle') ...[
                            const SizedBox(width: 12),
                            Icon(Icons.straighten, size: 14, color: _greyText),
                            const SizedBox(width: 4),
                            Text(
                              '${fence.radius}m',
                              style: TextStyle(fontSize: 12, color: _greyText),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Transform.scale(
                        scale: 0.85,
                        child: Switch(
                          value: isActive,
                          onChanged: (value) => _toggleFenceStatus(fence, value),
                          activeThumbColor: _primaryRed,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      Text(
                        isActive ? 'Active' : 'Inactive',
                        style: TextStyle(fontSize: 12, color: _greyText, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: _primaryRed, size: 20),
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
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade600, size: 20),
                  onPressed: () => _deleteFence(fence),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FenceArguments {
  final Geofence? fenceModel;
  FenceArguments({this.fenceModel});
}