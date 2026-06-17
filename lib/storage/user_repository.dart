import 'package:gpspro/preference.dart';
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

  static String? getEmail() {
    return prefs!.getString(PREF_USER_EMAIL);
  }

  static void setEmail(String email) {
    prefs!.setString(PREF_USER_EMAIL, email);
  }

  static String? getName() {
    return prefs!.getString(PREF_USER_NAME);
  }

  static void setName(String name) {
    prefs!.setString(PREF_USER_NAME, name);
  }

  static String? _sessionPassword; // in-memory only, not persisted

  static String? getPassword() {
    // First try persisted (rememberMe), then fall back to session memory
    return prefs!.getString(PREF_PASSWORD) ?? _sessionPassword;
  }

  static void setPassword(String password) {
    prefs!.setString(PREF_PASSWORD, password);
  }

  static void setSessionPassword(String password) {
    // Always store in memory for payment service (not persisted to disk)
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
    _sessionPassword = null; // clear memory password on logout
    prefs!.clear();
  }

  static String? getServerUrl() {
    return prefs!.getString(PREF_URL);
  }

  static void setServerUrl(String url) {
    prefs!.setString(PREF_URL, url);
  }
}