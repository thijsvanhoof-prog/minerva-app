import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:minerva_app/ui/components/app_logo_title.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/profiel/ouder_kind_koppel_page.dart';
import 'package:minerva_app/profiel/admin_gebruikersnamen_page.dart';
import 'package:minerva_app/ui/notifications/notification_settings_page.dart';
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

      // Sorteer netjes op team_id
      roles.sort((a, b) {
        final ai = (a['team_id'] as num?)?.toInt() ?? 0;
        final bi = (b['team_id'] as num?)?.toInt() ?? 0;
        return ai.compareTo(bi);
      });

      // 2b) Teamnamen ophalen (best-effort)
      final teamIds = roles
          .map((r) => (r['team_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList()
        ..sort();

      final teamNamesById = await _loadTeamNames(teamIds: teamIds);
      if (!mounted) return;

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

    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            title: Text(
              'Ouder-kind account',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          if (ctx.isViewingAsChild) ...[
            ListTile(
              dense: true,
              leading: const Icon(Icons.person_outline, color: AppColors.primary),
              title: const Text(
                'Terug naar mijn account',
                style: TextStyle(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Nu bekeken als: ${ctx.viewingAsDisplayName ?? 'Kind'}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () => notifier.clearViewingAs(),
            ),
          ],
          ...ctx.linkedChildProfiles.map((c) {
            final isActive = ctx.viewingAsProfileId == c.profileId;
            return ListTile(
              dense: true,
              leading: Icon(
                isActive ? Icons.check_circle : Icons.person_outline,
                color: isActive ? AppColors.primary : AppColors.iconMuted,
              ),
              title: Text(
                isActive ? 'Bekijk als ${c.displayName} (actief)' : 'Bekijk als ${c.displayName}',
                style: const TextStyle(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: isActive
                  ? null
                  : () => notifier.setViewingAs(c.profileId, c.displayName),
            );
          }),
          // Kind koppelen: waar je een nieuw kind aan je account koppelt
          if (!ctx.isViewingAsChild)
            ListTile(
              dense: true,
              leading: const Icon(Icons.person_add_outlined, color: AppColors.iconMuted),
              title: const Text(
                'Kind koppelen',
                style: TextStyle(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                ctx.linkedChildProfiles.isEmpty
                    ? 'Koppel het account van je kind aan je eigen account.'
                    : 'Nog een kind toevoegen.',
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const AppLogoTitle(),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
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
                          email,
                          style: const TextStyle(color: AppColors.onBackground),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Global admin status
                    GlassCard(
                      child: ListTile(
                        leading: Icon(
                          _isGlobalAdmin ? Icons.verified : Icons.person_outline,
                          color:
                              _isGlobalAdmin ? AppColors.primary : AppColors.iconMuted,
                        ),
                        title: const Text(
                          'Rol',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        subtitle: Text(
                          _isGlobalAdmin
                              ? 'Algemeen admin'
                              : (_isTrainerOrCoach ? 'Trainer/coach' : 'Speler'),
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

    if (newEmail == null || newEmail.trim().isEmpty) return;

    final email = newEmail.trim();
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vul een geldig e-mailadres in.')),
      );
      return;
    }
    if (email == currentEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dit is al je huidige e-mailadres.')),
      );
      return;
    }

    try {
      await _client.auth.updateUser(
        UserAttributes(email: email),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail wijziging gestart. Check je mail om te bevestigen.')),
      );
      await _reload();
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kon e-mail niet wijzigen. Probeer het later opnieuw.')),
      );
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

      final response = await _client.functions.invoke('delete_my_account');
      if (!mounted) return;
      if (response.status >= 200 && response.status < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account verwijderd.')),
        );
        await _client.auth.signOut();
      } else {
        final msg = response.data is Map && response.data['error'] != null
            ? response.data['error'].toString()
            : 'Account verwijderen mislukt.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } on FunctionException catch (e) {
      if (!mounted) return;
      final url = dotenv.env['SUPABASE_URL'] ?? '(onbekend)';

      if (e.status == 401) {
        // Token is invalid/expired → force re-auth by signing out.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Je sessie is verlopen. Je wordt uitgelogd; log opnieuw in en probeer opnieuw.'),
          ),
        );
        await _client.auth.signOut();
        return;
      }

      if (e.status == 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Edge Function delete_my_account niet gevonden (404). Controleer dat SUPABASE_URL naar het juiste project wijst ($url) en dat de function gedeployed is.',
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Account verwijderen mislukt (${_shortError(e)}). SUPABASE_URL: $url',
          ),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      final url = dotenv.env['SUPABASE_URL'] ?? '(onbekend)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Account verwijderen mislukt (${_shortError(e)}). Controleer dat SUPABASE_URL naar het juiste project wijst ($url) en dat de Edge Function delete_my_account gedeployed is.',
          ),
        ),
      );
    }
  }
}