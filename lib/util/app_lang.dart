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
    if (s.isEmpty) return s;
    final sb = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final charCode = s.codeUnitAt(i);
      // '0' is 48, '9' is 57
      if (charCode >= 48 && charCode <= 57) {
        sb.writeCharCode(0x09E6 + (charCode - 48)); // 0x09E6 is '০'
      } else {
        sb.writeCharCode(charCode);
      }
    }
    return sb.toString();
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
