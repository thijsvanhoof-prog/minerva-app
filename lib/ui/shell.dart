// lib/ui/shell.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/components/tab_page_header.dart';
import 'package:minerva_app/ui/app_user_context.dart';

import 'package:minerva_app/ui/home/home_tab.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/trainingen_wedstrijden_tab.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_standen_tab.dart';
import 'package:minerva_app/ui/tasks/my_tasks_tab.dart';
import 'package:minerva_app/ui/info/info_tab.dart';
import 'package:minerva_app/profiel/profiel_tab.dart';
import 'package:minerva_app/ui/commissies/commissies_tab.dart';

/// Callbacks voor in-app navigatie (bijv. Commissie → Contact zonder nieuw scherm).
class ShellNavigatorScope extends InheritedWidget {
  final VoidCallback switchToContactTab;

  const ShellNavigatorScope({
    super.key,
    required this.switchToContactTab,
    required super.child,
  });

  static ShellNavigatorScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellNavigatorScope>();
  }

  @override
  bool updateShouldNotify(ShellNavigatorScope oldWidget) =>
      switchToContactTab != oldWidget.switchToContactTab;

  /// Statische fallback wanneer InheritedWidget niet bereikbaar is (bijv. in dialogs).
  static VoidCallback? _switchToContactTab;

  static void registerSwitchToContactTab(VoidCallback cb) {
    _switchToContactTab = cb;
  }

  static void unregisterSwitchToContactTab() {
    _switchToContactTab = null;
  }

  static void goToContactTab() {
    _switchToContactTab?.call();
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    ShellNavigatorScope.registerSwitchToContactTab(_switchToContactTab);
  }

  @override
  void dispose() {
    ShellNavigatorScope.unregisterSwitchToContactTab();
    super.dispose();
  }

  void _switchToContactTab() {
    final userContext = AppUserContext.of(context);
    final hasTeam = userContext.memberships.isNotEmpty;
    final hasCommittees = userContext.committees.isNotEmpty ||
        userContext.hasFullAdminRights;
    final manageableTeams = userContext.memberships
        .where((m) => m.canManageTeam)
        .toList();
    final navItems = _buildNavItems(
      manageableTeams: manageableTeams,
      hasCommittees: hasCommittees,
      hasTeam: hasTeam,
      userContext: userContext,
    );
    int contactTabIndex = -1;
    for (var i = 0; i < navItems.length; i++) {
      if (navItems[i].page is InfoTab) {
        contactTabIndex = i;
        break;
      }
    }
    if (contactTabIndex >= 0 && contactTabIndex != _index) {
      setState(() => _index = contactTabIndex);
    }
  }

  Widget _navIcon(IconData icon, {required bool selected}) => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.darkBlue.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 24,
          color: selected ? AppColors.primary : Colors.white,
        ),
      );

  // Helper to keep nav structure in one place.
  // Beperkte weergave alleen wanneer géén team én géén commissie. Met commissie (of admin) = volledige toegang.
  List<_NavItem> _buildNavItems({
    required List<TeamMembership> manageableTeams,
    required bool hasCommittees,
    required bool hasTeam,
    required AppUserContext userContext,
  }) {
    final _ = userContext;

    final hasFullAccess = hasTeam || hasCommittees;
    // Toeschouwer: geen rol → alleen Uitgelicht, Agenda, Nieuws, Standen, Contact, Profiel
    if (!hasFullAccess) {
      return [
        _NavItem(
          page: const HomeTab(showOnlyHighlightsAndNews: false), // Uitgelicht + Agenda + Nieuws
          destination: NavigationDestination(
            icon: _navIcon(Icons.home_outlined, selected: false),
            selectedIcon: _navIcon(Icons.home, selected: true),
            label: 'Home',
          ),
        ),
        _NavItem(
          page: const _StandenOnlyPage(),
          destination: NavigationDestination(
            icon: _navIcon(Icons.leaderboard_outlined, selected: false),
            selectedIcon: _navIcon(Icons.leaderboard, selected: true),
            label: 'Standen',
          ),
        ),
        _NavItem(
          page: const InfoTab(),
          destination: NavigationDestination(
            icon: _navIcon(Icons.mail_outline, selected: false),
            selectedIcon: _navIcon(Icons.mail, selected: true),
            label: 'Contact',
          ),
        ),
        _NavItem(
          page: const ProfielTab(),
          destination: NavigationDestination(
            icon: _navIcon(Icons.person_outline, selected: false),
            selectedIcon: _navIcon(Icons.person, selected: true),
            label: 'Profiel',
          ),
        ),
      ];
    }

    final items = <_NavItem>[
      _NavItem(
        page: const HomeTab(),
        destination: NavigationDestination(
          icon: _navIcon(Icons.home_outlined, selected: false),
          selectedIcon: _navIcon(Icons.home, selected: true),
          label: 'Home',
        ),
      ),
      _NavItem(
        page: TrainingenWedstrijdenTab(manageableTeams: manageableTeams),
        destination: NavigationDestination(
          icon: _navIcon(Icons.emoji_events_outlined, selected: false),
          selectedIcon: _navIcon(Icons.emoji_events, selected: true),
          label: 'Teams',
        ),
      ),
      if (hasCommittees)
        _NavItem(
          page: const CommissiesTab(),
          destination: NavigationDestination(
            icon: _navIcon(Icons.badge_outlined, selected: false),
            selectedIcon: _navIcon(Icons.badge, selected: true),
            label: 'Commissie',
          ),
        ),
      _NavItem(
        page: const MyTasksTab(),
        destination: NavigationDestination(
          icon: _navIcon(Icons.task_alt_outlined, selected: false),
          selectedIcon: _navIcon(Icons.task_alt, selected: true),
          label: 'Taken',
        ),
      ),
      _NavItem(
        page: const InfoTab(),
        destination: NavigationDestination(
          icon: _navIcon(Icons.mail_outline, selected: false),
          selectedIcon: _navIcon(Icons.mail, selected: true),
          label: 'Contact',
        ),
      ),
      _NavItem(
        page: const ProfielTab(),
        destination: NavigationDestination(
          icon: _navIcon(Icons.person_outline, selected: false),
          selectedIcon: _navIcon(Icons.person, selected: true),
          label: 'Profiel',
        ),
      ),
    ];

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final userContext = AppUserContext.of(context);
    final hasTeam = userContext.memberships.isNotEmpty;
    final hasCommittees = userContext.committees.isNotEmpty ||
        userContext.hasFullAdminRights;

    // Filter to only teams the user can manage
    final manageableTeams = userContext.memberships
        .where((m) => m.canManageTeam)
        .toList();

    final navItems = _buildNavItems(
      manageableTeams: manageableTeams,
      hasCommittees: hasCommittees,
      hasTeam: hasTeam,
      userContext: userContext,
    );

    final selectedIndex = _index.clamp(0, navItems.length - 1);
    final pages = navItems.map((i) => i.page).toList();
    final destinations = navItems.map((i) => i.destination).toList();

    return ShellNavigatorScope(
      switchToContactTab: _switchToContactTab,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: AppColors.darkBlue,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: false,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Builder(
            builder: (context) {
              // Donkerblauwe strook bovenin (statusbalk): overlay zodat tab-inhoud niet verschuift; min. 44 als fallback.
              final topInset = MediaQuery.paddingOf(context).top;
              final statusBarHeight = topInset > 0 ? topInset : 44.0;
              return Stack(
                fit: StackFit.expand,
                children: [
                  IndexedStack(
                    index: selectedIndex,
                    children: pages,
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: AppColors.darkBlue,
                        child: SizedBox(height: statusBarHeight),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(
            navigationBarTheme: NavigationBarTheme.of(context).copyWith(
              iconTheme: WidgetStateProperty.resolveWith((states) {
                return IconThemeData(
                  color: AppColors.primary,
                  size: 24,
                );
              }),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                return TextStyle(
                  fontSize: 11,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: states.contains(WidgetState.selected)
                      ? AppColors.primary
                      : Colors.white,
                );
              }),
            ),
          ),
          child: ColoredBox(
            color: AppColors.darkBlue,
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

/// Alleen standen, voor gebruikers die niet aan een team zijn gekoppeld.
class _StandenOnlyPage extends StatelessWidget {
  const _StandenOnlyPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            TabPageHeader(
              child: Text(
                'Standen',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            const Expanded(child: NevoboStandenTab()),
          ],
        ),
      ),
    );
  }
}