class BillingVehicle {
  final int id;
  final String? name;
  final String imei;
  final String? simNumber;
  final String? expirationDate;
  final bool isActive;
  final double? monthlyBill;

  BillingVehicle({
    required this.id,
    this.name,
    required this.imei,
    this.simNumber,
    this.expirationDate,
    required this.isActive,
    this.monthlyBill,
  });

  factory BillingVehicle.fromJson(Map<String, dynamic> json) {
    final imeiStr = json['imei'].toString();
    double? parsedBill;
    if (json['monthly_bill'] != null) {
      parsedBill = double.tryParse(json['monthly_bill'].toString());
    } else if (json['monthly_bill_amount'] != null) {
      parsedBill = double.tryParse(json['monthly_bill_amount'].toString());
    }

    String? expDate = json['expiration_date']?.toString();

    return BillingVehicle(
      id: json['id'],
      name: json['name'],
      imei: imeiStr,
      simNumber: json['sim_number']?.toString(),
      expirationDate: expDate,
      isActive: json['is_active'] == true || json['is_active'] == 1 || json['status'] == 'Active',
      monthlyBill: parsedBill,
    );
  }
}
