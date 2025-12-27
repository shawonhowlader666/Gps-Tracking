import 'package:flutter/material.dart';
import 'package:from_css_color/from_css_color.dart';


const Color MAPS_IMAGES_COLOR = Color(0xFF0a4349);
const Color YELLOW_CUSTOM = Color(0xffFFAC00);

class CustomColor {
  static var primaryColor = MaterialColor(0xFF39a4db, color);
  static var primary= Color(0xFF4478C5);
  static var secondaryColor = Colors.white;
  static var onColor = Colors.green;
  static var offColor = Colors.grey;
  static var cssBlack = fromCssColor('#252525');
}

Map<int, Color> color = {
  50: Color.fromRGBO(57, 164, 219, .1),
  100: Color.fromRGBO(57, 164, 219, .2),
  200: Color.fromRGBO(57, 164, 219, .3),
  300: Color.fromRGBO(57, 164, 219, .4),
  400: Color.fromRGBO(57, 164, 219, .5),
  500: Color.fromRGBO(57, 164, 219, .6),
  600: Color.fromRGBO(57, 164, 219, .7),
  700: Color.fromRGBO(57, 164, 219, .8),
  800: Color.fromRGBO(57, 164, 219, .9),
  900: Color.fromRGBO(57, 164, 219, 1),
};
