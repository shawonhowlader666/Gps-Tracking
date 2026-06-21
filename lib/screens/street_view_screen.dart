import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class StreetViewScreen extends StatefulWidget {
  final double latitude;
  final double longitude;

  const StreetViewScreen({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<StreetViewScreen> createState() => _StreetViewScreenState();
}

class _StreetViewScreenState extends State<StreetViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _usingFallback = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
          },
          onPageFinished: (url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            if (!_usingFallback) {
              // Try fallback URL if first attempt fails
              _loadFallbackUrl();
            } else {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          },
          onNavigationRequest: (request) {
            // Block intent:// URLs but allow the main page to load
            if (request.url.startsWith('intent://')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(
        Uri.parse(
          'https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${widget.latitude},${widget.longitude}&force=web',
        ),
      );
  }

  void _loadFallbackUrl() {
    setState(() => _usingFallback = true);
    _controller.loadRequest(
      Uri.parse(
        'https://www.google.com/maps/@${widget.latitude},${widget.longitude},3a,75y/data=!3m7!1e1!3m5!1s-!2e0!6s%2F%2Fgeo0.ggpht.com%2Fcbk%3Fpanoid%3Ddummy%26output%3Dthumbnail%26cb_client%3Dmaps_sv.tactile%26thumb%3D2%26w%3D203%26h%3D100%26yaw%3D0%26pitch%3D0!7i16384!8i8192',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Street View'),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
          if (_hasError)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Failed to load Street View'),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _usingFallback = false;
                        _controller.reload();
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
