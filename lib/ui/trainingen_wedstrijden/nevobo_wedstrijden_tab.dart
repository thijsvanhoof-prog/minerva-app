import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, listEquals;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:minerva_app/ui/components/glass_card.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:minerva_app/ui/display_name_overrides.dart' show applyDisplayNameOverrides, unknownUserName;
import 'package:minerva_app/ui/trainingen_wedstrijden/match_key.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/match_travel.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NevoboWedstrijdenTab extends StatefulWidget {
  final List<String> teamCodes; // e.g. ["HS1","DS1"]
  /// team_code (uppercase) -> team_id, voor "niet gereageerd" overzicht
  final Map<String, int> teamIdByCode;

  const NevoboWedstrijdenTab({
    super.key,
    required this.teamCodes,
    this.teamIdByCode = const {},
  });

  @override
  State<NevoboWedstrijdenTab> createState() => _NevoboWedstrijdenTabState();
}

class _NevoboWedstrijdenTabState extends State<NevoboWedstrijdenTab> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<NevoboTeam> _teams = const [];

  final Map<String, List<NevoboMatch>> _matchesByTeam = {};
  final Map<String, String> _matchErrorByTeam = {};

  // Availability state
  final Map<String, String> _myStatusByMatchKey = {}; // match_key -> playing | coach | not_playing (null = nog geen keuze)
  final Map<String, List<String>> _playingNamesByMatchKey = {};
  final Map<String, List<String>> _coachNamesByMatchKey = {};
  final Map<String, List<String>> _notPlayingNamesByMatchKey = {};
  final Map<String, List<String>> _nietGereageerdByMatchKey = {};
  final Map<String, List<String>> _refereeNamesByMatchKey = {};
  final Map<String, List<String>> _tellerNamesByMatchKey = {};
  final Map<String, bool> _cancelledByMatchKey = {}; // match_key -> true if cancelled
  final Map<String, String?> _cancelReasonByMatchKey = {};
  final Set<String> _expandedMatchKeys = {};
  String? _myDisplayName;

  final Map<String, List<NevoboStandingEntry>> _leaderboardByTeam = {};
  final Map<String, String> _errorByTeam = {};

  /// Alle komende wedstrijden (voor "voor alle wedstrijden"-acties)
  List<_MatchRef> _upcomingMatchRefs = const [];

  /// Geselecteerde teamcodes voor weergave (opgeslagen in SharedPreferences).
  Set<String> _selectedTeamCodes = const {};
  static const _selectedTeamsKey = 'wedstrijden_selected_team_codes';

  @override
  void initState() {
    super.initState();
    _selectedTeamCodes = widget.teamCodes
        .map((c) => c.trim().toUpperCase())
        .where((c) => c.isNotEmpty)
        .toSet();
    _loadSelectedTeamsFromPrefs();
    _loadAll();
  }

  @override
  void didUpdateWidget(covariant NevoboWedstrijdenTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.teamCodes, widget.teamCodes)) {
      final current = widget.teamCodes
          .map((c) => c.trim().toUpperCase())
          .where((c) => c.isNotEmpty)
          .toSet();
      final merged = _selectedTeamCodes.intersection(current);
      setState(() {
        _selectedTeamCodes = merged.isEmpty ? current : merged;
      });
    }
  }

  Future<void> _loadSelectedTeamsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_selectedTeamsKey);
      if (json == null) return;
      final list = jsonDecode(json) as List<dynamic>?;
      if (list == null || list.isEmpty) return;
      final saved = list
          .map((e) => e.toString().trim().toUpperCase())
          .where((c) => c.isNotEmpty)
          .toSet();
      final current = widget.teamCodes
          .map((c) => c.trim().toUpperCase())
          .where((c) => c.isNotEmpty)
          .toSet();
      final merged = saved.intersection(current);
      if (merged.isNotEmpty && mounted) {
        setState(() => _selectedTeamCodes = merged);
      }
    } catch (_) {}
  }

  Future<void> _saveSelectedTeamsToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _selectedTeamsKey,
        jsonEncode(_selectedTeamCodes.toList()..sort()),
      );
    } catch (_) {}
  }

  void _toggleTeamSelection(String code) {
    final upper = code.trim().toUpperCase();
    setState(() {
      if (_selectedTeamCodes.contains(upper)) {
        if (_selectedTeamCodes.length > 1) {
          _selectedTeamCodes = {..._selectedTeamCodes}..remove(upper);
        }
      } else {
        _selectedTeamCodes = {..._selectedTeamCodes}..add(upper);
      }
    });
    _saveSelectedTeamsToPrefs();
  }

  bool _segmentMatchesTeamCode(String segment, String teamCode) {
    final s = segment.trim();
    if (s.isEmpty || !s.toLowerCase().contains('minerva')) return false;
    final extracted = NevoboApi.extractCodeFromTeamName(s);
    if (extracted == null || extracted.isEmpty) return false;
    final a = extracted.trim().toUpperCase();
    final b = teamCode.trim().toUpperCase();
    if (a.startsWith('XR') && b.startsWith('MR') && a.substring(2) == b.substring(2)) return true;
    if (b.startsWith('XR') && a.startsWith('MR') && b.substring(2) == a.substring(2)) return true;
    return a == b;
  }

  /// Displaylabel voor team (inclusief "(kindnaam)" bij gekoppeld kind).
  String _teamDisplayLabelForCode(String teamCode) {
    try {
      final ctx = AppUserContext.of(context);
      final code = teamCode.trim().toUpperCase();
      for (final m in ctx.memberships) {
        final extracted = NevoboApi.extractCodeFromTeamName(m.teamName);
        final match = extracted != null && extracted.toUpperCase() == code;
        final nevoboMatch = (m.nevoboCode?.trim().toUpperCase() ?? '') == code;
        if (match || nevoboMatch) return m.displayLabel;
      }
      return NevoboApi.displayTeamCode(teamCode);
    } catch (_) {
      return NevoboApi.displayTeamCode(teamCode);
    }
  }

  /// Highlight alleen het Minerva-team dat exact bij [teamCode] hoort.
  Widget _buildMatchSummaryText(String summary, {TextStyle? style, String? teamCode}) {
    final base = style ??
        const TextStyle(
          color: AppColors.onBackground,
          fontWeight: FontWeight.w800,
        );
    const sep = ' - ';
    final parts = summary.split(sep);
    if (parts.isEmpty) return Text(summary, style: base);

    final minervaSegmentCount = parts
        .where((p) => p.toLowerCase().contains('minerva'))
        .length;
    final isInternalMinervaMatch = minervaSegmentCount >= 2;

    if (teamCode != null && teamCode.trim().isNotEmpty) {
      final spans = <InlineSpan>[];
      var anyExactMatch = false;
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) spans.add(TextSpan(text: sep, style: base));
        final segment = parts[i].trim();
        final highlight = _segmentMatchesTeamCode(segment, teamCode) ||
            (isInternalMinervaMatch && segment.toLowerCase().contains('minerva'));
        if (highlight) anyExactMatch = true;
        spans.add(TextSpan(
          text: parts[i],
          style: highlight ? base.copyWith(color: AppColors.primary, fontWeight: FontWeight.w900) : base,
        ));
      }
      // Fallback: als exacte teamcode niet matcht, highlight alsnog eerste "Minerva"-segment.
      if (!anyExactMatch) {
        spans.clear();
        var highlighted = false;
        for (var i = 0; i < parts.length; i++) {
          if (i > 0) spans.add(TextSpan(text: sep, style: base));
          final raw = parts[i];
          final isMinervaSegment = !highlighted && raw.toLowerCase().contains('minerva');
          if (isMinervaSegment) highlighted = true;
          spans.add(TextSpan(
            text: raw,
            style: isMinervaSegment
                ? base.copyWith(color: AppColors.primary, fontWeight: FontWeight.w900)
                : base,
          ));
        }
      }
      return RichText(
        text: TextSpan(style: base, children: spans),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      );
    }

    final lower = summary.toLowerCase();
    final idx = lower.indexOf('minerva');
    if (idx < 0) return Text(summary, style: base);
    final endIdx = summary.indexOf(sep, idx) >= 0 ? summary.indexOf(sep, idx) : summary.length;
    final before = summary.substring(0, idx);
    final mid = summary.substring(idx, endIdx);
    final after = summary.substring(endIdx);
    return RichText(
      text: TextSpan(
        style: base,
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          TextSpan(text: mid, style: base.copyWith(color: AppColors.primary, fontWeight: FontWeight.w900)),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
  }

  String _matchKey({required String teamCode, required DateTime start}) {
    return nevoboMatchKey(teamCode: teamCode, start: start);
  }

  String _normalizeMatchSummaryForCompare(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .trim();
  }

  (String team, DateTime start)? _parseNevoboMatchKey(String key) {
    if (!key.startsWith('nevobo_match:')) return null;
    final rest = key.substring('nevobo_match:'.length);
    final idx = rest.indexOf(':');
    if (idx <= 0 || idx + 1 >= rest.length) return null;
    final team = rest.substring(0, idx).trim().toUpperCase();
    final start = DateTime.tryParse(rest.substring(idx + 1))?.toUtc();
    if (team.isEmpty || start == null) return null;
    return (team, start);
  }

  bool _summariesMatchForCancellation(String a, String b) {
    final na = _normalizeMatchSummaryForCompare(a);
    final nb = _normalizeMatchSummaryForCompare(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb || na.contains(nb) || nb.contains(na);
  }

  DateTime? _parseCancellationStartsAt(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toUtc();
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toUtc();
  }

  _MatchRef? _findMatchRefByEquivalentKey({
    required List<_MatchRef> matches,
    required String rowKey,
  }) {
    final rowParts = _parseNevoboMatchKey(rowKey);
    if (rowParts == null) return null;
    const tolerance = Duration(minutes: 2);
    for (final m in matches) {
      final localParts = _parseNevoboMatchKey(m.matchKey);
      if (localParts == null) continue;
      if (localParts.$1 != rowParts.$1) continue;
      if (localParts.$2.difference(rowParts.$2).abs() <= tolerance) return m;
    }
    return null;
  }

  _MatchRef? _findMatchRefByTeamAndTime({
    required List<_MatchRef> matches,
    required String teamCode,
    required DateTime startsAt,
  }) {
    const tolerance = Duration(minutes: 2);
    _MatchRef? best;
    Duration? bestDiff;
    for (final m in matches) {
      if (m.teamCode.trim().toUpperCase() != teamCode) continue;
      final diff = m.start.toUtc().difference(startsAt).abs();
      if (diff <= tolerance && (bestDiff == null || diff < bestDiff)) {
        best = m;
        bestDiff = diff;
      }
    }
    return best;
  }

  _MatchRef? _findMatchRefByTimeAndSummary({
    required List<_MatchRef> matches,
    required DateTime startsAt,
    required String rowSummary,
  }) {
    const tolerance = Duration(minutes: 2);
    _MatchRef? best;
    Duration? bestDiff;
    for (final m in matches) {
      final diff = m.start.toUtc().difference(startsAt).abs();
      if (diff > tolerance) continue;
      if (!_summariesMatchForCancellation(m.summary, rowSummary)) continue;
      if (bestDiff == null || diff < bestDiff) {
        best = m;
        bestDiff = diff;
      }
    }
    return best;
  }

  _MatchRef? _findMatchRefByTeamAndSummary({
    required List<_MatchRef> matches,
    required String teamCode,
    required String rowSummary,
  }) {
    _MatchRef? best;
    for (final m in matches) {
      if (m.teamCode.trim().toUpperCase() != teamCode) continue;
      if (!_summariesMatchForCancellation(m.summary, rowSummary)) continue;
      best ??= m;
    }
    return best;
  }

  _MatchRef? _findMatchRefByTeamAndLocalDate({
    required List<_MatchRef> matches,
    required String teamCode,
    required DateTime startsAt,
    required String rowSummary,
  }) {
    final localRow = startsAt.toLocal();
    for (final m in matches) {
      if (m.teamCode.trim().toUpperCase() != teamCode) continue;
      final localMatch = m.start.toLocal();
      if (localMatch.year != localRow.year ||
          localMatch.month != localRow.month ||
          localMatch.day != localRow.day) {
        continue;
      }
      if (rowSummary.trim().isEmpty ||
          _summariesMatchForCancellation(m.summary, rowSummary)) {
        return m;
      }
    }
    return null;
  }

  _MatchRef? _findMatchRefForCancellationRow({
    required List<_MatchRef> matches,
    required Set<String> localKeys,
    required Map<String, dynamic> row,
  }) {
    final rowKey = (row['match_key'] ?? '').toString();
    if (rowKey.isNotEmpty) {
      if (localKeys.contains(rowKey)) {
        for (final m in matches) {
          if (m.matchKey == rowKey) return m;
        }
      }
      final byKey = _findMatchRefByEquivalentKey(matches: matches, rowKey: rowKey);
      if (byKey != null) return byKey;
    }

    final teamCode = (row['team_code'] ?? '').toString().trim().toUpperCase();
    final startsAt = _parseCancellationStartsAt(row['starts_at']);
    final rowSummary = (row['summary'] ?? '').toString();

    if (teamCode.isNotEmpty && startsAt != null) {
      final byTeamTime = _findMatchRefByTeamAndTime(
        matches: matches,
        teamCode: teamCode,
        startsAt: startsAt,
      );
      if (byTeamTime != null) return byTeamTime;
    }

    if (startsAt != null && rowSummary.trim().isNotEmpty) {
      final byTimeSummary = _findMatchRefByTimeAndSummary(
        matches: matches,
        startsAt: startsAt,
        rowSummary: rowSummary,
      );
      if (byTimeSummary != null) return byTimeSummary;
    }

    if (teamCode.isNotEmpty && rowSummary.trim().isNotEmpty) {
      final byTeamSummary = _findMatchRefByTeamAndSummary(
        matches: matches,
        teamCode: teamCode,
        rowSummary: rowSummary,
      );
      if (byTeamSummary != null) return byTeamSummary;
    }

    if (teamCode.isNotEmpty && startsAt != null) {
      final byTeamDate = _findMatchRefByTeamAndLocalDate(
        matches: matches,
        teamCode: teamCode,
        startsAt: startsAt,
        rowSummary: rowSummary,
      );
      if (byTeamDate != null) return byTeamDate;
    }

    if (teamCode.isEmpty && rowKey.isNotEmpty) {
      final rowParts = _parseNevoboMatchKey(rowKey);
      if (rowParts != null) {
        return _findMatchRefByTeamAndTime(
          matches: matches,
          teamCode: rowParts.$1,
          startsAt: rowParts.$2,
        );
      }
    }

    return null;
  }

  void _applyCancellationRowToMaps({
    required Map<String, dynamic> row,
    required _MatchRef ref,
    required Map<String, bool> map,
    required Map<String, String?> reasons,
  }) {
    final localKey = ref.matchKey;
    final cancelled = row['is_cancelled'] == true;
    if (cancelled) {
      map[localKey] = true;
      final reason = (row['reason'] ?? '').toString().trim();
      if (reason.isNotEmpty) reasons[localKey] = reason;
      return;
    }
    map.putIfAbsent(localKey, () => false);
    final reason = (row['reason'] ?? '').toString().trim();
    reasons.putIfAbsent(localKey, () => reason.isEmpty ? null : reason);
  }

  /// Nevobo levert wedstrijden; lokale annuleringen uit `match_cancellations` winnen.
  void _overlayLocalCancellations({
    required List<_MatchRef> matches,
    required List<Map<String, dynamic>> rows,
    required Map<String, bool> map,
    required Map<String, String?> reasons,
  }) {
    final localKeys = matches.map((m) => m.matchKey).toSet();
    for (final ref in matches) {
      for (final r in rows) {
        if (r['is_cancelled'] != true) continue;
        final hit = _findMatchRefForCancellationRow(
          matches: [ref],
          localKeys: localKeys,
          row: r,
        );
        if (hit != null) {
          _applyCancellationRowToMaps(
            row: r,
            ref: hit,
            map: map,
            reasons: reasons,
          );
          break;
        }
      }
    }
    for (final r in rows) {
      final ref = _findMatchRefForCancellationRow(
        matches: matches,
        localKeys: localKeys,
        row: r,
      );
      if (ref == null) continue;
      _applyCancellationRowToMaps(row: r, ref: ref, map: map, reasons: reasons);
    }
  }

  void _debugLogCancellationMatching({
    required List<_MatchRef> matches,
    required List<Map<String, dynamic>> rows,
    required Map<String, bool> matched,
  }) {
    debugPrint(
      'NevoboWedstrijden: cancellations refs=${matches.length} rows=${rows.length} matched=${matched.length}',
    );
    for (final m in matches) {
      if (m.teamCode.trim().toUpperCase() != 'JC1') continue;
      debugPrint(
        'NevoboWedstrijden: local JC1 key=${m.matchKey} '
        'startUtc=${m.start.toUtc().toIso8601String()} summary=${m.summary}',
      );
    }
    for (final r in rows) {
      final key = (r['match_key'] ?? '').toString();
      final team = (r['team_code'] ?? '').toString().trim().toUpperCase();
      if (team != 'JC1' && !key.contains(':JC1:')) continue;
      debugPrint(
        'NevoboWedstrijden: cancel JC1 row key=$key team=$team '
        'start=${r['starts_at']} cancelled=${r['is_cancelled']} reason=${r['reason']}',
      );
    }
    for (final entry in matched.entries.where((e) => e.value)) {
      debugPrint('NevoboWedstrijden: matched cancelled key=${entry.key}');
    }
  }

  Future<Map<String, String>> _loadProfileDisplayNames(Set<String> profileIds) async {
    if (profileIds.isEmpty) return {};
    final ids = profileIds.toList();
    final me = _client.auth.currentUser;
    final myId = me?.id ?? '';
    final myMetaName = (me?.userMetadata?['display_name']?.toString() ?? '').trim();

    // Preferred: security definer RPC so names work even with restrictive RLS on profiles.
    try {
      final res = await _client.rpc('get_profile_display_names', params: {'profile_ids': ids});
      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final map = <String, String>{};
      for (final r in rows) {
        final id = r['profile_id']?.toString() ?? r['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final raw = (r['display_name'] ?? '').toString().trim();
        final name = applyDisplayNameOverrides(raw);
        map[id] = name.isNotEmpty ? name : unknownUserName;
      }
      if (myId.isNotEmpty && myMetaName.isNotEmpty && map.containsKey(myId)) {
        map[myId] = applyDisplayNameOverrides(myMetaName);
      }
      if (map.isNotEmpty) return map;
    } catch (_) {
      // fall back to direct profiles select below
    }

    List<Map<String, dynamic>> rows = const [];
    for (final select in const [
      'id, display_name, full_name, email',
      'id, display_name, email',
      'id, full_name, email',
      'id, name, email',
      'id, email',
    ]) {
      try {
        final res = await _client.from('profiles').select(select).inFilter('id', ids);
        rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
        break;
      } catch (_) {
        // try next
      }
    }

    final map = <String, String>{};
    for (final r in rows) {
      final id = r['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final name =
          (r['display_name'] ?? r['full_name'] ?? r['name'] ?? r['email'] ?? '')
              .toString()
              .trim();
      final overridden = applyDisplayNameOverrides(name);
      map[id] = overridden.isNotEmpty ? overridden : unknownUserName;
    }
    if (myId.isNotEmpty && myMetaName.isNotEmpty && map.containsKey(myId)) {
      map[myId] = applyDisplayNameOverrides(myMetaName);
    }
    return map;
  }

  Future<void> _loadAvailabilityForMatches(List<_MatchRef> matches) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    if (matches.isEmpty) return;

    final ctx = AppUserContext.of(context);
    final targetProfileId = ctx.attendanceProfileId;

    final keys = matches.map((m) => m.matchKey).toSet().toList();
    final targets = [
      for (final m in matches)
        MatchKeyTarget(matchKey: m.matchKey, teamCode: m.teamCode, start: m.start),
    ];

    // Fetch availability; match_key strings drift between app versions, so also
    // load by team_code and key prefix, then map onto the displayed matches.
    const select = 'match_key, profile_id, status, team_code, starts_at';
    final collected = <String, Map<String, dynamic>>{};
    void addRows(dynamic res) {
      for (final r in (res as List<dynamic>).cast<Map<String, dynamic>>()) {
        final id = '${r['match_key']}|${r['profile_id']}';
        collected[id] = r;
      }
    }

    try {
      addRows(
        await _client.from('match_availability').select(select).inFilter('match_key', keys),
      );
    } catch (_) {
      // Table missing or RLS; leave empty unless the broader queries succeed.
    }

    final teamAliases = <String>{};
    for (final m in matches) {
      teamAliases.addAll(nevoboTeamCodeAliases(m.teamCode));
    }
    if (teamAliases.isNotEmpty) {
      try {
        addRows(
          await _client
              .from('match_availability')
              .select(select)
              .inFilter('team_code', teamAliases.toList()),
        );
      } catch (_) {}
      await Future.wait(
        teamAliases.map((code) async {
          try {
            addRows(
              await _client
                  .from('match_availability')
                  .select(select)
                  .like('match_key', 'nevobo_match:$code:%'),
            );
          } catch (_) {}
        }),
      );
    }

    final rows = <Map<String, dynamic>>[];
    for (final r in collected.values) {
      final localKey = resolveLocalMatchKey(
        matches: targets,
        rowKey: (r['match_key'] ?? '').toString(),
        teamCode: r['team_code']?.toString(),
        startsAt: r['starts_at'],
      );
      if (localKey == null) continue;
      rows.add({...r, 'match_key': localKey});
    }

    final profileIds = <String>{};
    for (final r in rows) {
      final pid = r['profile_id']?.toString() ?? '';
      if (pid.isNotEmpty) profileIds.add(pid);
    }
    // Altijd naam van huidig profiel (zelf of kind) laden, ook als die nog nergens is aangemeld.
    if (targetProfileId.isNotEmpty) profileIds.add(targetProfileId);
    final namesById = await _loadProfileDisplayNames(profileIds);

    final myStatus = <String, String>{};
    final playingByKey = <String, List<String>>{};
    final coachByKey = <String, List<String>>{};
    final notPlayingByKey = <String, List<String>>{};

    for (final r in rows) {
      final key = (r['match_key'] ?? '').toString();
      if (key.isEmpty) continue;
      final pid = r['profile_id']?.toString() ?? '';
      final status = (r['status'] ?? '').toString().trim().toLowerCase();
      final name = pid.isEmpty ? '' : (namesById[pid] ?? unknownUserName);

      if (pid == targetProfileId &&
          (status == 'playing' || status == 'coach' || status == 'not_playing' || status == 'afgemeld')) {
        myStatus[key] = status;
      }
      if (name.trim().isEmpty) continue;
      if (status == 'playing') {
        playingByKey.putIfAbsent(key, () => []).add(name);
      } else if (status == 'coach') {
        coachByKey.putIfAbsent(key, () => []).add(name);
      } else if (status == 'not_playing') {
        notPlayingByKey.putIfAbsent(key, () => []).add(name);
      }
    }

    for (final entry in playingByKey.entries) {
      entry.value.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    for (final entry in coachByKey.entries) {
      entry.value.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    for (final entry in notPlayingByKey.entries) {
      entry.value.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }

    // Leden die niet hebben gereageerd: teamleden zonder match_availability-row.
    final respondedByKey = <String, Set<String>>{};
    for (final r in rows) {
      final key = (r['match_key'] ?? '').toString();
      final pid = r['profile_id']?.toString() ?? '';
      if (key.isEmpty || pid.isEmpty) continue;
      respondedByKey.putIfAbsent(key, () => {}).add(pid);
    }

    final nietGereageerdByKey = <String, List<String>>{};
    if (widget.teamIdByCode.isNotEmpty) {
      final teamIds = <int>{};
      final matchKeyToTeamId = <String, int>{};
      for (final m in matches) {
        final tid = widget.teamIdByCode[m.teamCode.trim().toUpperCase()];
        if (tid != null) {
          teamIds.add(tid);
          matchKeyToTeamId[m.matchKey] = tid;
        }
      }
      Map<int, List<String>> teamMemberIdsByTid = {};
      try {
        final tmRes = await _client
            .from('team_members')
            .select('team_id, profile_id')
            .inFilter('team_id', teamIds.toList());
        final tmRows = (tmRes as List<dynamic>).cast<Map<String, dynamic>>();
        for (final row in tmRows) {
          final tid = (row['team_id'] as num?)?.toInt();
          final pid = row['profile_id']?.toString() ?? '';
          if (tid == null || pid.isEmpty) continue;
          teamMemberIdsByTid.putIfAbsent(tid, () => []).add(pid);
        }
      } catch (_) {}

      var allNamesById = Map<String, String>.from(namesById);
      final idsToLoad = <String>{};
      for (final m in matches) {
        final key = m.matchKey;
        final tid = matchKeyToTeamId[key];
        if (tid == null) continue;
        final members = teamMemberIdsByTid[tid] ?? [];
        final responded = respondedByKey[key] ?? {};
        for (final pid in members) {
          if (!responded.contains(pid)) idsToLoad.add(pid);
        }
      }
      if (idsToLoad.isNotEmpty) {
        final extra = await _loadProfileDisplayNames(idsToLoad);
        allNamesById = {...allNamesById, ...extra};
      }
      for (final m in matches) {
        final key = m.matchKey;
        final tid = matchKeyToTeamId[key];
        if (tid == null) continue;
        final members = teamMemberIdsByTid[tid] ?? [];
        final responded = respondedByKey[key] ?? {};
        final names = <String>[];
        for (final pid in members) {
          if (!responded.contains(pid)) {
            final n = allNamesById[pid] ?? unknownUserName;
            if (n.trim().isNotEmpty) names.add(n);
          }
        }
        names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        if (names.isNotEmpty) nietGereageerdByKey[key] = names;
      }
    }

    if (!mounted) return;
    final myName = namesById[targetProfileId] ?? unknownUserName;
    setState(() {
      _myDisplayName = myName;
      _myStatusByMatchKey
        ..clear()
        ..addAll(myStatus);
      _playingNamesByMatchKey
        ..clear()
        ..addAll(playingByKey);
      _coachNamesByMatchKey
        ..clear()
        ..addAll(coachByKey);
      _notPlayingNamesByMatchKey
        ..clear()
        ..addAll(notPlayingByKey);
      _nietGereageerdByMatchKey
        ..clear()
        ..addAll(nietGereageerdByKey);
    });
  }

  Future<void> _loadRefereesForMatches(List<_MatchRef> matches) async {
    if (matches.isEmpty) return;
    final keys = matches.map((m) => m.matchKey).toSet().toList();
    if (keys.isEmpty) return;
    final targetProfileId = AppUserContext.of(context).attendanceProfileId;

    try {
      final linksRes = await _client
          .from('nevobo_home_matches')
          .select('match_key, fluiten_task_id, tellen_task_id')
          .inFilter('match_key', keys);
      final linkRows = (linksRes as List<dynamic>).cast<Map<String, dynamic>>();

      final refereeTaskIdByKey = <String, int>{};
      final tellerTaskIdByKey = <String, int>{};
      final taskIds = <int>{};
      for (final row in linkRows) {
        final key = (row['match_key'] ?? '').toString();
        if (key.isEmpty) continue;
        final fluitenTaskId = (row['fluiten_task_id'] as num?)?.toInt();
        final tellenTaskId = (row['tellen_task_id'] as num?)?.toInt();
        if (fluitenTaskId != null) {
          refereeTaskIdByKey[key] = fluitenTaskId;
          taskIds.add(fluitenTaskId);
        }
        if (tellenTaskId != null) {
          tellerTaskIdByKey[key] = tellenTaskId;
          taskIds.add(tellenTaskId);
        }
      }

      if (taskIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _refereeNamesByMatchKey
            ..clear()
            ..addEntries(keys.map((k) => MapEntry(k, const <String>[])));
          _tellerNamesByMatchKey
            ..clear()
            ..addEntries(keys.map((k) => MapEntry(k, const <String>[])));
        });
        return;
      }

      final signupRes = await _client
          .from('club_task_signups')
          .select('task_id, profile_id')
          .inFilter('task_id', taskIds.toList());
      final signupRows = (signupRes as List<dynamic>).cast<Map<String, dynamic>>();

      final profileIds = <String>{};
      for (final row in signupRows) {
        final pid = row['profile_id']?.toString() ?? '';
        if (pid.isNotEmpty) profileIds.add(pid);
      }
      // Altijd naam van huidig profiel laden (voor correcte weergave na aanmelden fluiten/tellen).
      if (targetProfileId.isNotEmpty) profileIds.add(targetProfileId);
      final namesByProfile = await _loadProfileDisplayNames(profileIds);

      final namesByTaskId = <int, List<String>>{};
      for (final row in signupRows) {
        final taskId = (row['task_id'] as num?)?.toInt();
        final pid = row['profile_id']?.toString() ?? '';
        if (taskId == null || pid.isEmpty) continue;
        final name = (namesByProfile[pid] ?? unknownUserName).trim();
        namesByTaskId.putIfAbsent(taskId, () => []).add(name);
      }
      for (final e in namesByTaskId.entries) {
        e.value.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      }

      final byMatch = <String, List<String>>{};
      final tellerByMatch = <String, List<String>>{};
      for (final key in keys) {
        final refereeTaskId = refereeTaskIdByKey[key];
        final tellerTaskId = tellerTaskIdByKey[key];
        byMatch[key] = refereeTaskId == null
            ? const []
            : (namesByTaskId[refereeTaskId] ?? const []);
        tellerByMatch[key] = tellerTaskId == null
            ? const []
            : (namesByTaskId[tellerTaskId] ?? const []);
      }

      if (!mounted) return;
      setState(() {
        _refereeNamesByMatchKey
          ..clear()
          ..addAll(byMatch);
        _tellerNamesByMatchKey
          ..clear()
          ..addAll(tellerByMatch);
      });
    } catch (_) {
      // best effort: keep UI working without referee data
    }
  }

  Future<void> _loadCancellationsForMatches(List<_MatchRef> matches) async {
    if (matches.isEmpty) {
      if (!mounted) return;
      setState(() {
        _cancelledByMatchKey.clear();
        _cancelReasonByMatchKey.clear();
      });
      return;
    }
    final keys = matches.map((m) => m.matchKey).toSet().toList();

    final teamCodes = matches
        .map((m) => m.teamCode.trim().toUpperCase())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();

    DateTime? minStart;
    DateTime? maxStart;
    for (final m in matches) {
      final utc = m.start.toUtc();
      if (minStart == null || utc.isBefore(minStart)) minStart = utc;
      if (maxStart == null || utc.isAfter(maxStart)) maxStart = utc;
    }

    try {
      const selectWithSummary =
          'match_key, team_code, starts_at, summary, is_cancelled, reason';
      const selectWithoutSummary =
          'match_key, team_code, starts_at, is_cancelled, reason';
      final rowsByKey = <String, Map<String, dynamic>>{};

      Future<void> runSelect(String select, Future<dynamic> Function() query) async {
        try {
          final res = await query();
          for (final r in (res as List<dynamic>).cast<Map<String, dynamic>>()) {
            final k = (r['match_key'] ?? '').toString();
            if (k.isNotEmpty) rowsByKey[k] = r;
          }
        } catch (e) {
          debugPrint('NevoboWedstrijden: cancellations query failed ($select): $e');
        }
      }

      await runSelect(
        selectWithSummary,
        () => _client.from('match_cancellations').select(selectWithSummary).inFilter('match_key', keys),
      );

      if (teamCodes.isNotEmpty) {
        await runSelect(
          selectWithSummary,
          () => _client
              .from('match_cancellations')
              .select(selectWithSummary)
              .inFilter('team_code', teamCodes)
              .eq('is_cancelled', true),
        );
      }

      if (teamCodes.isNotEmpty && minStart != null && maxStart != null) {
        final tightStart = minStart
            .subtract(const Duration(minutes: 2))
            .toUtc()
            .toIso8601String();
        final tightEnd = maxStart
            .add(const Duration(minutes: 2))
            .toUtc()
            .toIso8601String();
        await runSelect(
          selectWithSummary,
          () => _client
              .from('match_cancellations')
              .select(selectWithSummary)
              .inFilter('team_code', teamCodes)
              .gte('starts_at', tightStart)
              .lte('starts_at', tightEnd),
        );
      }

      if (minStart != null && maxStart != null) {
        final wideStart = minStart
            .subtract(const Duration(days: 1))
            .toUtc()
            .toIso8601String();
        final wideEnd = maxStart
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String();
        await runSelect(
          selectWithSummary,
          () => _client
              .from('match_cancellations')
              .select(selectWithSummary)
              .gte('starts_at', wideStart)
              .lte('starts_at', wideEnd),
        );
      }

      if (rowsByKey.isEmpty && teamCodes.isNotEmpty) {
        await runSelect(
          selectWithoutSummary,
          () => _client
              .from('match_cancellations')
              .select(selectWithoutSummary)
              .inFilter('team_code', teamCodes)
              .eq('is_cancelled', true),
        );
      }

      final rows = rowsByKey.values.toList();
      final map = <String, bool>{};
      final reasons = <String, String?>{};
      _overlayLocalCancellations(
        matches: matches,
        rows: rows,
        map: map,
        reasons: reasons,
      );

      _debugLogCancellationMatching(
        matches: matches,
        rows: rows,
        matched: map,
      );

      if (!mounted) return;
      setState(() {
        _cancelledByMatchKey
          ..clear()
          ..addAll(map);
        _cancelReasonByMatchKey
          ..clear()
          ..addAll(reasons);
      });
    } catch (e) {
      debugPrint('NevoboWedstrijden: cancellations load failed: $e');
    }
  }

  void _applyOptimisticMatchUpdate(String key, String? status) {
    final me = _myDisplayName ?? 'Ik';
    final playing = List<String>.from(_playingNamesByMatchKey[key] ?? []);
    final coaches = List<String>.from(_coachNamesByMatchKey[key] ?? []);
    final notPlaying = List<String>.from(_notPlayingNamesByMatchKey[key] ?? []);
    playing.remove(me);
    coaches.remove(me);
    notPlaying.remove(me);
    if (status == 'playing') {
      playing.add(me);
      playing.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } else if (status == 'coach') {
      coaches.add(me);
      coaches.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } else if (status == 'not_playing') {
      notPlaying.add(me);
      notPlaying.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    if (status == 'afgemeld') {
      _myStatusByMatchKey[key] = 'afgemeld';
      final ng = List<String>.from(_nietGereageerdByMatchKey[key] ?? []);
      ng.remove(me);
      _nietGereageerdByMatchKey[key] = ng;
    } else if (status == null) {
      _myStatusByMatchKey.remove(key);
    } else {
      _myStatusByMatchKey[key] = status;
      // Wie reageert (incl. afgemeld) verdwijnt uit "niet gereageerd"
      final ng = List<String>.from(_nietGereageerdByMatchKey[key] ?? []);
      ng.remove(me);
      _nietGereageerdByMatchKey[key] = ng;
    }
    _playingNamesByMatchKey[key] = playing;
    _coachNamesByMatchKey[key] = coaches;
    _notPlayingNamesByMatchKey[key] = notPlaying;
  }

  /// Bepaal of gebruiker als trainer/coach wordt aangemeld voor dit team (anders speler).
  bool _isTrainerOrCoachForTeamCode(String teamCode) {
    try {
      final ctx = AppUserContext.of(context);
      final code = teamCode.trim().toUpperCase();
      for (final m in ctx.memberships) {
        final extracted = NevoboApi.extractCodeFromTeamName(m.teamName);
        if (extracted != null && extracted.toUpperCase() == code) {
          return m.canManageTeam;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _setMyStatus({
    required _MatchRef match,
    required String? status, // null = clear
  }) async {
    if (_cancelledByMatchKey[match.matchKey] == true) {
      if (!mounted) return;
      showTopMessage(context, 'Deze wedstrijd is geannuleerd.', isError: true);
      return;
    }
    final user = _client.auth.currentUser;
    if (user == null) return;
    final ctx = AppUserContext.of(context);
    final targetProfileId = ctx.attendanceProfileId;
    final key = match.matchKey;

    final prevStatus = _myStatusByMatchKey[key];
    final prevPlaying = List<String>.from(_playingNamesByMatchKey[key] ?? []);
    final prevCoaches = List<String>.from(_coachNamesByMatchKey[key] ?? []);
    final prevNotPlaying = List<String>.from(_notPlayingNamesByMatchKey[key] ?? []);

    _applyOptimisticMatchUpdate(key, status);
    if (!mounted) return;
    setState(() {});

    try {
      if (status != null) {
        // status = playing | coach | not_playing | afgemeld
        await _client.from('match_availability').upsert(
          {
            'match_key': key,
            'team_code': match.teamCode,
            'starts_at': match.start.toUtc().toIso8601String(),
            'summary': match.summary,
            'location': match.location,
            'profile_id': targetProfileId,
            'status': status,
          },
          onConflict: 'match_key,profile_id',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (prevStatus == null) {
          _myStatusByMatchKey.remove(key);
        } else {
          _myStatusByMatchKey[key] = prevStatus;
        }
        _playingNamesByMatchKey[key] = prevPlaying;
        _coachNamesByMatchKey[key] = prevCoaches;
        _notPlayingNamesByMatchKey[key] = prevNotPlaying;
      });
      showTopMessage(context, 'Kon status niet opslaan: $e', isError: true);
    }
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _leaderboardByTeam.clear();
      _errorByTeam.clear();
      _matchesByTeam.clear();
      _matchErrorByTeam.clear();
      _nietGereageerdByMatchKey.clear();
    });

    try {
      final codes = widget.teamCodes
          .map((c) => c.trim().toUpperCase().replaceAll(' ', ''))
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList()
        ..sort(NevoboApi.compareTeamCodes);

      final teams = codes
          .map(NevoboApi.teamFromCode)
          .whereType<NevoboTeam>()
          .toList()
        ..sort(NevoboApi.compareTeams);

      setState(() {
        _teams = teams;
        _loading = false;
      });

      // Fetch matches + standings in parallel (best effort per team)
      await Future.wait(
        teams.map((team) async {
          try {
            final matches = await NevoboApi.fetchMatchesForTeam(team: team);
            if (!mounted) return;
            setState(() => _matchesByTeam[team.code] = matches);
          } catch (e) {
            if (!mounted) return;
            setState(() => _matchErrorByTeam[team.code] = e.toString());
          }

          try {
            final standings = await NevoboApi.fetchStandingsForTeam(team: team);
            if (!mounted) return;
            setState(() => _leaderboardByTeam[team.code] = standings);
            // Sync teamnaam uit API naar Supabase (geen team_id in deze tab).
            for (final s in standings) {
              if (s.teamName.trim().toLowerCase().contains('minerva')) {
                final extracted = NevoboApi.extractCodeFromTeamName(s.teamName);
                if (extracted != null &&
                    (extracted == team.code ||
                        (extracted.startsWith('XR') && team.code.startsWith('MR') &&
                            extracted.substring(2) == team.code.substring(2)) ||
                        (extracted.startsWith('MR') && team.code.startsWith('XR') &&
                            extracted.substring(2) == team.code.substring(2)))) {
                  NevoboApi.syncTeamNameFromNevobo(
                    client: _client,
                    teamId: null,
                    nevoboCode: team.code,
                    teamName: s.teamName,
                  );
                  break;
                }
              }
            }
          } catch (e) {
            if (!mounted) return;
            setState(() => _errorByTeam[team.code] = e.toString());
          }
        }),
      );

      // Load availability for upcoming matches
      final now = DateTime.now();
      final matchRefs = <_MatchRef>[];
      for (final team in teams) {
        final matches = _matchesByTeam[team.code] ?? const [];
        for (final m in matches) {
          final start = m.start;
          if (start == null) continue;
          if (start.isBefore(now.subtract(const Duration(hours: 2)))) continue;
          matchRefs.add(
            _MatchRef(
              matchKey: _matchKey(teamCode: team.code, start: start),
              teamCode: team.code,
              start: start,
              summary: m.summary,
              location: (m.location ?? '').trim(),
            ),
          );
        }
      }
      if (mounted) setState(() => _upcomingMatchRefs = matchRefs);
      // Nevobo-wedstrijden blijven de bron; lokale annuleringen overlayen daarna.
      await _loadCancellationsForMatches(matchRefs);
      await _loadAvailabilityForMatches(matchRefs);
      await _loadRefereesForMatches(matchRefs);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon Nevobo data niet laden.\n$e';
        _loading = false;
      });
    }
  }

  Future<void> refresh() async {
    await _loadAll();
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  static const List<String> _weekdayNames = [
    'maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag',
  ];
  static const List<String> _monthNames = [
    'januari', 'februari', 'maart', 'april', 'mei', 'juni', 'juli',
    'augustus', 'september', 'oktober', 'november', 'december',
  ];

  String _formatDateHeader(DateTime dt) {
    final d = dt.toLocal();
    final weekday = _weekdayNames[d.weekday - 1];
    final month = _monthNames[d.month - 1];
    return '$weekday ${d.day} $month ${d.year}';
  }

  String _formatRoleNames(List<String> names) {
    if (names.isEmpty) return 'Nog niet ingedeeld';
    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} +${names.length - 2}';
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.onBackground,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
    );
  }

  Widget _buildMatchAttendanceCategory(String label, int count, List<String> names, bool expanded, TextStyle labelStyle) {
    if (count == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $count', style: labelStyle),
        if (expanded && names.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: names.map((n) => Text('- $n', style: labelStyle.copyWith(fontSize: 12))).toList(),
            ),
          ),
      ],
    );
  }

  /// Eén wedstrijdrij (tijd, teamlabel, samenvatting, locatie, aanwezigheid). Voor weergave per dag.
  Widget _buildMatchRow(_MatchRef ref, String teamDisplayLabel) {
    final key = ref.matchKey;
    final isCancelled = _cancelledByMatchKey[key] == true;
    final cancelReason = _cancelReasonByMatchKey[key];
    final myStatus = _myStatusByMatchKey[key];
    final isPresent = myStatus == 'playing' || myStatus == 'coach';
    final isNotPlaying = myStatus == 'not_playing';
    final isAfgemeld = myStatus == 'afgemeld';
    final playing = _playingNamesByMatchKey[key] ?? const [];
    final coaches = _coachNamesByMatchKey[key] ?? const [];
    final notPlaying = _notPlayingNamesByMatchKey[key] ?? const [];
    final nietGereageerd = _nietGereageerdByMatchKey[key] ?? const [];
    final referees = _refereeNamesByMatchKey[key] ?? const [];
    final tellers = _tellerNamesByMatchKey[key] ?? const [];
    final hasCounts = playing.isNotEmpty || coaches.isNotEmpty || notPlaying.isNotEmpty || nietGereageerd.isNotEmpty;
    final expanded = _expandedMatchKeys.contains(key);
    final summaryColor =
        isCancelled ? AppColors.textSecondary : AppColors.onBackground;
    final teamLabelColor =
        isCancelled ? AppColors.textSecondary : AppColors.primary;
    final metaStyle = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 13,
    );
    final disabledMetaStyle = metaStyle.copyWith(
      color: AppColors.textSecondary.withValues(alpha: isCancelled ? 0.85 : 1),
    );

    return Opacity(
      opacity: isCancelled ? 0.72 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDateTime(ref.start),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            teamDisplayLabel,
            style: TextStyle(
              color: teamLabelColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: _buildMatchSummaryText(
                  NevoboApi.displayTeamName(ref.summary),
                  style: TextStyle(
                    color: summaryColor,
                    fontWeight: FontWeight.w800,
                    decoration: isCancelled
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                  teamCode: ref.teamCode,
                ),
              ),
              if (isCancelled)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Text(
                    'Geannuleerd',
                    style: TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          if (ref.location.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              ref.location,
              style: disabledMetaStyle,
            ),
            MatchTravelRow(
              location: ref.location,
              textDecoration: isCancelled ? TextDecoration.lineThrough : null,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Scheidsrechter: ${_formatRoleNames(referees)}',
            style: disabledMetaStyle,
          ),
          const SizedBox(height: 2),
          Text(
            'Teller: ${_formatRoleNames(tellers)}',
            style: disabledMetaStyle,
          ),
          if (isCancelled && cancelReason != null && cancelReason.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Reden: $cancelReason',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              isPresent
                  ? FilledButton(
                      onPressed: isCancelled
                          ? null
                          : () => _setMyStatus(
                                match: ref,
                                status: _isTrainerOrCoachForTeamCode(ref.teamCode)
                                    ? 'coach'
                                    : 'playing',
                              ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        minimumSize: const Size(0, 44),
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                      child: const Text('Aanmelden'),
                    )
                  : OutlinedButton(
                      onPressed: isCancelled
                          ? null
                          : () => _setMyStatus(
                                match: ref,
                                status: _isTrainerOrCoachForTeamCode(ref.teamCode)
                                    ? 'coach'
                                    : 'playing',
                              ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        minimumSize: const Size(0, 44),
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                      child: const Text('Aanmelden'),
                    ),
              const SizedBox(width: 6),
              isNotPlaying
                  ? FilledButton(
                      onPressed: isCancelled
                          ? null
                          : () => _setMyStatus(match: ref, status: 'not_playing'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.amber.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        minimumSize: const Size(0, 44),
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                      child: const Text('Niet spelend'),
                    )
                  : OutlinedButton(
                      onPressed: isCancelled
                          ? null
                          : () => _setMyStatus(match: ref, status: 'not_playing'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        minimumSize: const Size(0, 44),
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                      child: const Text('Niet spelend'),
                    ),
              const SizedBox(width: 6),
              isAfgemeld
                  ? FilledButton(
                      onPressed: isCancelled
                          ? null
                          : () => _confirmAndSetAfwezig(match: ref),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        minimumSize: const Size(0, 44),
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                      child: const Text('Afmelden'),
                    )
                  : OutlinedButton(
                      onPressed: isCancelled
                          ? null
                          : () => _confirmAndSetAfwezig(match: ref),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        minimumSize: const Size(0, 44),
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                      child: const Text('Afmelden'),
                    ),
            ],
          ),
          if (hasCounts) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () {
                setState(() {
                  if (expanded) {
                    _expandedMatchKeys.remove(key);
                  } else {
                    _expandedMatchKeys.add(key);
                  }
                });
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _buildMatchAttendanceCategory(
                    'Spelend',
                    playing.length + coaches.length,
                    [...playing, ...coaches],
                    expanded,
                    const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  if (playing.isNotEmpty || coaches.isNotEmpty) const SizedBox(height: 4),
                  _buildMatchAttendanceCategory(
                    'Niet spelend',
                    notPlaying.length,
                    notPlaying,
                    expanded,
                    TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 13),
                  ),
                  if (notPlaying.isNotEmpty) const SizedBox(height: 4),
                  _buildMatchAttendanceCategory(
                    'Niet gereageerd',
                    nietGereageerd.length,
                    nietGereageerd,
                    expanded,
                    TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.7), fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmAndSetAfwezig({required _MatchRef match}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Afmelden bevestigen'),
        content: const Text(
          'Weet je zeker dat je je wilt afmelden voor deze wedstrijd?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuleren'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Afmelden'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      _setMyStatus(match: match, status: 'afgemeld');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);
    if (widget.teamCodes.isEmpty) {
      final hasTeams = ctx.memberships.isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hasTeams
                    ? 'Je bent wel gekoppeld aan een team, maar ik kan geen Nevobo-teamcode afleiden uit je teamnaam.\n'
                        'Laat TC je teamnaam controleren (bijv. “Heren 1” of “HS1”).'
                    : 'Je bent nog niet gekoppeld aan een team.\n'
                        'Koppel eerst je account aan een team om wedstrijden te zien.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (hasTeams) ...[
                const SizedBox(height: 10),
                GlassCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Gekoppelde teams',
                        style: TextStyle(
                          color: AppColors.onBackground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...ctx.memberships.map((m) {
                        final naam = m.displayLabel.trim().isNotEmpty
                            ? m.displayLabel
                            : '(naam ontbreekt)';
                        return Text(
                          '- $naam',
                          style: const TextStyle(color: AppColors.textSecondary),
                        );
                      }),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: ctx.reloadUserContext == null
                    ? null
                    : () async => ctx.reloadUserContext!.call(),
                icon: const Icon(Icons.refresh),
                label: const Text('Opnieuw laden'),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading && _teams.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      );
    }

    if (_teams.isEmpty) {
      return const Center(
        child: Text(
          'Geen teams gekoppeld voor leaderboards.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    // Filter op geselecteerde teams
    final displayedMatchRefs = _upcomingMatchRefs
        .where((r) => _selectedTeamCodes.contains(r.teamCode))
        .toList();

    // Wedstrijden gegroepeerd per dag (lokale datum) voor "Wedstrijden per dag".
    final matchesByDate = <DateTime, List<_MatchRef>>{};
    for (final ref in displayedMatchRefs) {
      final local = ref.start.toLocal();
      final dateKey = DateTime(local.year, local.month, local.day);
      matchesByDate.putIfAbsent(dateKey, () => []).add(ref);
    }
    for (final list in matchesByDate.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }
    final sortedDates = matchesByDate.keys.toList()..sort();

    // Teamfilter: aanvinken welke teams te tonen (alleen bij 2+ teams)
    final showTeamFilter = _teams.length >= 2;

    final listChildren = <Widget>[
      if (showTeamFilter) ...[
        _buildSectionHeader('Toon wedstrijden van'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _teams.map((team) {
            final selected = _selectedTeamCodes.contains(team.code);
            return FilterChip(
              label: Text(
                NevoboApi.displayTeamCode(team.code),
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.background,
                  fontWeight: FontWeight.w700,
                ),
              ),
              selected: selected,
              onSelected: (_) => _toggleTeamSelection(team.code),
              backgroundColor: AppColors.darkBlue,
              selectedColor: AppColors.darkBlue,
              side: BorderSide(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.95)
                    : AppColors.darkBlue,
                width: selected ? 1.6 : 1.0,
              ),
              checkmarkColor: AppColors.primary,
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
      _buildSectionHeader('Wedstrijden per dag'),
      if (sortedDates.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 16),
          child: Text(
            'Geen komende wedstrijden.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        )
      else
        ...sortedDates.expand((date) => [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Text(
                  _formatDateHeader(date),
                  style: const TextStyle(
                    color: AppColors.darkBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final ref in matchesByDate[date]!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: _buildMatchRow(
                          ref,
                          _teamDisplayLabelForCode(ref.teamCode),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ]),
    ];

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        await ctx.reloadUserContext?.call();
        await _loadAll();
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: listChildren,
      ),
    );
  }
}

class _MatchRef {
  final String matchKey;
  final String teamCode;
  final DateTime start;
  final String summary;
  final String location;

  const _MatchRef({
    required this.matchKey,
    required this.teamCode,
    required this.start,
    required this.summary,
    required this.location,
  });
}