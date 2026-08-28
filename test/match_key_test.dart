import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/match_key.dart';

void main() {
  final start = DateTime.utc(2026, 9, 12, 12, 30);

  MatchKeyTarget local({
    String team = 'JC1',
    DateTime? at,
    String? key,
  }) {
    final s = at ?? start;
    return MatchKeyTarget(
      matchKey: key ?? nevoboMatchKey(teamCode: team, start: s),
      teamCode: team,
      start: s,
    );
  }

  group('nevoboMatchKey', () {
    test('canonicalizes to second precision and MR instead of XR', () {
      final withMicros = DateTime.utc(2026, 9, 12, 12, 30, 0, 123, 456);
      expect(
        nevoboMatchKey(teamCode: 'xr1', start: withMicros),
        'nevobo_match:MR1:2026-09-12T12:30:00.000Z',
      );
    });
  });

  group('resolveLocalMatchKey', () {
    test('matches exact stored key', () {
      final m = local();
      expect(
        resolveLocalMatchKey(matches: [m], rowKey: m.matchKey),
        m.matchKey,
      );
    });

    test('matches ISO without milliseconds', () {
      final m = local();
      expect(
        resolveLocalMatchKey(
          matches: [m],
          rowKey: 'nevobo_match:JC1:2026-09-12T12:30:00Z',
        ),
        m.matchKey,
      );
    });

    test('matches XR alias in stored key', () {
      final m = local(team: 'MR1');
      expect(
        resolveLocalMatchKey(
          matches: [m],
          rowKey: 'nevobo_match:XR1:2026-09-12T12:30:00.000Z',
        ),
        m.matchKey,
      );
    });

    test('matches via team_code + starts_at when key format drifted', () {
      final m = local();
      expect(
        resolveLocalMatchKey(
          matches: [m],
          rowKey: 'nevobo_match:JC1:2026-09-12T14:30:00.000Z',
          teamCode: 'JC1',
          startsAt: '2026-09-12T12:30:00+00:00',
        ),
        m.matchKey,
      );
    });

    test('returns null when team and time do not match', () {
      final m = local();
      expect(
        resolveLocalMatchKey(
          matches: [m],
          rowKey: 'nevobo_match:HS1:2026-09-12T12:30:00.000Z',
        ),
        isNull,
      );
    });
  });
}
