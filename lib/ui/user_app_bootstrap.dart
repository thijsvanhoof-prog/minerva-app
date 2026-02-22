import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/display_name_overrides.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/nevobo_api.dart';
import 'package:minerva_app/ui/notifications/notification_service.dart';

/// Wrapt jouw app met AppUserContext.
/// - Haalt global admin status op via RPC: is_global_admin
/// - Haalt team memberships op uit team_members
/// - Haalt teamnamen op uit teams (losse query, dus geen FK/join vereist)
class UserAppBootstrap extends StatefulWidget {
  final Widget child;

  const UserAppBootstrap({
    super.key,
    required this.child,
  });

  @override
  State<UserAppBootstrap> createState() => _UserAppBootstrapState();
}

class _UserAppBootstrapState extends State<UserAppBootstrap> {
  final SupabaseClient _client = Supabase.instance.client;
  StreamSubscription<AuthState>? _authSub;
  final OuderKindNotifier _ouderKindNotifier = OuderKindNotifier();
  bool _suppressOuderKindReload = false;

  bool _loading = true;
  bool _initialLoadComplete = false;
  bool _isGlobalAdmin = false;

  String _profileId = '';
  String _email = '';
  String _displayName = '';
  String _loggedInProfileId = '';

  List<TeamMembership> _memberships = const [];
  List<String> _committees = const [];

