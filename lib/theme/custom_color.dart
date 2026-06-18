import 'package:flutter/material.dart';
import 'package:from_css_color/from_css_color.dart';


const Color MAPS_IMAGES_COLOR = Color(0xFF0a4349);
const Color YELLOW_CUSTOM = Color(0xffFFAC00);

class CustomColor {
  static var primaryColor = MaterialColor(0xFFFF0000, color);
  static const Color primary = Color(0xFFFF0000);
  static var secondaryColor = Colors.white;
  static var onColor = const Color(0xFF00C853);
  static var offColor = const Color(0xFF475569);
  static var cssBlack = fromCssColor('#252525');
}

Map<int, Color> color = {
  50: const Color.fromRGBO(255, 0, 0, .1),
  100: const Color.fromRGBO(255, 0, 0, .2),
  200: const Color.fromRGBO(255, 0, 0, .3),
  300: const Color.fromRGBO(255, 0, 0, .4),
  400: const Color.fromRGBO(255, 0, 0, .5),
  500: const Color.fromRGBO(255, 0, 0, .6),
  600: const Color.fromRGBO(255, 0, 0, .7),
  700: const Color.fromRGBO(255, 0, 0, .8),
  800: const Color.fromRGBO(255, 0, 0, .9),
  900: const Color.fromRGBO(255, 0, 0, 1),
};
