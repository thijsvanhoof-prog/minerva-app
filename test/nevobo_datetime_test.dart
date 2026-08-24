import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_api.dart';

void main() {
  group('NevoboApi.parseMatchDateTime', () {
    test('parses competition API tijdstip with offset as local wall time', () {
      final dt = NevoboApi.parseMatchDateTime('2026-09-12T14:30:00+02:00');
      expect(dt, isNotNull);
      expect(dt!.toUtc(), DateTime.utc(2026, 9, 12, 12, 30));
    });

    test('parses ICS DTSTART with Z suffix as UTC instant', () {
      final dt = NevoboApi.parseMatchDateTime('2026-09-12T12:30:00Z');
      expect(dt, isNotNull);
      expect(dt!.toUtc(), DateTime.utc(2026, 9, 12, 12, 30));
    });

    test('parses naive datetime as Netherlands local time (CEST)', () {
      final dt = NevoboApi.parseMatchDateTime('2026-09-12T14:30:00');
      expect(dt, isNotNull);
      expect(dt!.toUtc(), DateTime.utc(2026, 9, 12, 12, 30));
    });

    test('parses naive datetime as Netherlands local time (CET)', () {
      final dt = NevoboApi.parseMatchDateTime('2026-12-12T13:00:00');
      expect(dt, isNotNull);
      expect(dt!.toUtc(), DateTime.utc(2026, 12, 12, 12, 0));
    });
  });
}
