import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:get/get.dart';
import 'package:smart_lock/screens/DeviceSettingPage.dart';
import 'package:smart_lock/screens/SelectDevicePage.dart';
import 'package:smart_lock/screens/payment_list.dart';
import 'package:smart_lock/storage/user_repository.dart';
import 'package:smart_lock/config.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../translation/lang/bn_BD.dart';
import '../translation/lang/en_US.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<StatefulWidget> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  File? _image;
  final ImagePicker _picker = ImagePicker();
  bool isLoading = true;

  SharedPreferences get _prefs => UserRepository.prefs!;

  @override
  void initState() {
    super.initState();
    _loadImageFromPrefs();
    getUser();
  }

  Future<void> getUser() async {
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _loadImageFromPrefs() async {
    final String? imagePath = _prefs.getString('profile_image_path');
    if (imagePath != null && imagePath.isNotEmpty) {
      if (mounted) setState(() => _image = File(imagePath));
    }
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile =
        await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      if (mounted) setState(() => _image = File(pickedFile.path));
      await _prefs.setString('profile_image_path', pickedFile.path);
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'goodMorning'.tr;
    if (hour < 17) return 'goodAfternoon'.tr;
    return 'goodNight'.tr;
  }

  Future<void> logout() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      await _prefs.remove('profile_image_path');
      await _prefs.clear();
      DataController.clearAllOverridesInMemory();

      if (_image != null && await _image!.exists()) {
        try {
          await _image!.delete();
        } catch (_) {}
      }
      Get.deleteAll(force: true);
      if (mounted) Navigator.pop(context);
      Phoenix.rebirth(context);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Logout failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Support launchers ────────────────────────────────────────────────────

  Future<void> _launchPhone(String number) async {
    if (number.isEmpty) {
      _showNoDataSnack('Phone number not available');
      return;
    }
    final Uri uri = Uri.parse('tel:$number');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showNoDataSnack('Phone call not supported on this device');
      }
    } catch (e) {
      debugPrint('Phone launch error: $e');
    }
  }

  /// Sanitizes a raw stored identifier, extracting only the leading phone
  /// number or email address.  Guards against corrupted SharedPreferences
  /// values that may contain a trailing device-list suffix such as
  /// `01805469656) - Bike (IMEI: N/A, SIM: ...)` caused by stale cached data.
  String _sanitizeIdentifier(String raw) {
    if (raw.isEmpty) return raw;

    // Step 1 – strip everything after a stray closing parenthesis
    // e.g. "01805469656) - Bike …"  →  "01805469656"
    final parenIdx = raw.indexOf(')');
    if (parenIdx != -1) {
      final candidate = raw.substring(0, parenIdx).trim();
      if (candidate.isNotEmpty) return candidate;
    }

    // Step 2 – strip everything after " - " separator
    // e.g. "user - Bike (IMEI: N/A)"  →  "user"
    final dashIdx = raw.indexOf(' - ');
    if (dashIdx != -1) {
      final candidate = raw.substring(0, dashIdx).trim();
      if (candidate.isNotEmpty) return candidate;
    }

    // Step 3 – if it looks like an email, keep only the local part
    if (raw.contains('@')) {
      return raw.split('@').first.trim();
    }

    return raw.trim();
  }

  String _getSupportMessage() {
    final String raw = UserRepository.getEmail() ?? '';
    final String cleanIdentifier =
        raw.isNotEmpty ? _sanitizeIdentifier(raw) : 'Unknown Account';

    final StringBuffer buffer = StringBuffer();
    buffer.writeln("Hello Smart Lock Support,");
    buffer.writeln("");
    buffer.writeln("I need assistance with my account:");
    buffer.writeln("User Account: $cleanIdentifier");

    // Add device info if available
    try {
      if (Get.isRegistered<DataController>()) {
        final controller = Get.find<DataController>();
        if (controller.onlyDevices.isNotEmpty) {
          buffer.writeln("");
          buffer.writeln("My Registered Devices:");
          for (var device in controller.onlyDevices) {
            final name = device.name ?? 'Unknown Device';
            final imei = device.imei ?? 'N/A';
            final simNo = device.deviceData?.simNumber ?? 'N/A';
            buffer.writeln("- $name (IMEI: $imei, SIM: $simNo)");
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching device info for helpline: $e");
    }

    return buffer.toString().trim();
  }

  Future<void> _launchWhatsApp(String number) async {
    if (number.isEmpty) {
      _showNoDataSnack('WhatsApp number not available');
      return;
    }
    final String clean = number.replaceAll(RegExp(r'[^0-9]'), '');
    final String message = _getSupportMessage();

    final Uri uri =
        Uri.parse('https://wa.me/$clean?text=${Uri.encodeComponent(message)}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showNoDataSnack('WhatsApp not installed');
      }
    } catch (e) {
      debugPrint('WhatsApp launch error: $e');
    }
  }

  Future<void> _launchEmail(String email) async {
    if (email.isEmpty) {
      _showNoDataSnack('Email address not available');
      return;
    }
    final String message = _getSupportMessage();
    final String subject = Uri.encodeComponent("Support Request: Smart Lock");
    final String body = Uri.encodeComponent(message);

    final Uri uri = Uri.parse('mailto:$email?subject=$subject&body=$body');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showNoDataSnack('Email app not found');
      }
    } catch (e) {
      debugPrint('Email launch error: $e');
    }
  }

  void _showNoDataSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.orange),
    );
  }

  // ─── Contact Us bottom sheet ──────────────────────────────────────────────

  void _showContactUsSheet() {
    // Read live values from the global config populated by Firebase
    final String phone = PHONE_NO;
    final String whatsapp = WHATS_APP;
    final String email = EMAIL;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle bar ──
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // ── Header ──
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.headset_mic_rounded,
                    color: Color(0xFF1D4888),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contact Us',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'We\'re here to help you',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 28),

            // ── Phone ──
            _contactTile(
              icon: Icons.phone_rounded,
              iconBg: const Color(0xFFE8F5E9),
              iconColor: const Color(0xFF43A047),
              title: 'Call Us',
              subtitle: phone.isNotEmpty ? phone : 'Not available',
              onTap: phone.isNotEmpty ? () => _launchPhone(phone) : null,
            ),

            const SizedBox(height: 12),

            // ── WhatsApp ──
            _contactTile(
              icon: Icons.chat_rounded,
              iconBg: const Color(0xFFE8F5E9),
              iconColor: const Color(0xFF25D366),
              title: 'WhatsApp',
              subtitle: whatsapp.isNotEmpty ? whatsapp : 'Not available',
              onTap:
                  whatsapp.isNotEmpty ? () => _launchWhatsApp(whatsapp) : null,
            ),

            const SizedBox(height: 12),

            // ── Email ──
            _contactTile(
              icon: Icons.email_rounded,
              iconBg: const Color(0xFFE3F2FD),
              iconColor: const Color(0xFF1E88E5),
              title: 'Email Us',
              subtitle: email.isNotEmpty ? email : 'Not available',
              onTap: email.isNotEmpty ? () => _launchEmail(email) : null,
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _contactTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: onTap != null ? Colors.white : Colors.grey[50],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: onTap != null
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          onTap != null ? const Color(0xFF1D4888) : Colors.grey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEEEEE),
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
                  _buildProfileCard(),
                  const SizedBox(height: 10),
                  _buildGridSection(),
                  const SizedBox(height: 10),
                  _buildSeparateListItem(
                    imagePath: 'assets/images/device_setting.png',
                    fallbackIcon: Icons.settings,
                    label: 'deviceControl'.tr,
                    onTap: () => Get.to(() => DeviceSettingPage()),
                  ),
                  const SizedBox(height: 8),
                  _buildSeparateListItem(
                    imagePath: 'assets/images/payment.png',
                    fallbackIcon: Icons.monetization_on,
                    label: 'payment'.tr,
                    onTap: () => Get.to(() => PaymentListScreen()),
                  ),
                  const SizedBox(height: 8),
                  _buildSeparateListItem(
                    imagePath: 'assets/images/notification.png',
                    fallbackIcon: Icons.notifications,
                    label: 'notificationSetting'.tr,
                    onTap: () => Navigator.pushNamed(context, '/alertList'),
                  ),
                  const SizedBox(height: 8),
                  _buildSeparateListItem(
                    imagePath: 'assets/images/language.png',
                    fallbackIcon: Icons.language,
                    label: 'changeLanguage'.tr,
                    onTap: () => _showLanguageDialog(context),
                  ),
                  const SizedBox(height: 8),
                  _buildSeparateListItem(
                    imagePath: 'assets/images/password.png',
                    fallbackIcon: Icons.lock,
                    label: 'changePassword'.tr,
                    onTap: () => _showChangePasswordDialog(),
                  ),
                  const SizedBox(height: 8),
                  _buildSeparateListItem(
                    imagePath: 'assets/images/privacy.png',
                    fallbackIcon: Icons.shield,
                    label: 'privacyPolicy'.tr,
                    onTap: () => _showPrivacyPolicy(),
                  ),
                  const SizedBox(height: 8),
                  _buildSeparateListItem(
                    imagePath: 'assets/images/privacy.png',
                    fallbackIcon: Icons.shield_outlined,
                    label: 'termsAndCondition'.tr,
                    onTap: () => _showTermsAndConditions(),
                  ),
                  const SizedBox(height: 8),
                  _buildSeparateListItem(
                    imagePath: 'assets/images/logout.png',
                    fallbackIcon: Icons.logout,
                    label: 'logout'.tr,
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

  // ─── Profile card ─────────────────────────────────────────────────────────

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
                color: Color(0xFFFFE0E0),
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
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 2×2 grid ─────────────────────────────────────────────────────────────

  Widget _buildGridSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildGridCard(
                imagePath: 'assets/images/geofence.png',
                fallbackIcon: Icons.fence,
                fallbackColor: const Color(0xFFE53935),
                label: 'GeoFences',
                onTap: () => Navigator.pushNamed(context, '/geofenceList'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildGridCard(
                imagePath: 'assets/images/alert.png',
                fallbackIcon: Icons.notifications_active,
                fallbackColor: const Color(0xFFFFC107),
                label: 'Alert',
                onTap: () => Navigator.pushNamed(context, '/alertList'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildGridCard(
                imagePath: 'assets/images/report.png',
                fallbackIcon: Icons.bar_chart,
                fallbackColor: const Color(0xFF42A5F5),
                label: 'Report',
                onTap: () => Get.to(() => SelectDevicePage()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildGridCard(
                imagePath: 'assets/images/contact.png',
                fallbackIcon: Icons.headset_mic,
                fallbackColor: const Color(0xFF9575CD),
                label: 'Contact Us',
                // ← now opens the contact bottom sheet
                onTap: () => _showContactUsSheet(),
              ),
            ),
          ],
        ),
      ],
    );
  }

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
                errorBuilder: (_, __, ___) =>
                    Icon(fallbackIcon, color: fallbackColor, size: 50),
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

  // ─── Dialogs ──────────────────────────────────────────────────────────────

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
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    final TextEditingController currentPassController = TextEditingController();
    final TextEditingController passController = TextEditingController();
    final TextEditingController confirmController = TextEditingController();
    bool obscureCurrent = true;
    bool obscure1 = true;
    bool obscure2 = true;
    bool isChangingPassword = false;

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
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _buildPasswordField(
                  controller: currentPassController,
                  label: 'Current Password',
                  obscure: obscureCurrent,
                  onToggle: () =>
                      setSheetState(() => obscureCurrent = !obscureCurrent),
                ),
                const SizedBox(height: 16),
                _buildPasswordField(
                  controller: passController,
                  label: 'New Password',
                  obscure: obscure1,
                  onToggle: () => setSheetState(() => obscure1 = !obscure1),
                ),
                const SizedBox(height: 16),
                _buildPasswordField(
                  controller: confirmController,
                  label: 'Confirm New Password',
                  obscure: obscure2,
                  onToggle: () => setSheetState(() => obscure2 = !obscure2),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Cancel',
                            style: TextStyle(
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: isChangingPassword
                            ? null
                            : () async {
                                if (currentPassController.text.isEmpty ||
                                    passController.text.isEmpty ||
                                    confirmController.text.isEmpty) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                    content: Text('Please fill all fields'),
                                    backgroundColor: Colors.orange,
                                  ));
                                  return;
                                }
                                if (passController.text.length < 6) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                    content: Text(
                                        'Password must be at least 6 characters'),
                                    backgroundColor: Colors.orange,
                                  ));
                                  return;
                                }
                                if (passController.text !=
                                    confirmController.text) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                    content: Text('Passwords do not match'),
                                    backgroundColor: Colors.red,
                                  ));
                                  return;
                                }
                                setSheetState(() => isChangingPassword = true);
                                try {
                                  await APIService.changePassword(
                                      passController.text);
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: const Row(children: [
                                        Icon(Icons.check_circle,
                                            color: Colors.white, size: 18),
                                        SizedBox(width: 8),
                                        Text('Password updated successfully'),
                                      ]),
                                      backgroundColor: Colors.green,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ));
                                  }
                                } catch (e) {
                                  setSheetState(
                                      () => isChangingPassword = false);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: Colors.red,
                                      behavior: SnackBarBehavior.floating,
                                    ));
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          disabledBackgroundColor:
                              const Color(0xFFE53935).withValues(alpha: 0.6),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: isChangingPassword
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
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
              width: 40,
              height: 4,
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
              flag: '🇺🇸',
              language: 'English',
              isSelected: Get.locale?.languageCode == 'en',
              onTap: () async {
                Get.updateLocale(const Locale('en'));
                await _prefs.setString('language_code', 'en');
                await _prefs.setString('language', 'en');
                if (context.mounted) Navigator.pop(context);
              },
            ),
            const SizedBox(height: 10),
            _buildLanguageOption(
              flag: '🇧🇩',
              language: 'বাংলা',
              isSelected: Get.locale?.languageCode == 'bn',
              onTap: () async {
                Get.updateLocale(const Locale('bn'));
                await _prefs.setString('language_code', 'bn');
                await _prefs.setString('language', 'bn');
                if (context.mounted) Navigator.pop(context);
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
              child: Text(
                language,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color:
                      isSelected ? const Color(0xFF3E6FB8) : Colors.grey[800],
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  color: Color(0xFF3E6FB8), size: 22),
          ],
        ),
      ),
    );
  }

  void _showTermsAndConditions() {
    final t = Get.locale?.languageCode == 'bn' ? bn_BD : en_US;
    _showPolicyBottomSheet(
      title: t['termsTitle']!,
      icon: Icons.description_outlined,
      sections: [
        _PolicySection(t['termsAcceptance']!, t['termsAcceptanceDetail']!,
            Icons.check_circle_outline),
        _PolicySection(
            t['termsService']!, t['termsServiceDetail']!, Icons.gps_fixed),
        _PolicySection(
            t['termsUser']!, t['termsUserDetail']!, Icons.person_outline),
        _PolicySection(t['termsPayment']!, t['termsPaymentDetail']!,
            Icons.payment_outlined),
        _PolicySection(t['termsTermination']!, t['termsTerminationDetail']!,
            Icons.block_outlined),
        _PolicySection(
          t['contactInfo']!,
          'Email: $EMAIL\nPhone: $PHONE_NO',
          Icons.contact_support_outlined,
        ),
      ],
    );
  }

  void _showPrivacyPolicy() {
    final t = Get.locale?.languageCode == 'bn' ? bn_BD : en_US;
    _showPolicyBottomSheet(
      title: t['privacyPolicyTitle']!,
      icon: Icons.privacy_tip_outlined,
      sections: [
        _PolicySection(t['policyInfoWeCollect']!, t['policyInfoCollectDetail']!,
            Icons.info_outline),
        _PolicySection(t['policyHowWeUse']!, t['policyHowWeUseDetail']!,
            Icons.settings_outlined),
        _PolicySection(t['policyDataSecurity']!, t['policyDataSecurityDetail']!,
            Icons.lock_outline),
        _PolicySection(t['policyYourRights']!, t['policyYourRightsDetail']!,
            Icons.verified_user_outlined),
        _PolicySection(
          t['contactInfo']!,
          'Email: $EMAIL\nPhone: $PHONE_NO',
          Icons.contact_support_outlined,
        ),
      ],
    );
  }

  void _showPolicyBottomSheet({
    required String title,
    required IconData icon,
    required List<_PolicySection> sections,
  }) {
    final t = Get.locale?.languageCode == 'bn' ? bn_BD : en_US;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // ── Handle + header ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 16, 0),
                child: Column(
                  children: [
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
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F0FB),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icon,
                              color: const Color(0xFF1D4888), size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t['lastUpdated']!,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                  ],
                ),
              ),

              // ── Scrollable content ───────────────────────────────────
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  itemCount: sections.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final s = sections[index];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F0FB),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(s.icon,
                                color: const Color(0xFF1D4888), size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.title,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  s.body,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.6,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Add this class above SettingsPage ────────────────────────────────────

class _PolicySection {
  final String title;
  final String body;
  final IconData icon;
  const _PolicySection(this.title, this.body, this.icon);
}

// ── Add this method inside _SettingsPageState ─────────────────────────────

class AboutPageArguments {
  final String title;
  final String url;

  AboutPageArguments(this.title, this.url);
}
