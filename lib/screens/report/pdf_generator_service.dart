// import 'dart:typed_data';
// import 'dart:ui';
// import 'package:smart_lock/screens/report/get_today_report.dart';
// import 'package:syncfusion_flutter_pdf/pdf.dart';
//
// class PDFGeneratorService {
//   static Future<Uint8List> generateReportPDF({
//     required TodayReportData data,
//     required String deviceName,
//     required String periodName,
//   }) async {
//     // Create a new PDF document
//     final PdfDocument document = PdfDocument();
//     PdfPage page = document.pages.add();
//
//     // Get page dimensions
//     final Size pageSize = page.getClientSize();
//
//     // Define colors
//     final PdfColor primaryColor = PdfColor(37, 99, 235);
//     final PdfColor secondaryColor = PdfColor(107, 114, 128);
//     final PdfColor lightGray = PdfColor(243, 244, 246);
//
//     // Define fonts
//     final PdfFont headerFont = PdfStandardFont(PdfFontFamily.helvetica, 20, style: PdfFontStyle.bold);
//     final PdfFont titleFont = PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold);
//     final PdfFont labelFont = PdfStandardFont(PdfFontFamily.helvetica, 11);
//     final PdfFont valueFont = PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold);
//     final PdfFont smallFont = PdfStandardFont(PdfFontFamily.helvetica, 9);
//
//     double yPosition = 0;
//
//     // Draw header background
//     page.graphics.drawRectangle(
//       brush: PdfSolidBrush(primaryColor),
//       bounds: Rect.fromLTWH(0, 0, pageSize.width, 80),
//     );
//
//     // Draw logo/title
//     page.graphics.drawString(
//       'GPS TRACKER REPORT',
//       PdfStandardFont(PdfFontFamily.helvetica, 24, style: PdfFontStyle.bold),
//       bounds: Rect.fromLTWH(20, 20, pageSize.width - 40, 30),
//       brush: PdfBrushes.white,
//     );
//
//     // Draw device name and period
//     page.graphics.drawString(
//       '$deviceName - $periodName',
//       PdfStandardFont(PdfFontFamily.helvetica, 14),
//       bounds: Rect.fromLTWH(20, 50, pageSize.width - 40, 20),
//       brush: PdfBrushes.white,
//     );
//
//     yPosition = 100;
//
//     // Draw generated date
//     final now = DateTime.now();
//     final dateStr = '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
//     page.graphics.drawString(
//       'Generated: $dateStr',
//       smallFont,
//       bounds: Rect.fromLTWH(20, yPosition, pageSize.width - 40, 15),
//       brush: PdfBrushes.gray,
//     );
//
//     yPosition += 30;
//
//     // Helper function to draw a section
//     void drawSection(String title, List<MapEntry<String, String>> items) {
//       // Section title
//       page.graphics.drawRectangle(
//         brush: PdfSolidBrush(lightGray),
//         bounds: Rect.fromLTWH(20, yPosition, pageSize.width - 40, 30),
//       );
//
//       page.graphics.drawString(
//         title,
//         titleFont,
//         bounds: Rect.fromLTWH(30, yPosition + 8, pageSize.width - 60, 20),
//         brush: PdfSolidBrush(primaryColor),
//       );
//
//       yPosition += 40;
//
//       // Section items
//       for (var item in items) {
//         if (yPosition > pageSize.height - 100) {
//           // Add new page if needed
//           final newPage = document.pages.add();
//           yPosition = 20;
//           page = newPage;
//         }
//
//         // Draw label
//         page.graphics.drawString(
//           item.key,
//           labelFont,
//           bounds: Rect.fromLTWH(30, yPosition, pageSize.width * 0.5, 20),
//           brush: PdfSolidBrush(secondaryColor),
//         );
//
//         // Draw value
//         page.graphics.drawString(
//           item.value,
//           valueFont,
//           bounds: Rect.fromLTWH(pageSize.width * 0.5, yPosition, pageSize.width * 0.4, 20),
//           brush: PdfBrushes.black,
//           format: PdfStringFormat(alignment: PdfTextAlignment.right),
//         );
//
//         // Draw separator line
//         page.graphics.drawLine(
//           PdfPen(PdfColor(229, 231, 235), width: 0.5),
//           Offset(30, yPosition + 22),
//           Offset(pageSize.width - 30, yPosition + 22),
//         );
//
//         yPosition += 28;
//       }
//
//       yPosition += 15;
//     }
//
//     // Route Information
//     List<MapEntry<String, String>> routeItems = [];
//     if (data.routeStart != null) routeItems.add(MapEntry('Route Start', data.routeStart!));
//     if (data.routeEnd != null) routeItems.add(MapEntry('Route End', data.routeEnd!));
//     if (data.routeLength != null) routeItems.add(MapEntry('Route Length', data.routeLength!));
//
//     if (routeItems.isNotEmpty) {
//       drawSection('Route Information', routeItems);
//     }
//
//     // Duration
//     List<MapEntry<String, String>> durationItems = [];
//     if (data.moveDuration != null) durationItems.add(MapEntry('Move Duration', data.moveDuration!));
//     if (data.stopDuration != null) durationItems.add(MapEntry('Stop Duration', data.stopDuration!));
//
//     if (durationItems.isNotEmpty) {
//       drawSection('Duration', durationItems);
//     }
//
//     // Speed
//     List<MapEntry<String, String>> speedItems = [];
//     if (data.topSpeed != null) speedItems.add(MapEntry('Top Speed', data.topSpeed!));
//     if (data.averageSpeed != null) speedItems.add(MapEntry('Average Speed', data.averageSpeed!));
//     if (data.overspeedCount != null) speedItems.add(MapEntry('Overspeed Count', data.overspeedCount!));
//
//     if (speedItems.isNotEmpty) {
//       drawSection('Speed', speedItems);
//     }
//
//     // Engine
//     List<MapEntry<String, String>> engineItems = [];
//     if (data.engineHours != null) engineItems.add(MapEntry('Engine Hours', data.engineHours!));
//     if (data.engineWork != null) engineItems.add(MapEntry('Engine Work', data.engineWork!));
//     if (data.engineIdle != null) engineItems.add(MapEntry('Engine Idle', data.engineIdle!));
//
//     if (engineItems.isNotEmpty) {
//       drawSection('Engine', engineItems);
//     }
//
//     // Other
//     List<MapEntry<String, String>> otherItems = [];
//     if (data.odometer != null) otherItems.add(MapEntry('Odometer', data.odometer!));
//     if (data.fuelConsumption != null) otherItems.add(MapEntry('Fuel Consumption', data.fuelConsumption!));
//
//     if (otherItems.isNotEmpty) {
//       drawSection('Other Information', otherItems);
//     }
//
//     // Draw footer
//     final footerY = pageSize.height - 30;
//     page.graphics.drawLine(
//       PdfPen(PdfColor(229, 231, 235)),
//       Offset(20, footerY),
//       Offset(pageSize.width - 20, footerY),
//     );
//
//     page.graphics.drawString(
//       'GPS Tracker Report - Confidential',
//       smallFont,
//       bounds: Rect.fromLTWH(20, footerY + 10, pageSize.width - 40, 15),
//       brush: PdfBrushes.gray,
//       format: PdfStringFormat(alignment: PdfTextAlignment.center),
//     );
//
//     // Save and return
//     final List<int> bytes = await document.save();
//     document.dispose();
//
//     return Uint8List.fromList(bytes);
//   }
// }