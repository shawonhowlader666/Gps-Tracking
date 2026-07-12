import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_lock/screens/manual_payment_screen.dart';
import 'package:smart_lock/services/model/payment_stats.dart';
import 'package:smart_lock/services/model/payment_package.dart';
import 'package:smart_lock/services/payment_service.dart';

Future<String?> showPaymentDuePopupIfNeeded(BuildContext context,
    {bool forceShow = false, int? vehicleId, String? vehicleName, String? vehicleImei}) async {
  try {
    if (forceShow) {
      debugPrint('[POPUP] forceShow is true, opening dialog instantly for vehicleId: $vehicleId');
      return await showGeneralDialog<String>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.75),
        barrierLabel: 'PaymentDue',
        transitionDuration: const Duration(milliseconds: 350),
        transitionBuilder: (ctx, anim, _, child) {
          return ScaleTransition(
            scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
            child: FadeTransition(opacity: anim, child: child),
          );
        },
        pageBuilder: (ctx, _, __) => PaymentDuePopup(
          vehicleId: vehicleId,
          vehicleName: vehicleName,
          vehicleImei: vehicleImei,
        ),
      );
    }

    // Load stats and expirationInfo in parallel to speed up popup display
    final results = await Future.wait([
      PaymentService.getStats(),
      vehicleId != null
          ? PaymentService.getVehicleExpiration(vehicleId)
          : _fetchExpirationInfo(),
    ]);
    final stats = results[0] as PaymentStats?;
    final expirationInfo = results[1] as Map<String, dynamic>?;

    debugPrint('[POPUP] stats: due=${stats?.due}, enableBillAlert=${stats?.enableBillAlert}');

    if (!PaymentService.enableBillAlert) {
      debugPrint('[POPUP] BLOCKED: enableBillAlert is false (from service)');
      return null;
    }

    if (stats != null && !stats.enableBillAlert) {
      debugPrint('[POPUP] BLOCKED: stats.enableBillAlert is false');
      return null;
    }

    debugPrint('[POPUP] expirationInfo: $expirationInfo');

    if (!context.mounted) {
      debugPrint('[POPUP] BLOCKED: context not mounted');
      return null;
    }

    int daysRemaining = 999;
    bool isExpired = false;
    if (expirationInfo != null) {
      daysRemaining = (expirationInfo['days_remaining'] as int?) ?? 999;
      isExpired = expirationInfo['is_expired'] == true ||
          expirationInfo['is_expired'] == 'true';
    }

    double due = stats?.due ?? 0;
    int unpaidBillsCount = stats?.unpaidBillsCount ?? 1;
    Map<String, dynamic>? resolvedExpirationInfo = expirationInfo;

    // Filter by vehicleId, Name, or IMEI if provided
    if (vehicleId != null || vehicleName != null || vehicleImei != null) {
      try {
        final rawInvoices = await PaymentService.getInvoicesRaw();
        if (rawInvoices != null && rawInvoices['bills'] != null) {
          final List bills = rawInvoices['bills'];
          final deviceBills = bills.where((b) {
            final bVehicleId = b['vehicle_id'] ?? b['device_id'];
            final bVehicle = b['vehicle'];
            
            final matchId = vehicleId != null && bVehicleId != null && bVehicleId.toString() == vehicleId.toString();
            final matchImei = vehicleImei != null && bVehicle != null && bVehicle['imei'] != null && bVehicle['imei'].toString() == vehicleImei.toString();
            final matchName = vehicleName != null && bVehicle != null && bVehicle['name'] != null && bVehicle['name'].toString().toLowerCase().trim() == vehicleName.toString().toLowerCase().trim();
            
            return matchId || matchImei || matchName;
          }).toList();

          if (deviceBills.isNotEmpty) {
            due = deviceBills
                .where((b) => b['status'] == 'unpaid')
                .map((b) => (b['amount'] ?? b['total_bill'] ?? 0.0) as num)
                .fold(0.0, (sum, amt) => sum + amt.toDouble());

            unpaidBillsCount = deviceBills
                .where((b) => b['status'] == 'unpaid')
                .length;

            final vehicleData = deviceBills.first['vehicle'];
            if (vehicleData != null) {
              daysRemaining = (vehicleData['days_remaining'] as int?) ?? 999;
              isExpired = vehicleData['is_expired'] == true || vehicleData['is_expired'] == 'true';
              resolvedExpirationInfo = {
                'days_remaining': daysRemaining,
                'is_expired': isExpired,
                'expiration_date': vehicleData['expiration_date'],
                'human_readable': vehicleData['human_readable'],
              };
            }
          }
        }
      } catch (_) {}
    }

    debugPrint('[POPUP] due=$due, isExpired=$isExpired, daysRemaining=$daysRemaining, forceShow=$forceShow');

    // Alert triggers: server says due balance OR server says expired OR days running out (server-driven: days_remaining <= 0)
    // forceShow=true bypasses this (e.g. called from device tap when WOX says expired)
    final bool shouldAlert =
        forceShow || due > 0 || isExpired || daysRemaining <= 0;
    if (!shouldAlert) {
      debugPrint('[POPUP] BLOCKED: shouldAlert is false');
      return null;
    }

    // Use stats fallback if stats was null
    final resolvedStats = PaymentStats(
      due: due,
      totalBilled: stats?.totalBilled ?? 0,
      totalPaid: stats?.totalPaid ?? 0,
      unpaidBillsCount: unpaidBillsCount > 0 ? unpaidBillsCount : 1,
      enableBillAlert: stats?.enableBillAlert ?? true,
    );

    // Final warning mode: server says is_expired = true (no hardcoded day threshold)
    final bool isAfter10th = isExpired;

    if (!context.mounted) {
      debugPrint('[POPUP] BLOCKED: context not mounted after async bills check');
      return null;
    }

    return await showGeneralDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      barrierLabel: 'PaymentDue',
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (ctx, anim, _, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (ctx, _, __) => PaymentDuePopup(
        stats: resolvedStats,
        expirationInfo: resolvedExpirationInfo,
        isAfter10th: isAfter10th,
        vehicleId: vehicleId,
        vehicleName: vehicleName,
        vehicleImei: vehicleImei,
      ),
    );
  } catch (e) {
    debugPrint('Error showing payment due popup: $e');
    return null;
  }
}

