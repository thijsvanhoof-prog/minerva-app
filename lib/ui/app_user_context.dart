import 'package:flutter/material.dart';

import 'package:minerva_app/ui/committees/committee_normalization.dart';

/// Gekoppeld kind-profiel voor ouder-kind account.
class LinkedChild {
  final String profileId;
  final String displayName;

  const LinkedChild({required this.profileId, required this.displayName});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkedChild &&
          profileId == other.profileId &&
          displayName == other.displayName;

  @override
  int get hashCode => Object.hash(profileId, displayName);
}

/// State voor "Bekijk als kind": gekoppelde kinderen en actief gekozen kind.
class OuderKindNotifier extends ChangeNotifier {
  List<LinkedChild> linkedChildren = const [];
  String? viewingAsProfileId;
  String? viewingAsDisplayName;

  void setChildren(List<LinkedChild> children) {
    if (_listEquals(linkedChildren, children)) return;
    linkedChildren = children;
    // Als het gekozen kind niet meer in de lijst zit, reset
    if (viewingAsProfileId != null &&
        !children.any((c) => c.profileId == viewingAsProfileId)) {
      viewingAsProfileId = null;
      viewingAsDisplayName = null;
    }
    notifyListeners();
  }

  void setViewingAs(String? profileId, String? displayName) {
    if (viewingAsProfileId == profileId && viewingAsDisplayName == displayName) return;
    viewingAsProfileId = profileId;
    viewingAsDisplayName = displayName;
    notifyListeners();
  }

  void clearViewingAs() => setViewingAs(null, null);

  bool get isViewingAsChild => viewingAsProfileId != null;

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class TeamMembership {
  final int teamId;
  final String role;
  final String teamName;
  /// Nevobo-teamcode (HS1, DS1, …) indien bekend; gebruikt voor Standen/Wedstrijden.
  final String? nevoboCode;
  /// Bij guardian-rol: displaynaam van het gekoppelde kind (voor label "Team (kind)").
  final String? linkedChildDisplayName;
  /// Bij guardian-rol: profile_id van het gekoppelde kind.
  final String? linkedChildProfileId;

  const TeamMembership({
    required this.teamId,
    required this.role,
    required this.teamName,
    this.nevoboCode,
    this.linkedChildDisplayName,
    this.linkedChildProfileId,
  });

  /// Teamnaam voor weergave: "Team" of "Team (kindnaam)" bij gekoppeld kind.
  String get displayLabel =>
      linkedChildDisplayName != null && linkedChildDisplayName!.trim().isNotEmpty
          ? '$teamName (${linkedChildDisplayName!.trim()})'
          : teamName;

  bool get canManageTeam {
    final r = role.trim().toLowerCase();
    return r == 'trainer' || r == 'coach' || r == 'admin';
  }

  bool get isGuardian => role.trim().toLowerCase() == 'guardian';
}

/// Prioriteit bij samenvoegen van dubbele teamrollen voor hetzelfde team (hoger wint).
int teamMembershipRolePriority(String role) {
  switch (role.trim().toLowerCase()) {
    case 'admin':
      return 3;
    case 'trainer':
    case 'coach':
      return 2;
    case 'player':
    case 'speler':
    case 'lid':
      return 1;
    case 'guardian':
      return 1;
    case 'trainingslid':
      return 0;
    case 'supporter':
      return -1;
    default:
      return 0;
  }
}

/// Kiest de winnende membership bij conflicten voor hetzelfde [teamId].
TeamMembership pickHigherPriorityTeamMembership(
  TeamMembership a,
  TeamMembership b,
) {
  final pa = teamMembershipRolePriority(a.role);
  final pb = teamMembershipRolePriority(b.role);
  if (pa != pb) return pa > pb ? a : b;
  // Zelfde prioriteit: eigen rol boven guardian (deterministisch).
  if (a.isGuardian != b.isGuardian) return a.isGuardian ? b : a;
  return a;
}

/// Voegt memberships per [teamId] samen; trainer/coach wint boven speler-rollen.
List<TeamMembership> mergeTeamMembershipsByTeamId(
  List<TeamMembership> memberships,
) {
  final byTeam = <int, TeamMembership>{};
  for (final m in memberships) {
    final existing = byTeam[m.teamId];
    byTeam[m.teamId] =
        existing == null ? m : pickHigherPriorityTeamMembership(existing, m);
  }
  return byTeam.values.toList();
}

/// Resultaat van verdeling over Trainingen-subtabs Spelers en Trainers.
class TrainingTabTeamSplit {
  final List<TeamMembership> playerTeams;
  final List<TeamMembership> trainerTeams;

