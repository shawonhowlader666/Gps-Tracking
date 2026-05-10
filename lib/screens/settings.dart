import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:get/get.dart';
import 'package:smart_lock/constants/app_constants.dart';
import 'package:smart_lock/screens/DeviceSettingPage.dart';
import 'package:smart_lock/screens/SelectDevicePage.dart';
import 'package:smart_lock/screens/payment_list.dart';
import 'package:smart_lock/storage/user_repository.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

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
    setState(() => isLoading = false);
  }

  Future<void> _loadImageFromPrefs() async {
    prefs = await SharedPreferences.getInstance();
    final String? imagePath = prefs?.getString('profile_image_path');
    if (imagePath != null && imagePath.isNotEmpty) {
      setState(() => _image = File(imagePath));
    }
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile =
    await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _image = File(pickedFile.path));
      await prefs?.setString('profile_image_path', pickedFile.path);
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Night';
  }

  Future<void> logout() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      if (prefs != null) {
        await prefs!.remove('profile_image_path');
        await prefs!.clear();
      }
      if (_image != null && await _image!.exists()) {
        try { await _image!.delete(); } catch (_) {}
      }
      Get.deleteAll(force: true);
      if (mounted) Navigator.pop(context);
      Phoenix.rebirth(context);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEEEEE), // light grey background like image
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text(
          'Setting',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ),
      body: !isLoading
          ? SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            // ── Profile Card ──
            _buildProfileCard(),
            const SizedBox(height: 10),

            // ── 2x2 Grid ──
            _buildGridSection(),
            const SizedBox(height: 10),

            // ── List Items (each in its own white card) ──
            _buildSeparateListItem(
              imagePath: 'assets/images/device_setting.png',
              fallbackIcon: Icons.settings,
              label: 'Device Setting',
              onTap: () {
                Get.to(() => DeviceSettingPage());
              },
            ),
            const SizedBox(height: 8),
            _buildSeparateListItem(
              imagePath: 'assets/images/payment.png',
              fallbackIcon: Icons.monetization_on,
              label: 'Payment',
              onTap: () {
                Get.to(() => PaymentListScreen());
              },
            ),
            const SizedBox(height: 8),
            _buildSeparateListItem(
              imagePath: 'assets/images/notification.png',
              fallbackIcon: Icons.notifications,
              label: 'Notification Setting',
              onTap: () => Navigator.pushNamed(context, "/alertList"),
            ),
            const SizedBox(height: 8),
            _buildSeparateListItem(
              imagePath: 'assets/images/language.png',
              fallbackIcon: Icons.language,
              label: 'Change Language',
              onTap: () => _showLanguageDialog(context),
            ),
            const SizedBox(height: 8),
            _buildSeparateListItem(
              imagePath: 'assets/images/password.png',
              fallbackIcon: Icons.lock,
              label: 'Change Password',
              onTap: () => _showChangePasswordDialog(), // ← Connect it
            ),
            const SizedBox(height: 8),
            _buildSeparateListItem(
              imagePath: 'assets/images/privacy.png',
              fallbackIcon: Icons.shield,
              label: 'Privacy Policy',
              onTap: () => _showPrivacyPolicy(),
            ),
            const SizedBox(height: 8),
            _buildSeparateListItem(
              imagePath: 'assets/images/privacy.png',
              fallbackIcon: Icons.shield_outlined,
              label: 'Terms of Use',
              onTap: () => _showTermsAndConditions(),
            ),
            const SizedBox(height: 8),
            _buildSeparateListItem(
              imagePath: 'assets/images/logout.png',
              fallbackIcon: Icons.logout,
              label: 'Logout',
              onTap: () => _showLogoutDialog(),
            ),
            const SizedBox(height: 20),
            Text(
              'Version 1.0.9+11',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
            const SizedBox(height: 20),
          ],
        ),
      )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  // ── Profile Card: pink circle avatar + greeting + email ──
  Widget _buildProfileCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFFFE0E0), // pink circle bg like image
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: _image != null
                    ? Image.file(_image!, fit: BoxFit.cover)
                    : const Icon(
                  Icons.directions_car,
                  color: Color(0xFFE53935),
                  size: 36,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getGreeting(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                UserRepository.getEmail() ?? 'user@example.com',
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 2x2 Grid: GeoFences | Alert / Report | Contact Us ──
  Widget _buildGridSection() {
    return Column(
      children: [
        // Row 1
        Row(
          children: [
            Expanded(
              child: _buildGridCard(
                imagePath: 'assets/images/geofence.png',
                fallbackIcon: Icons.fence,
                fallbackColor: const Color(0xFFE53935),
                label: 'GeoFences',
                onTap: () => Navigator.pushNamed(context, "/geofenceList"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildGridCard(
                imagePath: 'assets/images/alert.png',
                fallbackIcon: Icons.notifications_active,
                fallbackColor: const Color(0xFFFFC107),
                label: 'Alert',
                onTap: () => Navigator.pushNamed(context, "/alertList"),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Row 2
        Row(
          children: [
            Expanded(
              child: _buildGridCard(
                imagePath: 'assets/images/report.png',
                fallbackIcon: Icons.bar_chart,
                fallbackColor: const Color(0xFF42A5F5),
                label: 'Report',
                onTap: () {
                  Get.to(() => SelectDevicePage());
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildGridCard(
                imagePath: 'assets/images/contact.png',
                fallbackIcon: Icons.headset_mic,
                fallbackColor: const Color(0xFF9575CD),
                label: 'Contact Us',
                onTap: () {},
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Single Grid Card ──
  Widget _buildGridCard({
    required String imagePath,
    required IconData fallbackIcon,
    required Color fallbackColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: Image.asset(
                imagePath,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  fallbackIcon,
                  color: fallbackColor,
                  size: 50,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Each list item in its OWN separate white card (like image) ──
  Widget _buildSeparateListItem({
    required String imagePath,
    required IconData fallbackIcon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Image.asset(
                imagePath,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  fallbackIcon,
                  size: 28,
                  color: Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dialogs ──

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
            onPressed: () { Navigator.pop(context); logout(); },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  void _showChangePasswordDialog() {
    final TextEditingController passController = TextEditingController();
    final TextEditingController confirmController = TextEditingController();
    final TextEditingController currentPassController = TextEditingController();
    bool obscureCurrent = true;
    bool obscure1 = true;
    bool obscure2 = true;
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Handle Bar ──
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Header ──
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE0E0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        color: Color(0xFFE53935),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Change Password',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Keep your account secure',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Current Password ──
                _buildPasswordField(
                  controller: currentPassController,
                  label: 'Current Password',
                  obscure: obscureCurrent,
                  onToggle: () =>
                      setSheetState(() => obscureCurrent = !obscureCurrent),
                ),
                const SizedBox(height: 16),

                // ── New Password ──
                _buildPasswordField(
                  controller: passController,
                  label: 'New Password',
                  obscure: obscure1,
                  onToggle: () =>
                      setSheetState(() => obscure1 = !obscure1),
                ),
                const SizedBox(height: 16),

                // ── Confirm Password ──
                _buildPasswordField(
                  controller: confirmController,
                  label: 'Confirm New Password',
                  obscure: obscure2,
                  onToggle: () =>
                      setSheetState(() => obscure2 = !obscure2),
                ),
                const SizedBox(height: 28),

                // ── Buttons ──
                Row(
                  children: [
                    // Cancel
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Update
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: isLoading
                            ? null
                            : () async {
                          // Validation
                          if (currentPassController.text.isEmpty ||
                              passController.text.isEmpty ||
                              confirmController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please fill all fields'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          if (passController.text.length < 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Password must be at least 6 characters'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          if (passController.text !=
                              confirmController.text) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Passwords do not match'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          setSheetState(() => isLoading = true);

                          try {
                            final response =
                            await APIService.changePassword(
                                passController.text);
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: const [
                                    Icon(Icons.check_circle,
                                        color: Colors.white, size: 18),
                                    SizedBox(width: 8),
                                    Text('Password updated successfully'),
                                  ],
                                ),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            );
                          } catch (e) {
                            setSheetState(() => isLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          disabledBackgroundColor:
                          const Color(0xFFE53935).withValues(alpha: 0.6),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                            : const Text(
                          'Update Password',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

// ── Reusable password field ──
  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.grey[500],
            size: 20,
          ),
          onPressed: onToggle,
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Select Language',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _buildLanguageOption(
              flag: '🇺🇸', language: 'English',
              isSelected: Get.locale?.languageCode == 'en',
              onTap: () async {
                Get.updateLocale(const Locale('en'));
                final p = await SharedPreferences.getInstance();
                await p.setString('language_code', 'en');
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 10),
            _buildLanguageOption(
              flag: '🇧🇩', language: 'বাংলা',
              isSelected: Get.locale?.languageCode == 'bn',
              onTap: () async {
                Get.updateLocale(const Locale('bn'));
                final p = await SharedPreferences.getInstance();
                await p.setString('language_code', 'bn');
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
              ? const Color(0xFF3E6FB8).withValues(alpha: 0.1)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF3E6FB8) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(language,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? const Color(0xFF3E6FB8) : Colors.grey[800],
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFF3E6FB8), size: 22),
          ],
        ),
      ),
    );
  }

  void _showTermsAndConditions() {
    _showPolicyDialog(
      title: 'Terms & Conditions',
      icon: Icons.description,
      content: '''1. Acceptance of Terms
By using ${AppConstants.appName}, you agree to these Terms and Conditions.

2. Service Description
${AppConstants.appName} provides real-time GPS tracking for vehicles.

3. User Responsibilities
- Must be 18+ years old
- Responsible for account security
- Only track authorized vehicles
- Comply with all applicable laws

4. Payment Terms
Subscription fees are non-refundable except as required by law.

5. Termination
We may suspend accounts violating these terms.

6. Contact
Email: asthahelpbd@gmail.com
Phone: +880-1912609087''',
    );
  }

  void _showPrivacyPolicy() {
    _showPolicyDialog(
      title: 'Privacy Policy',
      icon: Icons.privacy_tip,
      content: '''1. Information We Collect
- Name, email, phone number
- Real-time GPS coordinates
- Historical location data
- Device identifiers

2. How We Use Your Information
- Provide GPS tracking services
- Process payments
- Send alerts and notifications
- Improve our services

3. Data Security
We use encryption and industry-standard security measures.

4. Your Rights
- Access your data
- Request data deletion
- Opt-out of marketing

5. Contact
Email: privacy@spytrack.com
Phone: +880-1912609087''',
    );
  }

  void _showPolicyDialog({
    required String title,
    required IconData icon,
    required String content,
  }) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 560),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF3E6FB8), Color(0xFF5C8ACF)],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title,
                        style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white,
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
                  child: Text(
                    content,
                    style: TextStyle(fontSize: 13, height: 1.6, color: Colors.grey[800]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AboutPageArguments {
  final String title;
  final String url;
  AboutPageArguments(this.title, this.url);
}