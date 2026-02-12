import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_api.dart';

class NevoboStandenTab extends StatefulWidget {
  const NevoboStandenTab({super.key});

  @override
  State<NevoboStandenTab> createState() => _NevoboStandenTabState();
}

class _NevoboStandenTabState extends State<NevoboStandenTab> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<NevoboTeam> _teams = const [];
  List<String> _otherTeamNames = const [];
  final Map<String, List<NevoboStandingEntry>> _standingsByTeam = {};
  final Map<String, String> _errorByTeam = {};

  // Per team view: 0 = standen, 1 = programma, 2 = uitslagen
  final Map<String, int> _modeByTeamCode = {};

  // Matches are loaded lazily per team when needed.
  final Map<String, List<NevoboMatch>> _matchesByTeam = {};
  final Map<String, bool> _matchesLoadingByTeam = {};
  final Map<String, String> _matchesErrorByTeam = {};

  /// Accordion state: only one expanded at a time.
  final Set<String> _expandedTeamCodes = {};

  /// Per team: show all upcoming matches, or only next 3.
  final Map<String, bool> _showAllUpcomingByTeam = {};
  /// Per team: show all past results, or only last 3.
  final Map<String, bool> _showAllPastByTeam = {};

  /// Favoriete team codes, in de volgorde van favoritiseren (eerste = bovenaan).
  List<String> _favoriteTeamCodes = [];
  static const _favoritesKey = 'nevobo_standen_favorites';

  String _displayTeamCode(String code) {
    final normalized = code.trim().toUpperCase();
    // In-app naming preference: MR (recreanten/mix) is shown as XR.
    if (normalized.startsWith('MR')) return 'XR${normalized.substring(2)}';
    return normalized;
  }

  /// Team name for display: show "Minerva XR1" instead of "Minerva MR1".
  String _displayStandingTeamName(String name) {
    if (name.isEmpty) return name;
    return name.replaceAllMapped(
      RegExp(r'\bMR(\d+)\b', caseSensitive: false),
      (m) => 'XR${m.group(1)}',
    );
  }

  bool _isMinervaTeamName(String name) {
    final s = name.trim().toLowerCase();
    return s.contains('minerva');
  }

  /// Whether this standing entry is the given Minerva team (e.g. Minerva DS2 for code DS2).
  bool _standingMatchesTeam(NevoboStandingEntry entry, String teamCode) {
    if (!_isMinervaTeamName(entry.teamName)) return false;
    final extracted = NevoboApi.extractCodeFromTeamName(entry.teamName);
    if (extracted == null || extracted.isEmpty) return false;
    final a = extracted.trim().toUpperCase();
    final b = teamCode.trim().toUpperCase();
    // Display alias: app shows XR for MR (recreanten); API may return "Minerva MR1"
    if (a.startsWith('XR') && b.startsWith('MR') && a.substring(2) == b.substring(2)) return true;
    if (b.startsWith('XR') && a.startsWith('MR') && b.substring(2) == a.substring(2)) return true;
    return a == b;
  }

  /// Position of this specific Minerva team in the standings (1-based), or null if unknown.
  /// Match by name (Minerva + code) or by team path (ckm0v2o/dames/1).
  int? _minervaPosition(List<NevoboStandingEntry>? standings, String teamCode) {
    if (standings == null || standings.isEmpty) return null;
    final normPath = NevoboApi.resolvedTeamPath(teamCode)?.trim().toLowerCase().replaceAll(r'\', '/');
    for (final s in standings) {
      if (_standingMatchesTeam(s, teamCode)) return s.position;
      if (normPath != null &&
          s.teamPath != null &&
          s.teamPath!.trim().toLowerCase().replaceAll(r'\', '/') == normPath) {
        return s.position;
      }
    }
    return null;
  }

  /// Format position as "9e plek", "2e plek", etc.
  String _positionLabel(int position) {
    if (position <= 0) return '';
    return '${position}e plek';
  }

  // Parse "Team A - Team B" and determine whether Minerva is home (left side).
  bool _isMinervaHomeInSummary(String summary) {
    final s = summary.trim();
    final parts = s.split(' - ');
    if (parts.length == 2) {
      final home = parts[0].toLowerCase();
      final away = parts[1].toLowerCase();
      if (home.contains('minerva')) return true;
      if (away.contains('minerva')) return false;
    }
    // Fallback: if format is unexpected, assume Minerva is "home" for highlighting.
    return true;
  }

  // Highlight the Minerva team name in orange, keep the rest default.
  Widget _buildMatchSummaryText(String summary, {TextStyle? style}) {
    final base = style ??
        const TextStyle(
          color: AppColors.onBackground,
          fontWeight: FontWeight.w800,
        );
    final lower = summary.toLowerCase();
    final idx = lower.indexOf('minerva');
    if (idx < 0) return Text(summary, style: base);

    // Highlight from the first "minerva" occurrence until the next separator or end.
    final endIdx = (() {
      final nextSep = summary.indexOf(' - ', idx);
      if (nextSep >= 0) return nextSep;
      return summary.length;
    })();

    final before = summary.substring(0, idx);
    final mid = summary.substring(idx, endIdx);
    final after = summary.substring(endIdx);

    return RichText(
      text: TextSpan(
        style: base,
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          TextSpan(
            text: mid,
            style: base.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
  }

  // Render a set score like "25-20" with Minerva's points in orange.
  Widget _buildSetScoreText(String raw, {required bool isMinervaHome}) {
    final m = RegExp(r'^\s*(\d{1,2})\s*-\s*(\d{1,2})\s*$').firstMatch(raw);
    if (m == null) {
      return Text(
        raw,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    final a = m.group(1)!;
    final b = m.group(2)!;
    final leftStyle = TextStyle(
      color: isMinervaHome ? AppColors.primary : AppColors.textSecondary,
      fontSize: 12.5,
      fontWeight: FontWeight.w900,
    );
    final rightStyle = TextStyle(
      color: isMinervaHome ? AppColors.textSecondary : AppColors.primary,
      fontSize: 12.5,
      fontWeight: FontWeight.w900,
    );
    final dashStyle = const TextStyle(
      color: AppColors.textSecondary,
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
    );
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: a, style: leftStyle),
          TextSpan(text: '-', style: dashStyle),
          TextSpan(text: b, style: rightStyle),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  void _showMatchDetail(NevoboMatch m) {
    final when = m.start == null ? 'Onbekende datum' : _formatDateTime(m.start!);
    final where = (m.location ?? '').trim();
    final uitslag = _parseUitslagDisplay(m);
    final minervaHome = _isMinervaHomeInSummary(m.summary);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: _buildMatchSummaryText(
          m.summary,
          style: const TextStyle(
            color: AppColors.onBackground,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schedule, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(child: Text(when, style: const TextStyle(color: AppColors.textSecondary))),
              ],
            ),
            if (where.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(where, style: const TextStyle(color: AppColors.textSecondary))),
                ],
              ),
            ],
            if (uitslag.matchScore != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.emoji_events, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Uitslag: ${uitslag.matchScore}',
                      style: const TextStyle(
                        color: AppColors.onBackground,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (uitslag.setScores.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...uitslag.setScores.take(10).map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _buildSetScoreText(s, isMinervaHome: minervaHome),
                    ),
                  ),
            ],
            if ((m.volledigeUitslag ?? '').trim().isEmpty &&
                uitslag.matchScore == null) ...[
              const SizedBox(height: 12),
              const Text(
                'Uitslag nog niet beschikbaar.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
            if ((m.urlDwf ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final uri = Uri.tryParse(m.urlDwf!);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.link, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          m.urlDwf!,
                          style: const TextStyle(
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 3,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.open_in_new, size: 16, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ],
          ],
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

  ({String? matchScore, List<String> setScores}) _parseUitslagDisplay(NevoboMatch m) {
    final raw = (m.volledigeUitslag ?? '').trim();

    String? matchScore;
    final setScores = <String>[];

    if (raw.isNotEmpty) {
      // Example: "1-3  (21-25, 13-25, 14-25, 25-16)"
      final scoreMatch = RegExp(r'\b([0-5])\s*-\s*([0-5])\b').firstMatch(raw);
      if (scoreMatch != null) {
        matchScore = '${scoreMatch.group(1)}-${scoreMatch.group(2)}';
      }

      final setsMatch = RegExp(r'\(([^)]*)\)').firstMatch(raw);
      final setsRaw = setsMatch?.group(1)?.trim() ?? '';
      if (setsRaw.isNotEmpty) {
        for (final part in setsRaw.split(',')) {
          final s = part.trim();
          if (s.isEmpty) continue;
          setScores.add(s);
        }
      }
    }

    // Fallback: use eindstand when volledigeUitslag is empty/missing.
    if (matchScore == null && (m.eindstand != null && m.eindstand!.length >= 2)) {
      matchScore = '${m.eindstand![0]}-${m.eindstand![1]}';
    }

    return (matchScore: matchScore, setScores: setScores);
  }

  Future<void> _ensureMatchesLoaded(NevoboTeam team) async {
    final code = team.code;
    if (_matchesByTeam.containsKey(code)) return;
    if (_matchesLoadingByTeam[code] == true) return;

    setState(() {
      _matchesLoadingByTeam[code] = true;
      _matchesErrorByTeam.remove(code);
    });

    try {
      // Use the competition API here so uitslagen are reliable.
      final matches = await NevoboApi.fetchMatchesForTeamViaCompetitionApi(team: team);
      if (!mounted) return;
      setState(() {
        _matchesByTeam[code] = matches;
        _matchesLoadingByTeam[code] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _matchesErrorByTeam[code] = e.toString();
        _matchesLoadingByTeam[code] = false;
      });
    }
  }

  void _toggleExpanded(String teamCode) {
    setState(() {
      if (_expandedTeamCodes.contains(teamCode)) {
        _expandedTeamCodes.remove(teamCode);
      } else {
        _expandedTeamCodes.add(teamCode);
      }
    });
  }

  /// Teams gesorteerd: favorieten bovenaan (in volgorde van favoritiseren), daarna de rest.
  List<NevoboTeam> get _sortedTeams {
    final teamByCode = {for (final t in _teams) t.code: t};
    final favTeams = <NevoboTeam>[];
    for (final code in _favoriteTeamCodes) {
      final t = teamByCode[code];
      if (t != null) favTeams.add(t);
    }
    final favSet = _favoriteTeamCodes.toSet();
    final rest = _teams.where((t) => !favSet.contains(t.code)).toList()
      ..sort((a, b) => NevoboApi.compareTeamCodes(a.code, b.code));
    return [...favTeams, ...rest];
  }

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_favoritesKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>?;
      if (list == null) return;
      if (!mounted) return;
      setState(() {
        _favoriteTeamCodes = list.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      });
    } catch (_) {}
  }

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_favoritesKey, jsonEncode(_favoriteTeamCodes));
    } catch (_) {}
  }

  void _toggleFavorite(String teamCode) {
    setState(() {
      if (_favoriteTeamCodes.contains(teamCode)) {
        _favoriteTeamCodes.remove(teamCode);
      } else {
        _favoriteTeamCodes.add(teamCode);
      }
      _saveFavorites();
    });
  }

  // NOTE: uitslagen worden nu direct via GET /competitie/wedstrijden geladen.

  Widget _buildProgramma(NevoboTeam team) {
    final code = team.code;
    final loading = _matchesLoadingByTeam[code] == true;
    final err = _matchesErrorByTeam[code];
    final matches = _matchesByTeam[code] ?? const [];

    if (loading && matches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
          ),
        ),
      );
    }
    if (err != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(err, style: const TextStyle(color: AppColors.error)),
      );
    }

    final now = DateTime.now();
    final upcoming = matches
        .where((m) => (m.start ?? DateTime(2100)).isAfter(now.subtract(const Duration(hours: 2))))
        .toList()
      ..sort((a, b) => (a.start ?? DateTime(2100)).compareTo(b.start ?? DateTime(2100)));

    if (upcoming.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text('Geen programma gevonden.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final showAll = _showAllUpcomingByTeam[code] == true;
    final visibleUpcoming = showAll ? upcoming : upcoming.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...visibleUpcoming.map((m) {
        final when = m.start == null ? 'Onbekende datum' : _formatDateTime(m.start!);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showMatchDetail(m),
          child: GlassCard(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMatchSummaryText(
                  m.summary,
                  style: const TextStyle(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(when, style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        );
      }),
        if (upcoming.length > 3) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                setState(() => _showAllUpcomingByTeam[code] = !showAll);
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(showAll ? 'Minder…' : 'Meer…'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUitslagen(NevoboTeam team) {
    final code = team.code;
    final loading = _matchesLoadingByTeam[code] == true;
    final err = _matchesErrorByTeam[code];
    final matches = _matchesByTeam[code] ?? const [];

    if (loading && matches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
          ),
        ),
      );
    }
    if (err != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(err, style: const TextStyle(color: AppColors.error)),
      );
    }

    final now = DateTime.now();
    final past = matches
        .where((m) => (m.start ?? DateTime(2100)).isBefore(now.subtract(const Duration(hours: 2))))
        .toList()
      ..sort((a, b) => (b.start ?? DateTime(1900)).compareTo(a.start ?? DateTime(1900)));

    if (past.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text('Geen uitslagen gevonden.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final showAll = _showAllPastByTeam[code] == true;
    final visiblePast = showAll ? past : past.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...visiblePast.map((m) {
        final when = m.start == null ? 'Onbekende datum' : _formatDateTime(m.start!);
        final uitslag = _parseUitslagDisplay(m);
        final minervaHome = _isMinervaHomeInSummary(m.summary);
        final scoreMatch =
            RegExp(r'^\s*([0-5])\s*-\s*([0-5])\s*$').firstMatch(uitslag.matchScore ?? '');
        final homeSets = scoreMatch == null ? null : int.tryParse(scoreMatch.group(1)!);
        final awaySets = scoreMatch == null ? null : int.tryParse(scoreMatch.group(2)!);
        final minervaWon = (homeSets != null && awaySets != null)
            ? (minervaHome ? (homeSets > awaySets) : (awaySets > homeSets))
            : null;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showMatchDetail(m),
          child: GlassCard(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildMatchSummaryText(
                        m.summary,
                        style: const TextStyle(
                          color: AppColors.onBackground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (uitslag.matchScore != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: minervaWon == null
                              ? AppColors.darkBlue
                              : (minervaWon ? AppColors.success : AppColors.error),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          uitslag.matchScore!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(when, style: const TextStyle(color: AppColors.textSecondary)),
                if (uitslag.setScores.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...uitslag.setScores.take(5).map(
                        (s) => _buildSetScoreText(s, isMinervaHome: minervaHome),
                      ),
                ],
                if (uitslag.matchScore == null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Uitslag nog niet beschikbaar.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        );
      }),
        if (past.length > 3) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                setState(() => _showAllPastByTeam[code] = !showAll);
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(showAll ? 'Minder…' : 'Meer…'),
            ),
          ),
        ],
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadFavorites();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
      _standingsByTeam.clear();
      _errorByTeam.clear();
    });

    try {
      // Standen zijn altijd zichtbaar voor alle teams (onafhankelijk van koppeling).
      final teams = await NevoboApi.loadTeamsFromSupabase(client: _client);
      if (!mounted) return;
      setState(() => _teams = teams);

      // Also try to surface non-Nevobo teams (e.g. Volleystars) so they don't "disappear".
      // These won't have standings; we just show them as informational cards.
      try {
        final other = await _loadOtherTeamsFromSupabase();
        if (mounted) setState(() => _otherTeamNames = other);
      } catch (_) {
        // ignore
      }

      // Load sequentially to keep it simple and not hammer the API.
      for (final team in teams) {
        try {
          final standings = await NevoboApi.fetchStandingsForTeam(team: team);
          if (!mounted) return;
          setState(() {
            _standingsByTeam[team.code] = standings;
          });
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _errorByTeam[team.code] = e.toString();
          });
        }
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon standen niet laden.\n$e';
        _loading = false;
      });
    }
  }

  Future<List<String>> _loadOtherTeamsFromSupabase() async {
    // Best-effort: find Volleystars (and any other non-code teams) in the teams table.
    const candidates = <String>[
      'team_name',
      'name',
      'short_name',
      'code',
      'team_code',
      'abbreviation',
    ];
    for (final field in candidates) {
      try {
        final res = await _client.from('teams').select(field);
        final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
        final names = <String>{};
        for (final row in rows) {
          final raw = (row[field] ?? '').toString().trim();
          if (raw.isEmpty) continue;
          final lower = raw.toLowerCase();
          final code = NevoboApi.extractCodeFromTeamName(raw);
          // Anything without a Nevobo code but explicitly Volleystars: show it.
          if (code == null && lower.contains('volleystars')) {
            names.add(raw);
          }
        }
        if (names.isNotEmpty) {
          final list = names.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return list;
        }
      } catch (_) {
        // try next field
      }
    }
    return const [];
  }

  Future<void> refresh() async {
    await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
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
          'Geen teams gevonden voor standen.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadAll,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _sortedTeams.length + _otherTeamNames.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= _sortedTeams.length) {
            final name = _otherTeamNames[index - _sortedTeams.length];
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
                      name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Geen Nevobo-standen beschikbaar voor dit team.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            );
          }

          final team = _sortedTeams[index];
          final standings = _standingsByTeam[team.code];
          final error = _errorByTeam[team.code];
          final mode = _modeByTeamCode[team.code] ?? 0;
          final expanded = _expandedTeamCodes.contains(team.code);

          return GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(AppColors.cardRadius),
                  onTap: () => _toggleExpanded(team.code),
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
                            _displayTeamCode(team.code),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        if (standings != null && standings.isNotEmpty) ...[
                          Builder(
                            builder: (_) {
                              final pos = _minervaPosition(standings, team.code);
                              if (pos == null || pos <= 0) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Text(
                                  _positionLabel(pos),
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            _favoriteTeamCodes.contains(team.code)
                                ? Icons.star
                                : Icons.star_border,
                            color: _favoriteTeamCodes.contains(team.code)
                                ? AppColors.primary
                                : AppColors.iconMuted,
                          ),
                          tooltip: _favoriteTeamCodes.contains(team.code)
                              ? 'Uit favorieten'
                              : 'Toevoegen aan favorieten',
                          onPressed: () => _toggleFavorite(team.code),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(40, 40),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                        if (_loading && (standings == null && error == null) && expanded)
                          const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
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

                if (expanded) ...[
                  const SizedBox(height: 10),
                  GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          label: FittedBox(fit: BoxFit.scaleDown, child: Text('Standen', maxLines: 1)),
                        ),
                        ButtonSegment(
                          value: 1,
                          label: FittedBox(fit: BoxFit.scaleDown, child: Text('Programma', maxLines: 1)),
                        ),
                        ButtonSegment(
                          value: 2,
                          label: FittedBox(fit: BoxFit.scaleDown, child: Text('Uitslagen', maxLines: 1)),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (set) {
                        final next = set.first;
                        setState(() => _modeByTeamCode[team.code] = next);
                        if (next != 0) _ensureMatchesLoaded(team);
                      },
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        error,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    )
                  else if (mode == 0) ...[
                    if (standings == null || standings.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          'Geen stand gevonden.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
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
                                const SizedBox(width: 8),
                                SizedBox(width: 36, child: Text('Wedstr.', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                                const SizedBox(width: 10),
                                SizedBox(width: 36, child: Text('Punten', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                              ],
                            ),
                          ),
                          ...standings.map((s) {
                          final isMinerva = _isMinervaTeamName(s.teamName);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
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
                                      _displayStandingTeamName(s.teamName),
                                      style: TextStyle(
                                        color: AppColors.onBackground,
                                        fontWeight: isMinerva ? FontWeight.w900 : FontWeight.w700,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
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
                      ),
                  ] else if (mode == 1) ...[
                    _buildProgramma(team),
                  ] else ...[
                    _buildUitslagen(team),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

