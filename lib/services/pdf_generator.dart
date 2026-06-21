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
  static const PdfColor dividerColor = PdfColor.fromInt(0xFFE0E0E0);
  static const PdfColor backgroundColor = PdfColor.fromInt(0xFFF5F5F5);
  static const PdfColor cardColor = PdfColor.fromInt(0xFFFFFFFF);

  // Company Details
  static const String companyName = 'ONFLEET GPS';
  static const String companyTagline = 'Advanced Tracking Solution';
  static const String logoPath = 'images/onfleet_logo.png';

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

  // Format date consistently - Full format
  static String _formatDate(String dateString) {
    try {
      DateTime date;

      if (dateString.contains('T')) {
        date = DateTime.parse(dateString);
      } else if (dateString.contains('-')) {
        date = DateTime.parse(dateString);
      } else if (dateString.contains('/')) {
        date = DateFormat('dd/MM/yyyy').parse(dateString);
      } else {
        return dateString;
      }

      return DateFormat('dd MMMM yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  // Format date - Short format for tables
  static String _formatDateShort(String dateString) {
    try {
      DateTime date;

      if (dateString.contains('T')) {
        date = DateTime.parse(dateString);
      } else if (dateString.contains('-')) {
        date = DateTime.parse(dateString);
      } else if (dateString.contains('/')) {
        date = DateFormat('dd/MM/yyyy').parse(dateString);
      } else {
        return dateString;
      }

      return DateFormat('dd MMM yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  static String _formatDateTime(DateTime dateTime) {
    try {
      return DateFormat('dd MMMM yyyy, hh:mm a').format(dateTime);
    } catch (e) {
      return dateTime.toString().substring(0, 19);
    }
  }

  // ==================== GENERATE BILL PDF ====================

  static Future<File> generateBillPDF(Bill bill, {Uint8List? signatureImage}) async {
    final pdf = pw.Document();
    final logoBytes = await _loadLogo();
    final userDetails = _getUserDetails();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Compact Company Header
              _buildCompactHeader(logoBytes),
              pw.SizedBox(height: 12),

              // Invoice Title Bar
              _buildInvoiceTitleBar(bill),
              pw.SizedBox(height: 12),

              // Customer Information Card (Full Width)
              _buildCustomerInfoCard(userDetails),
              pw.SizedBox(height: 12),

              // Bill Details Card
              _buildBillDetailsCard(bill),
              pw.SizedBox(height: 16),

              // Payment History
              if (bill.payments.isNotEmpty) ...[
                _buildSectionTitle('Payment History'),
                pw.SizedBox(height: 8),
                _buildPaymentTableWithSerial(bill),
                pw.SizedBox(height: 10),
                _buildTotalPaidBar(bill),
              ] else ...[
                _buildNoPaymentsBox(),
              ],

              pw.Spacer(),

              // Signature Section
              _buildSignatureSection(signatureImage),
              pw.SizedBox(height: 12),

              // Compact Footer
              _buildCompactFooter(),
            ],
          );
        },
      ),
    );

    return _savePDF(
        pdf, 'invoice_${bill.billingMonth.replaceAll(' ', '_')}.pdf');
  }

  // ==================== GENERATE ALL TRANSACTIONS PDF ====================

  static Future<File> generateAllTransactionsPDF(
      List<Bill> bills, {
        Uint8List? signatureImage,
      }) async {
    final pdf = pw.Document();
    final logoBytes = await _loadLogo();
    final userDetails = _getUserDetails();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) {
          return [
            // Compact Header
            _buildCompactHeader(logoBytes),
            pw.SizedBox(height: 12),

            // Report Title Bar
            _buildReportTitleBar(),
            pw.SizedBox(height: 12),

            // Customer Information Card (Full Width)
            _buildCustomerInfoCard(userDetails),
            pw.SizedBox(height: 14),

            // Section Title
            _buildSectionTitle('Transaction Details'),
            pw.SizedBox(height: 8),

            // Transaction Table with Serial
            _buildTransactionTableWithSerial(bills),
            pw.SizedBox(height: 14),

            // Compact Summary
            _buildCompactSummaryBox(bills),

            pw.Spacer(),

            // Signature Section
            _buildSignatureSection(signatureImage),
            pw.SizedBox(height: 12),

            // Compact Footer
            _buildCompactFooter(),
          ];
        },
      ),
    );

    return _savePDF(
        pdf, 'all_transactions_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  // ==================== HEADER COMPONENTS ====================

  // Compact Header
  static pw.Widget _buildCompactHeader(Uint8List? logoBytes) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: lightAccent, width: 2),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              if (logoBytes != null)
                pw.Container(
                  width: 40,
                  height: 40,
                  child: pw.Image(
                    pw.MemoryImage(logoBytes),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              pw.SizedBox(width: 8),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName,
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  pw.Text(
                    companyTagline,
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: textSecondary,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Doc #${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}',
                style: pw.TextStyle(fontSize: 7, color: textSecondary),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                _formatDate(DateTime.now().toIso8601String()),
                style: pw.TextStyle(fontSize: 7, color: textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Invoice Title Bar
  static pw.Widget _buildInvoiceTitleBar(Bill bill) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: const pw.BoxDecoration(
        color: primaryColor,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
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
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Billing Period: ${_formatDate(bill.billingMonth)}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
              ),
            ],
          ),
          _buildStatusBadge(bill.status, large: true),
        ],
      ),
    );
  }

  // Report Title Bar
  static pw.Widget _buildReportTitleBar() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: const pw.BoxDecoration(
        color: primaryColor,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'TRANSACTION HISTORY',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Report Generated: ${_formatDate(DateTime.now().toIso8601String())}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
          ),
        ],
      ),
    );
  }

  // ==================== CUSTOMER INFO CARD ====================

  static pw.Widget _buildCustomerInfoCard(Map<String, String?> userDetails) {
    final hasName = _isNotEmpty(userDetails['name']);
    final hasEmail = _isNotEmpty(userDetails['email']);
    final hasPhone = _isNotEmpty(userDetails['phone']);
    final hasCompany = _isNotEmpty(userDetails['company']);
    final hasAnyDetails = hasName || hasEmail || hasPhone || hasCompany;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: cardColor,
        border: pw.Border.all(color: lightAccent, width: 1.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header
          pw.Row(
            children: [
              pw.Container(width: 3, height: 12, color: lightAccent),
              pw.SizedBox(width: 6),
              pw.Text(
                'Customer Information',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          pw.Divider(color: dividerColor, height: 8, thickness: 0.5),

          if (hasAnyDetails)
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Left Column
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (hasName)
                        _buildInfoRow('Name', userDetails['name']!),
                      if (hasEmail)
                        _buildInfoRow('Email', userDetails['email']!),
                    ],
                  ),
                ),
                pw.SizedBox(width: 20),
                // Right Column
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (hasPhone)
                        _buildInfoRow('Phone', userDetails['phone']!),
                      if (hasCompany)
                        _buildInfoRow('Company', userDetails['company']!),
                    ],
                  ),
                ),
              ],
            )
          else
            pw.Center(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 8),
                child: pw.Text(
                  'Customer details not available',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: textSecondary,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== BILL DETAILS CARD ====================

  static pw.Widget _buildBillDetailsCard(Bill bill) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: backgroundColor,
        border: pw.Border.all(color: dividerColor, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header
          pw.Row(
            children: [
              pw.Container(width: 3, height: 12, color: primaryColor),
              pw.SizedBox(width: 6),
              pw.Text(
                'Bill Details',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          pw.Divider(color: dividerColor, height: 8, thickness: 0.5),

          // Bill Details in Row with Middle Divider
          pw.Row(
            children: [
              // Left Section
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildDetailItem('Billing Month', _formatDate(bill.billingMonth)),
                    pw.SizedBox(height: 4),
                    _buildDetailItem('Bill Amount', 'BDT ${bill.amount.toStringAsFixed(2)}'),
                  ],
                ),
              ),

              // Middle Divider Bar
              pw.Container(
                width: 1,
                height: 35,
                margin: const pw.EdgeInsets.symmetric(horizontal: 10),
                color: dividerColor,
              ),

              // Right Section
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildDetailItem('Vehicle Count', '${bill.vehicleCount}'),
                    pw.SizedBox(height: 4),
                    _buildDetailItemWithStatus('Status', bill.status),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== PAYMENT TABLE WITH SERIAL ====================

  static pw.Widget _buildPaymentTableWithSerial(Bill bill) {
    return pw.Table(
      border: pw.TableBorder.all(color: dividerColor, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(35), // SL. No
        1: const pw.FlexColumnWidth(2),   // Payment Month
        2: const pw.FlexColumnWidth(1.3), // Method
        3: const pw.FlexColumnWidth(1.5), // Date
        4: const pw.FlexColumnWidth(1.5), // Amount
      },
      children: [
        // Header Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: primaryColor),
          children: [
            _buildTableHeaderCell('SL.'),
            _buildTableHeaderCell('Payment Month'),
            _buildTableHeaderCell('Method'),
            _buildTableHeaderCell('Date'),
            _buildTableHeaderCell('Amount'),
          ],
        ),
        // Data Rows
        ...bill.payments.asMap().entries.map((entry) {
          final index = entry.key;
          final payment = entry.value;
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: index % 2 == 0 ? cardColor : backgroundColor,
            ),
            children: [
              _buildTableCell('${index + 1}', center: true),
              _buildTableCell(_formatDateShort(payment.paidAt)),
              _buildTableCell(payment.method ?? 'N/A'),
              _buildTableCell(_formatDateShort(payment.paidAt)),
              _buildTableCell('BDT ${payment.amount.toStringAsFixed(2)}'),
            ],
          );
        }),
      ],
    );
  }

  // ==================== TRANSACTION TABLE WITH SERIAL ====================

  static pw.Widget _buildTransactionTableWithSerial(List<Bill> bills) {
    return pw.Table(
      border: pw.TableBorder.all(color: dividerColor, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(35), // SL. No
        1: const pw.FlexColumnWidth(2.5), // Billing Month
        2: const pw.FlexColumnWidth(1.5), // Amount
        3: const pw.FlexColumnWidth(1),   // Status
        4: const pw.FlexColumnWidth(0.8), // Vehicles
      },
      children: [
        // Header Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: primaryColor),
          children: [
            _buildTableHeaderCell('SL.'),
            _buildTableHeaderCell('Billing Month'),
            _buildTableHeaderCell('Amount'),
            _buildTableHeaderCell('Status'),
            _buildTableHeaderCell('Vehicles'),
          ],
        ),
        // Data Rows
        ...bills.asMap().entries.map((entry) {
          final index = entry.key;
          final bill = entry.value;
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: index % 2 == 0 ? cardColor : backgroundColor,
            ),
            children: [
              _buildTableCell('${index + 1}', center: true),
              _buildTableCell(_formatDate(bill.billingMonth)),
              _buildTableCell('BDT ${bill.amount.toStringAsFixed(2)}'),
              _buildStatusTableCell(bill.status),
              _buildTableCell('${bill.vehicleCount}', center: true),
            ],
          );
        }),
      ],
    );
  }

  // ==================== TOTAL PAID BAR ====================

  static pw.Widget _buildTotalPaidBar(Bill bill) {
    final totalPaid = bill.payments.fold<double>(0.0, (sum, p) => sum + p.amount);
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: const pw.BoxDecoration(
        color: accentColor,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Text(
        'Total Paid: BDT ${totalPaid.toStringAsFixed(2)}',
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  // ==================== NO PAYMENTS BOX ====================

  static pw.Widget _buildNoPaymentsBox() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: backgroundColor,
        border: pw.Border.all(color: dividerColor),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Center(
        child: pw.Text(
          'No payments made for this bill',
          style: pw.TextStyle(
            fontSize: 9,
            color: textSecondary,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
      ),
    );
  }

  // ==================== COMPACT SUMMARY BOX ====================

  static pw.Widget _buildCompactSummaryBox(List<Bill> bills) {
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
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: cardColor,
        border: pw.Border.all(color: primaryColor, width: 1.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(width: 3, height: 12, color: lightAccent),
              pw.SizedBox(width: 6),
              pw.Text(
                'Summary',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          pw.Divider(color: dividerColor, height: 10, thickness: 0.5),
          pw.Row(
            children: [
              // Left Summary
              pw.Expanded(
                child: pw.Column(
                  children: [
                    _buildSummaryRow('Total Bills', '$totalBills'),
                    _buildSummaryRow('Paid Bills', '$paidBills', valueColor: accentColor),
                    _buildSummaryRow('Unpaid Bills', '$unpaidBills', valueColor: errorColor),
                  ],
                ),
              ),
              pw.Container(width: 0.5, height: 45, color: dividerColor),
              pw.SizedBox(width: 10),
              // Right Summary
              pw.Expanded(
                child: pw.Column(
                  children: [
                    _buildSummaryRow('Total Amount', 'BDT ${totalAmount.toStringAsFixed(2)}'),
                    _buildSummaryRow('Total Paid', 'BDT ${totalPaid.toStringAsFixed(2)}', valueColor: accentColor),
                    _buildSummaryRow('Total Due', 'BDT ${totalDue.toStringAsFixed(2)}', valueColor: errorColor),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== SIGNATURE SECTION ====================

  static pw.Widget _buildSignatureSection(Uint8List? signatureImage) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: dividerColor, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          // Customer Signature
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Customer Signature',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: textSecondary,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 35),
              pw.Container(
                width: 130,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: textPrimary, width: 0.8),
                  ),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Date: _______________',
                style: pw.TextStyle(fontSize: 7, color: textSecondary),
              ),
            ],
          ),

          // Authorized Signature
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Authorized Signature',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: textSecondary,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),
              if (signatureImage != null)
                pw.Container(
                  height: 35,
                  width: 100,
                  child: pw.Image(
                    pw.MemoryImage(signatureImage),
                    fit: pw.BoxFit.contain,
                  ),
                )
              else
                pw.SizedBox(height: 16),
              pw.Container(
                width: 130,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: textPrimary, width: 0.8),
                  ),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'For $companyName',
                style: pw.TextStyle(
                  fontSize: 7,
                  color: primaryColor,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== COMPACT FOOTER ====================

  static pw.Widget _buildCompactFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: lightAccent, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '© ${DateTime.now().year} $companyName. All rights reserved.',
            style: pw.TextStyle(fontSize: 7, color: textSecondary),
          ),
          pw.Text(
            companyTagline,
            style: pw.TextStyle(
              fontSize: 7,
              color: primaryColor,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
          pw.Text(
            _formatDate(DateTime.now().toIso8601String()),
            style: pw.TextStyle(fontSize: 7, color: textSecondary),
          ),
        ],
      ),
    );
  }

  // ==================== SECTION TITLE ====================

  static pw.Widget _buildSectionTitle(String title) {
    return pw.Row(
      children: [
        pw.Container(width: 3, height: 14, color: primaryColor),
        pw.SizedBox(width: 6),
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: primaryColor,
          ),
        ),
      ],
    );
  }

  // ==================== HELPER WIDGETS ====================

  static bool _isNotEmpty(String? value) {
    return value != null && value.isNotEmpty && value != 'null';
  }

  // Info Row for Customer Card
  static pw.Widget _buildInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 55,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(fontSize: 8, color: textSecondary),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Detail Item for Bill Card
  static pw.Widget _buildDetailItem(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          '$label:',
          style: pw.TextStyle(fontSize: 8, color: textSecondary),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: textPrimary,
          ),
        ),
      ],
    );
  }

  // Detail Item with Status Badge
  static pw.Widget _buildDetailItemWithStatus(String label, String status) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          '$label:',
          style: pw.TextStyle(fontSize: 8, color: textSecondary),
        ),
        _buildStatusBadge(status),
      ],
    );
  }

  // Status Badge
  static pw.Widget _buildStatusBadge(String status, {bool large = false}) {
    final isPaid = status.toLowerCase() == 'paid';
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(
        horizontal: large ? 10 : 5,
        vertical: large ? 3 : 2,
      ),
      decoration: pw.BoxDecoration(
        color: isPaid ? accentColor : errorColor,
        borderRadius: pw.BorderRadius.circular(large ? 10 : 6),
      ),
      child: pw.Text(
        status.toUpperCase(),
        style: pw.TextStyle(
          fontSize: large ? 9 : 6,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  // Table Header Cell
  static pw.Widget _buildTableHeaderCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  // Table Cell
  static pw.Widget _buildTableCell(String text, {bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 7,
          color: textPrimary,
        ),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }

  // Status Table Cell
  static pw.Widget _buildStatusTableCell(String status) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Center(child: _buildStatusBadge(status)),
    );
  }

  // Summary Row
  static pw.Widget _buildSummaryRow(String label, String value, {PdfColor? valueColor}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 8, color: textSecondary),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: valueColor ?? textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== SAVE PDF ====================

  static Future<File> _savePDF(pw.Document pdf, String fileName) async {
    try {
      final bytes = await pdf.save();

      Directory? directory;

      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download/Onfleet_Invoices');

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