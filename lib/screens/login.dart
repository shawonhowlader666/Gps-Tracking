import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';

import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/flutter_flow/flutter_flow_widgets.dart';
import 'package:gpspro/screens/server_maintenance_screen.dart';
import 'package:gpspro/services/admob_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Import your other necessary files
import 'package:gpspro/services/model/login.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/config.dart';

// Define custom colors
const Color kPrimaryOrange = Color(0xFFF27B35);
const Color kLightGrey =
    Color(0xFFE0E0E0); // For inactive language button border

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<double> _translateAnimation;

  SharedPreferences? prefs;
  final TextEditingController _emailFilter = TextEditingController();
  final TextEditingController _passwordFilter = TextEditingController();
  final TextEditingController _serverUrl = TextEditingController();

  FocusNode? emailAddressFocusNode;
  late bool passwordVisibility;
  FocusNode? passwordFocusNode;
  bool _rememberMe = false; // Added for "Keep me sign in" checkbox

  DataController dataController = Get.put(DataController());

  String _email = "";
  String _password = "";
  String _notificationToken = "";
  bool isLoading = false;
  int _selectedLanguageIndex = 0; // 0 for English, 1 for Bangla

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
      ),
    );

    _translateAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();

    passwordVisibility = true;
    emailAddressFocusNode = FocusNode();
    passwordFocusNode = FocusNode();

    _emailFilter.addListener(_emailListen);
    _passwordFilter.addListener(_passwordListen);

    checkPreference();
  }

  @override
  void dispose() {
    _controller.dispose();
    emailAddressFocusNode?.dispose();
    passwordFocusNode?.dispose();
    _emailFilter.removeListener(_emailListen);
    _passwordFilter.removeListener(_passwordListen);
    _emailFilter.dispose();
    _passwordFilter.dispose();
    _serverUrl.dispose();
    super.dispose();
  }

  void _emailListen() {
    if (_emailFilter.text.isEmpty) {
      _email = "";
    } else {
      _email = _emailFilter.text;
    }
  }

  void _passwordListen() {
    if (_passwordFilter.text.isEmpty) {
      _password = "";
    } else {
      _password = _passwordFilter.text;
    }
  }

  void checkPreference() async {
    prefs = await SharedPreferences.getInstance();
    if (UserRepository.getServerUrl() != null &&
        prefs!.getBool('isManualServerUrl') == true) {
      setState(() {
        _serverUrl.text = UserRepository.getServerUrl()!;
      });
    } else {
      setState(() {
        _serverUrl.text = '';
      });
    }
    if (prefs!.getString('email') != null) {
      _emailFilter.text = prefs!.getString('email')!;
      _passwordFilter.text = prefs!.getString('password')!;
      _rememberMe =
          prefs!.getBool('rememberMe') ?? false; // Load remember me state
    }

    // Set initial language based on preferences
    String? langCode = prefs!.getString('language_code');
    if (langCode == 'bn') {
      _selectedLanguageIndex = 1;
    } else {
      _selectedLanguageIndex = 0;
    }
  }

  Future<void> fetchConfigAndProceed() async {
    try {
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
        BANNER_IMAGE = spytrackConfig['banners'] as List;
        fuelData = spytrackConfig['fuelData'];
      }

      // // Only update server URL from Firebase if no manual URL was set
      // if (SERVER_URL.isNotEmpty) {
      //   final prefs = await SharedPreferences.getInstance();
      //   if (prefs.getBool('isManualServerUrl') != true) {
      //     UserRepository.setServerUrl(SERVER_URL);
      //   }
      // }

      // 🔍 Match current server URL with server list
      String? currentServerUrl = UserRepository.getServerUrl();
      for (var server in SERVER_URL) {
        if (server['url'] == currentServerUrl) {
          ALWAYS_SHOW_BANNER_ADS = server['showBannerAds'];
          final message = server['message'] ?? '';
          if (message.isNotEmpty) {
            // 🚪 Close all routes and go to maintenance screen
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
        await AdMobService().initialize();
      }
    } catch (e) {
      print('Error fetching Firebase config: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
    ));

    return Scaffold(
      backgroundColor: Colors.white, // Set scaffold background to white
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _translateAnimation.value),
                child: Opacity(
                  opacity: _opacityAnimation.value,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start, // Align content to start
                    children: [
                      // Header: Language selector and chat icon
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SizedBox(
                            width: 15,
                          ),

                          // Language Toggle
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: kLightGrey, width: 1),
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedLanguageIndex = 0;
                                      Get.updateLocale(const Locale('en'));
                                      prefs?.setString('language_code', 'en');
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 30, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _selectedLanguageIndex == 0
                                          ? kPrimaryOrange
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'English',
                                      style: TextStyle(
                                        color: _selectedLanguageIndex == 0
                                            ? Colors.white
                                            : Colors.black,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedLanguageIndex = 1;
                                      Get.updateLocale(const Locale('bn'));
                                      prefs?.setString('language_code', 'bn');
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 30, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _selectedLanguageIndex == 1
                                          ? kPrimaryOrange
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'বাংলা',
                                      style: TextStyle(
                                        color: _selectedLanguageIndex == 1
                                            ? Colors.white
                                            : Colors.black,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Chat Icon
                          GestureDetector(
                            onTap: () async {
                              if (WHATS_APP.isEmpty) {
                                Get.snackbar(
                                    "Sorry!", "Not available right now");
                              } else {
                                await launchUrl(Uri.parse(WHATS_APP));
                              }
                            },
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: kLightGrey, width: 1),
                              ),
                              child: Center(
                                  child: Icon(
                                size: 20,
                                Icons.support_agent_outlined,
                                color: kPrimaryOrange,
                              )),
                            ),
                          ),
                        ],
                      ),

                      const Gap(60), // Increased gap for spacing

                      // SPYTRACK Logo
                      Center(
                        child: Image.asset(
                          'images/logo.png', // Assuming this is the correct path for the SPYTRACK logo
                          height: 30, // Adjust height as needed
                          fit: BoxFit.contain,
                        ),
                      ),

                      const Gap(90), // Increased gap for spacing

                      // "Sign in" title
                      Text(
                        'Sign in',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),

                      const Gap(24),

                      // Login form
                      _buildLoginForm(),

                      const Gap(20),

                      // "Keep me sign in" checkbox
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _rememberMe = !_rememberMe;
                              });
                            },
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color:
                                    _rememberMe ? kPrimaryOrange : Colors.white,
                                borderRadius: BorderRadius.circular(
                                    4), // Slightly rounded corners
                                border: Border.all(
                                  color: kLightGrey, // Thin border
                                  width: 1,
                                ),
                              ),
                              child: _rememberMe
                                  ? const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Keep me sign in',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),

                      const Gap(40),

                      // Login button
                      _buildLoginButton(),

                      const Gap(10),

                      // Forgot Password link
                      Center(
                        child: TextButton(
                          onPressed: () {
                            // Handle forgot password
                          },
                          child: Text(
                            'Forgot Password',
                            style: TextStyle(
                              fontSize: 14,
                              color: kPrimaryOrange,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),

                      const Gap(60), // Gap before BTRC section
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
      // "Approved By BTRC" section at the bottom center
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'images/btrc.png', // Placeholder, replace with actual BTRC logo if available
              height: 30,
              width: 30,
            ),
            const SizedBox(width: 8),
            Text(
              'Approved By BTRC',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      children: [
        // Email field
        TextField(
          controller: _emailFilter,
          focusNode: emailAddressFocusNode,
          style: const TextStyle(color: Colors.black, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'User ID or Email', // Changed label text
            labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            hintText: 'User ID or Email', // Changed hint text
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            prefixIcon: const Icon(Icons.mail_outline,
                color: Colors.grey, size: 20), // Changed icon
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kLightGrey),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kPrimaryOrange),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red),
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => passwordFocusNode?.requestFocus(),
        ),

        const Gap(16),

        // Password field
        TextField(
          controller: _passwordFilter,
          focusNode: passwordFocusNode,
          obscureText: passwordVisibility,
          style: const TextStyle(color: Colors.black, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Password', // Changed label text
            labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            hintText: 'Password', // Changed hint text
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            prefixIcon: const Icon(Icons.key,
                color: Colors.grey, size: 20), // Changed icon
            suffixIcon: IconButton(
              icon: Icon(
                passwordVisibility ? Icons.visibility : Icons.visibility_off,
                color: Colors.grey, // Changed icon color
                size: 20,
              ),
              onPressed: () =>
                  setState(() => passwordVisibility = !passwordVisibility),
            ),
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kLightGrey),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kPrimaryOrange),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red),
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _loginPressed(),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return FFButtonWidget(
      // Using FFButtonWidget for consistency with existing code
      onPressed: isLoading ? null : _loginPressed,
      text: 'Sign In →', // Changed text and added arrow
      options: FFButtonOptions(
        width: double.infinity,
        height: 50,
        color: kPrimaryOrange,
        textStyle: FlutterFlowTheme.of(context).titleSmall.override(
              fontFamily: 'Open Sans',
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
        elevation: 0, // Removed elevation
        borderSide: const BorderSide(
          color: Colors.transparent,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(25), // Perfect rounded sides
      ),
      showLoadingIndicator: isLoading,
    );
  }

  // Removed _buildBottomButtons as it's replaced by the new design elements
  // Widget _buildBottomButtons() {
  //   return Container(...);
  // }

  void _showLanguageDialog(BuildContext context) {
    // This dialog is no longer needed as language selection is now a toggle in the header
    // However, keeping the function for now in case it's called from other places or for future use.
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Language',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: FlutterFlowTheme.of(context).primary,
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.language, size: 20),
                title: const Text('English', style: TextStyle(fontSize: 14)),
                onTap: () async {
                  Get.updateLocale(const Locale('en'));
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('language_code', 'en');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.language, size: 20),
                title: const Text('Bangla', style: TextStyle(fontSize: 14)),
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

  void showServerDialog(BuildContext context) {
    // This function is still relevant for "Add Server" functionality if needed elsewhere
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Server Configuration',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: FlutterFlowTheme.of(context).primary,
                ),
              ),
              const Divider(height: 16),
              TextField(
                controller: _serverUrl,
                decoration: InputDecoration(
                  labelText: 'Enter server url without http or https',
                  labelStyle: const TextStyle(fontSize: 14),
                  hintStyle: const TextStyle(fontSize: 14),
                  prefixIcon: const Icon(Icons.dns, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (_serverUrl.text.trim().isNotEmpty) {
                        if (!_serverUrl.text.trim().contains('http://')) {
                          UserRepository.setServerUrl(
                              'http://${_serverUrl.text}');
                          _serverUrl.text = 'http://${_serverUrl.text}';
                        } else {
                          UserRepository.setServerUrl('${_serverUrl.text}');
                        }
                        prefs!.setBool('isManualServerUrl', true);
                      } else {
                        _serverUrl.text = '';
                        prefs!.setBool('isManualServerUrl', false);
                      }
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FlutterFlowTheme.of(context).primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    child: const Text('Save',
                        style: TextStyle(fontSize: 14, color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void updateToken() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.getToken().then((value) => {_notificationToken = value!});
    APIService.getUserData()
        .then((value) => {APIService.activateFCM(_notificationToken)});
  }

  void _loginPressed() async {
    List<dynamic> servers = _serverUrl.text.isEmpty
        ? SERVER_URL
        : [
            {'url': _serverUrl.text, 'type': 'free'}
          ];

    setState(() {
      isLoading = true;
    });

    bool loginSuccess = false;
    int? lastStatusCode;
    String? lastResponseBody;

    for (var server in servers) {
      try {
        final response =
            await APIService.login(server['url'], _email, _password);

        if (response != null) {
          lastStatusCode = response.statusCode;
          lastResponseBody = response.body;

          if (response.statusCode == 200) {
            UserLogin user = UserLogin.fromJson(
              jsonDecode(response.body.replaceAll("ï»¿", "")),
            );
            print(response.body);
            UserRepository.setServerUrl(server['url']);
            prefs!.setString('serverType', server['type']);

            UserRepository.setHash(user.userApiHash!);

            if (_rememberMe) {
              // Save email and password if "Remember me" is checked
              UserRepository.setEmail(_email);
              UserRepository.setPassword(_password);
              prefs!.setBool('rememberMe', true);
            } else {
              // Clear if not checked
              prefs!.remove('email');
              prefs!.remove('password');
              prefs!.setBool('rememberMe', false);
            }

            dataController.getDevices();
            updateToken();

            setState(() {
              isLoading = false;
            });

            Get.offAndToNamed('/home');
            loginSuccess = true;
            await fetchConfigAndProceed();
            break;
          }
        }
      } catch (e) {
        debugPrint('Error on ${server['url']}: $e');
      }
    }

    if (!loginSuccess) {
      setState(() {
        isLoading = false;
      });

      if (lastStatusCode == 422) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('emailAndPasswordRequired'.tr)),
        );
      } else if (lastStatusCode == 401 || lastStatusCode == 400) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('loginFailed'.tr)),
        );
      } else {
        Fluttertoast.showToast(
          msg: ("errorMsg").tr,
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.CENTER,
          timeInSecForIosWeb: 1,
          backgroundColor: Colors.black54,
          textColor: Colors.white,
          fontSize: 16.0,
        );
      }
    }
  }
}
