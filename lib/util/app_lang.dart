import 'package:get/get.dart';

/// Central app localization helper.
/// Use [AppLang.isBn] to check locale and [AppLang.num] to convert to Bangla numerals.
class AppLang {
  AppLang._();

  /// Returns true when Bengali locale is active.
  static bool get isBn => Get.locale?.languageCode == 'bn';

  // ── Numeral conversion ─────────────────────────────────────────────────────

  /// Convert any number or string to Bangla numerals when Bengali is active.
  static String num(dynamic value) {
    final str = value.toString();
    if (!isBn) return str;
    return _toBanglaDigits(str);
  }

  static String _toBanglaDigits(String s) {
    const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const bn = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    var result = s;
    for (int i = 0; i < en.length; i++) {
      result = result.replaceAll(en[i], bn[i]);
    }
    return result;
  }

  // ── Device status ──────────────────────────────────────────────────────────
  static String get unlimited    => isBn ? 'সীমাহীন'       : 'Unlimited';
  static String get expiresToday => isBn ? 'আজ মেয়াদ শেষ' : 'Expires Today';

  static String daysRemaining(int days) =>
      isBn ? '${_toBanglaDigits(days.toString())} দিন বাকি' : '$days Days Remaining';

  // ── Speed ──────────────────────────────────────────────────────────────────
  static String get speedUnit => isBn ? 'কি.মি./ঘ.' : 'KM/H';
  static String get kmUnit    => isBn ? 'কি.মি.'    : 'Km';

  // ── Address ────────────────────────────────────────────────────────────────
  static String get loadingAddress => isBn ? 'ঠিকানা লোড হচ্ছে...' : 'Loading address...';
  static String get noAddress      => isBn ? 'ঠিকানা পাওয়া যায়নি' : 'Address not found';
}
