import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:smart_lock/config.dart';
import 'package:smart_lock/screens/server_maintenance_screen.dart';
import 'package:smart_lock/services/model/login.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/storage/user_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreenPage extends StatefulWidget {
  const SplashScreenPage({super.key});

  @override
  State<StatefulWidget> createState() => _SplashScreenPageState();
}

class _SplashScreenPageState extends State<SplashScreenPage>
    with TickerProviderStateMixin {
  // ─── Timing ──────────────────────────────────────────────────────────────
  static const Duration _minimumSplashDuration = Duration(seconds: 2);
  static const Duration _initialDelay = Duration(milliseconds: 400);

  // Cache TTL: re-fetch Firestore config only after 10 seconds to ensure Maintenance Mode and Force Update take effect promptly
  static const int _configCacheTtlMs = 10 * 1000;

  // ─── State ────────────────────────────────────────────────────────────────
  bool _configLoaded = false;
  bool _minimumTimeReached = false;
  bool _showCheckmark = false;
  bool _isSystemBlockActive = false;

  // ─── Animation controllers ────────────────────────────────────────────────
  late AnimationController _logoController;
  late AnimationController _checkController;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _checkScale;
  late Animation<double> _checkFade;

  static const Color _primaryColor = Color(0xFF1D4888);

  // ─── Prefs (reuse the instance already created in main) ───────────────────
  SharedPreferences get _prefs => UserRepository.prefs!;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _requestPermissions();

    // Start config fetch and minimum timer in parallel
    Future.delayed(_initialDelay, fetchConfigAndProceed);

    Future.delayed(_minimumSplashDuration, () {
      if (!mounted) return;
      _minimumTimeReached = true;
      _tryNavigate();
    });
  }

  // ─── Animations ───────────────────────────────────────────────────────────
  void _initAnimations() {
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOut),
    );

    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _checkController, curve: Curves.elasticOut),
    );
    _checkFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _checkController, curve: Curves.easeOut),
    );

    _logoController.forward();
  }

  void _requestPermissions() {
    Permission.location.request();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _checkController.dispose();
    super.dispose();
  }

  // ─── Navigation gate ──────────────────────────────────────────────────────
  void _tryNavigate() {
    if (!mounted) return;
    if (_isSystemBlockActive) return;
    if (_configLoaded && _minimumTimeReached) {
      setState(() => _showCheckmark = true);
      _checkController.forward();
      Future.delayed(const Duration(milliseconds: 800), checkPreference);
    }
  }

  // ─── Config fetch with caching ────────────────────────────────────────────
  Future<void> fetchConfigAndProceed() async {
    try {
      await _fetchFromFirestore();
    } catch (e) {
      debugPrint('Config fetch error: $e');
    } finally {
      if (mounted) {
        _configLoaded = true;
        _tryNavigate();
      }
    }
  }

  Future<void> _fetchFromFirestore() async {
    final String serverType = _prefs.getString('serverType') ?? 'free';
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final String packageName = packageInfo.packageName;

    // 1. Try package-specific configuration document
    final doc = await FirebaseFirestore.instance
        .collection('configs')
        .doc(packageName)
        .get();

    if (doc.exists && doc.data() != null) {
      final data = doc.data() as Map<String, dynamic>;
      
      APP_NAME = data['app_name'] as String? ?? APP_NAME;
      APP_VERSION = data['version'] as String? ?? '1.0.0';
      
      final support = data['support'] as Map<String, dynamic>? ?? {};
      WHATS_APP = support['whatsapp'] as String? ?? '';
      PHONE_NO = support['phone'] as String? ?? '';
      EMAIL = support['email'] as String? ?? '';
      
      final settings = data['settings'] as Map<String, dynamic>? ?? {};
      SHOW_ADS = (settings['show_ads'] as bool? ?? false) && serverType == 'free';
      adsFrequency = settings['ads_frequency'] as int? ?? 30;
      
      if (data['servers'] != null) {
        SERVER_URL = data['servers'] as List;
      }
      
      final policies = data['policies'] as Map<String, dynamic>? ?? {};
      TERMS_AND_CONDITIONS = policies['terms'] as String? ?? TERMS_AND_CONDITIONS;
      PRIVACY_POLICY = policies['privacy'] as String? ?? PRIVACY_POLICY;

      // Custom payment numbers
      final payment = data['payment'] as Map<String, dynamic>? ?? {};
      bkashNumber = payment['bkash'] as String? ?? '';
      nagadNumber = payment['nagad'] as String? ?? '';
      rocketNumber = payment['rocket'] as String? ?? '';

      // System controls
      final maintenance = data['maintenance'] as Map<String, dynamic>? ?? {};
      globalMaintenanceEnabled = maintenance['enabled'] as bool? ?? false;
      globalMaintenanceMessage = maintenance['message'] as String? ?? '';

      final forceUpdate = data['force_update'] as Map<String, dynamic>? ?? {};
      forceUpdateEnabled = forceUpdate['enabled'] as bool? ?? false;
      forceUpdateVersion = forceUpdate['version'] as String? ?? '';
      forceUpdateUrl = forceUpdate['url'] as String? ?? '';
      forceUpdateMessage = forceUpdate['message'] as String? ?? '';
    } else {
      // 2. Fallback to legacy configs/urls/spytrack document
      final fallbackDoc = await FirebaseFirestore.instance
          .collection('configs')
          .doc('urls')
          .get();

      if (fallbackDoc.exists && fallbackDoc.data() != null) {
        final fallbackData = fallbackDoc.data() as Map<String, dynamic>;
        final spytrackConfig = fallbackData['spytrack'] as Map<String, dynamic>? ?? {};

        SERVER_URL = spytrackConfig['url'] as List? ?? [];
        SHOW_ADS = (spytrackConfig['ads'] as bool? ?? false) && serverType == 'free';
        WHATS_APP = spytrackConfig['whatsapp'] as String? ?? '';
        PHONE_NO = spytrackConfig['phone'] as String? ?? '';
        EMAIL = spytrackConfig['email'] as String? ?? '';
        adsFrequency = spytrackConfig['adsfrequency'] as int? ?? 3;
        APP_VERSION = spytrackConfig['version'] as String? ?? '1.0.0';
        BANNER_IMAGE = spytrackConfig['banners'] as List<dynamic>? ?? [];
        fuelData = spytrackConfig['fuelData'] as Map<String, dynamic>? ?? {};
      }
    }

    // Cache timestamp so we skip Firestore on next launch within TTL
    await _prefs.setInt(
        'config_last_fetch', DateTime.now().millisecondsSinceEpoch);

    bool isBlocked = _applyMaintenanceCheck();
    if (!isBlocked) {
      await _applyForceUpdateCheck();
    }
  }

  bool _applyMaintenanceCheck() {
    if (globalMaintenanceEnabled && globalMaintenanceMessage.isNotEmpty && mounted) {
      setState(() {
        _isSystemBlockActive = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ServerMaintenanceScreen(message: globalMaintenanceMessage),
          ),
          (route) => false,
        );
      });
      return true;
    }

    final String? currentServerUrl = UserRepository.getServerUrl();
    for (final server in SERVER_URL) {
      if (server['url'] == currentServerUrl) {
        ALWAYS_SHOW_BANNER_ADS = server['showBannerAds'] ?? false;
        final String message = server['message'] as String? ?? '';
        if (message.isNotEmpty && mounted) {
          setState(() {
            _isSystemBlockActive = true;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => ServerMaintenanceScreen(message: message),
              ),
              (route) => false,
            );
          });
          return true;
        }
        break;
      }
    }
    return false;
  }

  Future<bool> _applyForceUpdateCheck() async {
    if (forceUpdateEnabled && forceUpdateVersion.isNotEmpty && mounted) {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      if (_isVersionLower(currentVersion, forceUpdateVersion)) {
        setState(() {
          _isSystemBlockActive = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => PopScope(
              canPop: false,
              child: AlertDialog(
                title: const Text('Update Required'),
                content: Text(forceUpdateMessage.isNotEmpty 
                    ? forceUpdateMessage 
                    : 'A new version of the app is available. Please update to continue.'),
                actions: [
                  TextButton(
                    onPressed: () async {
                      if (forceUpdateUrl.isNotEmpty) {
                        final uri = Uri.parse(forceUpdateUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      }
                    },
                    child: const Text('Update Now'),
                  ),
                ],
              ),
            ),
          );
        });
        return true;
      }
    }
    return false;
  }

  bool _isVersionLower(String current, String required) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final requiredParts = required.split('.').map(int.parse).toList();
      for (var i = 0; i < requiredParts.length; i++) {
        if (i >= currentParts.length) return true;
        if (currentParts[i] < requiredParts[i]) return true;
        if (currentParts[i] > requiredParts[i]) return false;
      }
    } catch (_) {
      return current != required;
    }
    return false;
  }

  // ─── Login check ──────────────────────────────────────────────────────────
  void checkPreference() {
    if (!mounted) return;
    if (UserRepository.getHash() != null) {
      checkLogin();
    } else {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) Get.offAndToNamed('/login');
      });
    }
  }

  void checkLogin() {
    APIService.login(
      UserRepository.getServerUrl(),
      UserRepository.getEmail(),
      UserRepository.getPassword(),
    ).then((response) {
      if (!mounted) return;
      if (response != null && response.statusCode == 200) {
        final UserLogin user = UserLogin.fromJson(
          jsonDecode(response.body.replaceAll('ï»¿', '')),
        );
        UserRepository.setHash(user.userApiHash!);
        _updateFcmToken();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) Get.offAndToNamed('/home');
        });
      } else {
        if (mounted) Get.offAndToNamed('/login');
      }
    }).catchError((e) {
      debugPrint('Login check error: $e');
      if (mounted) Get.offAndToNamed('/login');
    });
  }

  void _updateFcmToken() async {
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await APIService.getUserData();
        final response = await APIService.activateFCM(token);
        if (response.statusCode == 200) {
          debugPrint("FCM token activated successfully");
        } else {
          debugPrint("FCM server activation failed: ${response.statusCode}");
        }
      } else {
        debugPrint("FCM Token is empty");
      }
    } catch (e) {
      debugPrint('FCM token update error: $e');
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Centered logo ──────────────────────────────────────────────
            Center(
              child: AnimatedBuilder(
                animation: _logoController,
                builder: (context, _) {
                  return FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Image.asset(
                        'icons/banner_logo.png',
                        width: MediaQuery.of(context).size.width * 0.55,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Bottom loader / checkmark ──────────────────────────────────
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Center(
                child: _showCheckmark ? _buildCheckmark() : _buildLoader(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoader() {
    return SizedBox(
      width: 32,
      height: 32,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        valueColor: AlwaysStoppedAnimation<Color>(
          _primaryColor.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _buildCheckmark() {
    return AnimatedBuilder(
      animation: _checkController,
      builder: (context, _) {
        return FadeTransition(
          opacity: _checkFade,
          child: ScaleTransition(
            scale: _checkScale,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: _primaryColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        );
      },
    );
  }
}
