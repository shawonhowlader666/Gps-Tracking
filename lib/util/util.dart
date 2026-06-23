import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:smart_lock/util/image_fetcher.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart' as m;
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import 'package:smart_lock/storage/user_repository.dart';

class Util {
  // ✅ Bangladesh timezone offset (UTC+6)
  static const Duration _bdOffset = Duration(hours: 6);

  /// যেকোনো DateTime কে Bangladesh time এ convert করো
  static DateTime _toBD(DateTime dt) => dt.toUtc().add(_bdOffset);

  static String convertSpeed(var speed, String type) {
    return "${speed.toInt()} $type";
  }

  // ✅ FIX: toLocal() এর বদলে BD time use করো
  static String formatTime(String time) {
    final lastUpdate = _toBD(DateTime.parse(time));
    return DateFormat('dd-MM-yyyy hh:mm:ss').format(lastUpdate);
  }

  static String formatOnlyTime(String date) {
    final inputFormat = DateFormat("MM-dd-yyyy HH:mm:ss");
    final lastUpdate = _toBD(inputFormat.parse(date));
    return DateFormat('HH:mm').format(lastUpdate);
  }

  static String formatOnlyTimeAMPM(String rawTime) {
    try {
      final dt = _toBD(DateTime.parse(rawTime));
      return DateFormat('hh:mm:ss a').format(dt);
    } catch (e) {
      return rawTime;
    }
  }

  static String historyTabTime(String time) {
    final lastUpdate = _toBD(DateTime.parse(time));
    return DateFormat('dd-MMM').format(lastUpdate);
  }

  static String formatInvalidDate(String date) {
    final inputFormat = DateFormat("dd-MM-yyyy HH:mm:ss");
    final lastUpdate = _toBD(inputFormat.parse(date));
    return DateFormat('yyyy-MM-dd').format(lastUpdate);
  }

  static String formatInvalidTime(String date) {
    final inputFormat = DateFormat("MM-dd-yyyy HH:mm:ss");
    final lastUpdate = _toBD(inputFormat.parse(date));
    return DateFormat('HH:mm:ss').format(lastUpdate);
  }

  static String convertDistance(double distance) {
    double calcDistance = distance / 1000;
    return "${calcDistance.toStringAsFixed(2)} Km";
  }

  static String convertDistancePlain(double distance) {
    double calcDistance = distance / 1000;
    return calcDistance.toStringAsFixed(2);
  }

  static String convertDuration(int duration) {
    double hours = duration / 3600000;
    double minutes = duration % 3600000 / 60000;
    return "${hours.toInt()} hr ${minutes.toInt()} min";
  }

  static String convertDurationPlain(int duration) {
    double hours = duration / 3600000;
    return hours.toInt().toString();
  }

  static String formatReportDate(DateTime date) {
    return DateFormat('dd-MM-yyyy').format(_toBD(date));
  }

  static String formatReportTime(DateTime date) {
    return DateFormat('HH:mm:ss').format(_toBD(date));
  }

  static String formatDateReport(String date) {
    final lastUpdate = _toBD(DateTime.parse(date));
    String month = lastUpdate.month < 10
        ? "0${lastUpdate.month}"
        : lastUpdate.month.toString();
    String day =
    lastUpdate.day < 10 ? "0${lastUpdate.day}" : lastUpdate.day.toString();
    return "${lastUpdate.year}-$month-$day";
  }

  static String formatTimeReport(String date) {
    final lastUpdate = _toBD(DateTime.parse(date));
    String hour = lastUpdate.hour < 10
        ? "0${lastUpdate.hour}"
        : lastUpdate.hour.toString();
    String minute = lastUpdate.minute < 10
        ? "0${lastUpdate.minute}"
        : lastUpdate.minute.toString();
    return "$hour:$minute:00";
  }

