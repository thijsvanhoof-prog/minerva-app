import 'package:flutter/material.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/tab_page_header.dart';
import 'package:minerva_app/ui/shell.dart';
import 'package:minerva_app/profiel/admin_gebruikersnamen_page.dart';
import 'package:minerva_app/ui/bestuur/bestuur_tab.dart';
import 'package:minerva_app/ui/tc/tc_tab.dart';
import 'package:minerva_app/ui/tasks/my_tasks_tab.dart';

class CommissiesTab extends StatelessWidget {
  const CommissiesTab({super.key});

  /// Korte labels voor de tabbalk bovenaan.
  static String _formatTabLabel(String key) {
    switch (key.trim().toLowerCase()) {
      case 'bestuur':
        return 'Bestuur';
      case 'technische-commissie':
      case 'tc':
        return 'TC';
      case 'communicatie':
        return 'CC';
      case 'wedstrijdzaken':
        return 'WZ';
      case 'admin':
        return 'Admin';
      default:
        return _formatCommitteeName(key);
    }
  }

  static String _formatCommitteeName(String key) {
    final k = key.trim();
    if (k.isEmpty) return key;
    switch (k.toLowerCase()) {
      case 'bestuur':
        return 'Bestuur';
      case 'technische-commissie':
      case 'tc':
        return 'Technische commissie';
      case 'communicatie':
        return 'Communicatie commissie';
      case 'wedstrijdzaken':
        return 'Wedstrijdzaken';
      case 'admin':
        return 'Admin';
      case 'jeugd':
        return 'Jeugdcommissie';
      default:
        return '${k[0].toUpperCase()}${k.substring(1).replaceAll('-', ' ')}';
    }
  }

  /// Volgorde: Admin eerst (licht), dan Bestuur, TC, CC, WZ – voorkomt freeze bij opstarten.
  static int _committeeOrder(String key) {
    switch (key.trim().toLowerCase()) {
      case 'admin':
        return 0;
      case 'bestuur':
        return 1;
      case 'technische-commissie':
      case 'tc':
        return 2;
      case 'communicatie':
        return 3;
      case 'wedstrijdzaken':
        return 4;
      default:
        return 5;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);
    // Altijd de vier vaste tabs tonen (Bestuur, TC, CC, WZ). Toegang tot inhoud regelt elke tab zelf.
    final List<String> committees = [
      'bestuur',
      'technische-commissie',
      'communicatie',
      'wedstrijdzaken',
    ];
    // Eventuele extra commissies uit context (bijv. jeugd) toevoegen.
    for (final c in ctx.committees) {
      final k = c.trim().toLowerCase();
      if (k != 'bestuur' && k != 'technische-commissie' && k != 'tc' &&
          k != 'wedstrijdzaken' && k != 'communicatie' && k != 'admin') {
        if (!committees.any((x) => x.trim().toLowerCase() == k)) {
          committees.add(c);
        }
      }
    }
    // Admin-tab voor iedereen die alle accounts mag zien (bestuur, TC, admins).
    if (ctx.canViewAllAccounts && !committees.any((c) => c.trim().toLowerCase() == 'admin')) {
      committees.add('admin');
    }
    committees.sort((a, b) {
      final orderA = _committeeOrder(a);
      final orderB = _committeeOrder(b);
      if (orderA != orderB) return orderA.compareTo(orderB);
      return _formatCommitteeName(a).compareTo(_formatCommitteeName(b));
    });

    if (committees.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              TabPageHeader(
                child: Text(
                  'Commissie',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              await ctx.reloadUserContext?.call();
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.badge_outlined,
                        size: 48,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Je zit niet in een commissie',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Commissieleden kunnen hier hun taken bekijken en uitvoeren.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
              ),
            ],
          ),
        ),
      );
    }

    // Lazy: bouw alleen de geselecteerde tab (voorkomt freeze bij Shell-start)
    return DefaultTabController(
      length: committees.length,
      initialIndex: 0,
      child: _CommissiesTabBody(committees: committees),
    );
  }
}

class _CommissiesTabBody extends StatefulWidget {
  final List<String> committees;

  const _CommissiesTabBody({required this.committees});

  @override
  State<_CommissiesTabBody> createState() => _CommissiesTabBodyState();
}

class _CommissiesTabBodyState extends State<_CommissiesTabBody> {
  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            TabPageHeader(
              child: Text(
                'Commissie',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Padding(
              padding: AppColors.tabContentPadding,
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                showBorder: false,
                showShadow: false,
                child: TabBar(
                  controller: controller,
                  isScrollable: widget.committees.length > 2,
                  tabAlignment: TabAlignment.center,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: AppColors.darkBlue,
                    borderRadius: BorderRadius.circular(AppColors.cardRadius),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: widget.committees
                      .map((c) => Tab(text: CommissiesTab._formatTabLabel(c)))
                      .toList(),
                ),
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) => IndexedStack(
                  index: controller.index,
                  children: widget.committees.map((c) {
                    return _CommitteeContent(
                      committeeKey: c,
                      committeeName: CommissiesTab._formatCommitteeName(c),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommitteeContent extends StatelessWidget {
  final String committeeKey;
  final String committeeName;

  const _CommitteeContent({
    required this.committeeKey,
    required this.committeeName,
  });

  @override
  Widget build(BuildContext context) {
    final key = committeeKey.trim().toLowerCase();

    // Technische commissie: TC-taken (trainingen, wedstrijden, teams)
    if (key == 'technische-commissie' || key == 'tc') {
      return const TcTab();
    }

    // Bestuur: trainingen, wedstrijden, commissies beheren
    if (key == 'bestuur') {
      return const BestuurTab();
    }

    // Wedstrijdzaken: teamtaken + overzicht (altijd volledig zichtbaar)
    if (key.contains('wedstrijd')) {
      return const MyTasksTab(forceFullView: true);
    }

    // Admin: gebruikersnamen, etc.
    if (key == 'admin') {
      return const _AdminCommitteeView();
    }

    // Overige commissies (communicatie, jeugd, etc.): contact/info
    return _GenericCommitteeView(committeeName: committeeName);
  }
}

class _AdminCommitteeView extends StatelessWidget {
  const _AdminCommitteeView();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassCard(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined, color: AppColors.primary),
              title: const Text(
                'Gebruikersnamen en accounts',
                style: TextStyle(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Bekijk alle accounts, wijzig gebruikersnamen of voeg leden aan teams toe. Zichtbaar voor bestuur, TC en admins.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminGebruikersnamenPage(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GenericCommitteeView extends StatelessWidget {
  final String committeeName;

  const _GenericCommitteeView({required this.committeeName});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.badge_outlined, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        committeeName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Deze commissie heeft geen specifieke taken in de app. '
                  'Voor contactgegevens kun je naar het Contact-tabblad.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: ShellNavigatorScope.goToContactTab,
                  icon: const Icon(Icons.mail_outline, size: 18),
                  label: const Text('Contactpersonen bekijken'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
