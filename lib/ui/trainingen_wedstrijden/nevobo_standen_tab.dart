import 'package:flutter/material.dart';
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
  final Map<String, List<NevoboStandingEntry>> _standingsByTeam = {};
  final Map<String, String> _errorByTeam = {};

  // Per team view: 0 = standen, 1 = programma, 2 = uitslagen
  final Map<String, int> _modeByTeamCode = {};

  // Matches are loaded lazily per team when needed.
  final Map<String, List<NevoboMatch>> _matchesByTeam = {};
  final Map<String, bool> _matchesLoadingByTeam = {};
  final Map<String, String> _matchesErrorByTeam = {};

  /// Accordion state: only one expanded at a time.
  String? _expandedTeamCode;

  bool _isMinervaTeamName(String name) {
    final s = name.trim().toLowerCase();
    return s.contains('minerva');
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year} ${two(d.hour)}:${two(d.minute)}';
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
      _expandedTeamCode = (_expandedTeamCode == teamCode) ? null : teamCode;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: upcoming.map((m) {
        final when = m.start == null ? 'Onbekende datum' : _formatDateTime(m.start!);
        final where = (m.location ?? '').trim();
        return GlassCard(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.summary,
                style: const TextStyle(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(when, style: const TextStyle(color: AppColors.textSecondary)),
              if (where.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(where, style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ],
          ),
        );
      }).toList(),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: past.map((m) {
        final when = m.start == null ? 'Onbekende datum' : _formatDateTime(m.start!);
        final where = (m.location ?? '').trim();
        final uitslag = _parseUitslagDisplay(m);

        return GlassCard(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
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
                        color: AppColors.darkBlue,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        uitslag.matchScore!,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              if (uitslag.setScores.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...uitslag.setScores.take(5).map(
                      (s) => Text(
                        s,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
              ],
              const SizedBox(height: 4),
              Text(when, style: const TextStyle(color: AppColors.textSecondary)),
              if (where.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(where, style: const TextStyle(color: AppColors.textSecondary)),
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
        );
      }).toList(),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
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
      setState(() => _teams = teams);

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
      setState(() {
        _error = 'Kon standen niet laden.\n$e';
        _loading = false;
      });
    }
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
        itemCount: _teams.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final team = _teams[index];
          final standings = _standingsByTeam[team.code];
          final error = _errorByTeam[team.code];
          final mode = _modeByTeamCode[team.code] ?? 0;
          final expanded = _expandedTeamCode == team.code;

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
                            team.code,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        const Spacer(),
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
                        children: standings.map((s) {
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
                                      s.teamName,
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
                        }).toList(),
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

