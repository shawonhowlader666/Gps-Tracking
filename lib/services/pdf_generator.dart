import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:gpspro/services/model/bill.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart' show rootBundle;

class PDFGenerator {
  static const PdfColor primaryColor = PdfColor.fromInt(0xFF1D4888);
  static const PdfColor lightAccent = PdfColor.fromInt(0xFFE4B34E);
  static const PdfColor accentColor = PdfColor.fromInt(0xFF4CAF50);
  static const PdfColor errorColor = PdfColor.fromInt(0xFFF44336);
  static const PdfColor textPrimary = PdfColor.fromInt(0xFF212121);
  static const PdfColor textSecondary = PdfColor.fromInt(0xFF757575);
  static const PdfColor dividerColor = PdfColor.fromInt(0xFFBDBDBD);
  static const PdfColor backgroundColor = PdfColor.fromInt(0xFFFAFAFA);

  // Company Details
  static const String companyName = 'Trust Me';
  static const String companyTagline = 'Advanced Tracking Solution';
  static const String logoPath = 'images/trust_logo.png';

  // Load logo image
  static Future<Uint8List?> _loadLogo() async {
    try {
      final ByteData data = await rootBundle.load(logoPath);
      return data.buffer.asUint8List();
    } catch (e) {
      print('Error loading logo: $e');
      return null;
    }
  }

  // Get User Details from Repository
  static Map<String, String?> _getUserDetails() {
    return {
      'email': UserRepository.getEmail(),
      'name': UserRepository.getName(),
      'phone': UserRepository.getPhone(),
      'company': UserRepository.getCompanyName(),
    };
  }

