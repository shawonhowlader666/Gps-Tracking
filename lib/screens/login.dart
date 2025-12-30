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
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
// Import your other necessary files
import 'package:gpspro/services/model/login.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/config.dart';

import 'package:gpspro/constants/app_constants.dart';

// Define custom colors
const Color kPrimaryOrange = Color(0xFF3E6FB8);
const Color kLightGrey = Color(0xFFE0E0E0);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<double> _translateAnimation;
  late Animation<double> _shimmerAnimation;
  late AnimationController _shimmerController;

  SharedPreferences? prefs;
  final TextEditingController _emailFilter = TextEditingController();
  final TextEditingController _passwordFilter = TextEditingController();

  static const Color _primaryColor = Color(0xFF1D4888);
  static const Color _lightAccent = Color(0xFFE4B34E);

  FocusNode? emailAddressFocusNode;
  late bool passwordVisibility;
  FocusNode? passwordFocusNode;
  bool _rememberMe = true;

  DataController dataController = Get.put(DataController());

  String _email = "";
  String _password = "";
  String _notificationToken = "";
  bool isLoading = false;
  int _selectedLanguageIndex = 0;

  // Server selection variables
  List<dynamic> availableServers = [];
  Map<String, dynamic>? selectedServer;
  bool isLoadingServers = true;

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
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      _shimmerController,
    );

    _controller.forward();

    passwordVisibility = true;
    emailAddressFocusNode = FocusNode();
    passwordFocusNode = FocusNode();

    _emailFilter.addListener(_emailListen);
    _passwordFilter.addListener(_passwordListen);

    checkPreference();
    fetchServersFromFirebase();
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
    _shimmerController.dispose();
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

    if (prefs!.getString('email') != null) {
      _emailFilter.text = prefs!.getString('email')!;
      _passwordFilter.text = prefs!.getString('password')!;
      _rememberMe = prefs!.getBool('rememberMe') ?? false;
    }

    // Set initial language based on preferences
    String? langCode = prefs!.getString('language_code');
    if (langCode == 'bn') {
      _selectedLanguageIndex = 1;
    } else {
      _selectedLanguageIndex = 0;
    }
  }

  Future<void> fetchServersFromFirebase() async {
    try {
      setState(() {
        isLoadingServers = true;
      });

      prefs = await SharedPreferences.getInstance();
      var serverType = prefs!.getString('serverType') ?? 'free';


      final doc = await FirebaseFirestore.instance
          .collection('configs')
          .doc('urls')
          .get();

      if (doc.exists) {
        print('✅ Firebase document found');
        final data = doc.data() as Map<String, dynamic>;

        if (data.containsKey('spytrack')) {
          final spytrackConfig = data['spytrack'] as Map<String, dynamic>;

          if (spytrackConfig.containsKey('url')) {
            final urlData = spytrackConfig['url'];

            List<dynamic> serverList = [];

            // Handle different data types
            if (urlData is List) {
              serverList = urlData;
              print('✅ Found ${serverList.length} servers in Firebase');
              for (int i = 0; i < serverList.length; i++) {
                print('   Server ${i + 1}: ${serverList[i]['name']} - ${serverList[i]['url']}');
              }
            } else if (urlData is String) {
              try {
                serverList = jsonDecode(urlData) as List;
                print('✅ Parsed ${serverList.length} servers from JSON string');
              } catch (e) {
                print('❌ Failed to parse URL string: $e');
              }
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

            setState(() {
              availableServers = serverList;
              print('✅ Total available servers: ${availableServers.length}');

              // Set default selected server
              if (availableServers.isNotEmpty) {
                String? savedServerUrl = UserRepository.getServerUrl();

                if (savedServerUrl != null && savedServerUrl.isNotEmpty) {
                  try {
                    selectedServer = availableServers.firstWhere(
                          (server) => server['url'] == savedServerUrl,
                      orElse: () => availableServers[0],
                    );
                  } catch (e) {
                    selectedServer = availableServers[0];
                  }
                } else {
                  selectedServer = availableServers[0];
                }
                print('✅ Selected server: ${selectedServer?['name']}');
              }
              isLoadingServers = false;
            });
          }
        }
      }
    } catch (e, stackTrace) {
      print('❌ Error fetching servers: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        isLoadingServers = false;
        availableServers = [];
      });
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

        if (spytrackConfig['url'] is List) {
          SERVER_URL = spytrackConfig['url'] as List;
        }

        SHOW_ADS = (spytrackConfig['ads'] as bool) && serverType == 'free';
        WHATS_APP = spytrackConfig['whatsapp'] as String;
        PHONE_NO = spytrackConfig['phone'] as String;
        EMAIL = spytrackConfig['email'] as String;
        adsFrequency = spytrackConfig['adsfrequency'] as int;
        APP_VERSION = spytrackConfig['version'] as String;
        BANNER_IMAGE = spytrackConfig['banners'] as List;
        fuelData = spytrackConfig['fuelData'];
      }

      String? currentServerUrl = UserRepository.getServerUrl();
      for (var server in SERVER_URL) {
        if (server['url'] == currentServerUrl) {
          ALWAYS_SHOW_BANNER_ADS = server['showBannerAds'] ?? false;
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
      backgroundColor: Colors.white,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Language selector and chat icon
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SizedBox(width: 15),
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
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const Gap(20),

                      Center(
                        child: Lottie.asset(
                          'images/login.json',
                          width: 140,
                          height: 140,
                          repeat: true,
                        ),
                      ),

                      // SPYTRACK Logo
                      // Center(
                      //   child: Image.asset(
                      //     AppConstants.logoPath,
                      //     width: 250,
                      //   ),
                      // ),

                      Center(child: _buildAppTitle()),

                      // const Gap(40),
                      //
                      // // Server Selector
                      // _buildServerSelector(),

                      const Gap(20),

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
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: kLightGrey,
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

                      const Gap(60),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'images/btrc.png',
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
            AppConstants.appName,
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

  // Widget _buildServerSelector() {
  //   if (isLoadingServers) {
  //     return Center(
  //       child: Padding(
  //         padding: const EdgeInsets.all(20.0),
  //         child: Column(
  //           children: [
  //             CircularProgressIndicator(
  //               valueColor: AlwaysStoppedAnimation<Color>(kPrimaryOrange),
  //             ),
  //             SizedBox(height: 12),
  //             Text(
  //               'Loading servers...',
  //               style: TextStyle(color: Colors.grey[600], fontSize: 12),
  //             ),
  //           ],
  //         ),
  //       ),
  //     );
  //   }
  //
  //   if (availableServers.isEmpty) {
  //     return Card(
  //       elevation: 2,
  //       shape: RoundedRectangleBorder(
  //         borderRadius: BorderRadius.circular(12),
  //       ),
  //       child: Padding(
  //         padding: const EdgeInsets.all(16.0),
  //         child: Column(
  //           children: [
  //             Row(
  //               children: [
  //                 Icon(Icons.warning_amber_rounded, color: Colors.orange),
  //                 SizedBox(width: 12),
  //                 Expanded(
  //                   child: Text(
  //                     'No servers available. Please check your connection and try again.',
  //                     style: TextStyle(fontSize: 14),
  //                   ),
  //                 ),
  //               ],
  //             ),
  //             SizedBox(height: 12),
  //             ElevatedButton.icon(
  //               onPressed: () => fetchServersFromFirebase(),
  //               icon: Icon(Icons.refresh, size: 18),
  //               label: Text('Retry'),
  //               style: ElevatedButton.styleFrom(
  //                 backgroundColor: kPrimaryOrange,
  //                 foregroundColor: Colors.white,
  //                 shape: RoundedRectangleBorder(
  //                   borderRadius: BorderRadius.circular(8),
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     );
  //   }
  //
  //   return Column(
  //     crossAxisAlignment: CrossAxisAlignment.start,
  //     children: [
  //       Row(
  //         mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //         children: [
  //           Text(
  //             'Available Servers',
  //             style: TextStyle(
  //               fontSize: 14,
  //               fontWeight: FontWeight.w600,
  //               color: Colors.black87,
  //             ),
  //           ),
  //           Container(
  //             padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  //             decoration: BoxDecoration(
  //               color: kPrimaryOrange.withValues(alpha: 0.1),
  //               borderRadius: BorderRadius.circular(12),
  //             ),
  //             child: Text(
  //               '${availableServers.length} servers',
  //               style: TextStyle(
  //                 fontSize: 11,
  //                 color: kPrimaryOrange,
  //                 fontWeight: FontWeight.w600,
  //               ),
  //             ),
  //           ),
  //         ],
  //       ),
  //       const Gap(8),
  //       InkWell(
  //         onTap: () => _showServerListDialog(),
  //         child: Container(
  //           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  //           decoration: BoxDecoration(
  //             color: Colors.white,
  //             borderRadius: BorderRadius.circular(12),
  //             border: Border.all(color: kLightGrey),
  //           ),
  //           child: Row(
  //             children: [
  //               Icon(Icons.dns_outlined, color: kPrimaryOrange, size: 20),
  //               const SizedBox(width: 12),
  //               Expanded(
  //                 child: Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     Text(
  //                       selectedServer?['name'] ??
  //                           selectedServer?['url'] ??
  //                           'View All Servers',
  //                       style: TextStyle(
  //                         fontSize: 14,
  //                         fontWeight: FontWeight.w500,
  //                         color: Colors.black87,
  //                       ),
  //                       maxLines: 1,
  //                       overflow: TextOverflow.ellipsis,
  //                     ),
  //                     if (selectedServer?['type'] != null) ...[
  //                       const SizedBox(height: 2),
  //                       Text(
  //                         '${selectedServer!['type']}'.toUpperCase(),
  //                         style: TextStyle(
  //                           fontSize: 11,
  //                           color: selectedServer!['type'] == 'premium'
  //                               ? Colors.green
  //                               : Colors.grey[600],
  //                           fontWeight: FontWeight.w500,
  //                         ),
  //                       ),
  //                     ],
  //                   ],
  //                 ),
  //               ),
  //               Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
  //             ],
  //           ),
  //         ),
  //       ),
  //       const Gap(8),
  //       Container(
  //         padding: const EdgeInsets.all(12),
  //         decoration: BoxDecoration(
  //           color: Colors.blue.shade50,
  //           borderRadius: BorderRadius.circular(8),
  //           border: Border.all(color: Colors.blue.shade200),
  //         ),
  //         child: Row(
  //           children: [
  //             Icon(Icons.info_outline, color: Colors.blue, size: 18),
  //             const SizedBox(width: 8),
  //             Expanded(
  //               child: Text(
  //                 'Login will automatically try all ${availableServers.length} servers to find your account',
  //                 style: TextStyle(
  //                   fontSize: 11,
  //                   color: Colors.blue.shade900,
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     ],
  //   );
  // }

  void _showServerListDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Icon(Icons.dns, color: kPrimaryOrange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Available Servers',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          'All servers will be checked during login',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ),
            ),
            Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: availableServers.length,
                itemBuilder: (context, index) {
                  final server = availableServers[index];
                  final isSelected = selectedServer?['url'] == server['url'];
                  final hasMessage = server['message']?.isNotEmpty == true;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        selectedServer = server;
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? kPrimaryOrange.withValues(alpha: 0.1)
                            : hasMessage
                            ? Colors.red.shade50
                            : Colors.white,
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey.shade200,
                            width: 1,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          if (hasMessage)
                            Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 20,
                            )
                          else
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 20,
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  server['name'] ?? server['url'] ?? 'Unknown',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: hasMessage
                                        ? Colors.grey
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  server['url'] ?? '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (hasMessage) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    server['message'],
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red.shade700,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (server['type'] != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: server['type'] == 'premium'
                                    ? Colors.green.shade100
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${server['type']}'.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: server['type'] == 'premium'
                                      ? Colors.green.shade800
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.grey[700]),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Login will try all active servers automatically',
                        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                      ),
                    ),
                  ],
                ),
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
            labelText: 'User ID or Email',
            labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            hintText: 'User ID or Email',
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            prefixIcon:
            const Icon(Icons.mail_outline, color: Colors.grey, size: 20),
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
            labelText: 'Password',
            labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            hintText: 'Password',
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            prefixIcon: const Icon(Icons.key, color: Colors.grey, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                passwordVisibility ? Icons.visibility : Icons.visibility_off,
                color: Colors.grey,
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
      onPressed: isLoading ? null : _loginPressed,
      text: 'Sign In →',
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
        elevation: 0,
        borderSide: const BorderSide(
          color: Colors.transparent,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      showLoadingIndicator: isLoading,
    );
  }

  void updateToken() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.getToken().then((value) => {_notificationToken = value!});
    APIService.getUserData()
        .then((value) => {APIService.activateFCM(_notificationToken)});
  }

  // UPDATED LOGIN METHOD - Tries ALL servers and connects to first successful one
  void _loginPressed() async {
    if (_email.isEmpty || _password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter email and password'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (availableServers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No servers available. Please check your connection.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    print('\n' + '=' * 60);
    print('🚀 STARTING MULTI-SERVER LOGIN');
    print('=' * 60);
    print('📧 Email: $_email');
    print('🌐 Total Servers: ${availableServers.length}');
    print('=' * 60 + '\n');

    bool loginSuccess = false;
    Map<String, dynamic>? successfulServer;
    int? lastStatusCode;
    String? lastResponseBody;

    // Filter out servers with maintenance messages
    List<dynamic> activeServers = availableServers
        .where((server) => server['message']?.isEmpty != false)
        .toList();

    print('✅ Active servers (without maintenance): ${activeServers.length}\n');

    if (activeServers.isEmpty) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('All servers are under maintenance. Please try again later.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Try ALL active servers
    for (int i = 0; i < activeServers.length; i++) {
      var server = activeServers[i];
      print('┌─────────────────────────────────────────────');
      print('│ Server ${i + 1}/${activeServers.length}');
      print('├─────────────────────────────────────────────');
      print('│ Name: ${server['name']}');
      print('│ URL: ${server['url']}');
      print('│ Type: ${server['type']}');
      print('└─────────────────────────────────────────────');

      try {
        print('   🔄 Attempting login...');

        final response =
        await APIService.login(server['url'], _email, _password);

        if (response != null) {
          lastStatusCode = response.statusCode;
          lastResponseBody = response.body;

          print('   📥 Response Code: ${response.statusCode}');

          if (response.statusCode == 200) {
            print('   ✅ SUCCESS! Login successful on this server!');
            print('   🎉 User data received\n');

            try {
              UserLogin user = UserLogin.fromJson(
                jsonDecode(response.body.replaceAll("ï»¿", "")),
              );

              // Save server configuration
              UserRepository.setServerUrl(server['url']);
              prefs!.setString('serverType', server['type'] ?? 'free');
              UserRepository.setHash(user.userApiHash!);

              // Handle remember me
              if (_rememberMe) {
                UserRepository.setEmail(_email);
                UserRepository.setPassword(_password);
                prefs!.setBool('rememberMe', true);
              } else {
                prefs!.remove('email');
                prefs!.remove('password');
                prefs!.setBool('rememberMe', false);
              }

              loginSuccess = true;
              successfulServer = server;

              // Update selected server in UI
              setState(() {
                selectedServer = server;
              });

              print('=' * 60);
              print('🎊 LOGIN SUCCESSFUL!');
              print('=' * 60);
              print('Connected to: ${server['name']}');
              print('Server URL: ${server['url']}');
              print('User Hash: ${user.userApiHash}');
              print('=' * 60 + '\n');

              break; // Stop trying other servers
            } catch (e) {
              print('   ❌ Error parsing user data: $e');
              continue; // Try next server
            }
          } else if (response.statusCode == 401 || response.statusCode == 400) {
            print('   ⚠️ Invalid credentials on this server');
          } else if (response.statusCode == 422) {
            print('   ⚠️ Validation error: ${response.statusCode}');
          } else {
            print('   ❌ Failed with status: ${response.statusCode}');
          }
        } else {
          print('   ❌ No response from server (connection failed)');
        }
      } catch (e) {
        print('   ❌ Exception: $e');
      }

      print(''); // Empty line between server attempts
    }

    setState(() {
      isLoading = false;
    });

    if (loginSuccess && successfulServer != null) {
      // Login successful
      print('🎯 Proceeding with successful login...\n');

      dataController.getDevices();
      updateToken();

      await fetchConfigAndProceed();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Login Successful!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Connected to ${successfulServer['name']}',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      Get.offAndToNamed('/home');
    } else {
      // Login failed on all servers
      print('=' * 60);
      print('❌ LOGIN FAILED ON ALL SERVERS');
      print('=' * 60);
      print('Total servers tried: ${activeServers.length}');
      print('Last status code: $lastStatusCode');
      print('=' * 60 + '\n');

      if (lastStatusCode == 422) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Email and password are required'),
            backgroundColor: Colors.orange,
          ),
        );
      } else if (lastStatusCode == 401 || lastStatusCode == 400) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Login Failed',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Invalid credentials. Checked ${activeServers.length} servers.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        Fluttertoast.showToast(
          msg:
          "Login failed on all ${activeServers.length} servers.\nPlease check your credentials and connection.",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.CENTER,
          backgroundColor: Colors.black87,
          textColor: Colors.white,
          fontSize: 14.0,
        );
      }
    }
  }
}