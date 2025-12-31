import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_user_context.dart';
import 'trainings_tab.dart';
import 'nevobo_wedstrijden_tab.dart';

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
    _tabController = TabController(length: 2, vsync: this);
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Trainingen & Wedstrijden'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.onBackground,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'Trainingen'),
            Tab(text: 'Wedstrijden'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          TrainingsTab(manageableTeams: widget.manageableTeams),
          const NevoboWedstrijdenTab(),
        ],
      ),
    );
  }
}