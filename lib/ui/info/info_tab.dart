import 'package:flutter/material.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/tab_page_header.dart';
import 'package:minerva_app/ui/display_name_overrides.dart' show applyDisplayNameOverrides, unknownUserName;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/committees/committee_normalization.dart';

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
  final Map<String, _CommitteeContactSettings> _contactSettingsByCommittee = {};

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
      _contactSettingsByCommittee.clear();
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

      final contactSettings = await _loadCommitteeContactSettings();
      if (rows.isEmpty && contactSettings.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loadingCommittees = false;
        });
        return;
      }

      final committeeKeys = <String>{...contactSettings.keys};
      final committeeDisplayNames = <String, String>{};
      final profileIds = <String>{};
      for (final row in rows) {
        final rawName = row['committee_name']?.toString().trim() ?? '';
        if (rawName.isEmpty) continue;
        final key = _resolveInfoCommitteeKey(rawName);
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
        final key = _resolveInfoCommitteeKey(rawName);

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
        'jeugdcommissie',
      ];
      final indexByKey = <String, int>{
        for (var i = 0; i < visibleOrder.length; i++) visibleOrder[i]: i,
      };
      list.removeWhere((k) => !(contactSettings[k]?.showInContact ?? true));
      list.sort((a, b) {
        final sa = contactSettings[a]?.sortOrder;
        final sb = contactSettings[b]?.sortOrder;
        if (sa != null || sb != null) {
          final va = sa ?? 999999;
          final vb = sb ?? 999999;
          if (va != vb) return va.compareTo(vb);
        }
        final ia = indexByKey[a] ?? 999;
        final ib = indexByKey[b] ?? 999;
        if (ia != ib) return ia.compareTo(ib);
        return _committeeLabel(a).toLowerCase().compareTo(_committeeLabel(b).toLowerCase());
      });

      if (!mounted) return;
      setState(() {
        _committees.addAll(list);
        _committeeDisplayName.addAll(committeeDisplayNames);
        _contactSettingsByCommittee.addAll(contactSettings);
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

  bool _isMissingColumnError(PostgrestException e) {
    return e.code == 'PGRST204' ||
        e.message.contains('column') ||
        e.message.contains('Could not find the');
  }

  List<String> _parseEmails(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.contains('@'))
          .toSet()
          .toList();
    }
    return raw
        .toString()
        .split(RegExp(r'[,;\n]'))
        .map((e) => e.trim())
        .where((e) => e.contains('@'))
        .toSet()
        .toList();
  }

  bool _parseShowInContact(dynamic raw) {
    if (raw is bool) return raw;
    if (raw == null) return true;
    final value = raw.toString().trim().toLowerCase();
    if (value.isEmpty) return true;
    return value == 'true' || value == '1' || value == 'yes' || value == 'ja';
  }

  int? _parseSortOrder(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString().trim());
  }

  Future<Map<String, _CommitteeContactSettings>> _loadCommitteeContactSettings() async {
    List<Map<String, dynamic>> rows = const [];
    for (final select in const [
      'committee_key, display_name, show_in_contact, contact_emails, sort_order',
      'committee_key, display_name, show_in_contact, sort_order',
      'committee_key, display_name, sort_order',
      'committee_key, show_in_contact, contact_emails, sort_order',
      'committee_key, show_in_contact, sort_order',
      'committee_key, sort_order',
      'committee_key',
    ]) {
      try {
        final res = await _client.from('committee_contact_settings').select(select);
        rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
        break;
      } on PostgrestException catch (e) {
        if (_isMissingColumnError(e)) continue;
      } catch (_) {
        break;
      }
    }

    final settings = <String, _CommitteeContactSettings>{};
    for (final row in rows) {
      final rawName = (row['committee_key'] ?? row['display_name'] ?? '')
          .toString()
          .trim();
      if (rawName.isEmpty) continue;
      final key = _resolveInfoCommitteeKey(rawName);
      if (key.isEmpty) continue;
      final emails = <String>{
        ..._parseEmails(row['contact_emails']),
      }.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      settings[key] = _CommitteeContactSettings(
        showInContact: _parseShowInContact(row['show_in_contact']),
        emails: emails,
        sortOrder: _parseSortOrder(row['sort_order']),
      );
    }
    return settings;
  }

  String _resolveInfoCommitteeKey(String value) {
    final c = value.trim().toLowerCase();
    if (c.isEmpty) return '';
    final key = normalizeCommitteeKey(value);
    if (key != 'bestuur' &&
        (c.contains('algemeen') || c.contains('secretariaat'))) {
      return 'secretariaat';
    }
    return key;
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
      case 'jeugdcommissie':
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
                              final contactEmails =
                                  _contactSettingsByCommittee[c]?.emails ?? const <String>[];
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
                                    if (contactEmails.isNotEmpty) ...[
                                      ...contactEmails.map(
                                        (email) => Padding(
                                          padding: const EdgeInsets.only(bottom: 4),
                                          child: GestureDetector(
                                            onTap: () => _openMail(email),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.mail_outline,
                                                  size: 14,
                                                  color: AppColors.primary,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  email,
                                                  style: const TextStyle(
                                                    color: AppColors.primary,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                    ],
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
                                              if (contactEmails.isEmpty && m.email != null) ...[
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

class _CommitteeContactSettings {
  final bool showInContact;
  final List<String> emails;
  final int? sortOrder;

  const _CommitteeContactSettings({
    required this.showInContact,
    required this.emails,
    this.sortOrder,
  });
}
