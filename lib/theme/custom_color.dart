import 'package:flutter/material.dart';
import 'package:from_css_color/from_css_color.dart';


const Color MAPS_IMAGES_COLOR = Color(0xFF0a4349);
const Color YELLOW_CUSTOM = Color(0xffFFAC00);

class CustomColor {
  static var primaryColor = MaterialColor(0xFF8B1A1A, color);
  static const Color primary = Color(0xFF8B1A1A);
  static var secondaryColor = Colors.white;
  static var onColor = Colors.green;
  static var offColor = Colors.grey;
  static var cssBlack = fromCssColor('#252525');
}

Map<int, Color> color = {
  50: const Color.fromRGBO(139, 26, 26, .1),
  100: const Color.fromRGBO(139, 26, 26, .2),
  200: const Color.fromRGBO(139, 26, 26, .3),
  300: const Color.fromRGBO(139, 26, 26, .4),
  400: const Color.fromRGBO(139, 26, 26, .5),
  500: const Color.fromRGBO(139, 26, 26, .6),
  600: const Color.fromRGBO(139, 26, 26, .7),
  700: const Color.fromRGBO(139, 26, 26, .8),
  800: const Color.fromRGBO(139, 26, 26, .9),
  900: const Color.fromRGBO(139, 26, 26, 1),
};
