import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'lang/es.dart';
import 'lang/pt.dart';
import 'lang/te_IN.dart';
import 'lang/bn_BD.dart';

import 'lang/en_US.dart';

class TranslationService extends Translations {
  static Locale? get locale => Get.deviceLocale;
  static const fallbackLocale = Locale('en', '');
  @override
  Map<String, Map<String, String>> get keys =>
      {'en': en_US, 'te': te_IN, 'pt': pt, 'es': es, 'bn': bn_BD};
}
