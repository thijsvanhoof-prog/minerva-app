import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/tab_page_header.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:minerva_app/profiel/ouder_kind_koppel_page.dart';
import 'package:minerva_app/ui/notifications/notification_settings_page.dart';
import 'package:minerva_app/ui/notifications/notification_service.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';

class ProfielTab extends StatefulWidget {
  const ProfielTab({super.key});

  @override
  State<ProfielTab> createState() => _ProfielTabState();
}

class _ProfielTabState extends State<ProfielTab> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  bool _isGlobalAdmin = false;
  List<Map<String, dynamic>> _teamRoles = [];
  Map<int, String> _teamNamesById = const {};
  List<String> _committeesInProfiel = const [];
  /// Future voor gekoppelde ouders (kind ziet met wie die is gekoppeld). Bij refresh opnieuw inladen.
  Future<List<Map<String, dynamic>>>? _linkedParentsFuture;

  final Set<String> _processingLinkRequestIds = {};
  String? _unlinkingChildId;
  bool _savingDisplayName = false;

  /// Fase B: 0 = Mijn gegevens, 1..n = tab voor gekoppeld kind.
  int _selectedProfileTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _reload();
    _linkedParentsFuture = _loadLinkedParentsFuture();
  }

  Future<List<Map<String, dynamic>>> _loadLinkedParentsFuture() async {
    try {
      final rpc = await _client.rpc('get_my_linked_parent_profiles');
      final rows = (rpc as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      return rows
          .map((r) => {
                'profile_id': r['profile_id']?.toString(),
                'display_name': (r['display_name']?.toString() ?? '').trim(),
              })
          .where((m) =>
              m['profile_id'] != null && (m['profile_id'] as String).isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  String _shortError(Object e, {int max = 160}) {
    final s = e.toString().replaceAll('\n', ' ').trim();
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  Future<void> _reload() async {
    _safeSetState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        _safeSetState(() {
          _isGlobalAdmin = false;
          _teamRoles = [];
          _teamNamesById = const {};
          _committeesInProfiel = const [];
          _loading = false;
        });
        return;
      }

      // 1) Global admin check (RPC)
      final adminRes = await _client.rpc('is_global_admin');
      if (!mounted) return;
      final isAdmin = adminRes == true;

      // 2) Teamrollen ophalen
      final data = await _client
          .from('team_members')
          .select('team_id, role')
          .eq('profile_id', user.id);
      if (!mounted) return;

      final roles = List<Map<String, dynamic>>.from(data);
      for (final row in roles) {
        final raw = row['role']?.toString() ?? 'player';
        row['role'] = _normalizeRole(raw);
      }

      // 2b) Teamnamen ophalen (best-effort)
      final teamIds = roles
          .map((r) => (r['team_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList()
        ..sort();

      Map<int, String> teamNamesById = await _loadTeamNames(teamIds: teamIds);
      if (teamNamesById.isEmpty && teamIds.isNotEmpty) {
        try {
          final rpc = await _client.rpc(
            'get_team_names_for_app',
            params: {'p_team_ids': teamIds},
          );
          final rows = (rpc as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
          final map = <int, String>{};
          for (final r in rows) {
            final tid = (r['team_id'] as num?)?.toInt();
            if (tid != null) {
              map[tid] = ((r['team_name'] as String?) ?? '').trim();
            }
          }
          teamNamesById = map;
        } catch (_) {}
      }
      if (!mounted) return;

      // Commissies uit Supabase (RPC voorkomt RLS-blokkade), anders directe select als fallback
      List<String> committeesInProfiel = const [];
      try {
        final rpc = await _client.rpc('get_my_committees');
        final rows = (rpc as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        final set = <String>{};
        for (final row in rows) {
          final raw = row['committee_name']?.toString() ?? '';
          final n = _normalizeCommitteeName(raw);
          if (n.isNotEmpty) set.add(n);
        }
        committeesInProfiel = set.toList()..sort((a, b) => _formatCommitteeName(a).compareTo(_formatCommitteeName(b)));
      } catch (_) {
        try {
          final cmRes = await _client
              .from('committee_members')
              .select('committee_name')
              .eq('profile_id', user.id);
          final cmRows = (cmRes as List<dynamic>).cast<Map<String, dynamic>>();
          final set = <String>{};
          for (final row in cmRows) {
            final raw = row['committee_name']?.toString() ?? '';
            final n = _normalizeCommitteeName(raw);
            if (n.isNotEmpty) set.add(n);
          }
          committeesInProfiel = set.toList()..sort();
        } catch (_) {}
      }
      if (!mounted) return;

      // Bij vernieuwen ook gekoppelde ouders opnieuw laden (voor kind-weergave)
      _linkedParentsFuture = _loadLinkedParentsFuture();

      // Sorteer teams volgens app-volgorde (DS -> HS -> XR -> MA -> JA -> MB -> JB -> MC -> JC ...)
      roles.sort((a, b) {
        final ai = (a['team_id'] as num?)?.toInt() ?? 0;
        final bi = (b['team_id'] as num?)?.toInt() ?? 0;
        final an = (teamNamesById[ai] ?? '').trim();
        final bn = (teamNamesById[bi] ?? '').trim();
        return NevoboApi.compareTeamNames(
          an.isEmpty ? '(naam ontbreekt)' : an,
          bn.isEmpty ? '(naam ontbreekt)' : bn,
          volleystarsLast: true,
        );
      });

      _safeSetState(() {
        _isGlobalAdmin = isAdmin;
        _teamRoles = roles;
        _teamNamesById = teamNamesById;
        _committeesInProfiel = committeesInProfiel;
        _loading = false;
      });
    } catch (e) {
      _safeSetState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _unlinkChild(
    BuildContext context,
    OuderKindNotifier notifier,
    String childId,
  ) async {
    _safeSetState(() => _unlinkingChildId = childId);
    try {
      await _client.rpc(
        'unlink_child_account',
        params: {'child_profile_id': childId},
      );
      final res = await _client.rpc('get_my_linked_child_profiles');
      final list = (res as List<dynamic>?)
              ?.map((e) {
                final m = e as Map<String, dynamic>?;
                if (m == null) return null;
                final id = m['profile_id']?.toString();
                final name = m['display_name']?.toString().trim() ?? '';
                if (id == null || id.isEmpty) return null;
                return LinkedChild(
                  profileId: id,
                  displayName: name.trim().isEmpty ? 'Gekoppeld account' : name,
                );
              })
              .whereType<LinkedChild>()
              .toList() ??
          const [];
      notifier.setChildren(list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_shortError(e))),
        );
      }
    } finally {
      _safeSetState(() => _unlinkingChildId = null);
    }
  }

  Future<void> _signOut() async {
    NotificationService.logout();
    await _client.auth.signOut();
  }

  String _editableDisplayName(String displayName) {
    // Strip the optional suffix added in UserAppBootstrap:
    // "Naam (ouder/verzorger 'X')"
    final s = displayName.trim();
    final i = s.indexOf(" (ouder/verzorger '");
    if (i > 0) return s.substring(0, i).trim();
    return s;
  }

  Future<void> _changeMyDisplayNameFlow() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final ctx = AppUserContext.of(context);
    final current = _editableDisplayName(ctx.displayName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _EditDisplayNameDialog(initialValue: current),
    );

    if (newName == null) return;
    if (!mounted) return;
    if (newName.trim().isEmpty) {
      showTopMessage(context, 'Vul een gebruikersnaam in.', isError: true);
      return;
    }

    _safeSetState(() => _savingDisplayName = true);
    try {
      // 1) Update auth metadata (immediate + works even if profiles RLS is strict).
      await _client.auth.updateUser(
        UserAttributes(data: {'display_name': newName}),
      );

      // 2) Best-effort: also persist in profiles for consistency.
      try {
        await _client.from('profiles').upsert({
          'id': user.id,
          'display_name': newName,
          'email': user.email ?? '',
        });
      } catch (_) {
        // ignore (RLS or schema differences)
      }

      if (!mounted) return;
      showTopMessage(context, 'Gebruikersnaam is bijgewerkt.');
      await _reload();
    } on AuthException catch (e) {
      if (!mounted) return;
      showTopMessage(context, e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Kon gebruikersnaam niet wijzigen: $e', isError: true);
    } finally {
      if (mounted) _safeSetState(() => _savingDisplayName = false);
    }
  }

  String _normalizeRole(String value) {
    final r = value.trim().toLowerCase();
    switch (r) {
      case 'trainer':
      case 'coach':
        return 'trainer';
      case 'trainingslid':
        return 'trainingslid';
      case 'speler':
      case 'player':
      default:
        return 'player';
    }
  }

  bool get _isTrainerOrCoach {
    return _teamRoles.any((row) {
      final r = (row['role']?.toString() ?? '').toLowerCase();
      return r == 'trainer' || r == 'coach';
    });
  }

  String _normalizeCommitteeName(String value) {
    final c = value.trim().toLowerCase();
    if (c.isEmpty) return '';
    if (c == 'bestuur') return 'bestuur';
    if (c == 'tc' || c.contains('technische')) return 'technische-commissie';
    if (c == 'cc' || c.contains('communicatie')) return 'communicatie';
    if (c == 'wz' || c.contains('wedstrijd')) return 'wedstrijdzaken';
    return c;
  }

  String _formatCommitteeName(String key) {
    final k = key.trim();
    if (k.isEmpty) return key;
    switch (k.toLowerCase()) {
      case 'bestuur':
        return 'Bestuur';
      case 'technische-commissie':
        return 'Technische commissie';
      case 'communicatie':
        return 'Communicatie';
      case 'wedstrijdzaken':
        return 'Wedstrijdzaken';
      case 'jeugd':
        return 'Jeugdcommissie';
      default:
        return '${k[0].toUpperCase()}${k.substring(1).replaceAll('-', ' ')}';
    }
  }

  /// Commissies uit context én lokaal geladen samenvoegen (zodat ze altijd zichtbaar zijn).
  List<String> _mergedCommittees(AppUserContext ctx) {
    final seen = <String>{};
    final list = <String>[];
    for (final c in [...ctx.committees, ..._committeesInProfiel]) {
      final n = _normalizeCommitteeName(c);
      if (n.isNotEmpty && seen.add(n)) list.add(c);
    }
    list.sort((a, b) => _formatCommitteeName(a).compareTo(_formatCommitteeName(b)));
    return list;
  }

  List<String> _buildRoleLabels(AppUserContext ctx) {
    final roles = <String>[];

    final isPlayer = _teamRoles.any((row) {
      final r = (row['role']?.toString() ?? '').toLowerCase();
      return r == 'player' || r == 'speler';
    });
    final isTrainingslid = _teamRoles.any((row) {
      final r = (row['role']?.toString() ?? '').toLowerCase();
      return r == 'trainingslid';
    });
    final isOuder = ctx.isOuderVerzorger || ctx.memberships.any((m) => m.isGuardian);
    final isTrainer = _isTrainerOrCoach || ctx.memberships.any((m) => m.canManageTeam);

    // Keep order: eerst teamrollen, dan commissies.
    if (isPlayer) roles.add('Speler');
    if (isTrainingslid) roles.add('Trainingslid');
    if (isOuder) roles.add('Ouder');
    if (isTrainer) roles.add('Trainer/coach');
    if (ctx.isInBestuur) roles.add('Bestuurslid');
    if (ctx.isInTechnischeCommissie) roles.add('TC lid');
    if (ctx.isInCommunicatie) roles.add('Communicatie lid');
    if (ctx.isInWedstrijdzaken) roles.add('Wedstrijdzaken lid');
    if (_isGlobalAdmin || ctx.hasFullAdminRights) roles.add('Algemeen admin');

    // Geen enkele rol → toeschouwer (alleen Uitgelicht, Agenda, Nieuws, Standen, Contact, Profiel)
    if (roles.isEmpty) roles.add('Toeschouwer');

    // De-duplicate while preserving order.
    final seen = <String>{};
    return roles.where((r) => seen.add(r)).toList();
  }

  String _roleLabel(String role) {
    switch (role.trim().toLowerCase()) {
      case 'trainer':
      case 'coach':
        return 'Trainer/coach';
      case 'trainingslid':
        return 'Trainingslid';
      case 'player':
      default:
        return 'Speler';
    }
  }

  Future<Map<int, String>> _loadTeamNames({required List<int> teamIds}) async {
    if (teamIds.isEmpty) return {};

    // We don't know your exact column names, so we try a few common options.
    // Each attempt selects only one candidate name column, so it won't fail if others don't exist.
    final candidates = <String>[
      'team_name',
      'name',
      'short_name',
      'code',
      'team_code',
      'abbreviation',
    ];

    // Prefer teams.team_id, but fall back to teams.id.
    final idFields = <String>['team_id', 'id'];

    for (final idField in idFields) {
      for (final nameField in candidates) {
        try {
          final List<dynamic> tRows = await _client
              .from('teams')
              .select('$idField, $nameField')
              .inFilter(idField, teamIds);

          final map = <int, String>{};
          for (final row in tRows) {
            final t = row as Map<String, dynamic>;
            final tid = (t[idField] as num?)?.toInt();
            if (tid == null) continue;
            final name = (t[nameField] as String?) ?? '';
            map[tid] = name;
          }

          final hasAny = map.values.any((v) => v.trim().isNotEmpty);
          if (hasAny) return map;
        } catch (_) {
          // Try next combination.
        }
      }
    }

    return {};
  }

  String _teamLabel(dynamic teamIdValue) {
    final teamId = (teamIdValue as num?)?.toInt();
    if (teamId == null) return 'Team';
    final raw = (_teamNamesById[teamId] ?? '').trim();
    final pretty = _teamAbbreviation(raw);
    if (pretty.isNotEmpty) return NevoboApi.displayTeamName(pretty);
    return '(naam ontbreekt)';
  }

  bool _showOuderKindSection(BuildContext context) {
    try {
      final ctx = AppUserContext.of(context);
      return ctx.ouderKindNotifier != null;
    } catch (_) {
      return false;
    }
  }

  Widget _buildOuderKindCard(BuildContext context) {
    final ctx = AppUserContext.of(context);
    final notifier = ctx.ouderKindNotifier;
    if (notifier == null) return const SizedBox.shrink();

    Future<List<Map<String, dynamic>>> loadRequests() async {
      try {
        final res = await _client.rpc('get_my_pending_account_link_requests');
        return (res as List<dynamic>).cast<Map<String, dynamic>>();
      } catch (_) {
        return const [];
      }
    }

    Future<void> acceptRequest(String requestId) async {
      await _client.rpc('accept_account_link_request', params: {'request_id': requestId});
      // Best-effort: refresh linked list in the app context.
      try {
        final res = await _client.rpc('get_my_linked_child_profiles');
        final list = (res as List<dynamic>?)
                ?.map((e) {
                  final m = e as Map<String, dynamic>?;
                  if (m == null) return null;
                  final id = m['profile_id']?.toString();
                  final name = m['display_name']?.toString().trim() ?? '';
                  if (id == null || id.isEmpty) return null;
                  return LinkedChild(profileId: id, displayName: name.trim().isEmpty ? 'Gekoppeld account' : name);
                })
                .whereType<LinkedChild>()
                .toList() ??
            const [];
        notifier.setChildren(list);
      } catch (_) {}
    }

    Future<void> rejectRequest(String requestId) async {
      await _client.rpc('reject_account_link_request', params: {'request_id': requestId});
    }

    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: const Text(
              'Gekoppelde accounts',
              style: TextStyle(
                color: AppColors.onBackground,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              'Wat kan wel: elkaars trainingen en wedstrijden bekijken, aanwezigheid voor een gekoppeld kind invullen. '
              'Wat kan niet: wachtwoorden of e-mail van anderen wijzigen.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: loadRequests(),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const [];
              if (rows.isEmpty) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    const Text(
                      'Koppelingsverzoeken',
                      style: TextStyle(
                        color: AppColors.onBackground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...rows.map((r) {
                      final requestId = (r['request_id'] ?? '').toString();
                      final otherName = (r['other_display_name'] ?? '').toString().trim();
                      final role = (r['role'] ?? '').toString();
                      final subtitle = role == 'parent'
                          ? 'Deze koppeling maakt jou ouder/verzorger.'
                          : role == 'child'
                              ? 'Deze koppeling maakt het andere account ouder/verzorger.'
                              : 'Koppelingsverzoek';
                      final isBusy = requestId.isNotEmpty && _processingLinkRequestIds.contains(requestId);

                      return GlassCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    otherName.isNotEmpty ? otherName : 'Account',
                                    style: const TextStyle(
                                      color: AppColors.onBackground,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: requestId.isEmpty
                                  ? null
                                  : isBusy
                                      ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(context);
                                      try {
                                        setState(() => _processingLinkRequestIds.add(requestId));
                                        await rejectRequest(requestId);
                                        if (!mounted) return;
                                        showTopMessage(messenger.context, 'Verzoek geweigerd.');
                                        setState(() => _processingLinkRequestIds.remove(requestId));
                                      } catch (e) {
                                        if (!mounted) return;
                                        showTopMessage(messenger.context, 'Weigeren mislukt: $e', isError: true);
                                        setState(() => _processingLinkRequestIds.remove(requestId));
                                      }
                                    },
                              child: isBusy
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Weigeren'),
                            ),
                            const SizedBox(width: 4),
                            ElevatedButton(
                              onPressed: requestId.isEmpty
                                  ? null
                                  : isBusy
                                      ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(context);
                                      try {
                                        setState(() => _processingLinkRequestIds.add(requestId));
                                        await acceptRequest(requestId);
                                        if (!mounted) return;
                                        showTopMessage(messenger.context, 'Verzoek geaccepteerd.');
                                        setState(() => _processingLinkRequestIds.remove(requestId));
                                      } catch (e) {
                                        if (!mounted) return;
                                        showTopMessage(messenger.context, 'Accepteren mislukt: $e', isError: true);
                                        setState(() => _processingLinkRequestIds.remove(requestId));
                                      }
                                    },
                              child: isBusy
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Accepteren'),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
          // Render this part from the notifier so UI updates immediately after unlink/link.
          AnimatedBuilder(
            animation: notifier,
            builder: (context, _) {
              final linked = notifier.linkedChildren;
              final widgets = <Widget>[];

              // Per gekoppeld kind: naam + ontkoppelknop (ouder kan altijd ontkoppelen).
              for (final c in linked) {
                final childId = c.profileId;
                final childName = c.displayName;
                final isUnlinkingThis = _unlinkingChildId == childId;
                widgets.add(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline, color: AppColors.iconMuted, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            childName,
                            style: const TextStyle(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _unlinkingChildId != null ? null
                              : () => _unlinkChild(context, notifier, childId),
                          icon: isUnlinkingThis
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.link_off, size: 20),
                          label: Text(
                            isUnlinkingThis ? '…' : 'Ontkoppelen',
                            style: const TextStyle(color: AppColors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Als kind: toon met wie je bent gekoppeld (geen ontkoppelknop; alleen ouder kan ontkoppelen).
              widgets.add(
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _linkedParentsFuture,
                  builder: (context, snapshot) {
                    final parents = snapshot.data ?? const <Map<String, dynamic>>[];
                    if (parents.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            'Je bent gekoppeld aan',
                            style: TextStyle(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        ...parents.map((p) {
                          final name = (p['display_name'] as String? ?? '').trim();
                          final displayName = name.isEmpty ? 'Gekoppeld account' : name;
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                            child: Row(
                              children: [
                                Icon(Icons.person_outline, color: AppColors.iconMuted, size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: AppColors.onBackground,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                          child: Text(
                            'Je bent gekoppeld aan bovenstaande ouder(s)/verzorger(s). Alleen zij kunnen de koppeling verbreken.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );

              // Altijd tonen: nog een account koppelen (zodat je meerdere kinderen kunt toevoegen).
              widgets.add(
                ListTile(
                  dense: true,
                  leading:
                      const Icon(Icons.person_add_outlined, color: AppColors.iconMuted),
                  title: const Text(
                    'Account koppelen',
                    style: TextStyle(
                      color: AppColors.onBackground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    linked.isEmpty
                        ? 'Start een koppeling. In de app genereer je een code of voer je de code van de ander in.'
                        : 'Nog een account toevoegen.',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const OuderKindKoppelPage(),
                      ),
                    );
                  },
                ),
              );

              return Column(children: widgets);
            },
          ),
        ],
      ),
    );
  }

  /// Teams van dit gekoppelde kind (memberships met linkedChildDisplayName = kind).
  List<TeamMembership> _teamsForChild(LinkedChild child, AppUserContext ctx) {
    final name = child.displayName.trim();
    return ctx.memberships
        .where((m) => m.linkedChildDisplayName?.trim() == name)
        .toList();
  }

  /// Inhoud van een kind-tab: teams van dat kind + uitleg over aanwezigheid/agenda.
  List<Widget> _buildKindTabContent(LinkedChild child, AppUserContext ctx) {
    final teams = _teamsForChild(child, ctx);
    final name = child.displayName.trim().isEmpty ? 'Gekoppeld kind' : child.displayName.trim();
    return [
      GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Teams van $name',
              style: const TextStyle(
                color: AppColors.onBackground,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            if (teams.isEmpty)
              const Text(
                'Geen teams gekoppeld voor dit kind.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else
              ...teams.map((m) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.groups_outlined, color: AppColors.iconMuted),
                    title: Text(
                      m.displayLabel,
                      style: const TextStyle(
                        color: AppColors.onBackground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Rol: ${m.role == 'guardian' ? 'Ouder/verzorger' : _roleLabel(m.role)}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  )),
          ],
        ),
      ),
      const SizedBox(height: 12),
      GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aanwezigheid en aanmeldingen',
              style: TextStyle(
                color: AppColors.onBackground,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Aanwezigheid voor trainingen en wedstrijden van $name regel je in de tab Teams (Trainingen en Wedstrijden). Aanmeldingen voor activiteiten kun je doen op Home bij Agenda.',
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    ];
  }

  String _teamAbbreviation(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';

    // If it's already a compact code like "Hs1", "Ds2", "Jb1", "Mb1", keep it.
    final compact = s.replaceAll(' ', '');
    final lower = compact.toLowerCase();
    final codeMatch = RegExp(r'^(hs|ds|jb|mb)\d+$').firstMatch(lower);
    if (codeMatch != null) {
      // Capitalize first letter only: hs1 -> Hs1
      return '${lower[0].toUpperCase()}${lower.substring(1)}';
    }

    // Try to derive from common full names.
    final normalized = s.toLowerCase();
    final number = RegExp(r'(\d+)').firstMatch(normalized)?.group(1);

    if (normalized.contains('heren')) {
      return number != null ? 'Hs$number' : 'Hs';
    }
    if (normalized.contains('dames')) {
      return number != null ? 'Ds$number' : 'Ds';
    }

    // Youth/minis: detect letter (A/B/C/D etc) + number.
    final group = RegExp(r'\b([a-d])\s*([0-9]+)\b').firstMatch(normalized);
    final letter = group?.group(1);
    final gnum = group?.group(2);

    if (normalized.contains('jongens')) {
      if (letter != null && gnum != null) {
        return 'J$letter$gnum'.replaceAll(' ', '');
      }
      return 'J';
    }
    if (normalized.contains('meis') || normalized.contains('mini')) {
      if (letter != null && gnum != null) {
        return 'M$letter$gnum'.replaceAll(' ', '');
      }
      return 'M';
    }

    // Fallback: return the original team name.
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final user = _client.auth.currentUser;
    final email = user?.email ?? 'Onbekend';
    final ctx = AppUserContext.of(context);
    final displayName = ctx.displayName.trim().isNotEmpty ? ctx.displayName.trim() : (user?.email ?? 'Onbekend');
    final roleLabels = _buildRoleLabels(ctx);

    final linkedChildren = ctx.linkedChildProfiles;
    final padding = EdgeInsets.fromLTRB(
      16,
      16,
      16,
      16 + MediaQuery.paddingOf(context).bottom,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            TabPageHeader(
              child: Text(
                'Profiel',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            if (linkedChildren.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _profileTabChip(
                        context,
                        label: 'Mijn gegevens',
                        selected: _selectedProfileTabIndex == 0,
                        onTap: () => setState(() => _selectedProfileTabIndex = 0),
                      ),
                      const SizedBox(width: 8),
                      ...linkedChildren.asMap().entries.map((e) {
                        final idx = e.key + 1;
                        final child = e.value;
                        final name = child.displayName.trim().isEmpty ? 'Kind' : child.displayName.trim();
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _profileTabChip(
                            context,
                            label: name,
                            selected: _selectedProfileTabIndex == idx,
                            onTap: () => setState(() => _selectedProfileTabIndex = idx),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _reload,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: padding,
                  children: (linkedChildren.isNotEmpty && _selectedProfileTabIndex > 0)
                      ? _buildKindTabContent(
                          linkedChildren[_selectedProfileTabIndex - 1],
                          ctx,
                        )
                      : _buildMijnGegevensList(context, displayName, email, roleLabels, ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMijnGegevensList(
    BuildContext context,
    String displayName,
    String email,
    List<String> roleLabels,
    AppUserContext ctx,
  ) {
    if (_loading) {
      return [
        const SizedBox(
          height: 300,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      ];
    }
    if (_error != null) {
      return [
        const SizedBox(height: 120),
        Text(
          'Fout: $_error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.error),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.background,
          ),
          onPressed: _reload,
          child: const Text('Opnieuw proberen'),
        ),
      ];
    }
    return [
                    GlassCard(
                      child: ListTile(
                        title: const Text(
                          'Ingelogd als',
                          style: TextStyle(
                            color: AppColors.onBackground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          displayName,
                          style: const TextStyle(color: AppColors.onBackground),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    GlassCard(
                      child: ListTile(
                        leading: const Icon(Icons.edit_outlined, color: AppColors.iconMuted),
                        title: const Text(
                          'Gebruikersnaam wijzigen',
                          style: TextStyle(
                            color: AppColors.onBackground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Pas aan hoe anderen jou zien in de app.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        onTap: _savingDisplayName ? null : _changeMyDisplayNameFlow,
                        trailing: _savingDisplayName
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Rollen: toon alleen als de gebruiker minstens één rol heeft.
                    if (roleLabels.isNotEmpty) ...[
                      GlassCard(
                        child: ListTile(
                          leading: Icon(
                            roleLabels.contains('Algemeen admin')
                                ? Icons.verified
                                : Icons.person_outline,
                            color: roleLabels.contains('Algemeen admin')
                                ? AppColors.primary
                                : AppColors.iconMuted,
                          ),
                          title: const Text(
                            'Rollen',
                            style: TextStyle(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            roleLabels.join(' • '),
                            style: const TextStyle(color: AppColors.onBackground),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Teams, rollen & commissies in één kaart
                    GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text(
                              'Teams, rollen & commissies',
                              style: TextStyle(
                                color: AppColors.onBackground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_teamRoles.isEmpty && _mergedCommittees(ctx).isEmpty)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Text(
                                'Geen teams of commissies gevonden voor dit account.',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          else
                            ...[
                              ..._teamRoles.map((row) {
                                final teamId = row['team_id'];
                                final role = row['role']?.toString() ?? 'player';
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.groups_outlined,
                                    color: AppColors.iconMuted,
                                  ),
                                  title: Text(
                                    _teamLabel(teamId),
                                    style: const TextStyle(
                                      color: AppColors.onBackground,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Rol: ${_roleLabel(role)}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                );
                              }),
                              ..._mergedCommittees(ctx).map((slug) => ListTile(
                                        dense: true,
                                        leading: const Icon(
                                          Icons.badge_outlined,
                                          color: AppColors.iconMuted,
                                        ),
                                        title: Text(
                                          _formatCommitteeName(slug),
                                          style: const TextStyle(
                                            color: AppColors.onBackground,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: const Text(
                                          'Commissie',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      )),
                            ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Ouder-kind account: wissel naar kind of terug naar eigen account
                    if (_showOuderKindSection(context)) ...[
                      _buildOuderKindCard(context),
                      const SizedBox(height: 12),
                    ],

                    GlassCard(
                      child: ListTile(
                        leading: const Icon(
                          Icons.notifications_outlined,
                          color: AppColors.iconMuted,
                        ),
                        title: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Notificaties',
                                style: TextStyle(
                                  color: AppColors.onBackground,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Tooltip(
                              message: 'Agenda: bij nieuwe of gewijzigde agenda-items. '
                                  'Nieuws: bij nieuwe berichten. Uitgelicht: bij nieuwe uitgelichte items. '
                                  'Stand: bij wijziging van de stand. Trainingen: bij nieuwe of gewijzigde trainingen.',
                              child: GestureDetector(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Wanneer krijg je notificaties?'),
                                      content: const SingleChildScrollView(
                                        child: Text(
                                          '• Agenda: bij nieuwe of gewijzigde agenda-items\n'
                                          '• Nieuws: bij nieuwe berichten op de homepagina\n'
                                          '• Uitgelicht: bij nieuwe uitgelichte items\n'
                                          '• Stand: bij wijziging van de stand van je team\n'
                                          '• Trainingen: bij nieuwe of gewijzigde trainingen',
                                          style: TextStyle(color: AppColors.onBackground),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('Ok'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: const Icon(
                                  Icons.info_outline,
                                  size: 20,
                                  color: AppColors.iconMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: const Text(
                          'Kies waar je meldingen van wilt krijgen.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const NotificationSettingsPage(),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Email wijzigen
                    GlassCard(
                      child: ListTile(
                        leading: const Icon(
                          Icons.email_outlined,
                          color: AppColors.iconMuted,
                        ),
                        title: const Text(
                          'E-mail wijzigen',
                          style: TextStyle(
                            color: AppColors.onBackground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Er wordt altijd een bevestigingsmail gestuurd naar het nieuwe adres. Pas na bevestiging is de wijziging actief.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        onTap: () => _changeEmailFlow(currentEmail: email),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Account verwijderen
                    GlassCard(
                      child: ListTile(
                        leading: const Icon(
                          Icons.delete_outline,
                          color: AppColors.error,
                        ),
                        title: const Text(
                          'Account verwijderen',
                          style: TextStyle(
                            color: AppColors.onBackground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Verwijdert je account en logt je uit.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        onTap: _deleteAccountFlow,
                      ),
                    ),

                    const SizedBox(height: 12),

                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.background,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.logout),
                      label: const Text('Uitloggen'),
                      onPressed: _signOut,
                    ),
                  ];
  }

  Widget _profileTabChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.25) : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.primary : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  static bool _isValidEmail(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(trimmed);
  }

  Future<void> _changeEmailFlow({required String currentEmail}) async {
    final newEmail = await showDialog<String>(
      context: context,
      builder: (context) => _EditEmailDialog(hint: currentEmail),
    );

    if (!mounted) return;
    if (newEmail == null || newEmail.trim().isEmpty) return;

    final email = newEmail.trim();
    if (!_isValidEmail(email)) {
      showTopMessage(context, 'Vul een geldig e-mailadres in.', isError: true);
      return;
    }
    if (email == currentEmail) {
      showTopMessage(context, 'Dit is al je huidige e-mailadres.', isError: true);
      return;
    }

    try {
      await _client.auth.updateUser(
        UserAttributes(email: email),
      );
      if (!mounted) return;
      showTopMessage(context, 'E-mail wijziging gestart. Check je mail om te bevestigen.');
      await _reload();
    } on AuthException catch (e) {
      if (!mounted) return;
      showTopMessage(context, e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Kon e-mail niet wijzigen. Probeer het later opnieuw.', isError: true);
    }
  }

  Future<void> _deleteAccountFlow() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Account verwijderen'),
        content: const Text(
          'Weet je zeker dat je je account wilt verwijderen? Dit kan niet ongedaan gemaakt worden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      // Ensure we have a fresh access token before calling an Edge Function.
      // If the token is expired, the function will respond 401.
      try {
        await _client.auth.refreshSession();
      } catch (_) {
        // Best-effort; we'll handle errors from the function call below.
      }

      // Self-service deletion via SQL RPC (no Edge Function / service role needed).
      await _client.rpc('delete_my_account');
      if (!mounted) return;

      showTopMessage(context, 'Account verwijderd.');
      NotificationService.logout();
      await _client.auth.signOut();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final url = dotenv.env['SUPABASE_URL'] ?? '(onbekend)';

      showTopMessage(
        context,
        'Account verwijderen mislukt (${_shortError(e.message)}). SUPABASE_URL: $url',
        isError: true,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      showTopMessage(context, e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      final url = dotenv.env['SUPABASE_URL'] ?? '(onbekend)';
      showTopMessage(
        context,
        'Account verwijderen mislukt (${_shortError(e)}). Controleer dat SUPABASE_URL naar het juiste project wijst ($url).',
        isError: true,
      );
    }
  }
}

class _EditDisplayNameDialog extends StatefulWidget {
  final String initialValue;

  const _EditDisplayNameDialog({required this.initialValue});

  @override
  State<_EditDisplayNameDialog> createState() => _EditDisplayNameDialogState();
}

class _EditDisplayNameDialogState extends State<_EditDisplayNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gebruikersnaam wijzigen'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Nieuwe gebruikersnaam',
          hintText: 'Naam zoals anderen jou zien',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Annuleren'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Opslaan'),
        ),
      ],
    );
  }
}

class _EditEmailDialog extends StatefulWidget {
  final String hint;

  const _EditEmailDialog({required this.hint});

  @override
  State<_EditEmailDialog> createState() => _EditEmailDialogState();
}

class _EditEmailDialogState extends State<_EditEmailDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('E-mail wijzigen'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: 'Nieuw e-mailadres',
          hintText: widget.hint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Annuleren'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Opslaan'),
        ),
      ],
    );
  }
}