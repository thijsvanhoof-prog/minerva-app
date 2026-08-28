import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/tab_page_header.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/trainings_tab.dart';
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

  /// Spelers-tab: alle teams waar je géén beheerder bent (dus role = player, speler, lid, trainingslid, guardian, supporter).
  /// canManageTeam is true alleen voor trainer/coach/admin.
  static List<TeamMembership> _playerTeams(List<TeamMembership> memberships) {
    return memberships
        .where((m) => !m.canManageTeam)
        .toList()
      ..sort((a, b) => NevoboApi.compareTeamNames(a.teamName, b.teamName, volleystarsLast: true));
  }

  /// Alleen teams waar je als trainer/coach/admin staat.
  static List<TeamMembership> _trainerTeams(List<TeamMembership> memberships) {
    return memberships.where((m) => m.canManageTeam).toList()
      ..sort((a, b) => NevoboApi.compareTeamNames(a.teamName, b.teamName, volleystarsLast: true));
  }

  List<String> _teamCodesForMemberships(
    List<({NevoboTeam team, int? teamId})> withIds,
    List<TeamMembership> memberships,
  ) {
    final teamIds = memberships.map((m) => m.teamId).toSet();
    final codes = withIds
        .where((e) => e.teamId != null && teamIds.contains(e.teamId))
        .map((e) => e.team.code)
        .toSet()
        .toList()
      ..sort(NevoboApi.compareTeamCodes);
    if (codes.isEmpty && memberships.isNotEmpty) {
      codes.addAll(_fallbackLinkedCodes(memberships));
      codes.sort(NevoboApi.compareTeamCodes);
    }
    return codes;
  }

  List<String> _fallbackLinkedCodes(List<TeamMembership> memberships) {
    return memberships
        .map((m) => m.nevoboCode?.trim().toUpperCase() ?? NevoboApi.extractCodeFromTeamName(m.teamName))
        .whereType<String>()
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort(NevoboApi.compareTeamCodes);
  }

  @override
  Widget build(BuildContext context) {
    final userContext = AppUserContext.of(context);
    final isAdmin = userContext.hasFullAdminRights;
    final allMemberships = widget.manageableTeams;
    final playerTeams = _playerTeams(allMemberships);
    final trainerTeams = _trainerTeams(allMemberships);
    final hasTrainerRole = trainerTeams.isNotEmpty || isAdmin;

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
        final allTeamCodes = withIds
            .map((e) => e.team.code.trim().toUpperCase())
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort(NevoboApi.compareTeamCodes);
        final playerTeamCodes = isAdmin
            ? allTeamCodes
            : _teamCodesForMemberships(withIds, playerTeams);
        final trainerTeamCodes = isAdmin
            ? allTeamCodes
            : _teamCodesForMemberships(withIds, trainerTeams);

        if (playerTeams.isNotEmpty) {
          _autoSelectedTrainerSubTab = false;
        } else if (hasTrainerRole &&
            !isAdmin &&
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
                // Sub-tabs: Spelers | Trainers (alleen bij Trainingen, niet bij Wedstrijden)
                if (hasTrainerRole && _mainTabController.index == 0)
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
                        hasTrainerRole: hasTrainerRole,
                        playerTeams: trainingPlayerTeams,
                        trainerTeams: trainingTrainerTeams,
                      ),
                      // Wedstrijden
                      _buildWedstrijdenContent(
                        playerTeamCodes: playerTeamCodes,
                        trainerTeamCodes: trainerTeamCodes,
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
    required bool hasTrainerRole,
    required List<TeamMembership> playerTeams,
    required List<TeamMembership> trainerTeams,
  }) {
    if (!hasTrainerRole) {
      return TrainingsTab(manageableTeams: playerTeams);
    }
    return IndexedStack(
      index: _subTabController.index,
      children: [
        TrainingsTab(manageableTeams: playerTeams),
        TrainingsTab(manageableTeams: trainerTeams),
      ],
    );
  }

  Widget _buildWedstrijdenContent({
    required List<String> playerTeamCodes,
    required List<String> trainerTeamCodes,
    required List<({NevoboTeam team, int? teamId})> withIds,
  }) {
    final allTeamCodes = <String>{
      ...playerTeamCodes,
      ...trainerTeamCodes,
    }.toList()
      ..sort(NevoboApi.compareTeamCodes);
    if (allTeamCodes.isEmpty) {
      return _SpelersEmptyContent();
    }
    final teamIdByCode = <String, int>{};
    for (final e in withIds) {
      if (e.teamId != null) {
        teamIdByCode[e.team.code.trim().toUpperCase()] = e.teamId!;
      }
    }
    return NevoboWedstrijdenTab(
      teamCodes: allTeamCodes,
      teamIdByCode: teamIdByCode,
    );
  }
}

/// Lege staat wanneer je bij geen team als speler staat (Spelers-tab).
class _SpelersEmptyContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group_off,
              size: 48,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              'Je staat bij geen team als speler',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Staat je bij een team alleen als trainer/coach? Dan zie je dat team onder de tab Trainers.\n\n'
              'Om hier teams te zien: vraag de Technische Commissie (Commissie → TC) om je als speler aan een team toe te voegen.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
