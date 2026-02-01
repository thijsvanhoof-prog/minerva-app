import 'package:flutter/material.dart';
import 'package:minerva_app/ui/components/glass_card.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/components/top_message.dart';
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
  final Map<String, String> _myStatusByMatchKey = {}; // match_key -> playing | coach (null = afwezig)
  final Map<String, List<String>> _playingNamesByMatchKey = {};
  final Map<String, List<String>> _coachNamesByMatchKey = {};
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

  String _matchKey({required String teamCode, required DateTime start}) {
    return 'nevobo_match:${teamCode.trim().toUpperCase()}:${start.toUtc().toIso8601String()}';
  }

  String _shortId(String value) {
    if (value.length <= 8) return value;
    return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
  }

  Future<Map<String, String>> _loadProfileDisplayNames(Set<String> profileIds) async {
    if (profileIds.isEmpty) return {};
    final ids = profileIds.toList();

    // Preferred: security definer RPC so names work even with restrictive RLS on profiles.
    try {
      final res = await _client.rpc('get_profile_display_names', params: {'profile_ids': ids});
      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final map = <String, String>{};
      for (final r in rows) {
        final id = r['profile_id']?.toString() ?? r['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final name = (r['display_name'] ?? '').toString().trim();
        map[id] = name.isNotEmpty ? name : _shortId(id);
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
      map[id] = name.isNotEmpty ? name : _shortId(id);
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
    final namesById = await _loadProfileDisplayNames(profileIds);

    final myStatus = <String, String>{};
    final playingByKey = <String, List<String>>{};
    final coachByKey = <String, List<String>>{};

    for (final r in rows) {
      final key = (r['match_key'] ?? '').toString();
      if (key.isEmpty) continue;
      final pid = r['profile_id']?.toString() ?? '';
      final status = (r['status'] ?? '').toString().trim().toLowerCase();
      final name = pid.isEmpty ? '' : (namesById[pid] ?? _shortId(pid));

      if (pid == targetProfileId && (status == 'playing' || status == 'coach')) {
        myStatus[key] = status;
      }
      if (name.trim().isEmpty) continue;
      if (status == 'playing') {
        playingByKey.putIfAbsent(key, () => []).add(name);
      } else if (status == 'coach') {
        coachByKey.putIfAbsent(key, () => []).add(name);
      }
    }

    for (final entry in playingByKey.entries) {
      entry.value.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    for (final entry in coachByKey.entries) {
      entry.value.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }

    if (!mounted) return;
    final myName = namesById[targetProfileId] ?? _shortId(targetProfileId);
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
    });
  }

  void _applyOptimisticMatchUpdate(String key, String? status) {
    final me = _myDisplayName ?? 'Ik';
    final playing = List<String>.from(_playingNamesByMatchKey[key] ?? []);
    final coaches = List<String>.from(_coachNamesByMatchKey[key] ?? []);
    playing.remove(me);
    coaches.remove(me);
    if (status == 'playing') {
      playing.add(me);
      playing.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } else if (status == 'coach') {
      coaches.add(me);
      coaches.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    if (status == null) {
      _myStatusByMatchKey.remove(key);
    } else {
      _myStatusByMatchKey[key] = status;
    }
    _playingNamesByMatchKey[key] = playing;
    _coachNamesByMatchKey[key] = coaches;
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

  String _matchAttendanceSummary(List<String> playing, List<String> coaches) {
    final parts = <String>[];
    if (coaches.isNotEmpty) parts.add('Trainer/coach: ${coaches.length}');
    if (playing.isNotEmpty) parts.add('Speler(s): ${playing.length}');
    return parts.isEmpty ? '' : parts.join(' • ');
  }

  Future<void> _setMyStatus({
    required _MatchRef match,
    required String? status, // null = clear
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final ctx = AppUserContext.of(context);
    final targetProfileId = ctx.attendanceProfileId;
    final key = match.matchKey;

    final prevStatus = _myStatusByMatchKey[key];
    final prevPlaying = List<String>.from(_playingNamesByMatchKey[key] ?? []);
    final prevCoaches = List<String>.from(_coachNamesByMatchKey[key] ?? []);

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

    for (final m in _upcomingMatchRefs) {
      _applyOptimisticMatchUpdate(m.matchKey, status);
    }
    if (!mounted) return;
    setState(() {});

    try {
      final keys = _upcomingMatchRefs.map((m) => m.matchKey).toSet().toList();
      if (status == null) {
        await _client
            .from('match_availability')
            .delete()
            .eq('profile_id', targetProfileId)
            .inFilter('match_key', keys);
      } else {
        final rows = _upcomingMatchRefs.map((m) => {
          'match_key': m.matchKey,
          'team_code': m.teamCode,
          'starts_at': m.start.toUtc().toIso8601String(),
          'summary': m.summary,
          'location': m.location,
          'profile_id': targetProfileId,
          'status': status,
        }).toList();
        await _client.from('match_availability').upsert(
          rows,
          onConflict: 'match_key,profile_id',
        );
      }
      if (!mounted) return;
      final label = status == null ? 'Afwezig' : 'Aanwezig';
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
      await _loadAvailabilityForMatches(matchRefs);
    } catch (e) {
      setState(() {
        _error = 'Kon Nevobo data niet laden.\n$e';
        _loading = false;
      });
    }
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _buildVoorAlleWedstrijdenBar() {
    final allPresent = _upcomingMatchRefs.every((m) {
      final s = _myStatusByMatchKey[m.matchKey];
      return s == 'playing' || s == 'coach';
    });
    final anyPresent = _upcomingMatchRefs.any((m) {
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
            '${_upcomingMatchRefs.length} wedstrijd(en)',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: _setMyStatusForAllMatchesAanwezig,
                style: ElevatedButton.styleFrom(
                  backgroundColor: allPresent ? AppColors.primary : AppColors.card,
                  foregroundColor: allPresent ? AppColors.background : AppColors.onBackground,
                  side: allPresent ? null : BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                ),
                child: const Text('Aanwezig'),
              ),
              ElevatedButton(
                onPressed: () => _setMyStatusForAllMatches(null),
                style: ElevatedButton.styleFrom(
                  backgroundColor: !anyPresent ? AppColors.primary : AppColors.card,
                  foregroundColor: !anyPresent ? AppColors.background : AppColors.onBackground,
                  side: !anyPresent ? null : BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                ),
                child: const Text('Afwezig'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.teamCodes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Je bent nog niet gekoppeld aan een team.\n'
            'Koppel eerst je account aan een team om wedstrijden te zien.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
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

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadAll,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: (showBulkBar ? 1 : 0) + _teams.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (showBulkBar && index == 0) {
            return _buildVoorAlleWedstrijdenBar();
          }
          final teamIndex = showBulkBar ? index - 1 : index;
          final team = _teams[teamIndex];
          final matches = _matchesByTeam[team.code] ?? const [];
          final matchError = _matchErrorByTeam[team.code];
          final leaderboard = _leaderboardByTeam[team.code];
          final error = _errorByTeam[team.code];

          return GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.darkBlue,
                        borderRadius: BorderRadius.circular(AppColors.cardRadius),
                      ),
                      child: Text(
                        team.code,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    const Spacer(),
                    if (_loading && (leaderboard == null && error == null))
                      const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                const Text(
                  'Leaderboard',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                if (error != null)
                  Text(
                    error,
                    style: const TextStyle(color: AppColors.error),
                  )
                else ...[
                  if (leaderboard == null)
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
                    ...leaderboard.map((s) {
                      final isMinerva = _isMinervaTeamName(s.teamName);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: isMinerva
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: isMinerva
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
                                  s.teamName,
                                  style: TextStyle(
                                    color: AppColors.onBackground,
                                    fontWeight: isMinerva ? FontWeight.w900 : FontWeight.w700,
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
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
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

                const SizedBox(height: 14),

                const Text(
                  'Wedstrijden',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                if (matchError != null)
                  Text(
                    matchError,
                    style: const TextStyle(color: AppColors.error),
                  )
                else if (matches.isEmpty)
                  const Text(
                    'Geen wedstrijden gevonden.',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else ...[
                  ...matches.where((m) {
                    final start = m.start;
                    if (start == null) return false;
                    return start.isAfter(DateTime.now().subtract(const Duration(hours: 2)));
                  }).take(20).map((m) {
                    final start = m.start;
                    if (start == null) return const SizedBox.shrink();
                    final key = _matchKey(teamCode: team.code, start: start);
                    final myStatus = _myStatusByMatchKey[key];
                    final isPresent = myStatus == 'playing' || myStatus == 'coach';
                    final playing = _playingNamesByMatchKey[key] ?? const [];
                    final coaches = _coachNamesByMatchKey[key] ?? const [];
                    final hasCounts = playing.isNotEmpty || coaches.isNotEmpty;
                    final expanded = _expandedMatchKeys.contains(key);
                    final summary = _matchAttendanceSummary(playing, coaches);

                    final ref = _MatchRef(
                      matchKey: key,
                      teamCode: team.code,
                      start: start,
                      summary: m.summary,
                      location: (m.location ?? '').trim(),
                    );

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDateTime(start),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            m.summary,
                            style: const TextStyle(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if ((m.location ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              (m.location ?? '').trim(),
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton(
                                onPressed: () => _setMyStatus(match: ref, status: _isTrainerOrCoachForTeamCode(ref.teamCode) ? 'coach' : 'playing'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isPresent ? AppColors.primary : AppColors.card,
                                  foregroundColor: isPresent ? AppColors.background : AppColors.onBackground,
                                  side: isPresent ? null : BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                                ),
                                child: const Text('Aanwezig'),
                              ),
                              ElevatedButton(
                                onPressed: () => _setMyStatus(match: ref, status: null),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: !isPresent ? AppColors.primary : AppColors.card,
                                  foregroundColor: !isPresent ? AppColors.background : AppColors.onBackground,
                                  side: !isPresent ? null : BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                                ),
                                child: const Text('Afwezig'),
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
                                  Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.textSecondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    summary,
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
                              if (coaches.isNotEmpty && playing.isNotEmpty) const SizedBox(height: 2),
                              if (playing.isNotEmpty)
                                Text(
                                  'Speler(s): ${playing.join(', ')}',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                ),
                            ],
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          );
        },
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