import 'package:flutter/material.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/data/mock_home_data.dart';
import 'package:minerva_app/models/news_item.dart';
import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/display_name_overrides.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_api.dart';

/// Home-tab van VV Minerva. Stap voor stap herbouwd.
///
/// Stap 1: Minimale basis – scaffold, AppBar, welkomsttekst
/// Stap 2: Sectiestructuur – tabs voor Uitgelicht, Agenda, Nieuws
/// Stap 3: Uitgelicht – highlights laden (Supabase of mock) en horizontale kaarten
/// Stap 4: Agenda – agenda laden, kaarten, RSVP
/// Stap 5: Nieuwsberichten – NewsItem + mockNews (zoals oorspronkelijk)
/// Stap 6: Afronden – refresh, foutmeldingen, admin-actions (highlights)
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with SingleTickerProviderStateMixin {
  final SupabaseClient _client = Supabase.instance.client;

  late final TabController _tabController;

  bool _loadingHighlights = true;
  String? _highlightsError;
  List<_Highlight> _highlights = const [];

  bool _loadingAgenda = true;
  String? _agendaError;
  List<_AgendaItem> _agendaItems = const [];
  Set<int> _myRsvpAgendaIds = const {};

  // Agenda sub-tab: 0 = agenda, 1 = aanmeldingen (bestuur/communicatie)
  int _agendaMode = 0;
  bool _loadingAgendaRsvps = false;
  String? _agendaRsvpsError;
  Map<int, List<_AgendaSignup>> _rsvpsByAgendaId = const {};

  bool _loadingNews = true;
  String? _newsError;
  List<NewsItem> _newsItems = const [];
  bool _newsFromSupabase = false;
  String _newsIdField = 'news_id';

  NewsCategory _categoryFromDb(dynamic v) {
    final s = (v ?? '').toString().trim().toLowerCase();
    switch (s) {
      case 'tc':
      case 'technische commissie':
      case 'technische-commissie':
        return NewsCategory.tc;
      case 'communicatie':
        return NewsCategory.communicatie;
      case 'team':
        return NewsCategory.team;
      case 'bestuur':
      default:
        return NewsCategory.bestuur;
    }
  }

  DateTime? _parseVisibleUntil(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) {
      final local = raw.toLocal();
      if (local.hour == 0 &&
          local.minute == 0 &&
          local.second == 0 &&
          local.millisecond == 0) {
        return DateTime(local.year, local.month, local.day, 23, 59, 59);
      }
      return local;
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    // Date-only (YYYY-MM-DD) -> treat as end-of-day local.
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
      final d = DateTime.tryParse(s);
      if (d == null) return null;
      return DateTime(d.year, d.month, d.day, 23, 59, 59);
    }
    final dt = DateTime.tryParse(s);
    if (dt == null) return null;
    final local = dt.toLocal();
    if (local.hour == 0 &&
        local.minute == 0 &&
        local.second == 0 &&
        local.millisecond == 0) {
      return DateTime(local.year, local.month, local.day, 23, 59, 59);
    }
    return local;
  }

  bool _isVisibleNow(DateTime? visibleUntil) {
    if (visibleUntil == null) return true;
    // show through the end moment (inclusive)
    return !DateTime.now().isAfter(visibleUntil);
  }

  Future<DateTime?> _pickVisibleUntilDate(DateTime? current) async {
    final now = DateTime.now();
    final initial = current ?? now;
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('nl', 'NL'),
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Tonen tot (optioneel)',
    );
    if (picked == null) return current;
    // Treat as end-of-day local.
    return DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
  }

  Future<void> _refreshHome() async {
    await _loadHighlights();
    await _loadAgenda();
    await _loadNews();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0);
    _loadHighlights();
    _loadAgenda();
    _loadNews();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHighlights() async {
    setState(() {
      _loadingHighlights = true;
      _highlightsError = null;
    });

    try {
      // Best-effort: support optional `visible_until` column.
      List<dynamic> res;
      try {
        res = await _client
            .from('home_highlights')
            .select('highlight_id, title, subtitle, icon_name, visible_until')
            .order('created_at', ascending: false);
      } catch (_) {
        res = await _client
            .from('home_highlights')
            .select('highlight_id, title, subtitle, icon_name')
            .order('created_at', ascending: false);
      }

      final rows = res.cast<Map<String, dynamic>>();
      final list = rows.map((r) {
        final until = _parseVisibleUntil(r['visible_until']);
        return _Highlight(
          id: (r['highlight_id'] as num).toInt(),
          title: (r['title'] as String?) ?? '',
          subtitle: (r['subtitle'] as String?) ?? '',
          iconText: (r['icon_name'] as String?) ?? '🏐',
          visibleUntil: until,
        );
      }).where((h) => _isVisibleNow(h.visibleUntil)).toList();

      setState(() {
        _highlights = list;
        _loadingHighlights = false;
      });
    } catch (e) {
      setState(() {
        _highlights = _mockHighlights();
        _highlightsError = e.toString();
        _loadingHighlights = false;
      });
    }
  }

  Future<void> _loadAgenda() async {
    setState(() {
      _loadingAgenda = true;
      _agendaError = null;
    });

    try {
      List<Map<String, dynamic>> rows = [];
      for (final attempt in const [
        ('agenda_id, title, description, start_datetime, end_datetime, location, can_rsvp', 'start_datetime'),
        ('agenda_id, title, description, start_datetime, location, can_rsvp', 'start_datetime'),
        ('agenda_id, title, start_datetime, end_datetime, location, can_rsvp', 'start_datetime'),
        ('agenda_id, title, start_datetime, location, can_rsvp', 'start_datetime'),
        ('agenda_id, title, starts_at, location, can_rsvp', 'starts_at'),
        ('agenda_id, title, start_at, location, can_rsvp', 'start_at'),
        ('agenda_id, title, when, where, can_rsvp', null),
        ('agenda_id, title, start_datetime, location', 'start_datetime'),
        ('agenda_id, title, starts_at, location', 'starts_at'),
        ('agenda_id, title, start_at, location', 'start_at'),
      ]) {
        try {
          final select = attempt.$1;
          final orderColumn = attempt.$2;
          final res = orderColumn == null
              ? await _client.from('home_agenda').select(select)
              : await _client
                  .from('home_agenda')
                  .select(select)
                  .order(orderColumn, ascending: true);
          rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
          break;
        } catch (_) {}
      }

      if (rows.isEmpty) {
        setState(() {
          _agendaItems = _mockAgenda();
          _myRsvpAgendaIds = const {};
          _loadingAgenda = false;
        });
        return;
      }

      final items = <_AgendaItem>[];
      for (final row in rows) {
        final id = (row['agenda_id'] as num?)?.toInt();
        if (id == null) continue;

        final title = (row['title'] as String?) ?? '';
        final description = (row['description'] as String?)?.trim();
        final canRsvp = (row['can_rsvp'] as bool?) ?? false;
        final location =
            (row['location'] ?? row['where'] ?? row['locatie'])?.toString() ?? '';

        DateTime? start;
        final rawStart = row['start_datetime'] ?? row['starts_at'] ?? row['start_at'];
        if (rawStart is DateTime) {
          start = rawStart;
        } else if (rawStart != null) {
          start = DateTime.tryParse(rawStart.toString());
        }

        DateTime? end;
        final rawEnd = row['end_datetime'] ?? row['ends_at'] ?? row['end_at'];
        if (rawEnd is DateTime) {
          end = rawEnd;
        } else if (rawEnd != null) {
          end = DateTime.tryParse(rawEnd.toString());
        }

        final whenLabel = start != null
            ? _formatDateTimeShort(start)
            : (row['when']?.toString() ?? '');
        final dateLabel = start != null ? _formatDate(start) : null;
        final timeLabel = start != null ? _formatTime(start) : null;
        final endDateLabel = end != null ? _formatDate(end) : null;
        final endTimeLabel = end != null ? _formatTime(end) : null;

        items.add(
          _AgendaItem(
            id: id,
            title: title,
            description: description != null && description.isNotEmpty ? description : null,
            when: whenLabel,
            where: location,
            canRsvp: canRsvp,
            startDatetime: start,
            endDatetime: end,
            dateLabel: dateLabel,
            timeLabel: timeLabel,
            endDateLabel: endDateLabel,
            endTimeLabel: endTimeLabel,
          ),
        );
      }

      final user = _client.auth.currentUser;
      final agendaIdsWithRsvp =
          items.where((a) => a.canRsvp).map((a) => a.id!).toList();
      Set<int> myRsvps = {};
      if (user != null && agendaIdsWithRsvp.isNotEmpty) {
        try {
          final res = await _client
              .from('home_agenda_rsvps')
              .select('agenda_id')
              .eq('profile_id', user.id)
              .inFilter('agenda_id', agendaIdsWithRsvp);
          final rsvpRows = (res as List<dynamic>).cast<Map<String, dynamic>>();
          myRsvps = rsvpRows
              .map((r) => (r['agenda_id'] as num?)?.toInt())
              .whereType<int>()
              .toSet();
        } catch (_) {}
      }

      setState(() {
        _agendaItems = items;
        _myRsvpAgendaIds = myRsvps;
        _loadingAgenda = false;
      });

      // Best-effort: if the user is allowed to view RSVPs and has selected the RSVPs tab,
      // load RSVPs after agenda is available.
      try {
        if (!mounted) return;
        final ctx = AppUserContext.of(context);
        if (ctx.canViewAgendaRsvps && _agendaMode == 1) {
          // Don't await; keep agenda UI responsive.
          // ignore: unawaited_futures
          _loadAgendaRsvps();
        }
      } catch (_) {}
    } catch (e) {
      setState(() {
        _agendaItems = _mockAgenda();
        _myRsvpAgendaIds = const {};
        _agendaError = e.toString();
        _loadingAgenda = false;
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

    // Preferred: security definer RPC so names work even with restrictive RLS on profiles.
    try {
      final res =
          await _client.rpc('get_profile_display_names', params: {'profile_ids': ids});
      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final map = <String, String>{};
      for (final r in rows) {
        final id = r['profile_id']?.toString() ?? r['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final raw = (r['display_name'] ?? '').toString().trim();
        final name = applyDisplayNameOverrides(raw);
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
      map[id] = name.isNotEmpty ? name : _shortId(id);
    }
    return map;
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
          final List<dynamic> tRows = await _client
              .from('teams')
              .select('$idField, $nameField')
              .inFilter(idField, teamIds);

          final map = <int, String>{};
          for (final row in tRows) {
            final t = row as Map<String, dynamic>;
            final tid = (t[idField] as num?)?.toInt();
            if (tid == null) continue;
            final name = (t[nameField] as String?) ?? '';
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

  Future<void> _loadAgendaRsvps() async {
    final ctx = AppUserContext.of(context);
    if (!ctx.canViewAgendaRsvps) return;

    final agendaIds = _agendaItems.where((a) => a.canRsvp).map((a) => a.id).whereType<int>().toList();
    if (agendaIds.isEmpty) {
      if (mounted) {
        setState(() {
          _rsvpsByAgendaId = const {};
          _agendaRsvpsError = null;
          _loadingAgendaRsvps = false;
        });
      }
      return;
    }

    setState(() {
      _loadingAgendaRsvps = true;
      _agendaRsvpsError = null;
    });

    try {
      // Fetch RSVPs (best-effort column variants)
      List<Map<String, dynamic>> rows = const [];
      for (final select in const [
        'agenda_id, profile_id, created_at',
        'agenda_id, profile_id',
      ]) {
        try {
          final res = await _client
              .from('home_agenda_rsvps')
              .select(select)
              .inFilter('agenda_id', agendaIds);
          rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
          break;
        } catch (_) {}
      }

      final profileIds = <String>{};
      for (final r in rows) {
        final pid = r['profile_id']?.toString() ?? '';
        if (pid.isNotEmpty) profileIds.add(pid);
      }

      final nameById = await _loadProfileDisplayNames(profileIds);

      // Load team memberships for these profiles to show the linked team(s).
      final teamIds = <int>{};
      final teamIdsByProfile = <String, Set<int>>{};
      if (profileIds.isNotEmpty) {
        try {
          // Only show teams where the member is linked as a player.
          // (So trainer/coach/guardian entries are ignored here.)
          List<dynamic> res;
          try {
            res = await _client
                .from('team_members')
                .select('profile_id, team_id, role')
                .inFilter('profile_id', profileIds.toList());
          } catch (_) {
            // If schema/RLS prevents selecting role, we can't reliably filter → show no teams.
            res = const [];
          }
          final tmRows = res.cast<Map<String, dynamic>>();
          for (final r in tmRows) {
            final pid = r['profile_id']?.toString() ?? '';
            final tid = (r['team_id'] as num?)?.toInt();
            final role = (r['role'] ?? '').toString().trim().toLowerCase();
            if (pid.isEmpty || tid == null) continue;
            final isPlayer = role == 'player' || role == 'speler';
            if (!isPlayer) continue;
            teamIds.add(tid);
            teamIdsByProfile.putIfAbsent(pid, () => <int>{}).add(tid);
          }
        } catch (_) {
          // ignore (schema/RLS)
        }
      }

      final teamNamesById = await _loadTeamNames(teamIds: teamIds.toList()..sort());

      List<String> teamLabelsFor(String profileId) {
        final ids = teamIdsByProfile[profileId]?.toList() ?? const [];
        final out = <String>[];
        for (final tid in ids) {
          final raw = (teamNamesById[tid] ?? '').trim();
          final code = raw.isNotEmpty ? (NevoboApi.extractCodeFromTeamName(raw) ?? raw) : '';
          out.add(code.isNotEmpty ? code : 'Team $tid');
        }
        out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return out;
      }

      final byAgenda = <int, List<_AgendaSignup>>{};
      for (final r in rows) {
        final aid = (r['agenda_id'] as num?)?.toInt();
        final pid = r['profile_id']?.toString() ?? '';
        if (aid == null || pid.isEmpty) continue;
        final rawName = (nameById[pid] ?? '').trim();
        final name = rawName.isNotEmpty ? rawName : _shortId(pid);
        final createdAtValue = r['created_at'];
        final createdAt = createdAtValue is DateTime
            ? createdAtValue
            : (createdAtValue != null ? DateTime.tryParse(createdAtValue.toString()) : null);
        byAgenda.putIfAbsent(aid, () => []).add(
              _AgendaSignup(
                agendaId: aid,
                profileId: pid,
                name: name,
                teamLabels: teamLabelsFor(pid),
                createdAt: createdAt,
              ),
            );
      }
      for (final e in byAgenda.entries) {
        e.value.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }

      if (!mounted) return;
      setState(() {
        _rsvpsByAgendaId = byAgenda;
        _loadingAgendaRsvps = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _agendaRsvpsError = e.toString();
        _loadingAgendaRsvps = false;
      });
    }
  }

  Widget _buildAgendaListView({required bool canManageAgenda}) {
    final hasRsvp = _agendaItems.any((a) => a.canRsvp);
    final showRsvpInfo = hasRsvp && _agendaItems.isNotEmpty;
    final extraRows = showRsvpInfo ? 1 : 0;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshHome,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: 1 + (_agendaItems.isEmpty ? 1 : _agendaItems.length + extraRows),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _HomeTabHeader(
              title: 'Agenda',
              trailing: canManageAgenda
                  ? IconButton(
                      tooltip: 'Activiteit toevoegen',
                      icon: const Icon(Icons.add_circle_outline),
                      color: AppColors.primary,
                      onPressed: () => _openAddAgendaDialog(),
                    )
                  : (_loadingAgenda
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : null),
            );
          }

          if (_agendaItems.isEmpty) {
            if (_agendaError != null && canManageAgenda) {
              return Text(
                'Let op: agenda tabel/RSVP niet beschikbaar.\n'
                'Voeg Supabase tabellen `home_agenda` + `home_agenda_rsvps` toe.\n'
                'Details: $_agendaError',
                style: const TextStyle(color: AppColors.textSecondary),
              );
            }
            return const Text(
              'Geen items in de agenda.',
              style: TextStyle(color: AppColors.textSecondary),
            );
          }

          if (showRsvpInfo && i == 1) {
            return Text(
              'Bij aanmelden slaan we je naam en (spelers)team op. '
              'Dit is zichtbaar voor Bestuur/Communicatie. Je kunt altijd weer afmelden.',
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.9),
                fontSize: 12.5,
              ),
            );
          }

          final itemIndex = showRsvpInfo ? (i - 2) : (i - 1);
          final item = _agendaItems[itemIndex];
          final signedUp = item.id != null && _myRsvpAgendaIds.contains(item.id);
          final enabled = item.canRsvp && item.id != null;
          return _AgendaCard(
            item: item,
            signedUp: signedUp,
            enabled: enabled,
            canManage: canManageAgenda,
            onToggleRsvp: () => _toggleAgendaRsvp(item),
            onReadMore: () => _showAgendaDetail(item),
            onEdit: item.id != null ? () => _openEditAgendaDialog(item) : null,
            onDelete: item.id != null ? () => _deleteAgendaItem(item) : null,
          );
        },
      ),
    );
  }

  Widget _buildAgendaRsvpsView() {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadAgendaRsvps,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _HomeTabHeader(
            title: 'Aanmeldingen',
            trailing: _loadingAgendaRsvps
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          if (_agendaRsvpsError != null)
            Text(
              _agendaRsvpsError!,
              style: const TextStyle(color: AppColors.error),
            )
          else ...[
            if (_agendaItems.where((a) => a.canRsvp).isEmpty)
              const Text(
                'Geen agenda-items met aanmeldingen.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else
              ..._agendaItems.where((a) => a.canRsvp).map((a) {
                final id = a.id ?? -1;
                final signups = _rsvpsByAgendaId[id] ?? const [];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title,
                          style: const TextStyle(
                            color: AppColors.onBackground,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [a.when, a.where].where((s) => s.trim().isNotEmpty).join(' • '),
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 10),
                        if (signups.isEmpty)
                          const Text(
                            'Nog geen aanmeldingen.',
                            style: TextStyle(color: AppColors.textSecondary),
                          )
                        else
                          ...signups.map((s) {
                            final teams = s.teamLabels.isEmpty ? '—' : s.teamLabels.join(', ');
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.person_outline, size: 18, color: AppColors.iconMuted),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.name,
                                          style: const TextStyle(
                                            color: AppColors.onBackground,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Team: $teams',
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }

  Future<void> _loadNews() async {
    setState(() {
      _loadingNews = true;
      _newsError = null;
    });

    try {
      // Be defensive about schema differences (id/title/body columns).
      List<Map<String, dynamic>> rows = const [];
      String idField = 'news_id';
      for (final attempt in const [
        // Preferred: supports optional `visible_until`.
        ('news_id, title, description, created_at, author, category, source, visible_until', 'news_id'),
        ('id, title, description, created_at, author, category, source, visible_until', 'id'),
        ('news_id, title, body, created_at, author, category, source, visible_until', 'news_id'),
        ('id, title, body, created_at, author, category, source, visible_until', 'id'),
        ('news_id, title, description, created_at, visible_until', 'news_id'),
        ('id, title, description, created_at, visible_until', 'id'),
        ('news_id, title, body, created_at, visible_until', 'news_id'),
        ('id, title, body, created_at, visible_until', 'id'),
        ('news_id, title, description, created_at, author, category, source', 'news_id'),
        ('id, title, description, created_at, author, category, source', 'id'),
        // Older schemas may use "body" instead of "description"
        ('news_id, title, body, created_at, author, category, source', 'news_id'),
        ('id, title, body, created_at, author, category, source', 'id'),
        // Minimal schema
        ('news_id, title, description, created_at', 'news_id'),
        ('id, title, description, created_at', 'id'),
        ('news_id, title, body, created_at', 'news_id'),
        ('id, title, body, created_at', 'id'),
      ]) {
        try {
          final select = attempt.$1;
          final candidateId = attempt.$2;
          final res = await _client
              .from('home_news')
              .select(select)
              .order('created_at', ascending: false);
          rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
          idField = candidateId;
          break;
        } catch (_) {
          // try next
        }
      }

      final list = <NewsItem>[];
      for (final r in rows) {
        final rawId = r[idField];
        final idStr = (rawId is num)
            ? (rawId.toInt()).toString()
            : (rawId?.toString() ?? '').trim();
        if (idStr.isEmpty) continue;
        final title = (r['title'] as String?) ?? '';
        final body = (r['description'] ?? r['body'] ?? '').toString();
        DateTime? date;
        final raw = r['created_at'];
        if (raw is DateTime) {
          date = raw;
        } else if (raw != null) {
          date = DateTime.tryParse(raw.toString());
        }
        date ??= DateTime.now();
        final author = (r['author'] ?? '').toString().trim();
        final category = _categoryFromDb(r['category']);
        final visibleUntil = _parseVisibleUntil(r['visible_until']);
        if (!_isVisibleNow(visibleUntil)) continue;
        list.add(NewsItem(
          id: idStr,
          title: title,
          body: body,
          date: date,
          author: author.isNotEmpty ? author : 'Bestuur',
          category: category,
          visibleUntil: visibleUntil,
        ));
      }

      setState(() {
        _newsIdField = idField;
        // If the DB table exists but has no rows yet, show an empty state (not mock data),
        // otherwise admins end up with "fake" items that can't be edited/deleted.
        _newsItems = list;
        _newsFromSupabase = true;
        _loadingNews = false;
      });
    } catch (e) {
      setState(() {
        _newsItems = mockNews;
        _newsFromSupabase = false;
        _newsError = e.toString();
        _loadingNews = false;
      });
    }
  }

  String _formatDateTimeShort(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year} • ${two(d.hour)}:${two(d.minute)}';
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

  Future<void> _toggleAgendaRsvp(_AgendaItem item) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      showTopMessage(context, 'Log in om je aan te melden.', isError: true);
      return;
    }
    if (item.id == null) return;

    final isSignedUp = _myRsvpAgendaIds.contains(item.id);
    try {
      if (isSignedUp) {
        await _client
            .from('home_agenda_rsvps')
            .delete()
            .eq('agenda_id', item.id!)
            .eq('profile_id', user.id);
      } else {
        await _client.from('home_agenda_rsvps').insert({
          'agenda_id': item.id,
          'profile_id': user.id,
        });
      }

      setState(() {
        final next = {..._myRsvpAgendaIds};
        if (isSignedUp) {
          next.remove(item.id);
        } else {
          next.add(item.id!);
        }
        _myRsvpAgendaIds = next;
      });
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Aanmelding mislukt: $e', isError: true);
    }
  }

  void _showAgendaDetail(_AgendaItem item) {
    final hasAny = item.description != null ||
        item.dateLabel != null ||
        item.endDateLabel != null ||
        item.timeLabel != null ||
        item.endTimeLabel != null ||
        item.where.isNotEmpty;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.description != null && item.description!.isNotEmpty) ...[
                Text(
                  item.description!,
                  style: const TextStyle(color: AppColors.onBackground, height: 1.4),
                ),
                const SizedBox(height: 16),
              ],
              if (item.dateLabel != null) ...[
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      item.endDateLabel != null && item.endDateLabel != item.dateLabel
                          ? '${item.dateLabel!} t/m ${item.endDateLabel!}'
                          : item.dateLabel!,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (item.timeLabel != null) ...[
                Row(
                  children: [
                    Icon(Icons.schedule, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      item.endTimeLabel != null && item.endTimeLabel != item.timeLabel
                          ? '${item.timeLabel!} – ${item.endTimeLabel!}'
                          : item.timeLabel!,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (item.where.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.place, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.where,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              if (!hasAny)
                const Text('Geen extra informatie.', style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Sluiten'),
          ),
        ],
      ),
    );
  }

  void _showNewsDetail(NewsItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.title),
        content: SingleChildScrollView(
          child: Text(
            item.body,
            style: const TextStyle(color: AppColors.onBackground, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Sluiten'),
          ),
        ],
      ),
    );
  }

  void _showHighlightDetail(_Highlight item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.subtitle,
                style: const TextStyle(color: AppColors.onBackground, height: 1.4),
              ),
              if (item.visibleUntil != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Tonen t/m ${_formatDateShort(item.visibleUntil!)}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Sluiten'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddNewsDialog() async {
    final authorName = (() {
      try {
        final ctx = AppUserContext.of(context);
        final n = ctx.displayName.trim();
        return n.isNotEmpty ? n : 'Bestuur';
      } catch (_) {
        return 'Bestuur';
      }
    })();

    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime? visibleUntil;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          scrollable: true,
          title: const Text('Nieuwsbericht toevoegen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Titel *',
                  hintText: 'bijv. Update vanuit het bestuur',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Beschrijving',
                  hintText: 'Volledige tekst van het bericht',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tonen tot',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final next = await _pickVisibleUntilDate(visibleUntil);
                      setLocalState(() => visibleUntil = next);
                    },
                    child: Text(
                      visibleUntil == null ? 'Geen' : _formatDate(visibleUntil!),
                    ),
                  ),
                  if (visibleUntil != null)
                    IconButton(
                      tooltip: 'Wissen',
                      onPressed: () => setLocalState(() => visibleUntil = null),
                      icon: const Icon(Icons.close, size: 18),
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuleren'),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.trim().isEmpty) return;
                Navigator.of(context).pop(true);
              },
              child: const Text('Opslaan'),
            ),
          ],
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleController.dispose();
      descriptionController.dispose();
    });

    if (ok != true) return;

    final title = titleController.text.trim();
    if (title.isEmpty) return;

    try {
      final payload = {
        'title': title,
        'description': descriptionController.text.trim(),
        'author': authorName,
        'category': 'bestuur',
        'visible_until': visibleUntil?.toUtc().toIso8601String(),
      };
      // Some DB schemas require non-null `source` / `author` / `category` columns.
      try {
        await _client.from('home_news').insert({...payload, 'source': 'app'});
      } on PostgrestException catch (e) {
        // Missing column -> retry without optional `visible_until`, then fallback minimal.
        if (e.code == 'PGRST204' ||
            (e.message.contains("Could not find the '") &&
                e.message.contains("column"))) {
          try {
            final retry = {...payload, 'source': 'app'}..remove('visible_until');
            await _client.from('home_news').insert(retry);
          } on PostgrestException catch (e2) {
            if (e2.code == 'PGRST204' ||
                (e2.message.contains("Could not find the '") &&
                    e2.message.contains("column"))) {
              await _client.from('home_news').insert({
                'title': title,
                'description': descriptionController.text.trim(),
              });
            } else {
              rethrow;
            }
          }
        } else {
          rethrow;
        }
      }
      await _loadNews();
      if (!mounted) return;
      showTopMessage(context, 'Nieuwsbericht toegevoegd.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Opslaan mislukt: $e', isError: true);
    }
  }

  Future<void> _openEditNewsDialog(NewsItem existing) async {
    final authorName = (() {
      try {
        final ctx = AppUserContext.of(context);
        final n = ctx.displayName.trim();
        return n.isNotEmpty ? n : existing.author;
      } catch (_) {
        return existing.author;
      }
    })();

    final idValue = int.tryParse(existing.id) ?? existing.id;
    if (existing.id.trim().isEmpty) return;

    final titleController = TextEditingController(text: existing.title);
    final descriptionController = TextEditingController(text: existing.body);
    DateTime? visibleUntil = existing.visibleUntil;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          scrollable: true,
          title: const Text('Nieuwsbericht aanpassen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Titel *',
                  hintText: 'bijv. Update vanuit het bestuur',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Beschrijving',
                  hintText: 'Volledige tekst van het bericht',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tonen tot',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final next = await _pickVisibleUntilDate(visibleUntil);
                      setLocalState(() => visibleUntil = next);
                    },
                    child: Text(
                      visibleUntil == null ? 'Geen' : _formatDate(visibleUntil!),
                    ),
                  ),
                  if (visibleUntil != null)
                    IconButton(
                      tooltip: 'Wissen',
                      onPressed: () => setLocalState(() => visibleUntil = null),
                      icon: const Icon(Icons.close, size: 18),
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuleren'),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.trim().isEmpty) return;
                Navigator.of(context).pop(true);
              },
              child: const Text('Opslaan'),
            ),
          ],
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleController.dispose();
      descriptionController.dispose();
    });

    if (ok != true) return;

    final title = titleController.text.trim();
    if (title.isEmpty) return;

    try {
      final payload = {
        'title': title,
        'description': descriptionController.text.trim(),
        'author': authorName,
        'category': existing.category.label.toLowerCase(),
        'visible_until': visibleUntil?.toUtc().toIso8601String(),
      };
      // Some DB schemas require non-null `source` / `author` / `category` columns.
      try {
        await _client
            .from('home_news')
            .update({...payload, 'source': 'app'})
            .eq(_newsIdField, idValue);
      } on PostgrestException catch (e) {
        // Missing column -> retry without optional `visible_until`, then fallback minimal.
        if (e.code == 'PGRST204' ||
            (e.message.contains("Could not find the '") &&
                e.message.contains("column"))) {
          try {
            final retry = {...payload, 'source': 'app'}..remove('visible_until');
            await _client.from('home_news').update(retry).eq(_newsIdField, idValue);
          } on PostgrestException catch (e2) {
            if (e2.code == 'PGRST204' ||
                (e2.message.contains("Could not find the '") &&
                    e2.message.contains("column"))) {
              await _client.from('home_news').update({
                'title': title,
                'description': descriptionController.text.trim(),
              }).eq(_newsIdField, idValue);
            } else {
              rethrow;
            }
          }
        } else {
          rethrow;
        }
      }
      await _loadNews();
      if (!mounted) return;
      showTopMessage(context, 'Nieuwsbericht aangepast.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Opslaan mislukt: $e', isError: true);
    }
  }

  Future<void> _deleteNewsItem(NewsItem item) async {
    final idValue = int.tryParse(item.id) ?? item.id;
    if (item.id.trim().isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nieuwsbericht verwijderen'),
        content: Text(
          'Weet je zeker dat je "${item.title}" wilt verwijderen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _client.from('home_news').delete().eq(_newsIdField, idValue);
      await _loadNews();
      if (!mounted) return;
      showTopMessage(context, 'Nieuwsbericht verwijderd.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Verwijderen mislukt: $e', isError: true);
    }
  }

  Future<void> _openAddAgendaDialog() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final locationController = TextEditingController();
    DateTime? pickedDateTime;
    DateTime? pickedEndDateTime;
    bool canRsvp = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            String two(int v) => v.toString().padLeft(2, '0');
            String dateStr(DateTime? dt) => dt == null
                ? 'Niet gekozen'
                : '${two(dt.day)}-${two(dt.month)}-${dt.year}';
            String timeStr(DateTime? dt) => dt == null
                ? 'Niet gekozen'
                : '${two(dt.hour)}:${two(dt.minute)}';

            return AlertDialog(
              scrollable: true,
              title: const Text('Activiteit toevoegen'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Titel *',
                      hintText: 'bijv. Algemene ledenvergadering',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Beschrijving',
                      hintText: 'Alleen zichtbaar bij Lees meer',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Begindatum', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(dateStr(pickedDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            locale: const Locale('nl', 'NL'),
                            initialDate: pickedDateTime ?? now,
                            firstDate: now.subtract(const Duration(days: 365)),
                            lastDate: now.add(const Duration(days: 365 * 2)),
                          );
                          if (d == null) return;
                          setState(() {
                            pickedDateTime = DateTime(
                              d.year, d.month, d.day,
                              pickedDateTime?.hour ?? 0, pickedDateTime?.minute ?? 0,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Begintijd', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(timeStr(pickedDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: pickedDateTime != null
                                ? TimeOfDay(hour: pickedDateTime!.hour, minute: pickedDateTime!.minute)
                                : const TimeOfDay(hour: 20, minute: 0),
                          );
                          if (t == null) return;
                          setState(() {
                            pickedDateTime = DateTime(
                              pickedDateTime?.year ?? DateTime.now().year,
                              pickedDateTime?.month ?? DateTime.now().month,
                              pickedDateTime?.day ?? DateTime.now().day,
                              t.hour, t.minute,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Einddatum', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(dateStr(pickedEndDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final startOrNow = pickedDateTime ?? now;
                          final d = await showDatePicker(
                            context: context,
                            locale: const Locale('nl', 'NL'),
                            initialDate: pickedEndDateTime ?? pickedDateTime ?? now,
                            firstDate: startOrNow,
                            lastDate: now.add(const Duration(days: 365 * 2)),
                          );
                          if (d == null) return;
                          setState(() {
                            pickedEndDateTime = DateTime(
                              d.year, d.month, d.day,
                              pickedEndDateTime?.hour ?? 23, pickedEndDateTime?.minute ?? 59,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Eindtijd', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(timeStr(pickedEndDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: pickedEndDateTime != null
                                ? TimeOfDay(hour: pickedEndDateTime!.hour, minute: pickedEndDateTime!.minute)
                                : const TimeOfDay(hour: 22, minute: 0),
                          );
                          if (t == null) return;
                          setState(() {
                            pickedEndDateTime = DateTime(
                              pickedEndDateTime?.year ?? DateTime.now().year,
                              pickedEndDateTime?.month ?? DateTime.now().month,
                              pickedEndDateTime?.day ?? DateTime.now().day,
                              t.hour, t.minute,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Locatie',
                      hintText: 'bijv. Kantine',
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: canRsvp,
                    onChanged: (v) => setState(() => canRsvp = v ?? false),
                    title: const Text('Aanmelden mogelijk'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuleren'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (titleController.text.trim().isEmpty) return;
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Opslaan'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleController.dispose();
      descriptionController.dispose();
      locationController.dispose();
    });

    if (ok != true) return;

    final title = titleController.text.trim();
    if (title.isEmpty) return;

    try {
      final payload = <String, dynamic>{
        'title': title,
        'description': descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
        'location': locationController.text.trim().isEmpty ? null : locationController.text.trim(),
        'can_rsvp': canRsvp,
      };
      if (pickedDateTime != null) {
        payload['start_datetime'] = pickedDateTime!.toUtc().toIso8601String();
      }
      if (pickedEndDateTime != null) {
        payload['end_datetime'] = pickedEndDateTime!.toUtc().toIso8601String();
      }
      await _client.from('home_agenda').insert(payload);
      await _loadAgenda();
      if (!mounted) return;
      showTopMessage(context, 'Activiteit toegevoegd.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Opslaan mislukt: $e', isError: true);
    }
  }

  Future<void> _openEditAgendaDialog(_AgendaItem existing) async {
    if (existing.id == null) return;

    final titleController = TextEditingController(text: existing.title);
    final descriptionController = TextEditingController(text: existing.description ?? '');
    final locationController = TextEditingController(text: existing.where);
    DateTime? pickedDateTime = existing.startDatetime?.toLocal();
    DateTime? pickedEndDateTime = existing.endDatetime?.toLocal();
    bool canRsvp = existing.canRsvp;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            String two(int v) => v.toString().padLeft(2, '0');
            String dateStr(DateTime? dt) => dt == null
                ? 'Niet gekozen'
                : '${two(dt.day)}-${two(dt.month)}-${dt.year}';
            String timeStr(DateTime? dt) => dt == null
                ? 'Niet gekozen'
                : '${two(dt.hour)}:${two(dt.minute)}';

            return AlertDialog(
              scrollable: true,
              title: const Text('Activiteit aanpassen'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Titel *',
                      hintText: 'bijv. Algemene ledenvergadering',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Beschrijving',
                      hintText: 'Alleen zichtbaar bij Lees meer',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Begindatum', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(dateStr(pickedDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            locale: const Locale('nl', 'NL'),
                            initialDate: pickedDateTime ?? now,
                            firstDate: now.subtract(const Duration(days: 365)),
                            lastDate: now.add(const Duration(days: 365 * 2)),
                          );
                          if (d == null) return;
                          setState(() {
                            pickedDateTime = DateTime(
                              d.year, d.month, d.day,
                              pickedDateTime?.hour ?? 0, pickedDateTime?.minute ?? 0,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Begintijd', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(timeStr(pickedDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: pickedDateTime != null
                                ? TimeOfDay(hour: pickedDateTime!.hour, minute: pickedDateTime!.minute)
                                : const TimeOfDay(hour: 20, minute: 0),
                          );
                          if (t == null) return;
                          setState(() {
                            pickedDateTime = DateTime(
                              pickedDateTime?.year ?? DateTime.now().year,
                              pickedDateTime?.month ?? DateTime.now().month,
                              pickedDateTime?.day ?? DateTime.now().day,
                              t.hour, t.minute,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Einddatum', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(dateStr(pickedEndDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            locale: const Locale('nl', 'NL'),
                            initialDate: pickedEndDateTime ?? pickedDateTime ?? now,
                            firstDate: now.subtract(const Duration(days: 365)),
                            lastDate: now.add(const Duration(days: 365 * 2)),
                          );
                          if (d == null) return;
                          setState(() {
                            pickedEndDateTime = DateTime(
                              d.year, d.month, d.day,
                              pickedEndDateTime?.hour ?? 23, pickedEndDateTime?.minute ?? 59,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Eindtijd', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(timeStr(pickedEndDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: pickedEndDateTime != null
                                ? TimeOfDay(hour: pickedEndDateTime!.hour, minute: pickedEndDateTime!.minute)
                                : const TimeOfDay(hour: 22, minute: 0),
                          );
                          if (t == null) return;
                          setState(() {
                            pickedEndDateTime = DateTime(
                              pickedEndDateTime?.year ?? DateTime.now().year,
                              pickedEndDateTime?.month ?? DateTime.now().month,
                              pickedEndDateTime?.day ?? DateTime.now().day,
                              t.hour, t.minute,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Locatie',
                      hintText: 'bijv. Kantine',
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: canRsvp,
                    onChanged: (v) => setState(() => canRsvp = v ?? false),
                    title: const Text('Aanmelden mogelijk'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuleren'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (titleController.text.trim().isEmpty) return;
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Opslaan'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleController.dispose();
      descriptionController.dispose();
      locationController.dispose();
    });

    if (ok != true) return;

    final title = titleController.text.trim();
    if (title.isEmpty) return;

    try {
      final payload = <String, dynamic>{
        'title': title,
        'description': descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
        'location': locationController.text.trim().isEmpty ? null : locationController.text.trim(),
        'can_rsvp': canRsvp,
      };
      if (pickedDateTime != null) {
        payload['start_datetime'] = pickedDateTime!.toUtc().toIso8601String();
      }
      if (pickedEndDateTime != null) {
        payload['end_datetime'] = pickedEndDateTime!.toUtc().toIso8601String();
      } else {
        payload['end_datetime'] = null;
      }
      await _client.from('home_agenda').update(payload).eq('agenda_id', existing.id!);
      await _loadAgenda();
      if (!mounted) return;
      showTopMessage(context, 'Activiteit aangepast.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Opslaan mislukt: $e', isError: true);
    }
  }

  Future<void> _deleteAgendaItem(_AgendaItem item) async {
    if (item.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activiteit verwijderen'),
        content: Text(
          'Weet je zeker dat je "${item.title}" wilt verwijderen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _client.from('home_agenda').delete().eq('agenda_id', item.id!);
      await _loadAgenda();
      if (!mounted) return;
      showTopMessage(context, 'Activiteit verwijderd.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Verwijderen mislukt: $e', isError: true);
    }
  }

  Future<void> _upsertHighlight({
    int? id,
    required String title,
    required String subtitle,
    required String iconText,
    required DateTime? visibleUntil,
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      'subtitle': subtitle,
      'icon_name': iconText,
      'visible_until': visibleUntil?.toUtc().toIso8601String(),
    };
    if (id == null) {
      try {
        await _client.from('home_highlights').insert(payload);
      } on PostgrestException catch (e) {
        // Missing column -> retry without optional visible_until
        if (e.code == 'PGRST204' ||
            (e.message.contains("Could not find the '") &&
                e.message.contains("column"))) {
          payload.remove('visible_until');
          await _client.from('home_highlights').insert(payload);
        } else {
          rethrow;
        }
      }
    } else {
      try {
        await _client
            .from('home_highlights')
            .update(payload)
            .eq('highlight_id', id);
      } on PostgrestException catch (e) {
        if (e.code == 'PGRST204' ||
            (e.message.contains("Could not find the '") &&
                e.message.contains("column"))) {
          payload.remove('visible_until');
          await _client
              .from('home_highlights')
              .update(payload)
              .eq('highlight_id', id);
        } else {
          rethrow;
        }
      }
    }
  }

  Future<void> _deleteHighlight(int id) async {
    await _client.from('home_highlights').delete().eq('highlight_id', id);
  }

  Future<void> _confirmDeleteHighlight(_Highlight item) async {
    if (item.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Punt verwijderen'),
        content: Text('Weet je zeker dat je "${item.title}" wilt verwijderen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _deleteHighlight(item.id!);
      await _loadHighlights();
      if (!mounted) return;
      showTopMessage(context, 'Punt verwijderd.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Verwijderen mislukt: $e', isError: true);
    }
  }

  Future<void> _openEditHighlightDialog({
    required bool canManage,
    _Highlight? existing,
  }) async {
    if (!canManage) return;

    final titleController = TextEditingController(text: existing?.title ?? '');
    final subtitleController =
        TextEditingController(text: existing?.subtitle ?? '');
    DateTime? visibleUntil = existing?.visibleUntil;

    final result = await showDialog<_HighlightEditResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          scrollable: true,
          title: Text(existing == null ? 'Punt toevoegen' : 'Punt aanpassen'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: titleController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Titel',
                    hintText: 'Bijv. De Minerva app',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subtitleController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Tekst',
                    hintText: 'Korte omschrijving',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Tonen tot',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final next = await _pickVisibleUntilDate(visibleUntil);
                        setLocalState(() => visibleUntil = next);
                      },
                      child: Text(
                        visibleUntil == null ? 'Geen' : _formatDate(visibleUntil!),
                      ),
                    ),
                    if (visibleUntil != null)
                      IconButton(
                        tooltip: 'Wissen',
                        onPressed: () => setLocalState(() => visibleUntil = null),
                        icon: const Icon(Icons.close, size: 18),
                        color: AppColors.textSecondary,
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Annuleren'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(
                _HighlightEditResult.save(
                  titleController.text.trim(),
                  subtitleController.text.trim(),
                  // Icon/emoji field removed; keep existing icon or use default.
                  existing?.iconText ?? '🏐',
                  visibleUntil,
                ),
              ),
              child: const Text('Opslaan'),
            ),
          ],
        ),
      ),
    );

    // Disposal uitstellen tot na sluiting dialoog; anders "used after being disposed".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleController.dispose();
      subtitleController.dispose();
    });

    if (result == null) return;

    try {
      if (result.isSave) {
        final title = result.title ?? '';
        if (title.isEmpty) return;
        await _upsertHighlight(
          id: existing?.id,
          title: title,
          subtitle: result.subtitle ?? '',
          iconText:
              (result.iconText?.isNotEmpty == true) ? result.iconText! : '🏐',
          visibleUntil: result.visibleUntil,
        );
      }
      await _loadHighlights();
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Opslaan mislukt: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userContext = AppUserContext.of(context);
    final canManageHighlights = userContext.canManageHighlights;
    final canManageAgenda = userContext.canManageAgenda;
    final canManageNews = userContext.canManageNews;
    final canViewAgendaRsvps = userContext.canViewAgendaRsvps;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.darkBlue,
                  borderRadius: BorderRadius.circular(AppColors.cardRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welkom bij VV Minerva',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Updates, agenda en nieuws vanuit de vereniging.',
                      style: TextStyle(
                        color: AppColors.primary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                showBorder: false,
                showShadow: false,
                child: TabBar(
                  controller: _tabController,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: AppColors.darkBlue,
                    borderRadius: BorderRadius.circular(AppColors.cardRadius),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: const [
                    Tab(text: 'Uitgelicht'),
                    Tab(text: 'Agenda'),
                    Tab(text: 'Nieuws'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Uitgelicht
                  RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _refreshHome,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      children: [
                        _HomeTabHeader(
                          title: 'Uitgelicht',
                          trailing: canManageHighlights
                              ? IconButton(
                                  tooltip: 'Punt toevoegen',
                                  icon: const Icon(Icons.add_circle_outline),
                                  color: AppColors.primary,
                                  onPressed: () => _openEditHighlightDialog(
                                    canManage: true,
                                    existing: null,
                                  ),
                                )
                              : (_loadingHighlights
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary,
                                      ),
                                    )
                                  : null),
                        ),
                        const SizedBox(height: 12),
                        if (_highlightsError != null && canManageHighlights)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Let op: highlights tabel niet beschikbaar.\n'
                              'Voer supabase/home_highlights_minimal.sql uit in Supabase → SQL Editor.\n'
                              'Details: $_highlightsError',
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        const Text(
                          'Korte, belangrijke mededelingen en acties.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        if (_highlights.isEmpty)
                          const Text(
                            'Geen uitgelichte items.',
                            style: TextStyle(color: AppColors.textSecondary),
                          )
                        else
                          ..._highlights.map((h) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _HighlightCard(
                                item: h,
                                canManage: canManageHighlights,
                                onMore: () => _showHighlightDetail(h),
                                onEdit: () => _openEditHighlightDialog(
                                  canManage: canManageHighlights,
                                  existing: h,
                                ),
                                onDelete: h.id != null
                                    ? () => _confirmDeleteHighlight(h)
                                    : null,
                              ),
                            );
                          }),
                      ],
                    ),
                  ),

                  // Agenda
                  Column(
                    children: [
                      if (canViewAgendaRsvps)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: SegmentedButton<int>(
                              segments: const [
                                ButtonSegment(value: 0, label: Text('Agenda')),
                                ButtonSegment(value: 1, label: Text('Aanmeldingen')),
                              ],
                              selected: {_agendaMode},
                              onSelectionChanged: (set) {
                                final next = set.first;
                                setState(() => _agendaMode = next);
                                if (next == 1) {
                                  // ignore: unawaited_futures
                                  _loadAgendaRsvps();
                                }
                              },
                            ),
                          ),
                        ),
                      Expanded(
                        child: _agendaMode == 1 && canViewAgendaRsvps
                            ? _buildAgendaRsvpsView()
                            : _buildAgendaListView(canManageAgenda: canManageAgenda),
                      ),
                    ],
                  ),

                  // Nieuws
                  RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _refreshHome,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      itemCount: 1 + (_newsItems.isEmpty ? 1 : _newsItems.length),
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _HomeTabHeader(
                                title: 'Nieuws',
                                trailing: canManageNews
                                    ? IconButton(
                                        tooltip: 'Nieuwsbericht toevoegen',
                                        icon: const Icon(Icons.add_circle_outline),
                                        color: AppColors.primary,
                                        onPressed: () => _openAddNewsDialog(),
                                      )
                                    : (_loadingNews
                                        ? const SizedBox(
                                            height: 18,
                                            width: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.primary,
                                            ),
                                          )
                                        : null),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Berichten met wat meer context. '
                                'Tip: stel optioneel “Tonen tot” in zodat een bericht automatisch verdwijnt.',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            ],
                          );
                        }

                        if (_newsItems.isEmpty) {
                          if (_newsError != null && canManageNews) {
                            return Text(
                              'Let op: nieuwstabel niet beschikbaar. '
                              'Voer supabase/home_news_minimal.sql uit in Supabase → SQL Editor.\n'
                              'Details: $_newsError',
                              style: const TextStyle(color: AppColors.textSecondary),
                            );
                          }
                          return const Text(
                            'Geen nieuwsberichten gevonden.',
                            style: TextStyle(color: AppColors.textSecondary),
                          );
                        }

                        final n = _newsItems[i - 1];
                        return _NewsCard(
                          item: n,
                          canManage: canManageNews,
                          onReadMore: () => _showNewsDetail(n),
                          onEdit: _newsFromSupabase ? () => _openEditNewsDialog(n) : null,
                          onDelete: _newsFromSupabase ? () => _deleteNewsItem(n) : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ----------------------- SECTIE-TITEL ----------------------- */

class _HomeTabHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _HomeTabHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkBlue,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/* ----------------------- KAART-WRAPPER ----------------------- */

class _CardBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const _CardBox({
    required this.child,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(14),
      child: child,
    );
  }
}

String _formatDateShort(DateTime dt) {
  final d = dt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}-${two(d.month)}-${d.year}';
}

/* ----------------------- HIGHLIGHTS ----------------------- */

class _Highlight {
  final int? id;
  final String title;
  final String subtitle;
  final String iconText;
  final DateTime? visibleUntil;

  const _Highlight({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconText,
    required this.visibleUntil,
  });
}

class _HighlightCard extends StatelessWidget {
  final _Highlight item;
  final bool canManage;
  final VoidCallback? onMore;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _HighlightCard({
    required this.item,
    required this.canManage,
    this.onMore,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final showMenu = canManage && (onEdit != null || onDelete != null);
    return _CardBox(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.iconText, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.onBackground,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                if (item.visibleUntil != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Tonen t/m ${_formatDateShort(item.visibleUntil!)}',
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.9),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (onMore != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onMore,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Meer…'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showMenu)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 1),
              tooltip: 'Meer opties',
              onSelected: (v) {
                if (v == 'edit') onEdit?.call();
                if (v == 'delete') onDelete?.call();
              },
              itemBuilder: (context) => [
                if (onEdit != null)
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20, color: AppColors.textSecondary),
                        SizedBox(width: 8),
                        Text('Bewerken'),
                      ],
                    ),
                  ),
                if (onDelete != null)
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                        SizedBox(width: 8),
                        Text('Verwijderen', style: TextStyle(color: AppColors.error)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HighlightEditResult {
  final bool isSave;
  final String? title;
  final String? subtitle;
  final String? iconText;
  final DateTime? visibleUntil;

  const _HighlightEditResult._({
    required this.isSave,
    this.title,
    this.subtitle,
    this.iconText,
    this.visibleUntil,
  });

  const _HighlightEditResult.save(
    String title,
    String subtitle,
    String iconText,
    DateTime? visibleUntil,
  ) : this._(
          isSave: true,
          title: title,
          subtitle: subtitle,
          iconText: iconText,
          visibleUntil: visibleUntil,
        );
}

List<_Highlight> _mockHighlights() => const [
      _Highlight(
        id: null,
        iconText: '📌',
        title: 'Seizoensstart',
        subtitle: 'Belangrijke clubafspraken en planning',
        visibleUntil: null,
      ),
      _Highlight(
        id: null,
        iconText: '🏆',
        title: 'Toernooi',
        subtitle: 'Inschrijving geopend (jeugd & senioren)',
        visibleUntil: null,
      ),
      _Highlight(
        id: null,
        iconText: '🤝',
        title: 'Vrijwilligers gezocht',
        subtitle: 'Tafelaars en scheidsrechters nodig',
        visibleUntil: null,
      ),
    ];

/* ----------------------- AGENDA ----------------------- */

class _AgendaItem {
  final int? id;
  final String title;
  final String? description;
  final String when;
  final String where;
  final bool canRsvp;
  final DateTime? startDatetime;
  final DateTime? endDatetime;
  final String? dateLabel;
  final String? timeLabel;
  final String? endDateLabel;
  final String? endTimeLabel;

  const _AgendaItem({
    required this.id,
    required this.title,
    this.description,
    required this.when,
    required this.where,
    required this.canRsvp,
    this.startDatetime,
    this.endDatetime,
    this.dateLabel,
    this.timeLabel,
    this.endDateLabel,
    this.endTimeLabel,
  });
}

class _AgendaSignup {
  final int agendaId;
  final String profileId;
  final String name;
  final List<String> teamLabels;
  final DateTime? createdAt;

  const _AgendaSignup({
    required this.agendaId,
    required this.profileId,
    required this.name,
    required this.teamLabels,
    required this.createdAt,
  });
}

class _AgendaCard extends StatelessWidget {
  final _AgendaItem item;
  final bool signedUp;
  final bool enabled;
  final bool canManage;
  final VoidCallback onToggleRsvp;
  final VoidCallback onReadMore;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _AgendaCard({
    required this.item,
    required this.signedUp,
    required this.enabled,
    required this.canManage,
    required this.onToggleRsvp,
    required this.onReadMore,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Einddatum/eindtijd alleen tonen als expliciet ingesteld én anders dan begin.
    // Geen einddatum → niet weergeven;zelfde dag → alleen begindatum, geen "t/m".
    final dateLine = item.dateLabel != null
        ? (item.endDateLabel != null && item.endDateLabel != item.dateLabel
            ? '${item.dateLabel!} t/m ${item.endDateLabel!}'
            : item.dateLabel!)
        : null;
    final timeRange = item.timeLabel != null
        ? (item.endTimeLabel != null && item.endTimeLabel != item.timeLabel
            ? '${item.timeLabel!} – ${item.endTimeLabel!}'
            : item.timeLabel!)
        : null;
    final timeLocation = timeRange != null
        ? [timeRange, item.where].where((s) => s.isNotEmpty).join(' • ')
        : [item.when, item.where].where((s) => s.isNotEmpty).join(' • ');
    final showMenu = canManage && (onEdit != null || onDelete != null);
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        );

    return _CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.onBackground,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (dateLine != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(dateLine, style: secondaryStyle),
                        ],
                      ),
                    ],
                    if (timeLocation.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(timeLocation, style: secondaryStyle),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (showMenu)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 1),
                  tooltip: 'Meer opties',
                  onSelected: (v) {
                    if (v == 'edit') onEdit?.call();
                    if (v == 'delete') onDelete?.call();
                  },
                  itemBuilder: (context) => [
                    if (onEdit != null)
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20, color: AppColors.textSecondary),
                            SizedBox(width: 8),
                            Text('Bewerken'),
                          ],
                        ),
                      ),
                    if (onDelete != null)
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                            SizedBox(width: 8),
                            Text('Verwijderen', style: TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (item.canRsvp) ...[
                SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: enabled ? onToggleRsvp : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(signedUp ? 'Afmelden' : 'Aanmelden'),
                  ),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed: onReadMore,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Meer…'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

List<_AgendaItem> _mockAgenda() => const [
      _AgendaItem(
        id: null,
        title: 'Algemene ledenvergadering',
        description: 'Jaarlijkse ALV met stemming over het jaarverslag.',
        when: 'Ma 15 jan • 20:00',
        where: 'Kantine',
        canRsvp: false,
        startDatetime: null,
        endDatetime: null,
        dateLabel: '15-01-2025',
        timeLabel: '20:00',
        endDateLabel: null,
        endTimeLabel: null,
      ),
      _AgendaItem(
        id: null,
        title: 'Clubdag',
        description: 'Sportieve dag voor jeugd en senioren.',
        when: 'Za 10 feb • 10:00',
        where: 'Sporthal',
        canRsvp: true,
        startDatetime: null,
        endDatetime: null,
        dateLabel: '10-02-2025',
        timeLabel: '10:00',
        endDateLabel: null,
        endTimeLabel: null,
      ),
    ];

/* ----------------------- NIEUWS ----------------------- */

String _newsDateLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(d.year, d.month, d.day);
  final diff = today.difference(date).inDays;
  if (diff == 0) return 'Vandaag';
  if (diff == 1) return 'Gisteren';
  if (diff < 7) return '$diff dagen geleden';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}-${two(d.month)}-${d.year}';
}

class _NewsCard extends StatelessWidget {
  final NewsItem item;
  final bool canManage;
  final VoidCallback? onReadMore;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _NewsCard({
    required this.item,
    required this.canManage,
    this.onReadMore,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final showMenu = canManage;
    final canEdit = onEdit != null;
    final canDelete = onDelete != null;

    return _CardBox(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(item.category.label),
              _Pill(item.author),
              Text(
                _newsDateLabel(item.date),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (item.visibleUntil != null)
                Text(
                  'Tonen t/m ${_formatDateShort(item.visibleUntil!)}',
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.onBackground,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (showMenu)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 1),
                  tooltip: 'Meer opties',
                  onSelected: (v) {
                    if (v == 'edit') onEdit?.call();
                    if (v == 'delete') onDelete?.call();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'edit',
                      enabled: canEdit,
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20, color: canEdit ? AppColors.textSecondary : AppColors.textSecondary.withValues(alpha: 0.5)),
                          const SizedBox(width: 8),
                          Text('Bewerken'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      enabled: canDelete,
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 20, color: canDelete ? AppColors.error : AppColors.error.withValues(alpha: 0.5)),
                          const SizedBox(width: 8),
                          Text('Verwijderen', style: TextStyle(color: canDelete ? AppColors.error : AppColors.error.withValues(alpha: 0.5))),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.body,
            maxLines: onReadMore != null ? 3 : null,
            overflow: onReadMore != null ? TextOverflow.ellipsis : null,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (onReadMore != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onReadMore,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Meer…'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;

  const _Pill(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.45),
          width: 1.4,
        ),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.onBackground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
