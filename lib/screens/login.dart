import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';
import 'package:gpspro/screens/server_maintenance_screen.dart';
import 'package:gpspro/services/admob_service.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:gpspro/services/model/login.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/config.dart';
import 'package:gpspro/constants/app_constants.dart';
import 'package:gpspro/widgets/scale_button.dart';

const Color kPrimaryOrange = Color(0xFF1B851C);
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

  static const Color _primaryColor = Color(0xFF1B851C);
  static const Color _lightAccent = Color(0xFFB30B0B);

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

  List<dynamic> availableServers = [];
  Map<String, dynamic>? selectedServer;
  bool isLoadingServers = true;

  @override
  void initState() {
    super.initState();

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
        final data = doc.data() as Map<String, dynamic>;

        if (data.containsKey('spytrack')) {
          final spytrackConfig = data['spytrack'] as Map<String, dynamic>;

          if (spytrackConfig.containsKey('url')) {
            final urlData = spytrackConfig['url'];

            List<dynamic> serverList = [];

            if (urlData is List) {
              serverList = urlData;
            } else if (urlData is String) {
              try {
                serverList = jsonDecode(urlData) as List;
              } catch (e) {}
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
              }
              isLoadingServers = false;
            });
          }
        }
      }
    } catch (e) {
      setState(() {
        isLoadingServers = false;
        availableServers = [];
      });
    }
  }

  Future<void> _callSupportPhone() async {
    if (PHONE_NO.isEmpty) {
      Get.snackbar("Sorry!", "Phone number not available");
      return;
    }

    final Uri uri = Uri.parse('tel:$PHONE_NO');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        Get.snackbar("Error", "Phone call not supported on this device");
      }
    } catch (e) {
      Get.snackbar("Error", "Failed to open phone app");
    }
  }

  Future<void> _openWhatsAppSupport() async {
    if (WHATS_APP.isEmpty) {
      Get.snackbar("Sorry!", "WhatsApp not available");
      return;
    }

    final cleanNumber = WHATS_APP.replaceAll(RegExp(r'[^0-9]'), '');
    final Uri uri = Uri.parse('https://wa.me/$cleanNumber');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        Get.snackbar("Error", "WhatsApp not installed");
      }
    } catch (e) {
      Get.snackbar("Error", "Failed to open WhatsApp");
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
    } catch (e) {}
  }

  // ==================== ADD NEW SERVER DIALOG ====================
  // void _showAddServerDialog() {
  //   final TextEditingController nameController = TextEditingController();
  //   final TextEditingController urlController = TextEditingController();
  //   final TextEditingController typeController = TextEditingController(text: 'free');
  //   bool showBannerAds = false;
  //   bool isSaving = false;
  //
  //   showDialog(
  //     context: context,
  //     builder: (dialogContext) => StatefulBuilder(
  //       builder: (context, setDialogState) => AlertDialog(
  //         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  //         title: Row(
  //           children: [
  //             Icon(Icons.add_circle_outline, color: kPrimaryOrange),
  //             const SizedBox(width: 10),
  //             const Text(
  //               'Add New Server',
  //               style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
  //             ),
  //           ],
  //         ),
  //         content: SingleChildScrollView(
  //           child: Column(
  //             mainAxisSize: MainAxisSize.min,
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               // Server Name
  //               TextField(
  //                 controller: nameController,
  //                 decoration: InputDecoration(
  //                   labelText: 'Server Name',
  //                   hintText: 'e.g., Main Server',
  //                   prefixIcon: Icon(Icons.dns, color: Colors.grey[600]),
  //                   border: OutlineInputBorder(
  //                     borderRadius: BorderRadius.circular(12),
  //                   ),
  //                   contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  //                 ),
  //               ),
  //               const SizedBox(height: 16),
  //
  //               // Server URL
  //               TextField(
  //                 controller: urlController,
  //                 decoration: InputDecoration(
  //                   labelText: 'Server URL',
  //                   hintText: 'https://example.com',
  //                   prefixIcon: Icon(Icons.link, color: Colors.grey[600]),
  //                   border: OutlineInputBorder(
  //                     borderRadius: BorderRadius.circular(12),
  //                   ),
  //                   contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  //                 ),
  //                 keyboardType: TextInputType.url,
  //               ),
  //               const SizedBox(height: 16),
  //
  //               // Server Type
  //               DropdownButtonFormField<String>(
  //                 value: typeController.text,
  //                 decoration: InputDecoration(
  //                   labelText: 'Server Type',
  //                   prefixIcon: Icon(Icons.category, color: Colors.grey[600]),
  //                   border: OutlineInputBorder(
  //                     borderRadius: BorderRadius.circular(12),
  //                   ),
  //                   contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  //                 ),
  //                 items: ['free', 'paid'].map((type) {
  //                   return DropdownMenuItem(
  //                     value: type,
  //                     child: Text(type.toUpperCase()),
  //                   );
  //                 }).toList(),
  //                 onChanged: (value) {
  //                   if (value != null) {
  //                     typeController.text = value;
  //                   }
  //                 },
  //               ),
  //               const SizedBox(height: 16),
  //
  //               // Show Banner Ads
  //               Row(
  //                 children: [
  //                   Checkbox(
  //                     value: showBannerAds,
  //                     activeColor: kPrimaryOrange,
  //                     onChanged: (value) {
  //                       setDialogState(() {
  //                         showBannerAds = value ?? false;
  //                       });
  //                     },
  //                   ),
  //                   const Text('Show Banner Ads'),
  //                 ],
  //               ),
  //             ],
  //           ),
  //         ),
  //         actions: [
  //           TextButton(
  //             onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
  //             child: Text(
  //               'Cancel',
  //               style: TextStyle(color: Colors.grey[600]),
  //             ),
  //           ),
  //           ElevatedButton(
  //             onPressed: isSaving
  //                 ? null
  //                 : () async {
  //               if (nameController.text.trim().isEmpty ||
  //                   urlController.text.trim().isEmpty) {
  //                 Get.snackbar(
  //                   'Error',
  //                   'Please fill all required fields',
  //                   backgroundColor: Colors.red,
  //                   colorText: Colors.white,
  //                 );
  //                 return;
  //               }
  //
  //               setDialogState(() => isSaving = true);
  //
  //               await _addServerToFirebase(
  //                 name: nameController.text.trim(),
  //                 url: urlController.text.trim(),
  //                 type: typeController.text.trim(),
  //                 showBannerAds: showBannerAds,
  //               );
  //
  //               setDialogState(() => isSaving = false);
  //
  //               if (dialogContext.mounted) {
  //                 Navigator.pop(dialogContext);
  //               }
  //
  //               await fetchServersFromFirebase();
  //             },
  //             style: ElevatedButton.styleFrom(
  //               backgroundColor: kPrimaryOrange,
  //               shape: RoundedRectangleBorder(
  //                 borderRadius: BorderRadius.circular(12),
  //               ),
  //             ),
  //             child: isSaving
  //                 ? const SizedBox(
  //               width: 16,
  //               height: 16,
  //               child: CircularProgressIndicator(
  //                 strokeWidth: 2,
  //                 valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
  //               ),
  //             )
  //                 : const Text(
  //               'Add Server',
  //               style: TextStyle(color: Colors.white),
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  // Future<void> _addServerToFirebase({
  //   required String name,
  //   required String url,
  //   required String type,
  //   required bool showBannerAds,
  // }) async {
  //   try {
  //     final docRef = FirebaseFirestore.instance.collection('configs').doc('urls');
  //
  //     final newServer = {
  //       'name': name,
  //       'url': url,
  //       'type': type,
  //       'showBannerAds': showBannerAds,
  //       'message': '',
  //     };
  //
  //     await docRef.update({
  //       'spytrack.url': FieldValue.arrayUnion([newServer])
  //     });
  //
  //     Get.snackbar(
  //       'Success',
  //       'Server added successfully!',
  //       backgroundColor: Colors.green,
  //       colorText: Colors.white,
  //       snackPosition: SnackPosition.BOTTOM,
  //       icon: const Icon(Icons.check_circle, color: Colors.white),
  //     );
  //   } catch (e) {
  //     Get.snackbar(
  //       'Error',
  //       'Failed to add server: $e',
  //       backgroundColor: Colors.red,
  //       colorText: Colors.white,
  //       snackPosition: SnackPosition.BOTTOM,
  //     );
  //   }
  // }

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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Admin Button (Add Server)
                          ScaleButton(
                            onTap: () {},
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: kLightGrey, width: 1),
                              ),
                              child: const Icon(
                                Icons.settings,
                                size: 20,
                                color: kPrimaryOrange,
                              ),
                            ),
                          ),

                          // Language Toggle
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: kLightGrey, width: 1),
                            ),
                            child: Row(
                              children: [
                                ScaleButton(
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
                                ScaleButton(
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

                          // Support Button
                          ScaleButton(
                            onTap: () async {
                              if (WHATS_APP.isNotEmpty) {
                                await _openWhatsAppSupport();
                              } else if (PHONE_NO.isNotEmpty) {
                                await _callSupportPhone();
                              } else {
                                Get.snackbar("Sorry!", "Support not available right now");
                              }
                            },
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: kLightGrey, width: 1),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.support_agent_outlined,
                                  size: 20,
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

                      Center(child: _buildAppTitle()),

                      const Gap(20),

                      Text(
                        'Sign in',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),

                      const Gap(24),

                      _buildLoginForm(),

                      const Gap(20),

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
                                color: _rememberMe ? kPrimaryOrange : Colors.white,
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

                      _buildLoginButton(),

                      const Gap(10),

                      Center(
                        child: ScaleButton(
                          onTap: () {},
                          child: TextButton(
                            onPressed: () {},
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
      bottomNavigationBar: _buildBtrcApproval(),
    );
  }

  Widget _buildBtrcApproval() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'images/asthax.png',
            height: 30,
            width: 30,
          ),
          const SizedBox(width: 8),
          Text(
            'Approved By AsthaX',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppTitle() {
    return Image.asset(
      'images/onfleet_logo.png',
      height: 45,
      fit: BoxFit.contain,
    );
  }

  Widget _buildLoginForm() {
    return Column(
      children: [
        TextField(
          controller: _emailFilter,
          focusNode: emailAddressFocusNode,
          style: const TextStyle(color: Colors.black, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'User ID or Email',
            labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            hintText: 'User ID or Email',
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            prefixIcon: const Icon(Icons.mail_outline, color: Colors.grey, size: 20),
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
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => passwordFocusNode?.requestFocus(),
        ),

        const Gap(16),

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
              onPressed: () => setState(() => passwordVisibility = !passwordVisibility),
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
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _loginPressed(),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return ScaleButton(
      onTap: isLoading ? null : _loginPressed,
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: isLoading ? null : () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: isLoading ? Colors.grey.shade400 : kPrimaryOrange,
            disabledBackgroundColor: Colors.grey.shade400,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: isLoading
              ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
              : const Text(
            'Sign In →',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  void updateToken() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.getToken().then((value) => {_notificationToken = value!});
    APIService.getUserData().then((user) {
      if (user != null) {
        if (user.id != null) UserRepository.setUserId(user.id.toString());
        if (user.email != null) UserRepository.setEmail(user.email!);
        if (user.username != null) UserRepository.setName(user.username!);
      }
      APIService.activateFCM(_notificationToken);
    });
  }

  void _loginPressed() async {
    if (_email.trim().isEmpty || _password.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter email and password'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (availableServers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No servers available. Please try again later.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => isLoading = true);

    bool loginSuccess = false;
    Map<String, dynamic>? successfulServer;
    int? lastStatusCode;

    String? apiErrorMessage;

    try {
      final List<dynamic> activeServers = availableServers
          .where((s) => s['message'] == null || s['message'].toString().isEmpty)
          .toList();

      if (activeServers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All servers are under maintenance'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      for (final server in activeServers) {
        try {
          final response = await APIService.login(server['url'], _email, _password);

          if (response == null) continue;

          lastStatusCode = response.statusCode;

          if (response.statusCode == 200) {
            final jsonMap = jsonDecode(response.body.replaceAll("ï»¿", ""));
            final user = UserLogin.fromJson(jsonMap);

            if (user.userApiHash != null) {
              UserRepository.setServerUrl(server['url']);
              UserRepository.setHash(user.userApiHash!);
              prefs?.setString('serverType', server['type'] ?? 'free');

              if (_rememberMe) {
                UserRepository.setEmail(_email);
                UserRepository.setPassword(_password);
                prefs?.setBool('rememberMe', true);
              } else {
                prefs?.remove('email');
                prefs?.remove('password');
                prefs?.setBool('rememberMe', false);
              }

              successfulServer = server;
              loginSuccess = true;
              break;
            } else {
              apiErrorMessage = jsonMap['message']?.toString();
            }
          }
        } catch (_) {
          continue;
        }
      }
    } finally {
      setState(() => isLoading = false);
    }

    if (loginSuccess && successfulServer != null) {
      dataController.getDevices();
      updateToken();
      await fetchConfigAndProceed();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Login successful (${successfulServer['name'] ?? 'Server'})',
                ),
              ),
            ],
          ),
        ),
      );

      Get.offAndToNamed('/home');
    } else {
      String message = apiErrorMessage ?? 'Login failed. Please check credentials.';

      if (lastStatusCode == 401 || lastStatusCode == 400) {
        message = 'Invalid email or password';
      } else if (lastStatusCode == 422) {
        message = 'Email and password are required';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}