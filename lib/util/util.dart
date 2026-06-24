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
import 'package:cached_network_image/cached_network_image.dart';
import 'package:smart_lock/theme/custom_color.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
import 'package:smart_lock/screens/data_controller/data_controller.dart';

class Util {
  static final Map<String, BitmapDescriptor> _markerIconCache = {};

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
    return DateFormat('dd-MM-yyyy').format(date.toLocal());
  }

  static String formatReportTime(DateTime date) {
    return DateFormat('HH:mm:ss').format(date.toLocal());
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

  static Future<BitmapDescriptor> getMarkerIconImagePath(String imagePath,
      String infoText, Color color, double rotateDegree, bool showTitle) async {
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

  static Future<BitmapDescriptor> getMarkerIconFromUrl(String imagePath,
      String infoText, Color color, double rotateDegree, bool showTitle) async {
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

  static String _getCacheKey(String imagePath, int size,
      {String? statusColor,
      String? iconType,
      String? deviceName,
      dynamic deviceId}) {
    final String? localAssetPath = getLocalMappedAsset(imagePath,
        iconType: iconType, deviceName: deviceName, deviceId: deviceId);
    return "${imagePath}_${size}_${statusColor ?? 'default'}_${iconType ?? 'default'}_${deviceName ?? 'default'}_${deviceId ?? 'default'}_${localAssetPath ?? 'default'}_v7";
  }

  static BitmapDescriptor? getCachedMarkerIcon(String imagePath, int size,
      {String? statusColor,
      String? iconType,
      String? deviceName,
      dynamic deviceId}) {
    final String cacheKey = _getCacheKey(imagePath, size,
        statusColor: statusColor,
        iconType: iconType,
        deviceName: deviceName,
        deviceId: deviceId);
    return _markerIconCache[cacheKey];
  }

  static Future<BitmapDescriptor> getMarkerIcon(String imagePath,
      {int size = 38,
      String? statusColor,
      String? iconType,
      String? deviceName,
      dynamic deviceId}) async {
    final String? localAssetPath = getLocalMappedAsset(imagePath,
        iconType: iconType, deviceName: deviceName, deviceId: deviceId);
    final String cacheKey = _getCacheKey(imagePath, size,
        statusColor: statusColor,
        iconType: iconType,
        deviceName: deviceName,
        deviceId: deviceId);
    if (_markerIconCache.containsKey(cacheKey)) {
      return _markerIconCache[cacheKey]!;
    }
    try {
      // Check if we have a local mapped PNG
      if (localAssetPath != null) {
        debugPrint(
            "getMarkerIcon local asset path matched: '$localAssetPath' for '$imagePath', deviceId: '$deviceId'");
        final tintColor = _getColorFromStatus(statusColor, imagePath);
        final Uint8List? bytes =
            await getTintedBytesFromAsset(localAssetPath, size, tintColor);
        if (bytes != null) {
          final descriptor = BitmapDescriptor.bytes(bytes);
          _markerIconCache[cacheKey] = descriptor;
          debugPrint(
              "getMarkerIcon LOADED local asset: '$localAssetPath' size: $size tint: $tintColor");
          return descriptor;
        } else {
          debugPrint(
              "getMarkerIcon FAILED to load tinted bytes for local asset: '$localAssetPath'");
        }
      }

      // Fetch the server PNG image directly
      final String imageUrl = "${UserRepository.getServerUrl()!}/$imagePath";
      final File imageFile =
          await DefaultCacheManager().getSingleFile(imageUrl);
      final Uint8List bytes = await imageFile.readAsBytes();

      // Resize image using instantiateImageCodec
      final ui.Codec codec =
          await ui.instantiateImageCodec(bytes, targetWidth: size);
      final ui.FrameInfo fi = await codec.getNextFrame();
      final Uint8List resizedBytes =
          (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List();

      final descriptor = BitmapDescriptor.bytes(resizedBytes);
      _markerIconCache[cacheKey] = descriptor;
      return descriptor;
    } catch (e) {
      debugPrint("Failed to fetch server icon: $e. Returning default marker.");
      return BitmapDescriptor.defaultMarker;
    }
  }

  static String? getLocalMappedAsset(String? imagePath,
      {String? iconType, String? deviceName, dynamic deviceId}) {
    if (imagePath == null &&
        iconType == null &&
        deviceName == null &&
        deviceId == null) return null;

    if (deviceId != null) {
      final String? savedAsset = UserRepository.prefs
          ?.getString("custom_icon_path_${deviceId.toString()}");
      if (savedAsset != null && savedAsset.isNotEmpty) {
        debugPrint(
            "getLocalMappedAsset PREFERENCE matched: '$savedAsset' for device ID '$deviceId'");
        return savedAsset;
      }
    }

    debugPrint(
        "getLocalMappedAsset CALLED with imagePath: '$imagePath', iconType: '$iconType', deviceName: '$deviceName', deviceId: '$deviceId'");
    final path =
        "${imagePath?.toLowerCase() ?? ''} ${iconType?.toLowerCase() ?? ''} ${deviceName?.toLowerCase() ?? ''}"
            .trim();
    if (path.isEmpty) return null;

    String? result;

    // 1. High priority keyword matching (e.g. from device name) to prioritize user-given device name types
    if (path.contains('ambulance')) {
      result = 'assets/images/ambulance_toprunning.png';
    } else if (path.contains('motorcycle') ||
        path.contains('bike') ||
        path.contains('scooter') ||
        path.contains('scotty')) {
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
    } else if (path.contains('cng') ||
        path.contains('rickshaw') ||
        path.contains('auto') ||
        path.contains('tempo')) {
      result = 'assets/images/tempotvr_toprunning.png';
    } else if (path.contains('truck')) {
      result = 'assets/images/truck_toprunning.png';
    }

    // 2. Default/Fallback Server Path & Hash matching
    if (result == null) {
      if (path.contains('6877e65ea4be98.96057559') ||
          path.contains('6877e65ea4be98.96057559_online') ||
          path.contains('6877e65ea4be98.96057559_offline')) {
        result = 'assets/images/car_green.png';
      } else if (path.contains('6877e682a122d5.26467715')) {
        result = 'assets/images/suv_toprunning.png';
      } else if (path.contains('68919e188759f4.90604553_online') ||
          path.contains('68919e188759f4.90604553_offline') ||
          path.contains('68919e188759f4.90604553_ack')) {
        result = 'assets/images/car_green.png';
      } else if (path.contains('694676186e6877.76876067')) {
        result = 'assets/images/muv_toprunning.png';
      } else if (path.contains('694bd24618ce36.67143977')) {
        result = 'assets/images/pickup_toprunning.png';
      } else if (path.contains('697613f6c938a0.41043256')) {
        result = 'assets/images/car_green.png';
      } else if (path.contains('697d973eeaedd3.55855774')) {
        result = 'assets/images/bus_toprunning.png';
      } else if (path.contains('697daf738d1b75.34407076_online') ||
          path.contains('697daf738d1b75.34407076_offline') ||
          path.contains('697daf738d1b75.34407076_ack')) {
        result = 'assets/images/car_green.png';
      } else if (path.contains('697ddf3220bbe8.30991600')) {
        result = 'assets/images/ambulance_toprunning.png';
      } else if (path.contains('697de4afdb0ed9.71856605_online') ||
          path.contains('697de4afdb0ed9.71856605_offline') ||
          path.contains('697de4afdb0ed9.71856605_ack') ||
          path.contains('697de4afdb0ed9.71856605_engine')) {
        result = 'assets/images/car_green.png';
      } else if (path.contains('697de539b850a9.16646834_online') ||
          path.contains('697de539b850a9.16646834_offline') ||
          path.contains('697de539b850a9.16646834_ack') ||
          path.contains('697de539b850a9.16646834_engine')) {
        result = 'assets/images/muv_toprunning.png';
      } else if (path.contains('697de5ef7182f1.91869408_online') ||
          path.contains('697de5ef7182f1.91869408_offline') ||
          path.contains('697de5ef7182f1.91869408_ack')) {
        result = 'assets/images/bus_toprunning.png';
      } else if (path.contains('6991da32795029.80377888_online') ||
          path.contains('6991da32795029.80377888_offline') ||
          path.contains('6991da32795029.80377888_ack')) {
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
        result = 'assets/images/car_green.png';
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
      } else if (path.contains('car') ||
          path.contains('1.png') ||
          path.contains('5.png') ||
          path.contains('rotating/')) {
        result = 'assets/images/car_green.png';
      }
    }

    // Default fallback
    result ??= 'assets/images/car_green.png';

    debugPrint(
        "getLocalMappedAsset RESULT: '$result' for path: '$imagePath', iconType: '$iconType', deviceName: '$deviceName'");
    return result;
  }

  static ColorFilter getTintFilter(Color color) {
    const double boost = 1.35;
    final double r = ((color.red / 255.0) * boost).clamp(0.0, 1.0);
    final double g = ((color.green / 255.0) * boost).clamp(0.0, 1.0);
    final double b = ((color.blue / 255.0) * boost).clamp(0.0, 1.0);
    return ColorFilter.matrix(<double>[
      0.15 * r,
      1.15 * r,
      0.1 * r,
      0,
      0,
      0.15 * g,
      1.15 * g,
      0.1 * g,
      0,
      0,
      0.15 * b,
      1.15 * b,
      0.1 * b,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  static Future<Uint8List?> getTintedBytesFromAsset(
      String path, int width, Color tintColor) async {
    if (path.isEmpty) return null;
    try {
      ByteData data = await rootBundle.load(path);
      ui.Codec codec =
          await ui.instantiateImageCodec(data.buffer.asUint8List());
      ui.FrameInfo fi = await codec.getNextFrame();
      ui.Image originalImage = fi.image;

      final double originalWidth = originalImage.width.toDouble();
      final double originalHeight = originalImage.height.toDouble();

      final double canvasSize = width.toDouble();
      double drawWidth, drawHeight;
      double dx, dy;

      if (originalHeight > originalWidth) {
        drawHeight = canvasSize;
        drawWidth = originalWidth * (canvasSize / originalHeight);
        dx = (canvasSize - drawWidth) / 2;
        dy = 0;
      } else {
        drawWidth = canvasSize;
        drawHeight = originalHeight * (canvasSize / originalWidth);
        dx = 0;
        dy = (canvasSize - drawHeight) / 2;
      }

      final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(pictureRecorder);

      final paint = Paint()..colorFilter = getTintFilter(tintColor);

      canvas.drawImageRect(
        originalImage,
        Rect.fromLTWH(0, 0, originalWidth, originalHeight),
        Rect.fromLTWH(dx, dy, drawWidth, drawHeight),
        paint,
      );

      final ui.Image tintedImage = await pictureRecorder
          .endRecording()
          .toImage(canvasSize.toInt(), canvasSize.toInt());
      final ByteData? byteData =
          await tintedImage.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint("Error tinting image $path: $e");
      return null;
    }
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
    } else if (status == 'red' || status.contains('red')) {
      return CustomColor.primary; // Red for stopped (brand red)
    } else if (status == 'orange' ||
        status.contains('orange') ||
        status == 'expired') {
      return const Color(0xFFF97316); // Orange for expired
    } else {
      return const Color(0xFF475569); // Slate/gray for offline
    }
  }

  static bool isExpired(DeviceItem device) {
    try {
      final expiry = device.deviceData?.expirationDate?.toString();
      if (expiry == null || expiry.isEmpty) return false;
      final date = DateTime.tryParse(expiry);
      if (date == null) return false;
      return date.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  static bool isDeviceOnline(DeviceItem device) {
    final online = device.online?.toLowerCase().trim() ?? '';
    if (online.contains('offline')) return false;
    if (online.contains('online')) return true;

    final iconColor = device.iconColor?.toLowerCase().trim() ?? '';
    if (iconColor == 'green' || iconColor == 'yellow') return true;

    if (device.timestamp != null && device.timestamp! > 0) {
      try {
        final lastUpdate =
            DateTime.fromMillisecondsSinceEpoch(device.timestamp! * 1000);
        if (DateTime.now().difference(lastUpdate).inMinutes < 5) return true;
      } catch (_) {}
    }

    final speed = double.tryParse(device.speed.toString()) ?? 0;
    return speed > 0;
  }

  static bool isEngineOn(DeviceItem device) {
    // Check local override first
    final devId = device.id;
    if (devId != null) {
      final engineOverride = DataController.getLocalEngineOverride(devId);
      if (engineOverride != null) {
        return ['on', '1', 'true', 'ign on', 'engine on', 'acc on']
            .contains(engineOverride.toLowerCase().trim());
      }
    }

    // 1. explicit engineStatus field
    if (device.engineStatus != null) {
      final status = device.engineStatus;
      if (status is bool) return status;
      if (status is int) return status == 1;
      if (status is String) {
        final s = status.toLowerCase().trim();
        if (['on', '1', 'true', 'ign on', 'engine on', 'acc on'].contains(s))
          return true;
        if (['off', '0', 'false', 'ign off', 'engine off', 'acc off']
            .contains(s)) return false;
      }
    }

    // 2. sensor array
    if (device.sensors != null) {
      for (final sensor in device.sensors!) {
        try {
          final type = (sensor['type'] ?? '').toString().toLowerCase();
          final sName = (sensor['name'] ?? '').toString().toLowerCase();
          final value = sensor['value'];
          final isIgnSensor = type == 'acc' ||
              type == 'ignition' ||
              type == 'engine' ||
              sName.contains('ignition') ||
              sName.contains('acc') ||
              sName.contains('engine');
          if (!isIgnSensor || value == null) continue;
          if (value is bool) return value;
          if (value is int) return value == 1;
          if (value is String) {
            final v = value.toLowerCase().trim();
            if (['on', '1', 'true', 'ign on', 'acc on', 'engine on']
                .contains(v)) return true;
            if (['off', '0', 'false', 'ign off', 'acc off', 'engine off']
                .contains(v)) return false;
          }
        } catch (_) {}
      }
    }

    // 3. iconColor fallback
    final iconColor = device.iconColor?.toLowerCase().trim() ?? '';
    if (iconColor == 'yellow' || iconColor == 'green') return true;

    // 4. speed fallback — if moving, engine must be on
    final speed = double.tryParse(device.speed.toString()) ?? 0;
    return speed > 0;
  }

  static String getDeviceStatusColorStr(DeviceItem device) {
    if (isExpired(device)) return "orange";
    if (!isDeviceOnline(device)) return "grey";

    final speed = double.tryParse(device.speed.toString()) ?? 0;
    if (speed > 0) return "green"; // Moving
    if (isEngineOn(device)) return "yellow"; // Engine ON, speed == 0
    return "red"; // Engine OFF, speed == 0
  }

  static Widget getVehicleIconWidget(String? imagePath, Color color,
      {double size = 40,
      String? iconType,
      String? deviceName,
      dynamic deviceId}) {
    if (imagePath != null && imagePath.isNotEmpty) {
      final String? localAsset = getLocalMappedAsset(imagePath,
          iconType: iconType, deviceName: deviceName, deviceId: deviceId);
      if (localAsset != null) {
        return ColorFiltered(
          colorFilter: getTintFilter(color),
          child: Image.asset(
            localAsset,
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
        );
      }

      final String? serverUrl = UserRepository.getServerUrl();
      if (serverUrl != null && serverUrl.isNotEmpty) {
        return CachedNetworkImage(
          imageUrl: "$serverUrl/$imagePath",
          width: size,
          height: size,
          fit: BoxFit.contain,
          placeholder: (context, url) => Icon(
            Icons.directions_car,
            color: color,
            size: size * 0.7,
          ),
          errorWidget: (context, url, error) => Icon(
            Icons.directions_car,
            color: color,
            size: size * 0.7,
          ),
        );
      }
    }

    return Image.asset(
      'assets/images/car_green.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }

  static Widget getChangeIconWidget(String? imagePath,
      {double size = 55,
      String? iconType,
      String? deviceName,
      dynamic deviceId}) {
    if (imagePath != null && imagePath.isNotEmpty) {
      final String? localAsset = getLocalMappedAsset(imagePath,
          iconType: iconType, deviceName: deviceName, deviceId: deviceId);
      if (localAsset != null) {
        return Image.asset(
          localAsset,
          width: size,
          height: size,
          fit: BoxFit.contain,
        );
      }

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
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          errorWidget: (context, url, error) => Icon(
            Icons.image_not_supported,
            color: Colors.grey[400],
            size: size * 0.6,
          ),
        );
      }
    }

    return Image.asset(
      'assets/images/car_green.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
