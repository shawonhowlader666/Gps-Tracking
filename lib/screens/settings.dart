import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:get/get.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/widgets/alert_dialog_custom.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
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

  getUser() async {
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

  logout() {
    UserRepository.doLogout();
    Phoenix.rebirth(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 8, // Increased elevation for more spreaded light
        shadowColor: Colors.black.withOpacity(0.2), // Added shadow color
        toolbarHeight: 80.0, // Increased appbar height
        titleSpacing: 20.0, // Added space from top for the title
        title: Text(
          "Settings",
          style: TextStyle(
            color: Colors.orange,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: !isLoading
          ? Column(
              children: [
                // Profile section
                SizedBox(
                  height: 20,
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundImage: _image != null
                                ? FileImage(_image!) as ImageProvider
                                : AssetImage("assets/images/user.png"),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _pickImage,
                              child: CircleAvatar(
                                radius: 10,
                                backgroundColor: Colors.white,
                                child: Icon(Icons.edit,
                                    size: 14, color: Colors.orange),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserRepository.getName() ?? "SpyTrack User",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            UserRepository.getEmail() ?? "harun@gmail.com",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(height: 24, thickness: 1),

                // Settings list
                Expanded(child: settingsList()),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget settingsList() {
    return ListView(
      children: [
        buildSettingTile(
          icon: Icons.notifications_none,
          title: "Alerts",
          subtitle: "Manage App Notifications And Reminders.",
          onTap: () => Navigator.pushNamed(context, "/alertList"),
        ),
        buildSettingTile(
          icon: Icons.fence,
          title: "Geofence",
          subtitle: "Set And Control Your Vehicle's Location Zones.",
          onTap: () => Navigator.pushNamed(context, "/geofenceList"),
        ),
        buildSettingTile(
          icon: Icons.language,
          title: "Language",
          subtitle: "Select Your Preferred App Language.",
          onTap: () => _showLanguageDialog(context),
        ),
        buildSettingTile(
          icon: Icons.payment,
          title: "Payment",
          subtitle: "View Invoices, Subscriptions & Make Payments.",
          onTap: () {},
        ),
        buildSettingTile(
          icon: Icons.add_circle_outline,
          title: "Add Vehicles",
          subtitle: "Register New Vehicles To Your Account.",
          onTap: () {},
        ),
        buildSettingTile(
          icon: Icons.description_outlined,
          title: "Terms & Conditions",
          subtitle: "Read The User Terms And App Policies.",
          onTap: () async => await launchUrl(Uri.parse("TERMS_AND_CONDITIONS")),
        ),
        buildSettingTile(
          icon: Icons.privacy_tip_outlined,
          title: "Privacy Policy",
          subtitle: "See How Your Data Is Collected And Used.",
          onTap: () async => await launchUrl(Uri.parse("PRIVACY_POLICY")),
        ),
        buildSettingTile(
          icon: Icons.logout,
          title: "Logout",
          subtitle: "",
          isLogout: true,
          onTap: logout,
        ),
      ],
    );
  }

  Widget buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLogout = false,
  }) {
    return ListTile(
      leading: CircleAvatar(
        radius: 23,
        backgroundColor: Colors.orange.withOpacity(0.08),
        child: Icon(
          icon,
          size: 19,
          color: isLogout ? Colors.red : const Color.fromARGB(205, 175, 76, 1),
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
            fontWeight: FontWeight.w400,
            color: isLogout ? Colors.red : Colors.black,
            fontSize: 17),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            )
          : null,
      trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
      onTap: onTap,
    );
  }

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Select Language",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange)),
              const Divider(),
              ListTile(
                leading: Icon(Icons.language),
                title: Text("English"),
                onTap: () async {
                  Get.updateLocale(const Locale('en'));
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('language_code', 'en');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.language),
                title: Text("Bangla"),
                onTap: () async {
                  Get.updateLocale(const Locale('bn'));
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('language_code', 'bn');
                  Navigator.pop(context);
                },
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
