import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/tab_page_header.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/trainings_tab.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_wedstrijden_tab.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_standen_tab.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_api.dart';

class TrainingenWedstrijdenTab extends StatefulWidget {
  final List<TeamMembership> manageableTeams;

  const TrainingenWedstrijdenTab({
    super.key,
    required this.manageableTeams,
  });

  @override
  State<TrainingenWedstrijdenTab> createState() =>
      _TrainingenWedstrijdenTabState();
}

class _TrainingenWedstrijdenTabState extends State<TrainingenWedstrijdenTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  /// Alle teams met team_id (voor Standen en om wedstrijden te filteren op “mijn” teams).
  late final Future<List<({NevoboTeam team, int? teamId})>> _teamsWithIdsFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _teamsWithIdsFuture = NevoboApi.loadTeamsFromSupabaseWithIds(
      client: Supabase.instance.client,
      excludeTrainingOnly: false,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userContext = AppUserContext.of(context);
    final manageableTeamsSorted = [...widget.manageableTeams]
      ..sort((a, b) => NevoboApi.compareTeamNames(a.teamName, b.teamName, volleystarsLast: true));

    return FutureBuilder<List<({NevoboTeam team, int? teamId})>>(
      future: _teamsWithIdsFuture,
      builder: (context, snapshot) {
        final withIds = snapshot.data ?? const [];
        // Tab Wedstrijden: alleen teams tonen waar de gebruiker bij hoort.
        final myTeamIds = userContext.memberships.map((m) => m.teamId).toSet();
        final wedstrijdenCodes = withIds
            .where((e) => e.teamId != null && myTeamIds.contains(e.teamId))
            .map((e) => e.team.code)
            .toSet()
            .toList()
          ..sort(NevoboApi.compareTeamCodes);
        // Als er geen match is via team_id (bijv. oude data), fallback op codes uit memberships.
        if (wedstrijdenCodes.isEmpty && userContext.memberships.isNotEmpty) {
          wedstrijdenCodes.addAll(_fallbackLinkedCodes(userContext));
          wedstrijdenCodes.sort(NevoboApi.compareTeamCodes);
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [
                TabPageHeader(
                  child: Text(
                    'Teams',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
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
                        Tab(text: 'Trainingen'),
                        Tab(text: 'Wedstrijden'),
                        Tab(text: 'Standen'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _tabController.index,
                    children: [
                      TrainingsTab(manageableTeams: manageableTeamsSorted),
                      NevoboWedstrijdenTab(teamCodes: wedstrijdenCodes),
                      const NevoboStandenTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Fallback als Supabase nog geen teams teruggeeft (bijv. RPC niet gedraaid).
  List<String> _fallbackLinkedCodes(AppUserContext userContext) {
    return userContext.memberships
        .map((m) => m.nevoboCode?.trim().toUpperCase() ?? NevoboApi.extractCodeFromTeamName(m.teamName))
        .whereType<String>()
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort(NevoboApi.compareTeamCodes);
  }
}