class Bill {
  final int id;
  final String billingMonth;
  final int vehicleCount;
  final double amount;
  final String status;
  final List<BillPayment> payments;

  Bill({
    required this.id,
    required this.billingMonth,
    required this.vehicleCount,
    required this.amount,
    required this.status,
    required this.payments,
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    var list = json['payments'] as List? ?? [];
    List<BillPayment> paymentList = list.map((i) => BillPayment.fromJson(i)).toList();

    return Bill(
      id: json['id'],
      billingMonth: json['billing_month'],
      vehicleCount: json['vehicle_count'],
      amount: (json['amount'] as num).toDouble(),
      status: json['status'],
      payments: paymentList,
    );
  }
}

class BillPayment {
  final int id;
  final int? billId;
  final double amount;
  final String paidAt;
  final String? method;
  final String? note;

  BillPayment({
    required this.id,
    this.billId,
    required this.amount,
    required this.paidAt,
    this.method,
    this.note,
  });

  factory BillPayment.fromJson(Map<String, dynamic> json) {
    return BillPayment(
      id: json['id'],
      billId: json['bill_id'],
      amount: (json['amount'] as num).toDouble(),
      paidAt: json['paid_at'],
      method: json['method'],
      note: json['note'],
    );
  }
}
