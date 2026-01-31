import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_user_context.dart';
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

  bool _loading = true;
  bool _isGlobalAdmin = false;

  String _profileId = '';
  String _email = '';
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
  }

  void _onOuderKindChanged() {
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
      _ouderKindNotifier.setViewingAs(null, null);
      _ouderKindNotifier.setChildren(const []);
      setState(() {
        _profileId = '';
        _email = '';
        _loggedInProfileId = '';
        _isGlobalAdmin = false;
        _memberships = const [];
        _committees = const [];
        _loading = false;
      });
      return;
    }

    _loggedInProfileId = user.id;
    _email = user.email ?? '';
    final effectiveProfileId = _ouderKindNotifier.viewingAsProfileId ?? user.id;
    _profileId = effectiveProfileId;

    // 0) Gekoppelde kinderen ophalen (ouder-kind account) – best-effort RPC
    try {
      final res = await _client.rpc('get_my_linked_child_profiles');
      final list = (res as List<dynamic>?)
          ?.map((e) {
            final m = e as Map<String, dynamic>?;
            if (m == null) return null;
            final id = m['profile_id']?.toString();
            final name = m['display_name']?.toString() ?? m['profile_id']?.toString() ?? '';
            if (id == null || id.isEmpty) return null;
            return LinkedChild(profileId: id, displayName: name.trim().isEmpty ? 'Kind' : name);
          })
          .whereType<LinkedChild>()
          .toList() ??
          const [];
      _ouderKindNotifier.setChildren(list);
    } catch (_) {
      _ouderKindNotifier.setChildren(const []);
    }

    // 1) Global admin check (RPC) – altijd voor de ingelogde user
    bool isGlobalAdmin = false;
    try {
      final res = await _client.rpc('is_global_admin');
      if (res is bool) isGlobalAdmin = res;
    } catch (_) {
      isGlobalAdmin = false;
    }

    // 2) Team memberships ophalen voor de effectieve profile (ouder of gekozen kind)
    final List<dynamic> tmRows = await _client
        .from('team_members')
        .select('team_id, role')
        .eq('profile_id', effectiveProfileId);

    final teamIds = <int>[];
    for (final row in tmRows) {
      final m = row as Map<String, dynamic>;
      final teamId = (m['team_id'] as num).toInt();
      if (!teamIds.contains(teamId)) teamIds.add(teamId);
    }

    // 3) Teamnamen ophalen zonder join (dus geen FK nodig).
    // We don't know your exact teams column names, so we try a few common options.
    final teamNamesById = await _loadTeamNames(teamIds: teamIds);

    // 4) Bouw memberships
    final memberships = <TeamMembership>[];
    for (final row in tmRows) {
      final m = row as Map<String, dynamic>;
      final teamId = (m['team_id'] as num).toInt();
      final roleRaw = (m['role'] as String?) ?? 'player';
      final role = _normalizeRole(roleRaw);

      // teamName is REQUIRED -> altijd string leveren
      final teamName = teamNamesById[teamId] ?? '';

      memberships.add(
        TeamMembership(
          teamId: teamId,
          role: role,
          teamName: teamName,
        ),
      );
    }

    // 5) Commissies ophalen voor de effectieve profile (best-effort).
    final committees = await _loadCommittees(profileId: effectiveProfileId);

    setState(() {
      _isGlobalAdmin = isGlobalAdmin;
      _memberships = memberships;
      _committees = committees;
      _loading = false;
    });

    // Best-effort OneSignal user sync (no-op if not supported / not initialized yet).
    // We schedule it post-frame so it can run after OneSignal initialize in main().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.syncUser(
        profileId: _profileId,
        email: _email,
        isGlobalAdmin: _isGlobalAdmin,
        memberships: _memberships,
        committees: _committees,
      );
    });
  }

  String _normalizeRole(String value) {
    final r = value.trim().toLowerCase();
    // Alleen speler en trainer/coach. Trainer en coach zijn één rol.
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
      // If table/column doesn't exist or RLS blocks it, just return empty.
      return const [];
    }
  }

  String _normalizeCommittee(String value) {
    final c = value.trim().toLowerCase();
    if (c.isEmpty) return '';
    // Accept common variations.
    if (c == 'bestuur') return 'bestuur';
    if (c == 'tc' || c.contains('technische')) return 'technische-commissie';
    if (c.contains('communicatie')) return 'communicatie';
    if (c.contains('wedstrijd')) return 'wedstrijdzaken';
    return c;
  }

  @override
  Widget build(BuildContext context) {
    // Belangrijk:
    // - We houden AppUserContext én de volledige Navigator (widget.child) altijd gemount.
    // - Tijdens reload/auth events tonen we alleen een overlay bovenop de app.
    //   Als je de Navigator vervangt (bijv. door een loading Scaffold), kan een open dialog
    //   nog afhankelijk zijn van inherited widgets, wat kan leiden tot:
    //   `Failed assertion: '_dependents.isEmpty'`.
    final base = widget.child;

    final child = Stack(
      children: [
        base,
        if (_loading)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: false,
              child: Container(
                color: Colors.black.withValues(alpha: 0.25),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              ),
            ),
          ),
      ],
    );

    return AppUserContext(
      profileId: _profileId,
      email: _email,
      isGlobalAdmin: _isGlobalAdmin,
      memberships: _memberships,
      committees: _committees,
      loggedInProfileId: _loggedInProfileId,
      viewingAsProfileId: _ouderKindNotifier.viewingAsProfileId,
      viewingAsDisplayName: _ouderKindNotifier.viewingAsDisplayName,
      linkedChildProfiles: _ouderKindNotifier.linkedChildren,
      ouderKindNotifier: _ouderKindNotifier,
      child: child,
    );
  }
}