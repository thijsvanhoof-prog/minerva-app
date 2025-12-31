import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/app_colors.dart';

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

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        setState(() {
          _isGlobalAdmin = false;
          _teamRoles = [];
          _loading = false;
        });
        return;
      }

      // 1) Global admin check (RPC)
      final adminRes = await _client.rpc('is_global_admin');
      final isAdmin = adminRes == true;

      // 2) Teamrollen ophalen
      final data = await _client
          .from('team_members')
          .select('team_id, role')
          .eq('profile_id', user.id);

      final roles = List<Map<String, dynamic>>.from(data);

      // Sorteer netjes op team_id
      roles.sort((a, b) {
        final ai = (a['team_id'] as num?)?.toInt() ?? 0;
        final bi = (b['team_id'] as num?)?.toInt() ?? 0;
        return ai.compareTo(bi);
      });

      setState(() {
        _isGlobalAdmin = isAdmin;
        _teamRoles = roles;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await _client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = _client.auth.currentUser;
    final email = user?.email ?? 'Onbekend';
    final userId = user?.id ?? '-';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profiel'),
        actions: [
          IconButton(
            tooltip: 'Verversen',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : (_error != null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _CardBox(
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
                    _CardBox(
                      child: ListTile(
                        title: const Text(
                          'User ID (UUID)',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        subtitle: Text(
                          userId,
                          style: const TextStyle(color: AppColors.onBackground),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Global admin status
                    _CardBox(
                      child: ListTile(
                        leading: Icon(
                          _isGlobalAdmin ? Icons.verified : Icons.person_outline,
                          color: _isGlobalAdmin
                              ? AppColors.primary
                              : AppColors.iconMuted,
                        ),
                        title: const Text(
                          'Rol',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        subtitle: Text(
                          _isGlobalAdmin ? 'Algemeen admin' : 'Speler',
                          style: const TextStyle(color: AppColors.onBackground),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Teamrollen
                    _CardBox(
                      child: Padding(
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
                                final role = row['role']?.toString() ?? '-';

                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.groups_outlined,
                                    color: AppColors.iconMuted,
                                  ),
                                  title: Text(
                                    'Team ID: $teamId',
                                    style: const TextStyle(
                                      color: AppColors.onBackground,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Rol: $role',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Email wijzigen (placeholder)
                    _CardBox(
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
                          'Komt zo: updateUser(email: ...)',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Nog niet geïmplementeerd.'),
                            ),
                          );
                        },
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
    );
  }
}

class _CardBox extends StatelessWidget {
  final Widget child;
  const _CardBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.65),
          width: 2.2, // vaste dikke oranje rand
        ),
      ),
      child: child,
    );
  }
}