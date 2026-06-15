import 'package:flutter_test/flutter_test.dart';
import 'package:gpspro/services/payment_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  test('Test PaymentService endpoints in detail', () async {
    SharedPreferences.setMockInitialValues({
      'email': 'user1@example.com',
      'password': '123456',
    });
    
    final prefs = await SharedPreferences.getInstance();
    UserRepository.prefs = prefs;

    final loggedIn = await PaymentService.login();
    print("Login status: $loggedIn");

    // We can use the payment service header helper if we make a dummy helper or get it.
    // Let's call them using PaymentService's ensureLoggedIn and custom requests in testEndpoints or similar.
    await PaymentService.testEndpoints();

    // Or we do custom gets using a helper in the test to check /api/me and /api/payments
    // Let's implement custom gets here
    final token = await _getToken();
    print("Token: $token");

    final bills = await PaymentService.getBills();
    print("--------------------------------------------------");
    print("BILLS RETRIEVED: ${bills?.length}");
    if (bills != null) {
      for (final b in bills) {
        print("Bill: ID=${b.id}, Month=${b.billingMonth}, Amount=${b.amount}, Status=${b.status}, Payments=${b.payments.length}");
      }
    }
    
    final stats = await PaymentService.getStats();
    print("--------------------------------------------------");
    print("STATS RETRIEVED: due=${stats?.due}, billed=${stats?.totalBilled}, paid=${stats?.totalPaid}, unpaidCount=${stats?.unpaidBillsCount}");
    print("--------------------------------------------------");

    expect(bills, isNotNull);
    expect(bills!.length, equals(4)); // we know user1 has 4 bills (May 100, May 200, June 100, June 200)
    expect(stats, isNotNull);

    double expectedDue = 0.0;
    int expectedUnpaidCount = 0;
    for (final b in bills!) {
      if (b.status.toLowerCase() != 'paid') {
        double paidForBill = 0.0;
        for (final p in b.payments) {
          paidForBill += p.amount;
        }
        expectedDue += (b.amount - paidForBill);
        expectedUnpaidCount++;
      }
    }
    expect(stats!.due, equals(expectedDue));
    expect(stats.unpaidBillsCount, equals(expectedUnpaidCount));
  });
}

Future<String?> _getToken() async {
  final response = await http.post(
    Uri.parse("http://167.86.78.162:8000/api/auth/login"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({
      "login": "user1@example.com",
      "password": "123456",
      "device_name": "mobile_app"
    }),
  );
  if (response.statusCode == 200) {
    return jsonDecode(response.body)['token'];
  }
  return null;
}






