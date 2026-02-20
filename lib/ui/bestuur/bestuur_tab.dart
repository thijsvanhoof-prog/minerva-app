import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:minerva_app/ui/display_name_overrides.dart' show applyDisplayNameOverrides, unknownUserName;
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_api.dart';

class BestuurTab extends StatefulWidget {
  const BestuurTab({super.key});

  @override
  State<BestuurTab> createState() => _BestuurTabState();
}

class _BestuurTabState extends State<BestuurTab> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);
    final allowed = ctx.hasFullAdminRights || ctx.isInBestuur;

    if (!allowed) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Dit tabblad is alleen zichtbaar voor het bestuur.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: AppColors.tabContentPadding,
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                showBorder: false,
                showShadow: false,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: AppColors.darkBlue,
                    borderRadius: BorderRadius.circular(AppColors.cardRadius),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: const [
                    Tab(text: 'Commissies'),
                    Tab(text: 'Trainingen'),
                    Tab(text: 'Wedstrijden'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tabController.index,
                children: const [
                  _BestuurCommissiesView(),
                  _BestuurTrainingenView(),
                  _BestuurWedstrijdenView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ===================== Trainingen (bestuur) ===================== */

class _BestuurTrainingenView extends StatefulWidget {
  const _BestuurTrainingenView();

  @override
  State<_BestuurTrainingenView> createState() => _BestuurTrainingenViewState();
}

class _BestuurTrainingenViewState extends State<_BestuurTrainingenView> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sessions = const [];
  Map<int, String> _teamNameById = const {};
  DateTime? _fromDateLocal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<int, String>> _loadTeamNames(List<int> teamIds) async {
    if (teamIds.isEmpty) return {};

    const candidates = <String>[
      'team_name',
      'name',
      'short_name',
      'code',
      'team_code',
      'abbreviation',
    ];
    const idFields = <String>['team_id', 'id'];

    for (final idField in idFields) {
      for (final nameField in candidates) {
        try {
          final res = await _client
              .from('teams')
              .select('$idField, $nameField')
              .inFilter(idField, teamIds);
          final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
          final map = <int, String>{};
          for (final r in rows) {
            final id = (r[idField] as num?)?.toInt();
            if (id == null) continue;
            final name = (r[nameField] ?? '').toString().trim();
            map[id] = name;
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

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  String _formatRange(DateTime? start, DateTime? end) {
    if (start == null) return '-';
    final s = start.toLocal();
    final e = (end ?? start.add(const Duration(hours: 2))).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${two(s.day)}-${two(s.month)}-${s.year}';
    final st = '${two(s.hour)}:${two(s.minute)}';
    final et = '${two(e.hour)}:${two(e.minute)}';
    return '$date $st – $et';
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year}';
  }

  DateTime _startOfDayLocal(DateTime dt) {
    final d = dt.toLocal();
    return DateTime(d.year, d.month, d.day);
  }

  Future<void> _pickFromDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('nl', 'NL'),
      initialDate: _fromDateLocal ?? now,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Filter: vanaf datum',
    );
    if (picked == null) return;
    setState(() => _fromDateLocal = picked);
    await _load(); // only now "bring trainings forward" by filtering
  }

  Future<void> _clearFromDate() async {
    setState(() => _fromDateLocal = null);
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final query = _client
          .from('sessions')
          .select(
            'session_id, team_id, session_type, title, start_datetime, start_timestamp, end_timestamp, location, is_cancelled',
          )
          .eq('session_type', 'training');

      // When a date is chosen, bring trainings from that date forward (filter).
      // If not chosen, show all trainings (bounded for performance).
      final List<dynamic> res;
      if (_fromDateLocal != null) {
        final fromLocal = _startOfDayLocal(_fromDateLocal!);
        res = await query
            .gte('start_datetime', fromLocal.toUtc().toIso8601String())
            .order('start_datetime', ascending: true);
      } else {
        res = await query.order('start_datetime', ascending: true).limit(500);
      }

      final rows = res.cast<Map<String, dynamic>>();
      if (_fromDateLocal == null) {
        // Sorteer: eerst volgende datum bovenaan, verst onderaan.
        rows.sort((a, b) {
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
      }
      final teamIds = rows
          .map((r) => (r['team_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList()
        ..sort();

      final teamNames = await _loadTeamNames(teamIds);

      if (!mounted) return;
      setState(() {
        _sessions = rows;
        _teamNameById = teamNames;
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

  Future<void> _setCancelled({
    required int sessionId,
    required bool cancelled,
  }) async {
    try {
      await _client
          .from('sessions')
          .update({'is_cancelled': cancelled})
          .eq('session_id', sessionId);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      showTopMessage(context, cancelled ? 'Training geannuleerd.' : 'Training weer actief.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Kon training niet aanpassen: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          GlassCard(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Trainingen beheren',
                  style: TextStyle(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Annuleer trainingen (vakantie/feestdagen) en filter op datum.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickFromDate,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          _fromDateLocal == null
                              ? 'Filter: kies datum'
                              : 'Vanaf ${_formatDate(_fromDateLocal!)}',
                        ),
                      ),
                    ),
                    if (_fromDateLocal != null) ...[
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: 'Filter wissen',
                        onPressed: _clearFromDate,
                        icon: const Icon(Icons.close),
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.error))
          else ...[
            Builder(
              builder: (context) {
                final now = DateTime.now();
                final visible = _sessions.where((s) {
                  final start = _parseDate(s['start_datetime'] ?? s['start_timestamp']);
                  final end = _parseDate(s['end_timestamp']);
                  final einde = end ?? start?.add(const Duration(hours: 2));
                  return einde != null && einde.isAfter(now);
                }).toList();
                if (visible.isEmpty) {
                  return Text(
                    _fromDateLocal == null
                        ? 'Geen trainingen gevonden.'
                        : 'Geen trainingen gevonden vanaf ${_formatDate(_fromDateLocal!)}.',
                    style: const TextStyle(color: AppColors.textSecondary),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: visible.map((s) {
              final id = (s['session_id'] as num).toInt();
              final teamId = (s['team_id'] as num?)?.toInt();
              final teamLabel = teamId == null
                  ? 'Team'
                  : (_teamNameById[teamId]?.trim().isNotEmpty == true
                      ? NevoboApi.displayTeamName(_teamNameById[teamId]!.trim())
                      : '(naam ontbreekt)');
              final title = (s['title'] ?? 'Training').toString().trim();
              final loc = (s['location'] ?? '').toString().trim();
              final start = _parseDate(s['start_datetime'] ?? s['start_timestamp']);
              final end = _parseDate(s['end_timestamp']);
              final cancelled = s['is_cancelled'] == true;

              return GlassCard(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            teamLabel,
                            style: const TextStyle(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (cancelled)
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
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.onBackground,
                        fontWeight: FontWeight.w800,
                        decoration: cancelled ? TextDecoration.lineThrough : TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatRange(start, end),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        decoration: cancelled ? TextDecoration.lineThrough : TextDecoration.none,
                      ),
                    ),
                    if (loc.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        loc,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          decoration: cancelled ? TextDecoration.lineThrough : TextDecoration.none,
                        ),
                      ),
                    ],
                    if (AppUserContext.of(context).canManageBestuur) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _setCancelled(
                              sessionId: id,
                              cancelled: !cancelled,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cancelled ? AppColors.card : AppColors.error,
                              foregroundColor: cancelled ? AppColors.onBackground : Colors.white,
                              side: cancelled
                                  ? BorderSide(color: AppColors.primary.withValues(alpha: 0.35))
                                  : BorderSide.none,
                            ),
                            icon: Icon(cancelled ? Icons.undo : Icons.event_busy),
                            label: Text(cancelled ? 'Herstellen' : 'Annuleren'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/* ===================== Wedstrijden (bestuur) ===================== */

class _BestuurWedstrijdenView extends StatefulWidget {
  const _BestuurWedstrijdenView();

  @override
  State<_BestuurWedstrijdenView> createState() => _BestuurWedstrijdenViewState();
}

class _BestuurWedstrijdenViewState extends State<_BestuurWedstrijdenView> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loadingTeams = true;
  String? _error;
  List<NevoboTeam> _teams = const [];

  String? _expandedTeamCode;
  final Map<String, bool> _loadingMatchesByTeam = {};
  final Map<String, String> _errorByTeam = {};
  final Map<String, List<NevoboMatch>> _matchesByTeam = {};

  // match_key -> is_cancelled
  final Map<String, bool> _cancelledByMatchKey = {};
  final Map<String, String?> _reasonByMatchKey = {};

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  String _matchKey({required String teamCode, required DateTime start}) {
    return 'nevobo_match:${teamCode.trim().toUpperCase()}:${start.toUtc().toIso8601String()}';
  }

  Future<void> _loadTeams() async {
    setState(() {
      _loadingTeams = true;
      _error = null;
    });
    try {
      // Alle teams uit de tabel (zelfde bron als TC/Standen), inclusief training-only.
      final withIds = await NevoboApi.loadTeamsFromSupabaseWithIds(
        client: _client,
        excludeTrainingOnly: false,
      );
      if (!mounted) return;
      setState(() {
        _teams = withIds.map((e) => e.team).toList();
        _loadingTeams = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingTeams = false;
      });
    }
  }

  Future<void> _ensureMatchesLoaded(NevoboTeam team) async {
    final code = team.code;
    if (_matchesByTeam.containsKey(code)) return;
    if (_loadingMatchesByTeam[code] == true) return;
    setState(() {
      _loadingMatchesByTeam[code] = true;
      _errorByTeam.remove(code);
    });
    try {
      final matches = await NevoboApi.fetchMatchesForTeamViaCompetitionApi(team: team);
      final upcoming = matches.where((m) {
        final start = m.start;
        if (start == null) return false;
        return start.isAfter(DateTime.now().subtract(const Duration(hours: 2)));
      }).toList();

      // Load cancellation state for these matches (best-effort).
      await _loadCancellations(upcoming, teamCode: code);

      if (!mounted) return;
      setState(() {
        _matchesByTeam[code] = upcoming;
        _loadingMatchesByTeam[code] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorByTeam[code] = e.toString();
        _loadingMatchesByTeam[code] = false;
      });
    }
  }

  Future<void> _loadCancellations(List<NevoboMatch> matches, {required String teamCode}) async {
    final keys = <String>[];
    for (final m in matches) {
      final start = m.start;
      if (start == null) continue;
      keys.add(_matchKey(teamCode: teamCode, start: start));
    }
    if (keys.isEmpty) return;

    try {
      final res = await _client
          .from('match_cancellations')
          .select('match_key, is_cancelled, reason')
          .inFilter('match_key', keys);
      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      for (final r in rows) {
        final k = (r['match_key'] ?? '').toString();
        if (k.isEmpty) continue;
        _cancelledByMatchKey[k] = r['is_cancelled'] == true;
        final reason = (r['reason'] ?? '').toString().trim();
        _reasonByMatchKey[k] = reason.isEmpty ? null : reason;
      }
    } catch (_) {
      // Table missing or RLS: ignore (best-effort).
    }
  }

  Future<void> _setMatchCancelled({
    required NevoboTeam team,
    required NevoboMatch match,
    required bool cancelled,
  }) async {
    final start = match.start;
    if (start == null) return;
    final key = _matchKey(teamCode: team.code, start: start);

    String? reason = _reasonByMatchKey[key];
    if (cancelled) {
      final input = await showDialog<String>(
        context: context,
        builder: (context) {
          final c = TextEditingController(text: reason ?? '');
          return AlertDialog(
            title: const Text('Wedstrijd annuleren'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Reden (optioneel)',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: c,
                  decoration: const InputDecoration(
                    hintText: 'bijv. vakantie / onvoldoende spelers',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Annuleren'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(c.text.trim()),
                child: const Text('Opslaan'),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      if (input == null) return; // cancelled dialog
      reason = input.isEmpty ? null : input;
    } else {
      reason = null;
    }

    try {
      await _client.from('match_cancellations').upsert(
        {
          'match_key': key,
          'team_code': team.code,
          'starts_at': start.toUtc().toIso8601String(),
          'summary': match.summary,
          'location': (match.location ?? '').trim(),
          'is_cancelled': cancelled,
          'reason': reason,
          'updated_by': _client.auth.currentUser?.id,
        },
        onConflict: 'match_key',
      );

      if (!mounted) return;
      setState(() {
        _cancelledByMatchKey[key] = cancelled;
        _reasonByMatchKey[key] = reason;
      });
      showTopMessage(context, cancelled ? 'Wedstrijd geannuleerd.' : 'Annulering verwijderd.');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      // Helpful hint when the table isn't installed.
      if (e.code == '42P01' || e.message.toLowerCase().contains('does not exist')) {
        showTopMessage(
          context,
          'Tabel `match_cancellations` ontbreekt in Supabase. Voeg hem toe via SQL (zie supabase/).',
          isError: true,
        );
        return;
      }
      showTopMessage(context, 'Kon niet opslaan: $e', isError: true);
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Kon niet opslaan: $e', isError: true);
    }
  }

  void _toggleExpanded(String code) {
    setState(() {
      _expandedTeamCode = (_expandedTeamCode == code) ? null : code;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingTeams && _teams.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
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

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadTeams,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _teams.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final team = _teams[i];
          final expanded = _expandedTeamCode == team.code;
          final loadingMatches = _loadingMatchesByTeam[team.code] == true;
          final matches = _matchesByTeam[team.code] ?? const [];
          final err = _errorByTeam[team.code];

          return GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(AppColors.cardRadius),
                  onTap: () {
                    _toggleExpanded(team.code);
                    if (!expanded) {
                      // ignore: unawaited_futures
                      _ensureMatchesLoaded(team);
                    }
                  },
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
                            NevoboApi.displayTeamCode(team.code),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        const Spacer(),
                        if (expanded && loadingMatches)
                          const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          )
                        else
                          Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
                            color: AppColors.textSecondary,
                          ),
                      ],
                    ),
                  ),
                ),
                if (!expanded) const SizedBox.shrink() else ...[
                  const SizedBox(height: 12),
                  if (err != null)
                    Text(err, style: const TextStyle(color: AppColors.error))
                  else if (matches.isEmpty && !loadingMatches)
                    const Text(
                      'Geen aankomende wedstrijden gevonden.',
                      style: TextStyle(color: AppColors.textSecondary),
                    )
                  else
                    ...matches.take(10).map((m) {
                      final start = m.start;
                      if (start == null) return const SizedBox.shrink();
                      final key = _matchKey(teamCode: team.code, start: start);
                      final cancelled = _cancelledByMatchKey[key] == true;
                      final reason = _reasonByMatchKey[key];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GlassCard(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _formatDateTime(start),
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (cancelled)
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
                              const SizedBox(height: 2),
                              Text(
                                NevoboApi.displayTeamName(m.summary),
                                style: TextStyle(
                                  color: AppColors.onBackground,
                                  fontWeight: FontWeight.w800,
                                  decoration: cancelled ? TextDecoration.lineThrough : TextDecoration.none,
                                ),
                              ),
                              if ((m.location ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  (m.location ?? '').trim(),
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    decoration: cancelled ? TextDecoration.lineThrough : TextDecoration.none,
                                  ),
                                ),
                              ],
                              if (cancelled && reason != null && reason.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Reden: $reason',
                                  style: const TextStyle(color: AppColors.textSecondary),
                                ),
                              ],
                              if (AppUserContext.of(context).canManageBestuur) ...[
                                const SizedBox(height: 10),
                                ElevatedButton.icon(
                                  onPressed: () => _setMatchCancelled(
                                    team: team,
                                    match: m,
                                    cancelled: !cancelled,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: cancelled ? AppColors.card : AppColors.error,
                                    foregroundColor: cancelled ? AppColors.onBackground : Colors.white,
                                    side: cancelled
                                        ? BorderSide(color: AppColors.primary.withValues(alpha: 0.35))
                                        : BorderSide.none,
                                  ),
                                  icon: Icon(cancelled ? Icons.undo : Icons.event_busy),
                                  label: Text(cancelled ? 'Herstellen' : 'Annuleren'),
                                ),
                              ],
                            ],
                          ),
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

/* ===================== Commissies (bestuur) ===================== */

class _BestuurCommissiesView extends StatefulWidget {
  const _BestuurCommissiesView();

  @override
  State<_BestuurCommissiesView> createState() => _BestuurCommissiesViewState();
}

class _BestuurCommissiesViewState extends State<_BestuurCommissiesView> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loadingCommittees = true;
  String? _committeeError;

  final List<String> _committees = [];
  final Map<String, List<_CommitteeMember>> _membersByCommittee = {};

  List<_ProfileOption> _allProfiles = const [];
  bool _loadingProfiles = false;

  static const _manageableCommittees = [
    'bestuur',
    'technische-commissie',
    'communicatie',
    'wedstrijdzaken',
  ];

  @override
  void initState() {
    super.initState();
    _loadCommittees();
    _loadAllProfilesForManagement();
  }

  String _normalizeCommittee(String value) {
    final c = value.trim().toLowerCase();
    if (c.isEmpty) return '';
    if (c == 'bestuur') return 'bestuur';
    if (c == 'tc' || c.contains('technische')) return 'technische-commissie';
    if (c.contains('communicatie')) return 'communicatie';
    if (c.contains('wedstrijd')) return 'wedstrijdzaken';
    return c;
  }

  String _committeeLabel(String value) {
    switch (value) {
      case 'bestuur':
        return 'Bestuur';
      case 'technische-commissie':
        return 'Technische commissie';
      case 'communicatie':
        return 'Communicatie commissie';
      case 'wedstrijdzaken':
        return 'Wedstrijdzaken';
      default:
        return value;
    }
  }

  Future<Map<String, String>> _loadProfileNames({required List<String> profileIds}) async {
    if (profileIds.isEmpty) return {};
    try {
      final res = await _client
          .from('profiles')
          .select('id, display_name, full_name, email')
          .inFilter('id', profileIds);
      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final map = <String, String>{};
      for (final row in rows) {
        final id = row['id']?.toString() ?? '';
        final name = (row['display_name'] ?? row['full_name'] ?? row['email'] ?? '').toString();
        if (id.isNotEmpty) map[id] = applyDisplayNameOverrides(name);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> _loadAllProfilesForManagement() async {
    setState(() => _loadingProfiles = true);
    List<_ProfileOption> list = [];
    List<_ProfileOption> normalizeRows(List<dynamic>? rawRows) {
      final rows = rawRows?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      final out = <_ProfileOption>[];
      for (final p in rows) {
        final id = (p['profile_id'] ?? p['id'])?.toString() ?? '';
        if (id.isEmpty) continue;
        final rawName = (p['display_name'] ?? p['full_name'] ?? p['name'] ?? '').toString().trim();
        final name = applyDisplayNameOverrides(rawName);
        final email = (p['email'] ?? '').toString().trim();
        out.add(_ProfileOption(
          profileId: id,
          name: name.isNotEmpty ? name : (email.isNotEmpty ? email : unknownUserName),
          email: email.isNotEmpty ? email : null,
        ));
      }
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    }

    // 1) Preferred for bestuur
    for (final rpc in const [
      'list_profiles_for_committee_management',
      // Extra fallbacks (same shape) in case one RPC is missing/broken in DB.
      'admin_list_profiles',
      'get_profiles_for_tc',
    ]) {
      try {
        final res = await _client.rpc(rpc);
        final parsed = normalizeRows(res as List<dynamic>?);
        if (parsed.isNotEmpty) {
          list = parsed;
          break;
        }
      } catch (_) {}
    }

    // 2) Last fallback: direct profiles select (werkt alleen als RLS het toelaat).
    if (list.isEmpty) {
      List<Map<String, dynamic>> raw = const [];
      for (final select in const [
        'id, display_name, full_name, email',
        'id, display_name, email',
        'id, full_name, email',
        'id, name, email',
        'id, email',
      ]) {
        try {
          final res = await _client.from('profiles').select(select);
          raw = (res as List<dynamic>).cast<Map<String, dynamic>>();
          break;
        } catch (_) {}
      }
      list = normalizeRows(raw);
    }
    if (!mounted) return;
    setState(() {
      _allProfiles = list;
      _loadingProfiles = false;
    });
  }

  Future<void> _loadCommittees() async {
    setState(() {
      _loadingCommittees = true;
      _committeeError = null;
      _committees.clear();
      _membersByCommittee.clear();
    });

    try {
      List<Map<String, dynamic>> rows = [];
      try {
        final res = await _client.rpc('get_committee_members_with_names');
        rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      } catch (_) {}

      if (rows.isEmpty) {
        for (final select in const [
          'committee_name, profile_id, function',
          'committee_name, profile_id, role',
          'committee_name, profile_id, title',
          'committee_name, profile_id',
        ]) {
          try {
            final res = await _client.from('committee_members').select(select);
            rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
            break;
          } catch (_) {}
        }
      }

      if (rows.isEmpty) {
        if (!mounted) return;
        setState(() => _loadingCommittees = false);
        return;
      }

      final committeeKeys = <String>{};
      final profileIds = <String>{};
      for (final row in rows) {
        final key = _normalizeCommittee(row['committee_name']?.toString() ?? '');
        if (key.isEmpty) continue;
        committeeKeys.add(key);
        final pid = row['profile_id']?.toString() ?? '';
        if (pid.isNotEmpty) profileIds.add(pid);
      }

      final nameByProfileId = await _loadProfileNames(profileIds: profileIds.toList());

      for (final row in rows) {
        final key = _normalizeCommittee(row['committee_name']?.toString() ?? '');
        if (key.isEmpty) continue;

        final pid = row['profile_id']?.toString() ?? '';
        final displayNameFromRow = (row['display_name'] ?? row['name'])?.toString().trim();
        final memberName = (displayNameFromRow?.isNotEmpty == true)
            ? applyDisplayNameOverrides(displayNameFromRow!)
            : applyDisplayNameOverrides((nameByProfileId[pid] ?? '').trim());
        final displayName = memberName.isNotEmpty ? memberName : unknownUserName;

        final function = (row['function'] ?? row['role'] ?? row['title'])?.toString();
        _membersByCommittee.putIfAbsent(key, () => []).add(
              _CommitteeMember(
                profileId: pid,
                name: displayName,
                function: function?.trim().isEmpty == true ? null : function?.trim(),
              ),
            );
      }

      final list = committeeKeys.toList()..sort();
      for (final k in list) {
        final members = _membersByCommittee[k] ?? [];
        members.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _membersByCommittee[k] = members;
      }

      if (!mounted) return;
      setState(() {
        _committees.addAll(list);
        _loadingCommittees = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _committeeError = e.toString();
        _loadingCommittees = false;
      });
    }
  }

  Future<bool> _updateCommitteeMemberFunction({
    required String committeeKey,
    required String profileId,
    required String? value,
  }) async {
    const candidates = [
      'function',
      'role',
      'title',
      'functie',
      'rol',
      'position',
      'positie',
    ];
    Object? lastError;
    for (final field in candidates) {
      try {
        final res = await _client
            .from('committee_members')
            .update({field: value})
            .eq('committee_name', committeeKey)
            .eq('profile_id', profileId)
            .select('profile_id');
        final rows = (res as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? const [];
        if (rows.isEmpty) throw StateError('Geen rij bijgewerkt.');
        return true;
      } on PostgrestException catch (e) {
        lastError = e;
        if (e.code == 'PGRST204' ||
            (e.message.contains("Could not find the '") && e.message.contains("column"))) {
          continue;
        }
        rethrow;
      } catch (e) {
        lastError = e;
        rethrow;
      }
    }
    if (lastError is PostgrestException) return false;
    return false;
  }

  Future<void> _addMemberToCommittee(String committeeKey) async {
    // Als de profielenlijst leeg is, eerst opnieuw laden (bijv. na eerdere fout).
    if (_allProfiles.isEmpty) {
      await _loadAllProfilesForManagement();
      if (!mounted) return;
    }
    final alreadyIn =
        (_membersByCommittee[committeeKey] ?? []).map((m) => m.profileId).toSet();
    final available =
        _allProfiles.where((p) => !alreadyIn.contains(p.profileId)).toList();
    if (available.isEmpty) {
      if (_allProfiles.isEmpty) {
        showTopMessage(
          context,
          'Kon de ledenlijst niet laden. Trek omlaag om te vernieuwen en probeer het opnieuw.',
          isError: true,
        );
      } else {
        showTopMessage(context, 'Iedereen zit al in deze commissie.', isError: true);
      }
      return;
    }
    var search = '';
    final chosen = await showDialog<_ProfileOption>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = search.trim().toLowerCase();
          final list = q.isEmpty
              ? available
              : available
                  .where((p) =>
                      p.name.toLowerCase().contains(q) ||
                      (p.email?.toLowerCase().contains(q) ?? false))
                  .toList();
          return AlertDialog(
            title: Text('Lid toevoegen aan ${_committeeLabel(committeeKey)}'),
            content: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppColors.cardRadius - 6),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.22),
                  width: 1.1,
                ),
              ),
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                width: double.maxFinite,
                height: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Zoek op naam of e-mail',
                      ),
                      onChanged: (v) => setDialogState(() => search = v),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: list.isEmpty
                          ? const Center(
                              child: Text(
                                'Geen leden gevonden.',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          : ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (context, i) {
                                final p = list[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    p.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: p.email != null
                                      ? Text(
                                          p.email!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        )
                                      : null,
                                  onTap: () => Navigator.of(context).pop(p),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Annuleren'),
              ),
            ],
          );
        },
      ),
    );
    if (chosen == null) return;
    if (!mounted) return;

    var function = '';
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Functie (optioneel)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(chosen.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (chosen.email != null) ...[
                const SizedBox(height: 4),
                Text(
                  chosen.email!,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Functie of rol',
                  hintText: 'bijv. Voorzitter',
                ),
                onChanged: (v) => function = v.trim(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuleren'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Toevoegen'),
            ),
          ],
        ),
      ),
    );
    if (save != true) return;

    try {
      await _client.from('committee_members').insert({
        'committee_name': committeeKey,
        'profile_id': chosen.profileId,
      });
      if (function.isNotEmpty) {
        final updated = await _updateCommitteeMemberFunction(
          committeeKey: committeeKey,
          profileId: chosen.profileId,
          value: function,
        );
        if (!updated && mounted) {
          showTopMessage(
            context,
            'Let op: je database heeft geen functie/rol-kolom; functie kon niet worden opgeslagen.',
            isError: true,
          );
        }
      }
      if (!mounted) return;
      showTopMessage(context, 'Lid toegevoegd aan commissie.');
      await _loadCommittees();
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Toevoegen mislukt: $e', isError: true);
    }
  }

  Future<void> _editOrRemoveCommitteeMember(
    String committeeKey,
    _CommitteeMember member,
  ) async {
    var draftFunction = member.function ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Lid in ${_committeeLabel(committeeKey)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(member.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: draftFunction,
                decoration: const InputDecoration(labelText: 'Functie of rol'),
                onChanged: (v) => setDialogState(() => draftFunction = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('remove'),
              child: Text('Uit commissie halen', style: TextStyle(color: AppColors.error)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Annuleren'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('Opslaan'),
            ),
          ],
        ),
      ),
    );
    final newFunction = draftFunction.trim();
    if (result == null) return;

    if (result == 'remove') {
      try {
        await _client
            .from('committee_members')
            .delete()
            .eq('committee_name', committeeKey)
            .eq('profile_id', member.profileId);
        if (!mounted) return;
        showTopMessage(context, 'Lid uit commissie gehaald.');
        await _loadCommittees();
      } catch (e) {
        if (!mounted) return;
        showTopMessage(context, 'Verwijderen mislukt: $e', isError: true);
      }
      return;
    }

    if (result == 'save') {
      try {
        final updated = await _updateCommitteeMemberFunction(
          committeeKey: committeeKey,
          profileId: member.profileId,
          value: newFunction.isEmpty ? null : newFunction,
        );
        if (!mounted) return;
        showTopMessage(
          context,
          updated
              ? 'Functie bijgewerkt.'
              : 'Je database heeft geen functie/rol-kolom; wijziging niet opgeslagen.',
          isError: !updated,
        );
        await _loadCommittees();
      } catch (e) {
        if (!mounted) return;
        showTopMessage(context, 'Bijwerken mislukt: $e', isError: true);
      }
    }
  }

  Future<void> _refreshCommitteesAndProfiles() async {
    await Future.wait([_loadCommittees(), _loadAllProfilesForManagement()]);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshCommitteesAndProfiles,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Commissies beheren',
                  style: TextStyle(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Voeg leden toe, pas functies aan of verwijder leden uit commissies.',
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
                if (_loadingProfiles) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Profielen laden...',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_committeeError != null)
            Text(_committeeError!, style: const TextStyle(color: AppColors.error))
          else if (_loadingCommittees)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_committees.isEmpty)
            const Text(
              'Geen commissies gevonden.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            ..._manageableCommittees.map((c) {
              final members = _membersByCommittee[c] ?? const [];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(
                          _committeeLabel(c),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (members.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Text(
                            'Geen leden in deze commissie.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        )
                      else
                        ...members.map((m) {
                          final suffix = (m.function != null && m.function!.isNotEmpty)
                              ? ' · ${m.function}'
                              : '';
                          return ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.person_outline,
                              color: AppColors.iconMuted,
                              size: 22,
                            ),
                            title: Text(
                              '${m.name}$suffix',
                              style: const TextStyle(
                                color: AppColors.onBackground,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            trailing: Icon(
                              Icons.edit_outlined,
                              color: AppUserContext.of(context).canManageBestuur
                                  ? AppColors.primary
                                  : AppColors.iconMuted,
                              size: 20,
                            ),
                            onTap: AppUserContext.of(context).canManageBestuur
                                ? () => _editOrRemoveCommitteeMember(c, m)
                                : null,
                          );
                        }),
                      if (AppUserContext.of(context).canManageBestuur)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.person_add_outlined, color: AppColors.primary, size: 22),
                          title: const Text(
                            'Lid toevoegen aan deze commissie',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          onTap: _loadingProfiles ? null : () => _addMemberToCommittee(c),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _CommitteeMember {
  final String profileId;
  final String name;
  final String? function;

  const _CommitteeMember({
    required this.profileId,
    required this.name,
    required this.function,
  });
}

class _ProfileOption {
  final String profileId;
  final String name;
  final String? email;

  const _ProfileOption({
    required this.profileId,
    required this.name,
    this.email,
  });
}

