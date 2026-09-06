/// Canonieke rollen voor wedstrijdtaken (fluiten, tellen, 2de scheidsrechter).
const kMatchTaskRoleFluiten = 'fluiten';
const kMatchTaskRoleTellen = 'tellen';
const kMatchTaskRoleTweedeScheidsrechter = 'tweede_scheidsrechter';

const kMatchTaskRoles = [
  kMatchTaskRoleFluiten,
  kMatchTaskRoleTweedeScheidsrechter,
  kMatchTaskRoleTellen,
];

const kMatchTaskColumnFluiten = 'fluiten_task_id';
const kMatchTaskColumnTellen = 'tellen_task_id';
const kMatchTaskColumnTweedeScheidsrechter = 'tweede_scheidsrechter_task_id';

const kNevoboHomeMatchesTaskSelectColumns =
    'match_key, team_code, starts_at, summary, location, linked_team_id, fluiten_task_id, tellen_task_id, tweede_scheidsrechter_task_id';

const kNevoboHomeMatchesLinkSelectColumns =
    'match_key, linked_team_id, fluiten_task_id, tellen_task_id, tweede_scheidsrechter_task_id';

const kNevoboHomeMatchesTaskIdSelectColumns =
    'fluiten_task_id, tellen_task_id, tweede_scheidsrechter_task_id';

const kNevoboHomeMatchesTaskKeySelectColumns =
    'match_key, fluiten_task_id, tellen_task_id, tweede_scheidsrechter_task_id';

/// Fallback tijdens DB-migratie (kolom nog niet live).
const kNevoboHomeMatchesTaskSelectColumnsLegacy =
    'match_key, team_code, starts_at, summary, location, linked_team_id, fluiten_task_id, tellen_task_id';

const kNevoboHomeMatchesLinkSelectColumnsLegacy =
    'match_key, linked_team_id, fluiten_task_id, tellen_task_id';

const kNevoboHomeMatchesTaskIdSelectColumnsLegacy =
    'fluiten_task_id, tellen_task_id';

const kNevoboHomeMatchesTaskKeySelectColumnsLegacy =
    'match_key, fluiten_task_id, tellen_task_id';

/// Wedstrijden tot 4 uur na start blijven zichtbaar (lopende wedstrijd).
const kHomeMatchActiveGracePeriod = Duration(hours: 4);

DateTime homeMatchActiveCutoffUtc({DateTime? now}) {
  return (now ?? DateTime.now()).toUtc().subtract(kHomeMatchActiveGracePeriod);
}

/// Of een thuiswedstrijd nog actueel is (toekomstig of recent gestart).
bool isHomeMatchStillActive(DateTime startsAt, {DateTime? now}) {
  return !startsAt.toUtc().isBefore(homeMatchActiveCutoffUtc(now: now));
}

bool isHomeMatchRowStillActive(Map<String, dynamic> row, {DateTime? now}) {
  final startsAt = DateTime.tryParse((row['starts_at'] ?? '').toString());
  if (startsAt == null) return false;
  return isHomeMatchStillActive(startsAt, now: now);
}

/// Profiel-id voor opslaan van een taakaanmelding.
String matchTaskSignupProfileId({
  required bool openScheidsrechtersTellersSignup,
  required String loggedInProfileId,
  required String attendanceProfileId,
}) {
  if (openScheidsrechtersTellersSignup) return loggedInProfileId;
  return attendanceProfileId;
}

/// Of een wedstrijd zichtbaar is voor open S/T-inschrijving (minstens één taak-id).
bool hasAnyMatchTaskId({
  int? fluitenTaskId,
  int? tellenTaskId,
  int? tweedeScheidsrechterTaskId,
}) {
  return fluitenTaskId != null ||
      tellenTaskId != null ||
      tweedeScheidsrechterTaskId != null;
}

/// Teamkoppeling is verplicht voor gewone teamleden, niet voor S/T.
bool shouldSkipMatchWithoutTeamLink({
  required bool openScheidsrechtersTellersSignup,
  required int? linkedTeamId,
}) {
  if (openScheidsrechtersTellersSignup) return false;
  return linkedTeamId == null;
}

Set<int> assignableTaskIdsForUser({
  required bool openScheidsrechtersTellersSignup,
  required Set<int> allTaskIdsInMatches,
  required Set<int> teamAssignedTaskIds,
}) {
  if (openScheidsrechtersTellersSignup) return allTaskIdsInMatches;
  return teamAssignedTaskIds;
}