  @override
  void initState() {
    super.initState();
    _ouderKindNotifier.addListener(_onOuderKindChanged);
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      // Belangrijk: op token refresh wil Supabase soms events emitten midden in een UI-flow
      // (bijv. tijdens "Opslaan"). We hoeven dan geen user-context reload te doen,
      // en het voorkomt zeldzame framework asserts rond (de)activation van inherited dependents.
      if (state.event == AuthChangeEvent.tokenRefreshed) return;
      if (!mounted) return;
      _reload();
    });
    _reload();
    // Voorkom eindeloze freeze: als een Supabase-call blijft hangen, na 15s toch UI tonen.
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _loading) setState(() => _loading = false);
    });
  }

  void _onOuderKindChanged() {
    if (_suppressOuderKindReload) return;
    if (mounted) _reload();
  }

  @override
  void dispose() {
    _ouderKindNotifier.removeListener(_onOuderKindChanged);
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);

    final user = _client.auth.currentUser;
    if (user == null) {
      _suppressOuderKindReload = true;
      try {
        _ouderKindNotifier.setViewingAs(null, null);
        _ouderKindNotifier.setChildren(const []);
      } finally {
        _suppressOuderKindReload = false;
      }
      setState(() {
        _profileId = '';
        _email = '';
        _displayName = '';
        _loggedInProfileId = '';
        _isGlobalAdmin = false;
        _memberships = const [];
        _committees = const [];
        _loading = false;
        _initialLoadComplete = false;
      });
      return;
    }
    // If the logged-in user changes, clear any "view as child" state immediately.
    final prevLoggedIn = _loggedInProfileId;
    _loggedInProfileId = user.id;
    _email = user.email ?? '';
    // Keep metadata as a fallback, but prefer `profiles.display_name` where available.
    _displayName = (user.userMetadata?['display_name']?.toString() ?? '').trim();
    if (prevLoggedIn.isNotEmpty && prevLoggedIn != user.id) {
      _suppressOuderKindReload = true;
      try {
        _ouderKindNotifier.setViewingAs(null, null);
      } finally {
        _suppressOuderKindReload = false;
      }
    }

    // 0) Gekoppelde kinderen ophalen (ouder-kind account) – best-effort RPC
    _suppressOuderKindReload = true;
    try {
      final res = await _client.rpc('get_my_linked_child_profiles');
      final list = (res as List<dynamic>?)
          ?.map((e) {
            final m = e as Map<String, dynamic>?;
            if (m == null) return null;
            final id = m['profile_id']?.toString();
            final name = (m['display_name']?.toString() ?? '').trim();
            if (id == null || id.isEmpty) return null;
            return LinkedChild(profileId: id, displayName: name.isEmpty ? 'Kind' : name);
          })
          .whereType<LinkedChild>()
          .toList() ??
          const [];
      _ouderKindNotifier.setChildren(list);

      // New desired behavior: if this account has linked profiles, default to "view as"
      // the first linked profile so the ouder/verzorger sees what the linked account sees.
      if (list.isNotEmpty && _ouderKindNotifier.viewingAsProfileId == null) {
        _ouderKindNotifier.setViewingAs(list.first.profileId, list.first.displayName);
      }
    } catch (_) {
      _ouderKindNotifier.setChildren(const []);
    } finally {
      _suppressOuderKindReload = false;
    }

    // We keep the logged-in profile as the "main" profile.
    // For ouder/verzorger we may additionally load team memberships for the selected linked profile.
    _profileId = user.id;

    // 1) Global admin check (RPC) – altijd voor de ingelogde user
    bool isGlobalAdmin = false;
    try {
      final res = await _client.rpc('is_global_admin');
      if (res is bool) isGlobalAdmin = res;
    } catch (_) {
      isGlobalAdmin = false;
    }

    // 2) Team memberships:
    // - altijd je eigen roles (player/trainer)
    // - als ouder/verzorger: voeg teams toe waar een gekoppeld account speler is
    final List<dynamic> ownTmRows = await _client
        .from('team_members')
        .select('team_id, role')
        .eq('profile_id', user.id);

    final linkedProfileIds = _ouderKindNotifier.linkedChildren
        .map((c) => c.profileId)
        .where((id) => id.isNotEmpty && id != user.id)
        .toSet()
        .toList();
    List<dynamic> linkedTmRows = const [];
    if (linkedProfileIds.isNotEmpty) {
      try {
        linkedTmRows = await _client
            .from('team_members')
            .select('team_id, role, profile_id')
            .inFilter('profile_id', linkedProfileIds);
      } catch (_) {
        linkedTmRows = const [];
      }
    }

    final teamIds = <int>[];
    for (final row in [...ownTmRows, ...linkedTmRows]) {
      final m = row as Map<String, dynamic>;
      final teamId = (m['team_id'] as num).toInt();
      if (!teamIds.contains(teamId)) teamIds.add(teamId);
    }

    // 3) Teamnamen (+ nevobo_code) ophalen. Eerst directe tabel, dan RPC-fallback (zelfde als Profiel).
    Map<int, String> teamNamesById = await _loadTeamNames(teamIds: teamIds);
    final nevoboCodeById = <int, String>{};
    if (teamIds.isNotEmpty) {
      try {
        final rpc = await _client.rpc(
          'get_team_names_for_app',
          params: {'p_team_ids': teamIds},
        );
        final rows = (rpc as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        for (final r in rows) {
          final tid = (r['team_id'] as num?)?.toInt();
          if (tid == null) continue;
          final name = (r['team_name'] as String?) ?? '';
          if (name.trim().isNotEmpty && (teamNamesById[tid] ?? '').trim().isEmpty) {
            teamNamesById = {...teamNamesById, tid: name.trim()};
          }
          final code = (r['nevobo_code'] as String?)?.trim();
          if (code != null && code.isNotEmpty) nevoboCodeById[tid] = code;
        }
      } catch (_) {}
    }

    // 4) Bouw memberships
    final memberships = <TeamMembership>[];

    // Own roles (player/trainer)
    for (final row in ownTmRows) {
      final m = row as Map<String, dynamic>;
      final teamId = (m['team_id'] as num).toInt();
      final roleRaw = (m['role'] as String?) ?? 'player';
      final role = _normalizeRole(roleRaw);
      final raw = teamNamesById[teamId] ?? '';
      final teamName = raw.isEmpty ? raw : NevoboApi.displayTeamName(raw);
      final nevoboCode = nevoboCodeById[teamId];
      memberships.add(TeamMembership(teamId: teamId, role: role, teamName: teamName, nevoboCode: nevoboCode));
    }

    // Guardian roles (ouder/verzorger): include teams where ANY linked account is a player.
    final seen = <String>{
      for (final m in memberships) '${m.teamId}:${m.role}',
    };
    for (final row in linkedTmRows) {
      final m = row as Map<String, dynamic>;
      final teamId = (m['team_id'] as num).toInt();
      final profileId = (m['profile_id']?.toString() ?? '').trim();
      final roleRaw = (m['role'] as String?) ?? 'player';
      final normalized = _normalizeRole(roleRaw);
      if (normalized != 'player') continue;
      final raw = teamNamesById[teamId] ?? '';
      final teamName = raw.isEmpty ? raw : NevoboApi.displayTeamName(raw);
      final nevoboCode = nevoboCodeById[teamId];
      final linkedChildName = profileId.isEmpty
          ? null
          : _ouderKindNotifier.linkedChildren
              .where((c) => c.profileId == profileId)
              .map((c) => c.displayName.trim())
              .where((s) => s.isNotEmpty)
              .firstOrNull;
      final key = '$teamId:guardian';
      if (seen.add(key)) {
        memberships.add(TeamMembership(
          teamId: teamId,
          role: 'guardian',
          teamName: teamName,
          nevoboCode: nevoboCode,
          linkedChildDisplayName: linkedChildName,
        ));
      }
    }

    // 5) Commissies altijd voor de ingelogde user (ouder/verzorger behoudt eigen commissies).
    final committees = await _loadCommittees(profileId: user.id);

    // 6) Display name (gebruikersnaam) voor "ingelogd als" etc. – prefer profiles/metadata.
    // Best-effort: use SECURITY DEFINER RPC if available to avoid RLS problems.
    final metaName = (_displayName).trim();
    String profileName = '';
    try {
      final res = await _client.rpc(
        'get_profile_display_names',
        params: {'profile_ids': [user.id]},
      );
      final rows = (res as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? const [];
      if (rows.isNotEmpty) {
        final name = (rows.first['display_name'] ?? '').toString().trim();
        if (name.isNotEmpty) profileName = name;
      }
    } catch (_) {}

    // Prefer auth user metadata (updated immediately from the app),
    // then fall back to profiles (RPC), then email.
    String displayName = metaName.isNotEmpty ? metaName : profileName;
    if (displayName.trim().isEmpty) {
      // last resort: email local-part
      final e = _email;
      displayName = e.contains('@') ? e.split('@').first : e;
    }

    displayName = applyDisplayNameOverrides(displayName);

    // If this user only has the ouder/verzorger role (no own team memberships),
    // show a clearer label: "Naam (ouder/verzorger 'Gekoppeld account')".
    if (ownTmRows.isEmpty && _ouderKindNotifier.linkedChildren.isNotEmpty) {
      final linkedName =
          (_ouderKindNotifier.viewingAsDisplayName ??
                  _ouderKindNotifier.linkedChildren.first.displayName)
              .trim();
      final suffix = linkedName.isNotEmpty ? linkedName : 'Gekoppeld account';
      displayName = "$displayName (ouder/verzorger '$suffix')";
    }

    if (!mounted) return;
    setState(() {
      _isGlobalAdmin = isGlobalAdmin;
      _memberships = memberships;
      _committees = committees;
      _displayName = displayName;
      _loading = false;
      _initialLoadComplete = true;
    });

    // FCM: token en standaardvoorkeur registreren na inloggen.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await NotificationService.syncUser(profileId: _profileId);
      } catch (_) {}
    });
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

  Future<Map<int, String>> _loadTeamNames({required List<int> teamIds}) async {
    if (teamIds.isEmpty) return {};

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

  Future<List<String>> _loadCommittees({required String profileId}) async {
    try {
      final rpc = await _client.rpc('get_my_committees');
      final rows = (rpc as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      final set = <String>{};
      for (final row in rows) {
        final raw = row['committee_name']?.toString() ?? '';
        final normalized = _normalizeCommittee(raw);
        if (normalized.isNotEmpty) set.add(normalized);
      }
      if (set.isNotEmpty) return set.toList()..sort();
    } catch (_) {}
    try {
      final res = await _client
          .from('committee_members')
          .select('committee_name')
          .eq('profile_id', profileId);
      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final set = <String>{};
      for (final row in rows) {
        final raw = row['committee_name']?.toString() ?? '';
        final normalized = _normalizeCommittee(raw);
        if (normalized.isNotEmpty) set.add(normalized);
      }
      return set.toList()..sort();
    } catch (_) {
      return const [];
    }
  }

  String _normalizeCommittee(String value) {
    final c = value.trim().toLowerCase();
    if (c.isEmpty) return '';
    // Accept common variations.
    if (c == 'bestuur') return 'bestuur';
    if (c == 'tc' || c.contains('technische')) return 'technische-commissie';
    if (c == 'cc' || c.contains('communicatie')) return 'communicatie';
    if (c == 'wz' || c.contains('wedstrijd')) return 'wedstrijdzaken';
    if (c.contains('evenement')) return 'evenementen';
    if (c == 'jeugd' || c.contains('jeugdcommissie')) return 'jeugdcommissie';
    if ((c.contains('scheidsrechter') && c.contains('teller')) ||
        c.contains('scheidsrechters-tellers')) {
      return 'scheidsrechters-tellers';
    }
    if (c.contains('vrijwilliger')) return 'vrijwilligers';
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final hasSession = _client.auth.currentUser != null;
    // Alleen volledig laadscherm bij eerste load; bij refresh blijft de huidige pagina zichtbaar.
    final showApp = !hasSession || !_loading || _initialLoadComplete;
    final content = showApp
        ? widget.child
        : Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Laden…',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          );

    return AppUserContext(
      profileId: _profileId,
      email: _email,
      displayName: _displayName,
      isGlobalAdmin: _isGlobalAdmin,
      memberships: _memberships,
      committees: _committees,
      reloadUserContext: _reload,
      loggedInProfileId: _loggedInProfileId,
      viewingAsProfileId: _ouderKindNotifier.viewingAsProfileId,
      viewingAsDisplayName: _ouderKindNotifier.viewingAsDisplayName,
      linkedChildProfiles: _ouderKindNotifier.linkedChildren,
      ouderKindNotifier: _ouderKindNotifier,
      child: content,
    );
  }
}