  static Future<File> generateBillPDF(Bill bill) async {
    final pdf = pw.Document();
    final logoBytes = await _loadLogo();
    final userDetails = _getUserDetails();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Company Header with Logo
              _buildCompanyHeader(logoBytes),
              pw.SizedBox(height: 20),

              // Invoice Header
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  gradient: const pw.LinearGradient(
                    colors: [primaryColor, PdfColor.fromInt(0xFF2557A7)],
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
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
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: pw.BoxDecoration(
                        color: bill.status.toLowerCase() == 'paid'
                            ? accentColor
                            : errorColor,
                        borderRadius: pw.BorderRadius.circular(20),
                      ),
                      child: pw.Text(
                        bill.status.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Customer Details & Bill Details Row
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Customer Details (Left)
                  pw.Expanded(
                    child: _buildCustomerDetails(userDetails),
                  ),
                  pw.SizedBox(width: 20),
                  // Bill Details (Right)
                  pw.Expanded(
                    child: _buildBillDetails(bill),
                  ),
                ],
              ),
              pw.SizedBox(height: 30),

              // Payment History
              if (bill.payments.isNotEmpty) ...[
                pw.Text(
                  'Payment History',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
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
                        _buildTableCell('Payment Month',
                            isHeader: true, isWhiteText: true),
                        _buildTableCell('Payment Method',
                            isHeader: true, isWhiteText: true),
                        _buildTableCell('Date',
                            isHeader: true, isWhiteText: true),
                        _buildTableCell('Amount',
                            isHeader: true, isWhiteText: true),
                      ],
                    ),
                    // Data rows
                    ...bill.payments.asMap().entries.map(
                          (entry) {
                        final payment = entry.value;
                        final paymentMonth =
                        _extractMonthFromDate(payment.paidAt);

                        return pw.TableRow(
                          decoration: pw.BoxDecoration(
                            color: entry.key % 2 == 0
                                ? PdfColors.white
                                : backgroundColor,
                          ),
                          children: [
                            _buildTableCell(paymentMonth),
                            _buildTableCell(payment.method ?? 'N/A'),
                            _buildTableCell(payment.paidAt),
                            _buildTableCell(
                                'BDT ${payment.amount.toStringAsFixed(2)}'),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                // Total Paid
                pw.Container(
                  alignment: pw.Alignment.centerRight,
                  padding: const pw.EdgeInsets.all(15),
                  decoration: const pw.BoxDecoration(
                    gradient: pw.LinearGradient(
                      colors: [accentColor, PdfColor.fromInt(0xFF66BB6A)],
                    ),
                  ),
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
                  decoration: pw.BoxDecoration(
                    color: backgroundColor,
                    border: pw.Border.all(color: dividerColor),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      'No payments made for this bill',
                      style: pw.TextStyle(
                        fontSize: 14,
                        color: textSecondary,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              ],

              pw.Spacer(),

              // Footer
              _buildFooter(),
            ],
          );
        },
      ),
    );

    return _savePDF(
        pdf, 'invoice_${bill.billingMonth.replaceAll(' ', '_')}.pdf');
  }

  static Future<File> generateAllTransactionsPDF(List<Bill> bills) async {
    final pdf = pw.Document();
    final logoBytes = await _loadLogo();
    final userDetails = _getUserDetails();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            // Company Header with Logo
            _buildCompanyHeader(logoBytes),
            pw.SizedBox(height: 20),

            // Report Header
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                gradient: const pw.LinearGradient(
                  colors: [primaryColor, PdfColor.fromInt(0xFF2557A7)],
                ),
              ),
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
                    'All Transactions Report',
                    style: const pw.TextStyle(
                      fontSize: 18,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Generated on ${_formatDateTime(DateTime.now())}',
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Customer Details Section
            _buildCustomerDetailsFullWidth(userDetails),
            pw.SizedBox(height: 20),

            // Bills Table
            pw.Table(
              border: pw.TableBorder.all(color: dividerColor),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(1.5),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1),
              },
              children: [
                // Header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: primaryColor,
                  ),
                  children: [
                    _buildTableCell('Billing Month',
                        isHeader: true, isWhiteText: true),
                    _buildTableCell('Amount',
                        isHeader: true, isWhiteText: true),
                    _buildTableCell('Status',
                        isHeader: true, isWhiteText: true),
                    _buildTableCell('Vehicles',
                        isHeader: true, isWhiteText: true),
                  ],
                ),
                // Data rows
                ...bills.asMap().entries.map(
                      (entry) => pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: entry.key % 2 == 0
                          ? PdfColors.white
                          : backgroundColor,
                    ),
                    children: [
                      _buildTableCell(entry.value.billingMonth),
                      _buildTableCell(
                          'BDT ${entry.value.amount.toStringAsFixed(2)}'),
                      _buildStatusCell(entry.value.status),
                      _buildTableCell('${entry.value.vehicleCount}'),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 30),

            // Summary Box
            _buildSummaryBox(bills),

            pw.SizedBox(height: 20),

