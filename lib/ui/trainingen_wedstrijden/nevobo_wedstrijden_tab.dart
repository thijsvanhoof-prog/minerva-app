import 'package:flutter/material.dart';
import 'package:minerva_app/ui/components/glass_card.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:minerva_app/ui/display_name_overrides.dart' show applyDisplayNameOverrides, unknownUserName;
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NevoboWedstrijdenTab extends StatefulWidget {
  final List<String> teamCodes; // e.g. ["HS1","DS1"]

  const NevoboWedstrijdenTab({
    super.key,
    required this.teamCodes,
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

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  bool _isMinervaTeamName(String name) {
    final s = name.trim().toLowerCase();
    return s.contains('minerva');
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

  /// Of deze standing-entry exact bij [teamCode] hoort (bijv. "Minerva HS 2" voor HS2).
  bool _standingMatchesTeam(NevoboStandingEntry entry, String teamCode) {
    if (!_isMinervaTeamName(entry.teamName)) return false;
    final extracted = NevoboApi.extractCodeFromTeamName(entry.teamName);
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

  /// Fallback: match op teamPath als de naam geen "Minerva" bevat (API kan andere naam geven).
  /// Maximaal één team per leaderboard wordt gehighlight (de sectie-team).
  bool _standingMatchesTeamByPath(NevoboStandingEntry entry, String teamCode) {
    final resolved = NevoboApi.resolvedTeamPath(teamCode);
    if (resolved == null || resolved.isEmpty || entry.teamPath == null || entry.teamPath!.isEmpty) return false;
    final a = entry.teamPath!.trim().toLowerCase().replaceAll(r'\', '/');
    final b = resolved.trim().toLowerCase().replaceAll(r'\', '/');
    return a == b;
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
    return 'nevobo_match:${teamCode.trim().toUpperCase()}:${start.toUtc().toIso8601String()}';
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

    // Fetch all availability rows for displayed matches
    List<Map<String, dynamic>> rows = const [];
    try {
      final res = await _client
          .from('match_availability')
          .select('match_key, profile_id, status')
          .inFilter('match_key', keys);
      rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      // Table missing or RLS; leave empty
      return;
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

      if (pid == targetProfileId && (status == 'playing' || status == 'coach' || status == 'not_playing')) {
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
    if (matches.isEmpty) return;
    final keys = matches.map((m) => m.matchKey).toSet().toList();
    if (keys.isEmpty) return;

    try {
      final res = await _client
          .from('match_cancellations')
          .select('match_key, is_cancelled, reason')
          .inFilter('match_key', keys);
      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final map = <String, bool>{};
      final reasons = <String, String?>{};
      for (final r in rows) {
        final k = (r['match_key'] ?? '').toString();
        if (k.isEmpty) continue;
        map[k] = r['is_cancelled'] == true;
        final reason = (r['reason'] ?? '').toString().trim();
        reasons[k] = reason.isEmpty ? null : reason;
      }
      if (!mounted) return;
      setState(() {
        _cancelledByMatchKey
          ..clear()
          ..addAll(map);
        _cancelReasonByMatchKey
          ..clear()
          ..addAll(reasons);
      });
    } catch (_) {
      // Table missing or RLS; ignore (best-effort)
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
    if (status == null) {
      _myStatusByMatchKey.remove(key);
    } else {
      _myStatusByMatchKey[key] = status;
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

  String _matchAttendanceSummary(List<String> playing, List<String> coaches, List<String> notPlaying) {
    final parts = <String>[];
    if (coaches.isNotEmpty) parts.add('Trainer/coach: ${coaches.length}');
    if (playing.isNotEmpty) parts.add('Speler(s): ${playing.length}');
    if (notPlaying.isNotEmpty) parts.add('Afgemeld: ${notPlaying.length}');
    return parts.isEmpty ? '' : parts.join(' • ');
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
      if (status == null) {
        await _client
            .from('match_availability')
            .delete()
            .eq('match_key', key)
            .eq('profile_id', targetProfileId);
      } else {
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

  Future<void> _setMyStatusForAllMatches(String? status) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    if (_upcomingMatchRefs.isEmpty) return;
    final ctx = AppUserContext.of(context);
    final targetProfileId = ctx.attendanceProfileId;

    final prevStatus = Map<String, String?>.from(_myStatusByMatchKey);
    final prevPlaying = <String, List<String>>{
      for (final e in _playingNamesByMatchKey.entries) e.key: List<String>.from(e.value),
    };
    final prevCoaches = <String, List<String>>{
      for (final e in _coachNamesByMatchKey.entries) e.key: List<String>.from(e.value),
    };
    final prevNotPlaying = <String, List<String>>{
      for (final e in _notPlayingNamesByMatchKey.entries) e.key: List<String>.from(e.value),
    };

    for (final m in _upcomingMatchRefs) {
      if (_cancelledByMatchKey[m.matchKey] == true) continue;
      _applyOptimisticMatchUpdate(m.matchKey, status);
    }
    if (!mounted) return;
    setState(() {});

    try {
      final keys = _upcomingMatchRefs
          .where((m) => _cancelledByMatchKey[m.matchKey] != true)
          .map((m) => m.matchKey)
          .toSet()
          .toList();
      if (status == null) {
        await _client
            .from('match_availability')
            .delete()
            .eq('profile_id', targetProfileId)
            .inFilter('match_key', keys);
      } else {
        final rows = _upcomingMatchRefs
            .where((m) => _cancelledByMatchKey[m.matchKey] != true)
            .map((m) => {
          'match_key': m.matchKey,
          'team_code': m.teamCode,
          'starts_at': m.start.toUtc().toIso8601String(),
          'summary': m.summary,
          'location': m.location,
          'profile_id': targetProfileId,
          'status': status,
        })
            .toList();
        await _client.from('match_availability').upsert(
          rows,
          onConflict: 'match_key,profile_id',
        );
      }
      if (!mounted) return;
      final label = status == null ? 'Afwezig' : (status == 'not_playing' ? 'Afgemeld' : 'Aanwezig');
      showTopMessage(
        context,
        '$label voor ${_upcomingMatchRefs.length} wedstrijd(en) opgeslagen.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _myStatusByMatchKey.clear();
        for (final e in prevStatus.entries) {
          if (e.value != null) _myStatusByMatchKey[e.key] = e.value!;
        }
        _playingNamesByMatchKey
          ..clear()
          ..addAll(prevPlaying);
        _coachNamesByMatchKey
          ..clear()
          ..addAll(prevCoaches);
        _notPlayingNamesByMatchKey
          ..clear()
          ..addAll(prevNotPlaying);
      });
      showTopMessage(context, 'Kon status niet opslaan: $e', isError: true);
    }
  }

  /// Aanwezig voor alle wedstrijden: per match coach of playing op basis van team.
  Future<void> _setMyStatusForAllMatchesAanwezig() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    if (_upcomingMatchRefs.isEmpty) return;
    final ctx = AppUserContext.of(context);
    final targetProfileId = ctx.attendanceProfileId;

    final prevStatus = Map<String, String?>.from(_myStatusByMatchKey);
    final prevPlaying = <String, List<String>>{
      for (final e in _playingNamesByMatchKey.entries) e.key: List<String>.from(e.value),
    };
    final prevCoaches = <String, List<String>>{
      for (final e in _coachNamesByMatchKey.entries) e.key: List<String>.from(e.value),
    };

    for (final m in _upcomingMatchRefs) {
      final status = _isTrainerOrCoachForTeamCode(m.teamCode) ? 'coach' : 'playing';
      _applyOptimisticMatchUpdate(m.matchKey, status);
    }
    if (!mounted) return;
    setState(() {});

    try {
      final rows = _upcomingMatchRefs.map((m) {
        final status = _isTrainerOrCoachForTeamCode(m.teamCode) ? 'coach' : 'playing';
        return {
          'match_key': m.matchKey,
          'team_code': m.teamCode,
          'starts_at': m.start.toUtc().toIso8601String(),
          'summary': m.summary,
          'location': m.location,
          'profile_id': targetProfileId,
          'status': status,
        };
      }).toList();
      await _client.from('match_availability').upsert(
        rows,
        onConflict: 'match_key,profile_id',
      );
      if (!mounted) return;
      showTopMessage(
        context,
        'Aanwezig voor ${_upcomingMatchRefs.length} wedstrijd(en) opgeslagen.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _myStatusByMatchKey.clear();
        for (final e in prevStatus.entries) {
          if (e.value != null) _myStatusByMatchKey[e.key] = e.value!;
        }
        _playingNamesByMatchKey
          ..clear()
          ..addAll(prevPlaying);
        _coachNamesByMatchKey
          ..clear()
          ..addAll(prevCoaches);
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

  /// Kaart met alleen standen voor één team (geen wedstrijden).
  Widget _buildStandenCard(NevoboTeam team) {
    final leaderboard = _leaderboardByTeam[team.code];
    final error = _errorByTeam[team.code];

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.darkBlue,
              borderRadius: BorderRadius.circular(AppColors.cardRadius),
            ),
            child: Text(
              _teamDisplayLabelForCode(team.code),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(height: 12),
          if (error != null)
            Text(error, style: const TextStyle(color: AppColors.error))
          else if (leaderboard == null)
            const Text(
              'Laden...',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else if (leaderboard.isEmpty)
            const Text(
              'Geen leaderboard gevonden.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const SizedBox(width: 28, child: Text('', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600))),
                      const Expanded(child: Text('Team', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600))),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 36,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: const Text('Wedstr.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 36,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: const Text('Punten', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
                ...leaderboard.map((s) {
                  final isOurTeam = _standingMatchesTeam(s, team.code) || _standingMatchesTeamByPath(s, team.code);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: isOurTeam
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isOurTeam
                            ? Border.all(
                                color: AppColors.primary.withValues(alpha: 0.35),
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text(
                              s.position > 0 ? '${s.position}.' : '-',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              NevoboApi.displayTeamName(s.teamName),
                              style: TextStyle(
                                color: isOurTeam ? AppColors.primary : AppColors.onBackground,
                                fontWeight: isOurTeam ? FontWeight.w900 : FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${s.played}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${s.points}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }

  /// Eén wedstrijdrij (tijd, teamlabel, samenvatting, locatie, aanwezigheid). Voor weergave per dag.
  Widget _buildMatchRow(_MatchRef ref, String teamDisplayLabel) {
    final key = ref.matchKey;
    final isCancelled = _cancelledByMatchKey[key] == true;
    final cancelReason = _cancelReasonByMatchKey[key];
    final myStatus = _myStatusByMatchKey[key];
    final isPresent = myStatus == 'playing' || myStatus == 'coach';
    final playing = _playingNamesByMatchKey[key] ?? const [];
    final coaches = _coachNamesByMatchKey[key] ?? const [];
    final notPlaying = _notPlayingNamesByMatchKey[key] ?? const [];
    final referees = _refereeNamesByMatchKey[key] ?? const [];
    final tellers = _tellerNamesByMatchKey[key] ?? const [];
    final hasCounts = playing.isNotEmpty || coaches.isNotEmpty || notPlaying.isNotEmpty;
    final expanded = _expandedMatchKeys.contains(key);
    final summary = _matchAttendanceSummary(playing, coaches, notPlaying);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDateTime(ref.start),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            teamDisplayLabel,
            style: TextStyle(
              color: AppColors.primary,
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
                    color: AppColors.onBackground,
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Scheidsrechter: ${_formatRoleNames(referees)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Teller: ${_formatRoleNames(tellers)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          if (isCancelled && cancelReason != null && cancelReason.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Reden: $cancelReason',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              isPresent
                  ? FilledButton.icon(
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
                      ),
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text('Aanmelden'),
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
                      child: const Text('Aanmelden'),
                    ),
              isPresent
                  ? OutlinedButton.icon(
                      onPressed: isCancelled
                          ? null
                          : () => _confirmAndSetAfwezig(match: ref),
                      icon: const Icon(Icons.person_off, size: 18),
                      label: const Text('Afmelden'),
                    )
                  : FilledButton.icon(
                      onPressed: isCancelled
                          ? null
                          : () => _confirmAndSetAfwezig(match: ref),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.textSecondary.withValues(alpha: 0.25),
                        foregroundColor: AppColors.onBackground,
                      ),
                      icon: const Icon(Icons.person_off, size: 18),
                      label: const Text('Afmelden'),
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
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    summary,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 4),
              if (coaches.isNotEmpty)
                Text(
                  'Trainer/coach: ${coaches.join(', ')}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              if (coaches.isNotEmpty && (playing.isNotEmpty || notPlaying.isNotEmpty)) const SizedBox(height: 2),
              if (playing.isNotEmpty)
                Text(
                  'Speler(s): ${playing.join(', ')}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              if (playing.isNotEmpty && notPlaying.isNotEmpty) const SizedBox(height: 2),
              if (notPlaying.isNotEmpty)
                Text(
                  'Afgemeld: ${notPlaying.join(', ')}',
                  style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 13),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildVoorAlleWedstrijdenBar() {
    final active = _upcomingMatchRefs.where((m) => _cancelledByMatchKey[m.matchKey] != true).toList();
    final allPresent = active.every((m) {
      final s = _myStatusByMatchKey[m.matchKey];
      return s == 'playing' || s == 'coach';
    });
    final anyPresent = active.any((m) {
      final s = _myStatusByMatchKey[m.matchKey];
      return s == 'playing' || s == 'coach';
    });

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.darkBlue,
              borderRadius: BorderRadius.circular(AppColors.cardRadius),
            ),
            child: Text(
              'Voor alle wedstrijden',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${active.length} wedstrijd(en)',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              allPresent
                  ? FilledButton.icon(
                      onPressed: _setMyStatusForAllMatchesAanwezig,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text('Aanmelden'),
                    )
                  : OutlinedButton(
                      onPressed: _setMyStatusForAllMatchesAanwezig,
                      child: const Text('Aanmelden'),
                    ),
              anyPresent
                  ? OutlinedButton.icon(
                      onPressed: () => _confirmAndSetAfwezigVoorAlleWedstrijden(),
                      icon: const Icon(Icons.person_off, size: 18),
                      label: const Text('Afmelden'),
                    )
                  : FilledButton.icon(
                      onPressed: () => _confirmAndSetAfwezigVoorAlleWedstrijden(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.textSecondary.withValues(alpha: 0.25),
                        foregroundColor: AppColors.onBackground,
                      ),
                      icon: const Icon(Icons.person_off, size: 18),
                      label: const Text('Afmelden'),
                    ),
            ],
          ),
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
      _setMyStatus(match: match, status: 'not_playing');
    }
  }

  Future<void> _confirmAndSetAfwezigVoorAlleWedstrijden() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Afmelden bevestigen'),
        content: const Text(
          'Weet je zeker dat je je wilt afmelden voor alle wedstrijden?',
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
      _setMyStatusForAllMatches('not_playing');
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

    final showBulkBar = _upcomingMatchRefs.isNotEmpty;

    // Wedstrijden gegroepeerd per dag (lokale datum) voor "Wedstrijden per dag".
    final matchesByDate = <DateTime, List<_MatchRef>>{};
    for (final ref in _upcomingMatchRefs) {
      final local = ref.start.toLocal();
      final dateKey = DateTime(local.year, local.month, local.day);
      matchesByDate.putIfAbsent(dateKey, () => []).add(ref);
    }
    for (final list in matchesByDate.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }
    final sortedDates = matchesByDate.keys.toList()..sort();

    final listChildren = <Widget>[
      if (showBulkBar) ...[
        _buildVoorAlleWedstrijdenBar(),
        const SizedBox(height: 10),
      ],
      _buildSectionHeader('Standen'),
      ..._teams.expand((team) => [
            _buildStandenCard(team),
            const SizedBox(height: 10),
          ]),
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
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              GlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final ref in matchesByDate[date]!)
                      _buildMatchRow(
                        ref,
                        _teamDisplayLabelForCode(ref.teamCode),
                      ),
                  ],
                ),
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