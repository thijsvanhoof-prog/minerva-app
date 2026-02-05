import 'package:flutter/material.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/display_name_overrides.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/components/top_message.dart';

class InfoTab extends StatefulWidget {
  const InfoTab({super.key});

  @override
  State<InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<InfoTab> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loadingCommittees = true;
  String? _committeeError;

  // committeeKey -> committee display name
  final List<String> _committees = [];
  final Map<String, List<_CommitteeMember>> _membersByCommittee = {};
  /// Alle profielen voor commissiebeheer (alleen geladen voor bestuur)
  List<_ProfileOption> _allProfiles = const [];
  bool _loadingProfiles = false;

  static const _manageableCommittees = ['bestuur', 'technische-commissie', 'communicatie', 'wedstrijdzaken'];

  @override
  void initState() {
    super.initState();
    _loadCommittees();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      if (AppUserContext.of(context).isInBestuur && _allProfiles.isEmpty && !_loadingProfiles) {
        _loadAllProfilesForManagement();
      }
    } catch (_) {}
  }

  Future<void> _loadAllProfilesForManagement() async {
    setState(() => _loadingProfiles = true);
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
    final list = <_ProfileOption>[];
    for (final p in raw) {
      final id = p['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final name = applyDisplayNameOverrides(
        (p['display_name'] ?? p['full_name'] ?? p['name'] ?? '').toString().trim(),
      );
      final email = (p['email'] ?? '').toString().trim();
      list.add(_ProfileOption(
        profileId: id,
        name: name.isNotEmpty ? name : (email.isNotEmpty ? email : _shortId(id)),
        email: email.isNotEmpty ? email : null,
      ));
    }
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (mounted) setState(() { _allProfiles = list; _loadingProfiles = false; });
  }

  Future<void> _loadCommittees() async {
    setState(() {
      _loadingCommittees = true;
      _committeeError = null;
      _committees.clear();
      _membersByCommittee.clear();
    });

    try {
      // Prefer RPC that already includes display names (avoids RLS issues on profiles).
      List<Map<String, dynamic>> rows = [];
      try {
        final res = await _client.rpc('get_committee_members_with_names');
        rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      } catch (_) {}

      // Fallback: direct table reads (may show IDs if profiles are blocked by RLS).
      if (rows.isEmpty) {
        // Best-effort: we try a few common column names for "function" inside committee_members.
        for (final select in const [
          'committee_name, profile_id, function',
          'committee_name, profile_id, role',
          'committee_name, profile_id, title',
          'committee_name, profile_id',
        ]) {
          try {
            final res = await _client.from('committee_members').select(select);
            rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
            break;
          } catch (_) {
            // try next
          }
        }
      }

      if (rows.isEmpty) {
        setState(() {
          _loadingCommittees = false;
        });
        return;
      }

      final committeeKeys = <String>{};
      final profileIds = <String>{};
      for (final row in rows) {
        final rawName = row['committee_name']?.toString() ?? '';
        final key = _normalizeCommittee(rawName);
        if (key.isEmpty) continue;
        committeeKeys.add(key);
        final pid = row['profile_id']?.toString() ?? '';
        if (pid.isNotEmpty) profileIds.add(pid);
      }

      // Fetch profile display names (best-effort).
      // If the RPC was used, it already provided display_name, so this will just be a no-op fallback.
      final nameByProfileId = await _loadProfileNames(profileIds: profileIds.toList());

      // Build members by committee
      for (final row in rows) {
        final rawName = row['committee_name']?.toString() ?? '';
        final key = _normalizeCommittee(rawName);
        if (key.isEmpty) continue;

        final pid = row['profile_id']?.toString() ?? '';
        final displayNameFromRow =
            (row['display_name'] ?? row['name'])?.toString().trim();
        final memberName = (displayNameFromRow?.isNotEmpty == true)
            ? applyDisplayNameOverrides(displayNameFromRow!)
            : applyDisplayNameOverrides((nameByProfileId[pid] ?? '').trim());
        final displayName = memberName.isNotEmpty ? memberName : _shortId(pid);

        final function = (row['function'] ?? row['role'] ?? row['title'])?.toString();
        _membersByCommittee.putIfAbsent(key, () => []).add(
              _CommitteeMember(
                profileId: pid,
                name: displayName,
                function: function?.trim().isEmpty == true ? null : function?.trim(),
              ),
            );
      }

      final list = committeeKeys.toList()..sort();
      for (final k in list) {
        final members = _membersByCommittee[k] ?? [];
        members.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _membersByCommittee[k] = members;
      }

      setState(() {
        _committees.addAll(list);
        _loadingCommittees = false;
      });
    } catch (e) {
      setState(() {
        _committeeError = e.toString();
        _loadingCommittees = false;
      });
    }
  }

  Future<bool> _updateCommitteeMemberFunction({
    required String committeeKey,
    required String profileId,
    required String? value,
  }) async {
    // Best-effort: schema differs per Supabase project.
    // We try a few common column names for "function/role/title".
    const candidates = [
      'function',
      'role',
      'title',
      'functie',
      'rol',
      'position',
      'positie',
    ];

    Object? lastError;
    for (final field in candidates) {
      try {
        final res = await _client
            .from('committee_members')
            .update({field: value})
            .eq('committee_name', committeeKey)
            .eq('profile_id', profileId)
            .select('profile_id');
        final rows = (res as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? const [];
        if (rows.isEmpty) {
          throw StateError('Geen rij bijgewerkt (commissie of profiel niet gevonden).');
        }
        return true;
      } on PostgrestException catch (e) {
        lastError = e;
        // Missing column → try next candidate.
        if (e.code == 'PGRST204' ||
            (e.message.contains("Could not find the '") &&
                e.message.contains("column"))) {
          continue;
        }
        rethrow;
      } catch (e) {
        lastError = e;
        rethrow;
      }
    }

    // If none of the columns exist in this Supabase schema, treat as "not supported"
    // and don't fail the user flow (adding/editing members should still work).
    //
    // We only surface non-schema errors (RLS, network, etc.) above.
    if (lastError is PostgrestException) return false;
    if (lastError != null) return false;
    return false;
  }

  Future<Map<String, String>> _loadProfileNames({required List<String> profileIds}) async {
    if (profileIds.isEmpty) return {};

    try {
      final res = await _client
          .from('profiles')
          .select('id, display_name, full_name, email')
          .inFilter('id', profileIds);

      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final map = <String, String>{};
      for (final row in rows) {
        final id = row['id']?.toString() ?? '';
        final name = (row['display_name'] ??
                row['full_name'] ??
                row['email'] ??
                '')
            .toString();
        if (id.isNotEmpty) map[id] = applyDisplayNameOverrides(name);
      }
      return map;
    } catch (_) {
      // If RLS blocks profiles, we just fall back to shortened IDs.
      return {};
    }
  }

  String _normalizeCommittee(String value) {
    final c = value.trim().toLowerCase();
    if (c.isEmpty) return '';
    if (c == 'bestuur') return 'bestuur';
    if (c == 'tc' || c.contains('technische')) return 'technische-commissie';
    if (c.contains('communicatie')) return 'communicatie';
    if (c.contains('wedstrijd')) return 'wedstrijdzaken';
    return c;
  }

  String _committeeLabel(String value) {
    switch (value) {
      case 'bestuur':
        return 'Bestuur';
      case 'technische-commissie':
        return 'Technische commissie';
      case 'communicatie':
        return 'Communicatie commissie';
      case 'wedstrijdzaken':
        return 'Wedstrijdzaken';
      default:
        return value;
    }
  }

  String _shortId(String value) {
    if (value.isEmpty) return '-';
    if (value.length <= 8) return value;
    return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
  }

  bool _showCommitteeManagement(BuildContext context) {
    try {
      return AppUserContext.of(context).isInBestuur;
    } catch (_) {
      return false;
    }
  }

  Future<void> _addMemberToCommittee(String committeeKey) async {
    final alreadyIn = (_membersByCommittee[committeeKey] ?? []).map((m) => m.profileId).toSet();
    final available = _allProfiles.where((p) => !alreadyIn.contains(p.profileId)).toList();
    if (available.isEmpty) {
      showTopMessage(context, 'Iedereen zit al in deze commissie.', isError: true);
      return;
    }
    var search = '';
    final chosen = await showDialog<_ProfileOption>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = search.trim().toLowerCase();
          final list = q.isEmpty
              ? available
              : available
                  .where((p) =>
                      p.name.toLowerCase().contains(q) ||
                      (p.email?.toLowerCase().contains(q) ?? false))
                  .toList();
          return AlertDialog(
            title: Text('Lid toevoegen aan ${_committeeLabel(committeeKey)}'),
            content: SizedBox(
              width: double.maxFinite,
              height: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                        ? const Center(child: Text('Geen leden gevonden.', style: TextStyle(color: AppColors.textSecondary)))
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (context, i) {
                              final p = list[i];
                              return ListTile(
                                dense: true,
                                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: p.email != null ? Text(p.email!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)) : null,
                                onTap: () => Navigator.of(context).pop(p),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Annuleren')),
            ],
          );
        },
      ),
    );
    if (chosen == null) return;
    if (!mounted) return;
    var function = '';
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Functie (optioneel)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(chosen.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (chosen.email != null) ...[
                const SizedBox(height: 4),
                Text(chosen.email!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(labelText: 'Functie of rol', hintText: 'bijv. Voorzitter'),
                onChanged: (v) => function = v.trim(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuleren')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Toevoegen')),
          ],
        ),
      ),
    );
    if (save != true) return;
    try {
      await _client.from('committee_members').insert({
        'committee_name': committeeKey,
        'profile_id': chosen.profileId,
      });
      if (function.isNotEmpty) {
        // Try to write the function/role in whichever column exists.
        final updated = await _updateCommitteeMemberFunction(
          committeeKey: committeeKey,
          profileId: chosen.profileId,
          value: function,
        );
        if (!updated && mounted) {
          showTopMessage(
            context,
            'Let op: je database heeft geen functie/rol-kolom; functie kon niet worden opgeslagen.',
            isError: true,
          );
        }
      }
      if (!mounted) return;
      showTopMessage(
        context,
        function.isNotEmpty
            ? 'Lid toegevoegd aan commissie.'
            : 'Lid toegevoegd aan commissie.',
      );
      await _loadCommittees();
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Toevoegen mislukt: $e', isError: true);
    }
  }

  Future<void> _editOrRemoveCommitteeMember(String committeeKey, _CommitteeMember member) async {
    final controller = TextEditingController(text: member.function ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Lid in ${_committeeLabel(committeeKey)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(member.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Functie of rol'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('remove'),
            child: Text('Uit commissie halen', style: TextStyle(color: AppColors.error)),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Annuleren')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    final newFunction = controller.text.trim();
    controller.dispose();
    if (result == null) return;
    if (result == 'remove') {
      try {
        await _client.from('committee_members').delete().eq('committee_name', committeeKey).eq('profile_id', member.profileId);
        if (!mounted) return;
        showTopMessage(context, 'Lid uit commissie gehaald.');
        await _loadCommittees();
      } catch (e) {
        if (!mounted) return;
        showTopMessage(context, 'Verwijderen mislukt: $e', isError: true);
      }
      return;
    }
    if (result == 'save') {
      try {
        final updated = await _updateCommitteeMemberFunction(
          committeeKey: committeeKey,
          profileId: member.profileId,
          value: newFunction.isEmpty ? null : newFunction,
        );
        if (!mounted) return;
        showTopMessage(
          context,
          updated
              ? 'Functie bijgewerkt.'
              : 'Je database heeft geen functie/rol-kolom; wijziging niet opgeslagen.',
          isError: !updated,
        );
        await _loadCommittees();
      } catch (e) {
        if (!mounted) return;
        showTopMessage(context, 'Bijwerken mislukt: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadCommittees,
        child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16 + MediaQuery.paddingOf(context).top,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          const _InfoCard(
            icon: Icons.info_outline,
            title: 'Over de app',
            subtitle:
                'Deze app helpt je bij trainingen, wedstrijden en verenigingszaken.',
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy',
            subtitle: 'Je gegevens worden alleen gebruikt binnen de vereniging.',
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.support_agent,
            title: 'Contact',
            subtitle: 'Vragen of problemen? Neem contact op met het bestuur.',
          ),
          const SizedBox(height: 18),

          // Commissies overview
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.darkBlue,
                          borderRadius: BorderRadius.circular(AppColors.cardRadius),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.badge_outlined, color: AppColors.primary),
                            const SizedBox(width: 10),
                            Text(
                              'Commissies',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const Spacer(),
                            if (_loadingCommittees)
                              const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_committeeError != null)
                  Text(
                    _committeeError!,
                    style: const TextStyle(color: AppColors.error),
                  )
                else if (!_loadingCommittees && _committees.isEmpty)
                  const Text(
                    'Geen commissies gevonden.',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else
                  ..._committees.map((c) {
                    final members = _membersByCommittee[c] ?? const [];
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _committeeLabel(c),
                            style: const TextStyle(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (members.isEmpty)
                            const Text(
                              '—',
                              style: TextStyle(color: AppColors.textSecondary),
                            )
                          else
                            ...members.map((m) {
                              final suffix =
                                  (m.function != null && m.function!.isNotEmpty)
                                      ? ' (${m.function})'
                                      : '';
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  '- ${m.name}$suffix',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    );
                  }),
                if (_showCommitteeManagement(context)) ...[
                  const SizedBox(height: 24),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Text(
                    'Commissies beheren',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Alleen zichtbaar voor het bestuur. Voeg leden toe of pas functies aan.',
                    style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  ..._manageableCommittees.map((c) {
                    final members = _membersByCommittee[c] ?? [];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              child: Text(
                                _committeeLabel(c),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (members.isEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                                child: Text(
                                  'Geen leden in deze commissie.',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                ),
                              )
                            else
                              ...members.map((m) {
                                final suffix = (m.function != null && m.function!.isNotEmpty) ? ' · ${m.function}' : '';
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.person_outline, color: AppColors.iconMuted, size: 22),
                                  title: Text(
                                    '${m.name}$suffix',
                                    style: const TextStyle(
                                      color: AppColors.onBackground,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  trailing: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                                  onTap: () => _editOrRemoveCommitteeMember(c, m),
                                );
                              }),
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.person_add_outlined, color: AppColors.primary, size: 22),
                              title: const Text(
                                'Lid toevoegen aan deze commissie',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              onTap: _allProfiles.isEmpty && _loadingProfiles
                                  ? null
                                  : () => _addMemberToCommittee(c),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _CommitteeMember {
  final String profileId;
  final String name;
  final String? function;

  const _CommitteeMember({
    required this.profileId,
    required this.name,
    required this.function,
  });
}

class _ProfileOption {
  final String profileId;
  final String name;
  final String? email;

  const _ProfileOption({
    required this.profileId,
    required this.name,
    this.email,
  });
}

/* ===================== UI ===================== */

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.onBackground,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}