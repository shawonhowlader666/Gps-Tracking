import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smart_lock/config.dart';
import 'package:smart_lock/widgets/common.dart';

class FuelPriceCard extends StatelessWidget {
  FuelPriceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final updatedDate = fuelData["updated_date"];
    final List<dynamic> prices = fuelData["prices"];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: CustomCard(
        title: 'fuelPrice'.tr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Header Row: Icon + Title + Updated Date
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${'updated'.tr}: $updatedDate',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
            const SizedBox(height: 12),

            /// Fuel price row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: prices.map((item) {
                return Expanded(
                  child: _FuelTypePrice(
                    label: item['label'],
                    price: item['price'],
                    unit: item['unit'],
                    trend: item['trend'],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _FuelTypePrice extends StatelessWidget {
  final String label;
  final String price;
  final String unit;
  final String trend;

  const _FuelTypePrice({
    required this.label,
    required this.price,
    required this.unit,
    required this.trend,
  });

  @override
  Widget build(BuildContext context) {
    IconData arrowIcon = trend == "down"
        ? Icons.arrow_downward
        : trend == "up"
            ? Icons.arrow_upward
            : Icons.horizontal_rule;

    Color arrowColor = trend == "down"
        ? Colors.green
        : trend == "up"
            ? Colors.red
            : Colors.grey;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: price,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Icon(arrowIcon, size: 16, color: arrowColor),
        ],
      ),
    );
  }
}
