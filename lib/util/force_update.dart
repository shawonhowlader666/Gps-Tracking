import 'package:flutter/material.dart';
import 'package:gpspro/config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class VersionUtils {
  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      // Get current app version
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;

      if (_isNewVersion(currentVersion, APP_VERSION)) {
        // Close all routes and navigate to update screen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const UpdateScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      print("Version check failed: $e");
    }
  }

  static bool _isNewVersion(String current, String server) {
    try {
      List<int> c = current.split('.').map(int.parse).toList();
      List<int> s = server.split('.').map(int.parse).toList();

      while (c.length < s.length) c.add(0);
      while (s.length < c.length) s.add(0);

      for (int i = 0; i < c.length; i++) {
        if (s[i] > c[i]) return true;
        if (s[i] < c[i]) return false;
      }
    } catch (e) {
      print('Version comparison failed: $e');
    }
    return false;
  }
}

class UpdateScreen extends StatelessWidget {
  const UpdateScreen({Key? key}) : super(key: key);

  void _launchStore() async {
    const url =
        'https://play.google.com/store/apps/details?id=com.sptrackgps.mobileapp';
    if (!await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.system_update, size: 100, color: Colors.blue),
                const SizedBox(height: 20),
                const Text(
                  'Update Available!',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'A new version of the app is available.\nPlease update to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: _launchStore,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Text('Update Now', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
