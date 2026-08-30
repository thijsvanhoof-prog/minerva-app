import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/app_user_context.dart';

TeamMembership _tm(
  int teamId,
  String role, {
  String? childName,
  String? childProfileId,
}) {
  return TeamMembership(
    teamId: teamId,
    role: role,
    teamName: 'Team $teamId',
    linkedChildDisplayName: childName,
    linkedChildProfileId: childProfileId,
  );
}

void main() {
  group('mergeTeamMembershipsByTeamId', () {
    test('trainer wint boven speler voor hetzelfde team', () {
      final merged = mergeTeamMembershipsByTeamId([
        _tm(1, 'player'),
        _tm(1, 'trainer'),
      ]);
      expect(merged.length, 1);
      expect(merged.single.teamId, 1);
      expect(merged.single.canManageTeam, isTrue);
    });

    test('volgorde van input verandert de uitkomst niet', () {
      final a = mergeTeamMembershipsByTeamId([
        _tm(1, 'player'),
        _tm(1, 'trainer'),
        _tm(2, 'player'),
      ]);
      final b = mergeTeamMembershipsByTeamId([
        _tm(2, 'player'),
        _tm(1, 'trainer'),
        _tm(1, 'player'),
      ]);
      final rolesA = {for (final m in a) m.teamId: m.role};
      final rolesB = {for (final m in b) m.teamId: m.role};
      expect(rolesA, rolesB);
    });
  });

  group('splitTeamMembershipsForTrainingTabs', () {
    test('alleen speler van B en E', () {
      final split = splitTeamMembershipsForTrainingTabs([
        _tm(2, 'player'),
        _tm(5, 'player'),
      ]);
      expect(split.playerTeams.map((m) => m.teamId).toList()..sort(), [2, 5]);
      expect(split.trainerTeams, isEmpty);
    });

    test('alleen trainer van A en D', () {
      final split = splitTeamMembershipsForTrainingTabs([
        _tm(1, 'trainer'),
        _tm(4, 'trainer'),
      ]);
      expect(split.trainerTeams.map((m) => m.teamId).toList()..sort(), [1, 4]);
      expect(split.playerTeams, isEmpty);
    });

    test('speler B/E plus trainer A/D', () {
      final split = splitTeamMembershipsForTrainingTabs([
        _tm(1, 'trainer'),
        _tm(2, 'player'),
        _tm(4, 'trainer'),
        _tm(5, 'player'),
      ]);
      expect(split.playerTeams.map((m) => m.teamId).toList()..sort(), [2, 5]);
      expect(split.trainerTeams.map((m) => m.teamId).toList()..sort(), [1, 4]);
    });

    test('trainer en speler voor hetzelfde team → alleen Trainers', () {
      final split = splitTeamMembershipsForTrainingTabs([
        _tm(1, 'player'),
        _tm(1, 'trainer'),
      ]);
      expect(split.trainerTeams.map((m) => m.teamId), [1]);
      expect(split.playerTeams, isEmpty);
    });

    test('coach wordt behandeld als trainer', () {
      final split = splitTeamMembershipsForTrainingTabs([_tm(1, 'coach')]);
      expect(split.trainerTeams.length, 1);
      expect(split.trainerTeams.single.canManageTeam, isTrue);
      expect(split.playerTeams, isEmpty);
    });

    test('trainingslid en guardian verschijnen onder Spelers', () {
      final split = splitTeamMembershipsForTrainingTabs([
        _tm(1, 'trainingslid'),
        _tm(2, 'guardian', childName: 'Kind'),
      ]);
      expect(split.playerTeams.length, 2);
      expect(split.trainerTeams, isEmpty);
    });

    test('trainer van A kan A beheren, spelersteam B niet', () {
      final split = splitTeamMembershipsForTrainingTabs([
        _tm(1, 'trainer'),
        _tm(2, 'player'),
      ]);
      expect(
        split.trainerTeams.singleWhere((m) => m.teamId == 1).canManageTeam,
        isTrue,
      );
      expect(
        split.playerTeams.singleWhere((m) => m.teamId == 2).canManageTeam,
        isFalse,
      );
    });
  });

  group('training tab empty state scenarios', () {
    test('alleen speler → spelersteams zichtbaar, trainer-melding onder Trainers', () {
      final split = splitTeamMembershipsForTrainingTabs([_tm(2, 'player')]);
      expect(split.playerTeams, isNotEmpty);
      expect(split.trainerTeams, isEmpty);
      expect(
        shouldShowTrainingRoleEmptyState(
          teamsForTab: split.playerTeams,
          isGlobalAdmin: false,
        ),
        isFalse,
      );
      expect(
        shouldShowTrainingRoleEmptyState(
          teamsForTab: split.trainerTeams,
          isGlobalAdmin: false,
        ),
        isTrue,
      );
      expect(
        trainingTabEmptyMessage(TrainingTabViewRole.trainer),
        'Je bent niet gekoppeld als trainer aan een team.',
      );
    });

    test('alleen trainer → trainersteams zichtbaar, speler-melding onder Spelers', () {
      final split = splitTeamMembershipsForTrainingTabs([_tm(1, 'trainer')]);
      expect(split.trainerTeams, isNotEmpty);
      expect(split.playerTeams, isEmpty);
      expect(
        shouldShowTrainingRoleEmptyState(
          teamsForTab: split.playerTeams,
          isGlobalAdmin: false,
        ),
        isTrue,
      );
      expect(
        shouldShowTrainingRoleEmptyState(
          teamsForTab: split.trainerTeams,
          isGlobalAdmin: false,
        ),
        isFalse,
      );
      expect(
        trainingTabEmptyMessage(TrainingTabViewRole.player),
        'Je bent niet gekoppeld als speler aan een team.',
      );
    });

    test('speler én trainer bij verschillende teams → beide subtabs gevuld', () {
      final split = splitTeamMembershipsForTrainingTabs([
        _tm(1, 'trainer'),
        _tm(2, 'player'),
      ]);
      expect(split.playerTeams, isNotEmpty);
      expect(split.trainerTeams, isNotEmpty);
      expect(
        shouldShowTrainingRoleEmptyState(
          teamsForTab: split.playerTeams,
          isGlobalAdmin: false,
        ),
        isFalse,
      );
      expect(
        shouldShowTrainingRoleEmptyState(
          teamsForTab: split.trainerTeams,
          isGlobalAdmin: false,
        ),
        isFalse,
      );
    });

    test('geen teamrollen → beide rolgerichte meldingen', () {
      final split = splitTeamMembershipsForTrainingTabs(const []);
      expect(split.playerTeams, isEmpty);
      expect(split.trainerTeams, isEmpty);
      expect(
        shouldShowTrainingRoleEmptyState(
          teamsForTab: split.playerTeams,
          isGlobalAdmin: false,
        ),
        isTrue,
      );
      expect(
        shouldShowTrainingRoleEmptyState(
          teamsForTab: split.trainerTeams,
          isGlobalAdmin: false,
        ),
        isTrue,
      );
    });

    test('global admin → geen lege rolmeldingen', () {
      expect(
        shouldShowTrainingRoleEmptyState(
          teamsForTab: const [],
          isGlobalAdmin: true,
        ),
        isFalse,
      );
      expect(
        shouldShowTrainingRoleEmptyState(
          teamsForTab: [_tm(1, 'player')],
          isGlobalAdmin: true,
        ),
        isFalse,
      );
    });
  });

  group('matchAccessTeamMemberships', () {
    test('alleen speler', () {
      final teams = matchAccessTeamMemberships([_tm(2, 'player'), _tm(5, 'player')]);
      expect(teams.map((m) => m.teamId).toList()..sort(), [2, 5]);
    });

    test('alleen trainer', () {
      final teams = matchAccessTeamMemberships([_tm(1, 'trainer'), _tm(4, 'trainer')]);
      expect(teams.map((m) => m.teamId).toList()..sort(), [1, 4]);
    });

    test('alleen coach', () {
      final teams = matchAccessTeamMemberships([_tm(1, 'coach')]);
      expect(teams.single.canManageTeam, isTrue);
    });

    test('speler en trainer bij verschillende teams', () {
      final teams = matchAccessTeamMemberships([
        _tm(1, 'trainer'),
        _tm(2, 'player'),
        _tm(4, 'trainer'),
        _tm(5, 'player'),
      ]);
      expect(teams.map((m) => m.teamId).toList()..sort(), [1, 2, 4, 5]);
    });

    test('speler en trainer bij hetzelfde team → team één keer', () {
      final teams = matchAccessTeamMemberships([
        _tm(1, 'player'),
        _tm(1, 'trainer'),
      ]);
      expect(teams.length, 1);
      expect(teams.single.teamId, 1);
      expect(teams.single.canManageTeam, isTrue);
    });

    test('alleen trainingslid → geen wedstrijdtoegang', () {
      expect(matchAccessTeamMemberships([_tm(1, 'trainingslid')]), isEmpty);
      expect(
        shouldShowMatchAccessEmptyState(matchTeams: const [], isGlobalAdmin: false),
        isTrue,
      );
    });

    test('alleen supporter → geen wedstrijdtoegang', () {
      expect(matchAccessTeamMemberships([_tm(1, 'supporter')]), isEmpty);
    });

    test('geen team → lege melding', () {
      expect(matchAccessTeamMemberships(const []), isEmpty);
      expect(matchAccessEmptyMessage,
          'Je bent niet gekoppeld als speler of trainer/coach aan een team.');
    });

    test('guardian met geselecteerd kind → wedstrijden van kindteam', () {
      final teams = matchAccessTeamMemberships(
        [
          _tm(2, 'guardian', childName: 'Kind', childProfileId: 'child-1'),
          _tm(3, 'guardian', childName: 'Ander', childProfileId: 'child-2'),
        ],
        viewingAsProfileId: 'child-1',
      );
      expect(teams.map((m) => m.teamId), [2]);
    });

    test('committee power admin zonder team → lege melding', () {
      expect(
        shouldShowMatchAccessEmptyState(
          matchTeams: matchAccessTeamMemberships(const []),
          isGlobalAdmin: false,
        ),
        isTrue,
      );
    });

    test('global admin → geen lege wedstrijdmelding', () {
      expect(
        shouldShowMatchAccessEmptyState(matchTeams: const [], isGlobalAdmin: true),
        isFalse,
      );
    });

    test('volgorde van memberships verandert uitkomst niet', () {
      final a = matchAccessTeamMemberships([
        _tm(1, 'player'),
        _tm(1, 'trainer'),
        _tm(2, 'player'),
      ]);
      final b = matchAccessTeamMemberships([
        _tm(2, 'player'),
        _tm(1, 'trainer'),
        _tm(1, 'player'),
      ]);
      final idsA = a.map((m) => m.teamId).toList()..sort();
      final idsB = b.map((m) => m.teamId).toList()..sort();
      expect(idsA, idsB);
    });
  });

  group('taskAccessTeamMemberships', () {
    test('speler en trainer/coach krijgen toegang', () {
      final teams = taskAccessTeamMemberships([
        _tm(1, 'player'),
        _tm(2, 'trainer'),
        _tm(3, 'coach'),
      ]);
      expect(teams.map((m) => m.teamId).toList()..sort(), [1, 2, 3]);
    });

    test('trainingslid en supporter → geen toegang', () {
      expect(taskAccessTeamMemberships([_tm(1, 'trainingslid')]), isEmpty);
      expect(taskAccessTeamMemberships([_tm(1, 'supporter')]), isEmpty);
    });

    test('geen koppeling → exacte lege melding', () {
      expect(taskAccessTeamMemberships(const []), isEmpty);
      expect(tasksEmptyMessage,
          'Je bent niet gekoppeld als speler of trainer/coach aan een team.');
    });

    test('gewone gebruiker zonder team → lege melding', () {
      expect(
        shouldShowTaskAccessEmptyState(
          taskTeams: const [],
          isGlobalAdmin: false,
          canViewAllTasks: false,
          isInScheidsrechtersTellers: false,
        ),
        isTrue,
      );
    });

    test('scheidsrechters/tellers zonder team → geen lege melding', () {
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

    test('scheidsrechters/tellers met team → geen lege melding', () {
      expect(
        shouldShowTaskAccessEmptyState(
          taskTeams: taskAccessTeamMemberships([_tm(1, 'player')]),
          isGlobalAdmin: false,
          canViewAllTasks: false,
          isInScheidsrechtersTellers: true,
        ),
        isFalse,
      );
    });

    test('wedstrijdzaken zonder team → overzicht, geen lege melding', () {
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

    test('bestuur zonder team → overzicht, geen lege melding', () {
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

    test('ouder/verzorger met geselecteerd kind → teamtaken kind', () {
      final childTeams = taskAccessTeamMemberships(
        [
          _tm(
            2,
            'guardian',
            childName: 'Kind',
            childProfileId: 'child-1',
          ),
        ],
        viewingAsProfileId: 'child-1',
      );
      expect(childTeams.map((m) => m.teamId).toList(), [2]);
      expect(
        shouldShowTaskAccessEmptyState(
          taskTeams: childTeams,
          isGlobalAdmin: false,
          canViewAllTasks: false,
          isInScheidsrechtersTellers: false,
        ),
        isFalse,
      );
    });

    test('trainingslid zonder andere rol → lege melding', () {
      expect(taskAccessTeamMemberships([_tm(1, 'trainingslid')]), isEmpty);
      expect(
        shouldShowTaskAccessEmptyState(
          taskTeams: taskAccessTeamMemberships([_tm(1, 'trainingslid')]),
          isGlobalAdmin: false,
          canViewAllTasks: false,
          isInScheidsrechtersTellers: false,
        ),
        isTrue,
      );
    });

    test('shouldShowTaskAccessEmptyState niet voor global admin', () {
      expect(
        shouldShowTaskAccessEmptyState(
          taskTeams: taskAccessTeamMemberships(const []),
          isGlobalAdmin: true,
          canViewAllTasks: false,
          isInScheidsrechtersTellers: false,
        ),
        isFalse,
      );
    });
  });
}
