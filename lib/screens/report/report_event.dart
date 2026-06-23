import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smart_lock/arguments/report_args.dart';
import 'package:smart_lock/flutter_flow/flutter_flow_theme.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/theme/custom_color.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class ReportEventPage extends StatefulWidget {
  const ReportEventPage({super.key});

  @override
  State<StatefulWidget> createState() => _ReportEventPageState();
}

class _ReportEventPageState extends State<ReportEventPage> {
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  static ReportArguments? args;
  StreamController<int>? _postsController;
  bool isLoading = true;
  static var httpClient = HttpClient();
  File? file;
  String? url;
  Timer? _timer;

  @override
  void initState() {
    _postsController = StreamController();
    getReport();
    super.initState();
  }

  void getReport() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (args != null) {
        timer.cancel();
        APIService.getReport(
                args!.id.toString(), args!.fromDate, args!.toDate, args!.type)
            .then((value) {
          String decodedUrl = Uri.decodeFull(value!.url!);

          String correctedUrl = decodedUrl.replaceAll('%5B0%5D', '[]');
          String correctedUrl2 = correctedUrl.replaceAll('[0]', '[]');
          String correctedUrl3 =
              correctedUrl2.replaceAll('send_to_email[]=', 'send_to_email=');
          url = correctedUrl3;
          print(url!);
          _downloadFile(url!, "event");
          // launch(value.url),
          //
        });
      }
    });
  }

  Future<File?> _downloadFile(String url, String filename) async {
    Random random = Random();
    int randomNumber = random.nextInt(100);
    var request = await httpClient.getUrl(Uri.parse(url));
    var response = await request.close();
    var bytes = await consolidateHttpClientResponseBytes(response);
    String dir = (await getApplicationDocumentsDirectory()).path;
    print(dir);
    File pdffile = File('$dir/$filename-$randomNumber.pdf');
    //Navigator.pop(context); // Load from assets
    file = pdffile;
    _postsController!.add(1);
    await file!.writeAsBytes(bytes);
    return file;
  }

  Future<File?>? downloadReport(String url, String filename) async {
    Random random = Random();
    random.nextInt(100);
    print(url);
    var request = await httpClient.getUrl(Uri.parse(url));
    var response = await request.close();
    var bytes = await consolidateHttpClientResponseBytes(response);
    // String dir = (await getApplicationDocumentsDirectory()).path;
    // File pdffile = new File('$dir/$filename-$randomNumber.pdf');
    // //Navigator.pop(context); // Load from assets
    // file = pdffile;
    writeFile(bytes, "$filename${DateTime.now().millisecond}.pdf");
    _postsController!.add(1);
    await file!.writeAsBytes(bytes);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('excelDownloaded'.tr)));
    return file;

    //new File(filePath).writeAsBytes(value.bodyBytes.buffer.asUint8List(value.bodyBytes.offsetInBytes, value.bodyBytes.lengthInBytes))
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
            downloadReport(url!, "event");
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

class ReportEventArgument {
  final int eventId;
  final int positionId;
  final Map<String, dynamic> attributes;
  final String type;
  final String name;
  ReportEventArgument(
      this.eventId, this.positionId, this.attributes, this.type, this.name);
}
