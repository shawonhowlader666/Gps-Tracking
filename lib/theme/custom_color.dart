import 'package:flutter/material.dart';
import 'package:from_css_color/from_css_color.dart';


const Color MAPS_IMAGES_COLOR = Color(0xFF0a4349);
const Color YELLOW_CUSTOM = Color(0xffFFAC00);

class CustomColor {
  static var primaryColor = MaterialColor(0xFF1B851C, color);
  static var primary= const Color(0xFF1B851C);
  static var secondaryColor = Colors.white;
  static var onColor = Colors.green;
  static var offColor = Colors.grey;
  static var cssBlack = fromCssColor('#252525');
}

Map<int, Color> color = {
  50: const Color.fromRGBO(27, 133, 28, .1),
  100: const Color.fromRGBO(27, 133, 28, .2),
  200: const Color.fromRGBO(27, 133, 28, .3),
  300: const Color.fromRGBO(27, 133, 28, .4),
  400: const Color.fromRGBO(27, 133, 28, .5),
  500: const Color.fromRGBO(27, 133, 28, .6),
  600: const Color.fromRGBO(27, 133, 28, .7),
  700: const Color.fromRGBO(27, 133, 28, .8),
  800: const Color.fromRGBO(27, 133, 28, .9),
  900: const Color.fromRGBO(27, 133, 28, 1),
};
