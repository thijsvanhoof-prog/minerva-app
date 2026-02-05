import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:minerva_app/profiel/ouder_kind_koppel_page.dart';
import 'package:minerva_app/profiel/admin_gebruikersnamen_page.dart';
import 'package:minerva_app/ui/notifications/notification_settings_page.dart';
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
  final Set<String> _processingLinkRequestIds = {};
  bool _unlinking = false;

  @override
  void initState() {
    super.initState();
    _reload();
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

      final teamNamesById = await _loadTeamNames(teamIds: teamIds);
      if (!mounted) return;

      // Sorteer teams volgens app-volgorde (DS -> HS -> MR -> MA -> JA -> MB -> JB -> MC -> JC ...)
      roles.sort((a, b) {
        final ai = (a['team_id'] as num?)?.toInt() ?? 0;
        final bi = (b['team_id'] as num?)?.toInt() ?? 0;
        final an = (teamNamesById[ai] ?? '').trim();
        final bn = (teamNamesById[bi] ?? '').trim();
        return NevoboApi.compareTeamNames(
          an.isEmpty ? 'Team $ai' : an,
          bn.isEmpty ? 'Team $bi' : bn,
          volleystarsLast: true,
        );
      });

      _safeSetState(() {
        _isGlobalAdmin = isAdmin;
        _teamRoles = roles;
        _teamNamesById = teamNamesById;
        _loading = false;
      });
    } catch (e) {
      _safeSetState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
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

    final controller = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gebruikersnaam wijzigen'),
        content: TextField(
          controller: controller,
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
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName == null) return;
    if (newName.trim().isEmpty) {
      showTopMessage(context, 'Vul een gebruikersnaam in.', isError: true);
      return;
    }

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
    }
  }

  String _normalizeRole(String value) {
    final r = value.trim().toLowerCase();
    switch (r) {
      case 'trainer':
      case 'coach':
        return 'trainer';
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

  List<String> _buildRoleLabels(AppUserContext ctx) {
    final roles = <String>[];

    final isPlayer = _teamRoles.any((row) {
      final r = (row['role']?.toString() ?? '').toLowerCase();
      return r == 'player' || r == 'speler';
    });
    final isOuder = ctx.isOuderVerzorger || ctx.memberships.any((m) => m.isGuardian);
    final isTrainer = _isTrainerOrCoach || ctx.memberships.any((m) => m.canManageTeam);

    // Keep order as requested by the user.
    if (isPlayer) roles.add('Speler');
    if (isOuder) roles.add('Ouder');
    if (isTrainer) roles.add('Trainer/coach');
    if (ctx.isInBestuur) roles.add('Bestuurslid');
    if (ctx.isInTechnischeCommissie) roles.add('TC lid');
    if (ctx.isInCommunicatie) roles.add('Communicatie lid');
    if (ctx.isInWedstrijdzaken) roles.add('Wedstrijdzaken lid');
    if (_isGlobalAdmin || ctx.hasFullAdminRights) roles.add('Algemeen admin');

    // De-duplicate while preserving order.
    final seen = <String>{};
    return roles.where((r) => seen.add(r)).toList();
  }

  String _roleLabel(String role) {
    switch (role.trim().toLowerCase()) {
      case 'trainer':
      case 'coach':
        return 'Trainer/coach';
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
    if (pretty.isNotEmpty) return pretty;
    return 'Team $teamId';
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
                  final name = m['display_name']?.toString() ?? m['profile_id']?.toString() ?? '';
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
          const ListTile(
            title: Text(
              'Gekoppelde accounts',
              style: TextStyle(color: AppColors.textSecondary),
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
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
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
              final viewingAsId = notifier.viewingAsProfileId;
              final viewingAsName = notifier.viewingAsDisplayName;
              final isViewingAsChild = viewingAsId != null;
              final isOuderVerzorger = linked.isNotEmpty;

              final widgets = <Widget>[];

              // Only the ouder/verzorger (parent) can unlink. The linked account (child) never sees this.
              if (isViewingAsChild && isOuderVerzorger) {
                widgets.add(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _unlinking
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final childId = viewingAsId;
                                if (childId.isEmpty) {
                                  showTopMessage(
                                    messenger.context,
                                    'Geen gekoppeld account geselecteerd.',
                                    isError: true,
                                  );
                                  return;
                                }

                                final prevChildren =
                                    List<LinkedChild>.from(notifier.linkedChildren);
                                final prevViewingAsId = notifier.viewingAsProfileId;
                                final prevViewingAsName = notifier.viewingAsDisplayName;

                                try {
                                  setState(() => _unlinking = true);

                                  // Optimistic UI update: remove immediately so it feels responsive.
                                  notifier.clearViewingAs();
                                  notifier.setChildren(
                                    prevChildren.where((c) => c.profileId != childId).toList(),
                                  );

                                  await _client.rpc(
                                    'unlink_child_account',
                                    params: {'child_profile_id': childId},
                                  );

                                  // After unlink, refresh the list from backend (source of truth).
                                  // If we cannot fetch, we must NOT claim success (otherwise it may "come back").
                                  final res =
                                      await _client.rpc('get_my_linked_child_profiles');
                                  final fresh = (res as List<dynamic>?)
                                          ?.map((e) {
                                            final m = e as Map<String, dynamic>?;
                                            if (m == null) return null;
                                            final id = m['profile_id']?.toString();
                                            final name = (m['display_name'] ??
                                                    m['profile_id'] ??
                                                    '')
                                                .toString()
                                                .trim();
                                            if (id == null || id.isEmpty) return null;
                                            return LinkedChild(
                                              profileId: id,
                                              displayName: name.isNotEmpty
                                                  ? name
                                                  : 'Gekoppeld account',
                                            );
                                          })
                                          .whereType<LinkedChild>()
                                          .toList() ??
                                      const [];

                                  notifier.setChildren(fresh);
                                  // Keep viewing-as cleared after unlink attempt.

                                  // Verify: if still present, treat as failure (no silent success).
                                  final stillLinked =
                                      fresh.any((c) => c.profileId == childId);

                                  if (!mounted) return;
                                  if (stillLinked) {
                                    // Restore optimistic state if unlink didn't actually happen.
                                    notifier.setChildren(prevChildren);
                                    if (prevViewingAsId != null) {
                                      notifier.setViewingAs(prevViewingAsId, prevViewingAsName);
                                    }
                                    showTopMessage(
                                      messenger.context,
                                      'Ontkoppelen is niet gelukt (koppeling bestaat nog). Controleer of de Supabase RPC `unlink_child_account` correct is geïnstalleerd en rechten heeft.',
                                      isError: true,
                                    );
                                  } else {
                                    showTopMessage(messenger.context, 'Account ontkoppeld.');
                                  }
                                } on PostgrestException catch (e) {
                                  if (!mounted) return;
                                  final msg = e.message;
                                  final hint = msg.contains('Could not find the function') ||
                                          msg.contains('PGRST202')
                                      ? '\n\nRun `supabase/account_link_requests_schema.sql` (of alleen de unlink RPC) in Supabase.'
                                      : '';
                                  // Restore optimistic state on failure.
                                  notifier.setChildren(prevChildren);
                                  if (prevViewingAsId != null) {
                                    notifier.setViewingAs(prevViewingAsId, prevViewingAsName);
                                  }
                                  showTopMessage(
                                    messenger.context,
                                    'Ontkoppelen mislukt: $msg$hint',
                                    isError: true,
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  notifier.setChildren(prevChildren);
                                  if (prevViewingAsId != null) {
                                    notifier.setViewingAs(prevViewingAsId, prevViewingAsName);
                                  }
                                  showTopMessage(
                                    messenger.context,
                                    'Ontkoppelen mislukt: $e',
                                    isError: true,
                                  );
                                } finally {
                                  if (mounted) setState(() => _unlinking = false);
                                }
                              },
                        icon: _unlinking
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.link_off),
                        label: Text(
                          _unlinking
                              ? 'Ontkoppelen…'
                              : "Ontkoppelen (${viewingAsName ?? 'Gekoppeld account'})",
                        ),
                      ),
                    ),
                  ),
                );
              }

              // Linked accounts list
              widgets.addAll(
                linked.map((c) {
                  final isActive = viewingAsId == c.profileId;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isActive ? Icons.check_circle : Icons.person_outline,
                      color: isActive ? AppColors.primary : AppColors.iconMuted,
                    ),
                    title: Text(
                      isActive
                          ? 'Bekijk als ${c.displayName} (actief)'
                          : 'Bekijk als ${c.displayName}',
                      style: const TextStyle(
                        color: AppColors.onBackground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: isActive ? null : () => notifier.setViewingAs(c.profileId, c.displayName),
                  );
                }),
              );

              // Account koppelen (only when not viewing as)
              if (!isViewingAsChild) {
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
                          ? 'Koppel een ander account. De ouder/verzorger kan daarna meekijken en aanwezigheid aanpassen.'
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
              }

              return Column(children: widgets);
            },
          ),
        ],
      ),
    );
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            16 + MediaQuery.paddingOf(context).top,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: _loading
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
                    ]
                  : [
                    GlassCard(
                      child: ListTile(
                        title: const Text(
                          'Ingelogd als',
                          style: TextStyle(color: AppColors.textSecondary),
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
                          style: TextStyle(color: AppColors.onBackground),
                        ),
                        subtitle: const Text(
                          'Pas aan hoe anderen jou zien in de app.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        onTap: _changeMyDisplayNameFlow,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Rollen: toon alleen als de gebruiker minstens één rol heeft.
                    if (roleLabels.isNotEmpty)
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
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          subtitle: Text(
                            roleLabels.join(' • '),
                            style: const TextStyle(color: AppColors.onBackground),
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Teamrollen
                    GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          const ListTile(
                            title: Text(
                              'Teams & rollen',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                          if (_teamRoles.isEmpty)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Text(
                                'Geen teams gevonden voor dit account.',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          else
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
                        ],
                      ),
                    ),

                    // Ouder-kind account: wissel naar kind of terug naar eigen account
                    if (_showOuderKindSection(context)) ...[
                      const SizedBox(height: 12),
                      _buildOuderKindCard(context),
                    ],

                    const SizedBox(height: 24),

                    GlassCard(
                      child: ListTile(
                        leading: const Icon(
                          Icons.notifications_outlined,
                          color: AppColors.iconMuted,
                        ),
                        title: const Text(
                          'Notificaties',
                          style: TextStyle(color: AppColors.onBackground),
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

                    // Gebruikersnamen beheren (alleen voor admins; wijzig namen van anderen)
                    if (AppUserContext.of(context).hasFullAdminRights) ...[
                      GlassCard(
                        child: ListTile(
                          leading: const Icon(
                            Icons.badge_outlined,
                            color: AppColors.iconMuted,
                          ),
                          title: const Text(
                            'Gebruikersnaam wijzigen',
                            style: TextStyle(color: AppColors.onBackground),
                          ),
                          subtitle: const Text(
                            'Wijzig gebruikersnamen van leden.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AdminGebruikersnamenPage(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Email wijzigen
                    GlassCard(
                      child: ListTile(
                        leading: const Icon(
                          Icons.email_outlined,
                          color: AppColors.iconMuted,
                        ),
                        title: const Text(
                          'E-mail wijzigen',
                          style: TextStyle(color: AppColors.onBackground),
                        ),
                        subtitle: const Text(
                          'Je ontvangt mogelijk een bevestigingsmail.',
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
                          style: TextStyle(color: AppColors.onBackground),
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
                  ],
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
    final controller = TextEditingController();
    final newEmail = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('E-mail wijzigen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Nieuw e-mailadres',
            hintText: currentEmail,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Annuleren'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    controller.dispose();

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