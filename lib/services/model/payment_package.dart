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

/// Dynamic billing packages fetched from the server.
/// If server is unreachable or has no packages, it falls back to the default local packages.
Future<List<PaymentPackage>> fetchAndRecommendPackages(int unpaidBillsCount) async {
  try {
    final serverData = await PaymentService.getBillingPackages();
    if (serverData != null && serverData.isNotEmpty) {
      final List<PaymentPackage> serverPackages = [];
      for (var plan in serverData) {
        final rules = plan['pricing_rules'] ?? plan['pricingRules'];
        if (rules != null && rules is List) {
          for (var rule in rules) {
            final duration = rule['duration'];
            final durationType = rule['duration_type'] ?? rule['durationType'];
            final double price = (rule['price'] as num?)?.toDouble() ?? 0.0;

            if (durationType == 'month' || durationType == 'year') {
              final int months = durationType == 'year' ? (duration ?? 1) * 12 : (duration ?? 1);
              final String key = durationType == 'year' ? '${duration}_year' : '${duration}_months';
              final String label = durationType == 'year' ? '$duration বছরের বিল' : '$duration মাসের বিল';

              final double originalPrice = months * 200.0;
              int discount = 0;
              if (originalPrice > price) {
                discount = (((originalPrice - price) / originalPrice) * 100).round();
              }

              serverPackages.add(PaymentPackage(
                key: key,
                label: label,
                originalPrice: originalPrice,
                finalPrice: price,
                discountPercent: discount,
              ));
            }
          }
        }
      }

      if (serverPackages.isNotEmpty) {
        // Sort by final price ascending
        serverPackages.sort((a, b) => a.finalPrice.compareTo(b.finalPrice));
        
        PaymentPackage? pkg1;
        PaymentPackage? pkg2;

        // Find package that covers the due months
        for (var p in serverPackages) {
          final mCount = _getMonthCountFromKey(p.key);
          if (mCount >= unpaidBillsCount) {
            pkg1 = p;
            break;
          }
        }

        pkg1 ??= serverPackages.last;

        // Find an upsell package (larger than pkg1)
        for (var p in serverPackages) {
          final mCount = _getMonthCountFromKey(p.key);
          final pkg1Count = _getMonthCountFromKey(pkg1.key);
          if (mCount > pkg1Count) {
            pkg2 = p;
            break;
          }
        }

        // If no package is larger than pkg1, pick the next largest
        if (pkg2 == null) {
          if (serverPackages.length > 1) {
            pkg2 = pkg1;
            pkg1 = serverPackages[serverPackages.length - 2];
          } else {
            pkg2 = pkg1;
          }
        }

        return [pkg1, pkg2];
      }
    }
  } catch (e) {
    // Fail silently and use local recommendations
  }

  // Fallback to local default logic
  return getRecommendedPackages(unpaidBillsCount);
}

int _getMonthCountFromKey(String key) {
  if (key == '1_year') return 12;
  if (key.endsWith('_year')) {
    final val = int.tryParse(key.split('_').first) ?? 1;
    return val * 12;
  }
  if (key.endsWith('_months')) {
    return int.tryParse(key.split('_').first) ?? 1;
  }
  if (key == '1_month') return 1;
  return 1;
}

List<PaymentPackage> getRecommendedPackages(int unpaidBillsCount) {
  // Standard packages (Rate: 200 BDT/month)
  final p1 = PaymentPackage(
    key: '1_month',
    label: '১ মাসের বিল',
    originalPrice: 200,
    finalPrice: 200,
    discountPercent: 0,
  );
  
  final p3 = PaymentPackage(
    key: '3_months',
    label: '৩ মাসের বিল',
    originalPrice: 600,
    finalPrice: 570,
    discountPercent: 5, // 5% discount
  );
  
  final p6 = PaymentPackage(
    key: '6_months',
    label: '৬ মাসের বিল',
    originalPrice: 1200,
    finalPrice: 1020,
    discountPercent: 15, // 15% discount
  );
  
  final p12 = PaymentPackage(
    key: '1_year',
    label: '১ বছরের বিল',
    originalPrice: 2400,
    finalPrice: 1800,
    discountPercent: 25, // 25% discount
  );

  if (unpaidBillsCount <= 1) {
    return [p1, p3]; // Recommend 1 Month & 3 Months
  } else if (unpaidBillsCount <= 3) {
    return [p3, p6]; // Recommend 3 Months & 6 Months
  } else if (unpaidBillsCount <= 5) {
    return [p6, p12]; // Recommend 6 Months & 1 Year
  } else {
    // If they have 6+ months, calculate custom dues with 10% discount
    final customPrice = unpaidBillsCount * 200.0;
    final finalPrice = customPrice * 0.9;
    final pCustom = PaymentPackage(
      key: '${unpaidBillsCount}_months',
      label: '$unpaidBillsCount মাসের বিল',
      originalPrice: customPrice,
      finalPrice: finalPrice,
      discountPercent: 10,
    );
    return [pCustom, p12];
  }
}
