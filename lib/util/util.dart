import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:gpspro/util/image_fetcher.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart' as m;
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;

class Util {
  static final Map<String, BitmapDescriptor> _markerIconCache = {};

  static String convertSpeed(var speed, String type) {
    return "${speed.toInt()} $type";
  }

  static String formatTime(String time) {
    DateTime lastUpdate = DateTime.parse(time);
    return DateFormat('dd-MM-yyyy hh:mm:ss').format(lastUpdate.toLocal());
  }

  static String formatOnlyTime(String date) {
    DateFormat inputFormat = DateFormat("MM-dd-yyyy HH:mm:ss");
    DateTime lastUpdate = inputFormat.parse(date);
    return DateFormat('HH:mm').format(lastUpdate.toLocal());
  }

  static String historyTabTime(String time) {
    DateTime lastUpdate = DateTime.parse(time);
    return DateFormat('dd-MMM').format(lastUpdate.toLocal());
  }

  static String formatInvalidDate(String date) {
    DateFormat inputFormat = DateFormat("dd-MM-yyyy HH:mm:ss");
    DateTime lastUpdate = inputFormat.parse(date);
    return DateFormat('yyyy-MM-dd').format(lastUpdate.toLocal());
  }

  static String formatInvalidTime(String date) {
    DateFormat inputFormat = DateFormat("MM-dd-yyyy HH:mm:ss");
    DateTime lastUpdate = inputFormat.parse(date);
    return DateFormat('HH:mm:ss').format(lastUpdate.toLocal());
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

  static Future<Uint8List?> getBytesFromAsset(String path, int width) async {
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

  static String formatReportDate(DateTime date) {
    return DateFormat('dd-MM-yyyy').format(date.toLocal());
  }

  static String formatReportTime(DateTime date) {
    return DateFormat('HH:mm:ss').format(date.toLocal());
  }

  static String formatDateReport(String date) {
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

  static String formatTimeReport(String date) {
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

  static LatLngBounds boundsFromLatLngList(Set<Marker> list) {
    final validList = list
        .where((m) => m.position.latitude != 0.0 || m.position.longitude != 0.0)
        .toList();
    final targetList = validList.isNotEmpty ? validList : list.toList();
    assert(targetList.isNotEmpty);
    double? x0, x1, y0, y1;
    for (var value in targetList) {
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
    return LatLngBounds(
        northeast: LatLng(x1!, y1!), southwest: LatLng(x0!, y0!));
  }

  static LatLngBounds getLatLngBounds(Set<Marker> markers) {
    final validMarkers = markers
        .where((m) => m.position.latitude != 0.0 || m.position.longitude != 0.0)
        .toList();
    final targetMarkers =
        validMarkers.isNotEmpty ? validMarkers : markers.toList();

    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (final marker in targetMarkers) {
      final lat = marker.position.latitude;
      final lng = marker.position.longitude;

      minLat = lat < minLat ? lat : minLat;
      maxLat = lat > maxLat ? lat : maxLat;
      minLng = lng < minLng ? lng : minLng;
      maxLng = lng > maxLng ? lng : maxLng;
    }

    if (minLat == double.infinity) {
      return LatLngBounds(
        southwest: const LatLng(23.6850, 90.3563),
        northeast: const LatLng(23.6850, 90.3563),
      );
    }

    final southwest = LatLng(minLat, minLng);
    final northeast = LatLng(maxLat, maxLng);

    return LatLngBounds(
      southwest: southwest,
      northeast: northeast,
    );
  }

  static LatLngBounds boundsFromLatLngListCluster(List<LatLng> list) {
    final validList = list
        .where((latLng) => latLng.latitude != 0.0 || latLng.longitude != 0.0)
        .toList();
    final targetList = validList.isNotEmpty ? validList : list;
    assert(targetList.isNotEmpty);
    double? x0, x1, y0, y1;
    for (LatLng latLng in targetList) {
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

  static Future<BitmapDescriptor> getMarkerIconImagePath(String imagePath,
      String infoText, Color color, double rotateDegree, bool showTitle) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    //size
    Size canvasSize = const Size(700.0, 200.0);
    Size markerSize = const Size(250.0, 120.0);
    TextPainter? textPainter;
    if (showTitle) {
      // Add info text
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

    //final Paint markerPaint = Paint()..color = color.withOpacity(0.1);
    final double shadowWidth = 30.0;

    canvas.translate(
        canvasSize.width / 2, canvasSize.height / 2 + infoHeight / 2);

    // Add shadow circle
    //canvas.drawOval(Rect.fromLTWH(-markerSize.width/2, -markerSize.height/2, markerSize.width, markerSize.height), markerPaint);
    // Add border circle
    //canvas.drawOval(Rect.fromLTWH(-markerSize.width/2+shadowWidth, -markerSize.height/2+shadowWidth, markerSize.width-2*shadowWidth, markerSize.height-2*shadowWidth), borderPaint);

    // Oval for the image
    Rect oval = Rect.fromLTWH(
        -markerSize.width / 2 + .5 * shadowWidth,
        -markerSize.height / 2 + .5 * shadowWidth,
        markerSize.width - shadowWidth,
        markerSize.height - shadowWidth);

    //save canvas before rotate
    canvas.save();

    double rotateRadian = (pi / 180.0) * rotateDegree;

    //Rotate Image
    canvas.rotate(rotateRadian);

    // Add path for oval image
    canvas.clipPath(Path()..addOval(oval));

    ui.Image image;
    // Add image
    image = await getImageFromPath(imagePath);

    paintImage(canvas: canvas, image: image, rect: oval, fit: BoxFit.fitHeight);

    canvas.restore();
    if (showTitle) {
      // Add info box stroke
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

      //info info box
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

    // Convert canvas to image
    final ui.Image markerAsImage = await pictureRecorder
        .endRecording()
        .toImage(canvasSize.width.toInt(), canvasSize.height.toInt());

    // Convert image to bytes
    final ByteData? byteData =
        await markerAsImage.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List? uint8List = byteData?.buffer.asUint8List();

    return BitmapDescriptor.bytes(uint8List!);
  }

  static Future<ui.Image> getImageFromPath(String imagePath) async {
    //File imageFile = File(imagePath);
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
    //var bd = await rootBundle.load(imagePath);
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
//  var bd = await rootBundle.load(imagePath);
    //Uint8List imageBytes = Uint8List.view(bd.buffer);

    final Completer<ui.Image> completer = Completer();

    ui.decodeImageFromList(bytes, (ui.Image img) {
      return completer.complete(img);
    });

    return completer.future;
  }

  static Future<BitmapDescriptor> getMarkerIconFromUrl(String imagePath,
      String infoText, Color color, double rotateDegree, bool showTitle) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    //size
    Size canvasSize = const Size(700.0, 200.0);
    Size markerSize = const Size(250.0, 120.0);
    TextPainter? textPainter;
    if (showTitle) {
      // Add info text
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

    //final Paint markerPaint = Paint()..color = color.withOpacity(0.1);
    final double shadowWidth = 30.0;

    canvas.translate(
        canvasSize.width / 2, canvasSize.height / 2 + infoHeight / 2);

    // Add shadow circle
    //canvas.drawOval(Rect.fromLTWH(-markerSize.width/2, -markerSize.height/2, markerSize.width, markerSize.height), markerPaint);
    // Add border circle
    //canvas.drawOval(Rect.fromLTWH(-markerSize.width/2+shadowWidth, -markerSize.height/2+shadowWidth, markerSize.width-2*shadowWidth, markerSize.height-2*shadowWidth), borderPaint);

    // Oval for the image
    Rect oval = Rect.fromLTWH(
        -markerSize.width / 2 + .5 * shadowWidth,
        -markerSize.height / 2 + .5 * shadowWidth,
        markerSize.width - shadowWidth,
        markerSize.height - shadowWidth);

    //save canvas before rotate
    canvas.save();

    double rotateRadian = (pi / 180.0) * rotateDegree;

    //Rotate Image
    canvas.rotate(rotateRadian);

    // Add path for oval image
    canvas.clipPath(Path()..addOval(oval));

    ui.Image? image;
    // Add image
    //image = await getImageFromPathUrl(imagePath);
    await DefaultCacheManager().getFileFromCache(imagePath).then((value) async {
      image = await getImageFromFilePath(value!.file.path);
    });

    paintImage(
        canvas: canvas, image: image!, rect: oval, fit: BoxFit.fitHeight);

    canvas.restore();
    if (showTitle) {
      // Add info box stroke
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

      //info info box
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

    // Convert canvas to image
    final ui.Image markerAsImage = await pictureRecorder
        .endRecording()
        .toImage(canvasSize.width.toInt(), canvasSize.height.toInt());

    // Convert image to bytes
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

  static String _getCacheKey(String imagePath, int size,
      {String? statusColor, String? iconType, String? deviceName, dynamic deviceId}) {
    final String? localAssetPath = getLocalMappedAsset(imagePath, iconType: iconType, deviceName: deviceName, deviceId: deviceId);
    return "${imagePath}_${size}_${statusColor ?? 'default'}_${iconType ?? 'default'}_${deviceName ?? 'default'}_${deviceId ?? 'default'}_${localAssetPath ?? 'default'}_v17";
  }

  static BitmapDescriptor? getCachedMarkerIcon(String imagePath, int size,
      {String? statusColor, String? iconType, String? deviceName, dynamic deviceId}) {
    final String cacheKey = _getCacheKey(imagePath, size,
        statusColor: statusColor, iconType: iconType, deviceName: deviceName, deviceId: deviceId);
    return _markerIconCache[cacheKey];
  }

  static int getMarkerSizeForZoom(double zoom) {
    if (zoom >= 20) return 65;
    if (zoom >= 18) return 55;
    if (zoom >= 16) return 46;
    if (zoom >= 14) return 38;
    if (zoom >= 12) return 30;
    return 22;
  }

  static String getLocalSvgPath(String? serverPath) {
    if (serverPath == null) return 'assets/images/track_car.svg';
    final path = serverPath.toLowerCase().trim();

    // Check by ID or exact name parts
    if (path.contains('sportscar') ||
        path.contains('sports-car') ||
        path.contains('sports_car') ||
        path.contains('2.png')) {
      return 'assets/images/track_sportscar.svg';
    } else if (path.contains('motorcycle') ||
        path.contains('bike') ||
        path.contains('moto') ||
        path.contains('3.png')) {
      return 'assets/images/track_motorcycle.svg';
    } else if (path.contains('bus') || path.contains('4.png')) {
      return 'assets/images/track_bus.svg';
    } else if (path.contains('police') || path.contains('5.png')) {
      return 'assets/images/track_police.svg';
    } else if (path.contains('cargo_truck') ||
        path.contains('cargo-truck') ||
        path.contains('pickup') ||
        path.contains('6.png')) {
      return 'assets/images/track_truck.svg';
    } else if (path.contains('cng') ||
        path.contains('rickshaw') ||
        path.contains('auto') ||
        path.contains('7.png')) {
      return 'assets/images/track_cng.svg';
    } else if (path.contains('speedboat') ||
        path.contains('speed-boat') ||
        path.contains('15.png')) {
      return 'assets/images/track_speedboat.svg';
    } else if (path.contains('boat') ||
        path.contains('ship') ||
        path.contains('marine') ||
        path.contains('8.png')) {
      return 'assets/images/track_boat.svg';
    } else if (path.contains('bicycle') ||
        path.contains('cycle') ||
        path.contains('9.png')) {
      return 'assets/images/track_bicycle.svg';
    } else if (path.contains('container') ||
        path.contains('heavy-truck') ||
        path.contains('heavy_truck') ||
        path.contains('10.png')) {
      return 'assets/images/track_container.svg';
    } else if (path.contains('person') ||
        path.contains('walk') ||
        path.contains('11.png')) {
      return 'assets/images/track_person.svg';
    } else if (path.contains('van') ||
        path.contains('micro') ||
        path.contains('12.png')) {
      return 'assets/images/track_van.svg';
    } else if (path.contains('tractor') || path.contains('13.png')) {
      return 'assets/images/track_tractor.svg';
    } else if (path.contains('ambulance') || path.contains('14.png')) {
      return 'assets/images/track_ambulance.svg';
    } else if (path.contains('generator') || path.contains('16.png')) {
      return 'assets/images/track_generator.svg';
    } else if (path.contains('concrete') ||
        path.contains('mixer') ||
        path.contains('dump') ||
        path.contains('17.png')) {
      return 'assets/images/track_concrete.svg';
    }

    // Default fallback
    return 'assets/images/track_car.svg';
  }

  static String? getLocalMappedAsset(String? imagePath, {String? iconType, String? deviceName, dynamic deviceId}) {
    if (imagePath == null && iconType == null && deviceName == null && deviceId == null) return 'assets/images/car_toprunning.png';
    
    if (deviceId != null) {
      final String? savedAsset = UserRepository.prefs?.getString("custom_icon_path_${deviceId.toString()}");
      if (savedAsset != null && savedAsset.isNotEmpty) {
        debugPrint("getLocalMappedAsset PREFERENCE matched: '$savedAsset' for device ID '$deviceId'");
        return savedAsset;
      }
    }

    debugPrint("getLocalMappedAsset CALLED with imagePath: '$imagePath', iconType: '$iconType', deviceName: '$deviceName', deviceId: '$deviceId'");
    final path = "${imagePath?.toLowerCase() ?? ''} ${iconType?.toLowerCase() ?? ''} ${deviceName?.toLowerCase() ?? ''}".trim();
    if (path.isEmpty) return 'assets/images/car_toprunning.png';
    
    String? result;

    // 1. High priority keyword matching (e.g. from device name) to prioritize user-given device name types
    if (path.contains('ambulance')) {
      result = 'assets/images/ambulance_toprunning.png';
    } else if (path.contains('motorcycle') || path.contains('bike') || path.contains('scooter') || path.contains('scotty')) {
      if (path.contains('scotty') || path.contains('scooter')) {
        result = 'assets/images/scotty_toprunning.png';
      } else {
        result = 'assets/images/bike_toprunning.png';
      }
    } else if (path.contains('bus')) {
      if (path.contains('school')) {
        result = 'assets/images/school_toprunning.png';
      } else {
        result = 'assets/images/bus_toprunning.png';
      }
    } else if (path.contains('crane') || path.contains('tractor')) {
      result = 'assets/images/crane_toprunning.png';
    } else if (path.contains('garbage')) {
      result = 'assets/images/garbage_toprunning.png';
    } else if (path.contains('mixer') || path.contains('concrete')) {
      result = 'assets/images/mixer_toprunning.png';
    } else if (path.contains('muv')) {
      result = 'assets/images/muv_toprunning.png';
    } else if (path.contains('pickup') || path.contains('van')) {
      result = 'assets/images/pickup_toprunning.png';
    } else if (path.contains('suv')) {
      result = 'assets/images/suv_toprunning.png';
    } else if (path.contains('container') || path.contains('tanker')) {
      result = 'assets/images/tanker_toprunning.png';
    } else if (path.contains('cng') || path.contains('rickshaw') || path.contains('auto') || path.contains('tempo')) {
      result = 'assets/images/tempotvr_toprunning.png';
    } else if (path.contains('truck')) {
      result = 'assets/images/truck_toprunning.png';
    }

    // 2. Default/Fallback Server Path & Hash matching
    if (result == null) {
      if (path.contains('6877e65ea4be98.96057559') || path.contains('6877e65ea4be98.96057559_online') || path.contains('6877e65ea4be98.96057559_offline')) {
        result = 'assets/images/car_toprunning.png';
      } else if (path.contains('6877e682a122d5.26467715')) {
        result = 'assets/images/suv_toprunning.png';
      } else if (path.contains('68919e188759f4.90604553_online') || path.contains('68919e188759f4.90604553_offline') || path.contains('68919e188759f4.90604553_ack')) {
        result = 'assets/images/car_toprunning.png';
      } else if (path.contains('694676186e6877.76876067')) {
        result = 'assets/images/muv_toprunning.png';
      } else if (path.contains('694bd24618ce36.67143977')) {
        result = 'assets/images/pickup_toprunning.png';
      } else if (path.contains('697613f6c938a0.41043256')) {
        result = 'assets/images/car_toprunning.png';
      } else if (path.contains('697d973eeaedd3.55855774')) {
        result = 'assets/images/bus_toprunning.png';
      } else if (path.contains('697daf738d1b75.34407076_online') || path.contains('697daf738d1b75.34407076_offline') || path.contains('697daf738d1b75.34407076_ack')) {
        result = 'assets/images/car_toprunning.png';
      } else if (path.contains('697ddf3220bbe8.30991600')) {
        result = 'assets/images/ambulance_toprunning.png';
      } else if (path.contains('697de4afdb0ed9.71856605_online') || path.contains('697de4afdb0ed9.71856605_offline') || path.contains('697de4afdb0ed9.71856605_ack') || path.contains('697de4afdb0ed9.71856605_engine')) {
        result = 'assets/images/car_toprunning.png';
      } else if (path.contains('697de539b850a9.16646834_online') || path.contains('697de539b850a9.16646834_offline') || path.contains('697de539b850a9.16646834_ack') || path.contains('697de539b850a9.16646834_engine')) {
        result = 'assets/images/muv_toprunning.png';
      } else if (path.contains('697de5ef7182f1.91869408_online') || path.contains('697de5ef7182f1.91869408_offline') || path.contains('697de5ef7182f1.91869408_ack')) {
        result = 'assets/images/bus_toprunning.png';
      } else if (path.contains('6991da32795029.80377888_online') || path.contains('6991da32795029.80377888_offline') || path.contains('6991da32795029.80377888_ack')) {
        result = 'assets/images/bike_toprunning.png';
      } else if (path.contains('69a93ef4b3c047.72210671')) {
        result = 'assets/images/tempotvr_toprunning.png';
      } else if (path.contains('14.png')) {
        result = 'assets/images/ambulance_toprunning.png';
      } else if (path.contains('3.png')) {
        result = 'assets/images/bike_toprunning.png';
      } else if (path.contains('4.png')) {
        result = 'assets/images/bus_toprunning.png';
      } else if (path.contains('2.png')) {
        result = 'assets/images/car_toprunning.png';
      } else if (path.contains('13.png')) {
        result = 'assets/images/crane_toprunning.png';
      } else if (path.contains('17.png')) {
        result = 'assets/images/mixer_toprunning.png';
      } else if (path.contains('12.png')) {
        result = 'assets/images/pickup_toprunning.png';
      } else if (path.contains('10.png')) {
        result = 'assets/images/tanker_toprunning.png';
      } else if (path.contains('7.png')) {
        result = 'assets/images/tempotvr_toprunning.png';
      } else if (path.contains('6.png')) {
        result = 'assets/images/truck_toprunning.png';
      } else if (path.contains('car') || path.contains('1.png') || path.contains('5.png') || path.contains('rotating/')) {
        result = 'assets/images/car_toprunning.png';
      }
    }
    
    result ??= 'assets/images/car_toprunning.png';
    debugPrint("getLocalMappedAsset RESULT: '$result' for path: '$imagePath', iconType: '$iconType', deviceName: '$deviceName'");
    return result;
  }

  static ColorFilter getTintFilter(Color color) {
    const double boost = 1.35;
    final double r = (color.r * boost).clamp(0.0, 1.0);
    final double g = (color.g * boost).clamp(0.0, 1.0);
    final double b = (color.b * boost).clamp(0.0, 1.0);
    return ColorFilter.matrix(<double>[
      0.15 * r, 1.15 * r, 0.1 * r, 0, 0,
      0.15 * g, 1.15 * g, 0.1 * g, 0, 0,
      0.15 * b, 1.15 * b, 0.1 * b, 0, 0,
      0,        0,        0,       1, 0,
    ]);
  }

  static Future<Uint8List?> getTintedBytesFromAsset(String path, int width, Color tintColor) async {
    if (path.isEmpty) return null;
    try {
      ByteData data = await rootBundle.load(path);
      // Decode image at native size to get exact aspect ratio
      ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      ui.FrameInfo fi = await codec.getNextFrame();
      ui.Image originalImage = fi.image;

      final double originalWidth = originalImage.width.toDouble();
      final double originalHeight = originalImage.height.toDouble();

      // We make the canvas a perfect square of size `width`
      final double canvasSize = width.toDouble();
      double drawWidth, drawHeight;
      double dx, dy;

      if (originalHeight > originalWidth) {
        // Vertical/Long image (like top-view cars)
        drawHeight = canvasSize;
        drawWidth = originalWidth * (canvasSize / originalHeight);
        dx = (canvasSize - drawWidth) / 2;
        dy = 0;
      } else {
        // Horizontal/Wide image
        drawWidth = canvasSize;
        drawHeight = originalHeight * (canvasSize / originalWidth);
        dx = 0;
        dy = (canvasSize - drawHeight) / 2;
      }
      
      final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(pictureRecorder);
      
      final paint = Paint()
        ..colorFilter = getTintFilter(tintColor);
      
      canvas.drawImageRect(
        originalImage,
        Rect.fromLTWH(0, 0, originalWidth, originalHeight),
        Rect.fromLTWH(dx, dy, drawWidth, drawHeight),
        paint,
      );

      final ui.Image tintedImage = await pictureRecorder.endRecording().toImage(canvasSize.toInt(), canvasSize.toInt());
      final ByteData? byteData = await tintedImage.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint("Error tinting image $path: $e");
      return null;
    }
  }

  static String formatDurationString(String? duration) {
    if (duration == null || duration.isEmpty || duration == '-') return '-';
    
    // Attempt to parse standard HH:mm:ss if colon present
    if (duration.contains(':')) {
      final parts = duration.split(':');
      if (parts.length >= 2) {
        final hours = int.tryParse(parts[0]) ?? 0;
        final minutes = int.tryParse(parts[1]) ?? 0;
        if (hours >= 24) {
          final days = hours ~/ 24;
          final remHours = hours % 24;
          return "${days}d ${remHours}h ${minutes}m";
        }
        return "${hours}h ${minutes}m";
      }
    }

    // Attempt to parse from text: e.g. "4109h 54min 43s"
    final RegExp hoursReg = RegExp(r'([0-9]+)\s*h');
    final RegExp minsReg = RegExp(r'([0-9]+)\s*(?:min|m)');
    final RegExp secsReg = RegExp(r'([0-9]+)\s*(?:sec|s)');

    final hoursMatch = hoursReg.firstMatch(duration);
    final minsMatch = minsReg.firstMatch(duration);
    final secsMatch = secsReg.firstMatch(duration);

    final int hours = hoursMatch != null ? (int.tryParse(hoursMatch.group(1)!) ?? 0) : 0;
    final int minutes = minsMatch != null ? (int.tryParse(minsMatch.group(1)!) ?? 0) : 0;
    final int seconds = secsMatch != null ? (int.tryParse(secsMatch.group(1)!) ?? 0) : 0;

    if (hoursMatch == null && minsMatch == null && secsMatch == null) {
      return duration;
    }

    if (hours >= 24) {
      final days = hours ~/ 24;
      final remHours = hours % 24;
      if (minutes > 0) {
        return "${days}d ${remHours}h ${minutes}m";
      } else {
        return "${days}d ${remHours}h";
      }
    }

    final List<String> parts = [];
    if (hours > 0) parts.add("${hours}h");
    if (minutes > 0) parts.add("${minutes}m");
    if (seconds > 0 && hours == 0) parts.add("${seconds}s");

    if (parts.isEmpty) return "0s";
    return parts.join(" ");
  }

  static double parseDurationToSeconds(String? durationStr) {
    if (durationStr == null || durationStr.isEmpty) return 0.0;
    try {
      durationStr = durationStr.toLowerCase().trim();

      // If it contains colon (e.g. 02:30:00)
      if (durationStr.contains(':')) {
        final parts = durationStr.split(':');
        if (parts.length >= 2) {
          final hours = double.tryParse(parts[0]) ?? 0.0;
          final minutes = double.tryParse(parts[1]) ?? 0.0;
          final seconds = parts.length > 2 ? (double.tryParse(parts[2]) ?? 0.0) : 0.0;
          return hours * 3600.0 + minutes * 60.0 + seconds;
        }
      }

      // If it contains h, m, s (e.g. 2h 30m)
      double totalSeconds = 0.0;
      final hourReg = RegExp(r'(\d+)\s*h');
      final minReg = RegExp(r'(\d+)\s*(?:min|m)');
      final secReg = RegExp(r'(\d+)\s*(?:sec|s)');

      final hourMatch = hourReg.firstMatch(durationStr);
      if (hourMatch != null) {
        totalSeconds += (double.tryParse(hourMatch.group(1)!) ?? 0.0) * 3600.0;
      }

      final minMatch = minReg.firstMatch(durationStr);
      if (minMatch != null) {
        totalSeconds += (double.tryParse(minMatch.group(1)!) ?? 0.0) * 60.0;
      }

      final secMatch = secReg.firstMatch(durationStr);
      if (secMatch != null) {
        totalSeconds += double.tryParse(secMatch.group(1)!) ?? 0.0;
      }

      return totalSeconds;
    } catch (_) {
      return 0.0;
    }
  }

  static String formatDuration(Duration duration) {
    if (duration.isNegative) return '-';
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    
    final List<String> parts = [];
    if (days > 0) {
      parts.add("${days}d");
    }
    if (hours > 0 || days > 0) {
      parts.add("${hours}h");
    }
    if (minutes > 0 || (days == 0 && hours == 0)) {
      parts.add("${minutes}m");
    }
    return parts.join(" ");
  }

  static Color _getColorFromStatus(String? statusColor, String imagePath) {
    String status = statusColor?.toLowerCase().trim() ?? '';
    if (status.isEmpty) {
      final path = imagePath.toLowerCase();
      if (path.contains('green')) {
        status = 'green';
      } else if (path.contains('yellow')) {
        status = 'yellow';
      } else if (path.contains('red')) {
        status = 'red';
      }
    }
    
    if (status == 'green' || status.contains('green')) {
      return const Color(0xFF00C853); // Green for moving
    } else if (status == 'yellow' || status.contains('yellow')) {
      return const Color(0xFFFF9100); // Yellow/orange for idle
    } else if (status == 'red' || status.contains('red') || status == 'grey' || status.contains('grey') || status.contains('gray') || status.contains('offline')) {
      return CustomColor.primary; // Red for stopped/offline (brand red)
    } else {
      return CustomColor.primary; // Default fallback - red
    }
  }

  static bool isDeviceOnline(DeviceItem device) {
    final online = device.online?.toLowerCase().trim() ?? '';
    if (online.contains('offline')) {
      return false;
    }
    if (online.contains('online')) {
      return true;
    }
    final iconColor = device.iconColor?.toLowerCase().trim() ?? '';
    if (iconColor == 'green' || iconColor == 'yellow') {
      return true;
    }
    if (device.timestamp != null && device.timestamp! > 0) {
      try {
        final lastUpdate =
            DateTime.fromMillisecondsSinceEpoch(device.timestamp! * 1000);
        final difference = DateTime.now().difference(lastUpdate);
        return difference.inMinutes < 5;
      } catch (_) {
        return false;
      }
    }
    final speed = double.tryParse(device.speed.toString()) ?? 0;
    if (speed > 0) {
      return true;
    }
    return false;
  }

  static bool isEngineOn(DeviceItem device) {
    final speed = double.tryParse(device.speed.toString()) ?? 0;
    if (speed > 0) {
      return true;
    }
    if (device.engineStatus != null) {
      final status = device.engineStatus;
      if (status is bool) return status;
      if (status is int) return status == 1;
      if (status is String) {
        final s = status.toLowerCase().trim();
        if (['on', '1', 'true', 'ign on', 'engine on', 'acc on'].contains(s)) {
          return true;
        }
        if (['off', '0', 'false', 'ign off', 'engine off', 'acc off']
            .contains(s)) {
          return false;
        }
      }
    }
    if (device.sensors != null && device.sensors!.isNotEmpty) {
      for (var sensor in device.sensors!) {
        try {
          final type = (sensor['type'] ?? '').toString().toLowerCase();
          final name = (sensor['name'] ?? '').toString().toLowerCase();
          final value = sensor['value'];
          if (type == 'acc' ||
              type == 'ignition' ||
              type == 'engine' ||
              name.contains('ignition') ||
              name.contains('acc') ||
              name.contains('engine')) {
            if (value == null) continue;
            if (value is bool) return value;
            if (value is int) return value == 1;
            if (value is String) {
              final v = value.toLowerCase().trim();
              if (['on', '1', 'true', 'ign on', 'acc on', 'engine on']
                  .contains(v)) {
                return true;
              }
              if (['off', '0', 'false', 'ign off', 'acc off', 'engine off']
                  .contains(v)) {
                return false;
              }
            }
          }
        } catch (e) {
          continue;
        }
      }
    }
    final iconColor = device.iconColor?.toLowerCase().trim() ?? '';
    return iconColor == 'yellow' || iconColor == 'green';
  }

  static String getDeviceStatusColorStr(DeviceItem device) {
    if (!isDeviceOnline(device)) return "red";
    final speed = double.tryParse(device.speed.toString()) ?? 0;
    if (speed > 0) return "green";
    return "yellow";
  }

  static String resolveStatusIconPath(String imagePath, Color color, {bool isOnline = true}) {
    debugPrint("[DEBUG RESOLVE COLOR] path: $imagePath, color: $color");
    if (imagePath.isEmpty) return imagePath;

    // 1. Strip extension (e.g. .png, .jpg, .svg)
    final int extIdx = imagePath.lastIndexOf('.');
    String ext = '';
    String base = imagePath;
    if (extIdx != -1) {
      ext = imagePath.substring(extIdx);
      base = imagePath.substring(0, extIdx);
    }

    // 2. Strip any existing status suffix if present
    final suffixes = ['_online', '_offline', '_ack', '_engine'];
    for (final suffix in suffixes) {
      if (base.endsWith(suffix)) {
        base = base.substring(0, base.length - suffix.length);
        break;
      }
    }

    // 3. Determine the correct suffix based on status/color
    String newSuffix = '_offline';
    if (color.toARGB32() == 0xFF00C853) {
      newSuffix = '_online';
    } else if (color.toARGB32() == 0xFFFF9100) {
      newSuffix = '_ack';
    } else {
      newSuffix = !isOnline ? '_offline' : '_ack';
    }

    return "$base$newSuffix$ext";
  }

  static Future<BitmapDescriptor> getMarkerIcon(String imagePath,
      {int size = 55, String? statusColor, String? iconType, String? deviceName, dynamic deviceId, DeviceItem? device}) async {
    final String cacheKey = _getCacheKey(imagePath, size,
        statusColor: statusColor, iconType: iconType, deviceName: deviceName, deviceId: deviceId);
    if (_markerIconCache.containsKey(cacheKey)) {
      return _markerIconCache[cacheKey]!;
    }
    final int physicalSize = size;

    try {
      // 1. Check if we have a local custom icon preference set (Highest priority)
      if (deviceId != null) {
        final String? localCustomAsset = UserRepository.prefs
            ?.getString("custom_icon_path_${deviceId.toString()}");
        if (localCustomAsset != null && localCustomAsset.isNotEmpty) {
          final tintColor = _getColorFromStatus(statusColor, imagePath);
          final Uint8List? bytes =
              await getTintedBytesFromAsset(localCustomAsset, physicalSize, tintColor);
          if (bytes != null) {
            final descriptor = BitmapDescriptor.bytes(bytes);
            _markerIconCache[cacheKey] = descriptor;
            return descriptor;
          }
        }
      }

      // 2. Fetch the server PNG image directly
      if (imagePath.isNotEmpty) {
        final String? serverUrl = UserRepository.getServerUrl();
        if (serverUrl != null && serverUrl.isNotEmpty) {
          Color colorVal = const m.Color(0xFFE53935); // red/offline default
          final status = statusColor?.toLowerCase().trim() ?? '';
          if (status == 'green' || status.contains('green')) {
            colorVal = const m.Color(0xFF00C853);
          } else if (status == 'yellow' || status.contains('yellow')) {
            colorVal = const m.Color(0xFFFF9100);
          }
          final String resolvedPath = resolveStatusIconPath(
              imagePath, colorVal,
              isOnline: device != null ? isDeviceOnline(device) : status != 'red');

          final String imageUrl = "$serverUrl/$resolvedPath";
          try {
            final File imageFile =
                await DefaultCacheManager().getSingleFile(imageUrl);
            final Uint8List bytes = await imageFile.readAsBytes();

            // Scale down the target size to 85% of requested size for consistency
            final int adjustedSize = (size * 0.85).toInt();

            // Get original image size to constrain the larger dimension (width or height)
            final ui.Codec tempCodec = await ui.instantiateImageCodec(bytes);
            final ui.FrameInfo tempFi = await tempCodec.getNextFrame();
            final int origW = tempFi.image.width;
            final int origH = tempFi.image.height;

            int targetW;
            int targetH;
            if (origW > origH) {
              targetW = adjustedSize;
              targetH = (origH * adjustedSize / origW).toInt();
            } else {
              targetH = adjustedSize;
              targetW = (origW * adjustedSize / origH).toInt();
            }

            // Resize image using instantiateImageCodec
            final ui.Codec codec =
                await ui.instantiateImageCodec(bytes, targetWidth: targetW, targetHeight: targetH);
            final ui.FrameInfo fi = await codec.getNextFrame();
            final ui.Image decodedImage = fi.image;

            // Directly load the server image in its raw original colors (no custom color filter/tint)
            final Uint8List finalBytes = (await decodedImage.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List();

            final descriptor = BitmapDescriptor.bytes(finalBytes);
            _markerIconCache[cacheKey] = descriptor;
            return descriptor;
          } catch (serverErr) {
            debugPrint("Server icon fetch failed: $serverErr.");
          }
        }
      }

      return BitmapDescriptor.defaultMarker;
    } catch (e) {
      debugPrint("Failed to fetch server icon: $e. Returning default marker.");
      return BitmapDescriptor.defaultMarker;
    }
  }

  // static Future<BitmapDescriptor> getMarkerVehicleIcon(String imagePath, {required int width,required int height}) async {
  //   final String imageUrl = UserRepository.getServerUrl()! + "/" + imagePath;
  //   final File imageFile = await DefaultCacheManager().getSingleFile(imageUrl);
  //   final Uint8List bytes = await imageFile.readAsBytes();
  //   return BitmapDescriptor.bytes(bytes);
  // }

  // Add to util.dart

  /// Get a resized marker icon for smooth performance
  // static Future<BitmapDescriptor> getScaledMarkerIcon(
  //     String imagePath, {
  //       int size =40, // Smaller size for better performance
  //     }) async {
  //   try {
  //     final String imageUrl = "${UserRepository.getServerUrl()}/$imagePath";
  //     final File imageFile = await DefaultCacheManager().getSingleFile(imageUrl);
  //     final Uint8List originalBytes = await imageFile.readAsBytes();
  //
  //     // Decode and resize the image
  //     final ui.Codec codec = await ui.instantiateImageCodec(
  //       originalBytes,
  //       targetWidth: 20,
  //       targetHeight: 38,
  //     );
  //     final ui.FrameInfo frameInfo = await codec.getNextFrame();
  //     final ui.Image resizedImage = frameInfo.image;
  //
  //     // Convert to bytes
  //     final ByteData? byteData = await resizedImage.toByteData(
  //       format: ui.ImageByteFormat.png,
  //     );
  //
  //     if (byteData == null) {
  //       return BitmapDescriptor.defaultMarker;
  //     }
  //
  //     return BitmapDescriptor.bytes(byteData.buffer.asUint8List());
  //   } catch (e) {
  //     debugPrint('Error loading marker icon: $e');
  //     return BitmapDescriptor.defaultMarker;
  //   }
  // }
  //
  // /// Pre-cache marker icon for instant access
  // static BitmapDescriptor? _cachedMarkerIcon;
  // static String? _cachedMarkerPath;
  //
  // static Future<BitmapDescriptor> getCachedMarkerIcon(
  //     String imagePath, {
  //       int size = 48,
  //     }) async {
  //   if (_cachedMarkerIcon != null && _cachedMarkerPath == imagePath) {
  //     return _cachedMarkerIcon!;
  //   }
  //
  //   _cachedMarkerIcon = await getScaledMarkerIcon(imagePath, size: size);
  //   _cachedMarkerPath = imagePath;
  //   return _cachedMarkerIcon!;
  static Widget getVehicleIconWidget(String? imagePath, Color color, {double size = 40, String? iconType, String? deviceName, dynamic deviceId, DeviceItem? device}) {
    final bool isMoving = color == const Color(0xFF00C853);

    // 1. Check if the user set a custom icon locally in the app (Highest priority)
    if (deviceId != null) {
      final String? savedAsset = UserRepository.prefs
          ?.getString("custom_icon_path_${deviceId.toString()}");
      if (savedAsset != null && savedAsset.isNotEmpty) {
        debugPrint("[DEBUG ICON] Custom icon preference found for device $deviceId ($deviceName): $savedAsset");
        final Widget img = Image.asset(
          savedAsset,
          width: size,
          height: size,
          fit: BoxFit.contain,
        );
        return isMoving
            ? img
            : ColorFiltered(colorFilter: getTintFilter(color), child: img);
      }
    }

    // 2. Fetch the server PNG image directly
    if (imagePath != null && imagePath.isNotEmpty) {
      final String? serverUrl = UserRepository.getServerUrl();
      if (serverUrl != null && serverUrl.isNotEmpty) {
        final String resolvedPath = resolveStatusIconPath(
            imagePath, color,
            isOnline: device != null ? isDeviceOnline(device) : color != const Color(0xFFE53935));

        final Widget fallbackImg = Icon(
          Icons.directions_car,
          color: color,
          size: size * 0.7,
        );

        debugPrint("[DEBUG IMAGE URL] requesting: $serverUrl/$resolvedPath");

        return CachedNetworkImage(
          imageUrl: "$serverUrl/$resolvedPath",
          width: size,
          height: size,
          fit: BoxFit.contain,
          placeholder: (context, url) => SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey),
              ),
            ),
          ),
          errorWidget: (context, url, error) => fallbackImg,
        );
      }
    }

    return Icon(
      Icons.directions_car,
      color: color,
      size: size * 0.7,
    );
  }

  static Widget getChangeIconWidget(String? imagePath, {double size = 55, String? iconType, String? deviceName, dynamic deviceId}) {
    if (imagePath != null && imagePath.isNotEmpty) {
      final String? serverUrl = UserRepository.getServerUrl();
      if (serverUrl != null && serverUrl.isNotEmpty) {
        return CachedNetworkImage(
          imageUrl: "$serverUrl/$imagePath",
          width: size,
          height: size,
          fit: BoxFit.contain,
          placeholder: (context, url) => const SizedBox(
            width: 30,
            height: 30,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (context, url, error) => Icon(
            Icons.directions_car,
            color: Colors.grey[600],
            size: size * 0.7,
          ),
        );
      }
    }

    return Icon(
      Icons.directions_car,
      color: Colors.grey[600],
      size: size * 0.7,
    );
  }

  static int? parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    final str = value.toString().trim();
    if (str.isEmpty) return null;
    final parsedInt = int.tryParse(str);
    if (parsedInt != null) return parsedInt;
    try {
      return DateTime.parse(str.replaceAll(' ', 'T')).millisecondsSinceEpoch ~/ 1000;
    } catch (_) {
      try {
        return DateTime.parse(str).millisecondsSinceEpoch ~/ 1000;
      } catch (_) {
        return null;
      }
    }
  }

  static int? parseStopDurationSec(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    final str = value.toString().trim();
    if (str.isEmpty) return null;
    return int.tryParse(str);
  }
}

