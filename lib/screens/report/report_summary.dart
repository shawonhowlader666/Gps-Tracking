import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class TravelRecord {
  final String date;
  final String startTime;
  final String endTime;
  final String travelTime;
  final String distance;
  final String moveDuration;

  TravelRecord({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.travelTime,
    required this.distance,
    required this.moveDuration,
  });
}

class ReportSummaryPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _ReportSummaryPageState();
}

class _ReportSummaryPageState extends State<ReportSummaryPage> {
  static ReportArguments? args;
  Timer? _timer;
  bool isLoading = true;
  static var httpClient = HttpClient();
  File? file;
  String? url;
  String extractedText = "loadingPDF".tr;
  String _na = "notAvailable".tr;
  bool isExtracting = false;
  List<TravelRecord> travelRecords = [];
  String reportPeriod = '';
  String deviceId = '';
  String reportType = '';

  // Add filtering variables
  String _selectedFilter = 'Today';
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  final List<String> _filterOptions = [
    'today'.tr,
    'yesterday'.tr,
    'last2Days'.tr,
    'last3Days'.tr,
    'thisWeek'.tr,
    'thisMonth'.tr,
    'lastMonth'.tr,
    'custom'.tr
  ];

  @override
  void initState() {
    super.initState();
    _setDefaultDates();
    getReport();
  }

