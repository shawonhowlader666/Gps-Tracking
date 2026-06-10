import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../storage/user_repository.dart';


class ManualPaymentScreen extends StatefulWidget {
  final double dueAmount;

  // ✅ After 10th হলে back করলে popup আবার দেখাবে
  final bool isAfter10th;

  const ManualPaymentScreen({
    super.key,
    required this.dueAmount,
    this.isAfter10th = false,
  });

  @override
  State<ManualPaymentScreen> createState() => _ManualPaymentScreenState();
}

class _ManualPaymentScreenState extends State<ManualPaymentScreen>
    with SingleTickerProviderStateMixin {
  // ── Colors ──────────────────────────────────────────────────────────────────
  static const Color _bg      = Color(0xFFF4F6FB);
  static const Color _accent  = Color(0xFF980E04);

  static const Color _bkashColor  = Color(0xFFE2136E);
  static const Color _nagadColor  = Color(0xFFF26522);
  static const Color _rocketColor = Color(0xFF8B1FA8);

  // ── State ────────────────────────────────────────────────────────────────────
  _PayMethod? _selected;
  final _amountController = TextEditingController();
  final _senderController = TextEditingController();
  final _txnController    = TextEditingController();

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  final GlobalKey _receiptKey = GlobalKey();

  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.dueAmount.toStringAsFixed(0);

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _amountController.dispose();
    _senderController.dispose();
    _txnController.dispose();
    super.dispose();
  }

  // ── Payment methods ──────────────────────────────────────────────────────────
  List<_PayMethod> get _methods => [
    _PayMethod(
      id: 'bkash',
      label: 'bKash',
      number: PHONE_NO,
      color: _bkashColor,
      instruction: 'bKash অ্যাপ খুলুন → Send Money → নম্বর দিন → Amount → PIN',
      imagePath: 'assets/icons/bkash.png',
    ),
    _PayMethod(
      id: 'nagad',
      label: 'Nagad',
      number: PHONE_NO,
      color: _nagadColor,
      instruction: 'Nagad অ্যাপ খুলুন → Send Money → নম্বর দিন → Amount → PIN',
      imagePath: 'assets/icons/nogod.png',
    ),
    _PayMethod(
      id: 'rocket',
      label: 'Rocket',
      number: PHONE_NO,
      color: _rocketColor,
      instruction: 'Dial *322# → Send Money → নম্বর দিন → Amount → PIN',
      imagePath: 'assets/icons/rocket.png',
    ),
  ];

  // ── Back handler ─────────────────────────────────────────────────────────────
  // ✅ Back করলে simply pop — কোনো result পাঠাবে না
  // showPaymentDuePopupIfNeeded এর loop তখন আবার popup দেখাবে (after 10th হলে)
  void _handleBack() {
    Navigator.of(context).pop();
  }

  // ── Screenshot + WhatsApp ────────────────────────────────────────────────────
  Future<void> _captureAndShare() async {
    if (_selected == null) {
      _showSnack('পেমেন্ট পদ্ধতি বেছে নিন', isError: true);
      return;
    }
    if (_amountController.text.trim().isEmpty) {
      _showSnack('Amount লিখুন', isError: true);
      return;
    }
    if (_senderController.text.trim().isEmpty) {
      _showSnack('আপনার মোবাইল নম্বর লিখুন', isError: true);
      return;
    }
    if (_txnController.text.trim().isEmpty) {
      _showSnack('Transaction ID লিখুন', isError: true);
      return;
    }

    setState(() => _isSending = true);

    try {
      final boundary = _receiptKey.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Cannot capture receipt');

      final image    = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode image');

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/payment_receipt.png');
      await file.writeAsBytes(pngBytes);

      final String whatsapp = WHATS_APP;
      if (whatsapp.isEmpty) {
        _showSnack('Admin WhatsApp নম্বর সেট করা নেই', isError: true);
        setState(() => _isSending = false);
        return;
      }

      final adminNumber = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
      final userEmail   = UserRepository.getEmail() ?? 'N/A';
      final msg         = Uri.encodeComponent(
        '🧾 *Manual Payment Notification*\n\n'
            '👤 User: $userEmail\n'
            '💳 Method: ${_selected!.label}\n'
            '📱 Sender No: ${_senderController.text.trim()}\n'
            '💰 Amount: BDT ${_amountController.text.trim()}৳\n'
            '🔖 TxnID: ${_txnController.text.trim()}\n'
            '📅 Date: ${_formatNow()}\n\n'
            '📎 Screenshot attached above.\n'
            '_Please confirm payment._',
      );

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Manual Payment Receipt - BDT ${_amountController.text.trim()}৳ via ${_selected!.label}',
        subject: 'Payment Receipt',
      );

      await Future.delayed(const Duration(milliseconds: 800));
      final waUri = Uri.parse('https://wa.me/$adminNumber?text=$msg');
      if (await canLaunchUrl(waUri)) {
        await launchUrl(waUri, mode: LaunchMode.externalApplication);

        // ✅ WhatsApp এ send সফল → 'payment_done' দিয়ে screen বন্ধ করো
        // এতে loop এ result == 'payment_done' হবে → loop break → popup আর আসবে না
        if (mounted) {
          Navigator.of(context).pop('payment_done');
        }
      } else {
        _showSnack('WhatsApp পাওয়া যায়নি, install করুন।', isError: true);
      }
    } catch (e) {
      debugPrint('Share error: $e');
      _showSnack('Share করতে সমস্যা হয়েছে: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _formatNow() {
    final n = DateTime.now();
    return '${n.day.toString().padLeft(2, '0')}/'
        '${n.month.toString().padLeft(2, '0')}/'
        '${n.year}  '
        '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}';
  }

  void _copyNumber() {
    if (_selected == null) return;
    Clipboard.setData(ClipboardData(text: _selected!.number));
    _showSnack('${_selected!.label} নম্বর কপি হয়েছে!');
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(14),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // আমরা manually handle করি
      onPopInvoked: (didPop) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          title: const Text('Manual Payment',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: _handleBack,
          ),
          // ✅ After 10th: AppBar এ warning badge দেখাবে
          bottom: widget.isAfter10th
              ? PreferredSize(
            preferredSize: const Size.fromHeight(28),
            child: Container(
              width: double.infinity,
              color: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: const Text(
                '⚠️  পেমেন্ট না করলে ফিরে গেলে আবার সতর্কতা দেখাবে',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
              : null,
        ),
        body: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DueBanner(amount: widget.dueAmount),
                const SizedBox(height: 20),

                _StepHeader(step: '1', label: 'পেমেন্ট পদ্ধতি বেছে নিন'),
                const SizedBox(height: 12),
                ..._methods.map((m) => _MethodTile(
                  method: m,
                  isSelected: _selected?.id == m.id,
                  onTap: () => setState(() => _selected = m),
                )),

                if (_selected != null) ...[
                  const SizedBox(height: 20),
                  _StepHeader(step: '2', label: 'টাকা পাঠান'),
                  const SizedBox(height: 12),
                  _InstructionCard(method: _selected!, onCopy: _copyNumber),
                ],

                const SizedBox(height: 20),
                _StepHeader(
                    step: _selected != null ? '3' : '2',
                    label: 'পেমেন্টের তথ্য দিন'),
                const SizedBox(height: 12),

                _InputField(
                  controller: _amountController,
                  label: 'পরিমাণ (BDT)',
                  hint: 'যেমন: 500',
                  icon: Icons.currency_exchange,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 12),

                _InputField(
                  controller: _senderController,
                  label: 'আপনার ${_selected?.label ?? 'মোবাইল'} নম্বর',
                  hint: '01XXXXXXXXX',
                  icon: Icons.phone_android,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))
                  ],
                ),
                const SizedBox(height: 12),

                _InputField(
                  controller: _txnController,
                  label: 'Transaction ID',
                  hint: 'যেমন: 8G7K2F3D1A',
                  icon: Icons.receipt_long,
                  keyboardType: TextInputType.text,
                ),

                const SizedBox(height: 24),
                _StepHeader(
                    step: _selected != null ? '4' : '3',
                    label: 'রসিদ প্রিভিউ'),
                const SizedBox(height: 12),
                _ReceiptCard(
                  repaintKey: _receiptKey,
                  method: _selected,
                  amount: _amountController.text,
                  sender: _senderController.text,
                  txnId: _txnController.text,
                  dateStr: _formatNow(),
                  userEmail: UserRepository.getEmail() ?? '',
                ),

                const SizedBox(height: 24),
                _SendButton(isSending: _isSending, onTap: _captureAndShare),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────

class _PayMethod {
  final String id;
  final String label;
  final String number;
  final Color  color;
  final String instruction;
  final String imagePath;

  const _PayMethod({
    required this.id,
    required this.label,
    required this.number,
    required this.color,
    required this.instruction,
    required this.imagePath,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// UI COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

class _DueBanner extends StatelessWidget {
  final double amount;
  const _DueBanner({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3E6FB8), Color(0xFF5C8ACF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3E6FB8).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.account_balance_wallet,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('মোট বকেয়া',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                'BDT ${amount.toStringAsFixed(0)}৳',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final String step;
  final String label;
  const _StepHeader({required this.step, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFF3E6FB8),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(step,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A2340))),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  final _PayMethod method;
  final bool isSelected;
  final VoidCallback onTap;
  const _MethodTile(
      {required this.method, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? method.color.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? method.color : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: method.color.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(8),
              child: ClipOval(
                child: Image.asset(
                  method.imagePath,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.account_balance_wallet,
                    color: method.color,
                    size: 28,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? method.color
                          : const Color(0xFF1A2340),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    method.number,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? method.color : Colors.transparent,
                border: Border.all(
                  color: isSelected ? method.color : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  final _PayMethod method;
  final VoidCallback onCopy;
  const _InstructionCard({required this.method, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: method.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: method.color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: method.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(6),
                child: Image.asset(
                  method.imagePath,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.account_balance_wallet,
                    color: method.color,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${method.label} এ পাঠান',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: method.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('নম্বর',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Text(
                      method.number,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: method.color,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onCopy,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: method.color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, color: Colors.white, size: 14),
                      SizedBox(width: 6),
                      Text('Copy',
                          style: TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: method.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  method.instruction,
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A2340))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(fontSize: 15, color: Color(0xFF1A2340)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
            TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon:
            Icon(icon, color: const Color(0xFF3E6FB8), size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: Color(0xFF3E6FB8), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  final GlobalKey repaintKey;
  final _PayMethod? method;
  final String amount;
  final String sender;
  final String txnId;
  final String dateStr;
  final String userEmail;

  const _ReceiptCard({
    required this.repaintKey,
    required this.method,
    required this.amount,
    required this.sender,
    required this.txnId,
    required this.dateStr,
    required this.userEmail,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = method?.color ?? const Color(0xFF3E6FB8);

    return RepaintBoundary(
      key: repaintKey,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  vertical: 18, horizontal: 20),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18)),
              ),
              child: Column(
                children: [
                  if (method != null)
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Image.asset(
                        method!.imagePath,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.receipt_long,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    )
                  else
                    const Icon(Icons.receipt_long,
                        color: Colors.white, size: 32),
                  const SizedBox(height: 8),
                  const Text('Payment Receipt',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(dateStr,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _row('User', userEmail.isNotEmpty ? userEmail : '—'),
                  _divider(),
                  _row('Method', method?.label ?? '—'),
                  _divider(),
                  _row('Send Money To', method?.number ?? '—'),
                  _divider(),
                  _row('Sender Number', sender.isNotEmpty ? sender : '—'),
                  _divider(),
                  _row(
                    'Transaction ID',
                    txnId.isNotEmpty ? txnId : '—',
                    valueStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF1A2340)),
                  ),
                  _divider(),
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: accent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Amount Paid',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        Text(
                          'BDT ${amount.isNotEmpty ? amount : '0'}৳',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pending_outlined,
                            color: Colors.orange.shade700, size: 16),
                        const SizedBox(width: 6),
                        Text('Pending Admin Confirmation',
                            style: TextStyle(
                                color: Colors.orange.shade800,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(18)),
                border: Border(
                    top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Text(
                'SmartLock BD • smartlockbd.com',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {TextStyle? valueStyle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500)),
          ),
          Expanded(
            child: Text(
              value,
              style: valueStyle ??
                  const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A2340)),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.grey.shade100);
}

class _SendButton extends StatelessWidget {
  final bool isSending;
  final VoidCallback onTap;
  const _SendButton({required this.isSending, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isSending ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSending
              ? const Color(0xFF25D366).withValues(alpha: 0.6)
              : const Color(0xFF25D366),
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSending
              ? []
              : [
            BoxShadow(
              color: Colors.black45.withValues(alpha: 0.4),
              blurRadius: 2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSending)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
            else
              const Icon(Icons.send_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Text(
              isSending ? 'Sharing...' : 'Screenshot & Send to WhatsApp',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}