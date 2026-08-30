import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/app_user_context.dart';

List<String> _visible({
  List<String> userCommittees = const [],
  bool hasFullAdminRights = false,
  bool isCommitteePowerAdmin = false,
  bool isInBestuur = false,
  bool canManageAccounts = false,
}) {
  return visibleCommitteesForCommissiesTab(
    userCommittees: userCommittees,
    hasFullAdminRights: hasFullAdminRights,
    isCommitteePowerAdmin: isCommitteePowerAdmin,
    isInBestuur: isInBestuur,
    canManageAccounts: canManageAccounts,
  );
}

void main() {
  group('commissiesEmptyMessage', () {
    test('geen commissie → exacte lege melding', () {
      expect(commissiesEmptyMessage, 'Je bent niet gekoppeld aan een commissie.');
    });
  });

  group('dedupeNormalizedCommitteeKeys', () {
    test('naamvarianten → geen dubbele commissie', () {
      expect(
        dedupeNormalizedCommitteeKeys(['cc', 'Communicatie', 'communicatie']),
        ['communicatie'],
      );
      expect(
        dedupeNormalizedCommitteeKeys(['TC', 'Technische Commissie']),
        ['technische-commissie'],
      );
      expect(
        dedupeNormalizedCommitteeKeys(['wz', 'Wedstrijdzaken']),
        ['wedstrijdzaken'],
      );
    });
  });

  group('visibleCommitteesForCommissiesTab', () {
    test('geen commissie → lege lijst', () {
      expect(_visible(), isEmpty);
    });

    test('één commissie → alleen die commissie', () {
      expect(_visible(userCommittees: ['communicatie']), ['communicatie']);
      expect(_visible(userCommittees: ['Wedstrijdzaken']), ['wedstrijdzaken']);
    });

    test('twee commissies → beide zichtbaar', () {
      expect(
        _visible(userCommittees: ['evenementen', 'communicatie']),
        ['communicatie', 'evenementen'],
      );
    });

    test('gewoon commissielid → geen toegang tot andere commissies', () {
      final visible = _visible(userCommittees: ['wedstrijdzaken']);
      expect(visible, ['wedstrijdzaken']);
      expect(visible, isNot(contains('communicatie')));
      expect(visible, isNot(contains('bestuur')));
      expect(visible.length, 1);
    });

    test('bestuur → alle commissies', () {
      final visible = _visible(userCommittees: ['bestuur'], isInBestuur: true);
      expect(visible, standardCommitteeKeys);
    });

    test('global admin → alle commissies', () {
      final visible = _visible(hasFullAdminRights: true);
      expect(visible, standardCommitteeKeys);
    });

    test('committee power admin → alle commissies + admin-tab', () {
      final visible = _visible(
        isCommitteePowerAdmin: true,
        canManageAccounts: true,
      );
      expect(visible.first, 'admin');
      expect(visible, containsAll(standardCommitteeKeys));
    });

    test(
      'committee power admin zonder committee_members → geen Contact-lidmaatschap',
      () {
        const userCommittees = <String>[];
        final membershipKeys = dedupeNormalizedCommitteeKeys(userCommittees);
        expect(membershipKeys, isEmpty);

        final visible = _visible(
          userCommittees: userCommittees,
          isCommitteePowerAdmin: true,
          canManageAccounts: true,
        );
        expect(visible, isNotEmpty);
        expect(visible, containsAll(standardCommitteeKeys));
      },
    );

    test('custom commissie blijft zichtbaar voor lid', () {
      expect(
        _visible(userCommittees: ['sponsorcommissie']),
        ['sponsorcommissie'],
      );
    });

    test('bestuur ziet custom commissie uit eigen koppeling', () {
      final visible = _visible(
        userCommittees: ['bestuur', 'sponsorcommissie'],
        isInBestuur: true,
      );
      expect(visible, [...standardCommitteeKeys, 'sponsorcommissie']);
    });
  });
}
