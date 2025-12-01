import 'dart:async';
import 'dart:developer';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import 'package:gpspro/config.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/screens/report/get_today_report.dart';
import 'package:gpspro/services/model/device_item.dart';
import 'package:gpspro/widgets/common.dart';
import 'package:gpspro/widgets/fuel_price_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DataController dataController = Get.find<DataController>();
  String? selectedVehicle;
  TodayReportData? todayData;
  DeviceItem? selectedDevice;
  bool isLoadingReport = false;
  final double iconWidth = 25;
  final double fontWidth = 0.9;
  bool isLoaded = false;

  @override
  void initState() {
    super.initState();
    dataController.onlyDevices.listen((devices) {
      if (mounted && devices.isNotEmpty) {
        if (isLoaded) {
          return;
        }
        setState(() {
          selectedDevice = devices.first;
          selectedVehicle = _formatVehicleName(devices.first);
          isLoaded = true;
          getTodayDetails(devices.first.id!);
        });
      }
    });
  }

  Future<void> getTodayDetails(int id) async {
    if (!mounted) return;
    setState(() => isLoadingReport = true);

    try {
      final value = await ReportService.getTodayReportData(deviceId: id);
      if (mounted) {
        setState(() {
          todayData = value;
          isLoadingReport = false;
        });
      }
      log("Today's data: ${value.toJson()}");
    } catch (error) {
      log("Error fetching today's data: $error");
      if (mounted) {
        setState(() => isLoadingReport = false);
      }
    }
  }

  String _formatVehicleName(DeviceItem device) {
    return device.name ?? 'Unnamed Vehicle';
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 8, // Increased elevation for more spreaded light
        shadowColor: Colors.black.withOpacity(0.2), // Added shadow color
        toolbarHeight: 80.0, // Increased appbar height
        titleSpacing: 20.0, // Added space from top for the title
        title: Image.asset(
          'images/logo.png',
          height: 28.0,
          fit: BoxFit.contain,
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildSubscriptionStatusCard(),
            ),
            SizedBox(
              height: 16,
            ),
            CarouselSlider(
              options: CarouselOptions(
                height: 200.0,
                autoPlay: true,
                enlargeCenterPage: true,
                viewportFraction: 0.9,
                aspectRatio: 16 / 9,
                autoPlayInterval: const Duration(seconds: 3),
              ),
              items: BANNER_IMAGE
                  .map((url) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(url,
                            fit: BoxFit.cover, width: double.infinity),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            VehicleMileageChart(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildVehicleSummaryCard(),
            ),
            const SizedBox(
              height: 80,
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionStatusCard() {
    return CustomCard(
      title: 'Here\'s your subscription status.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSubscriptionStatRow(
            icon: m.Icons.directions_car,
            iconColor: Colors.blue,
            title: "Total Vehicles",
            value: "06",
          ),
          const _DottedDivider(),
          _buildSubscriptionStatRow(
            icon: m.Icons.check_circle,
            iconColor: Colors.green,
            title: "Paid",
            value: "05",
          ),
          const _DottedDivider(),
          _buildSubscriptionStatRow(
            icon: m.Icons.cancel,
            iconColor: Colors.red,
            title: "Due",
            value: "01",
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                // Handle Pay Now
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF57C00), // Orange color
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Pay Now",
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 8),
                  m.Icon(m.Icons.arrow_forward, color: Colors.white),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                // Handle View Expiry Dates
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: const Color(0xFFF57C00), width: 2), // Orange border
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "View Expiry Dates",
                    style: TextStyle(
                      fontSize: 18,
                      color: const Color(0xFFF57C00), // Orange text
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 8),
                  m.Icon(m.Icons.arrow_forward, color: const Color(0xFFF57C00)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionStatRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          m.Icon(
            icon,
            color: iconColor,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[800],
              ),
            ),
          ),
          Text(
            ": $value",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleSummaryCard() {
    final vehicleList = dataController.onlyDevices;

    return CustomCard(
      title: 'Vehicle Summary',
      child: isLoadingReport
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Vehicle',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[800],
                      ),
                    ),
                    if (vehicleList.isEmpty)
                      Center(child: Text("noVehicle".tr))
                    else
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.only(bottom: 8),
                        ),
                        value: selectedVehicle,
                        items: vehicleList
                            .map((device) => DropdownMenuItem<String>(
                                  value: _formatVehicleName(device),
                                  child: Text(_formatVehicleName(device)),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            final device = vehicleList.firstWhere(
                              (d) => _formatVehicleName(d) == value,
                              orElse: () => vehicleList.first,
                            );
                            setState(() {
                              selectedVehicle = value;
                              selectedDevice = device;
                            });
                            getTodayDetails(device.id!);
                          }
                        },
                      ),
                  ],
                ),
                const _DottedDivider(),
                _buildStatRow(
                  iconPath: "assets/icons/route-length.png",
                  title: "Route Length",
                  value: todayData?.routeLength ?? '0 Km',
                ),
                const _DottedDivider(),
                _buildStatRow(
                  iconPath: "assets/icons/hourglass-start.png",
                  title: "Move Duration",
                  value: todayData?.moveDuration ?? '0h 0min',
                ),
                const _DottedDivider(),
                _buildStatRow(
                  iconPath: "assets/icons/hourglass-end.png",
                  title: "Stop Duration",
                  value: todayData?.stopDuration ?? '0h 0min',
                ),
                const _DottedDivider(),
                _buildStatRow(
                  iconPath: "assets/icons/speed.png",
                  title: "Top Speed",
                  value: todayData?.topSpeed ?? '0 kph',
                ),
                const _DottedDivider(),
                _buildStatRow(
                  iconPath: "assets/icons/speed-average.png",
                  title: "Average Speed",
                  value: todayData?.averageSpeed ?? '0 kph',
                ),
                const _DottedDivider(),
                _buildStatRow(
                  iconPath: "assets/icons/engine_hours.png",
                  title: "Engine Hours",
                  value: todayData?.engineHours ?? '0h 0min',
                ),
                const _DottedDivider(),
                _buildStatRow(
                  iconPath: "assets/icons/engine-work.png",
                  title: "Engine Works",
                  value: todayData?.engineWork ?? '0h 0min',
                ),
                const _DottedDivider(),
                _buildStatRow(
                  iconPath: "assets/icons/engine-idle.png",
                  title: "Engine Idle",
                  value: todayData?.engineIdle ?? '0h 0min',
                ),
                const _DottedDivider(),
                _buildStatRow(
                  iconPath: "assets/icons/overspeed.png",
                  title: "Overspeed Count",
                  value: todayData?.overspeedCount ?? '0',
                ),
                const _DottedDivider(),
                _buildStatRow(
                  iconPath: "assets/icons/fuel_tank.png",
                  title: "Fuel Consumption",
                  value: selectedDevice?.deviceData?.fuelQuantity ?? '0.00',
                ),
                const _DottedDivider(),
                _buildStatRow(
                  iconPath: "assets/icons/total-distance.png",
                  title: "Total Distance",
                  value: selectedDevice?.totalDistance?.toStringAsFixed(2) ??
                      '0.00 Km',
                ),
              ],
            ),
    );
  }

  Widget _buildStatRow({
    required String iconPath,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14.0),
      child: Row(
        children: [
          Image.asset(
            iconPath,
            width: 24,
            height: 24,
            errorBuilder: (context, error, stackTrace) => m.Icon(
                Icons.help_outline,
                size: 24,
                color: Theme.of(context).primaryColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[800],
              ),
            ),
          ),
          Text(
            ": $value",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _DottedDivider extends StatelessWidget {
  const _DottedDivider({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 4.0;
        const dashGap = 4.0;
        final dashCount = (boxWidth / (dashWidth + dashGap)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: 0.8,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.grey[350]),
              ),
            );
          }),
        );
      },
    );
  }
}

