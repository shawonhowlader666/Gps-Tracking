import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class ImageFetcher {
  final String url;

  ImageFetcher(this.url);

  Future<void> downloadAndSaveImages() async {
    final file = await DefaultCacheManager().getSingleFile(url);
    final localPath = await _getLocalPath();
    final localFile = File('$localPath/${url.split('/').last}');
    await localFile.writeAsBytes(await file.readAsBytes());
  }

  Future<List<String>> getLocalImages() async {
    final localPath = await _getLocalPath();
    final directory = Directory(localPath);
    final List<String> localImages = [];
    await for (var entity in directory.list()) {
      if (entity is File) {
        localImages.add(entity.path);
      }
    }
    return localImages;
  }

  Future<String> _getLocalPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }
}
