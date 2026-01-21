// lib/screens/report/widgets/hourly_chart.dart

import 'package:flutter/material.dart';
import 'package:gpspro/screens/report/models/report_models.dart';

class HourlyDistanceChart extends StatelessWidget {
  final List<HourlyReportData> hourlyData;

  const HourlyDistanceChart({
    Key? key,
    required this.hourlyData,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (hourlyData.isEmpty) {
      return const Center(
        child: Text(
          'No data available',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final maxDistance = hourlyData.map((e) => e.distance).reduce((a, b) => a > b ? a : b);

    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = (constraints.maxWidth - 40) / 24;

        return Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(24, (hour) {
                  final data = hourlyData.firstWhere(
                        (d) => d.hour == hour,
                    orElse: () => HourlyReportData(
                      hour: hour,
                      distance: 0,
                      duration: Duration.zero,
                      avgSpeed: 0,
                      maxSpeed: 0,
                      tripCount: 0,
                    ),
                  );

                  final heightRatio = maxDistance > 0
                      ? data.distance / maxDistance
                      : 0.0;

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (data.distance > 0)
                            Tooltip(
                              message: '${hour}:00 - ${data.distance.toStringAsFixed(2)} km',
                              child: Container(
                                height: heightRatio * (constraints.maxHeight - 30),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF2196F3).withOpacity(0.7),
                                      const Color(0xFF21CBF3),
                                    ],
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                  ),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(3),
                                    topRight: Radius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            // X-axis labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('00:00', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                Text('06:00', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                Text('12:00', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                Text('18:00', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                Text('24:00', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ],
            ),
          ],
        );
      },
    );
  }
}