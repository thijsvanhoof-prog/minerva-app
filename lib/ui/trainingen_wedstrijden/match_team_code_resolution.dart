import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_api.dart';

/// Resultaat van het oplossen van Nevobo-teamcodes voor wedstrijdtoegang.
class MatchTeamCodeResolution {
  final List<String> codes;
  final List<TeamMembership> teamsWithoutCode;

  const MatchTeamCodeResolution({
    required this.codes,
    required this.teamsWithoutCode,
  });
}

/// Bepaalt per gekoppeld team de Nevobo-code (DB → membership → teamnaam).
MatchTeamCodeResolution resolveMatchTeamCodes({
  required List<TeamMembership> matchTeams,
  required Map<int, String> codeByTeamId,
}) {
  final codes = <String>{};
  final teamsWithoutCode = <TeamMembership>[];

  for (final m in matchTeams) {
    final fromDb = codeByTeamId[m.teamId]?.trim().toUpperCase();
    final fromMembership = m.nevoboCode?.trim().toUpperCase();
    final fromName = NevoboApi.extractCodeFromTeamName(m.teamName)?.trim().toUpperCase();

    String? code;
    for (final candidate in [fromDb, fromMembership, fromName]) {
      if (candidate != null && candidate.isNotEmpty) {
        code = candidate;
        break;
      }
    }

    if (code != null) {
      codes.add(code);
    } else {
      teamsWithoutCode.add(m);
    }
  }

  final sortedCodes = codes.toList()..sort(NevoboApi.compareTeamCodes);
  return MatchTeamCodeResolution(
    codes: sortedCodes,
    teamsWithoutCode: teamsWithoutCode,
  );
}

enum MatchWedstrijdenViewState {
  showMatches,
  notLinked,
  missingTeamCode,
  adminNoValidCodes,
}

MatchWedstrijdenViewState resolveMatchWedstrijdenViewState({
  required List<TeamMembership> matchTeams,
  required List<String> resolvedCodes,
  required bool isGlobalAdmin,
}) {
  if (isGlobalAdmin) {
    return resolvedCodes.isEmpty
        ? MatchWedstrijdenViewState.adminNoValidCodes
        : MatchWedstrijdenViewState.showMatches;
  }
  if (matchTeams.isEmpty) {
    return MatchWedstrijdenViewState.notLinked;
  }
  if (resolvedCodes.isEmpty) {
    return MatchWedstrijdenViewState.missingTeamCode;
  }
  return MatchWedstrijdenViewState.showMatches;
}

String matchTeamCodeMissingHeadline(int teamCount) {
  if (teamCount == 1) {
    return 'Je bent gekoppeld aan een team, maar voor dit team is geen Nevobo-code ingesteld.';
  }
  return 'Je bent gekoppeld aan teams, maar voor deze teams is geen Nevobo-code ingesteld.';
}

const String matchTeamCodeMissingTcHint =
    'Vraag de Technische Commissie om de Nevobo-code van het team te controleren.';

const String matchAdminNoValidCodesMessage =
    'Er zijn geen teams met een geldige Nevobo-code gevonden.';
