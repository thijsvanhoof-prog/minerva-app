// lib/ui/shell.dart
import 'package:flutter/material.dart';

import 'package:minerva_app/ui/app_user_context.dart';

import 'package:minerva_app/ui/home/home_tab.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/trainingen_wedstrijden_tab.dart';
import 'package:minerva_app/ui/tasks/my_tasks_tab.dart';
import 'package:minerva_app/ui/info/info_tab.dart';
import 'package:minerva_app/profiel/profiel_tab.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final userContext = AppUserContext.of(context);
    
    // Filter to only teams the user can manage
    final manageableTeams = userContext.memberships
        .where((m) => m.canManageTeam)
        .toList();

    final pages = <Widget>[
      const HomeTab(),
      TrainingenWedstrijdenTab(
        manageableTeams: manageableTeams,
      ),
      const MyTasksTab(),
      const InfoTab(),
      const ProfielTab(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Train/Wed',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Taken',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: 'Info',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profiel',
          ),
        ],
      ),
    );
  }
}