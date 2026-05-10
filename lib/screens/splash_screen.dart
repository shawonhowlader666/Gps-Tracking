import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
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

  // Cache TTL: re-fetch Firestore config only after 30 minutes
  static const int _configCacheTtlMs = 30 * 60 * 1000;

  // ─── State ────────────────────────────────────────────────────────────────
  bool _configLoaded = false;
  bool _minimumTimeReached = false;
  bool _showCheckmark = false;

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
    if (_configLoaded && _minimumTimeReached) {
      setState(() => _showCheckmark = true);
      _checkController.forward();
      Future.delayed(const Duration(milliseconds: 800), checkPreference);
    }
  }

  // ─── Config fetch with caching ────────────────────────────────────────────
  Future<void> fetchConfigAndProceed() async {
    try {
      // Check cache first — skip Firestore if data is fresh
      final int lastFetch = _prefs.getInt('config_last_fetch') ?? 0;
      final int now = DateTime.now().millisecondsSinceEpoch;
      final bool cacheValid =
          (now - lastFetch) < _configCacheTtlMs && SERVER_URL.isNotEmpty;

      if (!cacheValid) {
        await _fetchFromFirestore();
      } else {
        // Still check for server maintenance message using cached SERVER_URL
        _applyMaintenanceCheck();
      }
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

    final doc = await FirebaseFirestore.instance
        .collection('configs')
        .doc('urls')
        .get();

    if (!doc.exists) return;

    final data = doc.data() as Map<String, dynamic>;
    final spytrackConfig = data['spytrack'] as Map<String, dynamic>;

    SERVER_URL = spytrackConfig['url'] as List;
    SHOW_ADS = (spytrackConfig['ads'] as bool? ?? false) && serverType == 'free';
    WHATS_APP = spytrackConfig['whatsapp'] as String? ?? '';
    PHONE_NO = spytrackConfig['phone'] as String? ?? '';
    EMAIL = spytrackConfig['email'] as String? ?? '';
    adsFrequency = spytrackConfig['adsfrequency'] as int? ?? 3;
    APP_VERSION = spytrackConfig['version'] as String? ?? '1.0.0';
    BANNER_IMAGE = spytrackConfig['banners'] as List<dynamic>? ?? [];
    fuelData = spytrackConfig['fuelData'];

    // Cache timestamp so we skip Firestore on next launch within TTL
    await _prefs.setInt(
        'config_last_fetch', DateTime.now().millisecondsSinceEpoch);

    _applyMaintenanceCheck();
  }

  void _applyMaintenanceCheck() {
    final String? currentServerUrl = UserRepository.getServerUrl();
    for (final server in SERVER_URL) {
      if (server['url'] == currentServerUrl) {
        ALWAYS_SHOW_BANNER_ADS = server['showBannerAds'] ?? false;
        final String message = server['message'] as String? ?? '';
        if (message.isNotEmpty && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => ServerMaintenanceScreen(message: message),
              ),
                  (route) => false,
            );
          });
        }
        break;
      }
    }
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
        await APIService.activateFCM(token);
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
                child:
                _showCheckmark ? _buildCheckmark() : _buildLoader(),
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