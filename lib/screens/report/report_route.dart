import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:get/get.dart';
import 'package:flutter/services.dart';

import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class ReportRoutePage extends StatefulWidget {
  @override
  _ReportRoutePageState createState() => _ReportRoutePageState();
}

class _ReportRoutePageState extends State<ReportRoutePage> {
  static ReportArguments? args;
  Timer? _timer;
  bool isLoading = true;
  File? file;
  String? url;
  String extractedText = "loadingPDF".tr;
  bool isExtracting = false;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  List<TextSpan> _highlightedSpans = [];
  List<String> pdfPages = [];
  int currentPage = 0;

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
    _searchController.addListener(_updateSearch);
  }

  void _setDefaultDates() {
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, now.day);
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
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
        _toDate = picked.end.add(Duration(days: 1));
      } else {
        return;
      }
    }

    final fromDateStr = _formatDateForApi(_fromDate);
    final toDateStr = _formatDateForApi(_toDate);
    final fromTimeStr = "00:00:00";
    final toTimeStr = "23:59:59";

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

  String _formatTimeForApi(TimeOfDay time) {
    String hour = time.hour < 10 ? "0${time.hour}" : time.hour.toString();
    String minute =
    time.minute < 10 ? "0${time.minute}" : time.minute.toString();
    return "$hour:$minute:00";
  }

  void _refreshData({
    required String fromDate,
    required String toDate,
    required String fromTime,
    required String toTime,
  }) {
    setState(() {
      isLoading = true;
      extractedText = "Loading PDF content...";
    });

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
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Extract text from PDF using syncfusion_flutter_pdf
  Future<String> extractTextFromPdf(File file) async {
    try {
      // Read the PDF file bytes
      final List<int> bytes = await file.readAsBytes();

      // Load the PDF document
      final PdfDocument document = PdfDocument(inputBytes: bytes);

      // Create text extractor
      final PdfTextExtractor extractor = PdfTextExtractor(document);

      // Extract text from all pages and store paginated text
      pdfPages = [];
      String fullText = '';

      for (int i = 0; i < document.pages.count; i++) {
        String pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
        pdfPages.add(pageText);
        fullText += pageText + '\n';
      }

      // Dispose the document to free memory
      document.dispose();

      return fullText;
    } catch (e) {
      return "${'failedToExtract'.tr}: ${e.toString()}";
    }
  }

  void _updateSearch() {
    setState(() {
      _searchQuery = _searchController.text;
      _highlightText();
    });
  }

  void _highlightText() {
    if (_searchQuery.isEmpty) {
      _highlightedSpans = [TextSpan(text: extractedText)];
      return;
    }

    final matches = _searchQuery.allMatches(extractedText.toLowerCase());
    final spans = <TextSpan>[];
    int currentPos = 0;

    for (final match in matches) {
      if (match.start > currentPos) {
        spans.add(TextSpan(
          text: extractedText.substring(currentPos, match.start),
          style: TextStyle(color: Colors.black87),
        ));
      }
      spans.add(TextSpan(
        text: extractedText.substring(match.start, match.end),
        style: TextStyle(
          color: Colors.white,
          backgroundColor: Colors.orange.withOpacity(0.7),
        ),
      ));
      currentPos = match.end;
    }

    if (currentPos < extractedText.length) {
      spans.add(TextSpan(
        text: extractedText.substring(currentPos),
        style: TextStyle(color: Colors.black87),
      ));
    }

    _highlightedSpans = spans;
  }

  getReport() {
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
          _downloadFile(url!, "general");
        });
      }
    });
  }

  Future<void> _downloadFile(String url, String filename) async {
    try {
      setState(() => isExtracting = true);

      final httpClient = HttpClient();
      var request = await httpClient.getUrl(Uri.parse(url));
      var response = await request.close();
      var bytes = await consolidateHttpClientResponseBytes(response);

      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}/$filename-${DateTime.now().millisecondsSinceEpoch}.pdf';
      file = File(filePath);
      await file!.writeAsBytes(bytes);

      final text = await extractTextFromPdf(file!);
      setState(() {
        extractedText = text;
        isExtracting = false;
        _highlightText();
      });
    } catch (e) {
      setState(() {
        extractedText = "${'failedToProcess'.tr}: ${e.toString()}";
        isExtracting = false;
      });
    }
  }

  void _scrollToNextMatch() {
    if (_searchQuery.isEmpty) return;

    final matches = _searchQuery.allMatches(extractedText.toLowerCase());
    if (matches.isEmpty) return;

    final currentPos = _scrollController.offset;
    final textPainter = TextPainter(
      text: TextSpan(text: extractedText),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: MediaQuery.of(context).size.width - 32);

    for (final match in matches) {
      final offset = textPainter.getOffsetForCaret(
        TextPosition(offset: match.start),
        Rect.zero,
      );
      if (offset.dy > currentPos) {
        _scrollController.animateTo(
          offset.dy - 50,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
        return;
      }
    }

    final firstOffset = textPainter.getOffsetForCaret(
      TextPosition(offset: matches.first.start),
      Rect.zero,
    );
    _scrollController.animateTo(
      firstOffset.dy - 50,
      duration: Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("searchInDocument".tr),
        content: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: "enterSearchTerm".tr,
            suffixIcon: IconButton(
              icon: Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text("close".tr.toUpperCase()),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _changePage(int newPage) {
    if (newPage >= 0 && newPage < pdfPages.length) {
      setState(() {
        currentPage = newPage;
        extractedText = pdfPages[currentPage];
        _highlightText();
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
            icon: Icon(Icons.search),
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: Icon(Icons.download),
            onPressed: () => _downloadFile(url!, "general"),
          ),
        ],
        centerTitle: false,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
      bottomNavigationBar: pdfPages.isNotEmpty ? _buildPageNavigator() : null,
      floatingActionButton: _searchQuery.isNotEmpty
          ? FloatingActionButton(
        child: Icon(Icons.keyboard_arrow_down),
        onPressed: _scrollToNextMatch,
        mini: true,
      )
          : null,
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

  Widget _buildPageNavigator() {
    return BottomAppBar(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(Icons.chevron_left),
              onPressed: () => _changePage(currentPage - 1),
            ),
            Text(
                '${'page'.tr} ${currentPage + 1} ${'of'.tr} ${pdfPages.length}'),
            IconButton(
              icon: Icon(Icons.chevron_right),
              onPressed: () => _changePage(currentPage + 1),
            ),
          ],
        ),
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

    final metrics = _parseMetrics(extractedText);

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMetricCard(
            icon: Icons.calendar_today,
            title: "dateRange".tr,
            value: metrics['dateRange'] ?? 'N/A',
          ),
          _buildMetricCard(
            icon: Icons.device_hub,
            title: "device".tr,
            value: metrics['device'] ?? 'N/A',
          ),
          Card(
            margin: EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "routeInformation".tr,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  Divider(),
                  SizedBox(height: 8),
                  _buildMetricRow(
                    icon: Icons.flag,
                    title: "routeStart".tr,
                    value: metrics['routeStart'] ?? 'N/A',
                  ),
                  _buildMetricRow(
                    icon: Icons.flag_outlined,
                    title: "routeEnd".tr,
                    value: metrics['routeEnd'] ?? 'N/A',
                  ),
                  _buildMetricRow(
                    icon: Icons.alt_route,
                    title: "routeLength".tr,
                    value: metrics['routeLength'] ?? 'N/A',
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "durationInformation".tr,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  Divider(),
                  SizedBox(height: 8),
                  _buildMetricRow(
                    icon: Icons.directions_car,
                    title: "moveDuration".tr,
                    value: metrics['moveDuration'] ?? 'N/A',
                  ),
                  _buildMetricRow(
                    icon: Icons.pause_circle_outline,
                    title: "stopDuration".tr,
                    value: metrics['stopDuration'] ?? 'N/A',
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "speedInformation".tr,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  Divider(),
                  SizedBox(height: 8),
                  _buildMetricRow(
                    icon: Icons.speed,
                    title: "topSpeed".tr,
                    value: metrics['topSpeed'] ?? 'N/A',
                  ),
                  _buildMetricRow(
                    icon: Icons.timer,
                    title: "averageSpeed".tr,
                    value: metrics['averageSpeed'] ?? 'N/A',
                  ),
                  _buildMetricRow(
                    icon: Icons.warning_amber_rounded,
                    title: "overspeedCount".tr,
                    value: metrics['overspeedCount'] ?? 'N/A',
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "engineInformation".tr,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  Divider(),
                  SizedBox(height: 8),
                  _buildMetricRow(
                    icon: Icons.schedule,
                    title: "engineHours".tr,
                    value: metrics['engineHours'] ?? 'N/A',
                  ),
                  _buildMetricRow(
                    icon: Icons.engineering,
                    title: "engineWork".tr,
                    value: metrics['engineWork'] ?? 'N/A',
                  ),
                  _buildMetricRow(
                    icon: Icons.power_settings_new,
                    title: "engineIdle".tr,
                    value: metrics['engineIdle'] ?? 'N/A',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
      {required IconData icon, required String title, required String value}) {
    return Card(
      margin: EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blue),
                SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(
      {required IconData icon, required String title, required String value}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, String> _parseMetrics(String text) {
    final lines = text.split('\n');
    final metrics = <String, String>{};

    for (var line in lines) {
      if (line.contains('Device:')) {
        metrics['device'] = line.split('Device:')[1].trim();
      } else if (line.contains('Route start:')) {
        metrics['routeStart'] = line.split('Route start:')[1].trim();
      } else if (line.contains('Route end:')) {
        metrics['routeEnd'] = line.split('Route end:')[1].trim();
      } else if (line.contains('Route length:')) {
        metrics['routeLength'] = line.split('Route length:')[1].trim();
      } else if (line.contains('Move duration:')) {
        metrics['moveDuration'] = line.split('Move duration:')[1].trim();
      } else if (line.contains('Stop duration:')) {
        metrics['stopDuration'] = line.split('Stop duration:')[1].trim();
      } else if (line.contains('Top speed:')) {
        metrics['topSpeed'] = line.split('Top speed:')[1].trim();
      } else if (line.contains('Average speed:')) {
        metrics['averageSpeed'] = line.split('Average speed:')[1].trim();
      } else if (line.contains('Overspeed count:')) {
        metrics['overspeedCount'] = line.split('Overspeed count:')[1].trim();
      } else if (line.contains('Engine hours:')) {
        metrics['engineHours'] = line.split('Engine hours:')[1].trim();
      } else if (line.contains('Engine work:')) {
        metrics['engineWork'] = line.split('Engine work:')[1].trim();
      } else if (line.contains('Engine idle:')) {
        metrics['engineIdle'] = line.split('Engine idle:')[1].trim();
      } else if (line.contains('AM - ')) {
        metrics['dateRange'] = line.split('Report type:')[0].trim();
      }
    }

    return metrics;
  }
}