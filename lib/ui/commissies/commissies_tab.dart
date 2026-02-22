import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/tab_page_header.dart';
import 'package:minerva_app/ui/display_name_overrides.dart' show unknownUserName;
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
      case 'evenementen':
      case 'evenementen-commissie':
        return 'EV';
      case 'jeugd':
      case 'jeugdcommissie':
        return 'Jeugd';
      case 'scheidsrechters/tellers':
      case 'scheidsrechters-tellers':
        return 'S/T';
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
      case 'evenementen':
      case 'evenementen-commissie':
        return 'Evenementen commissie';
      case 'jeugd':
      case 'jeugdcommissie':
        return 'Jeugdcommissie';
      case 'scheidsrechters/tellers':
      case 'scheidsrechters-tellers':
        return 'Scheidsrechters/Tellers';
      case 'admin':
        return 'Admin';
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
      case 'evenementen':
      case 'evenementen-commissie':
        return 5;
      case 'jeugd':
      case 'jeugdcommissie':
        return 6;
      case 'scheidsrechters/tellers':
      case 'scheidsrechters-tellers':
        return 7;
      default:
        return 8;
    }
  }

  /// Of de gebruiker deze commissie mag inzien/aanpassen: alleen eigen commissies, tenzij bestuur of admin.
  static bool _mayViewCommittee(AppUserContext ctx, String committeeKey) {
    if (ctx.hasFullAdminRights || ctx.isInBestuur) return true;
    return ctx.isInCommittee(committeeKey);
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);
    // Alle mogelijke commissies (vaste set + eventueel uit context).
    final List<String> allPossible = [
      'bestuur',
      'technische-commissie',
      'communicatie',
      'wedstrijdzaken',
      'evenementen',
      'jeugdcommissie',
      'scheidsrechters-tellers',
    ];
    for (final c in ctx.committees) {
      final k = c.trim().toLowerCase();
      if (k != 'bestuur' && k != 'technische-commissie' && k != 'tc' &&
          k != 'wedstrijdzaken' && k != 'communicatie' &&
          k != 'evenementen' && k != 'evenementen-commissie' &&
          k != 'jeugd' && k != 'jeugdcommissie' &&
          k != 'scheidsrechters/tellers' && k != 'scheidsrechters-tellers' &&
          k != 'vrijwilligers' &&
          k != 'admin') {
        if (!allPossible.any((x) => x.trim().toLowerCase() == k)) {
          allPossible.add(c);
        }
      }
    }
    // Alleen commissies tonen waar de gebruiker in zit, tenzij bestuur of admin (die zien alles).
    final List<String> committees = allPossible
        .where((c) => _mayViewCommittee(ctx, c))
        .toList();
    // Admin-tab alleen voor globale admins (gebruikersnamen wijzigen, accounts verwijderen).
    if (ctx.hasFullAdminRights && !committees.any((c) => c.trim().toLowerCase() == 'admin')) {
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
  bool _nevoboTableMissing = false;
  bool _schemaCheckDone = false;

  Future<void> _checkNevoboTable() async {
    if (_schemaCheckDone) return;
    _schemaCheckDone = true;
    try {
      await Supabase.instance.client
          .from('nevobo_home_matches')
          .select('match_key')
          .limit(1);
    } catch (_) {
      if (mounted) setState(() => _nevoboTableMissing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);
    if ((ctx.isInBestuur || ctx.hasFullAdminRights) && !_schemaCheckDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkNevoboTable());
    }
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
            if (_nevoboTableMissing) ...[
              Padding(
                padding: AppColors.tabContentPadding,
                child: GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Supabase tabel ontbreekt',
                          style: TextStyle(
                            color: AppColors.onBackground,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Run `supabase/nevobo_home_matches_schema.sql` in Supabase om koppelingen op te slaan (nodig voor Google Sheet sync).',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
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

    // Scheidsrechters/Tellers: alle wedstrijden met fluit/tel-aanmelding.
    if (key == 'scheidsrechters-tellers' || key == 'scheidsrechters/tellers') {
      return const MyTasksTab(stOverviewMode: true);
    }

    // Communicatie, Jeugd en Evenementen: aanmeldingen op activiteiten.
    if (key == 'communicatie' || key == 'jeugdcommissie' || key == 'evenementen') {
      return const _CommitteeAgendaRsvpsView();
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
                'Bekijk alle accounts, wijzig gebruikersnamen of voeg leden aan teams toe. Alleen voor admins.',
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

class _CommitteeAgendaRsvpsView extends StatefulWidget {
  const _CommitteeAgendaRsvpsView();

  @override
  State<_CommitteeAgendaRsvpsView> createState() => _CommitteeAgendaRsvpsViewState();
}

class _CommitteeAgendaRsvpsViewState extends State<_CommitteeAgendaRsvpsView> {
  final SupabaseClient _client = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _agendaRows = const [];
  Map<int, List<String>> _namesByAgendaId = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _formatDateTime(dynamic raw) {
    final dt = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (dt == null) return 'Datum onbekend';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}-${two(dt.month)}-${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final aRes = await _client
          .from('home_agenda')
          .select('agenda_id, title, start_datetime, event_date, event_time')
          .order('start_datetime', ascending: true);
      final agendaRows = (aRes as List<dynamic>).cast<Map<String, dynamic>>();

      final sRes = await _client
          .from('home_agenda_rsvps')
          .select('agenda_id, profile_id')
          .order('created_at', ascending: false);
      final signupRows = (sRes as List<dynamic>).cast<Map<String, dynamic>>();

      final profileIds = <String>{};
      for (final r in signupRows) {
        final pid = (r['profile_id'] ?? '').toString().trim();
        if (pid.isNotEmpty) profileIds.add(pid);
      }

      final namesByProfile = <String, String>{};
      if (profileIds.isNotEmpty) {
        try {
          final rpc = await _client.rpc(
            'get_profile_display_names',
            params: {'profile_ids': profileIds.toList()},
          );
          final rows = (rpc as List<dynamic>).cast<Map<String, dynamic>>();
          for (final row in rows) {
            final id = (row['profile_id'] ?? row['id'] ?? '').toString().trim();
            final name = (row['display_name'] ?? '').toString().trim();
            if (id.isNotEmpty) namesByProfile[id] = name.isEmpty ? unknownUserName : name;
          }
        } catch (_) {}
      }

      final byAgenda = <int, List<String>>{};
      for (final r in signupRows) {
        final agendaId = (r['agenda_id'] as num?)?.toInt();
        if (agendaId == null) continue;
        final pid = (r['profile_id'] ?? '').toString().trim();
        final name = namesByProfile[pid] ?? unknownUserName;
        byAgenda.putIfAbsent(agendaId, () => []).add(name);
      }
      for (final entry in byAgenda.entries) {
        entry.value.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      }

      if (!mounted) return;
      setState(() {
        _agendaRows = agendaRows;
        _namesByAgendaId = byAgenda;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, style: const TextStyle(color: AppColors.error)),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.paddingOf(context).bottom),
        itemCount: _agendaRows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final row = _agendaRows[index];
          final agendaId = (row['agenda_id'] as num?)?.toInt();
          final title = (row['title'] ?? 'Activiteit').toString();
          final startsAt = row['start_datetime'] ?? row['event_date'];
          final names = agendaId == null ? const <String>[] : (_namesByAgendaId[agendaId] ?? const <String>[]);
          return GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.onBackground,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateTime(startsAt),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${names.length} aanmelding(en)',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (names.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      names.join(', '),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
