import 'package:flutter/material.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/profiel/admin_gebruikersnamen_page.dart';
import 'package:minerva_app/ui/bestuur/bestuur_tab.dart';
import 'package:minerva_app/ui/tc/tc_tab.dart';
import 'package:minerva_app/ui/tasks/my_tasks_tab.dart';
import 'package:minerva_app/ui/info/info_tab.dart';

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

  /// Vaste volgorde: Bestuur, TC, CC, WZ, Admin.
  static int _committeeOrder(String key) {
    switch (key.trim().toLowerCase()) {
      case 'bestuur':
        return 0;
      case 'technische-commissie':
      case 'tc':
        return 1;
      case 'communicatie':
        return 2;
      case 'wedstrijdzaken':
        return 3;
      case 'admin':
        return 4;
      default:
        return 5;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);
    List<String> committees;
    // Bestuur: alles kunnen zien, behalve Admin.
    if (ctx.isInBestuur) {
      committees = [
        'bestuur',
        'technische-commissie',
        'communicatie',
        'wedstrijdzaken',
      ];
    } else {
      // TC, WZ, CC, Admin: alleen de eigen tab. Overige commissies (jeugd, etc.) behouden.
      committees = [];
      if (ctx.isInTechnischeCommissie) committees.add('technische-commissie');
      if (ctx.isInWedstrijdzaken) committees.add('wedstrijdzaken');
      if (ctx.isInCommunicatie) committees.add('communicatie');
      if (ctx.hasFullAdminRights) committees.add('admin');
      for (final c in ctx.committees) {
        final k = c.trim().toLowerCase();
        if (k != 'bestuur' && k != 'technische-commissie' && k != 'tc' &&
            k != 'wedstrijdzaken' && k != 'communicatie' && k != 'admin') {
          if (!committees.any((x) => x.trim().toLowerCase() == k)) {
            committees.add(c);
          }
        }
      }
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
          top: true,
          bottom: false,
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              await ctx.reloadUserContext?.call();
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16 + MediaQuery.paddingOf(context).top,
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
      );
    }

    return DefaultTabController(
      length: committees.length,
      child: Scaffold(
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
                    isScrollable: committees.length > 2,
                    tabAlignment: TabAlignment.center,
                    dividerColor: Colors.transparent,
                    indicator: BoxDecoration(
                      color: AppColors.darkBlue,
                      borderRadius: BorderRadius.circular(AppColors.cardRadius),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    tabs: committees
                        .map((c) => Tab(text: _formatTabLabel(c)))
                        .toList(),
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: committees.map((committeeKey) {
                    return _CommitteeContent(
                      committeeKey: committeeKey,
                      committeeName: _formatCommitteeName(committeeKey),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
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
              leading: const Icon(Icons.person_outline, color: AppColors.primary),
              title: const Text(
                'Gebruikersnamen wijzigen',
                style: TextStyle(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Wijzig gebruikersnamen van leden.',
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
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const InfoTab(),
                      ),
                    );
                  },
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
