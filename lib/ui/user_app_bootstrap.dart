import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_user_context.dart';

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

  bool _loading = true;
  bool _isGlobalAdmin = false;

  String _profileId = '';
  String _email = '';

  List<TeamMembership> _memberships = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);

    final user = _client.auth.currentUser;
    if (user == null) {
      // Niet ingelogd: geen context
      setState(() {
        _profileId = '';
        _email = '';
        _isGlobalAdmin = false;
        _memberships = const [];
        _loading = false;
      });
      return;
    }

    _profileId = user.id;
    _email = user.email ?? '';

    // 1) Global admin check (RPC)
    bool isGlobalAdmin = false;
    try {
      final res = await _client.rpc('is_global_admin');
      if (res is bool) isGlobalAdmin = res;
    } catch (_) {
      isGlobalAdmin = false;
    }

    // 2) Team memberships ophalen
    // Verwachte kolommen: team_id (int/bigint), role (text), profile_id (uuid)
    final List<dynamic> tmRows = await _client
        .from('team_members')
        .select('team_id, role')
        .eq('profile_id', _profileId);

    final teamIds = <int>[];
    for (final row in tmRows) {
      final m = row as Map<String, dynamic>;
      final teamId = (m['team_id'] as num).toInt();
      if (!teamIds.contains(teamId)) teamIds.add(teamId);
    }

    // 3) Teamnamen ophalen zonder join (dus geen FK nodig)
    // Verwachte kolommen: teams.team_id of teams.id? (jij had eerder issues met "id")
    // We proberen beide varianten robuust:
    final Map<int, String> teamNamesById = {};

    if (teamIds.isNotEmpty) {
      // Probeer eerst teams.team_id
      try {
        final List<dynamic> tRows = await _client
            .from('teams')
            .select('team_id, team_name')
            .inFilter('team_id', teamIds);

        for (final row in tRows) {
          final t = row as Map<String, dynamic>;
          final tid = (t['team_id'] as num).toInt();
          final name = (t['team_name'] as String?) ?? '';
          teamNamesById[tid] = name;
        }
      } catch (_) {
        // Fallback: teams.id
        try {
          final List<dynamic> tRows = await _client
              .from('teams')
              .select('id, team_name')
              .inFilter('id', teamIds);

          for (final row in tRows) {
            final t = row as Map<String, dynamic>;
            final tid = (t['id'] as num).toInt();
            final name = (t['team_name'] as String?) ?? '';
            teamNamesById[tid] = name;
          }
        } catch (_) {
          // Laat teamNamesById leeg; we vullen teamName dan als ''
        }
      }
    }

    // 4) Bouw memberships
    final memberships = <TeamMembership>[];
    for (final row in tmRows) {
      final m = row as Map<String, dynamic>;
      final teamId = (m['team_id'] as num).toInt();
      final role = (m['role'] as String?) ?? 'player';

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

    setState(() {
      _isGlobalAdmin = isGlobalAdmin;
      _memberships = memberships;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Simpel laadscherm; je kunt dit vervangen door je eigen UI
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Als je niet ingelogd bent, wil je meestal gewoon widget.child tonen
    // (bijv. AuthGate regelt al wat er gebeurt). We zetten dan geen context.
    if (_profileId.isEmpty) {
      return widget.child;
    }

    return AppUserContext(
      profileId: _profileId,
      email: _email,
      isGlobalAdmin: _isGlobalAdmin,
      memberships: _memberships,
      child: widget.child,
    );
  }
}