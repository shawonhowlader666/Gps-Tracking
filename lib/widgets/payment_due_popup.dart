import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:smart_lock/screens/manual_payment_screen.dart';
import 'package:smart_lock/services/model/payment_stats.dart';
import 'package:smart_lock/services/payment_service.dart';

Future<String?> showPaymentDuePopupIfNeeded(BuildContext context) async {
  try {
    final stats = await PaymentService.getStats();
    if (stats == null) return null;
    if (stats.due <= 0) return null;

    final expirationInfo = await _fetchExpirationInfo();

    if (!context.mounted) return null;

    final todayDay = DateTime.now().day;
    final bool isAfter10th = todayDay > 10;

    // ✅ After 10th: loop — ManualPaymentScreen থেকে back করলে আবার popup দেখাবে
    if (isAfter10th) {
      while (true) {
        if (!context.mounted) return null;

        final result = await showGeneralDialog<String>(
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
            stats: stats,
            expirationInfo: expirationInfo,
            isAfter10th: true,
          ),
        );

        // ✅ 'payment_done' = WhatsApp এ send হয়েছে → loop break
        if (result == 'payment_done') return 'payment_done';

        // ✅ 'go_to_payment' = ManualPaymentScreen এ গেছে
        // সেখান থেকে back আসলে loop আবার চলবে → popup দেখাবে
        // অন্য যেকোনো result এও loop চলতে থাকে
      }
    }

    // ✅ 1–10 তারিখ: একবার দেখাও, snooze করা যাবে
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
        stats: stats,
        expirationInfo: expirationInfo,
        isAfter10th: false,
      ),
    );
  } on TimeoutException {
    return null;
  } on SocketException {
    return null;
  } catch (_) {
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
  final PaymentStats stats;
  final Map<String, dynamic>? expirationInfo;
  final bool isAfter10th;

  const PaymentDuePopup({
    super.key,
    required this.stats,
    this.expirationInfo,
    required this.isAfter10th,
  });

  @override
  State<PaymentDuePopup> createState() => _PaymentDuePopupState();
}

class _PaymentDuePopupState extends State<PaymentDuePopup> {
  bool _isPaymentLoading = false;
  String? _errorMessage;

  int get _daysRemaining =>
      (widget.expirationInfo?['days_remaining'] as int?) ?? 0;

  bool get _isExpired =>
      widget.expirationInfo?['is_expired'] == true ||
          widget.expirationInfo?['is_expired'] == 'true';

  int get _overdueBlocks {
    if (_isExpired) return 10;
    final overdue = -_daysRemaining;
    if (overdue <= 0) return 0;
    return overdue.clamp(0, 10);
  }

  Future<void> _handlePay() async {
    if (!mounted) return;

    final double due = widget.stats.due;
    final bool isAfter10th = widget.isAfter10th;
    final nav = Navigator.of(context, rootNavigator: true);

    // ✅ আগে ManualPaymentScreen push করো, তারপর popup pop করো
    // এতে context valid থাকে
    nav.pop('go_to_payment');

    // ✅ addPostFrameCallback দিয়ে popup বন্ধ হওয়ার পর push করো
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await nav.push<String>(
        MaterialPageRoute(
          builder: (_) => ManualPaymentScreen(
            dueAmount: due,
            isAfter10th: isAfter10th,
          ),
        ),
      );
    });
  }

  void _handleSnooze() {
    if (!widget.isAfter10th) {
      Navigator.of(context).pop('snoozed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.isAfter10th,
      onPopInvoked: (didPop) {},
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(              color: Colors.white,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(),
                  _buildBody(),
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
                widget.isAfter10th ? Icons.lock_outline : Icons.lock_clock,
                color: widget.isAfter10th
                    ? const Color(0xFFFF5252)
                    : const Color(0xFFFF8A65),
                size: 42,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.isAfter10th ? 'সেবা স্থগিত' : 'পেমেন্ট বকেয়া',
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          if (widget.isAfter10th) ...[
            const SizedBox(height: 6),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border:
                Border.all(color: Colors.red.withValues(alpha: 0.5)),
              ),
              child: const Text(
                '⛔  বিল পরিশোধ না করলে এই বার্তা বন্ধ হবে না',
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
                widget.stats.due.toStringAsFixed(2),
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
              style:
              const TextStyle(color: Color(0xFFE53935), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 20),

          // ✅ Pay button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isPaymentLoading ? null : _handlePay,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B6B3A),
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                const Color(0xFF1B6B3A).withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              icon: _isPaymentLoading
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.credit_card, size: 20),
              label: Text(
                _isPaymentLoading
                    ? 'অনুগ্রহ করে অপেক্ষা করুন...'
                    : 'পরিশোধ সম্পন্ন করুন',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Snooze: শুধু 1–10 তারিখ
          if (!widget.isAfter10th)
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
                  '৭ দিন পরে পুনরায় মনে করিয়ে দিন',
                  style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            ),

          // After 10th: forced warning
          if (widget.isAfter10th)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEEE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFE53935).withValues(alpha: 0.4),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Color(0xFFE53935), size: 18),
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
      ),
    );
  }

  Widget _buildOverdueBar() {
    final overdueDays = (-_daysRemaining).clamp(0, 999);
    return Column(
      children: [
        if (overdueDays > 0)
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                  color: isRed
                      ? const Color(0xFFE53935)
                      : const Color(0xFFFFCDD2),
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
    if (widget.isAfter10th) {
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
    final message = _isExpired
        ? 'আপনার সেবা বন্ধ হয়ে গেছে।'
        : 'সেবা বন্ধ হতে আর মাত্র ';

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