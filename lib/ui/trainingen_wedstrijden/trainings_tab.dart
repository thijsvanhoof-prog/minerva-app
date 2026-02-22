import 'package:flutter/material.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/primary_button.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart'; // TeamMembership
import 'package:minerva_app/ui/display_name_overrides.dart' show applyDisplayNameOverrides, unknownUserName;
import 'package:minerva_app/ui/trainingen_wedstrijden/add_training_page.dart';

/// playing = speler, coach = trainer/coach, afgemeld = afgemeld. Aanmelden = playing/coach; Afmelden = status afgemeld.
enum AttendanceStatus { playing, coach, afgemeld }

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
  final Map<int, List<String>> _afgemeldBySessionId = {};
  final Set<int> _expandedSessionIds = {};
  /// Welke team-accordions open staan (teamId); bij één team altijd uitgeklapt.
  final Set<int> _expandedTrainingTeamIds = {};
  bool _didInitExpandedTraining = false;
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
    // Also reload memberships/committees so newly linked teams show up immediately.
    try {
      await AppUserContext.of(context).reloadUserContext?.call();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loadFuture = _loadData(teamIds: _allowedTeamIds);
    });
    await _loadFuture;
    if (!mounted) return;
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
        .order('start_datetime', ascending: true);

    final sessions = (sessionsRes as List<dynamic>).cast<Map<String, dynamic>>();
    // Sorteer: eerst volgende datum bovenaan, verst onderaan.
    sessions.sort((a, b) {
      final rawA = a['start_datetime'] ?? a['start_timestamp'];
      final rawB = b['start_datetime'] ?? b['start_timestamp'];
      final startA = rawA is DateTime ? rawA : DateTime.tryParse(rawA?.toString() ?? '');
      final startB = rawB is DateTime ? rawB : DateTime.tryParse(rawB?.toString() ?? '');
      if (startA == null && startB == null) return 0;
      if (startA == null) return 1;
      if (startB == null) return -1;
      final now = DateTime.now();
      final aFuture = startA.isAfter(now);
      final bFuture = startB.isAfter(now);
      if (aFuture && !bFuture) return -1;
      if (!aFuture && bFuture) return 1;
      if (aFuture && bFuture) return startA.compareTo(startB);
      return startB.compareTo(startA);
    });
    _trainings = sessions;

    _statusBySessionId.clear();
    _playingBySessionId.clear();
    _coachBySessionId.clear();
    _afgemeldBySessionId.clear();
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
    // Altijd naam van huidig profiel (zelf of kind) laden, ook als die nog nergens is aangemeld.
    if (targetProfileId.isNotEmpty) profileIds.add(targetProfileId);
    final namesById = await _loadProfileDisplayNames(profileIds);

    final playingBySid = <int, List<String>>{};
    final coachBySid = <int, List<String>>{};
    final afgemeldBySid = <int, List<String>>{};

    for (final r in allRows) {
      final sid = (r['session_id'] as num?)?.toInt();
      if (sid == null) continue;
      final pid = r['person_id']?.toString() ?? '';
      final status = (r['status'] ?? '').toString().trim().toLowerCase();
      final name = pid.isEmpty ? '' : (namesById[pid] ?? unknownUserName);

      if (pid == targetProfileId) {
        final s = _statusFromString(status);
        if (s != null) _statusBySessionId[sid] = s;
      }
      if (name.trim().isEmpty) continue;
      if (status == 'playing' || status == 'aanwezig') {
        playingBySid.putIfAbsent(sid, () => []).add(name);
      } else if (status == 'coach') {
        coachBySid.putIfAbsent(sid, () => []).add(name);
      } else if (status == 'afgemeld') {
        afgemeldBySid.putIfAbsent(sid, () => []).add(name);
      }
    }

    for (final e in playingBySid.values) {
      e.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    for (final e in coachBySid.values) {
      e.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    for (final e in afgemeldBySid.values) {
      e.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }

    if (!mounted) return;
    final myName = namesById[targetProfileId] ?? unknownUserName;
    setState(() {
      _myDisplayName = myName;
      _playingBySessionId
        ..clear()
        ..addAll(playingBySid);
      _coachBySessionId
        ..clear()
        ..addAll(coachBySid);
      _afgemeldBySessionId
        ..clear()
        ..addAll(afgemeldBySid);
    });
  }

  void _applyOptimisticAttendanceUpdate(int sessionId, AttendanceStatus? effective) {
    final me = _myDisplayName ?? 'Ik';
    final playing = List<String>.from(_playingBySessionId[sessionId] ?? []);
    final coaches = List<String>.from(_coachBySessionId[sessionId] ?? []);
    final afgemeld = List<String>.from(_afgemeldBySessionId[sessionId] ?? []);
    playing.remove(me);
    coaches.remove(me);
    afgemeld.remove(me);
    if (effective == AttendanceStatus.playing) {
      playing.add(me);
      playing.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } else if (effective == AttendanceStatus.coach) {
      coaches.add(me);
      coaches.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } else if (effective == AttendanceStatus.afgemeld) {
      afgemeld.add(me);
      afgemeld.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    if (effective == null) {
      _statusBySessionId.remove(sessionId);
    } else {
      _statusBySessionId[sessionId] = effective;
    }
    _playingBySessionId[sessionId] = playing;
    _coachBySessionId[sessionId] = coaches;
    _afgemeldBySessionId[sessionId] = afgemeld;
  }

  Future<Map<String, String>> _loadProfileDisplayNames(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final list = ids.toList();
    final me = _client.auth.currentUser;
    final myId = me?.id ?? '';
    final myMetaName = (me?.userMetadata?['display_name']?.toString() ?? '').trim();

    // Preferred: security definer RPC so names work even with restrictive RLS on profiles.
    try {
      final res = await _client.rpc('get_profile_display_names', params: {'profile_ids': list});
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
      final name = applyDisplayNameOverrides(n);
      map[id] = name.isNotEmpty ? name : unknownUserName;
    }
    if (myId.isNotEmpty && myMetaName.isNotEmpty && map.containsKey(myId)) {
      map[myId] = applyDisplayNameOverrides(myMetaName);
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
      case 'afgemeld':
        return AttendanceStatus.afgemeld;
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

  /// Team-ids waar deze gebruiker trainer/coach is; alleen die trainingen mogen worden verwijderd.
  Set<int> get _manageableTeamIds =>
      widget.manageableTeams.map((m) => m.teamId).toSet();

  bool _canDeleteTrainingForTeam(int teamId) => _manageableTeamIds.contains(teamId);

  /// Trainingen die nog niet afgelopen zijn (niet geannuleerd, start in de toekomst).
  /// Gebruikt voor zowel de "Voor alle"-kaart als de lijst; verleden wordt niet getoond.
  List<Map<String, dynamic>> get _visibleTrainings {
    final now = DateTime.now();
    return _trainings.where((t) {
      if (t['is_cancelled'] == true) return false;
      final start = t['start_datetime'] ?? t['start_timestamp'];
      if (start == null) return false;
      final dt = start is DateTime ? start : DateTime.tryParse(start.toString());
      return dt != null && dt.toLocal().isAfter(now);
    }).toList();
  }

  /// Trainingen gegroepeerd per team_id; teamIds in vaste volgorde (gesorteerd).
  Map<int, List<Map<String, dynamic>>> _groupVisibleTrainingsByTeam() {
    final visible = _visibleTrainings;
    final byTeam = <int, List<Map<String, dynamic>>>{};
    for (final t in visible) {
      final teamId = (t['team_id'] as num?)?.toInt() ?? 0;
      byTeam.putIfAbsent(teamId, () => []).add(t);
    }
    return byTeam;
  }

  /// Displaylabel voor team (inclusief "(kindnaam)" bij gekoppeld kind).
  String _teamDisplayLabel(int teamId) {
    try {
      final ctx = AppUserContext.of(context);
      final m = ctx.memberships.where((m) => m.teamId == teamId).firstOrNull;
      return m?.displayLabel ?? m?.teamName ?? 'Team $teamId';
    } catch (_) {
      return 'Team $teamId';
    }
  }

  /// Eén team-accordionkaart in dezelfde stijl als de wedstrijden-tab (GlassCard, donkerblauwe header, uitklapicoon).
  Widget _buildTeamTrainingAccordion({
    required int teamId,
    required int teamIndex,
    required List<int> teamIds,
    required Map<int, List<Map<String, dynamic>>> byTeam,
  }) {
    final useAccordion = teamIds.length > 1;
    final expanded = !useAccordion || _expandedTrainingTeamIds.contains(teamId);

    final sessions = byTeam[teamId];
    final hasSessions = sessions != null && sessions.isNotEmpty;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: useAccordion
                ? () {
                    setState(() {
                      if (_expandedTrainingTeamIds.contains(teamId)) {
                        _expandedTrainingTeamIds.remove(teamId);
                      } else {
                        _expandedTrainingTeamIds.add(teamId);
                      }
                    });
                  }
                : null,
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.darkBlue,
                      borderRadius: BorderRadius.circular(AppColors.cardRadius),
                    ),
                    child: Text(
                      _teamDisplayLabel(teamId),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  const Spacer(),
                  if (useAccordion)
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            if (!hasSessions)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                child: Text(
                  'Er zijn voor dit team nog geen trainingen.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              )
            else
              ...sessions.map(
                (session) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildTrainingCard(session),
                ),
              ),
          ],
        ],
      ),
    );
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

  String _attendanceSummary(List<String> playing, List<String> coaches, List<String> afgemeld) {
    final parts = <String>[];
    if (coaches.isNotEmpty) parts.add('Trainer/coach: ${coaches.length}');
    if (playing.isNotEmpty) parts.add('Speler(s): ${playing.length}');
    if (afgemeld.isNotEmpty) parts.add('Afgemeld: ${afgemeld.length}');
    return parts.join(' • ');
  }

  List<Widget> _attendanceNameLists(List<String> playing, List<String> coaches, List<String> afgemeld) {
    final out = <Widget>[];
    if (coaches.isNotEmpty) {
      out.add(Text('Trainer/coach: ${coaches.join(', ')}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)));
      out.add(const SizedBox(height: 4));
    }
    if (playing.isNotEmpty) {
      out.add(Text('Speler(s): ${playing.join(', ')}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)));
      out.add(const SizedBox(height: 4));
    }
    if (afgemeld.isNotEmpty) {
      out.add(Text('Afgemeld: ${afgemeld.join(', ')}', style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 13)));
    }
    return out;
  }

  Widget _buildTrainingCard(Map<String, dynamic> session) {
    final sessionId = (session['session_id'] as num).toInt();
    final teamId = (session['team_id'] as num?)?.toInt() ?? 0;
    final isCancelled = (session['is_cancelled'] == true);
    final title = (session['title'] ?? 'Training').toString();
    final location = (session['location'] ?? '').toString();
    final start = session['start_datetime'] ?? session['start_timestamp'];
    final end = session['end_timestamp'];
    final currentStatus = _statusBySessionId[sessionId];
    final isPresent = currentStatus == AttendanceStatus.playing || currentStatus == AttendanceStatus.coach;
    final playing = _playingBySessionId[sessionId] ?? [];
    final coaches = _coachBySessionId[sessionId] ?? [];
    final afgemeld = _afgemeldBySessionId[sessionId] ?? [];
    final expanded = _expandedSessionIds.contains(sessionId);
    final hasCounts = playing.isNotEmpty || coaches.isNotEmpty || afgemeld.isNotEmpty;

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_selectionMode && _canDeleteTrainingForTeam(teamId))
                Checkbox(
                  value: _selectedSessionIds.contains(sessionId),
                  activeColor: AppColors.primary,
                  onChanged: (v) => _toggleSelected(sessionId, v ?? false),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: AppColors.onBackground,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              decoration: isCancelled
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
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
                    const SizedBox(height: 4),
                    if (location.isNotEmpty)
                      Text(
                        location,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          decoration: isCancelled
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      _formatRange(start, end),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        decoration: isCancelled
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isCancelled) ...[
            const Text(
              'Deze training is geannuleerd (bijv. vakantie/feestdag).',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              isPresent
                  ? FilledButton.icon(
                      onPressed: isCancelled
                          ? null
                          : () => _updateAttendance(
                                sessionId,
                                _isTrainerOrCoachForTeam(teamId)
                                    ? AttendanceStatus.coach
                                    : AttendanceStatus.playing,
                              ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text('Aanmelden'),
                    )
                  : OutlinedButton.icon(
                      onPressed: isCancelled
                          ? null
                          : () => _updateAttendance(
                                sessionId,
                                _isTrainerOrCoachForTeam(teamId)
                                    ? AttendanceStatus.coach
                                    : AttendanceStatus.playing,
                              ),
                      icon: const Icon(Icons.person_add, size: 18),
                      label: const Text('Aanmelden'),
                    ),
              isPresent
                  ? OutlinedButton.icon(
                      onPressed: isCancelled
                          ? null
                          : () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Afmelden bevestigen'),
                                  content: const Text(
                                    'Weet je zeker dat je je wilt afmelden voor deze training?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(false),
                                      child: const Text('Annuleren'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: AppColors.background,
                                      ),
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(true),
                                      child: const Text('Afmelden'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && mounted) {
                                _updateAttendance(sessionId, AttendanceStatus.afgemeld);
                              }
                            },
                      icon: const Icon(Icons.person_off, size: 18),
                      label: const Text('Afmelden'),
                    )
                  : FilledButton.icon(
                      onPressed: isCancelled
                          ? null
                          : () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Afmelden bevestigen'),
                                  content: const Text(
                                    'Weet je zeker dat je je wilt afmelden voor deze training?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(false),
                                      child: const Text('Annuleren'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: AppColors.background,
                                      ),
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(true),
                                      child: const Text('Afmelden'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && mounted) {
                                _updateAttendance(sessionId, AttendanceStatus.afgemeld);
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: currentStatus == AttendanceStatus.afgemeld
                            ? AppColors.textSecondary.withValues(alpha: 0.25)
                            : AppColors.textSecondary.withValues(alpha: 0.25),
                        foregroundColor: AppColors.onBackground,
                      ),
                      icon: const Icon(Icons.person_off, size: 18),
                      label: const Text('Afmelden'),
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
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _attendanceSummary(playing, coaches, afgemeld),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 6),
              ..._attendanceNameLists(playing, coaches, afgemeld),
            ],
          ],
        ],
      ),
    );
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

    // Alleen trainingen van teams waar deze gebruiker trainer/coach is mogen worden verwijderd.
    final toDelete = _selectedSessionIds.where((sessionId) {
      final t = _trainings.cast<Map<String, dynamic>>().where(
            (t) => (t['session_id'] as num?)?.toInt() == sessionId,
          ).firstOrNull;
      if (t == null) return false;
      final teamId = (t['team_id'] as num?)?.toInt() ?? 0;
      return _manageableTeamIds.contains(teamId);
    }).toList();

    if (toDelete.isEmpty) return;

    final count = toDelete.length;
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
          toDelete,
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
    final effective = status;
    if (effective == null) return;

    final ctx = AppUserContext.of(context);
    final targetProfileId = ctx.attendanceProfileId;

    final prevStatus = _statusBySessionId[sessionId];
    final prevPlaying = List<String>.from(_playingBySessionId[sessionId] ?? []);
    final prevCoaches = List<String>.from(_coachBySessionId[sessionId] ?? []);
    final prevAfgemeld = List<String>.from(_afgemeldBySessionId[sessionId] ?? []);

    _applyOptimisticAttendanceUpdate(sessionId, effective);
    if (!mounted) return;
    setState(() {});

    try {
      await _client.from('attendance').upsert(
        {
          'session_id': sessionId,
          'person_id': targetProfileId,
          'status': effective.name,
        },
        onConflict: 'session_id,person_id',
      );
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
        _afgemeldBySessionId[sessionId] = prevAfgemeld;
      });
    }
  }

  /// Aanmelden voor alle binnenkomende trainingen; per training coach of playing op basis van team.
  Future<void> _setMyStatusForAllTrainingsAanwezig() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final upcoming = _visibleTrainings;
    if (upcoming.isEmpty) return;

    final ctx = AppUserContext.of(context);
    final targetProfileId = ctx.attendanceProfileId;

    final prevStatus = Map<int, AttendanceStatus?>.from(_statusBySessionId);
    final prevPlaying = <int, List<String>>{
      for (final e in _playingBySessionId.entries) e.key: List<String>.from(e.value),
    };
    final prevCoaches = <int, List<String>>{
      for (final e in _coachBySessionId.entries) e.key: List<String>.from(e.value),
    };

    for (final t in upcoming) {
      final sid = (t['session_id'] as num?)?.toInt();
      final teamId = (t['team_id'] as num?)?.toInt() ?? 0;
      if (sid == null) continue;
      final status = _isTrainerOrCoachForTeam(teamId)
          ? AttendanceStatus.coach
          : AttendanceStatus.playing;
      _applyOptimisticAttendanceUpdate(sid, status);
    }
    if (!mounted) return;
    setState(() {});

    try {
      for (final t in upcoming) {
        final sid = (t['session_id'] as num?)?.toInt();
        final teamId = (t['team_id'] as num?)?.toInt() ?? 0;
        if (sid == null) continue;
        final status = _isTrainerOrCoachForTeam(teamId)
            ? AttendanceStatus.coach
            : AttendanceStatus.playing;
        await _client.from('attendance').upsert(
          {
            'session_id': sid,
            'person_id': targetProfileId,
            'status': status.name,
          },
          onConflict: 'session_id,person_id',
        );
      }
      if (!mounted) return;
      showTopMessage(
        context,
        'Aanwezig voor ${upcoming.length} training(en) opgeslagen.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusBySessionId
          ..clear()
          ..addAll(prevStatus);
        _playingBySessionId
          ..clear()
          ..addAll(prevPlaying);
        _coachBySessionId
          ..clear()
          ..addAll(prevCoaches);
      });
      showTopMessage(context, 'Kon aanwezigheid niet opslaan: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);
    if (ctx.memberships.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Je bent nog niet gekoppeld aan een team.\n'
                'Koppel eerst je account aan een team om trainingen te zien.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: ctx.reloadUserContext == null
                    ? null
                    : () async => ctx.reloadUserContext!.call(),
                icon: const Icon(Icons.refresh),
                label: const Text('Opnieuw laden'),
              ),
              const SizedBox(height: 6),
              Text(
                'Tip: als je net via TC bent gekoppeld, druk op opnieuw laden.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.9),
                  fontSize: 12.5,
                ),
              ),
            ],
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

            final visible = _visibleTrainings;
            final upcoming = visible;
            final hasUpcomingCard = upcoming.isNotEmpty;
            final hasHeader = _canCreateTrainings;
            final byTeam = _groupVisibleTrainingsByTeam();
            // Alle teams waaraan je gekoppeld bent (eigen + kinderen), niet alleen teams met trainingen.
            final teamIds = _allowedTeamIds;

            if (teamIds.length > 1 && !_didInitExpandedTraining) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_didInitExpandedTraining && _allowedTeamIds.isNotEmpty) {
                  setState(() {
                    _expandedTrainingTeamIds.add(_allowedTeamIds.first);
                    _didInitExpandedTraining = true;
                  });
                }
              });
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                if (hasUpcomingCard) ...[
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.darkBlue,
                            borderRadius:
                                BorderRadius.circular(AppColors.cardRadius),
                          ),
                          child: Text(
                            'Voor alle trainingen',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${upcoming.length} training(en)',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            upcoming.every((t) {
                              final sid = (t['session_id'] as num?)?.toInt();
                              return sid != null && _statusBySessionId[sid] != null;
                            })
                                ? FilledButton.icon(
                                    onPressed:
                                        _setMyStatusForAllTrainingsAanwezig,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.success,
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(
                                      Icons.check_circle,
                                      size: 18,
                                    ),
                                    label: const Text('Aanwezig'),
                                  )
                                : OutlinedButton(
                                    onPressed:
                                        _setMyStatusForAllTrainingsAanwezig,
                                    child: const Text('Aanwezig'),
                                  ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (hasHeader) ...[
                  GlassCard(
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
                  ),
                  const SizedBox(height: 8),
                ],
                for (var i = 0; i < teamIds.length; i++) ...[
                  _buildTeamTrainingAccordion(
                    teamId: teamIds[i],
                    teamIndex: i,
                    teamIds: teamIds,
                    byTeam: byTeam,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}