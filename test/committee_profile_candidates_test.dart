import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/bestuur/committee_profile_candidates.dart';

CommitteeProfileCandidate _candidate({
  required String id,
  String name = '',
  String? email,
  String accountRole = '',
}) {
  return parseCommitteeProfileRow({
    'profile_id': id,
    'display_name': name,
    'email': email,
    'account_role': accountRole,
  });
}

void main() {
  group('parseCommitteeProfileRow', () {
    test('supporter verschijnt als commissiekandidaat', () {
      final candidate = _candidate(
        id: 'supporter-1',
        name: 'Test Supporter',
        email: 'test@test.nl',
        accountRole: 'supporter',
      );
      expect(candidate.profileId, 'supporter-1');
      expect(
        filterVisibleCommitteeCandidates([candidate]),
        contains(candidate),
      );
    });

    test('ouder verschijnt als commissiekandidaat', () {
      final candidate = _candidate(
        id: 'ouder-1',
        name: 'Test Ouder',
        email: 'ouder@test.nl',
        accountRole: 'ouder',
      );
      expect(
        filterVisibleCommitteeCandidates([candidate]),
        contains(candidate),
      );
    });

    test('speler/trainer verschijnt als commissiekandidaat', () {
      final player = _candidate(
        id: 'player-1',
        name: 'Speler',
        email: 'speler@test.nl',
        accountRole: 'member',
      );
      final trainer = _candidate(
        id: 'trainer-1',
        name: 'Trainer',
        email: 'trainer@test.nl',
      );
      final visible = filterVisibleCommitteeCandidates([player, trainer]);
      expect(visible, containsAll([player, trainer]));
    });
  });

  group('mergeCommitteeProfileCandidates', () {
    test(
      'kandidaat uit tweede RPC wordt toegevoegd als eerste RPC onvolledig is',
      () {
        final firstRpc = [
          _candidate(id: 'a', name: 'Alice', email: 'alice@test.nl'),
        ];
        final secondRpc = [
          _candidate(
            id: 'b',
            name: 'Bob Supporter',
            email: 'test@test.nl',
            accountRole: 'supporter',
          ),
        ];

        final merged = mergeCommitteeProfileCandidates([firstRpc, secondRpc]);
        expect(merged.map((c) => c.profileId), ['a', 'b']);
        expect(
          merged.any((c) => c.email == 'test@test.nl'),
          isTrue,
          reason: 'supporter uit tweede RPC moet zichtbaar zijn',
        );
      },
    );

    test('dubbele profielen uit meerdere RPCs verschijnen één keer', () {
      final rpcA = [_candidate(id: 'shared', name: 'Onvolledig', email: '')];
      final rpcB = [
        _candidate(id: 'shared', name: 'Volledige Naam', email: 'test@test.nl'),
      ];

      final merged = mergeCommitteeProfileCandidates([rpcA, rpcB]);
      expect(merged, hasLength(1));
      expect(merged.single.profileId, 'shared');
      expect(merged.single.name, 'Volledige Naam');
      expect(merged.single.email, 'test@test.nl');
    });

    test('mergeCommitteeProfileRowsFromRpcResults sorteert op naam', () {
      final merged = mergeCommitteeProfileRowsFromRpcResults([
        [
          {'profile_id': 'z-id', 'display_name': 'Zorro', 'email': 'z@test.nl'},
        ],
        [
          {'profile_id': 'a-id', 'display_name': 'Anna', 'email': 'a@test.nl'},
        ],
      ]);
      expect(merged.map((c) => c.name), ['Anna', 'Zorro']);
    });
  });

  group('availableCommitteeCandidates', () {
    test('bestaand lid wordt alleen voor diezelfde commissie uitgesloten', () {
      final all = [
        _candidate(id: 'person-1', name: 'Persoon', email: 'test@test.nl'),
      ];
      final forWedstrijdzaken = availableCommitteeCandidates(
        allCandidates: all,
        existingMemberProfileIds: {'person-1'},
      );
      final forCommunicatie = availableCommitteeCandidates(
        allCandidates: all,
        existingMemberProfileIds: {},
      );

      expect(forWedstrijdzaken, isEmpty);
      expect(forCommunicatie, all);
    });
  });

  group('searchCommitteeCandidates', () {
    test('zoeken op test@test.nl vindt het account', () {
      final candidates = [
        _candidate(id: 'supporter-1', name: 'Test User', email: 'test@test.nl'),
        _candidate(id: 'other', name: 'Andere', email: 'other@test.nl'),
      ];

      final found = searchCommitteeCandidates(candidates, 'test@test.nl');
      expect(found, hasLength(1));
      expect(found.single.email, 'test@test.nl');
    });

    test('zoeken is case-insensitive op naam', () {
      final candidates = [
        _candidate(id: '1', name: 'Jan de Vries', email: 'jan@test.nl'),
      ];
      expect(searchCommitteeCandidates(candidates, 'JAN DE'), hasLength(1));
    });
  });

  group('filterVisibleCommitteeCandidates', () {
    test('gast@mail.com blijft uitgesloten', () {
      final guest = _candidate(
        id: 'guest',
        name: 'Gast',
        email: 'gast@mail.com',
      );
      expect(filterVisibleCommitteeCandidates([guest]), isEmpty);
    });
  });
}
