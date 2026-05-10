import 'package:flutter/material.dart';
import 'package:smart_lock/services/model/bill.dart';
import 'package:smart_lock/services/model/payment_stats.dart';
import 'package:smart_lock/services/payment_service.dart';
import 'package:smart_lock/screens/web_view.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'dart:io';

import '../services/pdf_generator.dart';

class PaymentListScreen extends StatefulWidget {
  @override
  _PaymentListScreenState createState() => _PaymentListScreenState();
}

class _PaymentListScreenState extends State<PaymentListScreen> {
  PaymentStats? _stats;
  List<Bill> _bills = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      _loadMoreBills();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final stats = await PaymentService.getStats();
      final bills = await PaymentService.getBills(page: 1);

      if (!mounted) return;

      setState(() {
        _stats = stats;
        _bills = bills ?? [];
        _isLoading = false;
        _currentPage = 1;
      });
    } catch (e) {
      debugPrint('Error loading data: $e');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = _getErrorMessage(e);
      });
    }
  }

  Future<void> _loadMoreBills() async {
    if (_isLoadingMore) return;

    if (!mounted) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      _currentPage++;
      final moreBills = await PaymentService.getBills(page: _currentPage);

      if (!mounted) return;

      if (moreBills != null && moreBills.isNotEmpty) {
        setState(() {
          _bills.addAll(moreBills);
          _isLoadingMore = false;
        });
      } else {
        setState(() {
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading more bills: $e');

      if (!mounted) return;

      setState(() {
        _isLoadingMore = false;
        _currentPage--;
      });

      _showErrorSnackBar('Failed to load more bills');
    }
  }

  Future<void> _initiatePayment() async {
    if (_stats == null || _stats!.due <= 0) {
      if (!mounted) return;
      _showErrorSnackBar('No due available to pay');
      return;
    }

    if (!mounted) return;
    _showLoadingDialog();

    try {
      final gatewayUrl = await PaymentService.initiateSslPayment();

      if (!mounted) return;

      Navigator.of(context).pop();

      if (gatewayUrl != null) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WebViewScreen(
              title: 'Payment',
              url: gatewayUrl,
            ),
          ),
        );

        if (mounted) {
          _loadData();
        }
      } else {
        _showErrorSnackBar('Failed to initiate payment');
      }
    } catch (e) {
      debugPrint('Payment initiation error: $e');

      if (!mounted) return;

      Navigator.of(context).pop();

      _showErrorSnackBar(_getErrorMessage(e));
    }
  }

  Future<void> _downloadBillPDF(Bill bill) async {
    try {
      // Request storage permission
      if (await _requestStoragePermission()) {
        if (!mounted) return;

        // Show loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 16),
                Text('Generating PDF...'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );

        final file = await PDFGenerator.generateBillPDF(bill);

        if (!mounted) return;

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF saved to ${file.path}'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () => OpenFile.open(file.path),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        if (!mounted) return;
        _showErrorSnackBar('Storage permission denied. Please enable it in settings.');
      }
    } catch (e) {
      debugPrint('Error generating PDF: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      _showErrorSnackBar('Failed to generate PDF: ${e.toString()}');
    }
  }

  Future<void> _downloadAllTransactionsPDF() async {
    if (_bills.isEmpty) {
      _showErrorSnackBar('No transactions to export');
      return;
    }

    try {
      if (await _requestStoragePermission()) {
        if (!mounted) return;

        _showLoadingDialog();

        final file = await PDFGenerator.generateAllTransactionsPDF(_bills);

        if (!mounted) return;

        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF saved to ${file.path}'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () => OpenFile.open(file.path),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        if (!mounted) return;
        _showErrorSnackBar('Storage permission denied. Please enable it in settings.');
      }
    } catch (e) {
      debugPrint('Error generating PDF: $e');
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErrorSnackBar('Failed to generate PDF: ${e.toString()}');
    }
  }



  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      // For Android 13+ (API 33+)
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }

      // For Android 10-12 (API 29-32)
      if (await Permission.storage.isGranted) {
        return true;
      }

      // Request appropriate permission based on Android version
      Map<Permission, PermissionStatus> statuses = await [
        Permission.storage,
        Permission.manageExternalStorage,
      ].request();

      // Check if any permission is granted
      if (statuses[Permission.storage]?.isGranted == true ||
          statuses[Permission.manageExternalStorage]?.isGranted == true) {
        return true;
      }

      // If permanently denied, show settings dialog
      if (statuses[Permission.storage]?.isPermanentlyDenied == true ||
          statuses[Permission.manageExternalStorage]?.isPermanentlyDenied == true) {
        return await _showPermissionDialog();
      }

      return false;
    }

    // iOS doesn't need storage permission for app documents
    return true;
  }

  Future<bool> _showPermissionDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Storage Permission Required'),
        content: const Text(
          'This app needs storage permission to save PDF files. '
              'Please enable it in app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context, false);
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    ) ?? false;
  }

  String _getErrorMessage(dynamic error) {
    String errorString = error.toString().toLowerCase();
    if (errorString.contains('timeout') || errorString.contains('timed out')) {
      return 'Connection timed out. Please check your internet connection.';
    } else if (errorString.contains('socket') || errorString.contains('connection')) {
      return 'Network error. Please check your internet connection.';
    } else {
      return 'Something went wrong. Please try again.';
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Processing...'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _extractMonthFromDate(String dateString) {
    try {
      DateTime date;

      if (dateString.contains('T')) {
        date = DateTime.parse(dateString);
      } else if (dateString.contains('-')) {
        date = DateFormat('yyyy-MM-dd').parse(dateString);
      } else {
        date = DateFormat('dd/MM/yyyy').parse(dateString);
      }

      return DateFormat('dd MMMM yyyy').format(date);
    } catch (e) {
      return dateString.split(' ').first;
    }
  }
  String _formatFullDate(String dateString) {
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



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Payment & Invoices'),
        backgroundColor: const Color(0xFF3E6FB8),
        foregroundColor: Colors.white,
        actions: [
          if (_bills.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Download All Transactions',
              onPressed: _downloadAllTransactionsPDF,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _bills.isEmpty) {
      return _buildErrorWidget();
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatsCard(),
            const SizedBox(height: 24),
            const Text(
              'Transaction History',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            _buildBillsList(),
            if (_isLoadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3E6FB8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    final due = _stats?.due ?? 0.0;
    final unpaid = _stats?.unpaidBillsCount ?? 0;
    final paid = _stats?.totalPaid ?? 0.0;
    final bool hasStats = _stats != null;
    final bool hasDue = due > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3E6FB8), Color(0xFF5C8ACF)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3E6FB8).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total Due',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasStats ? 'BDT ${due.toStringAsFixed(0)}৳' : 'BDT --',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Unpaid Bills',
                  hasStats ? unpaid.toString() : '--',
                  Icons.receipt_long,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white24,
              ),
              Expanded(
                child: _buildStatItem(
                  'Total Paid',
                  hasStats ? 'BDT ${paid.toStringAsFixed(0)}' : '--',
                  Icons.history,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (hasStats && hasDue) ? _initiatePayment : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF3E6FB8),
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
                disabledForegroundColor: const Color(0xFF3E6FB8).withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Pay Now',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildBillsList() {
    if (_bills.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                "No transactions found",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _bills.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final bill = _bills[index];
        return _buildBillItem(bill);
      },
    );
  }

  Widget _buildBillItem(Bill bill) {
    Color statusColor;
    Color statusBgColor;
    IconData statusIcon;

    switch (bill.status.toLowerCase()) {
      case 'paid':
        statusColor = const Color(0xFF22C55E);
        statusBgColor = const Color(0xFFDCFCE7);
        statusIcon = Icons.check_circle_outline;
        break;
      case 'unpaid':
        statusColor = const Color(0xFFEF4444);
        statusBgColor = const Color(0xFFFEE2E2);
        statusIcon = Icons.error_outline;
        break;
      default:
        statusColor = const Color(0xFFF59E0B);
        statusBgColor = const Color(0xFFFEF3C7);
        statusIcon = Icons.access_time;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              statusIcon,
              color: statusColor,
              size: 24,
            ),
          ),
          title: Text(
            _formatFullDate(bill.billingMonth),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                'BDT ${bill.amount.toStringAsFixed(2)} • ${bill.vehicleCount} Vehicles',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.download, size: 20),
                color: const Color(0xFF3E6FB8),
                tooltip: 'Download PDF',
                onPressed: () => _downloadBillPDF(bill),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  if (bill.payments.isNotEmpty) ...[
                    const Text(
                      'Payment History',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...bill.payments.map((payment) => _buildPaymentRow(payment)),
                  ] else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No payments made for this bill',
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRow(payment) {
    final paymentMonth = _extractMonthFromDate(payment.paidAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_month,
                        size: 16,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        paymentMonth,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    payment.method ?? 'Unknown Method',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    payment.paidAt,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'BDT ${payment.amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF22C55E),
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}