class VehicleMileageChart extends StatelessWidget {
  const VehicleMileageChart({super.key});

  @override
  Widget build(BuildContext context) {
    final barData = [
      {'day': '03', 'value': 150},
      {'day': '04', 'value': 61},
      {'day': '05', 'value': 350},
      {'day': '06', 'value': 235},
      {'day': '07', 'value': 17},
      {'day': '08', 'value': 135},
      {'day': '09', 'value': 150},
    ];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Row(
            children: [
              const m.Icon(Icons.speed, color: Colors.orange, size: 24),
              const SizedBox(width: 8),
              Text(
                "Vehicle 1 (Mileage-km)",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Date Picker style box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.orange.shade100),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  "03/08/2025 - 09/08/2025",
                  style: TextStyle(color: Colors.black54, fontSize: 16),
                ),
                m.Icon(Icons.keyboard_arrow_down, color: Colors.black54),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Chart
          AspectRatio(
            aspectRatio: 1.7,
            child: BarChart(
              BarChartData(
                barTouchData: BarTouchData(
                  enabled: false,
                ),
                alignment: BarChartAlignment.spaceAround,
                maxY: 400,
                gridData: FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        if (value % 100 == 0 && value != 0) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 12),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        int index = value.toInt();
                        if (index < barData.length) {
                          return Text(
                            barData[index]['day'].toString(),
                            style: const TextStyle(fontSize: 12),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(barData.length, (index) {
                  final data = barData[index];
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: (data['value'] as num).toDouble(),
                        gradient: LinearGradient(
                          colors: [
                            Colors.orange.shade700,
                            Colors.orange.shade200,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        width: 32,
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),

          // Values on top of bars
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
