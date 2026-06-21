import 'package:flutter/material.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:marquee_widget/marquee_widget.dart';

// Global cache for address lookup futures to avoid duplicate network requests on rebuilds
final Map<String, Future<String>> _addressFutureCache = {};

Future<String> _getGeocoderAddressCached(String lat, String lng) {
  final key = '$lat,$lng';
  return _addressFutureCache.putIfAbsent(key, () => APIService.getGeocoderAddress(lat, lng));
}

Widget addressLoad(String lat, lng) {
  return FutureBuilder<String>(
      future: _getGeocoderAddressCached(lat, lng),
      builder: (context, AsyncSnapshot<String> snapshot) {
        if (snapshot.hasData) {
          return Text(
            snapshot.data!.replaceAll('"', ''),
            style: const TextStyle(
                color: Colors.black, fontSize: 12),
          );
        } else {
          return const Text("...");
        }
      });
}

Widget addressLoadMarque(String lat, lng) {
  return FutureBuilder<String>(
      future: _getGeocoderAddressCached(lat, lng),
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
