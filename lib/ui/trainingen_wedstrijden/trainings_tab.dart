import 'package:flutter/material.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/primary_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart'; // TeamMembership
import 'package:minerva_app/ui/trainingen_wedstrijden/add_training_page.dart';

/// playing = speler, coach = trainer/coach. Aanwezig = één van beide; Afwezig = delete.
enum AttendanceStatus { playing, coach }

class TrainingsTab extends StatefulWidget {
  final List<TeamMembership> manageableTeams;

  const TrainingsTab({
    super.key,
    required this.manageableTeams,
  });

  @override
  State<TrainingsTab> createState() => _TrainingsTabState();
}

class _TrainingsTabState extends State<TrainingsTab> {
  final SupabaseClient _client = Supabase.instance.client;

  late Future<void> _loadFuture;
  List<int> _allowedTeamIds = const [];

  List<Map<String, dynamic>> _trainings = [];
  final Map<int, AttendanceStatus?> _statusBySessionId = {};
  final Map<int, List<String>> _playingBySessionId = {};
  final Map<int, List<String>> _coachBySessionId = {};
  final Set<int> _expandedSessionIds = {};
  String? _myDisplayName;

  bool _selectionMode = false;
  final Set<int> _selectedSessionIds = {};

  @override
  void initState() {
    super.initState();
    // Don't read inherited widgets in initState. We'll load once dependencies are available.
    _loadFuture = Future.value();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ctx = AppUserContext.of(context);
    final next = ctx.memberships.map((m) => m.teamId).toSet().toList()..sort();
    if (_sameIntList(_allowedTeamIds, next)) return;
    _allowedTeamIds = next;
    setState(() {
      _loadFuture = _loadData(teamIds: _allowedTeamIds);
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _loadFuture = _loadData(teamIds: _allowedTeamIds);
    });
    await _loadFuture;
  }

  Future<void> refresh() async {
    await _refresh();
  }

  bool _sameIntList(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _loadData({required List<int> teamIds}) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _trainings = [];
      _statusBySessionId.clear();
      return;
    }

    // Capture before awaits (avoids use_build_context_synchronously lint).
    final targetProfileId = AppUserContext.of(context).attendanceProfileId;

    if (teamIds.isEmpty) {
      _trainings = [];
      _statusBySessionId.clear();
      _playingBySessionId.clear();
      _coachBySessionId.clear();
      return;
    }

    final sessionsRes = await _client
        .from('sessions')
        .select(
          'session_id, team_id, session_type, title, start_datetime, location, created_by, is_cancelled, start_timestamp, end_timestamp',
        )
        .eq('session_type', 'training')
        .inFilter('team_id', teamIds)
        .order('start_datetime', ascending: false);

    final sessions = (sessionsRes as List<dynamic>).cast<Map<String, dynamic>>();
    _trainings = sessions;

    _statusBySessionId.clear();
    _playingBySessionId.clear();
    _coachBySessionId.clear();
    if (_trainings.isEmpty) return;

    final sessionIds =
        _trainings.map((s) => (s['session_id'] as num).toInt()).toList();

