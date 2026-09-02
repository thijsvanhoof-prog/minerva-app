import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/shell_navigation.dart';

TeamMembership _tm(
  int teamId,
  String role, {
  String? childProfileId,
}) {
  return TeamMembership(
    teamId: teamId,
    role: role,
    teamName: 'Team $teamId',
    linkedChildProfileId: childProfileId,
  );
}

void main() {
  group('rolmatrix navigatie', () {
    test('gastaccount → 3 tabs', () {
      expect(shellTabIdsForUser(isGuest: true).length, 3);
    });

    test('eigen account → 6 tabs', () {
      expect(shellTabIdsForUser(isGuest: false).length, 6);
    });
  });

  group('rolmatrix teams/trainingen/wedstrijden/taken', () {
    test('1 speler één team', () {
      final m = [_tm(1, 'player')];
      expect(splitTeamMembershipsForTrainingTabs(m).playerTeams.length, 1);
      expect(matchAccessTeamMemberships(m).length, 1);
      expect(taskAccessTeamMemberships(m).length, 1);
    });

    test('speler meerdere teams', () {
      final m = [_tm(1, 'player'), _tm(2, 'player')];
      expect(splitTeamMembershipsForTrainingTabs(m).playerTeams.length, 2);
    });

    test('trainingslid geen wedstrijd/taken', () {
      final m = [_tm(1, 'trainingslid')];
      expect(matchAccessTeamMemberships(m), isEmpty);
      expect(taskAccessTeamMemberships(m), isEmpty);
      expect(
        shouldShowTaskAccessEmptyState(
          taskTeams: taskAccessTeamMemberships(m),
          isGlobalAdmin: false,
          canViewAllTasks: false,
          isInScheidsrechtersTellers: false,
        ),
        isTrue,
      );
    });

    test('supporter geen wedstrijd/taken', () {
      final m = [_tm(1, 'supporter')];
      expect(matchAccessTeamMemberships(m), isEmpty);
      expect(taskAccessTeamMemberships(m), isEmpty);
    });

    test('trainer één team', () {
      final m = [_tm(1, 'trainer')];
      expect(splitTeamMembershipsForTrainingTabs(m).trainerTeams.length, 1);
      expect(splitTeamMembershipsForTrainingTabs(m).playerTeams, isEmpty);
    });

    test('coach wordt trainer', () {
      final m = [_tm(1, 'coach')];
      expect(splitTeamMembershipsForTrainingTabs(m).trainerTeams.length, 1);
    });

    test('trainer meerdere teams', () {
      final m = [_tm(1, 'trainer'), _tm(2, 'trainer')];
      expect(splitTeamMembershipsForTrainingTabs(m).trainerTeams.length, 2);
    });

    test('speler en trainer verschillende teams', () {
      final m = [_tm(1, 'player'), _tm(2, 'trainer')];
      final split = splitTeamMembershipsForTrainingTabs(m);
      expect(split.playerTeams.map((t) => t.teamId), [1]);
      expect(split.trainerTeams.map((t) => t.teamId), [2]);
    });

    test('speler en trainerzelfde team → alleen trainers', () {
      final m = [_tm(1, 'player'), _tm(1, 'trainer')];
      final split = splitTeamMembershipsForTrainingTabs(m);
      expect(split.playerTeams, isEmpty);
      expect(split.trainerTeams.length, 1);
    });

    test('dubbele rollen andere volgorde → zelfde uitkomst', () {
      final a = mergeTeamMembershipsByTeamId([_tm(1, 'player'), _tm(1, 'trainer')]);
      final b = mergeTeamMembershipsByTeamId([_tm(1, 'trainer'), _tm(1, 'player')]);
      expect(a.single.canManageTeam, isTrue);
      expect(b.single.canManageTeam, isTrue);
    });

    test('ouder één kind geselecteerd', () {
      final m = [
        _tm(2, 'guardian', childProfileId: 'child-1'),
      ];
      expect(
        matchAccessTeamMemberships(m, viewingAsProfileId: 'child-1').length,
        1,
      );
      expect(
        taskAccessTeamMemberships(m, viewingAsProfileId: 'child-1').length,
        1,
      );
    });

    test('ouder twee kinderen verschillende teams', () {
      final m = [
        _tm(2, 'guardian', childProfileId: 'child-1'),
        _tm(5, 'guardian', childProfileId: 'child-2'),
      ];
      expect(
        matchAccessTeamMemberships(m, viewingAsProfileId: 'child-1')
            .map((t) => t.teamId),
        [2],
      );
      expect(
        matchAccessTeamMemberships(m, viewingAsProfileId: 'child-2')
            .map((t) => t.teamId),
        [5],
      );
    });

    test('ouder zelf speler én guardian', () {
      final m = [
        _tm(1, 'player'),
        _tm(2, 'guardian', childProfileId: 'child-1'),
      ];
      expect(matchAccessTeamMemberships(m).map((t) => t.teamId).toList()..sort(), [1, 2]);
    });

    test('ouder zelf trainer en guardian kind in ander team', () {
      final m = [
        _tm(1, 'trainer'),
        _tm(2, 'guardian', childProfileId: 'child-1'),
      ];
      expect(splitTeamMembershipsForTrainingTabs(m).trainerTeams.length, 1);
    });
  });

  group('rolmatrix commissies', () {
    test('geen commissie', () {
      expect(
        visibleCommitteesForCommissiesTab(
          userCommittees: const [],
          hasFullAdminRights: false,
          isCommitteePowerAdmin: false,
          isInBestuur: false,
          canManageAccounts: false,
        ),
        isEmpty,
      );
    });

    test('alleen communicatie', () {
      expect(
        visibleCommitteesForCommissiesTab(
          userCommittees: const ['communicatie'],
          hasFullAdminRights: false,
          isCommitteePowerAdmin: false,
          isInBestuur: false,
          canManageAccounts: false,
        ),
        ['communicatie'],
      );
    });

    test('communicatie + evenementen', () {
      expect(
        visibleCommitteesForCommissiesTab(
          userCommittees: const ['communicatie', 'evenementen'],
          hasFullAdminRights: false,
          isCommitteePowerAdmin: false,
          isInBestuur: false,
          canManageAccounts: false,
        ),
        ['communicatie', 'evenementen'],
      );
    });

    test('commissielid en speler cumuleren aparte domeinen', () {
      final committees = visibleCommitteesForCommissiesTab(
        userCommittees: const ['wedstrijdzaken'],
        hasFullAdminRights: false,
        isCommitteePowerAdmin: false,
        isInBestuur: false,
        canManageAccounts: false,
      );
      final teams = taskAccessTeamMemberships([_tm(1, 'player')]);
      expect(committees, ['wedstrijdzaken']);
      expect(teams.length, 1);
    });

    test('power admin zonder committee_members', () {
      expect(
        dedupeNormalizedCommitteeKeys(const []),
        isEmpty,
      );
      expect(
        visibleCommitteesForCommissiesTab(
          userCommittees: const [],
          hasFullAdminRights: false,
          isCommitteePowerAdmin: true,
          isInBestuur: false,
          canManageAccounts: true,
        ).contains('admin'),
        isTrue,
      );
    });
  });

  group('rolmatrix taken', () {
    test('S/T zonder team geen lege melding', () {
      expect(
        shouldShowTaskAccessEmptyState(
          taskTeams: const [],
          isGlobalAdmin: false,
          canViewAllTasks: false,
          isInScheidsrechtersTellers: true,
        ),
        isFalse,
      );
    });

    test('WZ zonder team wel overzicht', () {
      expect(
        shouldShowTaskAccessEmptyState(
          taskTeams: const [],
          isGlobalAdmin: false,
          canViewAllTasks: true,
          isInScheidsrechtersTellers: false,
        ),
        isFalse,
      );
    });
  });
}
