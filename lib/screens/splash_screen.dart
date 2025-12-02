import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:gpspro/config.dart';
import 'package:gpspro/screens/server_maintenance_screen.dart';
import 'package:gpspro/services/admob_service.dart';
import 'package:gpspro/services/model/login.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreenPage extends StatefulWidget {
  const SplashScreenPage({super.key});

  @override
  State<StatefulWidget> createState() => _SplashScreenPageState();
}

class _SplashScreenPageState extends State<SplashScreenPage>
    with TickerProviderStateMixin {

  // TIMING CONFIGURATION - Adjust these values as needed

  static const Duration _minimumSplashDuration = Duration(seconds: 2);
  static const Duration _initialDelay = Duration(milliseconds: 400);


  SharedPreferences? prefs;
  String _notificationToken = "";

  // State variables
  bool _configLoaded = false;
  bool _minimumTimeReached = false;
  String _loadingStatus = 'Initializing...';

  // Animation Controllers
  late AnimationController _logoController;
  late AnimationController _pulseController;
  late AnimationController _progressController;
  late AnimationController _vehicleController;
  late AnimationController _shimmerController;
  late AnimationController _floatingController;

  // Animations
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _pulseAnimation;
  late Animation<double> _progressAnimation;
  late Animation<double> _vehicleAnimation;
  late Animation<double> _shimmerAnimation;
  late Animation<double> _floatingAnimation;

  // Notification Channel
  AndroidNotificationChannel channel = const AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // Theme Colors
  static const Color _primaryColor = Color(0xFF1D4888);
  static const Color _accentColor = Color(0xFFFFAC00);
  static const Color _lightAccent = Color(0xFFE4B34E);

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _requestPermissions();

    // Start loading after initial delay
    Future.delayed(_initialDelay, () {
      fetchConfigAndProceed();
    });

    // Ensure minimum splash time
    Future.delayed(_minimumSplashDuration, () {
      _minimumTimeReached = true;
      _tryNavigate();
    });
  }

  void _initAnimations() {
    // Logo animation
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
      ),
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    // Pulse animation for glow effects
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Progress animation - synced with vehicle
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _progressAnimation = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOut,
    );

    // Vehicle animation - same as progress
    _vehicleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _vehicleAnimation = CurvedAnimation(
      parent: _vehicleController,
      curve: Curves.easeInOut,
    );

    // Shimmer animation
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      _shimmerController,
    );

    // Floating elements animation
    _floatingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _floatingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _floatingController, curve: Curves.easeInOut),
    );

    // Start logo animation
    _logoController.forward();
  }

  void _requestPermissions() {
    Permission.location.request();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _pulseController.dispose();
    _progressController.dispose();
    _vehicleController.dispose();
    _shimmerController.dispose();
    _floatingController.dispose();
    super.dispose();
  }

  void _updateStatus(String status) {
    if (mounted) {
      setState(() {
        _loadingStatus = status;
      });
    }
  }

  void _tryNavigate() {
    if (_configLoaded && _minimumTimeReached) {
      checkPreference();
    }
  }

  Future<void> fetchConfigAndProceed() async {
    try {
      _updateStatus('Loading configuration...');

      prefs = await SharedPreferences.getInstance();
      var serverType = prefs!.getString('serverType') ?? 'free';

      final doc = await FirebaseFirestore.instance
          .collection('configs')
          .doc('urls')
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final spytrackConfig = data['spytrack'] as Map<String, dynamic>;
        SERVER_URL = spytrackConfig['url'] as List;
        SHOW_ADS = (spytrackConfig['ads'] as bool) && serverType == 'free';
        WHATS_APP = spytrackConfig['whatsapp'] as String;
        PHONE_NO = spytrackConfig['phone'] as String;
        EMAIL = spytrackConfig['email'] as String;
        adsFrequency = spytrackConfig['adsfrequency'] as int;
        APP_VERSION = spytrackConfig['version'] as String;
        BANNER_IMAGE = spytrackConfig['banners'] as List<dynamic>;
        fuelData = spytrackConfig['fuelData'];
      }

      _updateStatus('Checking server...');

      String? currentServerUrl = UserRepository.getServerUrl();
      for (var server in SERVER_URL) {
        if (server['url'] == currentServerUrl) {
          ALWAYS_SHOW_BANNER_ADS = server['showBannerAds'];
          final message = server['message'] ?? '';
          if (message.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => ServerMaintenanceScreen(message: message),
                ),
                    (route) => false,
              );
            });
            return;
          }
          break;
        }
      }

      if (SHOW_ADS) {
        _updateStatus('Loading resources...');
        await AdMobService().initialize();
      }

      _updateStatus('Almost ready...');
      _configLoaded = true;
      _tryNavigate();
    } catch (e) {
      print('Error fetching Firebase config: $e');
      _configLoaded = true;
      _tryNavigate();
    }
  }

  void checkPreference() async {
    if (UserRepository.getHash() != null) {
      checkLogin();
    } else {
      await Future.delayed(const Duration(milliseconds: 300));
      Get.offAndToNamed('/login');
    }
  }

  void checkLogin() {
    _updateStatus('Signing in...');

    APIService.login(
      UserRepository.getServerUrl(),
      UserRepository.getEmail(),
      UserRepository.getPassword(),
    ).then((response) {
      if (response != null && response.statusCode == 200) {
        UserLogin user = UserLogin.fromJson(
          jsonDecode(response.body.replaceAll("ï»¿", "")),
        );
        UserRepository.setHash(user.userApiHash!);
        updateToken();
        _updateStatus('Welcome back!');
        Future.delayed(const Duration(milliseconds: 500), () {
          Get.offAndToNamed('/home');
        });
      } else {
        Get.offAndToNamed('/login');
      }
    });
  }

  void updateToken() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.getToken().then((value) => {_notificationToken = value!});
    APIService.getUserData()
        .then((value) => {APIService.activateFCM(_notificationToken)});
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Top Wave Design
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: CustomPaint(
              size: Size(MediaQuery.of(context).size.width, 280),
              painter: TopWavePainter(),
            ),
          ),

          // Bottom Wave Design
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CustomPaint(
              size: Size(MediaQuery.of(context).size.width, 180),
              painter: BottomWavePainter(),
            ),
          ),

          // Decorative Elements
          _buildDecorativeElements(),

          // Floating Elements
          _buildFloatingElements(),

          // Main content
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Logo Section
                _buildLogoSection(),

                const SizedBox(height: 35),

                // App Title
                _buildAppTitle(),

                const SizedBox(height: 14),

                // Tagline
                _buildTagline(),

                const Spacer(flex: 3),

                // Loading Section - Car with Progress
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: _buildLoadingSection(),
                ),

                const Spacer(flex: 2),

                // Footer
                _buildFooter(),

                const SizedBox(height: 25),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecorativeElements() {
    return Stack(
      children: [
        Positioned(
          top: 120,
          right: 30,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
          ),
        ),
        Positioned(
          top: 180,
          left: 40,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
        ),
        Positioned(
          top: 200,
          right: 50,
          child: _buildDotPattern(Colors.white.withValues(alpha: 0.3)),
        ),
        Positioned(
          bottom: 120,
          left: 30,
          child: _buildAccentLines(),
        ),
      ],
    );
  }

  Widget _buildDotPattern(Color color) {
    return Column(
      children: List.generate(3, (row) {
        return Row(
          children: List.generate(3, (col) {
            return Container(
              margin: const EdgeInsets.all(3),
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            );
          }),
        );
      }),
    );
  }

  Widget _buildAccentLines() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 35,
          height: 3,
          decoration: BoxDecoration(
            color: _primaryColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 5),
        Container(
          width: 22,
          height: 3,
          decoration: BoxDecoration(
            color: _primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 5),
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: _primaryColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingElements() {
    return AnimatedBuilder(
      animation: _floatingAnimation,
      builder: (context, child) {
        double offset = _floatingAnimation.value * 10;
        return Stack(
          children: [
            Positioned(
              top: 300 + offset,
              right: 45,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _primaryColor
                          .withValues(alpha: 0.15 * _pulseAnimation.value),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 350 - offset,
              left: 55,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _accentColor
                          .withValues(alpha: 0.2 * _pulseAnimation.value),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              bottom: 280 + offset,
              right: 70,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _primaryColor.withValues(alpha: 0.15),
                    width: 2,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 320 - offset,
              left: 40,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _lightAccent.withValues(alpha: 0.2),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLogoSection() {
    return AnimatedBuilder(
      animation: _logoController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _logoFade,
          child: ScaleTransition(
            scale: _logoScale,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _primaryColor
                            .withValues(alpha: 0.25 * _pulseAnimation.value),
                        blurRadius: 50,
                        spreadRadius: 15,
                      ),
                    ],
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _primaryColor.withValues(alpha: 0.2),
                          _accentColor.withValues(alpha: 0.15),
                        ],
                      ),
                    ),
                    child: Container(
                      width: 135,
                      height: 135,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: _primaryColor.withValues(alpha: 0.2),
                            blurRadius: 25,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Image.asset(
                            'images/logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppTitle() {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: const [
                _primaryColor,
                _lightAccent,
                _primaryColor,
              ],
              stops: [
                (_shimmerAnimation.value - 0.3).clamp(0.0, 1.0),
                _shimmerAnimation.value.clamp(0.0, 1.0),
                (_shimmerAnimation.value + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: const Text(
            'GPS PRO',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 8,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTagline() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: _primaryColor.withValues(alpha: 0.15),
          width: 1.5,
        ),
        color: _primaryColor.withValues(alpha: 0.04),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _primaryColor,
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Real-Time Vehicle Tracking',
            style: TextStyle(
              fontSize: 14,
              color: _primaryColor.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }


  // LOADING SECTION WITH PROGRESS MOVING WITH CAR


  Widget _buildLoadingSection() {
    return Column(
      children: [
        // Vehicle Road with Progress on top of car
        _buildVehicleRoadWithProgress(),

        const SizedBox(height: 20),

        // Progress Bar below
        // _buildProgressBar(),

        const SizedBox(height: 150),

        // Status text
        // _buildStatusText(),
      ],
    );
  }

  Widget _buildVehicleRoadWithProgress() {
    return SizedBox(
      height: 130, // Height for progress badge + car
      child: AnimatedBuilder(
        animation: _vehicleAnimation,
        builder: (context, child) {
          return LayoutBuilder(
            builder: (context, constraints) {
              double roadWidth = constraints.maxWidth;
              double carWidth = 80;
              double carPosition =
                  _vehicleAnimation.value * (roadWidth - carWidth - 20);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Road Container
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildRoad(),
                  ),

                  // Car with Progress Badge
                  Positioned(
                    left: carPosition + 10,
                    bottom: 5,
                    child: _buildCarWithProgress(),
                  ),

                  // Trail Effect behind car
                  Positioned(
                    left: 10,
                    right: roadWidth - carPosition,
                    bottom: 28,
                    child: _buildTrailEffect(),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRoad() {
    return Container(
      height: 55,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _primaryColor.withValues(alpha: 0.08),
            _primaryColor.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(
          color: _primaryColor.withValues(alpha: 0.12),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(10, (index) {
              return AnimatedBuilder(
                animation: _vehicleAnimation,
                builder: (context, child) {
                  // Animate dashes
                  double opacity = 0.15 +
                      (0.15 *
                          math.sin(
                              (_vehicleAnimation.value * 2 * math.pi) +
                                  (index * 0.5)));
                  return Container(
                    width: 16,
                    height: 3,
                    decoration: BoxDecoration(
                      color: _primaryColor.withValues(alpha: opacity),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                },
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildCarWithProgress() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress Percentage Badge
        AnimatedBuilder(
          animation: _progressAnimation,
          builder: (context, child) {
            return AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _primaryColor,
                        _accentColor,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color:
                        _primaryColor.withValues(alpha: 0.4 * _pulseAnimation.value),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    '${(_progressAnimation.value * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                );
              },
            );
          },
        ),

        // Connector Arrow
        CustomPaint(
          size: const Size(12, 8),
          painter: ArrowPainter(color: _primaryColor),
        ),

        // Car Icon
        _buildCarIcon(),
      ],
    );
  }

  Widget _buildCarIcon() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          width: 80,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: _accentColor.withValues(alpha: 0.3 * _pulseAnimation.value),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Image.asset(
            'images/car.png',
            fit: BoxFit.contain,
          ),
        );
      },
    );
  }

  Widget _buildTrailEffect() {
    return AnimatedBuilder(
      animation: _vehicleAnimation,
      builder: (context, child) {
        return Container(
          height: 4,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(
              colors: [
                _accentColor.withValues(alpha: 0.0),
                _accentColor.withValues(alpha: 0.2),
                _accentColor.withValues(alpha: 0.4),
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _buildFooter() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _primaryColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: _primaryColor.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 14,
                color: _accentColor.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 8),
              Text(
                'Secure GPS Tracking',
                style: TextStyle(
                  fontSize: 11,
                  color: _primaryColor.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Version 1.0.0',
          style: TextStyle(
            fontSize: 10,
            color: _primaryColor.withValues(alpha: 0.4),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}


class TopWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF1D4888),
          Color(0xFF2D5A9A),
          Color(0xFFFFAC00),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path()
      ..lineTo(0, size.height * 0.75)
      ..cubicTo(
        size.width * 0.25,
        size.height * 0.95,
        size.width * 0.45,
        size.height * 0.65,
        size.width * 0.6,
        size.height * 0.8,
      )
      ..cubicTo(
        size.width * 0.75,
        size.height * 0.95,
        size.width * 0.9,
        size.height * 0.7,
        size.width,
        size.height * 0.85,
      )
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);

    final paint2 = Paint()..color = const Color(0xFF3D6AA8).withValues(alpha: 0.5);

    final path2 = Path()
      ..lineTo(0, size.height * 0.6)
      ..cubicTo(
        size.width * 0.2,
        size.height * 0.85,
        size.width * 0.5,
        size.height * 0.55,
        size.width * 0.7,
        size.height * 0.75,
      )
      ..cubicTo(
        size.width * 0.85,
        size.height * 0.9,
        size.width * 0.95,
        size.height * 0.8,
        size.width,
        size.height,
      )
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path2, paint2);

    final paint3 = Paint()..color = const Color(0xFF5A84B8).withValues(alpha: 0.3);

    final path3 = Path()
      ..lineTo(0, size.height * 0.5)
      ..cubicTo(
        size.width * 0.15,
        size.height * 0.75,
        size.width * 0.35,
        size.height * 0.65,
        size.width * 0.55,
        size.height * 0.85,
      )
      ..cubicTo(
        size.width * 0.75,
        size.height * 1.0,
        size.width * 0.9,
        size.height * 0.9,
        size.width,
        size.height * 1.05,
      )
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path3, paint3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BottomWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x0D1D4888),
          Color(0x1A1D4888),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path()
      ..moveTo(0, size.height * 0.5)
      ..cubicTo(
        size.width * 0.25,
        size.height * 0.2,
        size.width * 0.5,
        size.height * 0.6,
        size.width * 0.75,
        size.height * 0.3,
      )
      ..cubicTo(
        size.width * 0.9,
        size.height * 0.15,
        size.width * 0.95,
        size.height * 0.25,
        size.width,
        size.height * 0.2,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);

    final paint2 = Paint()..color = const Color(0xFFFFAC00).withValues(alpha: 0.05);

    final path2 = Path()
      ..moveTo(0, size.height * 0.7)
      ..cubicTo(
        size.width * 0.3,
        size.height * 0.4,
        size.width * 0.6,
        size.height * 0.8,
        size.width,
        size.height * 0.5,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ArrowPainter extends CustomPainter {
  final Color color;

  ArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder({
    Key? key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(key: key, listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}