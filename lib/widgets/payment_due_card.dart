import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:smart_lock/services/payment_service.dart';

class PaymentDueCountdownCard extends StatefulWidget {
  /// Called when the user taps "Pay Now".
  /// Receives the SSL gateway URL (or null on error).
  final void Function(String? gatewayUrl)? onPayNow;

  const PaymentDueCountdownCard({super.key, this.onPayNow});

  @override
  State<PaymentDueCountdownCard> createState() =>
      _PaymentDueCountdownCardState();
}

class _PaymentDueCountdownCardState extends State<PaymentDueCountdownCard>
    with SingleTickerProviderStateMixin {
  // ── state ──────────────────────────────────────────────────────────────────
  _CardState _state = _CardState.loading;
  double _due = 0;
  DateTime? _expirationDate;
  bool _isExpired = false;

  Duration _remaining = Duration.zero;
  Timer? _countdownTimer;

  bool _isPaying = false;

  // pulse animation
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // ── colours / styles ────────────────────────────────────────────────────────
  static const Color _crimson = Color(0xFFDC2626);
  static const Color _amber = Color(0xFFD97706);
  static const Color _green = Color(0xFF16A34A);
  static const Color _darkBg = Color(0xFF1C1917);
  static const Color _cardBg = Color(0xFF292524);
  static const Color _textLight = Color(0xFFF5F5F4);
  static const Color _textMuted = Color(0xFFA8A29E);

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _loadData();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── data ────────────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _state = _CardState.loading);

    try {
      final stats = await PaymentService.getStats();
      final expInfo = await PaymentService.getExpirationInfo();

      if (!mounted) return;

      final due = stats?.due ?? 0;
      if (due <= 0) {
        setState(() => _state = _CardState.noDue);
        return;
      }

      DateTime? expDate;
      bool expired = false;

      if (expInfo != null) {
        final raw = expInfo['expiration_date']?.toString();
        expDate = raw != null ? DateTime.tryParse(raw) : null;
        expired =
            expInfo['is_expired'] == true || expInfo['is_expired'] == 'true';
      }

      setState(() {
        _due = due;
        _expirationDate = expDate;
        _isExpired = expired;
        _state = _CardState.due;
      });

      _startCountdown();
    } on TimeoutException {
      if (mounted) setState(() => _state = _CardState.error);
    } on SocketException {
      if (mounted) setState(() => _state = _CardState.error);
    } catch (_) {
      if (mounted) setState(() => _state = _CardState.error);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    if (_expirationDate == null) return;

    _updateRemaining();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    if (_expirationDate == null) return;
    final diff = _expirationDate!.difference(DateTime.now());
    setState(() {
      _remaining = diff.isNegative ? Duration.zero : diff;
      _isExpired = diff.isNegative;
    });
  }

  // ── pay ──────────────────────────────────────────────────────────────────────
  Future<void> _handlePayNow() async {
    if (_isPaying) return;
    setState(() => _isPaying = true);
    try {
      final url = await PaymentService.initiateSslPayment();
      widget.onPayNow?.call(url);
    } catch (_) {
      widget.onPayNow?.call(null);
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _CardState.loading:
        return _buildShell(child: _buildLoading());
      case _CardState.noDue:
        return const SizedBox.shrink(); // hide if no due
      case _CardState.error:
        return _buildShell(child: _buildError());
      case _CardState.due:
        return _buildShell(child: _buildDueContent());
    }
  }

  Widget _buildShell({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _crimson.withValues(alpha: 0.25),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  // ── loading ──────────────────────────────────────────────────────────────────
  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: CircularProgressIndicator(
          color: _amber,
          strokeWidth: 2,
        ),
      ),
    );
  }

  // ── error ────────────────────────────────────────────────────────────────────
  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: _textMuted, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'পেমেন্ট তথ্য লোড হয়নি',
              style: TextStyle(color: _textMuted, fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: _loadData,
            child: const Text(
              'পুনরায় চেষ্টা',
              style: TextStyle(
                color: _amber,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── main content ──────────────────────────────────────────────────────────────
  Widget _buildDueContent() {
    final urgencyColor = _isExpired ? _crimson : _amber;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Top strip ────────────────────────────────────────────────────
        _buildTopStrip(urgencyColor),

        // ── Body ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            children: [
              // Due amount row
              _buildDueRow(),
              const SizedBox(height: 14),

              // Countdown
              _buildCountdown(urgencyColor),
              const SizedBox(height: 16),

              // Pay button
              _buildPayButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopStrip(Color urgencyColor) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              urgencyColor.withValues(alpha: 0.9),
              urgencyColor.withValues(alpha: 0.6),
            ],
          ),
        ),
        child: Row(
          children: [
            ScaleTransition(
              scale: _pulseAnim,
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _isExpired
                  ? 'সেবা মেয়াদ উত্তীর্ণ — অবিলম্বে পরিশোধ করুন'
                  : 'বিল পরিশোধের সময়সীমা আসছে',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDueRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Icon
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _crimson.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child:
              const Icon(Icons.receipt_long_rounded, color: _crimson, size: 20),
        ),
        const SizedBox(width: 12),

        // Label + amount
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'মোট বকেয়া',
              style: TextStyle(
                color: _textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            RichText(
              text: TextSpan(
                children: [
                  const TextSpan(
                    text: '৳ ',
                    style: TextStyle(
                      color: _crimson,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: _due.toStringAsFixed(2),
                    style: const TextStyle(
                      color: _textLight,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const Spacer(),

        // Expiry date badge
        if (_expirationDate != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'মেয়াদ শেষ',
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_expirationDate!.day.toString().padLeft(2, '0')}/'
                  '${_expirationDate!.month.toString().padLeft(2, '0')}/'
                  '${_expirationDate!.year}',
                  style: const TextStyle(
                    color: _textLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCountdown(Color urgencyColor) {
    if (_isExpired) {
      return AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, __) => Opacity(
          opacity: _pulseAnim.value,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _crimson.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _crimson.withValues(alpha: 0.4),
              ),
            ),
            child: const Center(
              child: Text(
                '⛔  মেয়াদ শেষ হয়ে গেছে',
                style: TextStyle(
                  color: _crimson,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final days = _remaining.inDays;
    final hours = _remaining.inHours % 24;
    final minutes = _remaining.inMinutes % 60;
    final seconds = _remaining.inSeconds % 60;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: urgencyColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Text(
            'সময় বাকি আছে',
            style: TextStyle(
              color: urgencyColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTimeUnit(value: days, label: 'দিন', color: urgencyColor),
              _buildSeparator(),
              _buildTimeUnit(value: hours, label: 'ঘণ্টা', color: urgencyColor),
              _buildSeparator(),
              _buildTimeUnit(
                  value: minutes, label: 'মিনিট', color: urgencyColor),
              _buildSeparator(),
              _buildTimeUnit(
                  value: seconds, label: 'সেকেন্ড', color: urgencyColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeUnit(
      {required int value, required String label, required Color color}) {
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Text(
            value.toString().padLeft(2, '0'),
            key: ValueKey(value),
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: _textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSeparator() {
    return const Text(
      ':',
      style: TextStyle(
        color: _textMuted,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
    );
  }

  Widget _buildPayButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _isPaying ? null : _handlePayNow,
        style: ElevatedButton.styleFrom(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _green.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        icon: _isPaying
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.credit_card_rounded, size: 20),
        label: Text(
          _isPaying ? 'অনুগ্রহ করে অপেক্ষা করুন...' : 'এখনই পরিশোধ করুন',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

enum _CardState { loading, noDue, error, due }
