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

  static String? getPhone() {
    return prefs!.getString(PREF_USER_PHONE);
  }

  static void setPhone(String phone) {
    prefs!.setString(PREF_USER_PHONE, phone);
  }

  static String? getCompanyName() {
    return prefs!.getString(PREF_COMPANY_NAME);
  }

  static void setCompanyName(String companyName) {
    prefs!.setString(PREF_COMPANY_NAME, companyName);
  }

  static String? getUserId() {
    return prefs!.getString(PREF_USER_ID);
  }

  static void setUserId(String userId) {
    prefs!.setString(PREF_USER_ID, userId);
  }

  static Map<String, String?> getAllUserDetails() {
    return {
      'email': getEmail(),
      'name': getName(),
      'phone': getPhone(),
      'company': getCompanyName(),
    };
  }

  static void doLogout() {
    _sessionPassword = null;
    prefs!.clear();
  }

  static String? getServerUrl() {
    return prefs!.getString(PREF_URL);
  }

  static void setServerUrl(String url) {
    prefs!.setString(PREF_URL, url);
  }

  // ==================== TRACKSOLID API MODE ====================

  /// Returns "traccar" (default) or "tracksolid"
  static String getApiMode() {
    return prefs!.getString(PREF_API_MODE) ?? 'traccar';
  }

  static void setApiMode(String mode) {
    prefs!.setString(PREF_API_MODE, mode);
  }

  static bool isTracksolidMode() {
    return getApiMode() == 'tracksolid';
  }

  static String? getTracksolidToken() {
    return prefs!.getString(PREF_TRACKSOLID_TOKEN);
  }

  static void setTracksolidToken(String token) {
    prefs!.setString(PREF_TRACKSOLID_TOKEN, token);
  }

  static void clearTracksolidToken() {
    prefs!.remove(PREF_TRACKSOLID_TOKEN);
  }

  static String? getTracksolidAccount() {
    return prefs!.getString(PREF_TRACKSOLID_ACCOUNT);
  }

  static void setTracksolidAccount(String account) {
    prefs!.setString(PREF_TRACKSOLID_ACCOUNT, account);
  }
}