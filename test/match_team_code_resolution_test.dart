import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/match_team_code_resolution.dart';

TeamMembership _tm(
  int teamId,
  String role, {
  String teamName = '',
  String? nevoboCode,
}) {
  return TeamMembership(
    teamId: teamId,
    role: role,
    teamName: teamName.isEmpty ? 'Team $teamId' : teamName,
    nevoboCode: nevoboCode,
  );
}

void main() {
  group('resolveMatchWedstrijdenViewState', () {
    test('geen geschikte koppeling → niet-gekoppeldmelding', () {
      expect(
        resolveMatchWedstrijdenViewState(
          matchTeams: const [],
          resolvedCodes: const [],
          isGlobalAdmin: false,
        ),
        MatchWedstrijdenViewState.notLinked,
      );
    });

    test('global admin zonder codes → geen foutieve niet-gekoppeldmelding', () {
      expect(
        resolveMatchWedstrijdenViewState(
          matchTeams: const [],
          resolvedCodes: const [],
          isGlobalAdmin: true,
        ),
        MatchWedstrijdenViewState.adminNoValidCodes,
      );
    });

    test('spelerteam zonder Nevobo-code → code-ontbreektmelding', () {
      final matchTeams = [_tm(2, 'player')];
      final resolution = resolveMatchTeamCodes(
        matchTeams: matchTeams,
        codeByTeamId: const {},
      );
      expect(resolution.codes, isEmpty);
      expect(
        resolveMatchWedstrijdenViewState(
          matchTeams: matchTeams,
          resolvedCodes: resolution.codes,
          isGlobalAdmin: false,
        ),
        MatchWedstrijdenViewState.missingTeamCode,
      );
    });

    test('trainerteam zonder Nevobo-code → code-ontbreektmelding', () {
      final matchTeams = [_tm(1, 'trainer')];
      final resolution = resolveMatchTeamCodes(
        matchTeams: matchTeams,
        codeByTeamId: const {},
      );
      expect(
        resolveMatchWedstrijdenViewState(
          matchTeams: matchTeams,
          resolvedCodes: resolution.codes,
          isGlobalAdmin: false,
        ),
        MatchWedstrijdenViewState.missingTeamCode,
      );
    });

    test('meerdere gekoppelde teams zonder code → meervoudstekst', () {
      expect(
        matchTeamCodeMissingHeadline(2),
        'Je bent gekoppeld aan teams, maar voor deze teams is geen Nevobo-code ingesteld.',
      );
      expect(
        matchTeamCodeMissingHeadline(1),
        'Je bent gekoppeld aan een team, maar voor dit team is geen Nevobo-code ingesteld.',
      );
    });

    test('minimaal één team met geldige code → wedstrijdpagina', () {
      final matchTeams = [
        _tm(1, 'player', nevoboCode: null),
        _tm(2, 'trainer', nevoboCode: 'DS1'),
      ];
      final resolution = resolveMatchTeamCodes(
        matchTeams: matchTeams,
        codeByTeamId: const {},
      );
      expect(resolution.codes, ['DS1']);
      expect(
        resolveMatchWedstrijdenViewState(
          matchTeams: matchTeams,
          resolvedCodes: resolution.codes,
          isGlobalAdmin: false,
        ),
        MatchWedstrijdenViewState.showMatches,
      );
    });

    test('geldige code via codeByTeamId', () {
      final matchTeams = [_tm(5, 'player')];
      final resolution = resolveMatchTeamCodes(
        matchTeams: matchTeams,
        codeByTeamId: {5: 'HS1'},
      );
      expect(resolution.codes, ['HS1']);
      expect(resolution.teamsWithoutCode, isEmpty);
    });

    test('geldige code zonder komende wedstrijden → showMatches (UI in NevoboWedstrijdenTab)', () {
      expect(
        resolveMatchWedstrijdenViewState(
          matchTeams: [_tm(1, 'player')],
          resolvedCodes: ['DS1'],
          isGlobalAdmin: false,
        ),
        MatchWedstrijdenViewState.showMatches,
      );
    });
  });

  group('resolveMatchTeamCodes', () {
    test('fallback naar nevoboCode op membership', () {
      final resolution = resolveMatchTeamCodes(
        matchTeams: [_tm(3, 'player', nevoboCode: 'MB1')],
        codeByTeamId: const {},
      );
      expect(resolution.codes, ['MB1']);
    });

    test('fallback naar code in teamnaam', () {
      final resolution = resolveMatchTeamCodes(
        matchTeams: [_tm(4, 'player', teamName: 'Heren 2')],
        codeByTeamId: const {},
      );
      expect(resolution.codes, ['HS2']);
    });
  });
}
