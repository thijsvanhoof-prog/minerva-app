import 'package:flutter/material.dart';

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

  const TeamMembership({
    required this.teamId,
    required this.role,
    required this.teamName,
    this.nevoboCode,
    this.linkedChildDisplayName,
  });

  /// Teamnaam voor weergave: "Team" of "Team (kindnaam)" bij gekoppeld kind.
  String get displayLabel =>
      linkedChildDisplayName != null && linkedChildDisplayName!.trim().isNotEmpty
          ? '$teamName (${linkedChildDisplayName!.trim()})'
          : teamName;

  bool get canManageTeam {
    final r = role.trim().toLowerCase();
    return r == 'trainer' || r == 'coach';
  }

  bool get isGuardian => role.trim().toLowerCase() == 'guardian';
}

class AppUserContext extends InheritedWidget {
  /// Effectieve profile id (voor data: ouder of gekozen kind).
  final String profileId;
  final String email;
  final String displayName;
  final bool isGlobalAdmin;
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

  String _normalizeCommitteeKey(String value) {
    final c = value.trim().toLowerCase();
    if (c.isEmpty) return '';
    if (c == 'bestuur') return 'bestuur';
    if (c == 'tc' || c.contains('technische')) return 'technische-commissie';
    if (c == 'cc' || c.contains('communicatie')) return 'communicatie';
    if (c == 'wz' || c.contains('wedstrijd')) return 'wedstrijdzaken';
    if (c.contains('evenement')) return 'evenementen';
    if (c == 'jeugd' || c.contains('jeugdcommissie')) return 'jeugdcommissie';
    if ((c.contains('scheidsrechter') && c.contains('teller')) ||
        c.contains('scheidsrechters-tellers')) {
      return 'scheidsrechters-tellers';
    }
    if (c.contains('vrijwilliger')) return 'vrijwilligers';
    return c;
  }

  bool isInCommittee(String name) {
    final needle = _normalizeCommitteeKey(name);
    return committees.any((c) => _normalizeCommitteeKey(c) == needle);
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
  /// Bestuur: alles inzien (view), alleen admins mogen aanpassen (manage).
  bool get canManageAgenda =>
      hasFullAdminRights || isInCommunicatie;
  bool get canViewAgendaRsvps =>
      hasFullAdminRights ||
      isInBestuur ||
      isInCommunicatie ||
      isInJeugdcommissie ||
      isInEvenementen;

  /// Alleen bestuur en communicatie (en global admin) mogen aanmeldingen exporteren.
  bool get canExportAgendaRsvps =>
      hasFullAdminRights || isInBestuur || isInCommunicatie;

  bool get canManageNews =>
      hasFullAdminRights || isInCommunicatie;
  bool get canManageHighlights =>
      hasFullAdminRights || isInCommunicatie;
  bool get canManageTeams => hasFullAdminRights || isInTechnischeCommissie;
  bool get canManageMatches => hasFullAdminRights || isInWedstrijdzaken;

  /// Bestuur-tab: bestuursleden en admins mogen bewerken.
  bool get canManageBestuur => hasFullAdminRights || isInBestuur;

  /// TC-tab: alleen admins en TC mogen bewerken; Bestuur mag alleen kijken.
  bool get canManageTc => hasFullAdminRights || isInTechnischeCommissie;

  // Tasks
  bool get canViewAllTasks => hasFullAdminRights || isInBestuur || isInWedstrijdzaken;
  bool get canManageTasks => hasFullAdminRights || isInWedstrijdzaken;

  /// Weergave van alle accounts (gebruikersnamen, team toevoegen): bestuur, TC en admins.
  bool get canViewAllAccounts =>
      hasFullAdminRights || isInBestuur || isInTechnischeCommissie;

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
        memberships != oldWidget.memberships ||
        committees != oldWidget.committees ||
        reloadUserContext != oldWidget.reloadUserContext ||
        loggedInProfileId != oldWidget.loggedInProfileId ||
        viewingAsProfileId != oldWidget.viewingAsProfileId ||
        viewingAsDisplayName != oldWidget.viewingAsDisplayName ||
        linkedChildProfiles != oldWidget.linkedChildProfiles;
  }
}