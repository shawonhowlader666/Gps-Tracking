import 'package:flutter/material.dart';
import 'package:gpspro/config.dart';
import 'package:gpspro/screens/web_view.dart';
import 'package:gpspro/services/payment_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentBlockScreen extends StatefulWidget {
  final double dueAmount;
  final VoidCallback onRefresh;

  const PaymentBlockScreen({
    super.key,
    required this.dueAmount,
    required this.onRefresh,
  });

  @override
  State<PaymentBlockScreen> createState() => _PaymentBlockScreenState();
}

class _PaymentBlockScreenState extends State<PaymentBlockScreen> {
  bool _isVerifying = false;
  bool _isInitiatingPayment = false;

  Future<void> _handlePayNow() async {
    if (_isInitiatingPayment) return;

    setState(() {
      _isInitiatingPayment = true;
    });

    _showLoadingDialog("পেমেন্ট গেটওয়ে লোড হচ্ছে...");

    try {
      final gatewayUrl = await PaymentService.initiateSslPayment();
      if (mounted) {
        Navigator.of(context).pop(); // Pop loading dialog
      }

      if (gatewayUrl != null && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WebViewScreen(
              title: 'পেমেন্ট',
              url: gatewayUrl,
            ),
          ),
        );
        // Re-check payment status when returning from WebView
        widget.onRefresh();
      } else {
        _showSnackBar('পেমেন্ট গেটওয়ে চালু করা যায়নি। অনুগ্রহ করে আবার চেষ্টা করুন।', Colors.red);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Pop loading dialog
      }
      _showSnackBar('একটি ত্রুটি ঘটেছে: ${e.toString()}', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isInitiatingPayment = false;
        });
      }
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD32F2F)),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    if (_isVerifying) return;

    setState(() {
      _isVerifying = true;
    });

    _showLoadingDialog("পেমেন্ট যাচাই করা হচ্ছে...");

    try {
      // Small delay for server sync
      await Future.delayed(const Duration(seconds: 1));
      widget.onRefresh();
    } finally {
      if (mounted) {
        Navigator.of(context).pop(); // Pop loading dialog
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  void _showSupportDialog() {
    final phoneNum = PHONE_NO.isNotEmpty ? PHONE_NO : "+8801960446666";
    final whatsAppNum = WHATS_APP.isNotEmpty ? WHATS_APP : "+8801960446666";
    final cleanWhatsApp = whatsAppNum.replaceAll(RegExp(r'[^0-9]'), '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.support_agent_rounded, color: Color(0xFFD32F2F)),
            SizedBox(width: 8),
            Text('হেল্পলাইন ও সাপোর্ট', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone_in_talk_rounded, color: Colors.green),
              title: const Text('কল করুন'),
              subtitle: Text(phoneNum),
              onTap: () async {
                Navigator.pop(ctx);
                final Uri uri = Uri.parse('tel:$phoneNum');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_rounded, color: Colors.green),
              title: const Text('হোয়াটসঅ্যাপ (WhatsApp)'),
              subtitle: Text(whatsAppNum),
              onTap: () async {
                Navigator.pop(ctx);
                final Uri uri = Uri.parse('https://wa.me/$cleanWhatsApp');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('বন্ধ করুন', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = UserRepository.getEmail() ?? "অজ্ঞাত অ্যাকাউন্ট";

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Warning Icon
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3), width: 3),
                  ),
                  child: const Icon(
                    Icons.lock_clock_rounded,
                    color: Color(0xFFEF4444),
                    size: 72,
                  ),
                ),
                const SizedBox(height: 32),

                // Bangla Error text
                const Text(
                  'সেবা সাময়িকভাবে স্থগিত',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'আপনার অ্যাকাউন্টে পেমেন্ট বকেয়া থাকায় সেবাটি সাময়িকভাবে স্থগিত করা হয়েছে। অবিলম্বে সেবাটি সচল করতে অনুগ্রহ করে বকেয়া বিল পরিশোধ করুন।',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Due Detail Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'অ্যাকাউন্ট ইমেইল:',
                            style: TextStyle(color: Colors.grey[400], fontSize: 13),
                          ),
                          Text(
                            email,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'মোট বকেয়া বিল:',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '৳ ${widget.dueAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Buttons layout
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _handlePayNow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.payment_rounded, size: 20),
                    label: const Text(
                      'এখনই পেমেন্ট করুন',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _showSupportDialog,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.support_agent_rounded, size: 18),
                          label: const Text('সাপোর্ট', style: TextStyle(fontSize: 14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _handleRefresh,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.sync_rounded, size: 18),
                          label: const Text('যাচাই করুন', style: TextStyle(fontSize: 14)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
