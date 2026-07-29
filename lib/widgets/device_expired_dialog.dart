import 'package:flutter/material.dart' hide Icon;
import 'package:flutter/material.dart' as m show Icon;
import 'package:url_launcher/url_launcher.dart';
import 'package:smart_lock/config.dart';
import 'package:smart_lock/screens/manual_payment_screen.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
import 'package:smart_lock/services/model/payment_package.dart';
import 'package:smart_lock/services/model/payment_stats.dart';
import 'package:smart_lock/services/payment_service.dart';
import 'package:smart_lock/storage/user_repository.dart';
import 'package:smart_lock/theme/custom_color.dart';

class DeviceExpiredBlockingDialog extends StatelessWidget {
  final DeviceItem device;

  const DeviceExpiredBlockingDialog({super.key, required this.device});

  Future<void> _launchPhone(BuildContext context, String number) async {
    if (number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Helpline number not available')),
      );
      return;
    }
    final Uri uri = Uri.parse('tel:$number');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Calling not supported on this device')),
          );
        }
      }
    } catch (e) {
      debugPrint('Phone launch error: $e');
    }
  }

  Future<void> _launchWhatsApp(BuildContext context, String number) async {
    if (number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp number not available')),
      );
      return;
    }
    final String clean = number.replaceAll(RegExp(r'[^0-9]'), '');
    final String rawIdentifier = UserRepository.getEmail() ?? '';
    // Sanitize: strip any corrupted suffix like ") - Bike (IMEI: ...)" from stored email
    String cleanIdentifier = rawIdentifier;
    if (rawIdentifier.contains(')')) {
      cleanIdentifier = rawIdentifier.substring(0, rawIdentifier.indexOf(')')).trim();
    } else if (rawIdentifier.contains(' - ')) {
      cleanIdentifier = rawIdentifier.substring(0, rawIdentifier.indexOf(' - ')).trim();
    } else if (rawIdentifier.contains('@')) {
      cleanIdentifier = rawIdentifier.split('@').first.trim();
    }

    String message =
        "Hello, I need help renewing my expired device: ${device.name ?? ''} ($cleanIdentifier)";
    final Uri uri =
        Uri.parse('https://wa.me/$clean?text=${Uri.encodeComponent(message)}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('WhatsApp is not installed')),
          );
        }
      }
    } catch (e) {
      debugPrint('WhatsApp launch error: $e');
    }
  }


  String _toBanglaDigits(String input) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const bangla = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

    String result = input;
    for (int i = 0; i < english.length; i++) {
      result = result.replaceAll(english[i], bangla[i]);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    String expiryText = 'N/A';
    try {
      final expiryDateStr = device.deviceData?.expirationDate?.toString();
      if (expiryDateStr != null && expiryDateStr.isNotEmpty) {
        final date = DateTime.tryParse(expiryDateStr);
        if (date != null) {
          final String formattedDate = "${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}";
          final difference = DateTime.now().difference(date).inDays;
          final int daysDiff = difference < 0 ? 0 : difference;

          if (daysDiff == 0) {
            expiryText = _toBanglaDigits('মেয়াদ উত্তীর্ণ (০ দিন বাকি) - $formattedDate');
          } else {
            expiryText = _toBanglaDigits('মেয়াদ উত্তীর্ণ ($daysDiff দিন অতিবাহিত) - $formattedDate');
          }
        }
      }
    } catch (_) {}

    return PopScope(
      canPop: true,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.2),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- Header ---
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF2C2C3E), Color(0xFFD32F2F)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Column(
                          children: [
                            const m.Icon(
                              Icons.error_outline_rounded,
                              color: Color(0xFFFFD700),
                              size: 48,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'ডিভাইসের মেয়াদ শেষ',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Device Expired',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // --- Body ---
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            // Device Details
                            Text(
                              device.name ?? 'Device',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF212121),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEEEE),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                expiryText,
                                style: const TextStyle(
                                  color: Color(0xFFD32F2F),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            FutureBuilder<ExpiredDialogData>(
                              future: loadExpiredDialogData(device),
                              builder: (context, snapshot) {
                                final data = snapshot.data ?? ExpiredDialogData(
                                  null,
                                  [],
                                );

                                final stats = data.stats;
                                final due = stats?.due ?? 0.0;
                                final unpaidBillsCount = stats?.unpaidBillsCount ?? 1;

                                final hasPackages = data.packages.isNotEmpty;
                                final pkg1 = hasPackages ? data.packages[0] : null;
                                final pkg2 = hasPackages && data.packages.length > 1 ? data.packages[1] : pkg1;

                                // Display exact due amount from server
                                final displayedDue = due;

                                final dynamicDescription = due > 0
                                      ? 'কানেকশন সচল রাখতে অনুগ্রহ করে বিল পরিশোধ করুন। আপনার মোট ${AppLang.num(unpaidBillsCount)} মাসের বিল (৳${AppLang.num(due.toStringAsFixed(0))}) বকেয়া রয়েছে।'
                                    : 'অনুগ্রহ করে বকেয়া বিল পরিশোধ করুন।';

                                return Column(
                                  children: [
                                    // Due Amount Row (Always visible)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'মোট বকেয়া: ',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                          Text(
                                            '৳${displayedDue.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFD32F2F),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    Text(
                                      dynamicDescription,
                                      style: const TextStyle(
                                        color: Color(0xFF616161),
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 20),

                                    // ✅ Pay Now Button (for the exact due amount)
                                    SizedBox(
                                      width: double.infinity,
                                      height: 50,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).pop(); // Close dialog
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => ManualPaymentScreen(
                                                dueAmount: displayedDue,
                                                isAfter10th: false,
                                                packageType: 'due_payment',
                                                packageTitle: 'Due Payment (${displayedDue.toStringAsFixed(0)} BDT)',
                                                vehicleName: device.name,
                                              ),
                                            ),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1B6B3A),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          elevation: 0,
                                        ),
                                        icon: const m.Icon(Icons.credit_card_rounded, size: 20, color: Colors.white),
                                        label: const Text(
                                          'এখনই পরিশোধ করুন',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),

                                    if (hasPackages) ...[
                                      const SizedBox(height: 16),

                                      // Divider
                                      const Row(
                                        children: [
                                          Expanded(child: Divider(color: Color(0xFFEEEEEE))),
                                          Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 10),
                                            child: Text(
                                              'অথবা প্যাকেজ সিলেক্ট করুন',
                                              style: TextStyle(fontSize: 11, color: Colors.grey),
                                            ),
                                          ),
                                          Expanded(child: Divider(color: Color(0xFFEEEEEE))),
                                        ],
                                      ),

                                      const SizedBox(height: 16),

                                      // Action Buttons - Recommended Packages
                                      if (pkg1 == pkg2)
                                        SizedBox(
                                          width: double.infinity,
                                          height: 48,
                                          child: ElevatedButton(
                                            onPressed: () {
                                              Navigator.of(context).pop(); // Close dialog
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => ManualPaymentScreen(
                                                    dueAmount: pkg1!.finalPrice,
                                                    isAfter10th: false,
                                                    packageType: pkg1.key,
                                                    packageTitle: pkg1.buttonText,
                                                    vehicleName: device.name,
                                                  ),
                                                ),
                                              );
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFFE4B34E),
                                              foregroundColor: Colors.black,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              elevation: 0,
                                            ),
                                            child: Text(
                                              pkg1!.buttonText,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        )
                                      else
                                        Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  Navigator.of(context).pop(); // Close dialog
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (_) => ManualPaymentScreen(
                                                        dueAmount: pkg1!.finalPrice,
                                                        isAfter10th: false,
                                                        packageType: pkg1.key,
                                                        packageTitle: pkg1.buttonText,
                                                        vehicleName: device.name,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF1B6B3A),
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  elevation: 0,
                                                ),
                                                child: Text(
                                                  pkg1!.buttonText,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  Navigator.of(context).pop(); // Close dialog
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (_) => ManualPaymentScreen(
                                                        dueAmount: pkg2!.finalPrice,
                                                        isAfter10th: false,
                                                        packageType: pkg2.key,
                                                        packageTitle: pkg2.buttonText,
                                                        vehicleName: device.name,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFFE4B34E),
                                                  foregroundColor: Colors.black,
                                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  elevation: 0,
                                                ),
                                                child: Text(
                                                  pkg2!.buttonText,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 12),

                            // Contact Buttons - Helpline & WhatsApp
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _launchPhone(context, PHONE_NO),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF1D4888),
                                      side: const BorderSide(
                                          color: Color(0xFF1D4888)),
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const m.Icon(Icons.phone, size: 16),
                                    label: const Text(
                                      'হেল্পলাইন',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _launchWhatsApp(context, WHATS_APP),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF25D366),
                                      side: const BorderSide(
                                          color: Color(0xFF25D366)),
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const m.Icon(Icons.chat, size: 16),
                                    label: const Text(
                                      'হোয়াটসঅ্যাপ',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Close button
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text(
                                'বাতিল করুন (Close)',
                                style: TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const m.Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ExpiredDialogData {
  final PaymentStats? stats;
  final List<PaymentPackage> packages;
  ExpiredDialogData(this.stats, this.packages);
}

Future<ExpiredDialogData> loadExpiredDialogData(DeviceItem device) async {
  final stats = await PaymentService.getStats().catchError((_) => null);
  PaymentStats? resolvedStats = stats;

  final deviceId = device.id;
  final vehicleName = device.name;
  final vehicleImei = device.imei ?? device.deviceData?.imei;

  if (deviceId != null || vehicleName != null || vehicleImei != null) {
    try {
      final rawInvoices = await PaymentService.getInvoicesRaw();
      if (rawInvoices != null && rawInvoices['bills'] != null) {
        final List bills = rawInvoices['bills'];
        
        // Filter bills for this device using ID, IMEI, or Name
        final deviceBills = bills.where((b) {
          final bVehicleId = b['vehicle_id'] ?? b['device_id'];
          final bVehicle = b['vehicle'];
          
          final matchId = deviceId != null && bVehicleId != null && bVehicleId.toString() == deviceId.toString();
          final matchImei = vehicleImei != null && bVehicle != null && bVehicle['imei'] != null && bVehicle['imei'].toString() == vehicleImei.toString();
          final matchName = vehicleName != null && bVehicle != null && bVehicle['name'] != null && bVehicle['name'].toString().toLowerCase().trim() == vehicleName.toString().toLowerCase().trim();
          
          return matchId || matchImei || matchName;
        }).toList();

        if (deviceBills.isNotEmpty) {
          // Sum unpaid bills for this device
          final double deviceDue = deviceBills
              .where((b) => b['status'] == 'unpaid')
              .map((b) => (b['amount'] ?? b['total_bill'] ?? 0.0) as num)
              .fold(0.0, (sum, amt) => sum + amt.toDouble());

          final int deviceUnpaidCount = deviceBills
              .where((b) => b['status'] == 'unpaid')
              .length;

          resolvedStats = PaymentStats(
            due: deviceDue,
            totalBilled: deviceBills
                .map((b) => (b['amount'] ?? b['total_bill'] ?? 0.0) as num)
                .fold(0.0, (sum, amt) => sum + amt.toDouble()),
            totalPaid: deviceBills
                .where((b) => b['status'] == 'paid')
                .map((b) => (b['amount'] ?? b['total_bill'] ?? 0.0) as num)
                .fold(0.0, (sum, amt) => sum + amt.toDouble()),
            unpaidBillsCount: deviceUnpaidCount > 0 ? deviceUnpaidCount : 1,
            enableBillAlert: stats?.enableBillAlert ?? true,
          );
        }
      }
    } catch (_) {}
  }

  final unpaidBillsCount = resolvedStats?.unpaidBillsCount ?? 1;
  final packages = await fetchAndRecommendPackages(unpaidBillsCount);
  return ExpiredDialogData(resolvedStats, packages);
}

// ─────────────────────────────────────────────────────────────────────────────
// DeviceExpiryReminderDialog — shown when device expires today (days remaining = 0)
// ─────────────────────────────────────────────────────────────────────────────

class DeviceExpiryReminderDialog extends StatelessWidget {
  final DeviceItem device;

  const DeviceExpiryReminderDialog({super.key, required this.device});

  Future<void> _launchWhatsApp(BuildContext context, String number) async {
    if (number.isEmpty) return;
    final String clean = number.replaceAll(RegExp(r'[^0-9]'), '');
    final String rawIdentifier = UserRepository.getEmail() ?? '';
    String cleanIdentifier = rawIdentifier;
    if (rawIdentifier.contains(')')) {
      cleanIdentifier = rawIdentifier.substring(0, rawIdentifier.indexOf(')')).trim();
    } else if (rawIdentifier.contains(' - ')) {
      cleanIdentifier = rawIdentifier.substring(0, rawIdentifier.indexOf(' - ')).trim();
    } else if (rawIdentifier.contains('@')) {
      cleanIdentifier = rawIdentifier.split('@').first.trim();
    }
    final String message =
        "Hello, I need help renewing my device: ${device.name ?? ''} ($cleanIdentifier) — expires today!";
    final Uri uri = Uri.parse('https://wa.me/$clean?text=${Uri.encodeComponent(message)}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('WhatsApp launch error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final String whatsapp = WHATS_APP;

    return PopScope(
      canPop: true,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.25),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF2C2C3E), Color(0xFFE65100)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      children: [
                        const m.Icon(
                          Icons.access_time_rounded,
                          color: Color(0xFFFFD700),
                          size: 48,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'মেয়াদ শেষ হচ্ছে আজ!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Expires Today',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Body
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          device.name ?? 'Device',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF212121),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE65100).withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'এই ডিভাইসটির সার্ভিসের মেয়াদ আজ শেষ হয়ে যাচ্ছে।\nবিল পরিশোধ না করলে ডিভাইসটি বন্ধ হয়ে যাবে।',
                            style: TextStyle(
                              color: Color(0xFFE65100),
                              fontSize: 13,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // WhatsApp button
                        if (whatsapp.isNotEmpty)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _launchWhatsApp(context, whatsapp),
                              icon: const m.Icon(Icons.chat_rounded, size: 18),
                              label: const Text('WhatsApp-এ যোগাযোগ করুন'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),

                        const SizedBox(height: 10),

                        // Remind in 7 days button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const m.Icon(Icons.notifications_outlined, size: 18),
                            label: const Text('৭ দিন পর মনে করিয়ে দিন'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF757575),
                              side: const BorderSide(color: Color(0xFFBDBDBD)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
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
    );
  }
}

