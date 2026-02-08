import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_api.dart';

class TcTab extends StatefulWidget {
  const TcTab({super.key});

  @override
  State<TcTab> createState() => _TcTabState();
}

class _TcTabState extends State<TcTab> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<_TeamOption> _teams = const [];
  List<_Member> _unassignedMembers = const [];
  /// Alle profielen (voor "lid toevoegen aan team")
  List<_Member> _allMembers = const [];
  /// teamId -> lijst van (profileId, name, email?, role)
  Map<int, List<_AssignedMember>> _teamAssignments = const {};

  String _query = '';
  String _teamQuery = '';
  String? _lastProfileId;
  int? _expandedTeamId;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ctx = AppUserContext.of(context);
    if (_lastProfileId != ctx.profileId) {
      _lastProfileId = ctx.profileId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  /// Bestuur mag kijken, alleen admins en TC mogen bewerken.
  bool _canView(AppUserContext ctx) =>
      ctx.hasFullAdminRights || ctx.isInTechnischeCommissie || ctx.isInBestuur;
  bool _canManage(AppUserContext ctx) => ctx.canManageTc;

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final ctx = AppUserContext.of(context);
      if (!_canView(ctx)) {
        if (mounted) {
          setState(() {
            _teams = const [];
            _unassignedMembers = const [];
            _allMembers = const [];
            _teamAssignments = const {};
            _loading = false;
          });
        }
        return;
      }

      final teams = await _fetchTeams();

      // Load all profiles (best-effort: can be blocked by RLS).
      List<Map<String, dynamic>> profiles = const [];
      for (final select in const [
        'id, display_name, full_name, email',
        'id, display_name, email',
        'id, full_name, email',
        'id, name, email',
        'id, email',
      ]) {
        try {
          final res = await _client.from('profiles').select(select);
          profiles = (res as List<dynamic>).cast<Map<String, dynamic>>();
          break;
        } catch (_) {
          // try next
        }
      }

      // Teammembers: team_id, profile_id, role
      final tmRes = await _client.from('team_members').select('team_id, profile_id, role');
      final tmRows = (tmRes as List<dynamic>).cast<Map<String, dynamic>>();
      final assigned = <String>{};
      final teamAssignments = <int, List<_AssignedMember>>{};
      final profileById = <String, Map<String, dynamic>>{};
      for (final p in profiles) {
        final id = p['id']?.toString() ?? '';
        if (id.isNotEmpty) profileById[id] = p;
      }

      for (final row in tmRows) {
        final pid = row['profile_id']?.toString() ?? '';
        final tid = (row['team_id'] as num?)?.toInt();
        if (pid.isEmpty || tid == null) continue;
        assigned.add(pid);
        final pro = profileById[pid];
        final name = (pro?['display_name'] ?? pro?['full_name'] ?? pro?['name'] ?? '')
            .toString()
            .trim();
        final email = (pro?['email'] ?? '').toString().trim();
        final role = (row['role'] ?? 'player').toString().trim().toLowerCase();
        final normalizedRole = role == 'coach'
            ? 'trainer'
            : (role == 'trainer'
                ? 'trainer'
                : (role == 'trainingslid' ? 'trainingslid' : 'player'));
        teamAssignments.putIfAbsent(tid, () => []).add(
          _AssignedMember(
            profileId: pid,
            name: name.isNotEmpty ? name : (email.isNotEmpty ? email : _shortId(pid)),
            email: email.isNotEmpty ? email : null,
            role: normalizedRole,
          ),
        );
      }
      for (final list in teamAssignments.values) {
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }

      final unassigned = <_Member>[];
      for (final p in profiles) {
        final id = p['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (assigned.contains(id)) continue;

        final name =
            (p['display_name'] ?? p['full_name'] ?? p['name'] ?? '').toString().trim();
        final email = (p['email'] ?? '').toString().trim();
        unassigned.add(
          _Member(
            profileId: id,
            name: name.isNotEmpty ? name : (email.isNotEmpty ? email : _shortId(id)),
            email: email.isNotEmpty ? email : null,
          ),
        );
      }

      unassigned.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final allMembers = <_Member>[];
      for (final p in profiles) {
        final id = p['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final name =
            (p['display_name'] ?? p['full_name'] ?? p['name'] ?? '').toString().trim();
        final email = (p['email'] ?? '').toString().trim();
        allMembers.add(
          _Member(
            profileId: id,
            name: name.isNotEmpty ? name : (email.isNotEmpty ? email : _shortId(id)),
            email: email.isNotEmpty ? email : null,
          ),
        );
      }
      allMembers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (mounted) {
        setState(() {
          _teams = teams;
          _unassignedMembers = unassigned;
          _allMembers = allMembers;
          _teamAssignments = teamAssignments;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<List<_TeamOption>> _fetchTeams() async {
    final candidates = <String>[
      'team_name',
      'name',
      'short_name',
      'code',
      'team_code',
      'abbreviation',
    ];
    final idFields = <String>['team_id', 'id'];

    for (final idField in idFields) {
      for (final nameField in candidates) {
        try {
          final res = await _client.from('teams').select('$idField, $nameField');
          final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
          final list = <_TeamOption>[];
          for (final row in rows) {
            final id = (row[idField] as num?)?.toInt();
            if (id == null) continue;
            final name = (row[nameField] as String?) ?? '';
            final label = name.trim().isEmpty ? 'Team $id' : name.trim();
            list.add(_TeamOption(id, label));
          }
          if (list.isNotEmpty) {
            list.sort((a, b) => NevoboApi.compareTeamNames(a.label, b.label, volleystarsLast: true));
            return list;
          }
        } catch (_) {
          // try next
        }
      }
    }
    return const [];
  }

  Future<void> _assignMemberToTeam(_Member member) async {
    final ctx = AppUserContext.of(context);
    if (!_canView(ctx)) return;
    if (_teams.isEmpty) {
      showTopMessage(context, 'Geen teams gevonden.', isError: true);
      return;
    }

    var selectedTeamId = _teams.first.teamId;
    var selectedRole = 'player';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Koppelen aan team'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              member.name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (member.email != null) ...[
              const SizedBox(height: 4),
              Text(
                member.email!,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue: selectedTeamId,
              items: _teams
                  .map(
                    (t) => DropdownMenuItem<int>(
                      value: t.teamId,
                      child: Text(t.label),
                    ),
                  )
                  .toList(),
              onChanged: (v) => selectedTeamId = v ?? selectedTeamId,
              decoration: const InputDecoration(labelText: 'Team'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: selectedRole,
              items: const [
                DropdownMenuItem(value: 'player', child: Text('Speler')),
                DropdownMenuItem(value: 'trainer', child: Text('Trainer/coach')),
                DropdownMenuItem(value: 'trainingslid', child: Text('Trainingslid')),
              ],
              onChanged: (v) => selectedRole = v ?? selectedRole,
              decoration: const InputDecoration(labelText: 'Rol'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Koppelen'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      await _client.from('team_members').insert({
        'team_id': selectedTeamId,
        'profile_id': member.profileId,
        'role': selectedRole,
      });

      if (!mounted) return;
      setState(() {
        _unassignedMembers =
            _unassignedMembers.where((m) => m.profileId != member.profileId).toList();
      });
      showTopMessage(context, 'Lid gekoppeld aan team.');
      await _load(); // ensure in-app refresh reflects the change immediately
      // If the current user just got linked (or role changed), refresh user context
      // so Trainingen/Wedstrijden updates without requiring app restart.
      try {
        if (!mounted) return;
        await AppUserContext.of(context).reloadUserContext?.call();
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Koppelen mislukt: $e', isError: true);
    }
  }

  List<_Member> get _filteredMembers {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _unassignedMembers;
    return _unassignedMembers.where((m) {
      if (m.name.toLowerCase().contains(q)) return true;
      final email = m.email?.toLowerCase() ?? '';
      return email.contains(q);
    }).toList();
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'trainer':
        return 'Trainer/coach';
      case 'trainingslid':
        return 'Trainingslid';
      default:
        return 'Speler';
    }
  }

  Future<void> _addMemberToTeam(int teamId, String teamLabel) async {
    final alreadyInTeam = (_teamAssignments[teamId] ?? []).map((a) => a.profileId).toSet();
    final available = _allMembers.where((m) => !alreadyInTeam.contains(m.profileId)).toList();
    if (available.isEmpty) {
      showTopMessage(context, 'Alle leden zitten al in dit team.', isError: true);
      return;
    }
    var search = '';
    final chosen = await showDialog<_Member>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = search.trim().toLowerCase();
          final list = q.isEmpty
              ? available
              : available
                  .where((m) =>
                      m.name.toLowerCase().contains(q) ||
                      (m.email?.toLowerCase().contains(q) ?? false))
                  .toList();
          return AlertDialog(
            title: Text('Lid toevoegen aan $teamLabel'),
            content: SizedBox(
              width: double.maxFinite,
              height: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Zoek op naam of e-mail',
                    ),
                    onChanged: (v) => setDialogState(() => search = v),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: list.isEmpty
                        ? const Center(
                            child: Text(
                              'Geen leden gevonden.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (context, i) {
                              final m = list[i];
                              return ListTile(
                                dense: true,
                                title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: m.email != null ? Text(m.email!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)) : null,
                                onTap: () => Navigator.of(context).pop(m),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Annuleren'),
              ),
            ],
          );
        },
      ),
    );
    if (chosen == null) return;
    if (!mounted) return;
    var selectedRole = 'player';
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rol kiezen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(chosen.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (chosen.email != null) ...[
                const SizedBox(height: 4),
                Text(chosen.email!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                items: const [
                  DropdownMenuItem(value: 'player', child: Text('Speler')),
                  DropdownMenuItem(value: 'trainer', child: Text('Trainer/coach')),
                  DropdownMenuItem(value: 'trainingslid', child: Text('Trainingslid')),
                ],
                onChanged: (v) => setDialogState(() => selectedRole = v ?? selectedRole),
                decoration: const InputDecoration(labelText: 'Rol'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuleren'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Toevoegen'),
            ),
          ],
        ),
      ),
    );
    if (save != true) return;
    try {
      await _client.from('team_members').insert({
        'team_id': teamId,
        'profile_id': chosen.profileId,
        'role': selectedRole,
      });
      if (!mounted) return;
      showTopMessage(context, 'Lid toegevoegd aan team.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Toevoegen mislukt: $e', isError: true);
    }
  }

  Future<void> _editAssignment(int teamId, _AssignedMember member) async {
    final teamLabel = _teams.where((t) => t.teamId == teamId).firstOrNull?.label ?? 'team';
    var chosenRole = member.role;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Lid in $teamLabel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                member.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (member.email != null) ...[
                const SizedBox(height: 4),
                Text(
                  member.email!,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: chosenRole,
                items: const [
                  DropdownMenuItem(value: 'player', child: Text('Speler')),
                  DropdownMenuItem(value: 'trainer', child: Text('Trainer/coach')),
                  DropdownMenuItem(value: 'trainingslid', child: Text('Trainingslid')),
                ],
                onChanged: (v) => setDialogState(() => chosenRole = v ?? chosenRole),
                decoration: const InputDecoration(labelText: 'Rol'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('remove'),
              child: Text('Uit team halen', style: TextStyle(color: AppColors.error)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Annuleren'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(chosenRole),
              child: const Text('Opslaan'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    if (result == 'remove') {
      try {
        await _client.from('team_members').delete().eq('team_id', teamId).eq('profile_id', member.profileId);
        if (!mounted) return;
        showTopMessage(context, 'Lid uit team gehaald.');
        await _load();
      } catch (e) {
        if (!mounted) return;
        showTopMessage(context, 'Verwijderen mislukt: $e', isError: true);
      }
      return;
    }
    // result is the new role
    if (result != member.role) {
      try {
        await _client.from('team_members').update({'role': result}).eq('team_id', teamId).eq('profile_id', member.profileId);
        if (!mounted) return;
        showTopMessage(context, 'Rol bijgewerkt.');
        await _load();
      } catch (e) {
        if (!mounted) return;
        showTopMessage(context, 'Bijwerken mislukt: $e', isError: true);
      }
    }
  }

  static String _shortId(String value) {
    if (value.length <= 8) return value;
    return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppUserContext.of(context);
    final canView = _canView(ctx);
    final canManage = _canManage(ctx);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            16 + MediaQuery.paddingOf(context).top,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: !canView
              ? [
                  const SizedBox(
                    height: 200,
                    child: Center(
                      child: Text(
                        'Deze pagina is alleen voor de Technische Commissie.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                ]
              : _loading
                  ? [
                      const SizedBox(
                        height: 300,
                        child: Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        ),
                      ),
                    ]
                  : (_error != null)
                      ? [
                          const SizedBox(height: 80),
                          GlassCard(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: AppColors.darkBlue,
                                      borderRadius: BorderRadius.circular(AppColors.cardRadius),
                                    ),
                                    child: Text(
                                      'TC tab kon niet laden',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: AppColors.error),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Tip: controleer Supabase RLS voor `profiles` en `team_members`.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ]
                      : [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.darkBlue,
                            borderRadius: BorderRadius.circular(AppColors.cardRadius),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Teambeheer',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Bekijk alle teams, voeg leden toe aan een of meerdere teams, en pas rollen aan.',
                                style: TextStyle(
                                  color: AppColors.primary.withValues(alpha: 0.9),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Tip: Teambeheer werkt ook op de computer via de browser — dat is vaak makkelijker dan alles in de app te doen.',
                                style: TextStyle(
                                  color: AppColors.primary.withValues(alpha: 0.75),
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Leden zonder team',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            labelText: 'Zoek lid',
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                        const SizedBox(height: 12),
                        if (_filteredMembers.isEmpty)
                          const GlassCard(
                            child: Padding(
                              padding: EdgeInsets.all(14),
                              child: Text(
                                'Geen leden zonder team gevonden.',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            ),
                          )
                        else
                          ..._filteredMembers.map((m) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GlassCard(
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.person_outline,
                                    color: AppColors.iconMuted,
                                  ),
                                  title: Text(
                                    m.name,
                                    style: const TextStyle(
                                      color: AppColors.onBackground,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: m.email == null
                                      ? null
                                      : Text(
                                          m.email!,
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                  trailing: Icon(
                                    Icons.link,
                                    color: canManage ? AppColors.primary : AppColors.iconMuted,
                                  ),
                                  onTap: canManage ? () => _assignMemberToTeam(m) : null,
                                ),
                              ),
                            );
                          }),
                        const SizedBox(height: 24),
                        const Text(
                          'Teamindeling',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Zie wie in welk team zit. Tik op een lid om de rol te wijzigen of uit het team te halen.',
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(alpha: 0.9),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            labelText: 'Zoek in teamindeling',
                          ),
                          onChanged: (v) => setState(() => _teamQuery = v),
                        ),
                        const SizedBox(height: 12),
                        ..._teams.map((t) {
                          final members = _teamAssignments[t.teamId] ?? [];
                          final q = _teamQuery.trim().toLowerCase();
                          final teamLabelMatches = q.isEmpty || t.label.toLowerCase().contains(q);
                          final filtered = q.isEmpty
                              ? members
                              : members
                                  .where((m) =>
                                      m.name.toLowerCase().contains(q) ||
                                      (m.email?.toLowerCase().contains(q) ?? false))
                                  .toList();
                          final toShow = q.isEmpty
                              ? members
                              : (teamLabelMatches ? members : filtered);
                          if (q.isNotEmpty && toShow.isEmpty) return const SizedBox.shrink();
                          final expanded = _expandedTeamId == t.teamId;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GlassCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(AppColors.cardRadius),
                                    onTap: () {
                                      setState(() {
                                        _expandedTeamId = expanded ? null : t.teamId;
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  t.label,
                                                  style: const TextStyle(
                                                    color: AppColors.primary,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${toShow.length} lid/leden',
                                                  style: TextStyle(
                                                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            expanded ? Icons.expand_less : Icons.expand_more,
                                            color: AppColors.textSecondary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (expanded) ...[
                                    const Divider(height: 1),
                                    if (toShow.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                                        child: Text(
                                          'Geen leden in dit team.',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      )
                                    else
                                      ...toShow.map(
                                        (m) => ListTile(
                                          dense: true,
                                          leading: const Icon(
                                            Icons.person_outline,
                                            color: AppColors.iconMuted,
                                            size: 22,
                                          ),
                                          title: Text(
                                            m.name,
                                            style: const TextStyle(
                                              color: AppColors.onBackground,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          subtitle: Text(
                                            _roleLabel(m.role),
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                          trailing: Icon(
                                            Icons.edit_outlined,
                                            color: canManage ? AppColors.primary : AppColors.iconMuted,
                                            size: 20,
                                          ),
                                          onTap: canManage ? () => _editAssignment(t.teamId, m) : null,
                                        ),
                                      ),
                                    const Divider(height: 1),
                                    if (canManage)
                                      ListTile(
                                        dense: true,
                                        leading: const Icon(
                                          Icons.person_add_outlined,
                                          color: AppColors.primary,
                                          size: 22,
                                        ),
                                        title: const Text(
                                          'Lid toevoegen aan dit team',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        onTap: () => _addMemberToTeam(t.teamId, t.label),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                        ],
        ),
      ),
    );
  }
}

class _TeamOption {
  final int teamId;
  final String label;
  const _TeamOption(this.teamId, this.label);
}

class _Member {
  final String profileId;
  final String name;
  final String? email;

  const _Member({
    required this.profileId,
    required this.name,
    required this.email,
  });
}

class _AssignedMember {
  final String profileId;
  final String name;
  final String? email;
  final String role;

  const _AssignedMember({
    required this.profileId,
    required this.name,
    this.email,
    required this.role,
  });
}