Future<Map<String, dynamic>?> _fetchExpirationInfo() async {
  try {
    final result = await PaymentService.getExpirationInfo();
    return result;
  } catch (_) {
    return null;
  }
}

// ─────────────────────────────────────────────
// The popup widget
// ─────────────────────────────────────────────

class PaymentDuePopup extends StatefulWidget {
  final PaymentStats? stats;
  final Map<String, dynamic>? expirationInfo;
  final bool? isAfter10th;
  final int? vehicleId;
  final String? vehicleName;
  final String? vehicleImei;

  const PaymentDuePopup({
    super.key,
    this.stats,
    this.expirationInfo,
    this.isAfter10th,
    this.vehicleId,
    this.vehicleName,
    this.vehicleImei,
  });

  @override
  State<PaymentDuePopup> createState() => _PaymentDuePopupState();
}

class _PaymentDuePopupState extends State<PaymentDuePopup> {
  final bool _isPaymentLoading = false;
  String? _errorMessage;
  late Future<DuePopupData> _duePopupDataFuture;

  PaymentStats? _loadedStats;
  Map<String, dynamic>? _loadedExpirationInfo;
  bool? _loadedIsAfter10th;
  bool _isLoading = false;
  bool _hasError = false;

  PaymentStats get _stats => _loadedStats ?? widget.stats!;
  Map<String, dynamic>? get _expirationInfo => _loadedExpirationInfo ?? widget.expirationInfo;
  bool get _isAfter10th => _loadedIsAfter10th ?? widget.isAfter10th!;

  @override
  void initState() {
    super.initState();
    if (widget.stats != null) {
      _duePopupDataFuture = loadDuePopupData(widget.stats!.unpaidBillsCount);
    } else {
      _loadDataAsync();
    }
  }

