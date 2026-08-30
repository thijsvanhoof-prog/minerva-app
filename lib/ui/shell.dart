// lib/ui/shell.dart
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';

import 'package:minerva_app/ui/home/home_tab.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/trainingen_wedstrijden_tab.dart';
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
    final navItems = _buildNavItems(userContext: userContext);
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

  /// Gast (`profileId` leeg): Home, Contact, Profiel.
  /// Eigen account: Home, Teams, Commissies, Contact, Taken, Profiel.
  List<_NavItem> _buildNavItems({
    required AppUserContext userContext,
  }) {
    final isGuest = userContext.profileId.trim().isEmpty;

    if (isGuest) {
      return [
        _NavItem(
          page: const HomeTab(showOnlyHighlightsAndNews: true),
          destination: NavigationDestination(
            icon: _navIcon(Icons.home_outlined, selected: false),
            selectedIcon: _navIcon(Icons.home, selected: true),
            label: 'Home',
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

    return [
      _NavItem(
        page: const HomeTab(),
        destination: NavigationDestination(
          icon: _navIcon(Icons.home_outlined, selected: false),
          selectedIcon: _navIcon(Icons.home, selected: true),
          label: 'Home',
        ),
      ),
      _NavItem(
        page: TrainingenWedstrijdenTab(manageableTeams: userContext.memberships),
        destination: NavigationDestination(
          icon: _navIcon(Icons.emoji_events_outlined, selected: false),
          selectedIcon: _navIcon(Icons.emoji_events, selected: true),
          label: 'Teams',
        ),
      ),
      _NavItem(
        page: const CommissiesTab(),
        destination: NavigationDestination(
          icon: _navIcon(Icons.badge_outlined, selected: false),
          selectedIcon: _navIcon(Icons.badge, selected: true),
          label: 'Commissies',
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
        page: const MyTasksTab(),
        destination: NavigationDestination(
          icon: _navIcon(Icons.task_alt_outlined, selected: false),
          selectedIcon: _navIcon(Icons.task_alt, selected: true),
          label: 'Taken',
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

  @override
  Widget build(BuildContext context) {
    final userContext = AppUserContext.of(context);

    final navItems = _buildNavItems(userContext: userContext);

    final selectedIndex = _index.clamp(0, navItems.length - 1);
    final pages = navItems.map((i) => i.page).toList();
    final destinations = navItems.map((i) => i.destination).toList();

    // Android 15+: statusBarColor/navigationBarColor/navigationBarDividerColor zijn beëindigd.
    // Op Android alleen brightness; op iOS wel kleuren.
    final overlayStyle = defaultTargetPlatform == TargetPlatform.android
        ? const SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarIconBrightness: Brightness.light,
          )
        : SystemUiOverlayStyle(
            statusBarColor: AppColors.darkBlue,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
          );

    return ShellNavigatorScope(
      switchToContactTab: _switchToContactTab,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
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
