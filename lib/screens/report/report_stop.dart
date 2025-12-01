import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class ReportStopPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => new _ReportStopPageState();
}

class _ReportStopPageState extends State<ReportStopPage> {
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  static ReportArguments? args;
  StreamController<int>? _postsController;
  bool isLoading = true;
  Timer? _timer;
  static var httpClient = new HttpClient();
  File? file;
  String? url;

  @override
  void initState() {
    _postsController = new StreamController();
    getReport();
    super.initState();
  }

  getReport() {
    _timer = new Timer.periodic(Duration(seconds: 1), (timer) {
      if (args != null) {
        timer.cancel();
        APIService.getReportStop(
                args!.id.toString(), args!.fromDate, args!.toDate, args!.type)
            .then((value) {
          String decodedUrl = Uri.decodeFull(value!.url!);

          String correctedUrl = decodedUrl.replaceAll('%5B0%5D', '[]');
          String correctedUrl2 = correctedUrl.replaceAll('[0]', '[]');
          String correctedUrl3 =
              correctedUrl2.replaceAll('send_to_email[]=', 'send_to_email=');
          url = correctedUrl3;
          print(url!);
          _downloadFile(url!, "stop");
          // launch(value.url),
          //
        });
      }
    });
  }

  Future<File?> _downloadFile(String url, String filename) async {
    Random random = new Random();
    int randomNumber = random.nextInt(100);
    print(url);
    if (url != null) {
      var request = await httpClient.getUrl(Uri.parse(url));
      var response = await request.close();
      var bytes = await consolidateHttpClientResponseBytes(response);
      String dir = (await getApplicationDocumentsDirectory()).path;
      File pdffile = new File('$dir/$filename-$randomNumber.pdf');
      //Navigator.pop(context); // Load from assets
      file = pdffile;
      _postsController!.add(1);
      await file!.writeAsBytes(bytes);
      return file;
    } else {
      isLoading = false;
      _postsController!.add(0);
      setState(() {});
    }
  }

  downloadReport(String url, String filename) async {
    Random random = new Random();
    int randomNumber = random.nextInt(100);
    print(url);
    if (url != null) {
      var request = await httpClient.getUrl(Uri.parse(url));
      var response = await request.close();
      var bytes = await consolidateHttpClientResponseBytes(response);
      writeFile(
          bytes, filename + DateTime.now().millisecond.toString() + ".pdf");
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
    } else {
      isLoading = false;
      _postsController!.add(0);
      setState(() {});
    }
  }

  Future<void> writeToFile(Uint8List data, String path) {
    final buffer = data.buffer;
    return new File(path).writeAsBytes(
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
    var filePath = tempPath + '/$name';
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
        floatingActionButton: new FloatingActionButton(
          child: const Icon(Icons.download_rounded),
          elevation: 0,
          onPressed: () {
            downloadReport(url!, "stop");
          },
        ),
        body: StreamBuilder<int>(
            stream: _postsController!.stream,
            builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
              if (snapshot.data == 1) {
                return SfPdfViewer.file(
                  file!,
                  key: _pdfViewerKey,
                );
              } else if (isLoading) {
                return Center(
                  child: CircularProgressIndicator(),
                );
              } else if (snapshot.data == 0) {
                return Center(
                  child: Text(('noData').tr),
                );
              } else {
                return Center(
                  child: Text(('noData').tr),
                );
              }
            }));
  }
}
