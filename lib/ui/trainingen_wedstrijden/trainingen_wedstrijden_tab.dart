import 'package:flutter/material.dart';

import 'package:minerva_app/ui/components/app_logo_title.dart';
import 'package:minerva_app/ui/components/glass_card.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userContext = AppUserContext.of(context);
    final linkedCodes = userContext.memberships
        .map((m) => NevoboApi.extractCodeFromTeamName(m.teamName))
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    return Scaffold(
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
                controller: _tabController,
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
                  Tab(text: 'Trainingen'),
                  Tab(text: 'Wedstrijden'),
                  Tab(text: 'Standen'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          TrainingsTab(manageableTeams: widget.manageableTeams),
          NevoboWedstrijdenTab(teamCodes: linkedCodes),
          const NevoboStandenTab(),
        ],
      ),
    );
  }
}