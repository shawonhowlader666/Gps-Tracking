import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SvgAssetColorizer extends StatelessWidget {
  final String assetPath;
  final Color color;
  final double? width;
  final double? height;

  // Static cache to store loaded SVG strings in memory
  static final Map<String, String> _svgCache = {};

  const SvgAssetColorizer({
    super.key,
    required this.assetPath,
    required this.color,
    this.width,
    this.height,
  });

  Future<String> _loadSvg(String path) async {
    try {
      debugPrint("SvgAssetColorizer: Loading asset path -> $path");
      final data = await rootBundle.loadString(path);
      _svgCache[path] = data;
      return data;
    } catch (e, stack) {
      debugPrint("SvgAssetColorizer: Failed to load asset $path. Error: $e\n$stack");
      rethrow;
    }
  }

  Widget _buildSvg(String svgData) {
    try {
      // Safely convert color to 6-digit hex code, compatible with all Flutter SDK versions
      final hexColor = '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toLowerCase()}';
      final colorizedSvg = svgData.replaceAll('#MAIN_COLOR', hexColor);
      
      debugPrint("SvgAssetColorizer: Colorized $assetPath with $hexColor");
      return SvgPicture.string(
        colorizedSvg,
        width: width,
        height: height,
        fit: BoxFit.contain,
      );
    } catch (e, stack) {
      debugPrint("SvgAssetColorizer: Error colorizing/building SVG $assetPath: $e\n$stack");
      return _buildPlaceholder();
    }
  }

  Widget _buildPlaceholder() {
    return SizedBox(
      width: width,
      height: height,
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF10B981),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_svgCache.containsKey(assetPath)) {
      return _buildSvg(_svgCache[assetPath]!);
    }

    return FutureBuilder<String>(
      future: _loadSvg(assetPath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
          return _buildSvg(snapshot.data!);
        } else if (snapshot.hasError) {
          debugPrint("SvgAssetColorizer: FutureBuilder error for $assetPath: ${snapshot.error}");
          // Return a fallback asset directly if loading fails
          return const Icon(Icons.directions_car, color: Colors.grey, size: 24);
        }
        
        return _buildPlaceholder();
      },
    );
  }
}
