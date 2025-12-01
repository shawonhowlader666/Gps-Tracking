import 'dart:developer';
import 'dart:io';
import 'package:gpspro/services/api_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class TodayReportData {
  String? device;
  String? routeStart;
  String? routeEnd;
  String? routeLength;
  String? moveDuration;
  String? stopDuration;
  String? topSpeed;
  String? averageSpeed;
  String? overspeedCount;
  String? engineHours;
  String? engineWork;
  String? engineIdle;

  TodayReportData({
    this.device,
    this.routeStart,
    this.routeEnd,
    this.routeLength,
    this.moveDuration,
    this.stopDuration,
    this.topSpeed,
    this.averageSpeed,
    this.overspeedCount,
    this.engineHours,
    this.engineWork,
    this.engineIdle,
  });

  Map<String, dynamic> toJson() {
    return {
      'device': device,
      'routeStart': routeStart,
      'routeEnd': routeEnd,
      'routeLength': routeLength,
      'moveDuration': moveDuration,
      'stopDuration': stopDuration,
      'topSpeed': topSpeed,
      'averageSpeed': averageSpeed,
      'overspeedCount': overspeedCount,
      'engineHours': engineHours,
      'engineWork': engineWork,
      'engineIdle': engineIdle,
    };
  }
}

class ReportService {
  static Future<TodayReportData> getTodayReportData({
    required int deviceId,
  }) async {
    try {
      // 1. Set today's date range
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final fromDate = _formatDateForApi(today);
      final toDate = _formatDateForApi(today.add(Duration(days: 1)));

      // 2. Call API to get the report URL
      final reportResponse = await APIService.getReport(
        deviceId.toString(),
        fromDate,
        toDate,
        1,
      );

      if (reportResponse == null || reportResponse.url == null) {
        throw Exception('Failed to get report URL');
      }

      // 3. Download the PDF file
      final pdfFile = await _downloadPdfFile(reportResponse.url!);

      // 4. Extract text from PDF using Syncfusion
      final text = await _extractPdfText(pdfFile.path);

      // 5. Parse the metrics from the text
      return _parseMetrics(text);
    } catch (e) {
      throw Exception('Failed to get today\'s report data: $e');
    }
  }

  /// Extract text from PDF using syncfusion_flutter_pdf
  static Future<String> _extractPdfText(String filePath) async {
    try {
      // Read the PDF file
      final File file = File(filePath);
      final List<int> bytes = await file.readAsBytes();

      // Load the PDF document
      final PdfDocument document = PdfDocument(inputBytes: bytes);

      // Extract text from all pages
      String extractedText = '';

      // Create text extractor
      PdfTextExtractor extractor = PdfTextExtractor(document);

      // Extract text from each page
      for (int i = 0; i < document.pages.count; i++) {
        extractedText += extractor.extractText(startPageIndex: i, endPageIndex: i);
        extractedText += '\n';
      }

      // Dispose the document
      document.dispose();

      // Delete temporary file
      try {
        await file.delete();
      } catch (e) {
        log('Failed to delete temp file: $e');
      }

      return extractedText;
    } catch (e) {
      throw Exception('Failed to extract PDF text: $e');
    }
  }

  static String _formatDateForApi(DateTime date) {
    String month = date.month < 10 ? "0${date.month}" : date.month.toString();
    String day = date.day < 10 ? "0${date.day}" : date.day.toString();
    return "${date.year}-$month-$day";
  }

  static Future<File> _downloadPdfFile(String url) async {
    try {
      // Fix URL encoding issues
      String decodedUrl = Uri.decodeFull(url);
      String correctedUrl = decodedUrl.replaceAll('%5B0%5D', '[]');
      String correctedUrl2 = correctedUrl.replaceAll('[0]', '[]');
      String correctedUrl3 =
      correctedUrl2.replaceAll('send_to_email[]=', 'send_to_email=');

      final httpClient = HttpClient();
      var request = await httpClient.getUrl(Uri.parse(correctedUrl3));
      var response = await request.close();
      var bytes = await response.fold<List<int>>(
        <int>[],
            (previous, element) => previous..addAll(element),
      );

      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}/today_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      return file;
    } catch (e) {
      throw Exception('Failed to download PDF: $e');
    }
  }

  static TodayReportData _parseMetrics(String text) {
    final lines = text.split('\n');
    final metrics = TodayReportData();

    for (var line in lines) {
      if (line.contains('Device:')) {
        metrics.device = line.split('Device:')[1].trim();
      } else if (line.contains('Route start:')) {
        metrics.routeStart = line.split('Route start:')[1].trim();
      } else if (line.contains('Route end:')) {
        metrics.routeEnd = line.split('Route end:')[1].trim();
      } else if (line.contains('Route length:')) {
        metrics.routeLength = line.split('Route length:')[1].trim();
      } else if (line.contains('Move duration:')) {
        metrics.moveDuration = line.split('Move duration:')[1].trim();
      } else if (line.contains('Stop duration:')) {
        metrics.stopDuration = line.split('Stop duration:')[1].trim();
      } else if (line.contains('Top speed:')) {
        metrics.topSpeed = line.split('Top speed:')[1].trim();
      } else if (line.contains('Average speed:')) {
        metrics.averageSpeed = line.split('Average speed:')[1].trim();
      } else if (line.contains('Overspeed count:')) {
        metrics.overspeedCount = line.split('Overspeed count:')[1].trim();
      } else if (line.contains('Engine hours:')) {
        metrics.engineHours = line.split('Engine hours:')[1].trim();
      } else if (line.contains('Engine work:')) {
        metrics.engineWork = line.split('Engine work:')[1].trim();
      } else if (line.contains('Engine idle:')) {
        metrics.engineIdle = line.split('Engine idle:')[1].trim();
      }
    }
    return metrics;
  }
}