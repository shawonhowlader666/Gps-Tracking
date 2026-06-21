import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class ReportTripPage extends StatefulWidget {
  const ReportTripPage({super.key});

  @override
  State<StatefulWidget> createState() => _ReportTripPageState();
}

class _ReportTripPageState extends State<ReportTripPage> {
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  static ReportArguments? args;
  StreamController<int>? _postsController;
  bool isLoading = true;
  static var httpClient = HttpClient();
  File? file;
  String? url;

  @override
  void initState() {
    _postsController = StreamController();
    getReport();
    super.initState();
  }

  void getReport() {}

  Future<File?>? downloadReport(String url, String filename) async {
    Random random = Random();
    random.nextInt(100);
    print(url);
    var request = await httpClient.getUrl(Uri.parse(url));
    var response = await request.close();
    var bytes = await consolidateHttpClientResponseBytes(response);
    writeFile(bytes, "$filename${DateTime.now().millisecond}.pdf");
    _postsController!.add(1);
    await file!.writeAsBytes(bytes);
    Fluttertoast.showToast(
        msg: ("excelDownloaded").tr,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 1,
        backgroundColor: Colors.black54,
        textColor: Colors.white,
        fontSize: 16.0);
    return file;
  }

  Future<void> writeToFile(Uint8List data, String path) {
    final buffer = data.buffer;
    return File(path).writeAsBytes(
        buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  Future<File> writeFile(Uint8List data, String name) async {
    // storage permission ask
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      await Permission.storage.request();
    }
    // the downloads folder path
    Directory? tempDir = await getDownloadsDirectory();
    String tempPath = tempDir!.path;
    var filePath = '$tempPath/$name';
    //

    // the data
    var bytes = ByteData.view(data.buffer);
    final buffer = bytes.buffer;
    // save the data in the path
    return File(filePath).writeAsBytes(
        buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
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
        floatingActionButton: FloatingActionButton(
          elevation: 0,
          onPressed: () {
            downloadReport(url!, "work");
          },
          child: const Icon(Icons.download_rounded),
        ),
        body: StreamBuilder<int>(
            stream: _postsController!.stream,
            builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
              if (snapshot.hasData) {
                return SfPdfViewer.file(
                  file!,
                  key: _pdfViewerKey,
                );
              } else if (isLoading) {
                return Center(
                  child: CircularProgressIndicator(),
                );
              } else {
                return Center(
                  child: Text(('noData').tr),
                );
              }
            }));
  }
}
