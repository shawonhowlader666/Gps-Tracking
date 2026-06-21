import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class ReportFuelPage extends StatefulWidget {
  const ReportFuelPage({super.key});

  @override
  State<StatefulWidget> createState() => _ReportFuelPageState();
}

class _ReportFuelPageState extends State<ReportFuelPage> {
  static ReportArguments? args;
  StreamController<int>? _postsController;
  Timer? _timer;
  Timer? _timer2;
  bool isLoading = true;
  static var httpClient = HttpClient();
  File? file;
  late WebViewController _controller;

  var bytes;
  final Color _mapTypeBackgroundColor = CustomColor.primaryColor;
  final Color _mapTypeForegroundColor = CustomColor.secondaryColor;
  @override
  void initState() {
    _postsController = StreamController();

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller =
        WebViewController.fromPlatformCreationParams(params);
    // #enddocregion platform_features

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('WebView is loading (progress : $progress%)');
          },
          onPageStarted: (String url) {
            debugPrint('Page started loading: $url');
          },
          onPageFinished: (String url) {
            debugPrint('Page finished loading: $url');
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
Page resource error:
  code: ${error.errorCode}
  description: ${error.description}
  errorType: ${error.errorType}
  isForMainFrame: ${error.isForMainFrame}
          ''');
          },
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.startsWith('https://www.youtube.com/')) {
              debugPrint('blocking navigation to ${request.url}');
              return NavigationDecision.prevent;
            }
            debugPrint('allowing navigation to ${request.url}');
            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel('Toaster',
          onMessageReceived: (JavaScriptMessage message) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message.message)),
        );
      });

    // #docregion platform_features
    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    // #enddocregion platform_features

    _controller = controller;
    setState(() {});
    getReport();
    super.initState();
  }

  Future<File?> _downloadFile(String url, String filename) async {
    Random random = Random();
    int randomNumber = random.nextInt(100);
    var request = await httpClient.getUrl(Uri.parse(url));
    var response = await request.close();
    bytes = await consolidateHttpClientResponseBytes(response);
    String dir = (await getApplicationDocumentsDirectory()).path;
    File pdffile = File('$dir/$filename-$randomNumber.html');
    //Navigator.pop(context); // Load from assets
    file = pdffile;
    await file!.writeAsBytes(bytes);
    _loadHtmlFromAssets();
    return file;
  }

  void getReport() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (args != null) {
        timer.cancel();
        APIService.getReportHtml(
                args!.id.toString(), args!.fromDate, args!.toDate, args!.type)
            .then((value) => {
                  _downloadFile(value!.url!, "work"),
                  setState(() {
                    isLoading = false;
                  })
                });
      }
    });
  }

  Future<File?> writeFile() async {
    // storage permission ask
    Random random = Random();
    int randomNumber = random.nextInt(100);
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      await Permission.storage.request();
    }
    // the downloads folder path
    Directory? tempDir = await getDownloadsDirectory();
    String tempPath = tempDir!.path;
    File pdffile = File('$tempPath/work-$randomNumber.pdf');
    file = pdffile;
    await file!.writeAsBytes(bytes);

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('excelDownloaded'.tr)));

    return file;
  }

  Future<void> _loadHtmlFromAssets() async {
    setState(() {
      isLoading = false;
      _postsController!.add(1);
    });
    String fileHtmlContents = await file!.readAsString();
    _controller.loadHtmlString(Uri.dataFromString(fileHtmlContents,
            mimeType: 'text/html', encoding: Encoding.getByName('utf-8'))
        .toString());
  }

  @override
  void dispose() {
    _timer!.cancel();
    _timer2!.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    args = ModalRoute.of(context)!.settings.arguments as ReportArguments;

    return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          automaticallyImplyLeading: true,
          iconTheme: IconThemeData(color: CustomColor.cssBlack),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                args!.name,
                style: FlutterFlowTheme.of(context).headlineMedium,
              ),
            ],
          ),
          centerTitle: false,
          elevation: 0,
        ),
        floatingActionButton: !isLoading
            ? FloatingActionButton(
                heroTag: "mapType",
                mini: true,
                onPressed: writeFile,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                backgroundColor: _mapTypeBackgroundColor,
                foregroundColor: _mapTypeForegroundColor,
                child: const Icon(Icons.download_rounded, size: 30.0),
              )
            : Container(),
        body: StreamBuilder<int>(
            stream: _postsController!.stream,
            builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
              if (snapshot.data == 1) {
                return WebViewWidget(controller: _controller);
              } else if (isLoading) {
                return Center(
                  child: CircularProgressIndicator(),
                );
              } else if (snapshot.data == 0) {
                return Center(
                  child: Text(('noData')),
                );
              } else {
                return Center(
                  child: Text(('noData')),
                );
              }
            }));
  }
}
