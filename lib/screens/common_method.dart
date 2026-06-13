import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

String formatTime(String time) {
  DateTime lastUpdate = DateTime.parse(time);
  return DateFormat('dd-MM-yyyy hh:mm:ss aa').format(lastUpdate.toLocal());
}

String formatDateReport(String date) {
  DateTime lastUpdate = DateTime.parse(date);
  String month, day;
  if (lastUpdate.month < 10) {
    month = "0${lastUpdate.month}";
  } else {
    month = lastUpdate.month.toString();
  }

  if (lastUpdate.day < 10) {
    day = "0${lastUpdate.day}";
  } else {
    day = lastUpdate.day.toString();
  }

  return "${lastUpdate.year}-$month-$day";
}

String formatTimeReport(String date) {
  DateTime lastUpdate = DateTime.parse(date);
  String hour, minute;
  if (lastUpdate.month < 10) {
    hour = "0${lastUpdate.month}";
  } else {
    minute = lastUpdate.month.toString();
  }

  if (lastUpdate.hour < 10) {
    hour = "0${lastUpdate.hour}";
  } else {
    hour = lastUpdate.hour.toString();
  }

  if (lastUpdate.minute < 10) {
    minute = "0${lastUpdate.minute}";
  } else {
    minute = lastUpdate.minute.toString();
  }
  return "$hour:$minute:00";
}

DateTime formatGetDateTime(String date) {
  DateFormat inputFormat = DateFormat("yyyy-MM-dd HH:mm:ss");
  DateTime lastUpdate = inputFormat.parse(date);
  return lastUpdate;
}

String formatInvalidDate(String date) {
  DateFormat inputFormat = DateFormat("dd-MM-yyyy HH:mm:ss");
  DateTime lastUpdate = inputFormat.parse(date);
  return DateFormat('yyyy-MM-dd').format(lastUpdate.toLocal());
}

String formatInvalidTime(String date) {
  DateFormat inputFormat = DateFormat("MM-dd-yyyy HH:mm:ss");
  DateTime lastUpdate = inputFormat.parse(date);
  return DateFormat('HH:mm:ss').format(lastUpdate.toLocal());
}

String convertSpeed(var speed, String type) {
  // double factor = 1.852;
  // double floatSpeed = (speed * factor);
  return "${speed.toInt()} $type";
}

String convertDistance(double distance) {
  double calcDistance = distance / 1000;
  return "${calcDistance.toStringAsFixed(2)} Km";
}

String convertDuration(int duration) {
  double hours = duration / 3600000;
  double minutes = duration % 3600000 / 60000;
  return "${hours.toInt()} hr ${minutes.toInt()} min";
}

Future<Uint8List?> getBytesFromAsset(String path, int width) async {
  if (path.isNotEmpty) {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
        targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } else {
    return null;
  }
}

Future<Uint8List?> getBytesFromBytes(var data, int width) async {
  if (data != null) {
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
        targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } else {
    return null;
  }
}

LatLngBounds boundsFromLatLngList(Set<Marker> list) {
  assert(list.isNotEmpty);
  double? x0, x1, y0, y1;
  for (var value in list) {
    if (x0 == null) {
      x0 = x1 = value.position.latitude;
      y0 = y1 = value.position.longitude;
    } else {
      if (value.position.latitude > x1!) x1 = value.position.latitude;
      if (value.position.latitude < x0!) x0 = value.position.latitude;
      if (value.position.longitude > y1!) y1 = value.position.longitude;
      if (value.position.longitude < y0!) y0 = value.position.longitude;
    }
  }
  return LatLngBounds(northeast: LatLng(x1!, y1!), southwest: LatLng(x0!, y0!));
}

LatLngBounds boundsFromLatLngGeofenceList(Set<Marker> list) {
  assert(list.isNotEmpty);
  double? x0, x1, y0, y1;
  for (var value in list) {
    if (x0 == null) {
      x0 = x1 = value.position.latitude;
      y0 = y1 = value.position.longitude;
    } else {
      if (value.position.latitude > x1!) x1 = value.position.latitude;
      if (value.position.latitude < x0!) x0 = value.position.latitude;
      if (value.position.longitude > y1!) y1 = value.position.longitude;
      if (value.position.longitude < y0!) y0 = value.position.longitude;
    }
  }
  return LatLngBounds(northeast: LatLng(x1!, y1!), southwest: LatLng(x0!, y0!));
}

Future<BitmapDescriptor> getBitmapDescriptorFromAssetBytes(
    String color, String path, int width) async {
  final Uint8List? imageData = await getBytesFromAsset(path, width);
  return BitmapDescriptor.bytes(imageData!);
}

Future<BitmapDescriptor> getBitmapDescriptorFromBytes(
    var path, int width, context) async {
  final Uint8List? image = await getBytesFromBytes(path, width);
  var decodedImage = await decodeImageFromList(image!);
  if (decodedImage.clone().height < 70) {
    double devicePixelRatio = MediaQuery.of(context).size.width / 2.5;
    Uint8List? imageData =
        await getBytesFromBytes(path, devicePixelRatio.toInt());
    return BitmapDescriptor.bytes(imageData!);
  } else {
    Uint8List? imageData = await getBytesFromBytes(path, width);
    return BitmapDescriptor.bytes(imageData!);
  }
}

String formatReportDate(DateTime date) {
  return DateFormat('dd-MM-yyyy').format(date.toLocal());
}

String formatReportTime(TimeOfDay timeOfDay) {
  return "${timeOfDay.hour}:${timeOfDay.minute}";
}

String convertCourse(double course) {
  if ((course >= 15) && (course < 75)) {
    return "NE";
  } else if ((course >= 75) && (course < 105)) {
    return "E";
  } else if ((course >= 105) && (course < 165)) {
    return "SE";
  } else if ((course >= 165) && (course < 195)) {
    return "S";
  } else if ((course >= 195) && (course < 255)) {
    return "SW";
  } else if ((course >= 255) && (course < 285)) {
    return "W";
  } else if ((course >= 285) && (course < 345)) {
    return "NW";
  } else {
    return "N";
  }
}

Future<void> showProgress(bool status, BuildContext context) async {
  if (status) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              Container(
                  margin: EdgeInsets.only(left: 5), child: Text("Loading")),
            ],
          ),
        );
      },
    );
  } else {
    Navigator.pop(context);
  }
}
