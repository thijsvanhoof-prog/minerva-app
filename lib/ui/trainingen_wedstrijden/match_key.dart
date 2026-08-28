/// Canonical Nevobo match_key helpers.
///
/// Stored keys are `nevobo_match:<TEAMCODE>:<START_UTC_ISO>`. The ISO suffix
/// can differ between app versions (millis vs seconds, Z vs offset, MR vs XR),
/// so lookups must tolerate equivalent keys — otherwise aanmeldingen verdwijnen.
library;

class MatchKeyTarget {
  final String matchKey;
  final String teamCode;
  final DateTime start;

  const MatchKeyTarget({
    required this.matchKey,
    required this.teamCode,
    required this.start,
  });
}

/// XR is the display alias for recreanten/mix (MR).
String canonicalizeNevoboTeamCode(String code) {
  final normalized = code.trim().toUpperCase();
  if (normalized.startsWith('XR') && normalized.length > 2) {
    return 'MR${normalized.substring(2)}';
  }
  return normalized;
}

Set<String> nevoboTeamCodeAliases(String code) {
  final canonical = canonicalizeNevoboTeamCode(code);
  if (canonical.startsWith('MR') && canonical.length > 2) {
    return {canonical, 'XR${canonical.substring(2)}'};
  }
  return {canonical};
}

bool sameNevoboTeamCode(String a, String b) {
  return canonicalizeNevoboTeamCode(a) == canonicalizeNevoboTeamCode(b);
}

/// Second-precision UTC key so micros/millis drift does not split rows.
String nevoboMatchKey({required String teamCode, required DateTime start}) {
  final utc = start.toUtc();
  final trimmed = DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
  );
  return 'nevobo_match:${canonicalizeNevoboTeamCode(teamCode)}:${trimmed.toIso8601String()}';
}

(String team, DateTime start)? parseNevoboMatchKey(String key) {
  if (!key.startsWith('nevobo_match:')) return null;
  final rest = key.substring('nevobo_match:'.length);
  final idx = rest.indexOf(':');
  if (idx <= 0 || idx + 1 >= rest.length) return null;
  final team = canonicalizeNevoboTeamCode(rest.substring(0, idx));
  final start = DateTime.tryParse(rest.substring(idx + 1))?.toUtc();
  if (team.isEmpty || start == null) return null;
  return (team, start);
}

DateTime? parseMatchStartsAt(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toUtc();
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toUtc();
}

/// Map a stored availability row onto a currently displayed match.
String? resolveLocalMatchKey({
  required Iterable<MatchKeyTarget> matches,
  required String rowKey,
  String? teamCode,
  dynamic startsAt,
  Duration tolerance = const Duration(minutes: 2),
}) {
  final list = matches.toList();
  if (list.isEmpty) return null;

  if (rowKey.isNotEmpty) {
    for (final m in list) {
      if (m.matchKey == rowKey) return m.matchKey;
    }
  }

  MatchKeyTarget? bestFor(String team, DateTime start) {
    MatchKeyTarget? best;
    Duration? bestDiff;
    for (final m in list) {
      if (!sameNevoboTeamCode(m.teamCode, team)) continue;
      final diff = m.start.toUtc().difference(start).abs();
      if (diff <= tolerance && (bestDiff == null || diff < bestDiff)) {
        best = m;
        bestDiff = diff;
      }
    }
    return best;
  }

  final rowParts = parseNevoboMatchKey(rowKey);
  if (rowParts != null) {
    final hit = bestFor(rowParts.$1, rowParts.$2);
    if (hit != null) return hit.matchKey;
  }

  final parsedStart = parseMatchStartsAt(startsAt);
  final team = (teamCode ?? '').trim();
  if (team.isNotEmpty && parsedStart != null) {
    final hit = bestFor(team, parsedStart);
    if (hit != null) return hit.matchKey;
  }

  if (parsedStart != null && team.isEmpty && rowParts != null) {
    final hit = bestFor(rowParts.$1, parsedStart);
    if (hit != null) return hit.matchKey;
  }

  return null;
}
