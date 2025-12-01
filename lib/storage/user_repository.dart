import 'package:get_storage/get_storage.dart';
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

  static String? getPassword() {
    return prefs!.getString(PREF_PASSWORD).toString();
  }

  static void setPassword(String password) {
    prefs!.setString(PREF_PASSWORD, password);
  }

  static void doLogout() {
    prefs!.clear();
  }

  static String? getServerUrl() {
    return prefs!.getString(PREF_URL);
  }

  static void setServerUrl(String url) {
    prefs!.setString(PREF_URL, url);
  }
}
