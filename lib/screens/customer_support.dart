import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gpspro/widgets/scale_button.dart';

class CustomerSupportScreen extends StatefulWidget {
  const CustomerSupportScreen({super.key});

  @override
  State<CustomerSupportScreen> createState() => _CustomerSupportScreenState();
}

class _CustomerSupportScreenState extends State<CustomerSupportScreen> {
  // Trigger phone call
  Future<void> _makeCall(String number) async {
    final Uri url = Uri(scheme: 'tel', path: number);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      _showErrorSnackBar("Could not initiate call: $e");
    }
  }

  // Trigger email draft
  Future<void> _sendEmail(String email) async {
    final Uri url = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': 'Support Ticket: OrbitGPS'},
    );
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      _showErrorSnackBar("Could not open email application: $e");
    }
  }

  // Trigger WhatsApp message
  Future<void> _openWhatsApp(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    final Uri url = Uri.parse("https://wa.me/$cleanPhone");
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      _showErrorSnackBar("Could not launch WhatsApp: $e");
    }
  }

  // Copy to clipboard helper
  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text('$label copied to clipboard!'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: const Color(0xFF1E293B),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E293B).withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ScaleButton(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Color(0xFF334155),
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  const Text(
                    'Customer Support',
                    style: TextStyle(
                      color: Color(0xFF0F4FAF),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 16),
              child: Text(
                'Support Channels',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            // The Grid / List of Support 3D Cards in 2x2 layout
            Row(
              children: [
                Expanded(
                  child: _buildSupportCard(
                    title: 'Phone Support',
                    subtitle: '01901388950',
                    icon: Icons.phone_in_talk_rounded,
                    iconColor: const Color(0xFF0083B0),
                    iconBgColor: const Color(0xFFE0F7FA),
                    shadowColor: const Color(0xFF0083B0),
                    onTap: () => _makeCall('01901388950'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSupportCard(
                    title: 'Helpline Hotline',
                    subtitle: '01901645999',
                    icon: Icons.support_agent_rounded,
                    iconColor: const Color(0xFFF12711),
                    iconBgColor: const Color(0xFFFFEBEE),
                    shadowColor: const Color(0xFFF12711),
                    onTap: () => _makeCall('01901645999'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSupportCard(
                    title: 'Email Support',
                    subtitle: 'info@orbitgps.com.bd',
                    icon: Icons.alternate_email_rounded,
                    iconColor: const Color(0xFF8E2DE2),
                    iconBgColor: const Color(0xFFF3E8FF),
                    shadowColor: const Color(0xFF8E2DE2),
                    onTap: () => _sendEmail('info@orbitgps.com.bd'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSupportCard(
                    title: 'WhatsApp Chat',
                    subtitle: '+8801901645999',
                    icon: Icons.question_answer_rounded,
                    iconColor: const Color(0xFF11998E),
                    iconBgColor: const Color(0xFFE8F5E9),
                    shadowColor: const Color(0xFF11998E),
                    onTap: () => _openWhatsApp('+8801901645999'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required Color shadowColor,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 115,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            // Underlying tap area for main card action
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  splashColor: iconBgColor.withOpacity(0.15),
                  highlightColor: iconBgColor.withOpacity(0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: iconBgColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            icon,
                            color: iconColor,
                            size: 20,
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Color(0xFF1E293B),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Positioned Copy Button on top right to avoid parent InkWell tap bubbling
            Positioned(
              top: 12,
              right: 12,
              child: ScaleButton(
                onTap: () => _copyToClipboard(subtitle, title),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.copy_rounded,
                    color: Colors.grey[600],
                    size: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
