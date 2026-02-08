// lib/ui/shell.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/branded_background.dart';

import 'package:minerva_app/ui/home/home_tab.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/trainingen_wedstrijden_tab.dart';
import 'package:minerva_app/ui/tasks/my_tasks_tab.dart';
import 'package:minerva_app/ui/info/info_tab.dart';
import 'package:minerva_app/profiel/profiel_tab.dart';
import 'package:minerva_app/ui/commissies/commissies_tab.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  Widget _navIcon(IconData icon) => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.darkBlue.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 24, color: AppColors.primary),
      );

  // Helper to keep nav structure in one place.
  List<_NavItem> _buildNavItems({
    required List<TeamMembership> manageableTeams,
    required bool hasCommittees,
  }) {
    final items = <_NavItem>[
      _NavItem(
        page: const HomeTab(),
        destination: NavigationDestination(
          icon: _navIcon(Icons.home_outlined),
          selectedIcon: _navIcon(Icons.home),
          label: 'Home',
        ),
      ),
      _NavItem(
        page: TrainingenWedstrijdenTab(manageableTeams: manageableTeams),
        destination: NavigationDestination(
          icon: _navIcon(Icons.emoji_events_outlined),
          selectedIcon: _navIcon(Icons.emoji_events),
          label: 'Teams',
        ),
      ),
      if (hasCommittees)
        _NavItem(
          page: const CommissiesTab(),
          destination: NavigationDestination(
            icon: _navIcon(Icons.badge_outlined),
            selectedIcon: _navIcon(Icons.badge),
            label: 'Commissie',
          ),
        ),
      _NavItem(
        page: const MyTasksTab(),
        destination: NavigationDestination(
          icon: _navIcon(Icons.checklist_outlined),
          selectedIcon: _navIcon(Icons.checklist),
          label: 'Taken',
        ),
      ),
      _NavItem(
        page: const InfoTab(),
        destination: NavigationDestination(
          icon: _navIcon(Icons.mail_outline),
          selectedIcon: _navIcon(Icons.mail),
          label: 'Contact',
        ),
      ),
      _NavItem(
        page: const ProfielTab(),
        destination: NavigationDestination(
          icon: _navIcon(Icons.person_outline),
          selectedIcon: _navIcon(Icons.person),
          label: 'Profiel',
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

    final hasCommittees = userContext.committees.isNotEmpty ||
        userContext.hasFullAdminRights;
    final navItems = _buildNavItems(
      manageableTeams: manageableTeams,
      hasCommittees: hasCommittees,
    );

    final selectedIndex = _index.clamp(0, navItems.length - 1);
    final pages = navItems.map((i) => i.page).toList();
    final destinations = navItems.map((i) => i.destination).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: false,
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
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(
            navigationBarTheme: NavigationBarTheme.of(context).copyWith(
              iconTheme: WidgetStateProperty.resolveWith((states) {
                return IconThemeData(
                  color: Colors.white,
                  size: 24,
                );
              }),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                return TextStyle(
                  fontSize: 11,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: AppColors.primary,
                );
              }),
            ),
          ),
          child: ColoredBox(
            color: AppColors.darkBlue.withValues(alpha: 0.92),
            child: SafeArea(
              top: false,
              child: NavigationBar(
                backgroundColor: Colors.transparent,
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