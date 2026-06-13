import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/util/util.dart';
import 'package:gpspro/arguments/fence_args.dart';

class GeofenceAddPage extends StatefulWidget {
  const GeofenceAddPage({super.key});

  @override
  State<GeofenceAddPage> createState() => _GeofenceAddPageState();
}

class _GeofenceAddPageState extends State<GeofenceAddPage> {
  // Controllers
  final Completer<GoogleMapController> _controller = Completer();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  GoogleMapController? mapController;
  DataController dataController = Get.put(DataController());

  // Map settings
  MapType _currentMapType = MapType.normal;
  String? _mapStyle;
  LatLng? _currentLocation;

  // Markers and Shapes
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};
  final Set<Polygon> _polygons = {};
  final List<LatLng> _polygonPoints = [];

  // Geofence settings
  String _geofenceType = 'circle';
  double _radius = 200;
  LatLng? _geofenceCenter;
  Color _fenceColor = Colors.blue;

  // Device selection
  final List<DeviceItem> _selectedDevices = [];
  List<DeviceItem> _devicesList = [];
  final List<DeviceItem> _searchResult = [];

  // UI State
  bool _showControlPanel = false;
  bool _isSubmitting = false;
  bool _isLoading = true;
  bool _argsChecked = false;

  // Constants
  static const double _minRadius = 50;
  static const double _maxRadius = 5000;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _getCurrentLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsChecked) {
      _argsChecked = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is FenceArguments && args.device != null) {
        final device = args.device!;
        if (!_selectedDevices.any((d) => d.id == device.id)) {
          _selectedDevices.add(device);
          if (device.lat != null && device.lng != null) {
            _geofenceCenter = LatLng(
              double.parse(device.lat.toString()),
              double.parse(device.lng.toString()),
            );
            _showControlPanel = true;
            _updateGeofenceShape();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              mapController?.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(target: _geofenceCenter!, zoom: 15),
                ),
              );
            });
          }
        }
      }
    }
  }

  void _loadMapStyle() async {
    try {
      _mapStyle = await rootBundle.loadString('assets/map_style.txt');
    } catch (e) {
      debugPrint('Map style not found');
    }
  }

  void _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    mapController?.dispose();
    super.dispose();
  }

  void _loadDeviceMarkers(DataController controller) async {
    _markers.clear();

    for (var group in controller.devices) {
      if (group.items != null && group.items!.isNotEmpty) {
        for (var device in group.items!) {
          if (device.deviceData?.active.toString() == "1" &&
              device.lat != null &&
              device.lng != null) {
            try {
              BitmapDescriptor markerIcon =
              await Util.getMarkerIcon(device.icon?.path ?? '');

              _markers.add(Marker(
                markerId: MarkerId(device.id.toString()),
                position: LatLng(
                  double.parse(device.lat.toString()),
                  double.parse(device.lng.toString()),
                ),
                icon: markerIcon,
                rotation: double.tryParse(device.course.toString()) ?? 0,
                onTap: () => _toggleDeviceSelection(device),
              ));
            } catch (e) {
              _markers.add(Marker(
                markerId: MarkerId(device.id.toString()),
                position: LatLng(
                  double.parse(device.lat.toString()),
                  double.parse(device.lng.toString()),
                ),
                onTap: () => _toggleDeviceSelection(device),
              ));
            }
          }
        }
      }
    }
    setState(() => _isLoading = false);
  }

  void _toggleDeviceSelection(DeviceItem device) {
    setState(() {
      final index = _selectedDevices.indexWhere((d) => d.id == device.id);
      if (index >= 0) {
        _selectedDevices.removeAt(index);
      } else {
        _selectedDevices.add(device);
        if (_selectedDevices.length == 1 && _geofenceCenter == null) {
          _geofenceCenter = LatLng(
            double.parse(device.lat.toString()),
            double.parse(device.lng.toString()),
          );
          _showControlPanel = true;
          _updateGeofenceShape();
          mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: _geofenceCenter!, zoom: 15),
            ),
          );
        }
      }
    });
  }

  void _onMapTap(LatLng position) {
    if (_geofenceType == 'circle') {
      setState(() {
        _geofenceCenter = position;
        _showControlPanel = true;
        _updateGeofenceShape();
      });
    } else {
      setState(() {
        _polygonPoints.add(position);
        _markers.add(Marker(
          markerId: MarkerId('polygon_point_${_polygonPoints.length}'),
          position: position,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ));

        if (_polygonPoints.length >= 3) {
          _showControlPanel = true;
          _updateGeofenceShape();
        }
      });
    }
  }

  void _updateGeofenceShape() {
    if (_geofenceType == 'circle' && _geofenceCenter != null) {
      _circles.clear();
      _circles.add(Circle(
        circleId: const CircleId('geofence_circle'),
        center: _geofenceCenter!,
        radius: _radius,
        fillColor: _fenceColor.withValues(alpha: 0.2),
        strokeColor: _fenceColor,
        strokeWidth: 2,
      ));
    } else if (_geofenceType == 'polygon' && _polygonPoints.length >= 3) {
      _polygons.clear();
      _polygons.add(Polygon(
        polygonId: const PolygonId('geofence_polygon'),
        points: _polygonPoints,
        fillColor: _fenceColor.withValues(alpha: 0.2),
        strokeColor: _fenceColor,
        strokeWidth: 2,
      ));
    }
    setState(() {});
  }

  void _clearGeofence() {
    setState(() {
      _geofenceCenter = null;
      _polygonPoints.clear();
      _circles.clear();
      _polygons.clear();
      _showControlPanel = false;
      _selectedDevices.clear();
      _markers.removeWhere((m) => m.markerId.value.startsWith('polygon_point_'));
    });
  }

  void _onSearchChanged(String text) {
    _searchResult.clear();
    if (text.isEmpty) {
      setState(() {});
      return;
    }
    for (var device in _devicesList) {
      if (device.name?.toLowerCase().contains(text.toLowerCase()) ?? false) {
        _searchResult.add(device);
      }
    }
    setState(() {});
  }

  // Show Device Selection Bottom Sheet
  void _showDeviceSelectionSheet() {
    _searchController.clear();
    _searchResult.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final list = _searchResult.isNotEmpty || _searchController.text.isNotEmpty
              ? _searchResult
              : _devicesList;

          return Container(
            height: MediaQuery.of(context).size.height * 0.6,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.directions_car, color: CustomColor.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Select Vehicles',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${_selectedDevices.length} selected',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_selectedDevices.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            setState(() => _selectedDevices.clear());
                            setModalState(() {});
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Clear',
                            style: TextStyle(color: Colors.red[400], fontSize: 13),
                          ),
                        ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close, size: 18, color: Colors.grey[600]),
                        ),
                      ),
                    ],
                  ),
                ),

                // Search bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (text) {
                      _onSearchChanged(text);
                      setModalState(() {});
                    },
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search vehicle...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[400], size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _onSearchChanged('');
                          setModalState(() {});
                        },
                        child: Icon(Icons.clear, size: 18, color: Colors.grey[400]),
                      )
                          : null,
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                const Divider(height: 1),

                // Select All Header (only if list is not empty)
                if (list.isNotEmpty) ...[
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: CustomColor.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Icon(Icons.select_all, color: CustomColor.primary, size: 20),
                    ),
                    title: const Text(
                      'Select All',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    trailing: Checkbox(
                      value: list.where((d) => d.deviceData?.active.toString() == "1").isNotEmpty &&
                          list.where((d) => d.deviceData?.active.toString() == "1").every((d) => _selectedDevices.any((sd) => sd.id == d.id)),
                      onChanged: (val) {
                        setState(() {
                          final activeList = list.where((d) => d.deviceData?.active.toString() == "1").toList();
                          if (val!) {
                            for (var device in activeList) {
                              if (!_selectedDevices.any((d) => d.id == device.id)) {
                                _selectedDevices.add(device);
                              }
                            }
                          } else {
                            for (var device in activeList) {
                              _selectedDevices.removeWhere((d) => d.id == device.id);
                            }
                          }
                        });
                        setModalState(() {});
                      },
                      activeColor: CustomColor.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onTap: () {
                      final activeList = list.where((d) => d.deviceData?.active.toString() == "1").toList();
                      final isAllSelected = activeList.isNotEmpty &&
                          activeList.every((d) => _selectedDevices.any((sd) => sd.id == d.id));
                      setState(() {
                        if (isAllSelected) {
                          for (var device in activeList) {
                            _selectedDevices.removeWhere((d) => d.id == device.id);
                          }
                        } else {
                          for (var device in activeList) {
                            if (!_selectedDevices.any((d) => d.id == device.id)) {
                              _selectedDevices.add(device);
                            }
                          }
                        }
                      });
                      setModalState(() {});
                    },
                  ),
                  const Divider(height: 1),
                ],

                // Device list
                Expanded(
                  child: list.isEmpty
                      ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 40, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text(
                          'No vehicles found',
                          style: TextStyle(color: Colors.grey[500], fontSize: 14),
                        ),
                      ],
                    ),
                  )
                      : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
                    itemBuilder: (context, index) {
                      final device = list[index];
                      final isActive = device.deviceData?.active.toString() == "1";
                      final isSelected = _selectedDevices.any((d) => d.id == device.id);

                      Color statusColor = device.iconColor == "green"
                          ? Colors.green
                          : device.iconColor == "yellow"
                          ? Colors.orange
                          : Colors.red;

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        onTap: isActive
                            ? () {
                          _toggleDeviceSelection(device);
                          setModalState(() {});
                        }
                            : null,
                        leading: Stack(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? CustomColor.primary.withValues(alpha: 0.15)
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Icon(
                                Icons.directions_car,
                                size: 20,
                                color: isActive ? statusColor : Colors.grey[400],
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: isActive ? statusColor : Colors.grey,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          device.name ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isActive ? Colors.grey[800] : Colors.grey[400],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: CustomColor.primary, size: 22)
                            : Icon(
                          Icons.circle_outlined,
                          size: 22,
                          color: isActive ? Colors.grey[300] : Colors.grey[200],
                        ),
                      );
                    },
                  ),
                ),

                // Done button
                Container(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CustomColor.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      child: Text(
                        _selectedDevices.isEmpty
                            ? 'Done'
                            : 'Done (${_selectedDevices.length} selected)',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _submitGeofence() async {
    if (_nameController.text.isEmpty) {
      _showToast('Please enter a fence name', Colors.orange);
      return;
    }

    if (_selectedDevices.isEmpty) {
      _showToast('Please select at least one vehicle', Colors.orange);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      Map<String, dynamic> requestBody = {};

      if (_geofenceType == 'circle' && _geofenceCenter != null) {
        requestBody = {
          'name': _nameController.text,
          'polygon_color': _colorToHex(_fenceColor),
          'type': 'circle',
          'center': json.encode({
            'lat': _geofenceCenter!.latitude.toString(),
            'lng': _geofenceCenter!.longitude.toString(),
          }),
          'radius': _radius.toString(),
          'coordinates': '',
        };
      } else if (_geofenceType == 'polygon' && _polygonPoints.length >= 3) {
        final coordinates =
        _polygonPoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
        requestBody = {
          'name': _nameController.text,
          'polygon_color': _colorToHex(_fenceColor),
          'type': 'polygon',
          'coordinates': json.encode(coordinates),
          'center': '',
          'radius': '',
        };
      } else {
        _showToast('Please set a valid geofence area', Colors.orange);
        setState(() => _isSubmitting = false);
        return;
      }

      for (int i = 0; i < _selectedDevices.length; i++) {
        requestBody['devices[$i]'] = _selectedDevices[i].id.toString();
      }

      final response = await APIService.addGeofence(requestBody);

      if (response != null && response.statusCode == 200) {
        _showToast('Geofence created successfully!', Colors.green);
        Navigator.pop(context, true);
      } else {
        _showToast('Failed to create geofence', Colors.red);
      }
    } catch (e) {
      _showToast('Error: ${e.toString()}', Colors.red);
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _showToast(String message, Color color) {
    Fluttertoast.showToast(
      msg: message,
      backgroundColor: color,
      textColor: Colors.white,
      gravity: ToastGravity.BOTTOM,
    );
  }

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).substring(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: GetX<DataController>(
        init: DataController(),
        builder: (controller) {
          _devicesList = controller.onlyDevices;

          if (controller.devices.isNotEmpty && _isLoading) {
            _loadDeviceMarkers(controller);
          }

          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }

          return _buildBody();
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: CustomColor.primary.withValues(alpha: 0.8),
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'addFence'.tr,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
      ),
      actions: [
        if (_showControlPanel)
          IconButton(
            icon: const Icon(Icons.refresh, size: 22),
            tooltip: 'Clear',
            onPressed: _clearGeofence,
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        GoogleMap(
          mapType: _currentMapType,
          initialCameraPosition: CameraPosition(
            target: _currentLocation ?? const LatLng(21.7679, 78.8718),
            zoom: _currentLocation != null ? 14 : 4,
          ),
          onMapCreated: (controller) {
            _controller.complete(controller);
            mapController = controller;
            if (_mapStyle != null) {
              controller.setMapStyle(_mapStyle);
            }
          },
          onTap: _onMapTap,
          markers: _markers,
          circles: _circles,
          polygons: _polygons,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),

        // Type selector & Map controls
        _buildTopControls(),

        // Right side controls
        _buildMapControls(),

        // Bottom control panel
        _buildControlPanel(),
      ],
    );
  }

  Widget _buildTopControls() {
    return Positioned(
      top: 12,
      left: 12,
      right: 60,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
          ],
        ),
        child: Row(
          children: [
            Expanded(child: _buildTypeButton('Circle', Icons.radio_button_unchecked, 'circle')),
            Container(width: 1, height: 20, color: Colors.grey[200]),
            Expanded(child: _buildTypeButton('Polygon', Icons.pentagon_outlined, 'polygon')),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeButton(String label, IconData icon, String type) {
    final isSelected = _geofenceType == type;
    return GestureDetector(
      onTap: () {
        if (_geofenceType != type) {
          setState(() {
            _geofenceType = type;
            _geofenceCenter = null;
            _polygonPoints.clear();
            _circles.clear();
            _polygons.clear();
            _showControlPanel = false;
            _markers.removeWhere((m) => m.markerId.value.startsWith('polygon_point_'));
          });
        }
      },
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: isSelected ? CustomColor.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey[600]),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapControls() {
    return Positioned(
      top: 12,
      right: 12,
      child: Column(
        children: [
          _buildControlButton(Icons.layers_outlined, () {
            setState(() {
              _currentMapType =
              _currentMapType == MapType.normal ? MapType.satellite : MapType.normal;
            });
          }),
          const SizedBox(height: 6),
          _buildControlButton(Icons.my_location, () {
            if (_currentLocation != null) {
              mapController?.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(target: _currentLocation!, zoom: 15),
                ),
              );
            }
          }),
          const SizedBox(height: 12),
          _buildControlButton(Icons.add, () {
            mapController?.animateCamera(CameraUpdate.zoomIn());
          }),
          const SizedBox(height: 4),
          _buildControlButton(Icons.remove, () {
            mapController?.animateCamera(CameraUpdate.zoomOut());
          }),
        ],
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(5),
      color: Colors.white,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.grey[700], size: 20),
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).padding.bottom + 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Fence name & Vehicle selection row
            Row(
              children: [
                // Fence name input
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _nameController,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Fence name',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      prefixIcon: Icon(Icons.label_outline, size: 20, color: Colors.grey[500]),
                      filled: true,
                      fillColor: Colors.grey[50],
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide(color: Colors.grey[200]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide(color: CustomColor.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Vehicle selection button
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _showDeviceSelectionSheet,
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _selectedDevices.isEmpty
                            ? Colors.grey[50]
                            : CustomColor.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: _selectedDevices.isEmpty
                              ? Colors.grey[200]!
                              : CustomColor.primary.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.directions_car,
                            size: 18,
                            color: _selectedDevices.isEmpty
                                ? Colors.grey[500]
                                : CustomColor.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _selectedDevices.isEmpty
                                  ? 'Vehicles'
                                  : '${_selectedDevices.length} selected',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _selectedDevices.isEmpty
                                      ? Colors.grey[500]
                                      : CustomColor.primary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.keyboard_arrow_down,
                            size: 18,
                            color: _selectedDevices.isEmpty
                                ? Colors.grey[400]
                                : CustomColor.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Radius slider (for circle) or polygon info
            if (_geofenceType == 'circle') ...[
              Row(
                children: [
                  Text(
                    'Radius',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[700]),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: CustomColor.primary,
                        inactiveTrackColor: Colors.grey[200],
                        thumbColor: CustomColor.primary,
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      ),
                      child: Slider(
                        value: _radius,
                        min: _minRadius,
                        max: _maxRadius,
                        onChanged: (value) {
                          setState(() {
                            _radius = value;
                            _updateGeofenceShape();
                          });
                        },
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: CustomColor.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '${_radius.toInt()}m',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: CustomColor.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 8),
                  Text(
                    '${_polygonPoints.length} points added',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  if (_polygonPoints.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_polygonPoints.isNotEmpty) {
                            _polygonPoints.removeLast();
                            _markers.removeWhere(
                                    (m) => m.markerId.value == 'polygon_point_${_polygonPoints.length + 1}');
                            _updateGeofenceShape();
                          }
                        });
                      },
                      child: Text(
                        'Undo',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CustomColor.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),

            // Color selection & Submit button row
            Row(
              children: [
                // Color options
                ...[Colors.blue, Colors.green, Colors.orange, Colors.red, Colors.purple].map(
                      (color) => GestureDetector(
                    onTap: () {
                      setState(() {
                        _fenceColor = color;
                        _updateGeofenceShape();
                      });
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _fenceColor == color ? Colors.grey[800]! : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: _fenceColor == color
                          ? const Icon(Icons.check, color: Colors.white, size: 14)
                          : null,
                    ),
                  ),
                ),

                const Spacer(),

                // Submit button
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitGeofence,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CustomColor.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.check, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Create',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}