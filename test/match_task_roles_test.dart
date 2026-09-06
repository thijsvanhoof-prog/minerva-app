import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/match_task_roles.dart';

void main() {
  group('match task roles', () {
    test('recognizes three independent task types from link row', () {
      final row = {
        'fluiten_task_id': 11,
        'tellen_task_id': 22,
        'tweede_scheidsrechter_task_id': 33,
      };

      expect(taskIdFromLinkRow(row, kMatchTaskRoleFluiten), 11);
      expect(taskIdFromLinkRow(row, kMatchTaskRoleTellen), 22);
      expect(taskIdFromLinkRow(row, kMatchTaskRoleTweedeScheidsrechter), 33);
      expect(taskIdsByRoleFromLinkRow(row), {
        kMatchTaskRoleFluiten: 11,
        kMatchTaskRoleTellen: 22,
        kMatchTaskRoleTweedeScheidsrechter: 33,
      });
    });

    test(
      'legacy link row without tweede scheidsrechter column still works',
      () {
        final row = {'fluiten_task_id': 11, 'tellen_task_id': 22};

        expect(taskIdsByRoleFromLinkRow(row), {
          kMatchTaskRoleFluiten: 11,
          kMatchTaskRoleTellen: 22,
        });
        expect(
          taskIdFromLinkRow(row, kMatchTaskRoleTweedeScheidsrechter),
          isNull,
        );
      },
    );

    test('taskIdsByRoleFromRows maps club_tasks rows by type', () {
      final rows = [
        {'task_id': 1, 'type': 'fluiten'},
        {'task_id': 2, 'type': 'tellen'},
        {'task_id': 3, 'type': 'tweede_scheidsrechter'},
      ];

      expect(taskIdsByRoleFromRows(rows), {
        kMatchTaskRoleFluiten: 1,
        kMatchTaskRoleTellen: 2,
        kMatchTaskRoleTweedeScheidsrechter: 3,
      });
    });

    test('display labels use exact UI text for 2de scheids', () {
      expect(matchTaskDisplayLabel(kMatchTaskRoleFluiten), 'Fluiten');
      expect(matchTaskDisplayLabel(kMatchTaskRoleTellen), 'Tellen');
      expect(
        matchTaskDisplayLabel(kMatchTaskRoleTweedeScheidsrechter),
        '2de scheids',
      );
    });

    test(
      'push body is role-specific for single link and general for multiple',
      () {
        expect(
          matchTaskPushBody(linkedRoles: {kMatchTaskRoleTweedeScheidsrechter}),
          '2de scheidsrechter is gekoppeld aan jouw team.',
        );
        expect(
          matchTaskPushBody(linkedRoles: {kMatchTaskRoleFluiten}),
          'Fluiten is gekoppeld aan jouw team.',
        );
        expect(
          matchTaskPushBody(linkedRoles: {kMatchTaskRoleTellen}),
          'Tellen is gekoppeld aan jouw team.',
        );
        expect(
          matchTaskPushBody(
            linkedRoles: {
              kMatchTaskRoleFluiten,
              kMatchTaskRoleTweedeScheidsrechter,
            },
          ),
          'Er zijn wedstrijdtaken gekoppeld aan jouw team.',
        );
      },
    );

    test('push dedupe key includes tweede_scheidsrechter', () {
      expect(
        matchTaskPushDedupeKey(
          matchKey: 'nevobo_match:HS1:2026-01-01',
          teamId: 7,
          linkedRoles: {kMatchTaskRoleTweedeScheidsrechter},
        ),
        'match-task:nevobo_match:HS1:2026-01-01:7:tweede_scheidsrechter',
      );
      expect(
        matchTaskPushDedupeKey(
          matchKey: 'k',
          teamId: 1,
          linkedRoles: {
            kMatchTaskRoleFluiten,
            kMatchTaskRoleTellen,
            kMatchTaskRoleTweedeScheidsrechter,
          },
        ),
        'match-task:k:1:fluiten+tweede_scheidsrechter+tellen',
      );
    });

    test('detects missing tweede scheidsrechter column errors', () {
      expect(
        isMissingTweedeScheidsrechterColumn(
          Exception('column tweede_scheidsrechter_task_id does not exist'),
        ),
        isTrue,
      );
      expect(
        isMissingTweedeScheidsrechterColumn(
          Exception('column fluiten_task_id does not exist'),
        ),
        isFalse,
      );
    });

    test('matchTaskIdColumnForRole returns stable column names', () {
      expect(
        matchTaskIdColumnForRole(kMatchTaskRoleFluiten),
        'fluiten_task_id',
      );
      expect(matchTaskIdColumnForRole(kMatchTaskRoleTellen), 'tellen_task_id');
      expect(
        matchTaskIdColumnForRole(kMatchTaskRoleTweedeScheidsrechter),
        'tweede_scheidsrechter_task_id',
      );
    });
  });
}