  void _setDefaultDates() {
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, now.day);
    _toDate =
        DateTime(now.year, now.month, now.day + 1); // Tomorrow for date_to
  }

  void _handleFilterChange(String filter) async {
    setState(() {
      _selectedFilter = filter;
    });

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (filter == 'today'.tr) {
      _fromDate = today;
      _toDate = today.add(Duration(days: 1));
    } else if (filter == 'yesterday'.tr) {
      _fromDate = today.subtract(Duration(days: 1));
      _toDate = today;
    } else if (filter == 'last2Days'.tr) {
      _fromDate = today.subtract(Duration(days: 2));
      _toDate = today.add(Duration(days: 1));
    } else if (filter == 'last3Days'.tr) {
      _fromDate = today.subtract(Duration(days: 3));
      _toDate = today.add(Duration(days: 1));
    } else if (filter == 'thisWeek'.tr) {
      _fromDate = today.subtract(Duration(days: today.weekday - 1));
      _toDate = today.add(Duration(days: 1));
    } else if (filter == 'thisMonth'.tr) {
      _fromDate = DateTime(now.year, now.month, 1);
      _toDate = today.add(Duration(days: 1));
    } else if (filter == 'lastMonth'.tr) {
      final firstDayLastMonth = DateTime(now.year, now.month - 1, 1);
      final lastDayLastMonth = DateTime(now.year, now.month, 0);
      _fromDate = firstDayLastMonth;
      _toDate = lastDayLastMonth.add(Duration(days: 1));
    } else if (filter == 'custom'.tr) {
      final DateTimeRange? picked = await material.showDateRangePicker(
        context: context,
        firstDate: DateTime(2015),
        lastDate: today,
        initialDateRange: DateTimeRange(
          start: _fromDate,
          end: _toDate,
        ),
      );

      if (picked != null) {
        _fromDate = picked.start;
        _toDate = picked.end.add(Duration(days: 1)); // Add 1 day to end date
      } else {
        return; // User cancelled, don't refresh
      }
    }

    // Format dates for API (time will always be 00:00:00 to 23:59:59)
    final fromDateStr = _formatDateForApi(_fromDate);
    final toDateStr = _formatDateForApi(_toDate);
    final fromTimeStr = "00:00:00";
    final toTimeStr = "23:59:59";

    // Refresh data with new dates
    _refreshData(
      fromDate: fromDateStr,
      toDate: toDateStr,
      fromTime: fromTimeStr,
      toTime: toTimeStr,
    );
  }

  String _formatDateForApi(DateTime date) {
    String month = date.month < 10 ? "0${date.month}" : date.month.toString();
    String day = date.day < 10 ? "0${date.day}" : date.day.toString();
    return "${date.year}-$month-$day";
  }

  void _refreshData({
    required String fromDate,
    required String toDate,
    required String fromTime,
    required String toTime,
  }) {
    setState(() {
      isLoading = true;
      extractedText = "loadingPdfContent".tr;
      travelRecords = [];
    });

    // Update the args with new dates
    args = ReportArguments(
      args!.id,
      fromDate,
      fromTime,
      toDate,
      toTime,
      args!.name,
      args!.type,
      args!.deviceItem,
    );

    // Call API with new dates
    APIService.getReport(args!.id.toString(), fromDate, toDate, args!.type)
        .then((value) {
      if (value != null && value.url != null) {
        String decodedUrl = Uri.decodeFull(value.url!);
        String correctedUrl = decodedUrl.replaceAll('%5B0%5D', '[]');
        String correctedUrl2 = correctedUrl.replaceAll('[0]', '[]');
        String correctedUrl3 =
            correctedUrl2.replaceAll('send_to_email[]=', 'send_to_email=');
        url = correctedUrl3;
        _downloadFile(url!, "general");
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<String> extractTextFromPdf(File file) async {
    try {
      final bytes = file.readAsBytesSync();

      // Load PDF document
      final PdfDocument document = PdfDocument(inputBytes: bytes);

      // Create text extractor
      final PdfTextExtractor extractor = PdfTextExtractor(document);

      // Extract full text
      final String text = extractor.extractText();

      document.dispose();

      _parseExtractedText(text);
      return text;
    } catch (e) {
      return "${'failedToExtract'.tr}: $e";
    }
  }

  void _parseExtractedText(String text) {
    final lines = text.split('\n');
    final records = <TravelRecord>[];

    // Parse header information
    if (lines.isNotEmpty) {
      deviceId = lines[0].trim(); // First line is device ID
    }

    if (lines.length > 1) {
      final periodMatch = RegExp(r'(\d{2}-\d{2}-\d{4}).*?(\d{2}-\d{2}-\d{4})')
          .firstMatch(lines[1]);
      if (periodMatch != null) {
        reportPeriod = '${periodMatch.group(1)} to ${periodMatch.group(2)}';
      }

      final typeMatch = RegExp(r'Report type: (.*)').firstMatch(lines[1]);
      if (typeMatch != null) {
        reportType = typeMatch.group(1) ?? '';
      }
    }

    // Parse travel records - start from line 3 (index 2) to skip headers
    for (int i = 3; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // Try matching the full format first
      final fullFormatMatch = RegExp(r'^(\d{2}-\d{2}-\d{4})\s+' // Date
              r'\d{2}-\d{2}-\d{4}\s+' // Repeated date (ignore)
              r'(\d{2}:\d{2}:\d{2}\s[AP]M)\s+' // Start time
              r'\d{2}-\d{2}-\d{4}\s+' // Repeated date (ignore)
              r'(\d{2}:\d{2}:\d{2}\s[AP]M)\s+' // End time
              r'((?:\d+h\s*)?(?:\d+min\s*)?(?:\d+s)?)\s+' // Travel time
              r'(\d+\.\d+)\sKm\s+' // Distance
              r'((?:\d+h\s*)?(?:\d+min\s*)?(?:\d+s)?)$' // Move duration
              )
          .firstMatch(line);

      if (fullFormatMatch != null) {
        records.add(TravelRecord(
          date: fullFormatMatch.group(1)!,
          startTime: fullFormatMatch.group(2)!,
          endTime: fullFormatMatch.group(3)!,
          travelTime: fullFormatMatch.group(4)!,
          distance: '${fullFormatMatch.group(5)} Km',
          moveDuration: fullFormatMatch.group(6)!,
        ));
      } else {
        // Try matching the simplified format (date - - time distance time)
        final simpleFormatMatch = RegExp(r'^(\d{2}-\d{2}-\d{4})\s+' // Date
                r'-\s+' // Separator
                r'-\s+' // Separator
                r'((?:\d+h\s*)?(?:\d+min\s*)?(?:\d+s)?)\s+' // Travel time
                r'(\d+\.\d+)\sKm\s+' // Distance
                r'((?:\d+h\s*)?(?:\d+min\s*)?(?:\d+s)?)$' // Move duration
                )
            .firstMatch(line);

        if (simpleFormatMatch != null) {
          records.add(TravelRecord(
            date: simpleFormatMatch.group(1)!,
            startTime: _na,
            // No time info in this format
            endTime: _na,
            // No time info in this format
            travelTime: simpleFormatMatch.group(2)!,
            distance: '${simpleFormatMatch.group(3)} Km',
            moveDuration: simpleFormatMatch.group(4)!,
          ));
        } else {
          print('Failed to parse line (unrecognized format): $line');
        }
      }
    }

    setState(() {
      travelRecords = records;
    });

    // Debug output
    print('Successfully parsed ${travelRecords.length} records:');
    for (final record in records) {
      print('''
  Date: ${record.date}
  Start: ${record.startTime}
  End: ${record.endTime}
  Travel Time: ${record.travelTime}
  Distance: ${record.distance}
  Move Duration: ${record.moveDuration}
  '''
          .trim());
    }
  }

  getReport() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (args != null) {
        timer.cancel();
        APIService.getReport(
          args!.id.toString(),
          args!.fromDate,
          args!.toDate,
          args!.type,
        ).then((value) {
          String decodedUrl = Uri.decodeFull(value!.url!);
          String correctedUrl = decodedUrl.replaceAll('%5B0%5D', '[]');
          String correctedUrl2 = correctedUrl.replaceAll('[0]', '[]');
          String correctedUrl3 =
              correctedUrl2.replaceAll('send_to_email[]=', 'send_to_email=');
          url = correctedUrl3;
          _downloadFile(url!, "general");
        });
      }
    });
  }

  Future<void> _downloadFile(String url, String filename) async {
    try {
      setState(() => isExtracting = true);

      var request = await httpClient.getUrl(Uri.parse(url));
      var response = await request.close();
      var bytes = await consolidateHttpClientResponseBytes(response);

      String dir = (await getApplicationDocumentsDirectory()).path;
      File pdffile =
          File('$dir/$filename-${DateTime.now().millisecondsSinceEpoch}.pdf');
      file = pdffile;
      await file!.writeAsBytes(bytes);

      final text = await extractTextFromPdf(file!);
      setState(() {
        extractedText = text;
        isExtracting = false;
      });
    } catch (e) {
      setState(() {
        extractedText = "${'failedToProcess'.tr}: ${e.toString()}";
        isExtracting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    args = ModalRoute.of(context)!.settings.arguments as ReportArguments;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        automaticallyImplyLeading: true,
        iconTheme: IconThemeData(color: CustomColor.cssBlack),
        title: Text(
          args!.name,
          style: FlutterFlowTheme.of(context).headlineMedium,
        ),
        actions: [
          IconButton(
            tooltip: "download".tr,
            icon: Icon(Icons.download),
            onPressed: () => _downloadFile(url!, "general"),
          ),
        ],
        centerTitle: false,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Add the filter chip bar
          _buildFilterChips(),
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        children: _filterOptions.map((filter) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(filter),
              selected: _selectedFilter == filter,
              onSelected: (bool selected) {
                if (selected) {
                  _handleFilterChange(filter);
                }
              },
              selectedColor: CustomColor.primaryColor.withOpacity(0.2),
              backgroundColor: Colors.grey[200],
              labelStyle: TextStyle(
                color: _selectedFilter == filter
                    ? CustomColor.primaryColor
                    : Colors.black87,
              ),
              shape: StadiumBorder(
                side: BorderSide(
                  color: _selectedFilter == filter
                      ? CustomColor.primaryColor
                      : Colors.grey[300]!,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContent() {
    if (isExtracting) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("processingPDF".tr),
          ],
        ),
      );
    }

    if (extractedText.startsWith("Failed")) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            extractedText,
            style: TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (travelRecords.isEmpty) {
      return Center(
        child: Text("noTravelRecords".tr),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildReportHeader(),
          SizedBox(height: 20),
          ...travelRecords.map((record) => _buildTravelCard(record)).toList(),
        ],
      ),
    );
  }

  Widget _buildReportHeader() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('reportPeriod'.tr,
                style: TextStyle(fontSize: 14, color: Colors.grey)),
            SizedBox(height: 4),
            Text(reportPeriod,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Text('${'device'.tr}: $deviceId', style: TextStyle(fontSize: 14)),
            Text('${'reportType'.tr}: $reportType',
                style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildTravelCard(TravelRecord record) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(record.date,
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                _buildTimeRange(record.startTime, record.endTime),
              ],
            ),
            SizedBox(height: 12),
            Divider(height: 1),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricCard(
                    'travelTime'.tr, record.travelTime, Icons.timer),
                _buildMetricCard(
                    'distance'.tr, record.distance, Icons.directions),
                _buildMetricCard('moveDuration'.tr, record.moveDuration,
                    Icons.directions_car),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRange(String start, String end) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(start, style: TextStyle(color: Colors.blue[800])),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.arrow_forward, size: 16, color: Colors.blue[800]),
          ),
          Text(end, style: TextStyle(color: Colors.blue[800])),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Colors.blue),
        SizedBox(height: 4),
        Text(title, style: TextStyle(fontSize: 12, color: Colors.grey)),
        SizedBox(height: 4),
        Text(value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
