import 'package:flutter/material.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/tab_page_header.dart';
import 'package:minerva_app/ui/display_name_overrides.dart' show applyDisplayNameOverrides, unknownUserName;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:minerva_app/ui/app_colors.dart';

class InfoTab extends StatefulWidget {
  const InfoTab({super.key});

  @override
  State<InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<InfoTab> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loadingCommittees = true;
  String? _committeeError;

  // committeeKey -> display name (eerste voorkomensnaam uit DB)
  final List<String> _committees = [];
  final Map<String, String> _committeeDisplayName = {};
  final Map<String, List<_CommitteeMember>> _membersByCommittee = {};

  @override
  void initState() {
    super.initState();
    _loadCommittees();
  }

  Future<void> _loadCommittees() async {
    if (!mounted) return;
    setState(() {
      _loadingCommittees = true;
      _committeeError = null;
      _committees.clear();
      _committeeDisplayName.clear();
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
          'committee_name, profile_id, function, email',
          'committee_name, profile_id, role, email',
          'committee_name, profile_id, title, email',
          'committee_name, profile_id, function, contact_email',
          'committee_name, profile_id, role, contact_email',
          'committee_name, profile_id, title, contact_email',
          'committee_name, profile_id, email',
          'committee_name, profile_id, contact_email',
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
        // Extra fallback: sommige setups bewaren commissie-contact direct per commissie
        // i.p.v. per profiel in committee_members.
        for (final select in const [
          'committee_name, contact_email',
          'committee_name, email',
          'name, contact_email',
          'name, email',
          'committee_name, mail',
          'name, mail',
        ]) {
          try {
            final res = await _client.from('committees').select(select);
            final raw = (res as List<dynamic>).cast<Map<String, dynamic>>();
            if (raw.isEmpty) continue;
            rows = raw
                .map((r) {
                  final committeeName =
                      (r['committee_name'] ?? r['name'] ?? '').toString().trim();
                  final email =
                      (r['contact_email'] ?? r['email'] ?? r['mail'])
                          ?.toString()
                          .trim();
                  return <String, dynamic>{
                    'committee_name': committeeName,
                    'profile_id': '',
                    'display_name': committeeName,
                    'function': 'Commissiecontact',
                    if (email != null && email.isNotEmpty) 'email': email,
                  };
                })
                .where((r) => (r['committee_name'] as String).isNotEmpty)
                .toList();
            if (rows.isNotEmpty) break;
          } catch (_) {
            // try next
          }
        }
      }

      if (rows.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loadingCommittees = false;
        });
        return;
      }

      final committeeKeys = <String>{};
      final committeeDisplayNames = <String, String>{};
      final profileIds = <String>{};
      for (final row in rows) {
        final rawName = row['committee_name']?.toString().trim() ?? '';
        if (rawName.isEmpty) continue;
        final key = _normalizeCommittee(rawName);
        committeeKeys.add(key);
        committeeDisplayNames.putIfAbsent(key, () => rawName);
        final pid = row['profile_id']?.toString() ?? '';
        if (pid.isNotEmpty) profileIds.add(pid);
      }

      // Namen en emails: uit RPC-response als die een email-kolom heeft, anders apart laden.
      final nameByProfileId = await _loadProfileNames(
        profileIds: profileIds.toList(),
      );
      Map<String, String> emailByProfileId = await _loadProfileEmails(
        profileIds: profileIds.toList(),
      );
      final hasEmailInRows = rows.any((r) {
        final direct = r['email']?.toString().trim() ?? '';
        final contact = r['contact_email']?.toString().trim() ?? '';
        final mail = r['mail']?.toString().trim() ?? '';
        return direct.isNotEmpty || contact.isNotEmpty || mail.isNotEmpty;
      });
      if (hasEmailInRows) {
        final fromRpc = <String, String>{};
        for (final row in rows) {
          final pid = row['profile_id']?.toString() ?? '';
          final email = (row['email'] ?? row['contact_email'] ?? row['mail'])
              ?.toString()
              .trim();
          if (pid.isNotEmpty && email != null && email.isNotEmpty) fromRpc[pid] = email;
        }
        if (fromRpc.isNotEmpty) emailByProfileId = fromRpc;
      }

      // Build members by committee
      for (final row in rows) {
        final rawName = row['committee_name']?.toString().trim() ?? '';
        if (rawName.isEmpty) continue;
        final key = _normalizeCommittee(rawName);

        final pid = row['profile_id']?.toString() ?? '';
        final displayNameFromRow = (row['display_name'] ?? row['name'])
            ?.toString()
            .trim();
        final memberName = (displayNameFromRow?.isNotEmpty == true)
            ? applyDisplayNameOverrides(displayNameFromRow!)
            : applyDisplayNameOverrides((nameByProfileId[pid] ?? '').trim());
        final displayName = memberName.isNotEmpty ? memberName : unknownUserName;
        final rowEmail = (row['email'] ?? row['contact_email'] ?? row['mail'])
            ?.toString()
            .trim();
        final email = rowEmail?.isNotEmpty == true
            ? rowEmail
            : emailByProfileId[pid]?.trim();
        // Alleen @-adressen tonen (e-mail van Minerva)
        final emailToShow = (email != null && email.contains('@'))
            ? email
            : null;

        final function = (row['function'] ?? row['role'] ?? row['title'])
            ?.toString();
        _membersByCommittee
            .putIfAbsent(key, () => [])
            .add(
              _CommitteeMember(
                profileId: pid,
                name: displayName,
                function: function?.trim().isEmpty == true
                    ? null
                    : function?.trim(),
                email: emailToShow,
              ),
            );
      }