  const TrainingTabTeamSplit({
    required this.playerTeams,
    required this.trainerTeams,
  });
}

/// Verdeelt teams over Spelers- en Trainers-subtab; elk team komt maximaal in één lijst.
TrainingTabTeamSplit splitTeamMembershipsForTrainingTabs(
  List<TeamMembership> memberships,
) {
  final merged = mergeTeamMembershipsByTeamId(memberships);
  final playerTeams = <TeamMembership>[];
  final trainerTeams = <TeamMembership>[];
  for (final m in merged) {
    if (m.canManageTeam) {
      trainerTeams.add(m);
    } else {
      playerTeams.add(m);
    }
  }
  return TrainingTabTeamSplit(
    playerTeams: playerTeams,
    trainerTeams: trainerTeams,
  );
}

/// Spelers- of Trainers-subtab onder Teams → Trainingen.
enum TrainingTabViewRole { player, trainer }

/// Lege-staattekst per subtab (exacte copy).
String trainingTabEmptyMessage(TrainingTabViewRole role) {
  switch (role) {
    case TrainingTabViewRole.player:
      return 'Je bent niet gekoppeld als speler aan een team.';
    case TrainingTabViewRole.trainer:
      return 'Je bent niet gekoppeld als trainer aan een team.';
  }
}

/// Of de rolgerichte lege toestand getoond moet worden (niet voor global admin).
bool shouldShowTrainingRoleEmptyState({
  required List<TeamMembership> teamsForTab,
  required bool isGlobalAdmin,
}) {
  return !isGlobalAdmin && teamsForTab.isEmpty;
}

/// Lege-staattekst voor Teams → Wedstrijden zonder speler/trainer/coach-koppeling.
const String matchAccessEmptyMessage =
    'Je bent niet gekoppeld als speler of trainer/coach aan een team.';

/// Of een membership wedstrijdtoegang geeft (geen trainingslid/supporter).
bool teamMembershipGrantsMatchAccess(TeamMembership membership) {
  final r = membership.role.trim().toLowerCase();
  switch (r) {
    case 'trainingslid':
    case 'supporter':
      return false;
    case 'trainer':
    case 'coach':
    case 'admin':
    case 'guardian':
    case 'player':
    case 'speler':
    case 'lid':
      return true;
    default:
      return false;
  }
}

/// Teams waarvoor wedstrijden getoond mogen worden (samengevoegd, deterministisch).
List<TeamMembership> matchAccessTeamMemberships(
  List<TeamMembership> memberships, {
  String? viewingAsProfileId,
}) {
  final merged = mergeTeamMembershipsByTeamId(memberships);

  if (viewingAsProfileId != null) {
    return merged
        .where(
          (m) =>
              m.isGuardian &&
              m.linkedChildProfileId == viewingAsProfileId &&
              teamMembershipGrantsMatchAccess(m),
        )
        .toList();
  }

  return merged.where(teamMembershipGrantsMatchAccess).toList();
}

/// Of de wedstrijd-leegstaat getoond moet worden (niet voor global admin).
bool shouldShowMatchAccessEmptyState({
  required List<TeamMembership> matchTeams,
  required bool isGlobalAdmin,
}) {
  return !isGlobalAdmin && matchTeams.isEmpty;
}

/// Teams waarvoor teamtaken getoond mogen worden (zelfde rollen als wedstrijden).
List<TeamMembership> taskAccessTeamMemberships(
  List<TeamMembership> memberships, {
  String? viewingAsProfileId,
}) {
  return matchAccessTeamMemberships(
    memberships,
    viewingAsProfileId: viewingAsProfileId,
  );
}

/// Lege-staattekst voor Taken zonder speler/trainer/coach-koppeling.
const String tasksEmptyMessage = matchAccessEmptyMessage;

/// Of de Taken-leegstaat getoond moet worden (niet voor global admin).
bool shouldShowTaskAccessEmptyState({
  required List<TeamMembership> taskTeams,
  required bool isGlobalAdmin,
  required bool canViewAllTasks,
  required bool isInScheidsrechtersTellers,
}) {
  if (isGlobalAdmin || canViewAllTasks || isInScheidsrechtersTellers) {
    return false;
  }
  return taskTeams.isEmpty;
}

/// Standaard commissies in vaste volgorde (canonieke sleutels).
const standardCommitteeKeys = [
  'bestuur',
  'technische-commissie',
  'communicatie',
  'wedstrijdzaken',
  'evenementen',
  'jeugdcommissie',
  'scheidsrechters-tellers',
];

const commissiesEmptyMessage = 'Je bent niet gekoppeld aan een commissie.';

/// Unieke commissiesleutels op basis van [normalizeCommitteeKey].
List<String> dedupeNormalizedCommitteeKeys(Iterable<String> raw) {
  final seen = <String>{};
  final result = <String>[];
  for (final item in raw) {
    final key = normalizeCommitteeKey(item);
    if (key.isEmpty || key == 'admin') continue;
    if (seen.add(key)) result.add(key);
  }
  return result;
}

int committeeDisplayOrder(String key) {
  switch (normalizeCommitteeKey(key)) {
    case 'admin':
      return 0;
    case 'bestuur':
      return 1;
    case 'technische-commissie':
      return 2;
    case 'communicatie':
      return 3;
    case 'wedstrijdzaken':
      return 4;
    case 'evenementen':
      return 5;
    case 'jeugdcommissie':
      return 6;
    case 'scheidsrechters-tellers':
      return 7;
    default:
      return 8;
  }
}

void sortCommitteesForDisplay(List<String> committees) {
  committees.sort((a, b) {
    final orderA = committeeDisplayOrder(a);
    final orderB = committeeDisplayOrder(b);
    if (orderA != orderB) return orderA.compareTo(orderB);
    return a.compareTo(b);
  });
}

/// Commissies zichtbaar in het Commissies-tabblad.
List<String> visibleCommitteesForCommissiesTab({
  required List<String> userCommittees,
  required bool hasFullAdminRights,
  required bool isCommitteePowerAdmin,
  required bool isInBestuur,
  required bool canManageAccounts,
}) {
  final userKeys = dedupeNormalizedCommitteeKeys(userCommittees);

  final List<String> visible;
  if (hasFullAdminRights || isCommitteePowerAdmin || isInBestuur) {
    visible = List<String>.from(standardCommitteeKeys);
    for (final k in userKeys) {
      if (!visible.any((v) => normalizeCommitteeKey(v) == k)) {
        visible.add(k);
      }
    }
  } else {
    visible = List<String>.from(userKeys);
  }

  if (canManageAccounts &&
      !visible.any((c) => normalizeCommitteeKey(c) == 'admin')) {
    visible.add('admin');
  }

  sortCommitteesForDisplay(visible);
  return visible;
}

class AppUserContext extends InheritedWidget {
  /// Effectieve profile id (voor data: ouder of gekozen kind).
  final String profileId;
  final String email;
  final String displayName;
  final bool isGlobalAdmin;
  /// Alle commissierechten zonder Contact/teamzicht als global admin.
  final bool isCommitteePowerAdmin;
  final List<TeamMembership> memberships;
  final List<String> committees;

