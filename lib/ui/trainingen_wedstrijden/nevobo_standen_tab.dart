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

  bool _isMinervaTeamName(String name) {
    final s = name.trim().toLowerCase();
    return s.contains('minerva');
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
      final teams = await NevoboApi.loadTeamsFromSupabase(client: _client);
      setState(() {
        _teams = teams;
      });

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
                    if (_loading && (standings == null && error == null))
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
                const SizedBox(height: 10),
                if (error != null)
                  Text(
                    error,
                    style: const TextStyle(color: AppColors.error),
                  )
                else if (standings == null || standings.isEmpty)
                  const Text(
                    'Geen stand gevonden.',
                    style: TextStyle(color: AppColors.textSecondary),
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
              ],
            ),
          );
        },
      ),
    );
  }
}