      final list = committeeKeys.toList()..sort();
      for (final k in list) {
        final members = _membersByCommittee[k] ?? [];
        members.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        _membersByCommittee[k] = members;
      }

      const visibleOrder = <String>[
        'bestuur',
        'communicatie',
        'technische-commissie',
        'wedstrijdzaken',
        'jeugd',
      ];
      final indexByKey = <String, int>{
        for (var i = 0; i < visibleOrder.length; i++) visibleOrder[i]: i,
      };
      list.removeWhere((k) => !indexByKey.containsKey(k));
      list.sort(
        (a, b) => (indexByKey[a] ?? 999).compareTo(indexByKey[b] ?? 999),
      );

      if (!mounted) return;
      setState(() {
        _committees.addAll(list);
        _committeeDisplayName.addAll(committeeDisplayNames);
        _loadingCommittees = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _committeeError = e.toString();
        _loadingCommittees = false;
      });
    }
  }

  Future<Map<String, String>> _loadProfileNames({
    required List<String> profileIds,
  }) async {
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
        final name =
            (row['display_name'] ?? row['full_name'] ?? row['email'] ?? '')
                .toString();
        if (id.isNotEmpty) map[id] = applyDisplayNameOverrides(name);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, String>> _loadProfileEmails({
    required List<String> profileIds,
  }) async {
    if (profileIds.isEmpty) return {};

    try {
      final res = await _client
          .from('profiles')
          .select('id, email')
          .inFilter('id', profileIds);

      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final map = <String, String>{};
      for (final row in rows) {
        final id = row['id']?.toString() ?? '';
        final email = (row['email'] ?? '').toString().trim();
        if (id.isNotEmpty && email.isNotEmpty) map[id] = email;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  String _normalizeCommittee(String value) {
    final c = value.trim().toLowerCase();
    if (c.isEmpty) return '';
    // Varianten samenvoegen voor dezelfde commissie
    if (c == 'bestuur') return 'bestuur';
    if (c == 'tc' || c.contains('technische')) return 'technische-commissie';
    if (c.contains('communicatie')) return 'communicatie';
    if (c.contains('wedstrijd')) return 'wedstrijdzaken';
    if (c.contains('jeugd')) return 'jeugd';
    if (c.contains('algemeen') || c.contains('secretariaat')) {
      return 'secretariaat';
    }
    return c;
  }

  String _committeeLabel(String key) {
    switch (key) {
      case 'bestuur':
        return 'Bestuur';
      case 'communicatie':
        return 'Communicatie';
      case 'technische-commissie':
        return 'Technische Commissie';
      case 'wedstrijdzaken':
        return 'Wedstrijdzaken';
      case 'jeugd':
        return 'Jeugdcommissie';
    }
    final raw = _committeeDisplayName[key] ?? key;
    return raw
        .split(' ')
        .map(
          (w) => w.isEmpty
              ? w
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Future<void> _openMail(String email) async {
    final uri = Uri.parse('mailto:$email');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            TabPageHeader(
              child: Text(
                'Contact',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _loadCommittees,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    // Commissies met contactpersonen
                    GlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.darkBlue,
                                    borderRadius: BorderRadius.circular(
                                      AppColors.cardRadius,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.badge_outlined,
                                        color: AppColors.primary,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Commissies',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
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
                              final members =
                                  _membersByCommittee[c] ?? const [];
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
                                        fontSize: 18,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (members.isEmpty)
                                      const Text(
                                        '—',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                        ),
                                      )
                                    else
                                      ...members.map((m) {
                                        final suffix =
                                            (m.function != null &&
                                                m.function!.isNotEmpty)
                                            ? ' (${m.function})'
                                            : '';
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '- ${m.name}$suffix',
                                                style: const TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                              ),
                                              if (m.email != null) ...[
                                                const SizedBox(height: 2),
                                                GestureDetector(
                                                  onTap: () =>
                                                      _openMail(m.email!),
                                                  child: Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.mail_outline,
                                                        size: 14,
                                                        color:
                                                            AppColors.primary,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        m.email!,
                                                        style: const TextStyle(
                                                          color:
                                                              AppColors.primary,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      }),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
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
  final String? email;

  const _CommitteeMember({
    required this.profileId,
    required this.name,
    required this.function,
    this.email,
  });
}
