import 'package:flutter/material.dart';
import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/components/app_logo_title.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyTasksTab extends StatelessWidget {
  const MyTasksTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const AppLogoTitle(),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(54),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: TabBar(
                  indicator: BoxDecoration(
                    color: AppColors.darkBlue,
                    borderRadius: BorderRadius.circular(AppColors.cardRadius),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                  tabs: const [
                    Tab(text: 'Verenigingstaken'),
                    Tab(text: 'Overzicht'),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            const _TeamTasksView(),
            ctx.canViewAllTasks
                ? const _OverviewHomeMatchesView()
                : const _LockedView(),
          ],
        ),
      ),
    );
  }
}

class _TeamTasksView extends StatefulWidget {
  const _TeamTasksView();

  @override
  State<_TeamTasksView> createState() => _TeamTasksViewState();
}

class _TeamTasksViewState extends State<_TeamTasksView> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  bool _schemaMissing = false;

  String? _lastProfileId;

  List<_LinkedMatchTasks> _matches = const [];
  Set<int> _signedUpTaskIds = const {}; // task_ids I am signed up for
  Map<int, String> _teamNameById = const {};
  Map<int, List<String>> _signupNamesByTaskId = const {}; // task_id -> names

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ctx = AppUserContext.of(context);
    if (_lastProfileId != ctx.profileId) {
      _lastProfileId = ctx.profileId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(ctx: ctx);
      });
    }
  }

  Future<void> _load({AppUserContext? ctx}) async {
    setState(() {
      _loading = true;
      _error = null;
      _schemaMissing = false;
    });

    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        setState(() {
          _matches = const [];
          _signedUpTaskIds = const {};
          _teamNameById = const {};
          _loading = false;
        });
        return;
      }

      final userContext = ctx ?? AppUserContext.of(context);
      final myTeamIds = userContext.memberships.map((m) => m.teamId).toSet().toList();
      myTeamIds.sort();

      if (myTeamIds.isEmpty) {
        setState(() {
          _matches = const [];
          _signedUpTaskIds = const {};
          _teamNameById = const {};
          _loading = false;
        });
        return;
      }

      // Load only matches Wedstrijdzaken linked to my teams.
      final now = DateTime.now().toUtc();
      final mRes = await _client
          .from('nevobo_home_matches')
          .select(
            'match_key, team_code, starts_at, summary, location, linked_team_id, fluiten_task_id, tellen_task_id',
          )
          .inFilter('linked_team_id', myTeamIds)
          .gte('starts_at', now.subtract(const Duration(days: 1)).toIso8601String())
          .order('starts_at', ascending: true);
      final mRows = (mRes as List<dynamic>).cast<Map<String, dynamic>>();

      final matches = <_LinkedMatchTasks>[];
      final taskIds = <int>{};
      final linkedTeamIds = <int>{};
      final matchKeys = <String>[];
      for (final row in mRows) {
        final matchKey = (row['match_key'] ?? '').toString();
        if (matchKey.isEmpty) continue;
        final startsAt = DateTime.tryParse((row['starts_at'] ?? '').toString());
        if (startsAt == null) continue;
        final linkedTeamId = (row['linked_team_id'] as num?)?.toInt();
        if (linkedTeamId == null) continue;

        final fluitenId = (row['fluiten_task_id'] as num?)?.toInt();
        final tellenId = (row['tellen_task_id'] as num?)?.toInt();
        if (fluitenId != null) taskIds.add(fluitenId);
        if (tellenId != null) taskIds.add(tellenId);
        linkedTeamIds.add(linkedTeamId);
        matchKeys.add(matchKey);

        matches.add(
          _LinkedMatchTasks(
            matchKey: matchKey,
            teamCode: (row['team_code'] ?? '').toString(),
            startsAt: startsAt,
            summary: (row['summary'] ?? '').toString(),
            location: (row['location'] ?? '').toString(),
            linkedTeamId: linkedTeamId,
            fluitenTaskId: fluitenId,
            tellenTaskId: tellenId,
          ),
        );
      }

      // My signups (only need signed/unsigned state)
      final signedUp = <int>{};
      if (taskIds.isNotEmpty) {
        final sRes = await _client
            .from('club_task_signups')
            .select('task_id')
            .eq('profile_id', user.id)
            .inFilter('task_id', taskIds.toList());
        final sRows = (sRes as List<dynamic>).cast<Map<String, dynamic>>();
        for (final row in sRows) {
          final tid = (row['task_id'] as num?)?.toInt();
          if (tid != null) signedUp.add(tid);
        }
      }

      final allTeamIds = linkedTeamIds.toList()..sort();
      final teamNameById = await _loadTeamNames(teamIds: allTeamIds);

      final signupNamesByTaskId = await _loadSignupNamesByTaskId(matchKeys: matchKeys);

      setState(() {
        _matches = matches;
        _signedUpTaskIds = signedUp;
        _teamNameById = teamNameById;
        _signupNamesByTaskId = signupNamesByTaskId;
        _loading = false;
      });
    } catch (e) {
      final msg = e.toString();
      setState(() {
        _error = msg;
        _schemaMissing = msg.contains('PGRST205') ||
            msg.contains('schema cache') ||
            msg.contains("Could not find the table 'public.club_tasks'") ||
            msg.contains("Could not find the table 'public.club_task_signups'") ||
            msg.contains("Could not find the table 'public.nevobo_home_matches'");
        _loading = false;
      });
    }
  }

  String _shortId(String value) {
    if (value.length <= 8) return value;
    return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
  }

  Future<Map<String, String>> _loadProfileDisplayNames(Set<String> profileIds) async {
    if (profileIds.isEmpty) return {};
    final ids = profileIds.toList();

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

  String _formatNames(List<String> names) {
    if (names.isEmpty) return '—';
    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} +${names.length - 2}';
  }

  Future<Map<int, List<String>>> _loadSignupNamesByTaskId({
    required List<String> matchKeys,
  }) async {
    if (matchKeys.isEmpty) return {};

    // Preferred: use RPC (security definer) so we can show display names.
    try {
      final res = await _client.rpc('get_sheet_home_matches');
      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final wanted = matchKeys.toSet();
      final out = <int, List<String>>{};

      for (final r in rows) {
        final key = (r['match_key'] ?? '').toString();
        if (key.isEmpty || !wanted.contains(key)) continue;

        final flTaskId = (r['fluiten_task_id'] as num?)?.toInt();
        final teTaskId = (r['tellen_task_id'] as num?)?.toInt();

        final fl = (r['fluiten_names'] as List<dynamic>?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            const [];
        final te = (r['tellen_names'] as List<dynamic>?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            const [];

        if (flTaskId != null) out[flTaskId] = fl;
        if (teTaskId != null) out[teTaskId] = te;
      }
      return out;
    } catch (_) {
      // fallback below
    }

    // Fallback: load signups for all relevant task ids and resolve names best-effort.
    final taskIds = <int>{
      for (final m in _matches) ...[
        if (m.fluitenTaskId != null) m.fluitenTaskId!,
        if (m.tellenTaskId != null) m.tellenTaskId!,
      ],
    }.toList();
    if (taskIds.isEmpty) return {};

    final sRes = await _client
        .from('club_task_signups')
        .select('task_id, profile_id')
        .inFilter('task_id', taskIds);
    final rows = (sRes as List<dynamic>).cast<Map<String, dynamic>>();

    final profileIds = <String>{};
    for (final r in rows) {
      final pid = r['profile_id']?.toString() ?? '';
      if (pid.isNotEmpty) profileIds.add(pid);
    }
    final namesById = await _loadProfileDisplayNames(profileIds);

    final out = <int, List<String>>{};
    for (final r in rows) {
      final tid = (r['task_id'] as num?)?.toInt();
      final pid = r['profile_id']?.toString() ?? '';
      if (tid == null || pid.isEmpty) continue;
      final name = (namesById[pid] ?? _shortId(pid)).trim();
      out.putIfAbsent(tid, () => []).add(name);
    }
    for (final entry in out.entries) {
      entry.value.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    return out;
  }

  Future<Map<int, String>> _loadTeamNames({required List<int> teamIds}) async {
    if (teamIds.isEmpty) return {};

    final candidates = <String>[
      'team_name',
      'name',
      'short_name',
      'code',
      'team_code',
      'abbreviation',
    ];
    final idFields = <String>['team_id', 'id'];

    for (final idField in idFields) {
      for (final nameField in candidates) {
        try {
          final res = await _client
              .from('teams')
              .select('$idField, $nameField')
              .inFilter(idField, teamIds);
          final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
          final map = <int, String>{};
          for (final row in rows) {
            final tid = (row[idField] as num?)?.toInt();
            if (tid == null) continue;
            final name = (row[nameField] ?? '').toString().trim();
            if (name.isNotEmpty) map[tid] = name;
          }
          if (map.isNotEmpty) return map;
        } catch (_) {
          // try next
        }
      }
    }
    return {};
  }

  Future<void> _toggleSignup(int taskId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final signedUp = _signedUpTaskIds.contains(taskId);
    try {
      if (signedUp) {
        await _client
            .from('club_task_signups')
            .delete()
            .eq('task_id', taskId)
            .eq('profile_id', user.id);
        if (!mounted) return;
        setState(() {
          _signedUpTaskIds = {..._signedUpTaskIds}..remove(taskId);
        });
      } else {
        await _client.from('club_task_signups').insert({
          'task_id': taskId,
          'profile_id': user.id,
        });
        if (!mounted) return;
        setState(() {
          _signedUpTaskIds = {..._signedUpTaskIds}..add(taskId);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kan aanmelding niet wijzigen: $e')),
      );
    }
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);
    final user = _client.auth.currentUser;

    if (user == null) {
      return const Center(
        child: Text(
          'Log in om taken te bekijken.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Verenigingstaken konden niet laden',
                  style: TextStyle(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
                const SizedBox(height: 12),
                if (_schemaMissing) ...[
                  const Text(
                    'Je Supabase tabellen voor taken zijn nog niet aangemaakt (of schema-cache is nog niet ververst).',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Run `supabase/club_tasks_schema.sql` in Supabase.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () => _load(ctx: ctx),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Opnieuw'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_matches.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: GlassCard(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Wedstrijdzaken heeft nog geen wedstrijden aan jouw team(s) gekoppeld.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _load(ctx: ctx),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _matches.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final m = _matches[index];
          final teamLabel = (_teamNameById[m.linkedTeamId] ?? 'Team ${m.linkedTeamId}').trim();

          return GlassCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        m.teamCode,
                        style: const TextStyle(
                          color: AppColors.onBackground,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _formatDateTime(m.startsAt),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    m.summary,
                    style: const TextStyle(
                      color: AppColors.onBackground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (m.location.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      m.location.trim(),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Toegewezen aan: $teamLabel',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _TaskSignupButton(
                          label: 'Fluiten',
                          taskId: m.fluitenTaskId,
                          signedUp: m.fluitenTaskId != null &&
                              _signedUpTaskIds.contains(m.fluitenTaskId),
                          onToggle: m.fluitenTaskId == null
                              ? null
                              : () => _toggleSignup(m.fluitenTaskId!),
                          subtitle: m.fluitenTaskId == null
                              ? null
                              : 'Aangemeld: ${_formatNames(_signupNamesByTaskId[m.fluitenTaskId!] ?? const [])}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TaskSignupButton(
                          label: 'Tellen',
                          taskId: m.tellenTaskId,
                          signedUp: m.tellenTaskId != null &&
                              _signedUpTaskIds.contains(m.tellenTaskId),
                          onToggle: m.tellenTaskId == null
                              ? null
                              : () => _toggleSignup(m.tellenTaskId!),
                          subtitle: m.tellenTaskId == null
                              ? null
                              : 'Aangemeld: ${_formatNames(_signupNamesByTaskId[m.tellenTaskId!] ?? const [])}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LinkedMatchTasks {
  final String matchKey;
  final String teamCode;
  final DateTime startsAt;
  final String summary;
  final String location;
  final int linkedTeamId;
  final int? fluitenTaskId;
  final int? tellenTaskId;

  const _LinkedMatchTasks({
    required this.matchKey,
    required this.teamCode,
    required this.startsAt,
    required this.summary,
    required this.location,
    required this.linkedTeamId,
    required this.fluitenTaskId,
    required this.tellenTaskId,
  });
}

class _TaskSignupButton extends StatelessWidget {
  final String label;
  final int? taskId;
  final bool signedUp;
  final VoidCallback? onToggle;
  final String? subtitle;

  const _TaskSignupButton({
    required this.label,
    required this.taskId,
    required this.signedUp,
    required this.onToggle,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = taskId == null || onToggle == null;
    final effectiveSignedUp = !disabled && signedUp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: disabled ? null : onToggle,
          style: ElevatedButton.styleFrom(
            backgroundColor: disabled
                ? AppColors.card
                : (effectiveSignedUp ? AppColors.card : AppColors.primary),
            foregroundColor: disabled
                ? AppColors.textSecondary
                : (effectiveSignedUp ? AppColors.onBackground : AppColors.background),
            side: (disabled || !effectiveSignedUp)
                ? null
                : BorderSide(color: AppColors.primary.withValues(alpha: 0.7)),
          ),
          child: Text(
            disabled
                ? label
                : (effectiveSignedUp ? '$label: Afmelden' : '$label: Aanmelden'),
            textAlign: TextAlign.center,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _OverviewHomeMatchesView extends StatefulWidget {
  const _OverviewHomeMatchesView();

  @override
  State<_OverviewHomeMatchesView> createState() => _OverviewHomeMatchesViewState();
}

class _OverviewHomeMatchesViewState extends State<_OverviewHomeMatchesView> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<_HomeMatch> _matches = const [];
  List<String> _warnings = const [];
  Map<String, _MatchLinkStatus> _statusByKey = const {};
  bool _supabaseLinkTableMissing = false;
  Map<String, Map<String, dynamic>> _linkRowsByKey = const {};
  Map<String, _MatchSignupSummary> _signupsByKey = const {};

  bool _teamsLoading = false;
  List<_TeamOption> _teams = const [];
  Map<int, String> _teamLabelById = const {};
  Map<String, int> _teamIdByCode = const {};

  @override
  void initState() {
    super.initState();
    _ensureTeamsLoaded();
    _load();
  }

  bool _isHomeMatch(String summary) {
    final s = summary.trim().toLowerCase();
    if (s.isEmpty) return false;
    final parts = s.split(' - ');
    if (parts.isNotEmpty) return parts.first.trim().contains('minerva');
    return s.startsWith('minerva');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _warnings = const [];
      _statusByKey = const {};
      _supabaseLinkTableMissing = false;
      _linkRowsByKey = const {};
      _signupsByKey = const {};
    });

    try {
      final teams = await NevoboApi.loadTeamsFromSupabase(client: _client);

      final now = DateTime.now();
      final to = now.add(const Duration(days: 365));

      final out = <_HomeMatch>[];
      final seen = <String>{};
      final warnings = <String>[];

      for (final team in teams) {
        List<NevoboMatch> matches = const [];
        try {
          matches = await NevoboApi.fetchMatchesForTeam(team: team);
        } catch (e) {
          warnings.add('${team.code}: $e');
          continue;
        }
        for (final m in matches) {
          final start = m.start;
          if (start == null) continue;
          // Alleen toekomstige wedstrijden
          if (start.isBefore(now) || start.isAfter(to)) continue;
          if (!_isHomeMatch(m.summary)) continue;

          final key =
              '${team.code}|${start.toUtc().toIso8601String()}|${m.summary.trim()}';
          if (!seen.add(key)) continue;

          out.add(
            _HomeMatch(
              teamCode: team.code,
              start: start,
              summary: m.summary.trim(),
              location: (m.location ?? '').trim(),
            ),
          );
        }
      }

      out.sort((a, b) => a.start.compareTo(b.start));

      // Persist to Supabase (for Google Sheet sync + linking state).
      final keys = out.map(_matchKey).toSet().toList();
      final linkRows = await _upsertAndLoadLinkRows(matches: out);
      if (linkRows == null) {
        // Table missing or not accessible; we keep going without Supabase status.
        _supabaseLinkTableMissing = true;
      }

      final statuses = linkRows == null
          ? <String, _MatchLinkStatus>{}
          : _statusesFromLinkRows(keys: keys, rows: linkRows);

      final signups = linkRows == null
          ? <String, _MatchSignupSummary>{}
          : await _loadSignupsByMatchKey(keys: keys, linkRows: linkRows);

      if (!mounted) return;
      setState(() {
        _matches = out;
        _warnings = warnings;
        _statusByKey = statuses;
        _linkRowsByKey = linkRows ?? const {};
        _signupsByKey = signups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year}';
  }

  String _formatTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }

  String _matchKey(_HomeMatch m) {
    final utc = m.start.toUtc().toIso8601String();
    return 'nevobo_match:${m.teamCode}:$utc';
  }

  String _shortId(String value) {
    if (value.length <= 8) return value;
    return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
  }

  Future<Map<String, String>> _loadProfileDisplayNames(Set<String> profileIds) async {
    if (profileIds.isEmpty) return {};
    final ids = profileIds.toList();

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

  Future<Map<String, _MatchSignupSummary>> _loadSignupsByMatchKey({
    required List<String> keys,
    required Map<String, Map<String, dynamic>> linkRows,
  }) async {
    // Preferred: use RPC that already resolves names (security definer)
    try {
      final res = await _client.rpc('get_sheet_home_matches');
      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final out = <String, _MatchSignupSummary>{};
      final wanted = keys.toSet();

      for (final r in rows) {
        final key = (r['match_key'] ?? '').toString();
        if (key.isEmpty || !wanted.contains(key)) continue;

        final fl = (r['fluiten_names'] as List<dynamic>?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            const [];
        final te = (r['tellen_names'] as List<dynamic>?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            const [];
        out[key] = _MatchSignupSummary(fluitenNames: fl, tellenNames: te);
      }
      return out;
    } catch (_) {
      // fallback below
    }

    // Fallback: load signups by task_id and resolve names best-effort.
    final taskIds = <int>{};
    final taskIdToKeyAndType = <int, (String, String)>{};
    for (final entry in linkRows.entries) {
      final key = entry.key;
      final row = entry.value;
      final fl = (row['fluiten_task_id'] as num?)?.toInt();
      final te = (row['tellen_task_id'] as num?)?.toInt();
      if (fl != null) {
        taskIds.add(fl);
        taskIdToKeyAndType[fl] = (key, 'fluiten');
      }
      if (te != null) {
        taskIds.add(te);
        taskIdToKeyAndType[te] = (key, 'tellen');
      }
    }

    if (taskIds.isEmpty) return {};

    final signupRows = await _client
        .from('club_task_signups')
        .select('task_id, profile_id')
        .inFilter('task_id', taskIds.toList());
    final rows = (signupRows as List<dynamic>).cast<Map<String, dynamic>>();

    final profileIds = <String>{};
    for (final r in rows) {
      final pid = r['profile_id']?.toString() ?? '';
      if (pid.isNotEmpty) profileIds.add(pid);
    }

    final namesById = await _loadProfileDisplayNames(profileIds);

    final flByKey = <String, List<String>>{};
    final teByKey = <String, List<String>>{};
    for (final r in rows) {
      final taskId = (r['task_id'] as num?)?.toInt();
      final profileId = r['profile_id']?.toString() ?? '';
      if (taskId == null || profileId.isEmpty) continue;
      final mapping = taskIdToKeyAndType[taskId];
      if (mapping == null) continue;
      final key = mapping.$1;
      final type = mapping.$2;
      final name = (namesById[profileId] ?? _shortId(profileId)).trim();
      if (type == 'fluiten') {
        flByKey.putIfAbsent(key, () => []).add(name);
      } else if (type == 'tellen') {
        teByKey.putIfAbsent(key, () => []).add(name);
      }
    }

    final out = <String, _MatchSignupSummary>{};
    for (final key in keys) {
      final fl = flByKey[key] ?? const [];
      final te = teByKey[key] ?? const [];
      if (fl.isEmpty && te.isEmpty) continue;
      fl.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      te.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      out[key] = _MatchSignupSummary(fluitenNames: fl, tellenNames: te);
    }
    return out;
  }

  int? _linkedTeamIdForMatch(_HomeMatch m) {
    final row = _linkRowsByKey[_matchKey(m)];
    return (row?['linked_team_id'] as num?)?.toInt();
  }

  Future<void> _ensureTeamsLoaded() async {
    if (_teamsLoading) return;
    if (_teams.isNotEmpty) return;
    _teamsLoading = true;
    try {
      final list = await _fetchTeams();
      final labelById = <int, String>{};
      final idByCode = <String, int>{};
      for (final t in list) {
        labelById[t.teamId] = t.label;
        final c = (t.code ?? '').trim().toUpperCase();
        if (c.isNotEmpty) idByCode[c] = t.teamId;
      }
      if (!mounted) return;
      setState(() {
        _teams = list;
        _teamLabelById = labelById;
        _teamIdByCode = idByCode;
      });
    } finally {
      _teamsLoading = false;
    }
  }

  String _teamLabel(int teamId) => (_teamLabelById[teamId] ?? 'Team $teamId').trim();

  Future<Map<String, Map<String, dynamic>>?> _upsertAndLoadLinkRows({
    required List<_HomeMatch> matches,
  }) async {
    if (matches.isEmpty) return <String, Map<String, dynamic>>{};

    // Upsert upcoming matches
    final rows = matches
        .map(
          (m) => {
            'match_key': _matchKey(m),
            'team_code': m.teamCode,
            'starts_at': m.start.toUtc().toIso8601String(),
            'summary': m.summary,
            'location': m.location,
            'updated_by': _client.auth.currentUser?.id,
          },
        )
        .toList();

    try {
      await _client.from('nevobo_home_matches').upsert(rows);
    } catch (e) {
      final msg = e.toString();
      // Table missing / schema cache
      if (msg.contains('PGRST205') ||
          msg.contains('schema cache') ||
          msg.contains("Could not find the table 'public.nevobo_home_matches'")) {
        return null;
      }
      // RLS/other errors -> still return null and show warning
      return null;
    }

    // Load rows for our keys
    final keys = matches.map(_matchKey).toSet().toList();
    try {
      final res = await _client
          .from('nevobo_home_matches')
          .select('match_key, linked_team_id, fluiten_task_id, tellen_task_id')
          .inFilter('match_key', keys);
      final list = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final map = <String, Map<String, dynamic>>{};
      for (final r in list) {
        final k = (r['match_key'] ?? '').toString();
        if (k.isNotEmpty) map[k] = r;
      }
      return map;
    } catch (_) {
      return null;
    }
  }

  Map<String, _MatchLinkStatus> _statusesFromLinkRows({
    required List<String> keys,
    required Map<String, Map<String, dynamic>> rows,
  }) {
    final out = <String, _MatchLinkStatus>{};
    for (final key in keys) {
      final r = rows[key];
      final linkedTeamId = (r?['linked_team_id'] as num?)?.toInt();
      final fluitenId = (r?['fluiten_task_id'] as num?)?.toInt();
      final tellenId = (r?['tellen_task_id'] as num?)?.toInt();

      final hasFluiten = fluitenId != null;
      final hasTellen = tellenId != null;
      final assigned = linkedTeamId != null;

      out[key] = _MatchLinkStatus(
        hasFluiten: hasFluiten,
        hasTellen: hasTellen,
        fluitenAssigned: hasFluiten && assigned,
        tellenAssigned: hasTellen && assigned,
      );
    }
    return out;
  }

  Future<void> _refreshStatusForKey(String key) async {
    final byKind = await _taskIdByKindForMatchKey(key);
    final fluitenId = byKind['fluiten'];
    final tellenId = byKind['tellen'];
    final ids = <int>[
      if (fluitenId != null) fluitenId,
      if (tellenId != null) tellenId,
    ];

    final assigned = <int>{};
    if (ids.isNotEmpty) {
      try {
        final res = await _client
            .from('club_task_team_assignments')
            .select('task_id')
            .inFilter('task_id', ids);
        final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
        for (final r in rows) {
          final tid = (r['task_id'] as num?)?.toInt();
          if (tid != null) assigned.add(tid);
        }
      } catch (_) {
        // ignore
      }
    }

    final status = _MatchLinkStatus(
      hasFluiten: fluitenId != null,
      hasTellen: tellenId != null,
      fluitenAssigned: fluitenId != null && assigned.contains(fluitenId),
      tellenAssigned: tellenId != null && assigned.contains(tellenId),
    );

    if (!mounted) return;
    setState(() {
      _statusByKey = {..._statusByKey, key: status};
    });
  }

  Future<void> _refreshLinkRowForKey(String key) async {
    try {
      final res = await _client
          .from('nevobo_home_matches')
          .select('match_key, linked_team_id, fluiten_task_id, tellen_task_id')
          .eq('match_key', key)
          .maybeSingle();
      final Map<String, dynamic>? row = res;
      if (!mounted) return;
      if (row == null) return;
      setState(() {
        _linkRowsByKey = {..._linkRowsByKey, key: row};
      });
    } catch (_) {
      // ignore
    }
  }

  Widget _statusChipForMatch(_HomeMatch match) {
    final key = _matchKey(match);
    final s = _statusByKey[key] ?? const _MatchLinkStatus.empty();

    String label;
    Color border;
    Color text;

    if (!s.hasFluiten && !s.hasTellen) {
      label = 'Niet gekoppeld';
      border = AppColors.textSecondary;
      text = AppColors.textSecondary;
    } else if (s.fluitenAssigned && s.tellenAssigned) {
      label = 'Gekoppeld';
      border = AppColors.primary;
      text = AppColors.primary;
    } else if (s.fluitenAssigned || s.tellenAssigned) {
      label = 'Deels';
      border = AppColors.primary;
      text = AppColors.primary;
    } else {
      label = 'Gemaakt';
      border = AppColors.textSecondary;
      text = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border.withValues(alpha: 0.6)),
        color: Colors.transparent,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Future<void> _openLinkSheet({
    required AppUserContext ctx,
    required _HomeMatch match,
  }) async {
    if (!ctx.canManageTasks) return;
    await _ensureTeamsLoaded();
    if (!mounted) return;

    final key = _matchKey(match);
    final currentLinked = _linkedTeamIdForMatch(match);
    final suggested = _teamIdByCode[match.teamCode.trim().toUpperCase()];
    final existingKinds = await _existingTaskKindsForMatchKey(key);
    if (!mounted) return;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var selectedTeamId =
            currentLinked ?? suggested ?? (_teams.isNotEmpty ? _teams.first.teamId : 0);
        var fluiten = true;
        var tellen = true;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
            ),
            child: GlassCard(
              child: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Wedstrijd koppelen',
                            style: TextStyle(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(false),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${match.teamCode} • ${_formatDate(match.start)} ${_formatTime(match.start)}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        match.summary,
                        style: const TextStyle(
                          color: AppColors.onBackground,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (match.location.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          match.location,
                          style: const TextStyle(color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 14),

                      // Team selector row
                      GlassCard(
                        child: ListTile(
                          dense: true,
                          title: const Text(
                            'Team',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            _teamLabel(selectedTeamId),
                            style: const TextStyle(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          trailing: const Icon(Icons.search, color: AppColors.primary),
                          onTap: () async {
                            final picked = await _pickTeamId(
                              context: sheetContext,
                              initialTeamId: selectedTeamId,
                              suggestedTeamId: suggested,
                            );
                            if (picked != null) setState(() => selectedTeamId = picked);
                          },
                        ),
                      ),

                      if (currentLinked != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.link, size: 18, color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Huidig gekoppeld: ${_teamLabel(currentLinked)}',
                                style: const TextStyle(color: AppColors.textSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                Navigator.of(sheetContext).pop(false);
                                await _unlinkTasksForMatchKey(key);
                                if (!context.mounted) return;
                                await _refreshLinkRowForKey(key);
                                await _refreshStatusForKey(key);
                              },
                              child: const Text('Ontkoppelen'),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 14),
                      const Text(
                        'Taken',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilterChip(
                            selected: fluiten,
                            label: Text(
                              existingKinds.contains('fluiten')
                                  ? 'Fluiten (bestaat al)'
                                  : 'Fluiten',
                            ),
                            onSelected: (v) => setState(() => fluiten = v),
                            selectedColor: AppColors.primary.withValues(alpha: 0.20),
                            checkmarkColor: AppColors.primary,
                            side: BorderSide(
                              color: AppColors.primary.withValues(alpha: fluiten ? 0.8 : 0.25),
                            ),
                          ),
                          FilterChip(
                            selected: tellen,
                            label: Text(
                              existingKinds.contains('tellen') ? 'Tellen (bestaat al)' : 'Tellen',
                            ),
                            onSelected: (v) => setState(() => tellen = v),
                            selectedColor: AppColors.primary.withValues(alpha: 0.20),
                            checkmarkColor: AppColors.primary,
                            side: BorderSide(
                              color: AppColors.primary.withValues(alpha: tellen ? 0.8 : 0.25),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _teams.isEmpty
                              ? null
                              : () async {
                                  Navigator.of(sheetContext).pop(true);
                                  await _applyLinkForMatch(
                                    ctx: ctx,
                                    match: match,
                                    teamId: selectedTeamId,
                                    fluiten: fluiten,
                                    tellen: tellen,
                                  );
                                },
                          icon: const Icon(Icons.link),
                          label: Text('Koppel aan ${_teamLabel(selectedTeamId)}'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    // handled inside sheet
    if (result != true) return;
  }

  Future<int?> _pickTeamId({
    required BuildContext context,
    required int initialTeamId,
    required int? suggestedTeamId,
  }) async {
    if (_teams.isEmpty) return null;

    return await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var query = '';
        var selected = initialTeamId;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
            ),
            child: GlassCard(
              child: StatefulBuilder(
                builder: (context, setState) {
                  final filtered = _teams.where((t) {
                    final q = query.trim().toLowerCase();
                    if (q.isEmpty) return true;
                    return t.label.toLowerCase().contains(q) ||
                        (t.code ?? '').toLowerCase().contains(q);
                  }).toList();

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Kies team',
                            style: TextStyle(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(null),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Zoek team',
                        ),
                        onChanged: (v) => setState(() => query = v),
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final t = filtered[index];
                            final isSelected = t.teamId == selected;
                            final code = (t.code ?? '').trim();
                            final showSubtitle = code.isNotEmpty &&
                                code.toLowerCase() != t.label.trim().toLowerCase();

                            return ListTile(
                              dense: true,
                              title: Text(
                                t.label,
                                style: const TextStyle(
                                  color: AppColors.onBackground,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: showSubtitle
                                  ? Text(
                                      code,
                                      style: const TextStyle(color: AppColors.textSecondary),
                                    )
                                  : null,
                              trailing: isSelected
                                  ? const Icon(Icons.check, color: AppColors.primary)
                                  : null,
                              onTap: () => Navigator.of(sheetContext).pop(t.teamId),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _applyLinkForMatch({
    required AppUserContext ctx,
    required _HomeMatch match,
    required int teamId,
    required bool fluiten,
    required bool tellen,
  }) async {
    if (!ctx.canManageTasks) return;
    final user = _client.auth.currentUser;
    if (user == null) return;

    final key = _matchKey(match);
    int created = 0;

    Future<int> createTask(String type, String title) async {
      final inserted = await _client
          .from('club_tasks')
          .insert({
            'title': title,
            'type': type,
            'required': true,
            'starts_at': match.start.toUtc().toIso8601String(),
            'location': match.location,
            'notes': [
              key,
              'kind:$type',
              match.summary,
              if (match.location.isNotEmpty) 'Locatie: ${match.location}',
            ].join('\n'),
            'created_by': user.id,
          })
          .select()
          .single();
      final taskId = (inserted['task_id'] as num).toInt();
      await _client.from('club_task_team_assignments').insert({
        'task_id': taskId,
        'team_id': teamId,
        'assigned_by': user.id,
      });
      created++;
      try {
        await _client.from('nevobo_home_matches').upsert({
          'match_key': key,
          'team_code': match.teamCode,
          'starts_at': match.start.toUtc().toIso8601String(),
          'summary': match.summary,
          'location': match.location,
          'linked_team_id': teamId,
          'linked_by': user.id,
          'linked_at': DateTime.now().toUtc().toIso8601String(),
          if (type == 'fluiten') 'fluiten_task_id': taskId,
          if (type == 'tellen') 'tellen_task_id': taskId,
          'updated_by': user.id,
          'created_by': user.id,
        });
      } catch (_) {}
      return taskId;
    }

    try {
      final existingTaskIds = await _taskIdByKindForMatchKey(key);
      final toAssign = <int>[];

      if (fluiten) {
        final existing = existingTaskIds['fluiten'];
        if (existing != null) {
          toAssign.add(existing);
        } else {
          await createTask('fluiten', 'Fluiten (${match.teamCode})');
        }
      } else {
        final existing = existingTaskIds['fluiten'];
        if (existing != null) {
          await _client.from('club_task_team_assignments').delete().eq('task_id', existing);
        }
      }

      if (tellen) {
        final existing = existingTaskIds['tellen'];
        if (existing != null) {
          toAssign.add(existing);
        } else {
          await createTask('tellen', 'Tellen (${match.teamCode})');
        }
      } else {
        final existing = existingTaskIds['tellen'];
        if (existing != null) {
          await _client.from('club_task_team_assignments').delete().eq('task_id', existing);
        }
      }

      if (toAssign.isNotEmpty) {
        await _setAssignmentForTaskIds(taskIds: toAssign, teamId: teamId, assignedBy: user.id);
        try {
          await _client.from('nevobo_home_matches').update({
            'linked_team_id': teamId,
            'linked_by': user.id,
            'linked_at': DateTime.now().toUtc().toIso8601String(),
            'updated_by': user.id,
          }).eq('match_key', key);
        } catch (_) {}
      }

      if (!mounted) return;
      await _refreshLinkRowForKey(key);
      if (!mounted) return;
      await _refreshStatusForKey(key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gekoppeld. ($created aangemaakt)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Koppelen mislukt: $e')),
      );
    }
  }

  Future<List<_TeamOption>> _fetchTeams() async {
    final candidates = <String>[
      'team_name',
      'name',
      'short_name',
      'code',
      'team_code',
      'abbreviation',
    ];
    final idFields = <String>['team_id', 'id'];

    for (final idField in idFields) {
      for (final nameField in candidates) {
        try {
          final res = await _client.from('teams').select('$idField, $nameField');
          final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
          final list = <_TeamOption>[];
          for (final row in rows) {
            final id = (row[idField] as num?)?.toInt();
            if (id == null) continue;
            final label = (row[nameField] ?? '').toString().trim();
            final code = NevoboApi.extractCodeFromTeamName(label);
            list.add(
              _TeamOption(
                teamId: id,
                label: label.isNotEmpty ? label : 'Team $id',
                code: code,
              ),
            );
          }
          if (list.isNotEmpty) {
            list.sort((a, b) => a.label.compareTo(b.label));
            return list;
          }
        } catch (_) {
          // try next
        }
      }
    }
    return const [];
  }

  Future<Set<String>> _existingTaskKindsForMatchKey(String key) async {
    // Best-effort check to prevent duplicates.
    // Requires notes to start with the key and the type to match.
    try {
      final res = await _client
          .from('club_tasks')
          .select('type, notes')
          .ilike('notes', '$key%');
      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final kinds = <String>{};
      for (final row in rows) {
        final type = (row['type'] ?? '').toString().trim().toLowerCase();
        if (type.isNotEmpty) kinds.add(type);
      }
      return kinds;
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, int>> _taskIdByKindForMatchKey(String key) async {
    // Prefer the dedicated Supabase table (for spreadsheet syncing).
    try {
      final res = await _client
          .from('nevobo_home_matches')
          .select('fluiten_task_id, tellen_task_id')
          .eq('match_key', key)
          .maybeSingle();
      final Map<String, dynamic>? row = res;
      if (row != null) {
        final fluitenId = (row['fluiten_task_id'] as num?)?.toInt();
        final tellenId = (row['tellen_task_id'] as num?)?.toInt();
        return {
          if (fluitenId != null) 'fluiten': fluitenId,
          if (tellenId != null) 'tellen': tellenId,
        };
      }
    } catch (_) {
      // ignore
    }

    // Fallback: legacy method via notes on club_tasks.
    try {
      final res = await _client
          .from('club_tasks')
          .select('task_id, type, notes')
          .ilike('notes', '$key%');
      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final out = <String, int>{};
      for (final row in rows) {
        final notes = (row['notes'] ?? '').toString();
        if (!notes.startsWith(key)) continue;
        final type = (row['type'] ?? '').toString().trim().toLowerCase();
        final id = (row['task_id'] as num?)?.toInt();
        if (id == null || type.isEmpty) continue;
        out[type] = id;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _unlinkTasksForMatchKey(String key) async {
    final byKind = await _taskIdByKindForMatchKey(key);
    final taskIds = byKind.values.toSet().toList();
    if (taskIds.isEmpty) return;
    await _client.from('club_task_team_assignments').delete().inFilter('task_id', taskIds);
    try {
      await _client.from('nevobo_home_matches').update({
        'linked_team_id': null,
        'linked_by': _client.auth.currentUser?.id,
        'linked_at': null,
        'updated_by': _client.auth.currentUser?.id,
      }).eq('match_key', key);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _setAssignmentForTaskIds({
    required List<int> taskIds,
    required int teamId,
    required String assignedBy,
  }) async {
    if (taskIds.isEmpty) return;
    await _client.from('club_task_team_assignments').delete().inFilter('task_id', taskIds);
    final rows = taskIds
        .map((tid) => {'task_id': tid, 'team_id': teamId, 'assigned_by': assignedBy})
        .toList();
    await _client.from('club_task_team_assignments').insert(rows);
  }
  // NOTE: Old dialog-based linking removed in favor of the bottom-sheet UX.

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Kon thuiswedstrijden niet laden',
                  style: TextStyle(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Opnieuw'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Geen thuiswedstrijden gevonden',
                  style: TextStyle(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _warnings.isNotEmpty
                      ? 'Sommige teams konden we niet laden (bijv. verkeerde Nevobo-categorie / 404).'
                      : 'Controleer of je teams in Supabase staan (tabel `teams`) en of de Nevobo API bereikbaar is.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                if (_warnings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _warnings.take(5).join('\n'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ],
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Verversen'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Groepeer per datum
    final byDate = <DateTime, List<_HomeMatch>>{};
    for (final m in _matches) {
      final d = m.start.toLocal();
      final key = DateTime(d.year, d.month, d.day);
      byDate.putIfAbsent(key, () => []).add(m);
    }
    final dates = byDate.keys.toList()..sort();
    for (final d in dates) {
      byDate[d]!.sort((a, b) => a.start.compareTo(b.start));
    }

    final children = <Widget>[];
    if (_supabaseLinkTableMissing) {
      children.add(
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Supabase tabel ontbreekt',
                  style: TextStyle(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Run `supabase/nevobo_home_matches_schema.sql` in Supabase om koppelingen op te slaan (nodig voor Google Sheet sync).',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
      children.add(const SizedBox(height: 12));
    }
    if (_warnings.isNotEmpty) {
      children.add(
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Let op: niet alle teams konden geladen worden',
                  style: TextStyle(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _warnings.take(5).join('\n'),
                  style: const TextStyle(color: AppColors.error),
                ),
                if (_warnings.length > 5) ...[
                  const SizedBox(height: 6),
                  Text(
                    '+ ${_warnings.length - 5} meer…',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      children.add(const SizedBox(height: 12));
    }
    for (final d in dates) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Text(
            _formatDate(d),
            style: const TextStyle(
              color: AppColors.onBackground,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
      for (final m in byDate[d]!) {
        final linkedTeamId = _linkedTeamIdForMatch(m);
        final signup = _signupsByKey[_matchKey(m)];
        children.add(
          GlassCard(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppColors.cardRadius),
              onTap: ctx.canManageTasks ? () => _openLinkSheet(ctx: ctx, match: m) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                m.teamCode,
                                style: const TextStyle(
                                  color: AppColors.onBackground,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _formatTime(m.start),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            m.summary,
                            style: const TextStyle(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (m.location.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              m.location,
                              style: const TextStyle(color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (signup != null &&
                              (signup.fluitenNames.isNotEmpty ||
                                  signup.tellenNames.isNotEmpty)) ...[
                            const SizedBox(height: 8),
                            if (signup.fluitenNames.isNotEmpty)
                              Text(
                                'Fluiten: ${_formatNames(signup.fluitenNames)}',
                                style: const TextStyle(color: AppColors.textSecondary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (signup.tellenNames.isNotEmpty)
                              Text(
                                'Tellen: ${_formatNames(signup.tellenNames)}',
                                style: const TextStyle(color: AppColors.textSecondary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _statusChipForMatch(m),
                        if (linkedTeamId != null) ...[
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Text(
                              _teamLabel(linkedTeamId),
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                        if (ctx.canManageTasks) ...[
                          const SizedBox(height: 6),
                          IconButton(
                            tooltip: 'Koppelen aan team',
                            icon: const Icon(Icons.link, color: AppColors.primary),
                            onPressed: () => _openLinkSheet(ctx: ctx, match: m),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        children.add(const SizedBox(height: 12));
      }
    }
    if (children.isNotEmpty && children.last is SizedBox) {
      children.removeLast();
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: children,
      ),
    );
  }

  String _formatNames(List<String> names) {
    if (names.isEmpty) return '-';
    if (names.length <= 3) return names.join(', ');
    final head = names.take(3).join(', ');
    return '$head +${names.length - 3}';
  }
}

class _HomeMatch {
  final String teamCode;
  final DateTime start;
  final String summary;
  final String location;

  const _HomeMatch({
    required this.teamCode,
    required this.start,
    required this.summary,
    required this.location,
  });
}

class _TeamOption {
  final int teamId;
  final String label;
  final String? code;

  const _TeamOption({
    required this.teamId,
    required this.label,
    required this.code,
  });
}

class _MatchLinkStatus {
  final bool hasFluiten;
  final bool hasTellen;
  final bool fluitenAssigned;
  final bool tellenAssigned;

  const _MatchLinkStatus({
    required this.hasFluiten,
    required this.hasTellen,
    required this.fluitenAssigned,
    required this.tellenAssigned,
  });

  const _MatchLinkStatus.empty()
      : hasFluiten = false,
        hasTellen = false,
        fluitenAssigned = false,
        tellenAssigned = false;
}

class _MatchSignupSummary {
  final List<String> fluitenNames;
  final List<String> tellenNames;

  const _MatchSignupSummary({
    required this.fluitenNames,
    required this.tellenNames,
  });
}

class _LockedView extends StatelessWidget {
  const _LockedView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: GlassCard(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Alleen Bestuur & Wedstrijdzaken.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
/* (oude Taken-implementatie staat hieronder; tijdelijk uitgecommentarieerd
   zodat we stap-voor-stap opnieuw kunnen ontwerpen)

class MyTasksTab extends StatelessWidget {
  const MyTasksTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const AppLogoTitle(),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          bottom: TabBar(
            indicator: BoxDecoration(
              color: AppColors.darkBlue,
              borderRadius: BorderRadius.circular(AppColors.cardRadius),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
            ),
            tabs: const [
              Tab(text: 'Verenigingstaken'),
              Tab(text: 'Overzicht'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const _EmptyTasksView(
              title: 'Verenigingstaken',
              subtitle: 'Leeg — dit bouwen we stap voor stap opnieuw.',
            ),
            ctx.canViewAllTasks
                ? const _EmptyTasksView(
                    title: 'Overzicht',
                    subtitle: 'Leeg — dit bouwen we stap voor stap opnieuw.',
                  )
                : const _LockedView(),
          ],
        ),
      ),
    );
  }
}

class _EmptyTasksView extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyTasksView({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.onBackground,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedView extends StatelessWidget {
  const _LockedView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: GlassCard(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Alleen Bestuur & Wedstrijdzaken.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:minerva_app/ui/components/app_logo_title.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyTasksTab extends StatefulWidget {
  const MyTasksTab({super.key});

  @override
  State<MyTasksTab> createState() => _MyTasksTabState();
}

class _MyTasksTabState extends State<MyTasksTab> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  bool _schemaMissing = false;
  String? _lastProfileId;

  List<_ClubTask> _tasks = const [];
  Map<int, List<int>> _assignedTeamIdsByTaskId = const {};
  Set<int> _signedUpTaskIds = const {};
  Map<int, String> _teamNameById = const {};

  // Admin/Bestuur/Wedstrijdzaken overview (all tasks + who signed up)
  bool _adminLoading = false;
  String? _adminError;
  List<_ClubTask> _adminTasks = const [];
  Map<int, List<int>> _adminAssignedTeamIdsByTaskId = const {};
  Map<int, String> _adminTeamNameById = const {};
  Map<int, List<_TaskSignup>> _adminSignupsByTaskId = const {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Safe place to depend on inherited widgets (AppUserContext).
    final ctx = AppUserContext.of(context);
    if (_lastProfileId != ctx.profileId) {
      _lastProfileId = ctx.profileId;
      // Avoid setState during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _load(ctx: ctx);
          if (ctx.canViewAllTasks) {
            _loadAdminOverview();
          } else {
            // Clear admin view state when user loses permissions / logs out.
            setState(() {
              _adminLoading = false;
              _adminError = null;
              _adminTasks = const [];
              _adminAssignedTeamIdsByTaskId = const {};
              _adminTeamNameById = const {};
              _adminSignupsByTaskId = const {};
            });
          }
        }
      });
    }
  }

  Future<void> _load({AppUserContext? ctx}) async {
    setState(() {
      _loading = true;
      _error = null;
      _schemaMissing = false;
    });

    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        setState(() {
          _tasks = const [];
          _assignedTeamIdsByTaskId = const {};
          _signedUpTaskIds = const {};
          _teamNameById = const {};
          _loading = false;
        });
        return;
      }

      final userContext = ctx ?? AppUserContext.of(context);
      final myTeamIds = userContext.memberships.map((m) => m.teamId).toSet().toList();

      // Verenigingstaken: ONLY tasks assigned to my teams.
      List<int> taskIds = const [];
      List<_ClubTask> tasks = const [];
      if (myTeamIds.isNotEmpty) {
        final aRes = await _client
            .from('club_task_team_assignments')
            .select('task_id')
            .inFilter('team_id', myTeamIds);
        final assignedIds = (aRes as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((r) => (r['task_id'] as num).toInt())
            .toSet()
            .toList()
          ..sort();

        taskIds = assignedIds;
        if (taskIds.isNotEmpty) {
          final tRes = await _client
              .from('club_tasks')
              .select()
              .inFilter('task_id', taskIds)
              .order('starts_at', ascending: true);
          tasks = (tRes as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map(_ClubTask.fromRow)
              .toList();
        }
      }

      // Assignments for displayed tasks
      Map<int, List<int>> assignedTeamIdsByTaskId = {};
      if (taskIds.isNotEmpty) {
        final aRes = await _client
            .from('club_task_team_assignments')
            .select('task_id, team_id')
            .inFilter('task_id', taskIds);
        final rows = (aRes as List<dynamic>).cast<Map<String, dynamic>>();
        for (final row in rows) {
          final tid = (row['task_id'] as num).toInt();
          final teamId = (row['team_id'] as num).toInt();
          assignedTeamIdsByTaskId.putIfAbsent(tid, () => []).add(teamId);
        }
      }

      // Team names for assigned team IDs
      final allTeamIds = assignedTeamIdsByTaskId.values.expand((v) => v).toSet().toList()
        ..sort();
      final teamNameById = await _loadTeamNames(teamIds: allTeamIds);

      // Signups for displayed tasks (only need my signups for the toggle UI)
      final signedUpTaskIds = <int>{};
      if (taskIds.isNotEmpty) {
        final sRes = await _client
            .from('club_task_signups')
            .select('task_id, profile_id')
            .inFilter('task_id', taskIds);
        final rows = (sRes as List<dynamic>).cast<Map<String, dynamic>>();
        for (final row in rows) {
          final tid = (row['task_id'] as num).toInt();
          final pid = row['profile_id']?.toString() ?? '';
          if (pid == user.id) signedUpTaskIds.add(tid);
        }
      }

      setState(() {
        _tasks = tasks;
        _assignedTeamIdsByTaskId = assignedTeamIdsByTaskId;
        _teamNameById = teamNameById;
        _signedUpTaskIds = signedUpTaskIds;
        _loading = false;
      });
    } catch (e) {
      final msg = e.toString();
      setState(() {
        _error = msg;
        _schemaMissing = msg.contains('PGRST205') ||
            msg.contains('schema cache') ||
            msg.contains("Could not find the table 'public.club_tasks'");
        _loading = false;
      });
    }
  }

  Future<Map<String, String>> _loadProfileDisplayNames(Set<String> profileIds) async {
    if (profileIds.isEmpty) return {};
    final ids = profileIds.toList();

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

    String shortId(String value) {
      if (value.length <= 8) return value;
      return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
    }

    final map = <String, String>{};
    for (final r in rows) {
      final id = r['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final name =
          (r['display_name'] ?? r['full_name'] ?? r['name'] ?? r['email'] ?? '')
              .toString()
              .trim();
      map[id] = name.isNotEmpty ? name : shortId(id);
    }
    return map;
  }

  Future<void> _loadAdminOverview() async {
    final ctx = AppUserContext.of(context);
    if (!ctx.canViewAllTasks) return;

    if (mounted) {
      setState(() {
        _adminLoading = true;
        _adminError = null;
      });
    }

    try {
      final res = await _client
          .from('club_tasks')
          .select()
          .order('starts_at', ascending: true);
      final tasks = (res as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(_ClubTask.fromRow)
          .toList();
      final taskIds = tasks.map((t) => t.taskId).toList();

      // Assignments for admin tasks
      final assignedTeamIdsByTaskId = <int, List<int>>{};
      if (taskIds.isNotEmpty) {
        final aRes = await _client
            .from('club_task_team_assignments')
            .select('task_id, team_id')
            .inFilter('task_id', taskIds);
        final rows = (aRes as List<dynamic>).cast<Map<String, dynamic>>();
        for (final row in rows) {
          final tid = (row['task_id'] as num).toInt();
          final teamId = (row['team_id'] as num).toInt();
          assignedTeamIdsByTaskId.putIfAbsent(tid, () => []).add(teamId);
        }
      }

      final allTeamIds = assignedTeamIdsByTaskId.values.expand((v) => v).toSet().toList()
        ..sort();
      final teamNameById = await _loadTeamNames(teamIds: allTeamIds);

      // Signups with best-effort display names
      final signupsByTaskId = <int, List<_TaskSignup>>{};
      if (taskIds.isNotEmpty) {
        final sRes = await _client
            .from('club_task_signups')
            .select('task_id, profile_id')
            .inFilter('task_id', taskIds);
        final rows = (sRes as List<dynamic>).cast<Map<String, dynamic>>();

        final profileIds = <String>{};
        for (final row in rows) {
          final pid = row['profile_id']?.toString() ?? '';
          if (pid.isNotEmpty) profileIds.add(pid);
        }

        final namesById = await _loadProfileDisplayNames(profileIds);

        String shortId(String value) {
          if (value.length <= 8) return value;
          return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
        }

        for (final row in rows) {
          final tid = (row['task_id'] as num).toInt();
          final pid = row['profile_id']?.toString() ?? '';
          if (pid.isEmpty) continue;
          final name = (namesById[pid] ?? '').trim();
          signupsByTaskId
              .putIfAbsent(tid, () => [])
              .add(_TaskSignup(profileId: pid, displayName: name.isNotEmpty ? name : shortId(pid)));
        }

        // Sort signups for stable UI
        for (final entry in signupsByTaskId.entries) {
          entry.value.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
        }
      }

      if (!mounted) return;
      setState(() {
        _adminTasks = tasks;
        _adminAssignedTeamIdsByTaskId = assignedTeamIdsByTaskId;
        _adminTeamNameById = teamNameById;
        _adminSignupsByTaskId = signupsByTaskId;
        _adminLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _adminError = e.toString();
        _adminLoading = false;
      });
    }
  }

  Future<void> _refreshAll() async {
    final ctx = AppUserContext.of(context);
    await _load(ctx: ctx);
    if (ctx.canViewAllTasks) {
      await _loadAdminOverview();
    }
  }

  Widget _buildAssignedTasksView(BuildContext context, AppUserContext ctx) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return _TasksErrorView(
        error: _error!,
        schemaMissing: _schemaMissing,
        onRetry: _refreshAll,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Verenigingstaken',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.onBackground,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                ctx.canViewAllTasks
                    ? 'Taken voor jouw teams. (Tab "Overzicht" is alleen voor Bestuur/Wedstrijdzaken.)'
                    : 'Taken die aan jouw teams zijn toegewezen.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_tasks.isEmpty)
          const GlassCard(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Geen taken voor jouw teams gevonden.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          )
        else
          ..._tasks.map((t) {
            final assignedTeamIds = _assignedTeamIdsByTaskId[t.taskId] ?? const [];
            final assignedLabels = assignedTeamIds
                .map((id) => (_teamNameById[id] ?? 'Team $id').trim())
                .where((s) => s.isNotEmpty)
                .toList()
              ..sort();

            final canSignUp = _canSignUpForTask(ctx, t.taskId);
            final signedUp = _signedUpTaskIds.contains(t.taskId);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TaskCard(
                task: t,
                assignedTeamsLabel:
                    assignedLabels.isEmpty ? null : assignedLabels.join(', '),
                signupCount: null,
                showSignupAction: canSignUp,
                signedUp: signedUp,
                onToggleSignup: () => _toggleSignup(t.taskId),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildAdminOverviewView(BuildContext context) {
    if (_adminLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_adminError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.darkBlue,
                    borderRadius: BorderRadius.circular(AppColors.cardRadius),
                  ),
                  child: const Text(
                    'Overzicht kon niet laden',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _adminError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _loadAdminOverview,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Opnieuw proberen'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_adminTasks.isEmpty) {
      return const Center(
        child: Text(
          'Geen taken gevonden.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
          ),
          child: Text(
            'Overzicht',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(
          _adminTasks.length,
          (index) {
            final t = _adminTasks[index];
            final assignedTeamIds = _adminAssignedTeamIdsByTaskId[t.taskId] ?? const [];
            final assignedLabels = assignedTeamIds
                .map((id) => (_adminTeamNameById[id] ?? 'Team $id').trim())
                .where((s) => s.isNotEmpty)
                .toList()
              ..sort();

            final signups = _adminSignupsByTaskId[t.taskId] ?? const [];
            final subtitleParts = <String>[];
            if (assignedLabels.isNotEmpty) subtitleParts.add(assignedLabels.join(', '));
            if (t.startsAt != null) subtitleParts.add(_formatDateTime(t.startsAt!));
            if (t.location != null && t.location!.trim().isNotEmpty) {
              subtitleParts.add(t.location!.trim());
            }

            return Padding(
              padding: EdgeInsets.only(bottom: index < _adminTasks.length - 1 ? 12 : 0),
              child: GlassCard(
                child: ExpansionTile(
                  collapsedIconColor: AppColors.textSecondary,
                  iconColor: AppColors.primary,
                  title: Text(
                    t.title,
                    style: const TextStyle(
                      color: AppColors.onBackground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    subtitleParts.join(' • '),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${signups.length} aangemeld',
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          if (signups.isEmpty)
                            const Text(
                              'Nog niemand aangemeld.',
                              style: TextStyle(color: AppColors.textSecondary),
                            )
                          else
                            ...signups.map((s) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Text(
                                  s.displayName,
                                  style: const TextStyle(
                                    color: AppColors.onBackground,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<Map<int, String>> _loadTeamNames({required List<int> teamIds}) async {
    if (teamIds.isEmpty) return {};

    final candidates = <String>[
      'team_name',
      'name',
      'short_name',
      'code',
      'team_code',
      'abbreviation',
    ];
    final idFields = <String>['team_id', 'id'];

    for (final idField in idFields) {
      for (final nameField in candidates) {
        try {
          final res = await _client
              .from('teams')
              .select('$idField, $nameField')
              .inFilter(idField, teamIds);
          final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();

          final map = <int, String>{};
          for (final row in rows) {
            final tid = (row[idField] as num?)?.toInt();
            if (tid == null) continue;
            final name = (row[nameField] as String?) ?? '';
            map[tid] = name;
          }
          final hasAny = map.values.any((v) => v.trim().isNotEmpty);
          if (hasAny) return map;
        } catch (_) {
          // try next
        }
      }
    }

    return {};
  }

  bool _canSignUpForTask(AppUserContext ctx, int taskId) {
    final assigned = _assignedTeamIdsByTaskId[taskId] ?? const [];
    if (assigned.isEmpty) return false;
    final myTeamIds = ctx.memberships.map((m) => m.teamId).toSet();
    return assigned.any(myTeamIds.contains);
  }

  Future<void> _toggleSignup(int taskId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final signedUp = _signedUpTaskIds.contains(taskId);
    try {
      if (signedUp) {
        await _client
            .from('club_task_signups')
            .delete()
            .eq('task_id', taskId)
            .eq('profile_id', user.id);
      } else {
        await _client.from('club_task_signups').insert({
          'task_id': taskId,
          'profile_id': user.id,
        });
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kan aanmelding niet wijzigen: $e')),
      );
    }
  }

  Future<void> _openCreateTask() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _CreateTaskPage()),
    );
    if (created == true && mounted) {
      await _load();
    }
  }

  bool _isHomeMatch(String summary) {
    final s = summary.trim().toLowerCase();
    if (s.isEmpty) return false;
    final parts = s.split(' - ');
    if (parts.isNotEmpty) {
      return parts.first.trim().contains('minerva');
    }
    return s.startsWith('minerva');
  }

  Future<Map<String, int>> _loadTeamIdByCode() async {
    final candidates = <String>[
      'team_name',
      'name',
      'short_name',
      'code',
      'team_code',
      'abbreviation',
    ];
    final idFields = <String>['team_id', 'id'];

    for (final idField in idFields) {
      for (final nameField in candidates) {
        try {
          final res = await _client.from('teams').select('$idField, $nameField');
          final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
          final map = <String, int>{};
          for (final row in rows) {
            final id = (row[idField] as num?)?.toInt();
            if (id == null) continue;
            final raw = (row[nameField] ?? '').toString();
            final code = NevoboApi.extractCodeFromTeamName(raw);
            if (code == null || code.isEmpty) continue;
            map[code] = id;
          }
          if (map.isNotEmpty) return map;
        } catch (_) {
          // try next
        }
      }
    }
    return {};
  }

  Future<void> _importHomeMatchesAsTasks() async {
    final ctx = AppUserContext.of(context);
    if (!ctx.canManageTasks) return;

    final user = _client.auth.currentUser;
    if (user == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thuiswedstrijden importeren'),
        content: const Text(
          'We importeren alle komende thuiswedstrijden uit Nevobo en maken daar taken van.\n\n'
          'De taken worden automatisch toegewezen aan het team dat thuis speelt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Importeren'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _schemaMissing = false;
      });
    }

    try {
      final teams = await NevoboApi.loadTeamsFromSupabase(client: _client);
      final teamIdByCode = await _loadTeamIdByCode();

      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 7));
      final to = now.add(const Duration(days: 365));

      // Best-effort de-dupe on our own "nevobo:" key stored in notes.
      final existingKeys = <String>{};
      try {
        final res = await _client
            .from('club_tasks')
            .select('notes')
            .eq('type', 'wedstrijd')
            .gte('starts_at', from.toUtc().toIso8601String())
            .lte('starts_at', to.toUtc().toIso8601String());
        final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
        for (final row in rows) {
          final notes = (row['notes'] ?? '').toString();
          final firstLine = notes.split('\n').first.trim();
          if (firstLine.startsWith('nevobo:')) existingKeys.add(firstLine);
        }
      } catch (_) {
        // ignore
      }

      int created = 0;
      int skipped = 0;
      int missingTeamId = 0;

      for (final team in teams) {
        final teamId = teamIdByCode[team.code];
        if (teamId == null) {
          missingTeamId++;
          continue;
        }

        final matches = await NevoboApi.fetchMatchesIcs(icsUrl: team.icsUrl);
        for (final m in matches) {
          final start = m.start;
          if (start == null) continue;
          if (start.isBefore(from) || start.isAfter(to)) continue;
          if (!_isHomeMatch(m.summary)) continue;

          final key = 'nevobo:${team.code}:${start.toUtc().toIso8601String()}';
          if (existingKeys.contains(key)) {
            skipped++;
            continue;
          }

          final title = 'Thuiswedstrijd ${team.code}';
          final location = (m.location ?? '').trim();
          final notes = [
            key,
            m.summary.trim(),
            if (location.isNotEmpty) 'Locatie: $location',
          ].join('\n');

          final inserted = await _client
              .from('club_tasks')
              .insert({
                'title': title,
                'type': 'wedstrijd',
                'required': true,
                'starts_at': start.toUtc().toIso8601String(),
                'location': location,
                'notes': notes,
                'created_by': user.id,
              })
              .select()
              .single();

          final taskId = (inserted['task_id'] as num).toInt();
          await _client.from('club_task_team_assignments').insert({
            'task_id': taskId,
            'team_id': teamId,
            'assigned_by': user.id,
          });

          existingKeys.add(key);
          created++;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Import klaar: $created taken toegevoegd, $skipped overgeslagen.'
            '${missingTeamId > 0 ? ' ($missingTeamId teams konden we niet mappen)' : ''}',
          ),
        ),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Importeren mislukt: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);
    final showOverview = ctx.canViewAllTasks;

    final fab = ctx.canManageTasks && !_schemaMissing
        ? FloatingActionButton(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.background,
            onPressed: _openCreateTask,
            child: const Icon(Icons.add),
          )
        : null;

    if (!showOverview) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const AppLogoTitle(),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          actions: [
            if (ctx.canManageTasks && !_schemaMissing)
              IconButton(
                tooltip: 'Importeer thuiswedstrijden',
                icon: const Icon(Icons.download),
                onPressed: _importHomeMatchesAsTasks,
              ),
          ],
        ),
        floatingActionButton: fab,
        body: _buildAssignedTasksView(context, ctx),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const AppLogoTitle(),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          bottom: TabBar(
            indicator: BoxDecoration(
              color: AppColors.darkBlue,
              borderRadius: BorderRadius.circular(AppColors.cardRadius),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
            ),
            tabs: const [
              Tab(text: 'Verenigingstaken'),
              Tab(text: 'Overzicht'),
            ],
          ),
          actions: [
            if (ctx.canManageTasks && !_schemaMissing)
              IconButton(
                tooltip: 'Importeer thuiswedstrijden',
                icon: const Icon(Icons.download),
                onPressed: _importHomeMatchesAsTasks,
              ),
          ],
        ),
        floatingActionButton: fab,
        body: TabBarView(
          children: [
            _buildAssignedTasksView(context, ctx),
            _buildAdminOverviewView(context),
          ],
        ),
      ),
    );
  }
}

/* ===================== UI ===================== */

class _TaskCard extends StatelessWidget {
  final _ClubTask task;
  final String? assignedTeamsLabel;
  final int? signupCount;
  final bool showSignupAction;
  final bool signedUp;
  final VoidCallback onToggleSignup;

  const _TaskCard({
    required this.task,
    required this.assignedTeamsLabel,
    required this.signupCount,
    required this.showSignupAction,
    required this.signedUp,
    required this.onToggleSignup,
  });

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[];
    if (assignedTeamsLabel != null && assignedTeamsLabel!.trim().isNotEmpty) {
      subtitleParts.add(assignedTeamsLabel!);
    }
    if (task.startsAt != null) {
      subtitleParts.add(_formatDateTime(task.startsAt!));
    }
    if (task.location != null && task.location!.trim().isNotEmpty) {
      subtitleParts.add(task.location!.trim());
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              task.required ? Icons.priority_high : Icons.assignment_outlined,
              color: task.required ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.onBackground,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitleParts.join(' • '),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (signupCount != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$signupCount aangemeld',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  if (showSignupAction) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: onToggleSignup,
                        child: Text(signedUp ? 'Afmelden' : 'Aanmelden'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}

class _TasksErrorView extends StatelessWidget {
  final String error;
  final bool schemaMissing;
  final VoidCallback onRetry;
  const _TasksErrorView({
    required this.error,
    required this.schemaMissing,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Taken konden niet laden',
                style: TextStyle(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error),
              ),
              const SizedBox(height: 12),
              if (schemaMissing) ...[
                const Text(
                  'Je Supabase tabellen voor taken bestaan nog niet (of de API schema-cache is nog niet ververst).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Oplossing:\n'
                  '1) Run `supabase/club_tasks_schema.sql` in Supabase (SQL editor)\n'
                  '2) Ga in Supabase naar Settings → API → “Reload schema” (of wacht ±1 minuut)\n'
                  '3) Open de app opnieuw / druk op verversen',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ] else ...[
                const Text(
                  'Tip: controleer je internetverbinding en permissies in Supabase (RLS).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Opnieuw proberen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ===================== DATA ===================== */

class _ClubTask {
  final int taskId;
  final String title;
  final String type;
  final bool required;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? location;
  final String? notes;

  const _ClubTask({
    required this.taskId,
    required this.title,
    required this.type,
    required this.required,
    required this.startsAt,
    required this.endsAt,
    required this.location,
    required this.notes,
  });

  static _ClubTask fromRow(Map<String, dynamic> row) {
    DateTime? parseDt(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    return _ClubTask(
      taskId: (row['task_id'] as num).toInt(),
      title: (row['title'] as String?) ?? 'Taak',
      type: (row['type'] as String?) ?? 'taak',
      required: (row['required'] as bool?) ?? false,
      startsAt: parseDt(row['starts_at']),
      endsAt: parseDt(row['ends_at']),
      location: row['location'] as String?,
      notes: row['notes'] as String?,
    );
  }
}

class _TeamOption {
  final int teamId;
  final String label;
  const _TeamOption(this.teamId, this.label);
}

class _TaskSignup {
  final String profileId;
  final String displayName;
  const _TaskSignup({
    required this.profileId,
    required this.displayName,
  });
}

class _CreateTaskPage extends StatefulWidget {
  const _CreateTaskPage();

  @override
  State<_CreateTaskPage> createState() => _CreateTaskPageState();
}

class _CreateTaskPageState extends State<_CreateTaskPage> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<_TeamOption> _teams = const [];
  final Set<int> _selectedTeamIds = {};

  String _type = 'wedstrijd';
  bool _required = true;
  DateTime _date = DateTime.now();
  TimeOfDay? _time;
  String _location = '';
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadTeams() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final teams = await _fetchTeams();
      setState(() {
        _teams = teams;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<List<_TeamOption>> _fetchTeams() async {
    final candidates = <String>[
      'team_name',
      'name',
      'short_name',
      'code',
      'team_code',
      'abbreviation',
    ];
    final idFields = <String>['team_id', 'id'];

    for (final idField in idFields) {
      for (final nameField in candidates) {
        try {
          final res = await _client.from('teams').select('$idField, $nameField');
          final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
          final list = <_TeamOption>[];
          for (final row in rows) {
            final id = (row[idField] as num?)?.toInt();
            if (id == null) continue;
            final name = (row[nameField] as String?) ?? '';
            final label = name.trim().isEmpty ? 'Team $id' : name.trim();
            list.add(_TeamOption(id, label));
          }
          if (list.isNotEmpty) {
            list.sort((a, b) => a.label.compareTo(b.label));
            return list;
          }
        } catch (_) {
          // try next
        }
      }
    }

    return const [];
  }

  Future<TimeOfDay?> _pickTimeTyped() async {
    final hourController = TextEditingController();
    final minuteController = TextEditingController();
    String? errorText;

    final result = await showDialog<TimeOfDay?>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Tijd'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Typ een tijd',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: TextField(
                          controller: hourController,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 2,
                          decoration: const InputDecoration(
                            counterText: '',
                            hintText: 'uu',
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          ':',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 70,
                        child: TextField(
                          controller: minuteController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 2,
                          decoration: const InputDecoration(
                            counterText: '',
                            hintText: 'mm',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Annuleren'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final h = int.tryParse(hourController.text.trim());
                    final m = int.tryParse(minuteController.text.trim());
                    if (h == null || m == null) {
                      setState(() => errorText = 'Vul uur en minuten in.');
                      return;
                    }
                    if (h < 0 || h > 23) {
                      setState(() => errorText = 'Uur moet tussen 0 en 23 zijn.');
                      return;
                    }
                    if (m < 0 || m > 59) {
                      setState(
                        () => errorText = 'Minuten moeten tussen 0 en 59 zijn.',
                      );
                      return;
                    }
                    Navigator.of(context).pop(TimeOfDay(hour: h, minute: m));
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );

    hourController.dispose();
    minuteController.dispose();
    return result;
  }

  Future<void> _save() async {
    if (_saving) return;
    final ctx = AppUserContext.of(context);
    if (!ctx.canManageTasks) return;

    setState(() => _saving = true);
    try {
      final user = _client.auth.currentUser;
      if (user == null) return;

      final title = _typeLabel(_type);
      DateTime? startsAt;
      if (_time != null) {
        startsAt = DateTime(_date.year, _date.month, _date.day, _time!.hour, _time!.minute);
      }

      final inserted = await _client
          .from('club_tasks')
          .insert({
            'title': title,
            'type': _type,
            'required': _required,
            'starts_at': startsAt?.toUtc().toIso8601String(),
            'location': _location.trim(),
            'notes': _notesController.text.trim(),
            'created_by': user.id,
          })
          .select()
          .single();

      final taskId = (inserted['task_id'] as num).toInt();

      if (_selectedTeamIds.isNotEmpty) {
        final assignments = _selectedTeamIds
            .map((teamId) => {
                  'task_id': taskId,
                  'team_id': teamId,
                  'assigned_by': user.id,
                })
            .toList();
        await _client.from('club_task_team_assignments').insert(assignments);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _typeLabel(String value) {
    switch (value) {
      case 'wedstrijd':
        return 'Thuiswedstrijd';
      case 'fluiten':
        return 'Fluiten';
      case 'tellen':
        return 'Tellen';
      case 'kantine':
        return 'Kantinedienst';
      default:
        return 'Taak';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Taak aanmaken',
          style: TextStyle(color: AppColors.onBackground, fontWeight: FontWeight.w800),
        ),
        foregroundColor: AppColors.onBackground,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: !ctx.canManageTasks
          ? const Center(
              child: Text(
                'Geen rechten om taken aan te maken.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const Text(
                      'Type',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: DropdownButton<String>(
                        value: _type,
                        isExpanded: true,
                        dropdownColor: AppColors.card,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(
                            value: 'wedstrijd',
                            child: Text('Thuiswedstrijd'),
                          ),
                          DropdownMenuItem(value: 'fluiten', child: Text('Fluiten')),
                          DropdownMenuItem(value: 'tellen', child: Text('Tellen')),
                          DropdownMenuItem(value: 'kantine', child: Text('Kantinedienst')),
                        ],
                        onChanged: (v) => setState(() => _type = v ?? 'wedstrijd'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      value: _required,
                      onChanged: (v) => setState(() => _required = v),
                      activeThumbColor: AppColors.primary,
                      title: const Text(
                        'Verplicht',
                        style: TextStyle(
                          color: AppColors.onBackground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: const Text(
                        'Toon als belangrijke taak',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      child: ListTile(
                        title: const Text('Datum'),
                        subtitle: Text(
                          '${_date.day}-${_date.month}-${_date.year}',
                          style: const TextStyle(color: AppColors.onBackground),
                        ),
                        trailing: const Icon(Icons.edit_calendar, color: AppColors.primary),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setState(() => _date = picked);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      child: ListTile(
                        title: const Text('Tijd'),
                        subtitle: Text(
                          _time == null ? 'Optioneel' : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(color: AppColors.onBackground),
                        ),
                        trailing: const Icon(Icons.schedule, color: AppColors.primary),
                        onTap: () async {
                          final picked = await _pickTimeTyped();
                          if (picked != null) setState(() => _time = picked);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      style: const TextStyle(color: AppColors.onBackground),
                      decoration: const InputDecoration(
                        labelText: 'Locatie (optioneel)',
                      ),
                      onChanged: (v) => _location = v,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      style: const TextStyle(color: AppColors.onBackground),
                      decoration: const InputDecoration(
                        labelText: 'Notitie (optioneel)',
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Toewijzen aan teams',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tip: je mag dit leeg laten en later alsnog verdelen.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: _teams.map((t) {
                          final selected = _selectedTeamIds.contains(t.teamId);
                          return CheckboxListTile(
                            dense: true,
                            value: selected,
                            activeColor: AppColors.primary,
                            checkColor: AppColors.background,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedTeamIds.add(t.teamId);
                                } else {
                                  _selectedTeamIds.remove(t.teamId);
                                }
                              });
                            },
                            title: Text(
                              t.label,
                              style: const TextStyle(color: AppColors.onBackground),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_saving)
                      const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      ),
                  ],
                ),
    );
  }
}
*/