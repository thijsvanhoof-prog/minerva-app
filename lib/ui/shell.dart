// lib/ui/shell.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/branded_background.dart';

import 'package:minerva_app/ui/home/home_tab.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/trainingen_wedstrijden_tab.dart';
import 'package:minerva_app/ui/tasks/my_tasks_tab.dart';
import 'package:minerva_app/ui/info/info_tab.dart';
import 'package:minerva_app/profiel/profiel_tab.dart';
import 'package:minerva_app/ui/tc/tc_tab.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  // Helper to keep nav structure in one place.
  List<_NavItem> _buildNavItems({
    required List<TeamMembership> manageableTeams,
    required bool showTc,
  }) {
    final items = <_NavItem>[
      _NavItem(
        page: const HomeTab(),
        destination: const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
      ),
      _NavItem(
        page: TrainingenWedstrijdenTab(manageableTeams: manageableTeams),
        destination: const NavigationDestination(
          icon: Icon(Icons.emoji_events_outlined),
          selectedIcon: Icon(Icons.emoji_events),
          label: 'Sport',
        ),
      ),
      if (showTc)
        _NavItem(
          page: const TcTab(),
          destination: const NavigationDestination(
            icon: Icon(Icons.settings_suggest_outlined),
            selectedIcon: Icon(Icons.settings_suggest),
            label: 'TC',
          ),
        ),
      _NavItem(
        page: const MyTasksTab(),
        destination: const NavigationDestination(
          icon: Icon(Icons.checklist_outlined),
          selectedIcon: Icon(Icons.checklist),
          label: 'Taken',
        ),
      ),
      _NavItem(
        page: const InfoTab(),
        destination: const NavigationDestination(
          icon: Icon(Icons.info_outline),
          selectedIcon: Icon(Icons.info),
          label: 'Info',
        ),
      ),
      _NavItem(
        page: const ProfielTab(),
        destination: const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Ik',
        ),
      ),
    ];

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final userContext = AppUserContext.of(context);
    
    // Filter to only teams the user can manage
    final manageableTeams = userContext.memberships
        .where((m) => m.canManageTeam)
        .toList();

    final showTc = userContext.hasFullAdminRights || userContext.isInTechnischeCommissie;
    final navItems = _buildNavItems(
      manageableTeams: manageableTeams,
      showTc: showTc,
    );

    final selectedIndex = _index.clamp(0, navItems.length - 1);
    final pages = navItems.map((i) => i.page).toList();
    final destinations = navItems.map((i) => i.destination).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        // Keep Android nav area consistent with our bottom bar background.
        systemNavigationBarColor: Colors.white,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            BrandedBackground(child: const SizedBox.shrink()),
            SafeArea(
              top: true,
              bottom: false,
              child: IndexedStack(
                index: selectedIndex,
                children: pages,
              ),
            ),
          ],
        ),
        bottomNavigationBar: ColoredBox(
          // Fully opaque so nothing can shine through as a "stripe".
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: NavigationBar(
              backgroundColor: Colors.white,
              elevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              indicatorColor: Colors.transparent,
              selectedIndex: selectedIndex,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: destinations,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final Widget page;
  final NavigationDestination destination;

  const _NavItem({
    required this.page,
    required this.destination,
  });
}