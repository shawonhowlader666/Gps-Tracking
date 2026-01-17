import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:gpspro/services/model/bill.dart';

class PDFGenerator {
  // Material-like colors
  static const PdfColor primaryColor = PdfColor.fromInt(0xFF2196F3); // Blue
  static const PdfColor primaryDark = PdfColor.fromInt(0xFF1976D2); // Dark Blue
  static const PdfColor accentColor = PdfColor.fromInt(0xFF4CAF50); // Green
  static const PdfColor errorColor = PdfColor.fromInt(0xFFF44336); // Red
  static const PdfColor textPrimary = PdfColor.fromInt(0xFF212121); // Dark Grey
  static const PdfColor textSecondary = PdfColor.fromInt(0xFF757575); // Grey
  static const PdfColor dividerColor = PdfColor.fromInt(0xFFBDBDBD); // Light Grey
  static const PdfColor backgroundColor = PdfColor.fromInt(0xFFFAFAFA); // Very Light Grey

  static Future<File> generateBillPDF(Bill bill) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(20),
                color: primaryColor,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'INVOICE',
                      style: pw.TextStyle(
                        fontSize: 32,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      bill.billingMonth,
                      style: const pw.TextStyle(
                        fontSize: 18,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),

              // Bill Details
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: dividerColor, width: 1),
                  color: backgroundColor,
                ),
                child: pw.Column(
                  children: [
                    _buildDetailRow('Bill Amount:', 'BDT ${bill.amount.toStringAsFixed(2)}'),
                    pw.SizedBox(height: 12),
                    _buildDetailRow('Vehicle Count:', '${bill.vehicleCount}'),
                    pw.SizedBox(height: 12),
                    _buildDetailRow('Status:', bill.status.toUpperCase()),
                    pw.SizedBox(height: 12),
                    // _buildDetailRow('Created At:', bill.createdAt),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),

              // Payment History
              if (bill.payments.isNotEmpty) ...[
                pw.Text(
                  'Payment History',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                pw.SizedBox(height: 15),
                pw.Table(
                  border: pw.TableBorder.all(color: dividerColor),
                  children: [
                    // Header
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: primaryColor,
                      ),
                      children: [
                        _buildTableCell('Payment Method', isHeader: true, isWhiteText: true),
                        _buildTableCell('Date', isHeader: true, isWhiteText: true),
                        _buildTableCell('Amount', isHeader: true, isWhiteText: true),
                      ],
                    ),
                    // Data rows
                    ...bill.payments.asMap().entries.map(
                          (entry) => pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: entry.key % 2 == 0 ? PdfColors.white : backgroundColor,
                        ),
                        children: [
                          _buildTableCell(entry.value.method ?? 'N/A'),
                          _buildTableCell(entry.value.paidAt),
                          _buildTableCell('BDT ${entry.value.amount.toStringAsFixed(2)}'),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                // Total Paid
                pw.Container(
                  alignment: pw.Alignment.centerRight,
                  padding: const pw.EdgeInsets.all(15),
                  color: accentColor,
                  child: pw.Text(
                    'Total Paid: BDT ${bill.payments.fold<double>(0.0, (sum, p) => sum + p.amount).toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
              ] else ...[
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(20),
                  color: backgroundColor,
                  child: pw.Center(
                    child: pw.Text(
                      'No payments made for this bill',
                      style: pw.TextStyle(
                        fontSize: 14,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ),
              ],

              pw.Spacer(),

              // Footer
              pw.Divider(color: dividerColor),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  'Generated on ${DateTime.now().toString().substring(0, 19)}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: textSecondary,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return _savePDF(pdf, 'invoice_${bill.billingMonth.replaceAll(' ', '_')}.pdf');
  }

  static Future<File> generateAllTransactionsPDF(List<Bill> bills) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            // Header
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(20),
              color: primaryColor,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'TRANSACTION HISTORY',
                    style: pw.TextStyle(
                      fontSize: 32,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'All Transactions',
                    style: const pw.TextStyle(
                      fontSize: 18,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 30),

            // Bills Table
            pw.Table(
              border: pw.TableBorder.all(color: dividerColor),
              children: [
                // Header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: primaryColor,
                  ),
                  children: [
                    _buildTableCell('Billing Month', isHeader: true, isWhiteText: true),
                    _buildTableCell('Amount', isHeader: true, isWhiteText: true),
                    _buildTableCell('Status', isHeader: true, isWhiteText: true),
                    _buildTableCell('Vehicles', isHeader: true, isWhiteText: true),
                  ],
                ),
                // Data rows
                ...bills.asMap().entries.map(
                      (entry) => pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: entry.key % 2 == 0 ? PdfColors.white : backgroundColor,
                    ),
                    children: [
                      _buildTableCell(entry.value.billingMonth),
                      _buildTableCell('BDT ${entry.value.amount.toStringAsFixed(2)}'),
                      _buildTableCell(entry.value.status.toUpperCase()),
                      _buildTableCell('${entry.value.vehicleCount}'),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 30),

            // Summary
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: primaryColor, width: 2),
                color: backgroundColor,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Summary',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  pw.SizedBox(height: 15),
                  _buildDetailRow(
                    'Total Bills:',
                    '${bills.length}',
                  ),
                  pw.SizedBox(height: 8),
                  _buildDetailRow(
                    'Paid Bills:',
                    '${bills.where((b) => b.status.toLowerCase() == 'paid').length}',
                  ),
                  pw.SizedBox(height: 8),
                  _buildDetailRow(
                    'Unpaid Bills:',
                    '${bills.where((b) => b.status.toLowerCase() == 'unpaid').length}',
                  ),
                  pw.SizedBox(height: 8),
                  _buildDetailRow(
                    'Total Amount:',
                    'BDT ${bills.fold<double>(0.0, (sum, b) => sum + b.amount).toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),
            pw.Divider(color: dividerColor),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'Generated on ${DateTime.now().toString().substring(0, 19)}',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: textSecondary,
                ),
              ),
            ),
          ];
        },
      ),
    );

    return _savePDF(pdf, 'all_transactions_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  static pw.Widget _buildDetailRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: textPrimary,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 14,
            color: textPrimary,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTableCell(String text, {bool isHeader = false, bool isWhiteText = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(10),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 13 : 12,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isWhiteText ? PdfColors.white : textPrimary,
        ),
      ),
    );
  }

  static Future<File> _savePDF(pw.Document pdf, String fileName) async {
    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }
}