  /// Allows pages to request a full user-context reload (memberships/committees/names).
  /// Useful after TC/admin changes (team link) without requiring app restart.
  final Future<void> Function()? reloadUserContext;

  /// Ouder-kind: id van de ingelogde user (ouder).
  final String loggedInProfileId;
  /// Ouder-kind: als je "als kind" kijkt, de kind-profile-id en -naam.
  final String? viewingAsProfileId;
  final String? viewingAsDisplayName;
  final List<LinkedChild> linkedChildProfiles;
  final OuderKindNotifier? ouderKindNotifier;

  const AppUserContext({
    super.key,
    required this.profileId,
    required this.email,
    required this.displayName,
    required this.isGlobalAdmin,
    this.isCommitteePowerAdmin = false,
    required this.memberships,
    required this.committees,
    this.reloadUserContext,
    required this.loggedInProfileId,
    this.viewingAsProfileId,
    this.viewingAsDisplayName,
    this.linkedChildProfiles = const [],
    this.ouderKindNotifier,
    required super.child,
  });

  /// True als de gebruiker nu "als kind" kijkt.
  bool get isViewingAsChild => viewingAsProfileId != null;

  /// Ouder/verzorger-rol: je hebt minimaal één gekoppeld account.
  bool get isOuderVerzorger => linkedChildProfiles.isNotEmpty;

  /// Voor aanwezigheid beheren: als je een gekoppeld account geselecteerd hebt,
  /// voer acties uit voor dat profiel; anders voor je eigen account.
  String get attendanceProfileId => (viewingAsProfileId ?? loggedInProfileId);