  void _loadDataAsync() {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    loadCombinedDuePopupData(
      vehicleId: widget.vehicleId,
      vehicleName: widget.vehicleName,
      vehicleImei: widget.vehicleImei,
    ).then((data) {
      if (mounted) {
        setState(() {
          _loadedStats = data.stats;
          _loadedExpirationInfo = data.expirationInfo;
          _loadedIsAfter10th = data.expirationInfo?['is_expired'] == true ||
              data.expirationInfo?['is_expired'] == 'true';
          _duePopupDataFuture = Future.value(DuePopupData(data.packages));
          _isLoading = false;
        });
      }
    }).catchError((e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    });
  }

  int get _daysRemaining =>
      (_expirationInfo?['days_remaining'] as int?) ?? 0;

  bool get _isExpired =>
      _expirationInfo?['is_expired'] == true ||
      _expirationInfo?['is_expired'] == 'true';

  int get _overdueBlocks {
    if (_isExpired) return 10;
    final overdue = -_daysRemaining;
    if (overdue <= 0) return 0;
    return overdue.clamp(0, 10);
  }

  Future<void> _handlePay(double amount, String packageType, {String? packageTitle}) async {
    if (!mounted) return;

    final bool isAfter10th = _isAfter10th;
    final nav = Navigator.of(context, rootNavigator: true);

    // ✅ আগে ManualPaymentScreen push করো, তারপর popup pop করো
    // এতে context valid থাকে
    nav.pop('go_to_payment');

    // ✅ addPostFrameCallback দিয়ে popup বন্ধ হওয়ার পর push করো
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await nav.push<String>(
        MaterialPageRoute(
          builder: (_) => ManualPaymentScreen(
            dueAmount: amount,
            isAfter10th: isAfter10th,
            packageType: packageType,
            packageTitle: packageTitle,
            vehicleName: widget.vehicleName,
          ),
        ),
      );
    });
  }

  void _handleSnooze() {
    Navigator.of(context).pop('snoozed');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {},
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE53935).withValues(alpha: 0.3),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  _isLoading
                      ? Container(
                          height: 250,
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(
                            color: Color(0xFFE53935),
                          ),
                        )
                      : _hasError
                          ? Container(
                              height: 250,
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.cloud_off_rounded, color: Colors.grey, size: 40),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'বকেয়া বিল লোড করা যায়নি।',
                                    style: TextStyle(color: Colors.grey, fontSize: 14),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _loadDataAsync,
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
                                    child: const Text('Retry'),
                                  )
                                ],
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildHeader(),
                                _buildBody(),
                              ],
                            ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: _handleSnooze,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C2C3E), Color(0xFF8B1A1A)],
        ),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
              ),
              Icon(
                _isAfter10th ? Icons.lock_outline : Icons.lock_clock,
                color: _isAfter10th
                    ? const Color(0xFFFF5252)
                    : const Color(0xFFFF8A65),
                size: 42,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _isAfter10th ? 'সেবা স্থগিত' : 'পেমেন্ট বকেয়া',
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          if (widget.vehicleName != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.vehicleName!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_isAfter10th) ...[
            const SizedBox(height: 6),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
              ),
              child: const Text(
                '⛔  বিল পরিশোধ না করলে লাইভ ট্র্যাকিং বন্ধ থাকবে',
                style: TextStyle(
                  color: Color(0xFFFF8A80),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(
        children: [
          const Text(
            'মোট বকেয়া',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  '৳',
                  style: TextStyle(
                    color: Color(0xFFE53935),
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Text(
                _stats.due.toStringAsFixed(2),
                style: const TextStyle(
                  color: Color(0xFFE53935),
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          _buildOverdueBar(),
          const SizedBox(height: 10),

          _buildWarningMessage(),

          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFFE53935), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 20),

          // ✅ Pay Now Button (for the exact due amount)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isPaymentLoading
                  ? null
                  : () => _handlePay(_stats.due, 'due_payment', packageTitle: 'Due Payment (${_stats.due.toStringAsFixed(0)} BDT)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B6B3A),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF1B6B3A).withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.credit_card_rounded, size: 20),
              label: const Text(
                'এখনই পরিশোধ করুন',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Divider
          const Row(
            children: [
              Expanded(child: Divider(color: Color(0xFFEEEEEE))),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'অথবা প্যাকেজ সিলেক্ট করুন',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              Expanded(child: Divider(color: Color(0xFFEEEEEE))),
            ],
          ),

          const SizedBox(height: 16),

          // ✅ Package options row (Dynamically loaded, defaults instantly)
          FutureBuilder<DuePopupData>(
            future: _duePopupDataFuture,
            builder: (context, snapshot) {
              final data = snapshot.data;
              if (data == null || data.packages.isEmpty) {
                return const SizedBox.shrink();
              }
              final pkg1 = data.packages[0];
              final pkg2 = data.packages.length > 1 ? data.packages[1] : pkg1;

              if (pkg1 == pkg2) {
                return SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isPaymentLoading
                        ? null
                        : () => _handlePay(pkg1.finalPrice, pkg1.key, packageTitle: pkg1.buttonText),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE4B34E),
                      foregroundColor: Colors.black,
                      disabledBackgroundColor:
                          const Color(0xFFE4B34E).withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isPaymentLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            pkg1.buttonText,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                  ),
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isPaymentLoading
                            ? null
                            : () => _handlePay(pkg1.finalPrice, pkg1.key, packageTitle: pkg1.buttonText),
                        style: ElevatedButton.styleFrom(
                           backgroundColor: const Color(0xFF1B6B3A),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              const Color(0xFF1B6B3A).withValues(alpha: 0.6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        child: _isPaymentLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                pkg1.buttonText,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isPaymentLoading
                            ? null
                            : () => _handlePay(pkg2.finalPrice, pkg2.key, packageTitle: pkg2.buttonText),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE4B34E),
                          foregroundColor: Colors.black,
                          disabledBackgroundColor:
                              const Color(0xFFE4B34E).withValues(alpha: 0.6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        child: _isPaymentLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                pkg2.buttonText,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 10),

          // Snooze
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _handleSnooze,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF555555),
                side: const BorderSide(color: Color(0xFFDDDDDD)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.access_time, size: 18),
              label: const Text(
                'পরে মনে করিয়ে দিন',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),

          // After 10th: forced warning
          if (_isAfter10th) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEEE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFE53935).withValues(alpha: 0.4),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFE53935), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'আপনার সময় শেষ হয়েছে। সেবা পুনরায় চালু করতে অবিলম্বে পরিশোধ করুন।',
                      style: TextStyle(
                        color: Color(0xFFE53935),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOverdueBar() {
    final overdueDays = (-_daysRemaining).clamp(0, 999);
    return Column(
      children: [
        if (overdueDays > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEEEE),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFFE53935).withValues(alpha: 0.3)),
            ),
            child: Text(
              '$overdueDays দিন অতিক্রান্ত',
              style: const TextStyle(
                color: Color(0xFFE53935),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(10, (i) {
            final isRed = i >= (10 - _overdueBlocks);
            return Expanded(
              child: Container(
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color:
                      isRed ? const Color(0xFFE53935) : const Color(0xFFFFCDD2),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildWarningMessage() {
    if (_isAfter10th) {
      return const Text(
        'আপনার বিল পরিশোধের সময়সীমা পেরিয়ে গেছে।\nসেবা স্থগিত রয়েছে।',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFFE53935),
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.5,
        ),
      );
    }

    final remaining = _daysRemaining > 0 ? _daysRemaining : 0;
    final message =
        _isExpired ? 'আপনার সেবা বন্ধ হয়ে গেছে।' : 'সেবা বন্ধ হতে আর মাত্র ';

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: const TextStyle(
          color: Color(0xFF444444),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        children: [
          TextSpan(text: message),
          if (!_isExpired) ...[
            TextSpan(
              text: '$remaining দিন',
              style: const TextStyle(
                color: Color(0xFFE53935),
                fontWeight: FontWeight.w700,
              ),
            ),
            const TextSpan(text: ' বাকি।'),
          ],
        ],
      ),
    );
  }
}

class DuePopupDataCombined {
  final PaymentStats? stats;
  final Map<String, dynamic>? expirationInfo;
  final List<PaymentPackage> packages;
  DuePopupDataCombined(this.stats, this.expirationInfo, this.packages);
}

Future<DuePopupDataCombined> loadCombinedDuePopupData({int? vehicleId, String? vehicleName, String? vehicleImei}) async {
  final stats = await PaymentService.getStats();
  PaymentStats? resolvedStats = stats;
  Map<String, dynamic>? resolvedExpirationInfo;

  if (vehicleId != null || vehicleName != null || vehicleImei != null) {
    if (vehicleId != null) {
      resolvedExpirationInfo = await PaymentService.getVehicleExpiration(vehicleId);
    }
    try {
      final rawInvoices = await PaymentService.getInvoicesRaw();
      if (rawInvoices != null && rawInvoices['bills'] != null) {
        final List bills = rawInvoices['bills'];
        final deviceBills = bills.where((b) {
          final bVehicleId = b['vehicle_id'] ?? b['device_id'];
          final bVehicle = b['vehicle'];
          
          final matchId = vehicleId != null && bVehicleId != null && bVehicleId.toString() == vehicleId.toString();
          final matchImei = vehicleImei != null && bVehicle != null && bVehicle['imei'] != null && bVehicle['imei'].toString() == vehicleImei.toString();
          final matchName = vehicleName != null && bVehicle != null && bVehicle['name'] != null && bVehicle['name'].toString().toLowerCase().trim() == vehicleName.toString().toLowerCase().trim();
          
          return matchId || matchImei || matchName;
        }).toList();

        if (deviceBills.isNotEmpty) {
          final double deviceDue = deviceBills
              .where((b) => b['status'] == 'unpaid')
              .map((b) => (b['amount'] ?? b['total_bill'] ?? 0.0) as num)
              .fold(0.0, (sum, amt) => sum + amt.toDouble());

          final int deviceUnpaidCount = deviceBills
              .where((b) => b['status'] == 'unpaid')
              .length;

          resolvedStats = PaymentStats(
            due: deviceDue,
            totalBilled: deviceBills
                .map((b) => (b['amount'] ?? b['total_bill'] ?? 0.0) as num)
                .fold(0.0, (sum, amt) => sum + amt.toDouble()),
            totalPaid: deviceBills
                .where((b) => b['status'] == 'paid')
                .map((b) => (b['amount'] ?? b['total_bill'] ?? 0.0) as num)
                .fold(0.0, (sum, amt) => sum + amt.toDouble()),
            unpaidBillsCount: deviceUnpaidCount > 0 ? deviceUnpaidCount : 1,
            enableBillAlert: stats?.enableBillAlert ?? true,
          );

          final vehicleData = deviceBills.first['vehicle'];
          if (vehicleData != null) {
            resolvedExpirationInfo = {
              'days_remaining': (vehicleData['days_remaining'] as int?) ?? 999,
              'is_expired': vehicleData['is_expired'] == true || vehicleData['is_expired'] == 'true',
              'expiration_date': vehicleData['expiration_date'],
              'human_readable': vehicleData['human_readable'],
            };
          }
        }
      }
    } catch (_) {}
  } else {
    resolvedExpirationInfo = await PaymentService.getExpirationInfo();
  }

  final unpaidBillsCount = resolvedStats?.unpaidBillsCount ?? 1;
  final packages = await fetchAndRecommendPackages(unpaidBillsCount);
  return DuePopupDataCombined(resolvedStats, resolvedExpirationInfo, packages);
}

class DuePopupData {
  final List<PaymentPackage> packages;
  DuePopupData(this.packages);
}

Future<DuePopupData> loadDuePopupData(int unpaidBillsCount) async {
  final packages = await fetchAndRecommendPackages(unpaidBillsCount);
  return DuePopupData(packages);
}
