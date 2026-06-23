import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:smart_lock/screens/server_maintenance_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:smart_lock/services/model/login.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/storage/user_repository.dart';
import 'package:smart_lock/config.dart';
import 'package:smart_lock/constants/app_constants.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {

  // ─── Theme ────────────────────────────────────────────────────────────────
  static const Color _red = Color(0xFFE53935);
  static const Color _grey = Color(0xFFE0E0E0);
  static const Color _textGrey = Color(0xFF9E9E9E);

  // ─── Controllers ──────────────────────────────────────────────────────────
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  // ─── State ────────────────────────────────────────────────────────────────
  bool _passwordVisible = false;
  bool _isLoading = false;
  bool _rememberMe = true;
  bool _isLoadingServers = true;
  List<dynamic> _availableServers = [];

  // ─── Single SharedPreferences instance ───────────────────────────────────
  // Reuse the prefs already initialized in main via UserRepository
  SharedPreferences get _prefs => UserRepository.prefs!;

  final DataController _dataController = Get.put(DataController());

  // ─── Animation ────────────────────────────────────────────────────────────
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();

    _loadSavedCredentials();

    // If SERVER_URL is already populated from splash, skip the Firestore fetch
    if (SERVER_URL.isNotEmpty) {
      setState(() {
        _availableServers = List.from(SERVER_URL);
        _isLoadingServers = false;
      });
    } else {
      _fetchServersFromFirebase();
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ─── Load saved credentials ───────────────────────────────────────────────
  void _loadSavedCredentials() {
    final String? savedEmail = _prefs.getString('email');
    if (savedEmail != null) {
      _emailController.text = savedEmail;
      _passwordController.text = _prefs.getString('password') ?? '';
      _rememberMe = _prefs.getBool('rememberMe') ?? false;
    }
  }

  // ─── Firebase fetch (only called when SERVER_URL is empty) ───────────────
  Future<void> _fetchServersFromFirebase() async {
    try {
      setState(() => _isLoadingServers = true);

      final String serverType = _prefs.getString('serverType') ?? 'free';
      final doc = await FirebaseFirestore.instance
          .collection('configs')
          .doc('urls')
          .get();

      if (!doc.exists) return;

      final data = doc.data() as Map<String, dynamic>;
      if (!data.containsKey('spytrack')) return;

      final spytrackConfig = data['spytrack'] as Map<String, dynamic>;
      final urlData = spytrackConfig['url'];

      List<dynamic> serverList = [];
      if (urlData is List) {
        serverList = urlData;
      } else if (urlData is String) {
        try {
          serverList = jsonDecode(urlData) as List;
        } catch (_) {}
      }

      SERVER_URL = serverList;
      SHOW_ADS = (spytrackConfig['ads'] as bool? ?? false) && serverType == 'free';
      WHATS_APP = spytrackConfig['whatsapp'] as String? ?? '';
      PHONE_NO = spytrackConfig['phone'] as String? ?? '';
      EMAIL = spytrackConfig['email'] as String? ?? '';
      adsFrequency = spytrackConfig['adsfrequency'] as int? ?? 3;
      APP_VERSION = spytrackConfig['version'] as String? ?? '1.0.0';
      if (spytrackConfig['banners'] != null) {
        BANNER_IMAGE = spytrackConfig['banners'] as List;
      }
      if (spytrackConfig['fuelData'] != null) {
        fuelData = spytrackConfig['fuelData'];
      }

      if (mounted) {
        setState(() {
          _availableServers = serverList;
          _isLoadingServers = false;
        });
      }
    } catch (e) {
      debugPrint('Server fetch error: $e');
      if (mounted) {
        setState(() => _isLoadingServers = false);
      }
    }
  }

  // ─── Maintenance check (post-login) ───────────────────────────────────────
  Future<void> _checkMaintenanceForCurrentServer() async {
    try {
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
    } catch (e) {
      debugPrint('Maintenance check error: $e');
    }
  }

  // ─── Support actions ──────────────────────────────────────────────────────
  Future<void> _callSupportPhone() async {
    if (PHONE_NO.isEmpty) {
      Get.snackbar('Sorry!', 'Phone number not available');
      return;
    }
    final Uri uri = Uri.parse('tel:$PHONE_NO');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        Get.snackbar('Error', 'Phone call not supported on this device');
      }
    } catch (e) {
      debugPrint('Phone launch error: $e');
      Get.snackbar('Error', 'Failed to open phone app');
    }
  }

  Future<void> _openWhatsAppSupport() async {
    if (WHATS_APP.isEmpty) {
      Get.snackbar('Sorry!', 'WhatsApp not available');
      return;
    }
    final String cleanNumber = WHATS_APP.replaceAll(RegExp(r'[^0-9]'), '');

    // Get the typed or saved SIM/IMEI
    String deviceIdentifier = _emailController.text.trim();
    if (deviceIdentifier.isEmpty) {
      deviceIdentifier = _prefs.getString('email') ?? '';
    }

    // Clean any email domain suffix (e.g. from "01982822121@sl.com" to "01982822121")
    String cleanIdentifier = deviceIdentifier;
    if (deviceIdentifier.contains('@')) {
      cleanIdentifier = deviceIdentifier.split('@').first;
    }

    String message = "Hello Smart Lock";
    if (cleanIdentifier.isNotEmpty) {
      message += " $cleanIdentifier";
    }

    final Uri uri = Uri.parse('https://wa.me/$cleanNumber?text=${Uri.encodeComponent(message)}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        Get.snackbar('Error', 'WhatsApp not installed');
      }
    } catch (e) {
      debugPrint('WhatsApp launch error: $e');
      Get.snackbar('Error', 'Failed to open WhatsApp');
    }
  }

  Future<void> _openYoutube() async {
    final Uri uri = Uri.parse('https://www.youtube.com');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('YouTube launch error: $e');
    }
  }

  // ─── FCM token ────────────────────────────────────────────────────────────
  void _updateFcmToken() async {
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await APIService.activateFCM(token);
        debugPrint('FCM token registered');
      }
    } catch (e) {
      debugPrint('FCM token error: $e');
    }
  }

  // ─── Login ────────────────────────────────────────────────────────────────
  void _loginPressed() async {
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter email and password'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_availableServers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No servers available. Please try again later.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    bool loginSuccess = false;
    Map<String, dynamic>? successfulServer;
    int? lastStatusCode;

    try {
      final List<dynamic> activeServers = _availableServers
          .where((s) =>
      (s['message'] as String? ?? '').isEmpty)
          .toList();

      if (activeServers.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All servers are under maintenance'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      for (final server in activeServers) {
        try {
          final response =
          await APIService.login(server['url'], email, password);
          if (response == null) continue;
          lastStatusCode = response.statusCode;
          if (response.statusCode == 200) {
            final UserLogin user = UserLogin.fromJson(
              jsonDecode(response.body.replaceAll('ï»¿', '')),
            );
            UserRepository.setServerUrl(server['url'] as String);
            UserRepository.setHash(user.userApiHash!);
            await _prefs.setString('serverType', server['type'] as String? ?? 'free');

            if (_rememberMe) {
              UserRepository.setEmail(email);
              UserRepository.setPassword(password);
              await _prefs.setBool('rememberMe', true);
            } else {
              await _prefs.remove('email');
              await _prefs.remove('password');
              await _prefs.setBool('rememberMe', false);
            }

            successfulServer = server as Map<String, dynamic>;
            loginSuccess = true;
            break;
          }
        } catch (e) {
          debugPrint('Server ${server['url']} login error: $e');
          continue;
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    if (loginSuccess && successfulServer != null) {
      _dataController.getDevices();
      _updateFcmToken();
      await _checkMaintenanceForCurrentServer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      'Login successful (${successfulServer['name'] ?? 'Server'})'),
                ),
              ],
            ),
          ),
        );
        Get.offAndToNamed('/home');
      }
    } else {
      String message = 'Login failed. Please check credentials.';
      if (lastStatusCode == 401 || lastStatusCode == 400) {
        message = 'Invalid email or password';
      } else if (lastStatusCode == 422) {
        message = 'Email and password are required';
      } else if (lastStatusCode == null) {
        message = 'Could not reach server. Check your internet connection.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
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
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 100),

                  // ── Logo ──────────────────────────────────────────────────
                  Image.asset(
                    AppConstants.logoPath,
                    height: 90,
                    fit: BoxFit.contain,
                  ),

                  const SizedBox(height: 60),

                  // ── Email ─────────────────────────────────────────────────
                  _inputField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    hint: 'Enter your email',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(_passwordFocus),
                  ),

                  const SizedBox(height: 16),

                  // ── Password ──────────────────────────────────────────────
                  _inputField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    hint: 'Enter Password',
                    obscureText: !_passwordVisible,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _loginPressed(),
                    suffix: IconButton(
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: _textGrey,
                        size: 20,
                      ),
                      onPressed: () => setState(
                              () => _passwordVisible = !_passwordVisible),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Login button ──────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (_isLoading || _isLoadingServers)
                          ? null
                          : _loginPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _red,
                        disabledBackgroundColor: Colors.grey.shade400,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white),
                        ),
                      )
                          : _isLoadingServers
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white),
                        ),
                      )
                          : const Text(
                        'LogIn',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Terms ─────────────────────────────────────────────────
                  RichText(
                    textAlign: TextAlign.center,
                    text: const TextSpan(
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                      children: [
                        TextSpan(
                          text:
                          'By Successfully login, You are agreeing with Our\n',
                        ),
                        TextSpan(
                          text: 'Terms and Conditions',
                          style: TextStyle(
                              color: _red, fontWeight: FontWeight.w500),
                        ),
                        TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy policy',
                          style: TextStyle(
                              color: _red, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // ── Support buttons ───────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _socialButton(
                        backgroundColor: Colors.white54,
                        icon: 'icons/mobile.png',
                        label: 'Call',
                        onTap: _callSupportPhone,
                      ),
                      _socialButton(
                        backgroundColor: Colors.white54,
                        icon: 'icons/youtube.png',
                        label: 'Youtube',
                        onTap: _openYoutube,
                      ),
                      _socialButton(
                        backgroundColor: Colors.white54,
                        icon: 'icons/whatsapp.png',
                        label: 'WhatsApp',
                        onTap: _openWhatsAppSupport,
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Reusable widgets ─────────────────────────────────────────────────────
  Widget _inputField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 16, color: Colors.black87),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _textGrey, fontSize: 14),
        suffixIcon: suffix,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _grey, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
          const BorderSide(color: Color(0xFFE53935), width: 1.5),
        ),
      ),
    );
  }

  Widget _socialButton({
    required Color backgroundColor,
    required String icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Image.asset(
                icon,
                fit: BoxFit.fill,
                height: 50,
                width: 50,
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black87,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}