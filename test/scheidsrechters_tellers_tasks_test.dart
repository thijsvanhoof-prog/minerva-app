import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/committees/committee_normalization.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/match_task_roles.dart';

bool isInScheidsrechtersTellersCommittee(Iterable<String> committees) {
  return committees.any(
    (c) => normalizeCommitteeKey(c) == 'scheidsrechters-tellers',
  );
}

void main() {
  group('actuele wedstrijdfilter', () {
    final september2026 = DateTime.utc(2026, 9, 5, 12);
    final january2026Match = DateTime.utc(2026, 1, 15, 19, 30);
    final futureMatch = DateTime.utc(2026, 9, 20, 19, 30);

    test('wedstrijd uit januari 2026 is niet zichtbaar in september 2026', () {
      expect(
        isHomeMatchStillActive(january2026Match, now: september2026),
        isFalse,
      );
      expect(
        isHomeMatchRowStillActive({
          'starts_at': january2026Match.toIso8601String(),
        }, now: september2026),
        isFalse,
      );
    });

    test('toekomstige wedstrijd is wel zichtbaar', () {
      expect(isHomeMatchStillActive(futureMatch, now: september2026), isTrue);
    });

    test('server cutoff hanteert 4 uur grace', () {
      final cutoff = homeMatchActiveCutoffUtc(now: september2026);
      expect(cutoff, september2026.subtract(kHomeMatchActiveGracePeriod));
      expect(kHomeMatchActiveGracePeriod, const Duration(hours: 4));
    });

    test('wedstrijd van 3 uur geleden is nog zichtbaar', () {
      final threeHoursAgo = september2026.subtract(const Duration(hours: 3));
      expect(isHomeMatchStillActive(threeHoursAgo, now: september2026), isTrue);
    });

    test('wedstrijd van 5 uur geleden is niet meer zichtbaar', () {
      final fiveHoursAgo = september2026.subtract(const Duration(hours: 5));
      expect(isHomeMatchStillActive(fiveHoursAgo, now: september2026), isFalse);
    });
  });

  group('stOverviewMode signup-gating', () {
    Future<bool> readStOverviewSignupAllowed({
      required WidgetTester tester,
      required List<String> committees,
      required bool isGlobalAdmin,
      required bool isCommitteePowerAdmin,
    }) async {
      late bool allowed;
      await tester.pumpWidget(
        MaterialApp(
          home: AppUserContext(
            profileId: 'u1',
            email: 'test@example.com',
            displayName: 'Test',
            isGlobalAdmin: isGlobalAdmin,
            isCommitteePowerAdmin: isCommitteePowerAdmin,
            memberships: const [],
            committees: committees,
            loggedInProfileId: 'u1',
            child: Builder(
              builder: (context) {
                final ctx = AppUserContext.of(context);
                allowed = allowOpenSignupInStOverview(
                  stOverviewMode: true,
                  isInScheidsrechtersTellers: ctx.isInScheidsrechtersTellers,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return allowed;
    }

    test('echt S/T-lid + stOverviewMode → open signup toegestaan', () {
      expect(
        allowOpenSignupInStOverview(
          stOverviewMode: true,
          isInScheidsrechtersTellers: true,
        ),
        isTrue,
      );
    });

    testWidgets('echt S/T-lid + stOverviewMode → open signup via context', (
      tester,
    ) async {
      expect(
        await readStOverviewSignupAllowed(
          tester: tester,
          committees: const ['Scheidsrechters/Tellers'],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: false,
        ),
        isTrue,
      );
    });

    test(
      'power admin zonder S/T-lidmaatschap + stOverviewMode → geen open signup',
      () {
        expect(
          allowOpenSignupInStOverview(
            stOverviewMode: true,
            isInScheidsrechtersTellers: false,
          ),
          isFalse,
        );
      },
    );

    testWidgets(
      'power admin zonder S/T-lidmaatschap + stOverviewMode → geen open signup via context',
      (tester) async {
        expect(
          await readStOverviewSignupAllowed(
            tester: tester,
            committees: const ['wedstrijdzaken', 'bestuur'],
            isGlobalAdmin: false,
            isCommitteePowerAdmin: true,
          ),
          isFalse,
        );
      },
    );

    test('stOverviewMode uit → nooit open signup', () {
      expect(
        allowOpenSignupInStOverview(
          stOverviewMode: false,
          isInScheidsrechtersTellers: true,
        ),
        isFalse,
      );
    });
  });

  group('S/T open inschrijving', () {
    test('commissienaamvarianten herkennen S/T-lidmaatschap', () {
      expect(
        isInScheidsrechtersTellersCommittee(const ['Scheidsrechters/Tellers']),
        isTrue,
      );
      expect(
        isInScheidsrechtersTellersCommittee(const ['scheidsrechters-tellers']),
        isTrue,
      );
    });

    test('S/T-lid zonder team ziet wedstrijd met taak-id', () {
      expect(
        shouldSkipMatchWithoutTeamLink(
          openScheidsrechtersTellersSignup: true,
          linkedTeamId: null,
        ),
        isFalse,
      );
      expect(
        isMatchVisibleForUser(
          openScheidsrechtersTellersSignup: true,
          fluitenTaskId: 10,
          tellenTaskId: null,
          tweedeScheidsrechterTaskId: null,
          assignableTaskIds: {10},
        ),
        isTrue,
      );
    });

    test('S/T gebruikt eigen profiel ook bij geselecteerd kind', () {
      expect(
        matchTaskSignupProfileId(
          openScheidsrechtersTellersSignup: true,
          loggedInProfileId: 'parent-id',
          attendanceProfileId: 'child-id',
        ),
        'parent-id',
      );
    });

    test(
      'gewone gebruiker zonder teamtoewijzing krijgt geen open S/T-inschrijving',
      () {
        expect(
          isMatchVisibleForUser(
            openScheidsrechtersTellersSignup: false,
            fluitenTaskId: 10,
            tellenTaskId: 11,
            tweedeScheidsrechterTaskId: 12,
            assignableTaskIds: const {},
          ),
          isFalse,
        );
        expect(
          shouldSkipMatchWithoutTeamLink(
            openScheidsrechtersTellersSignup: false,
            linkedTeamId: null,
          ),
          isTrue,
        );
      },
    );

    test(
      'power admin zonder echte S/T-koppeling krijgt geen open inschrijfrecht',
      () {
        expect(
          isInScheidsrechtersTellersCommittee(const ['wedstrijdzaken']),
          isFalse,
        );
        expect(
          isInScheidsrechtersTellersCommittee(const [
            'bestuur',
            'communicatie',
          ]),
          isFalse,
        );
      },
    );

    test('refresh houdt hetzelfde S/T-aanmeldprofiel aan', () {
      const parentId = 'parent-id';
      const childId = 'child-id';
      final before = matchTaskSignupProfileId(
        openScheidsrechtersTellersSignup: true,
        loggedInProfileId: parentId,
        attendanceProfileId: childId,
      );
      final after = matchTaskSignupProfileId(
        openScheidsrechtersTellersSignup: true,
        loggedInProfileId: parentId,
        attendanceProfileId: childId,
      );
      expect(before, after);
      expect(before, parentId);
    });

    test('S/T-lid kan aan- en afmelden wanneer taak-id bestaat', () {
      expect(
        isMatchTaskAssignable(taskId: 42, assignableTaskIds: {42, 43}),
        isTrue,
      );
      expect(
        assignableTaskIdsForUser(
          openScheidsrechtersTellersSignup: true,
          allTaskIdsInMatches: {42, 43},
          teamAssignedTaskIds: const {},
        ),
        {42, 43},
      );
    });
  });
}
