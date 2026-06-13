import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GPRS Lock/Unlock Command Title Mapping Test', () {
    final List<dynamic> list = [
      {"id": 1, "title": "Unlock Vehicle", "type": "custom_unlock_type"},
      {"id": 2, "title": "Lock Car", "type": "custom_lock_type"},
      {"id": 3, "title": "Engine Status Check", "type": "engine_check"},
    ];

    String? lockCommandType;
    String? unlockCommandType;

    for (var element in list) {
      if (element is Map) {
        final title = (element["title"] ?? "").toString().toLowerCase();
        final type = (element["type"] ?? "").toString();
        if (title.contains("unlock")) {
          unlockCommandType = type;
        } else if (title.contains("lock")) {
          lockCommandType = type;
        }
      }
    }

    expect(unlockCommandType, equals("custom_unlock_type"));
    expect(lockCommandType, equals("custom_lock_type"));
  });

  test('Regex Parameter Extraction Test (Quoted vs Unquoted)', () {
    String? getRawParameter(String key, String other) {
      final jsonMatch = RegExp('["\']?$key["\']?\\s*:\\s*(true|false|"[^"]*"|\'[^\']*\'|\\d+\\.?\\d*)', caseSensitive: false).firstMatch(other);
      if (jsonMatch != null && jsonMatch.group(1) != null) {
        return jsonMatch.group(1)!.replaceAll('"', '').replaceAll("'", '');
      }
      return null;
    }

    // Test cases
    expect(getRawParameter('blocked', '{"blocked":false}'), equals('false'));
    expect(getRawParameter('blocked', '{"blocked":true}'), equals('true'));
    expect(getRawParameter('blocked', '{blocked:false}'), equals('false'));
    expect(getRawParameter('blocked', '{blocked:true}'), equals('true'));
    expect(getRawParameter('blocked', '{blocked: "true"}'), equals('true'));
    expect(getRawParameter('blocked', "{'blocked': 'false'}"), equals('false'));
    expect(getRawParameter('blocked', '{blocked: 1}'), equals('1'));
  });

  test('SOS Command Formatting Test', () {
    final List<Map<String, String>> protocols = [
      {'format': 'sos,A,{phone}#'},
      {'format': '101#{phone}#'},
      {'format': 'admin123456 {phone}'},
      {'format': 'SOS,1,{phone}#'},
      {'format': '{phone}'},
    ];

    String formatCommand(int selectedIndex, String phone) {
      final format = protocols[selectedIndex]['format']!;
      return phone.isEmpty ? '' : format.replaceAll('{phone}', phone);
    }

    final testPhone = '01712345678';
    expect(formatCommand(0, testPhone), equals('sos,A,01712345678#'));
    expect(formatCommand(1, testPhone), equals('101#01712345678#'));
    expect(formatCommand(2, testPhone), equals('admin123456 01712345678'));
    expect(formatCommand(3, testPhone), equals('SOS,1,01712345678#'));
    expect(formatCommand(4, testPhone), equals('01712345678'));
    expect(formatCommand(0, ''), equals(''));
  });
}
