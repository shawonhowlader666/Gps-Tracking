import 'package:flutter/material.dart';
import 'package:gpspro/services/model/bill.dart';
import 'package:gpspro/services/model/payment_stats.dart';
import 'package:gpspro/services/payment_service.dart';
import 'package:gpspro/screens/web_view.dart';

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

    // Show loading dialog
    if (!mounted) return;
    _showLoadingDialog();

    try {
      final gatewayUrl = await PaymentService.initiateSslPayment();

      if (!mounted) return;

      // Hide loading dialog
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

      // Hide loading dialog if showing
      Navigator.of(context).pop();

      _showErrorSnackBar(_getErrorMessage(e));
    }
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
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _loadData,
        ),
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
                Text('Initiating payment...'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Payment & Invoices'),
        backgroundColor: const Color(0xFF3E6FB8),
        foregroundColor: Colors.white,
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
            hasStats ? 'BDT :  ${due.toStringAsFixed(0)}৳' : 'BDT --',
            style: const TextStyle(
              color: Colors.red,
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
            bill.billingMonth,
            style: const TextStyle(
              fontSize: 16,
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
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  if (bill.payments.isNotEmpty) ...[
                    const Text(
                      'Payments',
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                payment.method ?? 'Unknown Method',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              Text(
                payment.paidAt,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Text(
            'BDT ${payment.amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF22C55E),
            ),
          ),
        ],
      ),
    );
  }
}