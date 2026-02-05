import 'package:flutter/material.dart';

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
      ..sort(NevoboApi.compareTeamCodes);

    final manageableTeamsSorted = [...widget.manageableTeams]
      ..sort((a, b) => NevoboApi.compareTeamNames(a.teamName, b.teamName, volleystarsLast: true));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                    Tab(text: 'Trainingen'),
                    Tab(text: 'Wedstrijden'),
                    Tab(text: 'Standen'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  TrainingsTab(manageableTeams: manageableTeamsSorted),
                  NevoboWedstrijdenTab(teamCodes: linkedCodes),
                  const NevoboStandenTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}