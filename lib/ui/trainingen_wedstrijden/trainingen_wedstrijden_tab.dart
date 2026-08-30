import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/tab_page_header.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/trainings_tab.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/match_team_code_resolution.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_wedstrijden_tab.dart';
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
    with TickerProviderStateMixin {
  late TabController _mainTabController;
  late TabController _subTabController;
  bool _autoSelectedTrainerSubTab = false;
  /// Alle teams met team_id (om wedstrijden te filteren op “mijn” teams).
  late final Future<List<({NevoboTeam team, int? teamId})>> _teamsWithIdsFuture;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this);
    _subTabController = TabController(length: 2, vsync: this);
    _mainTabController.addListener(() {
      if (mounted) setState(() {});
    });
    _subTabController.addListener(() {
      if (mounted) setState(() {});
    });
    _teamsWithIdsFuture = NevoboApi.loadTeamsFromSupabaseWithIds(
      client: Supabase.instance.client,
      excludeTrainingOnly: false,
    );
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    _subTabController.dispose();
    super.dispose();
  }

  /// Spelers- en trainersteams via gedeelde rol-logica (deterministisch per teamId).
  TrainingTabTeamSplit _trainingTeamSplit(List<TeamMembership> memberships) {
    return splitTeamMembershipsForTrainingTabs(memberships);
  }

  Map<int, String> _codeByTeamIdFromWithIds(
    List<({NevoboTeam team, int? teamId})> withIds,
  ) {
    final codeByTeamId = <int, String>{};
    for (final e in withIds) {
      if (e.teamId != null) {
        codeByTeamId[e.teamId!] = e.team.code;
      }
    }
    return codeByTeamId;
  }

  @override
  Widget build(BuildContext context) {
    final userContext = AppUserContext.of(context);
    final isAdmin = userContext.hasFullAdminRights;
    final allMemberships = widget.manageableTeams;
    final teamSplit = _trainingTeamSplit(allMemberships);
    var playerTeams = teamSplit.playerTeams
      ..sort((a, b) => NevoboApi.compareTeamNames(a.teamName, b.teamName, volleystarsLast: true));
    var trainerTeams = teamSplit.trainerTeams
      ..sort((a, b) => NevoboApi.compareTeamNames(a.teamName, b.teamName, volleystarsLast: true));

    return FutureBuilder<List<({NevoboTeam team, int? teamId})>>(
      future: _teamsWithIdsFuture,
      builder: (context, snapshot) {
        final withIds = snapshot.data ?? const [];
        final adminAllTeams = withIds
            .where((e) => e.teamId != null)
            .map(
              (e) => TeamMembership(
                teamId: e.teamId!,
                role: 'admin',
                teamName: 'Minerva ${NevoboApi.displayTeamCode(e.team.code)}',
                nevoboCode: e.team.code,
              ),
            )
            .toList()
          ..sort(
            (a, b) => NevoboApi.compareTeamCodes(
              a.nevoboCode ?? NevoboApi.extractCodeFromTeamName(a.teamName) ?? '',
              b.nevoboCode ?? NevoboApi.extractCodeFromTeamName(b.teamName) ?? '',
            ),
          );
        final trainingPlayerTeams = isAdmin ? adminAllTeams : playerTeams;
        final trainingTrainerTeams = isAdmin ? adminAllTeams : trainerTeams;

        if (playerTeams.isNotEmpty) {
          _autoSelectedTrainerSubTab = false;
        } else if (!isAdmin &&
            trainerTeams.isNotEmpty &&
            !_autoSelectedTrainerSubTab) {
          _autoSelectedTrainerSubTab = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _subTabController.index != 1) {
              _subTabController.animateTo(1);
            }
          });
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
                // Hoofdtabs: Trainingen | Wedstrijden
                Padding(
                  padding: AppColors.tabContentPadding,
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    showBorder: false,
                    showShadow: false,
                    child: TabBar(
                      controller: _mainTabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.center,
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        color: AppColors.darkBlue,
                        borderRadius: BorderRadius.circular(AppColors.cardRadius),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.textSecondary,
                      tabs: const [
                        Tab(text: 'Trainingen'),
                        Tab(text: 'Wedstrijden'),
                      ],
                    ),
                  ),
                ),
                // Sub-tabs: Spelers | Trainers (altijd bij Trainingen)
                if (_mainTabController.index == 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      showBorder: false,
                      showShadow: false,
                      child: TabBar(
                        controller: _subTabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.center,
                        dividerColor: Colors.transparent,
                        indicator: BoxDecoration(
                          color: AppColors.darkBlue,
                          borderRadius: BorderRadius.circular(AppColors.cardRadius),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: AppColors.primary,
                        unselectedLabelColor: AppColors.textSecondary,
                        tabs: const [
                          Tab(text: 'Spelers'),
                          Tab(text: 'Trainers'),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _mainTabController.index,
                    children: [
                      // Trainingen
                      _buildTrainingenContent(
                        isAdmin: isAdmin,
                        playerTeams: trainingPlayerTeams,
                        trainerTeams: trainingTrainerTeams,
                      ),
                      // Wedstrijden
                      _buildWedstrijdenContent(
                        isAdmin: isAdmin,
                        allMemberships: allMemberships,
                        viewingAsProfileId: userContext.viewingAsProfileId,
                        withIds: withIds,
                      ),
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

  Widget _buildTrainingenContent({
    required bool isAdmin,
    required List<TeamMembership> playerTeams,
    required List<TeamMembership> trainerTeams,
  }) {
    return IndexedStack(
      index: _subTabController.index,
      children: [
        TrainingsTab(
          manageableTeams: playerTeams,
          viewRole: TrainingTabViewRole.player,
          suppressRoleEmptyState: isAdmin,
        ),
        TrainingsTab(
          manageableTeams: trainerTeams,
          viewRole: TrainingTabViewRole.trainer,
          suppressRoleEmptyState: isAdmin,
        ),
      ],
    );
  }

  Widget _buildWedstrijdenContent({
    required bool isAdmin,
    required List<TeamMembership> allMemberships,
    required String? viewingAsProfileId,
    required List<({NevoboTeam team, int? teamId})> withIds,
  }) {
    final codeByTeamId = _codeByTeamIdFromWithIds(withIds);

    if (isAdmin) {
      final adminCodes = withIds
          .map((e) => e.team.code.trim().toUpperCase())
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList()
        ..sort(NevoboApi.compareTeamCodes);
      final viewState = resolveMatchWedstrijdenViewState(
        matchTeams: const [],
        resolvedCodes: adminCodes,
        isGlobalAdmin: true,
      );
      if (viewState == MatchWedstrijdenViewState.adminNoValidCodes) {
        return const _MatchAdminNoCodesContent();
      }
      final teamIdByCode = <String, int>{};
      for (final e in withIds) {
        if (e.teamId != null) {
          teamIdByCode[e.team.code.trim().toUpperCase()] = e.teamId!;
        }
      }
      return NevoboWedstrijdenTab(
        teamCodes: adminCodes,
        teamIdByCode: teamIdByCode,
      );
    }

    final matchTeams = matchAccessTeamMemberships(
      allMemberships,
      viewingAsProfileId: viewingAsProfileId,
    );
    final resolution = resolveMatchTeamCodes(
      matchTeams: matchTeams,
      codeByTeamId: codeByTeamId,
    );
    final viewState = resolveMatchWedstrijdenViewState(
      matchTeams: matchTeams,
      resolvedCodes: resolution.codes,
      isGlobalAdmin: false,
    );

    switch (viewState) {
      case MatchWedstrijdenViewState.notLinked:
        return const _MatchAccessEmptyContent();
      case MatchWedstrijdenViewState.missingTeamCode:
        return _MatchTeamCodeMissingContent(matchTeams: matchTeams);
      case MatchWedstrijdenViewState.adminNoValidCodes:
        return const _MatchAdminNoCodesContent();
      case MatchWedstrijdenViewState.showMatches:
        final teamIdByCode = <String, int>{};
        for (final e in withIds) {
          if (e.teamId != null) {
            teamIdByCode[e.team.code.trim().toUpperCase()] = e.teamId!;
          }
        }
        return NevoboWedstrijdenTab(
          teamCodes: resolution.codes,
          teamIdByCode: teamIdByCode,
        );
    }
  }
}

/// Lege staat voor Wedstrijden zonder speler/trainer/coach-koppeling.
class _MatchAccessEmptyContent extends StatelessWidget {
  const _MatchAccessEmptyContent();

  Future<void> _refresh(BuildContext context) async {
    final ctx = AppUserContext.of(context);
    await ctx.reloadUserContext?.call();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _refresh(context),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.emoji_events_outlined,
            size: 48,
            color: AppColors.textSecondary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          Text(
            matchAccessEmptyMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Center(
            child: ElevatedButton.icon(
              onPressed: AppUserContext.of(context).reloadUserContext == null
                  ? null
                  : () => _refresh(context),
              icon: const Icon(Icons.refresh),
              label: const Text('Opnieuw laden'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lege staat: gekoppeld team(s) zonder Nevobo-code.
class _MatchTeamCodeMissingContent extends StatelessWidget {
  final List<TeamMembership> matchTeams;

  const _MatchTeamCodeMissingContent({required this.matchTeams});

  Future<void> _refresh(BuildContext context) async {
    final ctx = AppUserContext.of(context);
    await ctx.reloadUserContext?.call();
  }

  @override
  Widget build(BuildContext context) {
    final sortedTeams = List<TeamMembership>.from(matchTeams)
      ..sort((a, b) => NevoboApi.compareTeamNames(a.teamName, b.teamName, volleystarsLast: true));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _refresh(context),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.link_off,
            size: 48,
            color: AppColors.textSecondary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          Text(
            matchTeamCodeMissingHeadline(sortedTeams.length),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          ...sortedTeams.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '- ${m.displayLabel}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            matchTeamCodeMissingTcHint,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: ElevatedButton.icon(
              onPressed: AppUserContext.of(context).reloadUserContext == null
                  ? null
                  : () => _refresh(context),
              icon: const Icon(Icons.refresh),
              label: const Text('Opnieuw laden'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lege staat voor global admin zonder teams met geldige Nevobo-code.
class _MatchAdminNoCodesContent extends StatelessWidget {
  const _MatchAdminNoCodesContent();

  Future<void> _refresh(BuildContext context) async {
    final ctx = AppUserContext.of(context);
    await ctx.reloadUserContext?.call();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _refresh(context),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.emoji_events_outlined,
            size: 48,
            color: AppColors.textSecondary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          Text(
            matchAdminNoValidCodesMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Center(
            child: ElevatedButton.icon(
              onPressed: AppUserContext.of(context).reloadUserContext == null
                  ? null
                  : () => _refresh(context),
              icon: const Icon(Icons.refresh),
              label: const Text('Opnieuw laden'),
            ),
          ),
        ],
      ),
    );
  }
}