            // Footer
            _buildFooter(),
          ];
        },
      ),
    );

    return _savePDF(
        pdf, 'all_transactions_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  // Company Header with Logo
  static pw.Widget _buildCompanyHeader(Uint8List? logoBytes) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: lightAccent, width: 3),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              // Logo
              if (logoBytes != null)
                pw.Container(
                  width: 60,
                  height: 60,
                  child: pw.Image(
                    pw.MemoryImage(logoBytes),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              pw.SizedBox(width: 16),
              // Company Name
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName,
                    style: pw.TextStyle(
                      fontSize: 28,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    companyTagline,
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: textSecondary,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Document ID/Date
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Document #${DateTime.now().millisecondsSinceEpoch}',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: textSecondary,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                DateFormat('dd/MM/yyyy').format(DateTime.now()),
                style: pw.TextStyle(
                  fontSize: 10,
                  color: textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Customer Details Box (for side-by-side layout in invoice)
  static pw.Widget _buildCustomerDetails(Map<String, String?> userDetails) {
    final hasAnyDetails = userDetails.values.any((v) => v != null && v.isNotEmpty);

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: lightAccent, width: 2),
        color: backgroundColor,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 4,
                height: 18,
                color: lightAccent,
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                'Bill To',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          pw.Divider(color: dividerColor, height: 16),
          if (hasAnyDetails) ...[
            if (_isNotEmpty(userDetails['name']))
              _buildCustomerInfoRow('Name', userDetails['name']!),
            if (_isNotEmpty(userDetails['email']))
              _buildCustomerInfoRow('Email', userDetails['email']!),
            if (_isNotEmpty(userDetails['phone']))
              _buildCustomerInfoRow('Phone', userDetails['phone']!),
            if (_isNotEmpty(userDetails['company']))
              _buildCustomerInfoRow('Company', userDetails['company']!),
          ] else
            pw.Text(
              'Customer details not available',
              style: pw.TextStyle(
                fontSize: 11,
                color: textSecondary,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  // Customer Details Full Width (for transaction history)
  static pw.Widget _buildCustomerDetailsFullWidth(Map<String, String?> userDetails) {
    final hasAnyDetails = userDetails.values.any((v) => v != null && v.isNotEmpty);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: lightAccent, width: 2),
        color: backgroundColor,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 4,
                height: 20,
                color: lightAccent,
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                'Customer Information',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          pw.Divider(color: dividerColor, height: 20),
          if (hasAnyDetails)
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (_isNotEmpty(userDetails['name']))
                        _buildCustomerInfoRowHorizontal('Name:', userDetails['name']!),
                      pw.SizedBox(height: 6),
                      if (_isNotEmpty(userDetails['email']))
                        _buildCustomerInfoRowHorizontal('Email:', userDetails['email']!),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (_isNotEmpty(userDetails['phone']))
                        _buildCustomerInfoRowHorizontal('Phone:', userDetails['phone']!),
                      pw.SizedBox(height: 6),
                      if (_isNotEmpty(userDetails['company']))
                        _buildCustomerInfoRowHorizontal('Company:', userDetails['company']!),
                    ],
                  ),
                ),
              ],
            )
          else
            pw.Center(
              child: pw.Text(
                'Customer details not available',
                style: pw.TextStyle(
                  fontSize: 12,
                  color: textSecondary,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Bill Details Box
  static pw.Widget _buildBillDetails(Bill bill) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: dividerColor, width: 1),
        color: backgroundColor,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 4,
                height: 18,
                color: primaryColor,
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                'Bill Details',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          pw.Divider(color: dividerColor, height: 16),
          _buildBillInfoRow('Billing Month', bill.billingMonth),
          pw.SizedBox(height: 8),
          _buildBillInfoRow('Bill Amount', 'BDT ${bill.amount.toStringAsFixed(2)}'),
          pw.SizedBox(height: 8),
          _buildBillInfoRow('Vehicle Count', '${bill.vehicleCount}'),
          pw.SizedBox(height: 8),
          _buildStatusInfoRow('Status', bill.status),
        ],
      ),
    );
  }

  // Summary Box
  static pw.Widget _buildSummaryBox(List<Bill> bills) {
    final totalBills = bills.length;
    final paidBills = bills.where((b) => b.status.toLowerCase() == 'paid').length;
    final unpaidBills = bills.where((b) => b.status.toLowerCase() != 'paid').length;
    final totalAmount = bills.fold<double>(0.0, (sum, b) => sum + b.amount);
    final totalPaid = bills
        .where((b) => b.status.toLowerCase() == 'paid')
        .fold<double>(0.0, (sum, b) => sum + b.amount);
    final totalDue = bills
        .where((b) => b.status.toLowerCase() != 'paid')
        .fold<double>(0.0, (sum, b) => sum + b.amount);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: primaryColor, width: 2),
        color: backgroundColor,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 4,
                height: 24,
                color: lightAccent,
              ),
              pw.SizedBox(width: 10),
              pw.Text(
                'Summary',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          pw.Divider(color: dividerColor, height: 20),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildSummaryRow('Total Bills:', '$totalBills'),
                    pw.SizedBox(height: 6),
                    _buildSummaryRow('Paid Bills:', '$paidBills', valueColor: accentColor),
                    pw.SizedBox(height: 6),
                    _buildSummaryRow('Unpaid Bills:', '$unpaidBills', valueColor: errorColor),
                  ],
                ),
              ),
              pw.Container(
                width: 1,
                height: 60,
                color: dividerColor,
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildSummaryRow('Total Amount:', 'BDT ${totalAmount.toStringAsFixed(2)}'),
                    pw.SizedBox(height: 6),
                    _buildSummaryRow('Total Paid:', 'BDT ${totalPaid.toStringAsFixed(2)}', valueColor: accentColor),
                    pw.SizedBox(height: 6),
                    _buildSummaryRow('Total Due:', 'BDT ${totalDue.toStringAsFixed(2)}', valueColor: errorColor),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Helper Methods
  static bool _isNotEmpty(String? value) {
    return value != null && value.isNotEmpty && value != 'null';
  }

  static pw.Widget _buildCustomerInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9,
              color: textSecondary,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCustomerInfoRowHorizontal(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 60,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 11,
              color: textSecondary,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildBillInfoRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 11,
            color: textSecondary,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: textPrimary,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildStatusInfoRow(String label, String status) {
    final isPaid = status.toLowerCase() == 'paid';
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 11,
            color: textSecondary,
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: pw.BoxDecoration(
            color: isPaid ? accentColor : errorColor,
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Text(
            status.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildStatusCell(String status) {
    final isPaid = status.toLowerCase() == 'paid';
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Center(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: pw.BoxDecoration(
            color: isPaid ? accentColor : errorColor,
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Text(
            status.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ),
      ),
    );
  }

  static pw.Widget _buildSummaryRow(String label, String value, {PdfColor? valueColor}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 12,
            color: textSecondary,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: valueColor ?? textPrimary,
          ),
        ),
      ],
    );
  }

  // Footer
  static pw.Widget _buildFooter() {
    return pw.Column(
      children: [
        pw.Divider(color: dividerColor),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '© ${DateTime.now().year} $companyName. All rights reserved.',
              style: pw.TextStyle(
                fontSize: 10,
                color: textSecondary,
              ),
            ),
            pw.Text(
              'Generated on ${_formatDateTime(DateTime.now())}',
              style: pw.TextStyle(
                fontSize: 10,
                color: textSecondary,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Center(
          child: pw.Text(
            companyTagline,
            style: pw.TextStyle(
              fontSize: 9,
              color: textSecondary,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ),
      ],
    );
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

  static pw.Widget _buildTableCell(String text,
      {bool isHeader = false, bool isWhiteText = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(10),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 12 : 11,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isWhiteText ? PdfColors.white : textPrimary,
        ),
        textAlign: isHeader ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }

  static String _formatDateTime(DateTime dateTime) {
    try {
      return DateFormat('dd MMM yyyy, hh:mm a').format(dateTime);
    } catch (e) {
      return dateTime.toString().substring(0, 19);
    }
  }

  static String _extractMonthFromDate(String dateString) {
    try {
      DateTime date;

      if (dateString.contains('T')) {
        date = DateTime.parse(dateString);
      } else if (dateString.contains('-')) {
        date = DateFormat('yyyy-MM-dd').parse(dateString);
      } else {
        date = DateFormat('dd/MM/yyyy').parse(dateString);
      }

      return DateFormat('MMMM yyyy').format(date);
    } catch (e) {
      return dateString.split(' ').first;
    }
  }

  static Future<File> _savePDF(pw.Document pdf, String fileName) async {
    try {
      final bytes = await pdf.save();

      Directory? directory;

      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download/TrustMe_Invoices');

        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(bytes);

      print('PDF saved to: ${file.path}');
      return file;
    } catch (e) {
      print('Error saving PDF: $e');
      rethrow;
    }
  }
}