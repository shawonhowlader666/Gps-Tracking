import 'package:flutter/material.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/theme/custom_color.dart';
import 'package:marquee_widget/marquee_widget.dart';

Widget addressLoad(String lat, lng) {
  return FutureBuilder<String>(
      future: APIService.getGeocoderAddress(lat, lng),
      builder: (context, AsyncSnapshot<String> snapshot) {
        if (snapshot.hasData) {
          return Text(
            snapshot.data!.replaceAll('"', ''),
            style: const TextStyle(
                color: Colors.black, fontFamily: "Popins", fontSize: 12),
          );
        } else {
          return const Text("...");
        }
      });
}

Widget addressLoadMarque(String lat, lng) {
  return FutureBuilder<String>(
      future: APIService.getGeocoderAddress(lat, lng),
      builder: (context, AsyncSnapshot<String> snapshot) {
        if (snapshot.hasData) {
          return Marquee(
            direction: Axis.horizontal,
            textDirection: TextDirection.ltr,
            animationDuration: const Duration(seconds: 4),
            backDuration: const Duration(seconds: 1000),
            pauseDuration: const Duration(milliseconds: 1000),
            directionMarguee: DirectionMarguee.oneDirection,
            child: Text(snapshot.data!.replaceAll('"', ''),
                style: TextStyle(color: CustomColor.cssBlack, fontSize: 13)),
          );
        } else {
          return const Text("...");
        }
      });
}
