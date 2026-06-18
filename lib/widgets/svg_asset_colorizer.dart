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
    final data = await rootBundle.loadString(path);
    _svgCache[path] = data;
    return data;
  }

  Widget _buildSvg(String svgData) {
    // Convert color to hex code (e.g. #00C853)
    final hexColor = '#${color.toARGB32().toRadixString(16).substring(2).padLeft(6, '0')}';
    final colorizedSvg = svgData.replaceAll('#MAIN_COLOR', hexColor);
    
    return SvgPicture.string(
      colorizedSvg,
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
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
    // If SVG string is cached in memory, render it synchronously to avoid build flickering
    if (_svgCache.containsKey(assetPath)) {
      return _buildSvg(_svgCache[assetPath]!);
    }

    return FutureBuilder<String>(
      future: _loadSvg(assetPath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
          return _buildSvg(snapshot.data!);
        }
        
        // Return a circular loader while the SVG file is loading
        return _buildPlaceholder();
      },
    );
  }
}
