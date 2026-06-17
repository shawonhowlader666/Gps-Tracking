import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:get/get.dart';
import 'package:gpspro/constants/app_constants.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gpspro/screens/payment_list.dart';
import 'package:gpspro/screens/customer_support.dart';
import 'package:gpspro/widgets/scale_button.dart';
import 'package:gpspro/theme/custom_color.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<StatefulWidget> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SharedPreferences? prefs;
  File? _image;
  final ImagePicker _picker = ImagePicker();
  bool isLoading = true;

  @override
  void initState() {
    _loadImageFromPrefs();
    getUser();
    super.initState();
  }

  Future<void> getUser() async {
    setState(() {
      isLoading = false;
    });
  }

  Future<void> _loadImageFromPrefs() async {
    prefs = await SharedPreferences.getInstance();
    final String? imagePath = prefs?.getString('profile_image_path');
    if (imagePath != null && imagePath.isNotEmpty) {
      setState(() {
        _image = File(imagePath);
      });
    }
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile =
    await _picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
      await prefs?.setString('profile_image_path', pickedFile.path);
    }
  }

  Future<void> logout() async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // 1. Clear SharedPreferences data
      if (prefs != null) {
        await prefs!.remove('profile_image_path');
        await prefs!.clear();
      }

      // 2. Delete profile image file
      if (_image != null && await _image!.exists()) {
        try {
          await _image!.delete();
        } catch (e) {
        }
      }


      // 4. Reset GetX controllers
      Get.deleteAll(force: true);

      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      // 5. Restart app
      Phoenix.rebirth(context);

    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: CustomColor.primary.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                 Icon(
                    Icons.settings,
                    color: CustomColor.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 60),
                  Text(
                    'Settings',
                    style: const TextStyle(
                      color: CustomColor.primary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: !isLoading
          ? SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileCard(),
            const SizedBox(height: 24),
            _buildSectionTitle('General'),
            const SizedBox(height: 12),
            _buildSettingsCard([
              _buildSettingItem(
                icon: Icons.notifications_outlined,
                iconColor: CustomColor.primary,
                iconBgColor: Colors.transparent,
                iconSize: 24,
                title: 'Alerts',
                subtitle: 'Manage notifications',
                onTap: () => Navigator.pushNamed(context, "/alertList"),
              ),
              _buildDivider(),
              _buildSettingItem(
                icon: Icons.fence_outlined,
                iconColor: CustomColor.primary,
                iconBgColor: Colors.transparent,
                title: 'Geofence',
                subtitle: 'Set location zones',
                onTap: () => Navigator.pushNamed(context, "/geofenceList"),
              ),
              _buildDivider(),
              _buildSettingItem(
                icon: Icons.language_outlined,
                iconColor: CustomColor.primary,
                iconBgColor: Colors.transparent,
                title: 'Language',
                subtitle: 'Select language',
                onTap: () => _showLanguageDialog(context),
              ),
            ]),
            const SizedBox(height: 24),
            _buildSectionTitle('Account & Support'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildPremium3DCard(
                    title: 'Payment',
                    subtitle: 'View invoices',
                    icon: Icons.payment_rounded,
                    iconColor: CustomColor.primary,
                    iconBgColor: Colors.transparent,
                    shadowColor: CustomColor.primary,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PaymentListScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildPremium3DCard(
                    title: 'Support',
                    subtitle: '24/7 Helpline',
                    icon: Icons.headset_mic_rounded,
                    iconColor: CustomColor.primary,
                    iconBgColor: Colors.transparent,
                    shadowColor: CustomColor.primary,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CustomerSupportScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Support'),
            const SizedBox(height: 12),
            _buildSettingsCard([
              _buildSettingItem(
                icon: Icons.description_outlined,
                iconColor: CustomColor.primary,
                iconBgColor: Colors.transparent,
                title: 'Terms & Conditions',
                subtitle: 'Read terms',
                onTap: () => _showTermsAndConditions(),
              ),
              _buildDivider(),
              _buildSettingItem(
                icon: Icons.privacy_tip_outlined,
                iconColor: CustomColor.primary,
                iconBgColor: Colors.transparent,
                title: 'Privacy Policy',
                subtitle: 'Read privacy',
                onTap: () => _showPrivacyPolicy(),
              ),
            ]),
            const SizedBox(height: 24),
            _buildLogoutButton(),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Version 1.0.9+11',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
            ),
          ],
        ),
      )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(16),
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
      ),
      child: Row(
        children: [
          ScaleButton(
            onTap: _pickImage,
            child: Stack(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: CustomColor.primary,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: _image != null
                        ? Image.file(_image!, fit: BoxFit.cover)
                        : Image.asset(
                      "assets/images/user.png",
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: CustomColor.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UserRepository.getName() ?? '${AppConstants.appName} User',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  UserRepository.getEmail() ?? "user@example.com",
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.edit_outlined,
              color: CustomColor.primary,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey[500],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildPremium3DCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required Color shadowColor,
    required VoidCallback onTap,
  }) {
    return ScaleButton(
      onTap: onTap,
      child: Container(
        height: 105,
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
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      color: iconColor,
                      size: 20,
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.grey[300],
                    size: 16,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
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
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
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
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    double iconSize = 20,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: iconSize),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Divider(height: 1, color: Colors.grey[100]),
    );
  }

  Widget _buildLogoutButton() {
    return ScaleButton(
      onTap: () => _showLogoutDialog(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
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
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.logout_outlined,
                color: Colors.red,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Logout',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Colors.red[300],
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              logout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Select Language',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildLanguageOption(
              flag: '🇺🇸',
              language: 'English',
              isSelected: Get.locale?.languageCode == 'en',
              onTap: () async {
                Get.updateLocale(const Locale('en'));
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('language_code', 'en');
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 10),
            _buildLanguageOption(
              flag: '🇧🇩',
              language: 'বাংলা',
              isSelected: Get.locale?.languageCode == 'bn',
              onTap: () async {
                Get.updateLocale(const Locale('bn'));
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('language_code', 'bn');
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption({
    required String flag,
    required String language,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? CustomColor.primary.withValues(alpha: 0.1)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? CustomColor.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                language,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? CustomColor.primary : Colors.grey[800],
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: CustomColor.primary, size: 22),
          ],
        ),
      ),
    );
  }

  // Terms and Conditions Dialog
  void _showTermsAndConditions() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      CustomColor.primary,
                      CustomColor.primary.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Terms & Conditions',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTermsSection(
                        'Acceptance of Terms',
                        'By downloading, installing, or using ONFLEET GPS GPS Tracking App, you agree to be bound by these Terms and Conditions. If you do not agree to these terms, please do not use our services.',
                      ),
                      _buildTermsSection(
                        'Service Description',
                        'ONFLEET GPS provides real-time GPS tracking services for vehicles. Our services include location tracking, geofencing, alerts, trip history, and fleet management features.',
                      ),
                      _buildTermsSection(
                        'User Responsibilities',
                        '• You must be at least 18 years old to use this service\n'
                            '• You are responsible for maintaining account confidentiality\n'
                            '• You must only track vehicles you own or have permission to track\n'
                            '• You agree to use the service in compliance with all applicable laws',
                      ),
                      _buildTermsSection(
                        'Service Availability',
                        'While we strive for 99.9% uptime, we do not guarantee uninterrupted service. GPS tracking accuracy may vary based on signal strength, weather conditions, and device hardware.',
                      ),
                      _buildTermsSection(
                        'Payment Terms',
                        'Subscription fees are charged according to your selected plan. Payments are non-refundable except as required by law. We reserve the right to modify pricing with 30 days notice.',
                      ),
                      _buildTermsSection(
                        'Prohibited Uses',
                        'You may not use our service to:\n'
                            '• Stalk, harass, or violate the privacy of others\n'
                            '• Track vehicles without proper authorization\n'
                            '• Engage in illegal activities\n'
                            '• Resell or redistribute our services',
                      ),
                      _buildTermsSection(
                        'Limitation of Liability',
                        'ONFLEET GPS is not liable for any indirect, incidental, or consequential damages arising from use of our services. Our maximum liability is limited to the amount paid for the service.',
                      ),
                      _buildTermsSection(
                        'Termination',
                        'We reserve the right to suspend or terminate accounts that violate these terms. You may cancel your subscription at any time through the app settings.',
                      ),
                      _buildTermsSection(
                        'Changes to Terms',
                        'We may update these terms periodically. Continued use of the service after changes constitutes acceptance of the new terms.',
                      ),
                      _buildTermsSection(
                        'Contact Information',
                        'For questions about these terms, contact us at:\nEmail: asthahelpbd@gmail.com\nPhone: +880-1912609087',
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          'Last Updated: ${DateTime.now().year}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Privacy Policy Dialog
  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      CustomColor.primary,
                      CustomColor.primary.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.privacy_tip, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTermsSection(
                        'Introduction',
                        'ONFLEET GPS ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our GPS tracking application.',
                      ),
                      _buildTermsSection(
                        'Information We Collect',
                        'Personal Information:\n'
                            '• Name, email address, phone number\n'
                            '• Account credentials and profile information\n'
                            '• Payment and billing information\n\n'
                            'Location Data:\n'
                            '• Real-time GPS coordinates\n'
                            '• Historical location data\n'
                            '• Speed and direction information\n\n'
                            'Device Information:\n'
                            '• Device type and model\n'
                            '• Operating system version\n'
                            '• Unique device identifiers\n'
                            '• IP address and network information',
                      ),
                      _buildTermsSection(
                        'How We Use Your Information',
                        '• Provide GPS tracking and location services\n'
                            '• Process payments and manage subscriptions\n'
                            '• Send notifications and alerts\n'
                            '• Improve and optimize our services\n'
                            '• Provide customer support\n'
                            '• Comply with legal obligations\n'
                            '• Prevent fraud and ensure security',
                      ),
                      _buildTermsSection(
                        'Data Sharing and Disclosure',
                        'We do not sell your personal information. We may share data with:\n\n'
                            '• Service Providers: Cloud hosting, payment processors, and analytics services\n'
                            '• Legal Requirements: When required by law or to protect our rights\n'
                            '• Business Transfers: In connection with mergers or acquisitions\n'
                            '• With Your Consent: When you explicitly authorize sharing',
                      ),
                      _buildTermsSection(
                        'Data Security',
                        'We implement industry-standard security measures including:\n'
                            '• Encryption of data in transit and at rest\n'
                            '• Regular security audits and updates\n'
                            '• Access controls and authentication\n'
                            '• Secure data centers with backup systems\n\n'
                            'However, no method of transmission over the internet is 100% secure.',
                      ),
                      _buildTermsSection(
                        'Data Retention',
                        'We retain your information for as long as your account is active or as needed to provide services. Location data is retained for up to 12 months unless you request deletion earlier.',
                      ),
                      _buildTermsSection(
                        'Your Rights',
                        'You have the right to:\n'
                            '• Access your personal data\n'
                            '• Correct inaccurate information\n'
                            '• Request deletion of your data\n'
                            '• Export your data\n'
                            '• Opt-out of marketing communications\n'
                            '• Withdraw consent at any time',
                      ),
                      _buildTermsSection(
                        'Location Tracking',
                        'Our app requires location permissions to function. You can control location sharing through your device settings. Disabling location services will limit app functionality.',
                      ),
                      _buildTermsSection(
                        'Children\'s Privacy',
                        'Our service is not intended for children under 13. We do not knowingly collect information from children. If we discover such data, we will delete it promptly.',
                      ),
                      _buildTermsSection(
                        'International Data Transfers',
                        'Your data may be transferred to and processed in countries other than your own. We ensure appropriate safeguards are in place for such transfers.',
                      ),
                      _buildTermsSection(
                        'Cookies and Tracking',
                        'We use cookies and similar technologies to enhance user experience, analyze usage patterns, and improve our services. You can control cookie preferences through your browser settings.',
                      ),
                      _buildTermsSection(
                        'Changes to Privacy Policy',
                        'We may update this policy periodically. We will notify you of significant changes via email or app notification. Continued use after changes indicates acceptance.',
                      ),
                      _buildTermsSection(
                        'Contact Us',
                        'For privacy concerns or to exercise your rights:\n\n'
                            'Email: privacy@onfleetgps.com\n'
                            'Website: https://onfleetgps.com/privacy-policy/\n'
                            'Phone: +880-1912609087\n'
                            'Address: [Your Company Address]',
                      ),
                      _buildTermsSection(
                        'GDPR & Compliance',
                        'For EU residents: We comply with GDPR requirements. You have additional rights under GDPR including data portability and the right to lodge complaints with supervisory authorities.',
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          'Last Updated: ${DateTime.now().year}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to build policy sections
  Widget _buildTermsSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: CustomColor.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
}

class AboutPageArguments {
  final String title;
  final String url;
  AboutPageArguments(this.title, this.url);
}