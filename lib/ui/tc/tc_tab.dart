import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/display_name_overrides.dart' show applyDisplayNameOverrides, unknownUserName;
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
  /// Leden zonder team én zonder commissie (voor aparte lijst)
  List<_Member> _unassignedNoCommittee = const [];
  /// Alle profielen (voor "lid toevoegen aan team")
  List<_Member> _allMembers = const [];
  /// teamId -> lijst van (profileId, name, email?, role)
  Map<int, List<_AssignedMember>> _teamAssignments = const {};

  String _queryNoCommittee = '';
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

  /// Profile_ids die in minstens één commissie zitten (voor filter "zonder team én zonder commissie").
  Future<Set<String>> _loadCommitteeMemberProfileIds() async {
    try {
      final res = await _client.rpc('get_committee_member_profile_ids');
      final rows = (res as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      return rows
          .map((r) => r['profile_id']?.toString())
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  /// Haalt display names op voor een set profile_ids (RPC, werkt ook bij strikte RLS).
  Future<Map<String, String>> _loadDisplayNamesForProfileIds(Set<String> profileIds) async {
    if (profileIds.isEmpty) return {};
    try {
      final res = await _client.rpc(
        'get_profile_display_names',
        params: {'profile_ids': profileIds.toList()},
      );
      final rows = (res as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      final map = <String, String>{};
      for (final r in rows) {
        final id = r['profile_id']?.toString() ?? r['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final raw = (r['display_name'] ?? '').toString().trim();
        final name = applyDisplayNameOverrides(raw);
        map[id] = name.isNotEmpty ? name : unknownUserName;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// Haalt alle profielen op voor TC (RPC), zodat "leden zonder team" volledig is.
  Future<List<Map<String, dynamic>>> _loadProfilesForTc() async {
    List<Map<String, dynamic>> normalize(List<dynamic>? input) {
      final rows = input?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      return rows.map((r) {
        final id = (r['profile_id'] ?? r['id'])?.toString();
        final display = (r['display_name'] ?? r['full_name'] ?? r['name'] ?? '').toString();
        final email = (r['email'] ?? '').toString();
        return <String, dynamic>{
          'id': id,
          'display_name': display,
          'full_name': display,
          'name': display,
          'email': email,
        };
      }).where((r) => (r['id']?.toString().isNotEmpty ?? false)).toList();
    }

    // 1) Preferred RPC for TC
    try {
      final res = await _client.rpc('get_profiles_for_tc');
      final list = normalize(res as List<dynamic>?);
      if (list.isNotEmpty) return list;
    } catch (_) {}

    // 2) Fallback: admin/profile management RPCs (bestuur/TC/admin)
    for (final rpc in const [
      'admin_list_profiles',
      'list_profiles_for_committee_management',
    ]) {
      try {
        final res = await _client.rpc(rpc);
        final list = normalize(res as List<dynamic>?);
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }

    // 3) Last fallback: direct select (can be limited by RLS)
    for (final select in const [
      'id, display_name, full_name, email',
      'id, display_name, email',
      'id, full_name, email',
      'id, name, email',
      'id, email',
    ]) {
      try {
        final res = await _client.from('profiles').select(select);
        final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
        final list = rows.map((p) {
          final id = p['id']?.toString();
          final display =
              (p['display_name'] ?? p['full_name'] ?? p['name'] ?? '').toString();
          final email = (p['email'] ?? '').toString();
          return <String, dynamic>{
            'id': id,
            'display_name': display,
            'full_name': display,
            'name': display,
            'email': email,
          };
        }).where((r) => (r['id']?.toString().isNotEmpty ?? false)).toList();
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }

    return [];
  }

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
            _unassignedNoCommittee = const [];
            _allMembers = const [];
            _teamAssignments = const {};
            _loading = false;
          });
        }
        return;
      }

      final teams = await _fetchTeams();

      // Lijst profielen: eerst RPC (zodat TC alle accounts ziet voor "leden zonder team").
      List<Map<String, dynamic>> profiles = await _loadProfilesForTc();
      if (profiles.isEmpty) {
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
      }

      // Teammembers: team_id, profile_id, role
      final tmRes = await _client.from('team_members').select('team_id, profile_id, role');
      final tmRows = (tmRes as List<dynamic>).cast<Map<String, dynamic>>();
      final assigned = <String>{};
      final teamMemberProfileIds = <String>{};
      for (final row in tmRows) {
        final pid = row['profile_id']?.toString() ?? '';
        if (pid.isNotEmpty) teamMemberProfileIds.add(pid);
      }
      // Expliciet namen ophalen via RPC (werkt ook bij strikte RLS), zodat geen "Onbekend" voor teamleden.
      final displayNamesByProfileId = await _loadDisplayNamesForProfileIds(teamMemberProfileIds);

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
        final fromProfile = (pro?['display_name'] ?? pro?['full_name'] ?? pro?['name'] ?? '')
            .toString()
            .trim();
        final email = (pro?['email'] ?? '').toString().trim();
        final name = displayNamesByProfileId[pid]?.trim().isNotEmpty == true
            ? displayNamesByProfileId[pid]!
            : (fromProfile.isNotEmpty ? fromProfile : (email.isNotEmpty ? email : unknownUserName));
        final role = (row['role'] ?? 'player').toString().trim().toLowerCase();
        final normalizedRole = role == 'coach'
            ? 'trainer'
            : (role == 'trainer'
                ? 'trainer'
                : (role == 'trainingslid' ? 'trainingslid' : 'player'));
        teamAssignments.putIfAbsent(tid, () => []).add(
          _AssignedMember(
            profileId: pid,
            name: name,
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
            name: name.isNotEmpty ? name : (email.isNotEmpty ? email : unknownUserName),
            email: email.isNotEmpty ? email : null,
          ),
        );
      }

      unassigned.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      // Leden zonder team én zonder commissie: expliciet de set (alle profielen \ team \ commissie)
      final profileIdsInCommittee = await _loadCommitteeMemberProfileIds();
      final allProfileIds = profiles
          .map((p) => p['id']?.toString())
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet();
      final idsNoTeamNoCommittee = allProfileIds
          .where((id) => !assigned.contains(id) && !profileIdsInCommittee.contains(id))
          .toSet();
      final namesNoTeamNoCommittee = await _loadDisplayNamesForProfileIds(idsNoTeamNoCommittee);
      final unassignedNoCommittee = idsNoTeamNoCommittee.map((id) {
        final pro = profileById[id];
        final fromProfile = (pro?['display_name'] ?? pro?['full_name'] ?? pro?['name'] ?? '')
            .toString()
            .trim();
        final email = (pro?['email'] ?? '').toString().trim();
        final name = namesNoTeamNoCommittee[id]?.trim().isNotEmpty == true
            ? namesNoTeamNoCommittee[id]!
            : (fromProfile.isNotEmpty ? fromProfile : (email.isNotEmpty ? email : unknownUserName));
        return _Member(
          profileId: id,
          name: name,
          email: email.isNotEmpty ? email : null,
        );
      }).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

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
            name: name.isNotEmpty ? name : (email.isNotEmpty ? email : unknownUserName),
            email: email.isNotEmpty ? email : null,
          ),
        );
      }
      allMembers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (mounted) {
        setState(() {
          _teams = teams;
          _unassignedMembers = unassigned;
          _unassignedNoCommittee = unassignedNoCommittee;
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
    // Zorg dat Volleystars en Recreanten (niet competitie) bestaan (daarna in teamlijst).
    await _ensureTcTrainingGroups();

    // Alle teams inclusief teams die alleen trainen (training_only = true).
    try {
      final all = await NevoboApi.loadAllTeamsFromSupabase(
        client: _client,
        excludeTrainingOnly: false,
      );
      if (all.isNotEmpty) {
        final list = all
            .map((t) {
              final raw = t.name.trim();
              final lower = raw.toLowerCase();
              final label = lower == 'recreanten trainingsgroep'
                  ? 'Recreanten (niet competitie)'
                  : raw;
              return _TeamOption(t.teamId, label);
            })
            .toList()
          ..sort((a, b) => NevoboApi.compareTeamNames(a.label, b.label, volleystarsLast: true));
        return list;
      }
    } catch (_) {}

    const candidates = ['team_name', 'name', 'short_name', 'code', 'team_code', 'abbreviation'];
    const idFields = ['team_id', 'id'];
    for (final idField in idFields) {
      for (final nameField in candidates) {
        try {
          final selectCols = '$idField, $nameField, nevobo_code';
          List<Map<String, dynamic>> rows;
          try {
            final res = await _client.from('teams').select(selectCols);
            rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
          } catch (_) {
            final res = await _client.from('teams').select('$idField, $nameField');
            rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
          }
          final list = <_TeamOption>[];
          for (final row in rows) {
            final id = (row[idField] as num?)?.toInt();
            if (id == null) continue;
            final name = (row[nameField] as String?) ?? '';
            final nevoboCode = (row['nevobo_code'] as String?)?.trim();
            final label = name.trim().isNotEmpty
                ? name.trim()
                : (nevoboCode?.isNotEmpty == true ? nevoboCode! : '(naam ontbreekt)');
            list.add(_TeamOption(id, label));
          }
          if (list.isNotEmpty) {
            list.sort((a, b) => NevoboApi.compareTeamNames(a.label, b.label, volleystarsLast: true));
            return list;
          }
        } catch (_) {}
      }
    }
    return const [];
  }

  Future<void> _ensureTcTrainingGroups() async {
    // 1) Preferred: RPC (SECURITY DEFINER)
    try {
      await _client.rpc('ensure_training_groups_for_tc');
      return;
    } catch (_) {}

    // 2) Fallback: direct upsert (works when teams_tc_manage policy is active)
    try {
      await _client.from('teams').upsert(
        const [
          {'team_name': 'Volleystars', 'training_only': true},
          {'team_name': 'Recreanten (niet competitie)', 'training_only': true},
        ],
        onConflict: 'team_name',
      );
      return;
    } catch (_) {}

    // 3) Older schema fallback without training_only column
    try {
      await _client.from('teams').upsert(
        const [
          {'team_name': 'Volleystars'},
          {'team_name': 'Recreanten (niet competitie)'},
        ],
        onConflict: 'team_name',
      );
    } catch (_) {}
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
                      child: Text(NevoboApi.displayTeamName(t.label)),
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

  List<_Member> get _filteredMembersNoCommittee {
    final q = _queryNoCommittee.trim().toLowerCase();
    if (q.isEmpty) return _unassignedNoCommittee;
    return _unassignedNoCommittee.where((m) {
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
    final raw = _teams.where((t) => t.teamId == teamId).firstOrNull?.label ?? 'team';
    final teamLabel = NevoboApi.displayTeamName(raw);
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

  Future<void> _addTeam() async {
    final ctx = AppUserContext.of(context);
    if (!_canManage(ctx)) return;

    final result = await showDialog<_AddTeamResult>(
      context: context,
      builder: (context) => const _AddTeamDialog(),
    );

    if (result == null || !mounted) return;

    final teamName = result.teamName;
    final trainingOnly = result.trainingOnly;

    if (teamName.isEmpty) {
      showTopMessage(context, 'Vul een geldige teamnaam in.', isError: true);
      return;
    }

    try {
      final payload = <String, dynamic>{
        'team_name': teamName,
        'season': NevoboApi.currentSeason(),
      };
      if (trainingOnly) {
        payload['training_only'] = true;
      }
      await _client.from('teams').insert(payload);
      if (!mounted) return;
      showTopMessage(context, 'Team "$teamName" toegevoegd.');
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      if (e.code == '23505' || msg.contains('duplicate key')) {
        showTopMessage(
          context,
          'Dit team bestaat al voor dit seizoen.',
          isError: true,
        );
        return;
      }
      if (e.code == 'PGRST204' || msg.contains('team_name')) {
        try {
          final retry = <String, dynamic>{'name': teamName, 'season': NevoboApi.currentSeason()};
          if (trainingOnly) retry['training_only'] = true;
          await _client.from('teams').insert(retry);
          if (!mounted) return;
          showTopMessage(context, 'Team "$teamName" toegevoegd.');
          await _load();
        } catch (e2) {
          if (!mounted) return;
          if (e2 is PostgrestException &&
              ((e2.code == '23505') || e2.message.toLowerCase().contains('duplicate key'))) {
            showTopMessage(context, 'Dit team bestaat al voor dit seizoen.', isError: true);
          } else {
            showTopMessage(context, 'Toevoegen mislukt: $e2', isError: true);
          }
        }
      } else {
        showTopMessage(context, 'Toevoegen mislukt: $e', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      if (e.toString().toLowerCase().contains('duplicate key')) {
        showTopMessage(context, 'Dit team bestaat al voor dit seizoen.', isError: true);
      } else {
        showTopMessage(context, 'Toevoegen mislukt: $e', isError: true);
      }
    }
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
                          'Accounts zonder team én zonder commissie',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Deze accounts hebben nog geen team en zitten in geen commissie. Koppel ze aan een team om ze zichtbaar te maken.',
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(alpha: 0.9),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            labelText: 'Zoek in deze lijst',
                          ),
                          onChanged: (v) => setState(() => _queryNoCommittee = v),
                        ),
                        const SizedBox(height: 12),
                        if (_filteredMembersNoCommittee.isEmpty)
                          const GlassCard(
                            child: Padding(
                              padding: EdgeInsets.all(14),
                              child: Text(
                                'Geen accounts zonder team én zonder commissie.',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            ),
                          )
                        else
                          ..._filteredMembersNoCommittee.map((m) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GlassCard(
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.person_off_outlined,
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
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Teamindeling',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (canManage)
                              IconButton(
                                onPressed: _addTeam,
                                icon: const Icon(Icons.add_circle_outline),
                                color: AppColors.primary,
                                tooltip: 'Team toevoegen',
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Zie wie in welk team zit. Inclusief teams die alleen trainen (geen competitie). Tik op een lid om de rol te wijzigen of uit het team te halen.',
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
                                                  NevoboApi.displayTeamName(t.label),
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
                                        onTap: () => _addMemberToTeam(t.teamId, NevoboApi.displayTeamName(t.label)),
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

class _AddTeamResult {
  final String teamName;
  final bool trainingOnly;
  const _AddTeamResult({required this.teamName, required this.trainingOnly});
}

class _AddTeamDialog extends StatefulWidget {
  const _AddTeamDialog();

  @override
  State<_AddTeamDialog> createState() => _AddTeamDialogState();
}

class _AddTeamDialogState extends State<_AddTeamDialog> {
  static const _prefixOptions = [
    ('DS', 'DS (Dames)'),
    ('HS', 'HS (Heren)'),
    ('XR', 'XR (Recreanten/Mix)'),
    ('Recreanten (niet competitie)', 'Recreanten (niet competitie)'),
    ('MA', 'MA (Meiden A)'),
    ('MB', 'MB (Meiden B)'),
    ('MC', 'MC (Meiden C)'),
    ('JA', 'JA (Jongens A)'),
    ('JB', 'JB (Jongens B)'),
    ('JC', 'JC (Jongens C)'),
    ('Volleystars', 'Volleystars'),
  ];

  late String _selectedPrefix;
  late TextEditingController _numberController;
  bool _trainingOnly = false;
  bool _nevoboChecking = false;

  @override
  void initState() {
    super.initState();
    _selectedPrefix = _prefixOptions.first.$1;
    _numberController = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _koppelMetNevobo() async {
    final isNoNumber = _selectedPrefix == 'Volleystars' || _selectedPrefix == 'Recreanten (niet competitie)';
    final teamName = isNoNumber
        ? _selectedPrefix
        : '$_selectedPrefix${_numberController.text.trim().isEmpty ? "1" : _numberController.text.trim()}';

    if (isNoNumber) {
      showTopMessage(context, 'Dit team is geen Nevobo-competitieteam.', isError: true);
      return;
    }

    final team = NevoboApi.teamFromCode(teamName);
    if (team == null) {
      showTopMessage(context, 'Ongeldige teamcode.', isError: true);
      return;
    }

    setState(() => _nevoboChecking = true);
    try {
      await NevoboApi.fetchStandingsForTeam(team: team);
      if (!mounted) return;
      showTopMessage(context, 'Team $teamName gevonden bij Nevobo.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(
        context,
        'Het team is niet gevonden bij de Nevobo.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _nevoboChecking = false);
    }
  }

  bool get _isNoNumberOption =>
      _selectedPrefix == 'Volleystars' || _selectedPrefix == 'Recreanten (niet competitie)';

  @override
  Widget build(BuildContext context) {
    final teamName = _isNoNumberOption
        ? _selectedPrefix
        : '$_selectedPrefix${_numberController.text.trim().isEmpty ? "1" : _numberController.text.trim()}';

    return AlertDialog(
      title: const Text('Team toevoegen'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedPrefix,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Teamtype'),
                items: _prefixOptions
                    .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
                    .toList(),
                selectedItemBuilder: (context) => _prefixOptions
                    .map((o) => Text(
                          o.$2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedPrefix = v ?? _selectedPrefix),
              ),
            if (!_isNoNumberOption) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _numberController,
                decoration: const InputDecoration(
                  labelText: 'Nummer',
                  hintText: '1',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _nevoboChecking ? null : _koppelMetNevobo,
                  icon: _nevoboChecking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link, size: 18),
                  label: Text(_nevoboChecking ? 'Controleren…' : 'Koppel met Nevobo'),
                ),
              ),
            ],
            const SizedBox(height: 20),
            CheckboxListTile(
              value: _trainingOnly,
              onChanged: (v) => setState(() => _trainingOnly = v ?? false),
              title: const Text(
                'Trainingsteam',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Alleen trainingen, niet standen of wedstrijden',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuleren'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(
            _AddTeamResult(teamName: teamName, trainingOnly: _trainingOnly),
          ),
          child: const Text('Toevoegen'),
        ),
      ],
    );
  }
}