  static Future<Uint8List?> getBytesFromAsset(String path, int width) async {
    if (path.isNotEmpty) {
      ByteData data = await rootBundle.load(path);
      ui.Codec codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
          targetWidth: width);
      ui.FrameInfo fi = await codec.getNextFrame();
      return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
    } else {
      return null;
    }
  }

  static Future<BitmapDescriptor> getBitmapDescriptorFromAssetBytes(
      String path, int width) async {
    final Uint8List? imageData = await getBytesFromAsset(path, width);
    return BitmapDescriptor.bytes(imageData!);
  }

  static Future<BitmapDescriptor> getBitmapDescriptorFromBytes(
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

  static Future<Uint8List?> getBytesFromBytes(var data, int width) async {
    if (data != null) {
      ui.Codec codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
          targetWidth: width);
      ui.FrameInfo fi = await codec.getNextFrame();
      return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
    } else {
      return null;
    }
  }

  static LatLngBounds boundsFromLatLngList(Set<Marker> list) {
    assert(list.isNotEmpty);
    double? x0, x1, y0, y1;
    for (var value in list) {
      if (x0 == null) {
        x0 = x1 = value.position.latitude;
        y0 = y1 = value.position.longitude;
      } else {
        if (value.position.latitude > x1!) x1 = value.position.latitude;
        if (value.position.latitude < x0) x0 = value.position.latitude;
        if (value.position.longitude > y1!) y1 = value.position.longitude;
        if (value.position.longitude < y0!) y0 = value.position.longitude;
      }
    }
    return LatLngBounds(
        northeast: LatLng(x1!, y1!), southwest: LatLng(x0!, y0!));
  }

  static LatLngBounds getLatLngBounds(Set<Marker> markers) {
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (final marker in markers) {
      final lat = marker.position.latitude;
      final lng = marker.position.longitude;

      minLat = lat < minLat ? lat : minLat;
      maxLat = lat > maxLat ? lat : maxLat;
      minLng = lng < minLng ? lng : minLng;
      maxLng = lng > maxLng ? lng : maxLng;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  static LatLngBounds boundsFromLatLngListCluster(List<LatLng> list) {
    assert(list.isNotEmpty);
    double? x0, x1, y0, y1;
    for (LatLng latLng in list) {
      if (x0 == null) {
        x0 = x1 = latLng.latitude;
        y0 = y1 = latLng.longitude;
      } else {
        if (latLng.latitude > x1!) x1 = latLng.latitude;
        if (latLng.latitude < x0) x0 = latLng.latitude;
        if (latLng.longitude > y1!) y1 = latLng.longitude;
        if (latLng.longitude < y0!) y0 = latLng.longitude;
      }
    }
    return LatLngBounds(
        northeast: LatLng(x1!, y1!), southwest: LatLng(x0!, y0!));
  }

  static Future<BitmapDescriptor> getMarkerIconImagePath(
      String imagePath,
      String infoText,
      Color color,
      double rotateDegree,
      bool showTitle) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    Size canvasSize = const Size(700.0, 200.0);
    Size markerSize = const Size(250.0, 120.0);
    TextPainter? textPainter;
    if (showTitle) {
      textPainter = TextPainter(textDirection: m.TextDirection.ltr);
      textPainter.text = TextSpan(
        text: infoText,
        style: TextStyle(
            fontSize: 20.0, fontWeight: FontWeight.w600, color: color),
      );
      textPainter.layout();
    }

    final Paint infoPaint = Paint()..color = Colors.white;
    final Paint infoStrokePaint = Paint()..color = color;
    final double infoHeight = 50.0;
    final double strokeWidth = 2.0;
    final double shadowWidth = 30.0;

    canvas.translate(
        canvasSize.width / 2, canvasSize.height / 2 + infoHeight / 2);

    Rect oval = Rect.fromLTWH(
        -markerSize.width / 2 + .5 * shadowWidth,
        -markerSize.height / 2 + .5 * shadowWidth,
        markerSize.width - shadowWidth,
        markerSize.height - shadowWidth);

    canvas.save();
    canvas.rotate((pi / 180.0) * rotateDegree);
    canvas.clipPath(Path()..addOval(oval));

    ui.Image image = await getImageFromPath(imagePath);
    paintImage(canvas: canvas, image: image, rect: oval, fit: BoxFit.fitHeight);

    canvas.restore();
    if (showTitle) {
      canvas.drawPath(
          Path()
            ..addRRect(RRect.fromLTRBR(
                -textPainter!.width / 2 - infoHeight / 2,
                -canvasSize.height / 2 - infoHeight / 2 + 1,
                textPainter.width / 2 + infoHeight / 2,
                -canvasSize.height / 2 + infoHeight / 2 + 1,
                const Radius.circular(35.0)))
            ..moveTo(-15, -canvasSize.height / 2 + infoHeight / 2 + 1)
            ..lineTo(0, -canvasSize.height / 2 + infoHeight / 2 + 25)
            ..lineTo(15, -canvasSize.height / 2 + infoHeight / 2 + 1),
          infoStrokePaint);

      canvas.drawPath(
          Path()
            ..addRRect(RRect.fromLTRBR(
                -textPainter.width / 2 - infoHeight / 2 + strokeWidth,
                -canvasSize.height / 2 - infoHeight / 2 + 1 + strokeWidth,
                textPainter.width / 2 + infoHeight / 2 - strokeWidth,
                -canvasSize.height / 2 + infoHeight / 2 + 1 - strokeWidth,
                const Radius.circular(32.0)))
            ..moveTo(-15 + strokeWidth / 2,
                -canvasSize.height / 2 + infoHeight / 2 + 1 - strokeWidth)
            ..lineTo(0,
                -canvasSize.height / 2 + infoHeight / 2 + 25 - strokeWidth * 2)
            ..lineTo(15 - strokeWidth / 2,
                -canvasSize.height / 2 + infoHeight / 2 + 1 - strokeWidth),
          infoPaint);

      textPainter.paint(
          canvas,
          Offset(
              -textPainter.width / 2,
              -canvasSize.height / 2 -
                  infoHeight / 2 +
                  infoHeight / 2 -
                  textPainter.height / 2));

      canvas.restore();
    }

    final ui.Image markerAsImage = await pictureRecorder
        .endRecording()
        .toImage(canvasSize.width.toInt(), canvasSize.height.toInt());

    final ByteData? byteData =
    await markerAsImage.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List? uint8List = byteData?.buffer.asUint8List();

    return BitmapDescriptor.bytes(uint8List!);
  }

  static Future<ui.Image> getImageFromPath(String imagePath) async {
    var bd = await rootBundle.load(imagePath);
    Uint8List imageBytes = Uint8List.view(bd.buffer);

    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(imageBytes, (ui.Image img) {
      return completer.complete(img);
    });

    return completer.future;
  }

  static Future<ui.Image> getImageFromFilePath(String imagePath) async {
    File imageFile = File(imagePath);
    Uint8List imageBytes = Uint8List.view(imageFile.readAsBytesSync().buffer);

    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(imageBytes, (ui.Image img) {
      return completer.complete(img);
    });

    return completer.future;
  }

  static Future<ui.Image> getImageFromPathUrl(String imagePath) async {
    final response = await http.Client().get(Uri.parse(imagePath));
    final bytes = response.bodyBytes;

    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      return completer.complete(img);
    });

    return completer.future;
  }

  static Future<BitmapDescriptor> getMarkerIconFromUrl(
      String imagePath,
      String infoText,
      Color color,
      double rotateDegree,
      bool showTitle) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    Size canvasSize = const Size(700.0, 200.0);
    Size markerSize = const Size(250.0, 120.0);
    TextPainter? textPainter;
    if (showTitle) {
      textPainter = TextPainter(textDirection: m.TextDirection.ltr);
      textPainter.text = TextSpan(
        text: infoText,
        style: TextStyle(
            fontSize: 30.0, fontWeight: FontWeight.w600, color: color),
      );
      textPainter.layout();
    }

    final Paint infoPaint = Paint()..color = Colors.white;
    final Paint infoStrokePaint = Paint()..color = color;
    final double infoHeight = 50.0;
    final double strokeWidth = 2.0;
    final double shadowWidth = 30.0;

    canvas.translate(
        canvasSize.width / 2, canvasSize.height / 2 + infoHeight / 2);

    Rect oval = Rect.fromLTWH(
        -markerSize.width / 2 + .5 * shadowWidth,
        -markerSize.height / 2 + .5 * shadowWidth,
        markerSize.width - shadowWidth,
        markerSize.height - shadowWidth);

    canvas.save();
    canvas.rotate((pi / 180.0) * rotateDegree);
    canvas.clipPath(Path()..addOval(oval));

    ui.Image? image;
    await DefaultCacheManager().getFileFromCache(imagePath).then((value) async {
      image = await getImageFromFilePath(value!.file.path);
    });

    paintImage(
        canvas: canvas, image: image!, rect: oval, fit: BoxFit.fitHeight);

    canvas.restore();
    if (showTitle) {
      canvas.drawPath(
          Path()
            ..addRRect(RRect.fromLTRBR(
                -textPainter!.width / 2 - infoHeight / 2,
                -canvasSize.height / 2 - infoHeight / 2 + 1,
                textPainter.width / 2 + infoHeight / 2,
                -canvasSize.height / 2 + infoHeight / 2 + 1,
                const Radius.circular(35.0)))
            ..moveTo(-15, -canvasSize.height / 2 + infoHeight / 2 + 1)
            ..lineTo(0, -canvasSize.height / 2 + infoHeight / 2 + 25)
            ..lineTo(15, -canvasSize.height / 2 + infoHeight / 2 + 1),
          infoStrokePaint);

      canvas.drawPath(
          Path()
            ..addRRect(RRect.fromLTRBR(
                -textPainter.width / 2 - infoHeight / 2 + strokeWidth,
                -canvasSize.height / 2 - infoHeight / 2 + 1 + strokeWidth,
                textPainter.width / 2 + infoHeight / 2 - strokeWidth,
                -canvasSize.height / 2 + infoHeight / 2 + 1 - strokeWidth,
                const Radius.circular(32.0)))
            ..moveTo(-15 + strokeWidth / 2,
                -canvasSize.height / 2 + infoHeight / 2 + 1 - strokeWidth)
            ..lineTo(0,
                -canvasSize.height / 2 + infoHeight / 2 + 25 - strokeWidth * 2)
            ..lineTo(15 - strokeWidth / 2,
                -canvasSize.height / 2 + infoHeight / 2 + 1 - strokeWidth),
          infoPaint);

      textPainter.paint(
          canvas,
          Offset(
              -textPainter.width / 2,
              -canvasSize.height / 2 -
                  infoHeight / 2 +
                  infoHeight / 2 -
                  textPainter.height / 2));

      canvas.restore();
    }

    final ui.Image markerAsImage = await pictureRecorder
        .endRecording()
        .toImage(canvasSize.width.toInt(), canvasSize.height.toInt());

    final ByteData? byteData =
    await markerAsImage.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List uint8List = byteData!.buffer.asUint8List();

    return BitmapDescriptor.bytes(uint8List);
  }

  Future<File> getImageFileFromCache(String imageUrl) async {
    final DefaultCacheManager cacheManager = DefaultCacheManager();
    final FileInfo? fileInfo = await cacheManager.getFileFromCache(imageUrl);
    return fileInfo!.file;
  }

  static Map<String, dynamic> convertXmlToJson(String xmlData) {
    final document = xml.XmlDocument.parse(xmlData);
    final jsonMap = <String, dynamic>{};

    for (var element in document.findAllElements('info').first.children) {
      if (element is xml.XmlElement) {
        final key = element.name.local;
        // ignore: deprecated_member_use
        final value = element.text;
        jsonMap[key] = value;
      }
    }

    return jsonMap;
  }

  static Future<void> fetchAndCacheImages(String url) async {
    final imageFetcher = ImageFetcher(url);
    await imageFetcher.downloadAndSaveImages();
  }

  static Future<BitmapDescriptor> getMarkerIcon(String imagePath) async {
    final String imageUrl = "${UserRepository.getServerUrl()!}/$imagePath";
    final File imageFile = await DefaultCacheManager().getSingleFile(imageUrl);
    final Uint8List bytes = await imageFile.readAsBytes();
    return BitmapDescriptor.bytes(bytes);
  }
}