import 'package:flutter/material.dart' hide Icon;
import 'package:flutter/material.dart' as m show Icon;
import 'package:url_launcher/url_launcher.dart';
import 'package:smart_lock/config.dart';
import 'package:smart_lock/screens/manual_payment_screen.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
import 'package:smart_lock/storage/user_repository.dart';

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
            const SnackBar(content: Text('Calling not supported on this device')),
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
    String deviceIdentifier = UserRepository.getEmail() ?? '';
    String cleanIdentifier = deviceIdentifier;
    if (deviceIdentifier.contains('@')) {
      cleanIdentifier = deviceIdentifier.split('@').first;
    }

    String message = "Hello, I need help renewing my expired device: ${device.name ?? ''} ($cleanIdentifier)";
    final Uri uri = Uri.parse('https://wa.me/$clean?text=${Uri.encodeComponent(message)}');
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

  void _navigateToPayment(BuildContext context, String packageType) {
    Navigator.of(context).pop(); // Close the dialog
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualPaymentScreen(
          dueAmount: packageType == '1_year' ? 1800.0 : 200.0,
          isAfter10th: false,
          packageType: packageType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String expiry = device.deviceData?.expirationDate?.toString() ?? 'N/A';

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
              child: Column(
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
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEEEE),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Expired On: $expiry',
                            style: const TextStyle(
                              color: Color(0xFFD32F2F),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          'কানেকশন সচল রাখতে অনুগ্রহ করে বিল পরিশোধ করুন। ১ বছরের অগ্রিম পেমেন্টে ২৫% ডিসকাউন্ট রয়েছে।',
                          style: TextStyle(
                            color: Color(0xFF616161),
                            fontSize: 13,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),

                        // Action Buttons - 1 Month & 1 Year
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _navigateToPayment(context, '1_month'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1B6B3A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  '১ মাসের বিল',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _navigateToPayment(context, '1_year'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE4B34E),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  '১ বছরের বিল',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Contact Buttons - Helpline & WhatsApp
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _launchPhone(context, PHONE_NO),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF1D4888),
                                  side: const BorderSide(color: Color(0xFF1D4888)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const m.Icon(Icons.phone, size: 16),
                                label: const Text(
                                  'হেল্পলাইন',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _launchWhatsApp(context, WHATS_APP),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF25D366),
                                  side: const BorderSide(color: Color(0xFF25D366)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const m.Icon(Icons.chat, size: 16),
                                label: const Text(
                                  'হোয়াটসঅ্যাপ',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
            ),
          ),
        ),
      ),
    );
  }
}
