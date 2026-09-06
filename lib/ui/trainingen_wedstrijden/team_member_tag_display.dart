import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String teamMemberTagKey(int teamId, String profileId) {
  return '$teamId:${profileId.trim().toLowerCase()}';
}

String displayNameWithTeamMemberTag({
  required String displayName,
  required String profileId,
  required int? teamId,
  required Map<String, String> tagsByTeamAndProfile,
}) {
  final name = displayName.trim();
  if (name.isEmpty || teamId == null || profileId.trim().isEmpty) return name;
  final tag = tagsByTeamAndProfile[teamMemberTagKey(teamId, profileId)]?.trim();
  return tag == null || tag.isEmpty ? name : '$name ($tag)';
}

Future<Map<String, String>> loadVisibleTeamMemberTags({
  required SupabaseClient client,
  required Iterable<int> teamIds,
}) async {
  final ids = teamIds.toSet().toList()..sort();
  if (ids.isEmpty) return const {};
  try {
    final res = await client.rpc(
      'get_visible_team_member_tags',
      params: {'p_team_ids': ids},
    );
    final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
    final tags = <String, String>{};
    for (final row in rows) {
      final teamId = (row['team_id'] as num?)?.toInt();
      final profileId = (row['profile_id']?.toString() ?? '').trim();
      final tag = (row['member_tag']?.toString() ?? '').trim();
      if (teamId == null || profileId.isEmpty || tag.isEmpty) continue;
      tags[teamMemberTagKey(teamId, profileId)] = tag;
    }
    return tags;
  } catch (error) {
    // Tags zijn optioneel zolang de database-migratie nog niet live staat.
    debugPrint('Lid-tags konden niet worden geladen: $error');
    return const {};
  }
}
