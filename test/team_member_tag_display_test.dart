import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/team_member_tag_display.dart';

void main() {
  test('tag wordt achter de naam van hetzelfde profiel en team gezet', () {
    final tags = {teamMemberTagKey(2, 'player-1'): 'aanvoerder'};

    expect(
      displayNameWithTeamMemberTag(
        displayName: 'Thijs',
        profileId: 'player-1',
        teamId: 2,
        tagsByTeamAndProfile: tags,
      ),
      'Thijs (aanvoerder)',
    );
  });

  test('tag van een ander team wordt niet getoond', () {
    final tags = {teamMemberTagKey(2, 'player-1'): 'aanvoerder'};

    expect(
      displayNameWithTeamMemberTag(
        displayName: 'Thijs',
        profileId: 'player-1',
        teamId: 3,
        tagsByTeamAndProfile: tags,
      ),
      'Thijs',
    );
  });

  test('oudertag wordt nooit achter de naam van het kind gezet', () {
    final tags = {teamMemberTagKey(2, 'parent-1'): 'vader van Jessie'};

    expect(
      displayNameWithTeamMemberTag(
        displayName: 'Jessie',
        profileId: 'child-1',
        teamId: 2,
        tagsByTeamAndProfile: tags,
      ),
      'Jessie',
    );
  });
}
