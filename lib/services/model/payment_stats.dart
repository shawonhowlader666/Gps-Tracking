class PaymentStats {
  final double due;
  final double totalBilled;
  final double totalPaid;
  final int unpaidBillsCount;
  final bool enableBillAlert;

  PaymentStats({
    required this.due,
    required this.totalBilled,
    required this.totalPaid,
    required this.unpaidBillsCount,
    required this.enableBillAlert,
  });

  factory PaymentStats.fromJson(Map<String, dynamic> json) {
    return PaymentStats(
      due: (json['due'] as num).toDouble(),
      totalBilled: (json['total_billed'] as num).toDouble(),
      totalPaid: (json['total_paid'] as num).toDouble(),
      unpaidBillsCount: json['unpaid_bills_count'],
      enableBillAlert: json['enable_bill_alert'] as bool? ?? true,
    );
  }
}