  bool get hasFullAdminRights => isGlobalAdmin;

  bool isInCommittee(String name) {
    final needle = normalizeCommitteeKey(name);
    return committees.any((c) => normalizeCommitteeKey(c) == needle);
  }

  bool get isInBestuur => isInCommittee('bestuur');
  bool get isInTechnischeCommissie =>
      isInCommittee('technische-commissie') || isInCommittee('tc');
  bool get isInCommunicatie => isInCommittee('communicatie');
  bool get isInWedstrijdzaken => isInCommittee('wedstrijdzaken');
  bool get isInEvenementen => isInCommittee('evenementen');
  bool get isInJeugdcommissie => isInCommittee('jeugdcommissie');
  bool get isInScheidsrechtersTellers => isInCommittee('scheidsrechters-tellers');
  bool get isInVrijwilligers => isInCommittee('vrijwilligers');

  /// Central place for feature permissions (can be reused across the app).
  /// Nieuws/agenda beheren: admin, bestuur en communicatie (sluit aan bij RLS).
  bool get canManageAgenda =>
      hasFullAdminRights ||
      isCommitteePowerAdmin ||
      isInBestuur ||
      isInCommunicatie ||
      isInJeugdcommissie ||
      isInEvenementen;
  bool get canViewAgendaRsvps =>
      hasFullAdminRights ||
      isCommitteePowerAdmin ||
      isInBestuur ||
      isInCommunicatie ||
      isInJeugdcommissie ||
      isInEvenementen;

  /// Alleen bestuur en communicatie (en global admin) mogen aanmeldingen exporteren.
  bool get canExportAgendaRsvps =>
      hasFullAdminRights ||
      isCommitteePowerAdmin ||
      isInBestuur ||
      isInCommunicatie;

  bool get canManageNews =>
      hasFullAdminRights || isCommitteePowerAdmin || isInBestuur || isInCommunicatie;
  bool get canManageHighlights =>
      hasFullAdminRights || isCommitteePowerAdmin || isInBestuur || isInCommunicatie;
  bool get canManageTeams => hasFullAdminRights || isInTechnischeCommissie;
  bool get canManageMatches =>
      hasFullAdminRights || isCommitteePowerAdmin || isInWedstrijdzaken;

  /// Bestuur-tab: bestuursleden en admins mogen bewerken.
  bool get canManageBestuur =>
      hasFullAdminRights || isCommitteePowerAdmin || isInBestuur;

  /// TC-tab teambeheer: alleen global admin of echte TC (niet committee power admin).
  bool get canManageTc => hasFullAdminRights || isInTechnischeCommissie;

  // Tasks
  bool get canViewAllTasks =>
      hasFullAdminRights ||
      isCommitteePowerAdmin ||
      isInBestuur ||
      isInWedstrijdzaken;
  bool get canManageTasks =>
      hasFullAdminRights || isCommitteePowerAdmin || isInWedstrijdzaken;

  /// Weergave van alle accounts (gebruikersnamen, team toevoegen): bestuur, TC en admins.
  bool get canViewAllAccounts =>
      hasFullAdminRights ||
      isCommitteePowerAdmin ||
      isInBestuur ||
      isInTechnischeCommissie;

  /// Gebruikersnamen wijzigen en accounts verwijderen (global admin of committee power admin).
  bool get canManageAccounts => hasFullAdminRights || isCommitteePowerAdmin;

  static AppUserContext of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<AppUserContext>();
    if (result == null) {
      throw FlutterError(
        'AppUserContext.of() called but no AppUserContext found.\n'
        'Did you forget to wrap your widget tree?',
      );
    }
    return result;
  }

  @override
  bool updateShouldNotify(AppUserContext oldWidget) {
    return profileId != oldWidget.profileId ||
        email != oldWidget.email ||
        displayName != oldWidget.displayName ||
        isGlobalAdmin != oldWidget.isGlobalAdmin ||
        isCommitteePowerAdmin != oldWidget.isCommitteePowerAdmin ||
        memberships != oldWidget.memberships ||
        committees != oldWidget.committees ||
        reloadUserContext != oldWidget.reloadUserContext ||
        loggedInProfileId != oldWidget.loggedInProfileId ||
        viewingAsProfileId != oldWidget.viewingAsProfileId ||
        viewingAsDisplayName != oldWidget.viewingAsDisplayName ||
        linkedChildProfiles != oldWidget.linkedChildProfiles;
  }
}