import 'package:flutter_test/flutter_test.dart';
import 'package:smart_lock/services/model/event.dart';

void main() {
  group('Event Model Tests', () {
    test('Should clean ignition off/stop message to Engine Off', () {
      final event1 = Event(message: 'Ignition off');
      final event2 = Event(message: 'Engine stop detected');
      expect(event1.message, 'Engine Off');
      expect(event2.message, 'Engine Off');
    });

    test('Should clean ignition on message to Engine On', () {
      final event = Event(message: 'Ignition on');
      expect(event.message, 'Engine On');
    });

    test('Should clean power cut message to Power Disconnect', () {
      final event = Event(message: 'Main power cut alarm');
      expect(event.message, 'Power Disconnect');
    });

    test('Should keep other messages as is', () {
      final event = Event(message: 'Over speed alert: 80 km/h');
      expect(event.message, 'Over speed alert: 80 km/h');
    });
  });
}