bool isMatchVisibleForUser({
  required bool openScheidsrechtersTellersSignup,
  required int? fluitenTaskId,
  required int? tellenTaskId,
  required int? tweedeScheidsrechterTaskId,
  required Set<int> assignableTaskIds,
}) {
  if (!hasAnyMatchTaskId(
    fluitenTaskId: fluitenTaskId,
    tellenTaskId: tellenTaskId,
    tweedeScheidsrechterTaskId: tweedeScheidsrechterTaskId,
  )) {
    return false;
  }
  if (openScheidsrechtersTellersSignup) return true;
  return isMatchTaskAssignable(
        taskId: fluitenTaskId,
        assignableTaskIds: assignableTaskIds,
      ) ||
      isMatchTaskAssignable(
        taskId: tellenTaskId,
        assignableTaskIds: assignableTaskIds,
      ) ||
      isMatchTaskAssignable(
        taskId: tweedeScheidsrechterTaskId,
        assignableTaskIds: assignableTaskIds,
      );
}

bool isMatchTaskAssignable({
  required int? taskId,
  required Set<int> assignableTaskIds,
}) {
  return taskId != null && assignableTaskIds.contains(taskId);
}

/// Open aanmelding in S/T-overzicht: alleen bij stOverviewMode én echt S/T-lidmaatschap.
bool allowOpenSignupInStOverview({
  required bool stOverviewMode,
  required bool isInScheidsrechtersTellers,
}) {
  return stOverviewMode && isInScheidsrechtersTellers;
}

String matchTaskIdColumnForRole(String role) {
  switch (role) {
    case kMatchTaskRoleFluiten:
      return kMatchTaskColumnFluiten;
    case kMatchTaskRoleTellen:
      return kMatchTaskColumnTellen;
    case kMatchTaskRoleTweedeScheidsrechter:
      return kMatchTaskColumnTweedeScheidsrechter;
    default:
      return '${role.trim().toLowerCase()}_task_id';
  }
}

String matchTaskDisplayLabel(String role) {
  switch (role) {
    case kMatchTaskRoleFluiten:
      return 'Fluiten';
    case kMatchTaskRoleTellen:
      return 'Tellen';
    case kMatchTaskRoleTweedeScheidsrechter:
      return '2de scheids';
    default:
      return role;
  }
}

String matchTaskTitlePrefix(String role) => matchTaskDisplayLabel(role);

int? taskIdFromLinkRow(Map<String, dynamic>? row, String role) {
  if (row == null) return null;
  return (row[matchTaskIdColumnForRole(role)] as num?)?.toInt();
}

Map<String, int> taskIdsByRoleFromLinkRow(Map<String, dynamic>? row) {
  if (row == null) return const {};
  final out = <String, int>{};
  for (final role in kMatchTaskRoles) {
    final id = taskIdFromLinkRow(row, role);
    if (id != null) out[role] = id;
  }
  return out;
}

Map<String, int> taskIdsByRoleFromRows(Iterable<Map<String, dynamic>> rows) {
  final out = <String, int>{};
  for (final row in rows) {
    final type = (row['type'] ?? '').toString().trim().toLowerCase();
    final id = (row['task_id'] as num?)?.toInt();
    if (id != null && type.isNotEmpty) out[type] = id;
  }
  return out;
}

String matchTaskPushBody({required Set<String> linkedRoles}) {
  if (linkedRoles.length > 1) {
    return 'Er zijn wedstrijdtaken gekoppeld aan jouw team.';
  }
  if (linkedRoles.contains(kMatchTaskRoleFluiten)) {
    return 'Fluiten is gekoppeld aan jouw team.';
  }
  if (linkedRoles.contains(kMatchTaskRoleTellen)) {
    return 'Tellen is gekoppeld aan jouw team.';
  }
  if (linkedRoles.contains(kMatchTaskRoleTweedeScheidsrechter)) {
    return '2de scheidsrechter is gekoppeld aan jouw team.';
  }
  return 'Er is een wedstrijdtaak gekoppeld aan jouw team.';
}

String matchTaskPushDedupeKey({
  required String matchKey,
  required int teamId,
  required Set<String> linkedRoles,
}) {
  final kinds = kMatchTaskRoles.where(linkedRoles.contains).join('+');
  return 'match-task:$matchKey:$teamId:$kinds';
}

bool isMissingTweedeScheidsrechterColumn(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('tweede_scheidsrechter_task_id') ||
      (msg.contains('column') && msg.contains('tweede_scheidsrechter'));
}
