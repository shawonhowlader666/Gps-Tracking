import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:smart_lock/services/payment_service.dart';

class PaymentPackage {
  final String key;
  final String label;
  final double originalPrice;
  final double finalPrice;
  final int discountPercent;

  PaymentPackage({
    required this.key,
    required this.label,
    required this.originalPrice,
    required this.finalPrice,
    required this.discountPercent,
  });

  String get buttonText => discountPercent > 0
      ? '$label\n(৳${finalPrice.toStringAsFixed(0)}) - $discountPercent% ছাড়'
      : '$label\n(৳${finalPrice.toStringAsFixed(0)})';
}

/// Fetches recommended package from server via /users/manual-custom-discount.
/// duration_months is omitted (null) so server decides the best package for this user.
Future<List<PaymentPackage>> fetchAndRecommendPackages(int unpaidBillsCount, {double? dueAmount}) async {
  try {
    // Pass no duration_months — server picks the best one for this user's account
    final res = await PaymentService.calculateManualCustomDiscount(
      willCreate: false,
    );

    debugPrint('[PACKAGES] API response: $res');

    if (res != null && res['payable_total'] != null) {
      // Use duration_months directly from server response (100% dynamic)
      final int durationMonths = (res['duration_months'] as num?)?.toInt() ?? 1;
      final double baseTotal = (res['base_total'] as num?)?.toDouble() ?? 0.0;
      final double payableTotal = (res['payable_total'] as num?)?.toDouble() ?? baseTotal;
      final int discountPercent = (res['discount_percent'] as num?)?.toInt()
          ?? (res['default_discount_percent'] as num?)?.toInt()
          ?? 0;

      // Build label from server data — no hardcoding
      final String label = (durationMonths % 12 == 0)
          ? '${durationMonths ~/ 12} বছরের বিল'
          : '$durationMonths মাসের বিল';

      final String key = (durationMonths % 12 == 0)
          ? '${durationMonths ~/ 12}_year'
          : '${durationMonths}_months';

      final pkg = PaymentPackage(
        key: key,
        label: label,
        originalPrice: baseTotal > 0 ? baseTotal : payableTotal,
        finalPrice: payableTotal,
        discountPercent: discountPercent,
      );

      debugPrint('[PACKAGES] -> ${pkg.key}: ${pkg.label}, price: ${pkg.finalPrice}, discount: ${pkg.discountPercent}%');
      return [pkg];
    }
  } catch (e) {
    debugPrint('[PACKAGES] Exception: $e');
  }

  return [];
}

int getMonthCountFromKey(String key) {
  if (key.endsWith('_year')) {
    final years = int.tryParse(key.split('_').first) ?? 1;
    return years * 12;
  }
  if (key.endsWith('_months') || key.endsWith('_month')) {
    return int.tryParse(key.split('_').first) ?? 1;
  }
  final numeric = int.tryParse(RegExp(r'\d+').firstMatch(key)?.group(0) ?? '');
  return numeric ?? 1;
}
