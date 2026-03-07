import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/display_name_overrides.dart' show unknownUserName;
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/top_message.dart';

/// Alleen globale admins: bekijk alle accounts, wijzig gebruikersnamen en verwijder accounts.
class AdminGebruikersnamenPage extends StatefulWidget {
  const AdminGebruikersnamenPage({super.key});

  @override
  State<AdminGebruikersnamenPage> createState() => _AdminGebruikersnamenPageState();
}

class _ProfileDetails {
  final String displayName;
  final String email;
  final String teamsText;
  final String committeesText;

  const _ProfileDetails({
    required this.displayName,
    required this.email,
    required this.teamsText,
    required this.committeesText,
  });
}

class _AdminGebruikersnamenPageState extends State<AdminGebruikersnamenPage> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<_ProfileRow> _profiles = const [];
  String _query = '';
  /// Details per profile_id (lazy geladen bij uitklappen).
  final Map<String, _ProfileDetails?> _detailsCache = {};
  final Set<String> _loadingDetails = {};
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Preferred: admin RPC (works even if profiles RLS is strict).
    try {
      final res = await _client.rpc('admin_list_profiles');
      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final list = <_ProfileRow>[];
      for (final r in rows) {
        final id = (r['profile_id'] ?? r['id'])?.toString() ?? '';
        if (id.isEmpty) continue;
        final name = (r['display_name'] ?? '').toString().trim();
        final email = (r['email'] ?? '').toString().trim();
        list.add(_ProfileRow(id: id, displayName: name, email: email));
      }
      if (mounted) {
        setState(() {
          _profiles = list;
          _loading = false;
        });
      }
      return;
    } catch (_) {
      // fall back to direct profiles select below
    }

    List<Map<String, dynamic>> raw = const [];
    for (final select in const [
      'id, display_name, full_name, email',
      'id, display_name, email',
      'id, full_name, email',
      'id, name, email',
      'id, email',
    ]) {
      try {
        final res = await _client.from('profiles').select(select);
        raw = (res as List<dynamic>).cast<Map<String, dynamic>>();
        break;
      } catch (_) {}
    }

    final list = <_ProfileRow>[];
    for (final p in raw) {
      final id = p['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final name = (p['display_name'] ?? p['full_name'] ?? p['name'] ?? '')
          .toString()
          .trim();
      final email = (p['email'] ?? '').toString().trim();
      list.add(_ProfileRow(
        id: id,
        displayName: name,
        email: email,
      ));
    }
    list.sort((a, b) {
      final an = (a.displayName.isNotEmpty ? a.displayName : a.email).toLowerCase();
      final bn = (b.displayName.isNotEmpty ? b.displayName : b.email).toLowerCase();
      return an.compareTo(bn);
    });

    if (mounted) {
      setState(() {
        _profiles = list;
        _loading = false;
      });
    }
  }

  List<_ProfileRow> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _profiles;
    return _profiles.where((p) {
      if (p.displayName.toLowerCase().contains(q)) return true;
      if (p.email.toLowerCase().contains(q)) return true;
      return false;
    }).toList();
  }

  Future<void> _loadDetailsFor(String profileId) async {
    if (_loadingDetails.contains(profileId)) return;
    _loadingDetails.add(profileId);
    if (mounted) setState(() {});

    try {
      final res = await _client.rpc(
        'admin_get_profile_details',
        params: {'p_profile_id': profileId},
      );
      final rows = (res as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      _ProfileDetails? details;
      if (rows.isNotEmpty) {
        final r = rows.first;
        details = _ProfileDetails(
          displayName: (r['display_name'] ?? '').toString().trim(),
          email: (r['email'] ?? '').toString().trim(),
          teamsText: (r['teams_text'] ?? '').toString().trim(),
          committeesText: (r['committees_text'] ?? '').toString().trim(),
        );
      }
      if (mounted) {
        _detailsCache[profileId] = details;
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        _detailsCache[profileId] = null;
        setState(() {});
      }
    } finally {
      _loadingDetails.remove(profileId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _changeNameFor(_ProfileRow profile) async {
    var draftName = profile.displayName;
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Gebruikersnaam wijzigen'),
          content: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppColors.cardRadius - 6),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.22),
                width: 1.1,
              ),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (profile.email.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      profile.email,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                TextFormField(
                  initialValue: draftName,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nieuwe gebruikersnaam',
                    hintText: 'Naam zoals anderen deze persoon zien',
                  ),
                  onChanged: (v) => setDialogState(() => draftName = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Annuleren'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(draftName.trim()),
              child: const Text('Opslaan'),
            ),
          ],
        ),
      ),
    );

    if (newName == null) return;

    try {
      // Preferred: admin RPC (works even if profiles RLS is strict).
      try {
        await _client.rpc(
          'admin_set_profile_display_name',
          params: {'target_profile_id': profile.id, 'new_display_name': newName},
        );
      } catch (_) {
        // fallback: direct update (older installs)
        await _client
            .from('profiles')
            .update({'display_name': newName})
            .eq('id', profile.id);
      }
      if (!mounted) return;
      showTopMessage(context, 'Gebruikersnaam is bijgewerkt.');
      _detailsCache.remove(profile.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Kon gebruikersnaam niet wijzigen: $e', isError: true);
    }
  }

  Future<void> _deleteUser(_ProfileRow profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Account verwijderen'),
        content: Text(
          'Weet je zeker dat je dit account wilt verwijderen?\n\n'
          '${profile.displayName.isNotEmpty ? profile.displayName : profile.email}\n'
          '${profile.email.isNotEmpty ? profile.email : ''}',
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
    if (!mounted) return;

    try {
      await _client.rpc(
        'admin_delete_user',
        params: {'target_user_id': profile.id},
      );
      if (!mounted) return;
      showTopMessage(context, 'Account verwijderd.');
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Verwijderen mislukt: ${e.message}', isError: true);
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Verwijderen mislukt: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.error),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _load,
                            child: const Text('Opnieuw proberen'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16 + MediaQuery.paddingOf(context).top,
                      16,
                      16 + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                        ),
                      ),
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Zoek op naam of e-mail',
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      const SizedBox(height: 16),
                      if (_filtered.isEmpty)
                        const GlassCard(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Geen gebruikers gevonden.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      else
                        ..._filtered.map(_buildAccordionTile),
                    ],
                  ),
                ),
              );
  }

  Widget _buildAccordionTile(_ProfileRow p) {
    final isExpanded = _expandedIds.contains(p.id);
    final details = _detailsCache[p.id];
    final isLoading = _loadingDetails.contains(p.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: const Icon(
              Icons.person_outline,
              color: AppColors.iconMuted,
            ),
            title: Text(
              p.displayName.isNotEmpty
                  ? p.displayName
                  : (p.email.isNotEmpty ? p.email : unknownUserName),
              style: const TextStyle(
                color: AppColors.onBackground,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: isExpanded ? null : (p.email.isNotEmpty
                ? Text(
                    p.email,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  )
                : null),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (AppUserContext.of(context).hasFullAdminRights)
                  IconButton(
                    tooltip: 'Account verwijderen',
                    icon: const Icon(Icons.delete_outline),
                    color: AppColors.error,
                    onPressed: () => _deleteUser(p),
                  ),
                IconButton(
                  tooltip: 'Gebruikersnaam wijzigen',
                  icon: const Icon(Icons.edit_outlined),
                  color: AppColors.primary,
                  onPressed: () => _changeNameFor(p),
                ),
              ],
            ),
            initiallyExpanded: false,
            onExpansionChanged: (expanded) {
              setState(() {
                if (expanded) {
                  _expandedIds.add(p.id);
                  _loadDetailsFor(p.id);
                } else {
                  _expandedIds.remove(p.id);
                }
              });
            },
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      )
                    : details == null
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Kon gegevens niet laden.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _detailRow(Icons.email_outlined, 'E-mail', details.email),
                              const SizedBox(height: 10),
                              _detailRow(Icons.groups_outlined, 'Teams & rollen', details.teamsText),
                              const SizedBox(height: 10),
                              _detailRow(Icons.workspaces_outlined, 'Commissies', details.committeesText),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.onBackground,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileRow {
  final String id;
  final String displayName;
  final String email;

  const _ProfileRow({
    required this.id,
    required this.displayName,
    required this.email,
  });
}