    List<Map<String, dynamic>> allRows = const [];
    try {
      final res = await _client
          .from('attendance')
          .select('session_id, person_id, status')
          .inFilter('session_id', sessionIds);
      allRows = (res as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {}

    final profileIds = <String>{};
    for (final r in allRows) {
      final pid = r['person_id']?.toString() ?? '';
      if (pid.isNotEmpty) profileIds.add(pid);
    }
    final namesById = await _loadProfileDisplayNames(profileIds);

    final playingBySid = <int, List<String>>{};
    final coachBySid = <int, List<String>>{};

    for (final r in allRows) {
      final sid = (r['session_id'] as num?)?.toInt();
      if (sid == null) continue;
      final pid = r['person_id']?.toString() ?? '';
      final status = (r['status'] ?? '').toString().trim().toLowerCase();
      final name = pid.isEmpty ? '' : (namesById[pid] ?? _shortId(pid));

      if (pid == targetProfileId) {
        final s = _statusFromString(status);
        if (s != null) _statusBySessionId[sid] = s;
      }
      if (name.trim().isEmpty) continue;
      if (status == 'playing' || status == 'aanwezig') {
        playingBySid.putIfAbsent(sid, () => []).add(name);
      } else if (status == 'coach') {
        coachBySid.putIfAbsent(sid, () => []).add(name);
      }
    }

    for (final e in playingBySid.values) {
      e.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    for (final e in coachBySid.values) {
      e.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }

    if (!mounted) return;
    final myName = namesById[targetProfileId] ?? _shortId(targetProfileId);
    setState(() {
      _myDisplayName = myName;
      _playingBySessionId
        ..clear()
        ..addAll(playingBySid);
      _coachBySessionId
        ..clear()
        ..addAll(coachBySid);
    });
  }

  void _applyOptimisticAttendanceUpdate(int sessionId, AttendanceStatus? effective) {
    final me = _myDisplayName ?? 'Ik';
    final playing = List<String>.from(_playingBySessionId[sessionId] ?? []);
    final coaches = List<String>.from(_coachBySessionId[sessionId] ?? []);
    playing.remove(me);
    coaches.remove(me);
    if (effective == AttendanceStatus.playing) {
      playing.add(me);
      playing.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } else if (effective == AttendanceStatus.coach) {
      coaches.add(me);
      coaches.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    if (effective == null) {
      _statusBySessionId.remove(sessionId);
    } else {
      _statusBySessionId[sessionId] = effective;
    }
    _playingBySessionId[sessionId] = playing;
    _coachBySessionId[sessionId] = coaches;
  }

  String _shortId(String v) =>
      v.length <= 8 ? v : '${v.substring(0, 4)}…${v.substring(v.length - 4)}';

  Future<Map<String, String>> _loadProfileDisplayNames(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final list = ids.toList();

    // Preferred: security definer RPC so names work even with restrictive RLS on profiles.
    try {
      final res = await _client.rpc('get_profile_display_names', params: {'profile_ids': list});
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
        final res = await _client.from('profiles').select(select).inFilter('id', list);
        rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
        break;
      } catch (_) {}
    }
    final map = <String, String>{};
    for (final r in rows) {
      final id = r['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final n = (r['display_name'] ?? r['full_name'] ?? r['name'] ?? r['email'] ?? '')
          .toString()
          .trim();
      map[id] = n.isNotEmpty ? n : _shortId(id);
    }
    return map;
  }

  AttendanceStatus? _statusFromString(String value) {
    switch (value) {
      case 'playing':
        return AttendanceStatus.playing;
      case 'coach':
        return AttendanceStatus.coach;
      case 'aanwezig':
        return AttendanceStatus.playing;
      default:
        return null;
    }
  }

  String _formatRange(dynamic startValue, dynamic endValue) {
    if (startValue == null) return '-';
    final start =
        startValue is DateTime ? startValue : DateTime.tryParse(startValue.toString());
    if (start == null) return startValue.toString();

    DateTime? end =
        endValue is DateTime ? endValue : DateTime.tryParse(endValue?.toString() ?? '');
    end ??= start.add(const Duration(hours: 2));

    final s = start.toLocal();
    final e = end.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${two(s.day)}-${two(s.month)}-${s.year}';
    final st = '${two(s.hour)}:${two(s.minute)}';
    final et = '${two(e.hour)}:${two(e.minute)}';
    return '$date $st – $et';
  }

  bool get _canCreateTrainings {
    final roles = widget.manageableTeams
        .map((m) => m.role.toLowerCase())
        .toList();
    return roles.any((r) => r == 'trainer' || r == 'coach');
  }

  /// Bepaal of gebruiker als trainer/coach wordt aangemeld voor dit team (anders speler).
  bool _isTrainerOrCoachForTeam(int teamId) {
    try {
      final ctx = AppUserContext.of(context);
      for (final m in ctx.memberships) {
        if (m.teamId == teamId) return m.canManageTeam;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  String _attendanceSummary(List<String> playing, List<String> coaches) {
    final parts = <String>[];
    if (coaches.isNotEmpty) parts.add('Trainer/coach: ${coaches.length}');
    if (playing.isNotEmpty) parts.add('Speler(s): ${playing.length}');
    return parts.join(' • ');
  }

  List<Widget> _attendanceNameLists(List<String> playing, List<String> coaches) {
    final out = <Widget>[];
    if (coaches.isNotEmpty) {
      out.add(Text('Trainer/coach: ${coaches.join(', ')}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)));
      out.add(const SizedBox(height: 4));
    }
    if (playing.isNotEmpty) {
      out.add(Text('Speler(s): ${playing.join(', ')}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)));
    }
    return out;
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedSessionIds.clear();
    });
  }

  void _toggleSelected(int sessionId, bool selected) {
    setState(() {
      if (selected) {
        _selectedSessionIds.add(sessionId);
      } else {
        _selectedSessionIds.remove(sessionId);
      }
    });
  }

  Future<void> _bulkDeleteSelected() async {
    if (_selectedSessionIds.isEmpty) return;

    final count = _selectedSessionIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Trainingen verwijderen'),
        content: Text('Weet je zeker dat je $count training(en) wilt verwijderen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _client.from('sessions').delete().inFilter(
          'session_id',
          _selectedSessionIds.toList(),
        );

    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedSessionIds.clear();
    });
    await _refresh();
  }

  Future<void> _openAddTraining() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddTrainingPage(manageableTeams: widget.manageableTeams),
      ),
    );

    if (created == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _updateAttendance(int sessionId, AttendanceStatus? status) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    if (!mounted) return;

    final ctx = AppUserContext.of(context);
    final targetProfileId = ctx.attendanceProfileId;

    final effective = status;

    final prevStatus = _statusBySessionId[sessionId];
    final prevPlaying = List<String>.from(_playingBySessionId[sessionId] ?? []);
    final prevCoaches = List<String>.from(_coachBySessionId[sessionId] ?? []);

    _applyOptimisticAttendanceUpdate(sessionId, effective);
    if (!mounted) return;
    setState(() {});

    try {
      if (effective == null) {
        await _client
            .from('attendance')
            .delete()
            .eq('session_id', sessionId)
            .eq('person_id', targetProfileId);
      } else {
        await _client.from('attendance').upsert(
          {
            'session_id': sessionId,
            'person_id': targetProfileId,
            'status': effective.name,
          },
          onConflict: 'session_id,person_id',
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (prevStatus == null) {
          _statusBySessionId.remove(sessionId);
        } else {
          _statusBySessionId[sessionId] = prevStatus;
        }
        _playingBySessionId[sessionId] = prevPlaying;
        _coachBySessionId[sessionId] = prevCoaches;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);
    if (ctx.memberships.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Je bent nog niet gekoppeld aan een team.\n'
            'Koppel eerst je account aan een team om trainingen te zien.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _canCreateTrainings
          ? FloatingActionButton(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              onPressed: _openAddTraining,
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: FutureBuilder<void>(
          future: _loadFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(
                    height: 280,
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  ),
                ],
              );
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Fout bij laden van trainingen: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.error),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _refresh,
                    child: const Text('Opnieuw laden'),
                  ),
                ],
              );
            }

            if (_trainings.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(height: 40),
                  Text(
                    'Geen trainingen gevonden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: _trainings.length + (_canCreateTrainings ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (_canCreateTrainings && index == 0) {
                  return GlassCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectionMode
                                ? 'Selecteer trainingen'
                                : 'Jouw trainingen',
                            style: const TextStyle(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _toggleSelectionMode,
                          child: Text(_selectionMode ? 'Klaar' : 'Selecteer'),
                        ),
                        if (_selectionMode) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 150,
                            child: PrimaryButton(
                              onPressed: _selectedSessionIds.isEmpty
                                  ? null
                                  : _bulkDeleteSelected,
                              child: Text(
                                'Verwijder (${_selectedSessionIds.length})',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                final session = _trainings[_canCreateTrainings ? index - 1 : index];
                final sessionId = (session['session_id'] as num).toInt();
                final teamId = (session['team_id'] as num?)?.toInt() ?? 0;

                final title = (session['title'] ?? 'Training').toString();
                final location = (session['location'] ?? '').toString();

                final start = session['start_datetime'] ?? session['start_timestamp'];
                final end = session['end_timestamp'];

                final currentStatus = _statusBySessionId[sessionId];
                final isPresent = currentStatus != null;
                final playing = _playingBySessionId[sessionId] ?? [];
                final coaches = _coachBySessionId[sessionId] ?? [];
                final expanded = _expandedSessionIds.contains(sessionId);
                final hasCounts = playing.isNotEmpty || coaches.isNotEmpty;

                return GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (_selectionMode)
                            Checkbox(
                              value: _selectedSessionIds.contains(sessionId),
                              activeColor: AppColors.primary,
                              onChanged: (v) => _toggleSelected(sessionId, v ?? false),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: AppColors.onBackground,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (location.isNotEmpty)
                                  Text(
                                    location,
                                    style: const TextStyle(color: AppColors.textSecondary),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatRange(start, end),
                                  style: const TextStyle(color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton(
                            onPressed: () => _updateAttendance(sessionId, _isTrainerOrCoachForTeam(teamId) ? AttendanceStatus.coach : AttendanceStatus.playing),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isPresent ? AppColors.primary : AppColors.card,
                              foregroundColor: isPresent ? AppColors.background : AppColors.onBackground,
                              side: isPresent ? null : BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                            ),
                            child: const Text('Aanwezig'),
                          ),
                          ElevatedButton(
                            onPressed: () => _updateAttendance(sessionId, null),
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
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              if (expanded) {
                                _expandedSessionIds.remove(sessionId);
                              } else {
                                _expandedSessionIds.add(sessionId);
                              }
                            });
                          },
                          child: Row(
                            children: [
                              Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Text(
                                _attendanceSummary(playing, coaches),
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        if (expanded) ...[
                          const SizedBox(height: 6),
                          ..._attendanceNameLists(playing, coaches),
                        ],
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}