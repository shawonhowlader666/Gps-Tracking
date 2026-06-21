import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:crypto/crypto.dart';

void main() {
  const String baseUrl = 'https://bgd.tracksolidpro.com/route/rest';
  const String appKey = '8FB345B8693CCD00C6CEB12895C150CF339A22A4105B6558';
  const String appSecret = '3928b55300604564b98344c92f5d6a2b';
  const String altSecret = '63e31f9c80c5f4334c93ffd46c0de59d';

  String fmtUtc() {
    final now = DateTime.now().toUtc();
    return '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')} '
        '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}';
  }

  Future<void> runTestVariant({
    required String label,
    required Map<String, String> baseParams,
    required String secretToUse,
    required String algo,
    required bool sendAsJson,
  }) async {
    final sortedKeys = baseParams.keys.toList()..sort();
    String signStr = '';
    String sign = '';

    if (algo == 'md5_both') {
      final buf = StringBuffer(secretToUse);
      for (final k in sortedKeys) {
        buf.write(k);
        buf.write(baseParams[k]);
      }
      buf.write(secretToUse);
      signStr = buf.toString();
      sign = md5.convert(utf8.encode(signStr)).toString().toUpperCase();
    } else if (algo == 'md5_query_both') {
      final parts = sortedKeys.map((k) => '$k=${baseParams[k]}').join('&');
      signStr = '$secretToUse$parts$secretToUse';
      sign = md5.convert(utf8.encode(signStr)).toString().toUpperCase();
    }

    final body = Map<String, String>.from(baseParams)..['sign'] = sign;

    try {
      final resp = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': sendAsJson ? 'application/json' : 'application/x-www-form-urlencoded',
        },
        body: sendAsJson ? json.encode(body) : body,
      ).timeout(const Duration(seconds: 10));
      final r = json.decode(resp.body);
      if (r['code'] != 1001) {
        print('*** SUCCESS! [$label | json: $sendAsJson] code=${r['code']} msg=${r['message']} (sign: $sign)');
      } else {
        // print('[$label | json: $sendAsJson] code=${r['code']} msg=${r['message']}');
      }
    } catch (e) {
      // print('[$label | json: $sendAsJson] Error: $e');
    }
  }

  test('JSON vs Form encoding signature tests', () async {
    final ts = fmtUtc();

    final secrets = {
      'appSecretLower': appSecret,
      'altSecretLower': altSecret,
    };

    final algos = ['md5_both', 'md5_query_both'];

    for (final secEntry in secrets.entries) {
      for (final algo in algos) {
        final baseParams = {
          'method': 'jimi.oauth.token.get',
          'app_key': appKey,
          'timestamp': ts,
          'sign_method': 'md5',
          'v': '1.0',
          'format': 'json',
          'user_id': 'dummy_user_123',
          'user_pwd_md5': 'dummy_pwd_123',
        };

        // Test as JSON
        await runTestVariant(
          label: '${secEntry.key} | $algo',
          baseParams: baseParams,
          secretToUse: secEntry.value,
          algo: algo,
          sendAsJson: true,
        );

        // Test as Form
        await runTestVariant(
          label: '${secEntry.key} | $algo',
          baseParams: baseParams,
          secretToUse: secEntry.value,
          algo: algo,
          sendAsJson: false,
        );
      }
    }
    print('Encoding tests completed.');
  });
}
