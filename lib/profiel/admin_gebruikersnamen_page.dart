import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/branded_background.dart';
import 'package:minerva_app/ui/components/glass_card.dart';

/// Alleen voor admins: bekijk en wijzig gebruikersnamen (display_name) van leden.
class AdminGebruikersnamenPage extends StatefulWidget {
  const AdminGebruikersnamenPage({super.key});

  @override
  State<AdminGebruikersnamenPage> createState() => _AdminGebruikersnamenPageState();
}

class _AdminGebruikersnamenPageState extends State<AdminGebruikersnamenPage> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<_ProfileRow> _profiles = const [];
  String _query = '';

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

  Future<void> _changeNameFor(_ProfileRow profile) async {
    final controller = TextEditingController(text: profile.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gebruikersnaam wijzigen'),
        content: Column(
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
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nieuwe gebruikersnaam',
                hintText: 'Naam zoals anderen deze persoon zien',
              ),
            ),
          ],
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

    try {
      await _client
          .from('profiles')
          .update({'display_name': newName})
          .eq('id', profile.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gebruikersnaam is bijgewerkt.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kon gebruikersnaam niet wijzigen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Gebruikersnamen beheren'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: BrandedBackground(
        child: RefreshIndicator(
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
                    padding: const EdgeInsets.all(16),
                    children: [
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
                        ..._filtered.map((p) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GlassCard(
                              child: ListTile(
                                leading: const Icon(
                                  Icons.badge_outlined,
                                  color: AppColors.iconMuted,
                                ),
                                title: Text(
                                  p.displayName.isEmpty ? p.email : p.displayName,
                                  style: const TextStyle(
                                    color: AppColors.onBackground,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: p.displayName.isNotEmpty && p.email.isNotEmpty
                                    ? Text(
                                        p.email,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                        ),
                                      )
                                    : null,
                                trailing: const Icon(
                                  Icons.edit_outlined,
                                  color: AppColors.primary,
                                ),
                                onTap: () => _changeNameFor(p),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
        ),
      ),
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
