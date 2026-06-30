import 'package:smart_lock/preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserRepository {
  static SharedPreferences? prefs;

  static String? getLanguage() {
    return prefs!.getString(PREF_LANGUAGE);
  }

  static void setLanguage(String lang) {
    prefs!.setString(PREF_LANGUAGE, lang);
  }

  static String? getHash() {
    return prefs!.getString(PREF_API_HASH);
  }

  static void setHash(String hash) {
    prefs!.setString(PREF_API_HASH, hash);
  }

  static String? _sessionEmail;
  static String? _sessionPassword;

  static String? getEmail() {
    final email = prefs!.getString(PREF_USER_EMAIL);
    if (email == null || email == 'null') {
      return _sessionEmail;
    }
    return email;
  }

  static void setEmail(String email) {
    // Sanitize before persisting: strip any corrupted suffix such as
    // ") - Bike (IMEI: N/A, SIM: ...)" that can accumulate via stale cache.
    String clean = email;
    final parenIdx = clean.indexOf(')');
    if (parenIdx != -1) {
      final candidate = clean.substring(0, parenIdx).trim();
      if (candidate.isNotEmpty) clean = candidate;
    } else {
      final dashIdx = clean.indexOf(' - ');
      if (dashIdx != -1) {
        final candidate = clean.substring(0, dashIdx).trim();
        if (candidate.isNotEmpty) clean = candidate;
      }
    }
    prefs!.setString(PREF_USER_EMAIL, clean);
    _sessionEmail = clean;
  }

  static String? getName() {
    return prefs!.getString(PREF_USER_NAME);
  }

  static void setName(String name) {
    prefs!.setString(PREF_USER_NAME, name);
  }

  static String? getPassword() {
    final pass = prefs!.getString(PREF_PASSWORD);
    if (pass == null || pass == 'null') {
      return _sessionPassword;
    }
    return pass;
  }

  static void setPassword(String password) {
    prefs!.setString(PREF_PASSWORD, password);
    _sessionPassword = password;
  }

  static void setSessionPassword(String password) {
    _sessionPassword = password;
  }

  static void clearSessionPassword() {
    _sessionPassword = null;
  }

  // NEW: Phone number
  static String? getPhone() {
    return prefs!.getString(PREF_USER_PHONE);
  }

  static void setPhone(String phone) {
    prefs!.setString(PREF_USER_PHONE, phone);
  }

  // NEW: Company name
  static String? getCompanyName() {
    return prefs!.getString(PREF_COMPANY_NAME);
  }

  static void setCompanyName(String companyName) {
    prefs!.setString(PREF_COMPANY_NAME, companyName);
  }

  // NEW: User ID
  static String? getUserId() {
    return prefs!.getString(PREF_USER_ID);
  }

  static void setUserId(String userId) {
    prefs!.setString(PREF_USER_ID, userId);
  }

  // NEW: Get all user details for PDF
  static Map<String, String?> getAllUserDetails() {
    return {
      'email': getEmail(),
      'name': getName(),
      'phone': getPhone(),
      'company': getCompanyName(),
    };
  }

  static void doLogout() {
    prefs!.clear();
    _sessionPassword = null;
    _sessionEmail = null;
  }

  static String? getServerUrl() {
    return prefs!.getString(PREF_URL);
  }

  static void setServerUrl(String url) {
    prefs!.setString(PREF_URL, url);
  }
}
