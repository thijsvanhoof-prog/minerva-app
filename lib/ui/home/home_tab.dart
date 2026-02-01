import 'package:flutter/material.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/data/mock_home_data.dart';
import 'package:minerva_app/models/news_item.dart';
import 'package:minerva_app/ui/app_colors.dart';

/// Home-tab van VV Minerva. Stap voor stap herbouwd.
///
/// Stap 1: Minimale basis – scaffold, AppBar, welkomsttekst
/// Stap 2: Sectiestructuur – tabs voor Uitgelicht, Agenda, Nieuws
/// Stap 3: Uitgelicht – highlights laden (Supabase of mock) en horizontale kaarten
/// Stap 4: Agenda – agenda laden, kaarten, RSVP
/// Stap 5: Nieuwsberichten – NewsItem + mockNews (zoals oorspronkelijk)
/// Stap 6: Afronden – refresh, foutmeldingen, admin-actions (highlights)
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with SingleTickerProviderStateMixin {
  final SupabaseClient _client = Supabase.instance.client;

  late final TabController _tabController;

  bool _loadingHighlights = true;
  String? _highlightsError;
  List<_Highlight> _highlights = const [];

  bool _loadingAgenda = true;
  String? _agendaError;
  List<_AgendaItem> _agendaItems = const [];
  Set<int> _myRsvpAgendaIds = const {};

  bool _loadingNews = true;
  String? _newsError;
  List<NewsItem> _newsItems = const [];
  bool _newsFromSupabase = false;

  Future<void> _refreshHome() async {
    await _loadHighlights();
    await _loadAgenda();
    await _loadNews();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0);
    _loadHighlights();
    _loadAgenda();
    _loadNews();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHighlights() async {
    setState(() {
      _loadingHighlights = true;
      _highlightsError = null;
    });

    try {
      final res = await _client
          .from('home_highlights')
          .select('highlight_id, title, subtitle, icon_name')
          .order('created_at', ascending: false);

      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final list = rows.map((r) {
        return _Highlight(
          id: (r['highlight_id'] as num).toInt(),
          title: (r['title'] as String?) ?? '',
          subtitle: (r['subtitle'] as String?) ?? '',
          iconText: (r['icon_name'] as String?) ?? '🏐',
        );
      }).toList();

      setState(() {
        _highlights = list;
        _loadingHighlights = false;
      });
    } catch (e) {
      setState(() {
        _highlights = _mockHighlights();
        _highlightsError = e.toString();
        _loadingHighlights = false;
      });
    }
  }

  Future<void> _loadAgenda() async {
    setState(() {
      _loadingAgenda = true;
      _agendaError = null;
    });

    try {
      List<Map<String, dynamic>> rows = [];
      for (final attempt in const [
        ('agenda_id, title, description, start_datetime, end_datetime, location, can_rsvp', 'start_datetime'),
        ('agenda_id, title, description, start_datetime, location, can_rsvp', 'start_datetime'),
        ('agenda_id, title, start_datetime, end_datetime, location, can_rsvp', 'start_datetime'),
        ('agenda_id, title, start_datetime, location, can_rsvp', 'start_datetime'),
        ('agenda_id, title, starts_at, location, can_rsvp', 'starts_at'),
        ('agenda_id, title, start_at, location, can_rsvp', 'start_at'),
        ('agenda_id, title, when, where, can_rsvp', null),
        ('agenda_id, title, start_datetime, location', 'start_datetime'),
        ('agenda_id, title, starts_at, location', 'starts_at'),
        ('agenda_id, title, start_at, location', 'start_at'),
      ]) {
        try {
          final select = attempt.$1;
          final orderColumn = attempt.$2;
          final res = orderColumn == null
              ? await _client.from('home_agenda').select(select)
              : await _client
                  .from('home_agenda')
                  .select(select)
                  .order(orderColumn, ascending: true);
          rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
          break;
        } catch (_) {}
      }

      if (rows.isEmpty) {
        setState(() {
          _agendaItems = _mockAgenda();
          _myRsvpAgendaIds = const {};
          _loadingAgenda = false;
        });
        return;
      }

      final items = <_AgendaItem>[];
      for (final row in rows) {
        final id = (row['agenda_id'] as num?)?.toInt();
        if (id == null) continue;

        final title = (row['title'] as String?) ?? '';
        final description = (row['description'] as String?)?.trim();
        final canRsvp = (row['can_rsvp'] as bool?) ?? false;
        final location =
            (row['location'] ?? row['where'] ?? row['locatie'])?.toString() ?? '';

        DateTime? start;
        final rawStart = row['start_datetime'] ?? row['starts_at'] ?? row['start_at'];
        if (rawStart is DateTime) {
          start = rawStart;
        } else if (rawStart != null) {
          start = DateTime.tryParse(rawStart.toString());
        }

        DateTime? end;
        final rawEnd = row['end_datetime'] ?? row['ends_at'] ?? row['end_at'];
        if (rawEnd is DateTime) {
          end = rawEnd;
        } else if (rawEnd != null) {
          end = DateTime.tryParse(rawEnd.toString());
        }

        final whenLabel = start != null
            ? _formatDateTimeShort(start)
            : (row['when']?.toString() ?? '');
        final dateLabel = start != null ? _formatDate(start) : null;
        final timeLabel = start != null ? _formatTime(start) : null;
        final endDateLabel = end != null ? _formatDate(end) : null;
        final endTimeLabel = end != null ? _formatTime(end) : null;

        items.add(
          _AgendaItem(
            id: id,
            title: title,
            description: description != null && description.isNotEmpty ? description : null,
            when: whenLabel,
            where: location,
            canRsvp: canRsvp,
            startDatetime: start,
            endDatetime: end,
            dateLabel: dateLabel,
            timeLabel: timeLabel,
            endDateLabel: endDateLabel,
            endTimeLabel: endTimeLabel,
          ),
        );
      }

      final user = _client.auth.currentUser;
      final agendaIdsWithRsvp =
          items.where((a) => a.canRsvp).map((a) => a.id!).toList();
      Set<int> myRsvps = {};
      if (user != null && agendaIdsWithRsvp.isNotEmpty) {
        try {
          final res = await _client
              .from('home_agenda_rsvps')
              .select('agenda_id')
              .eq('profile_id', user.id)
              .inFilter('agenda_id', agendaIdsWithRsvp);
          final rsvpRows = (res as List<dynamic>).cast<Map<String, dynamic>>();
          myRsvps = rsvpRows
              .map((r) => (r['agenda_id'] as num?)?.toInt())
              .whereType<int>()
              .toSet();
        } catch (_) {}
      }

      setState(() {
        _agendaItems = items;
        _myRsvpAgendaIds = myRsvps;
        _loadingAgenda = false;
      });
    } catch (e) {
      setState(() {
        _agendaItems = _mockAgenda();
        _myRsvpAgendaIds = const {};
        _agendaError = e.toString();
        _loadingAgenda = false;
      });
    }
  }

  Future<void> _loadNews() async {
    setState(() {
      _loadingNews = true;
      _newsError = null;
    });

    try {
      final res = await _client
          .from('home_news')
          .select('news_id, title, description, created_at')
          .order('created_at', ascending: false);

      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      final list = <NewsItem>[];
      for (final r in rows) {
        final id = (r['news_id'] as num?)?.toInt();
        if (id == null) continue;
        final title = (r['title'] as String?) ?? '';
        final body = (r['description'] as String?) ?? '';
        DateTime? date;
        final raw = r['created_at'];
        if (raw is DateTime) {
          date = raw;
        } else if (raw != null) {
          date = DateTime.tryParse(raw.toString());
        }
        date ??= DateTime.now();
        list.add(NewsItem(
          id: id.toString(),
          title: title,
          body: body,
          date: date,
          author: 'Bestuur',
          category: NewsCategory.bestuur,
        ));
      }

      setState(() {
        _newsItems = list.isEmpty ? mockNews : list;
        _newsFromSupabase = list.isNotEmpty;
        _loadingNews = false;
      });
    } catch (e) {
      setState(() {
        _newsItems = mockNews;
        _newsFromSupabase = false;
        _newsError = e.toString();
        _loadingNews = false;
      });
    }
  }

  String _formatDateTimeShort(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year} • ${two(d.hour)}:${two(d.minute)}';
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year}';
  }

  String _formatTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _toggleAgendaRsvp(_AgendaItem item) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      showTopMessage(context, 'Log in om je aan te melden.', isError: true);
      return;
    }
    if (item.id == null) return;

    final isSignedUp = _myRsvpAgendaIds.contains(item.id);
    try {
      if (isSignedUp) {
        await _client
            .from('home_agenda_rsvps')
            .delete()
            .eq('agenda_id', item.id!)
            .eq('profile_id', user.id);
      } else {
        await _client.from('home_agenda_rsvps').insert({
          'agenda_id': item.id,
          'profile_id': user.id,
        });
      }

      setState(() {
        final next = {..._myRsvpAgendaIds};
        if (isSignedUp) {
          next.remove(item.id);
        } else {
          next.add(item.id!);
        }
        _myRsvpAgendaIds = next;
      });
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Aanmelding mislukt: $e', isError: true);
    }
  }

  void _showAgendaDetail(_AgendaItem item) {
    final hasAny = item.description != null ||
        item.dateLabel != null ||
        item.endDateLabel != null ||
        item.timeLabel != null ||
        item.endTimeLabel != null ||
        item.where.isNotEmpty;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.description != null && item.description!.isNotEmpty) ...[
                Text(
                  item.description!,
                  style: const TextStyle(color: AppColors.onBackground, height: 1.4),
                ),
                const SizedBox(height: 16),
              ],
              if (item.dateLabel != null) ...[
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      item.endDateLabel != null && item.endDateLabel != item.dateLabel
                          ? '${item.dateLabel!} t/m ${item.endDateLabel!}'
                          : item.dateLabel!,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (item.timeLabel != null) ...[
                Row(
                  children: [
                    Icon(Icons.schedule, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      item.endTimeLabel != null && item.endTimeLabel != item.timeLabel
                          ? '${item.timeLabel!} – ${item.endTimeLabel!}'
                          : item.timeLabel!,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (item.where.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.place, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.where,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              if (!hasAny)
                const Text('Geen extra informatie.', style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Sluiten'),
          ),
        ],
      ),
    );
  }

  void _showNewsDetail(NewsItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.title),
        content: SingleChildScrollView(
          child: Text(
            item.body,
            style: const TextStyle(color: AppColors.onBackground, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Sluiten'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddNewsDialog() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Nieuwsbericht toevoegen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Titel *',
                hintText: 'bijv. Update vanuit het bestuur',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Beschrijving',
                hintText: 'Volledige tekst van het bericht',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isEmpty) return;
              Navigator.of(context).pop(true);
            },
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleController.dispose();
      descriptionController.dispose();
    });

    if (ok != true) return;

    final title = titleController.text.trim();
    if (title.isEmpty) return;

    try {
      await _client.from('home_news').insert({
        'title': title,
        'description': descriptionController.text.trim(),
      });
      await _loadNews();
      if (!mounted) return;
      showTopMessage(context, 'Nieuwsbericht toegevoegd.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Opslaan mislukt: $e', isError: true);
    }
  }

  Future<void> _openEditNewsDialog(NewsItem existing) async {
    final newsId = int.tryParse(existing.id);
    if (newsId == null) return;

    final titleController = TextEditingController(text: existing.title);
    final descriptionController = TextEditingController(text: existing.body);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Nieuwsbericht aanpassen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Titel *',
                hintText: 'bijv. Update vanuit het bestuur',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Beschrijving',
                hintText: 'Volledige tekst van het bericht',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isEmpty) return;
              Navigator.of(context).pop(true);
            },
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleController.dispose();
      descriptionController.dispose();
    });

    if (ok != true) return;

    final title = titleController.text.trim();
    if (title.isEmpty) return;

    try {
      await _client.from('home_news').update({
        'title': title,
        'description': descriptionController.text.trim(),
      }).eq('news_id', newsId);
      await _loadNews();
      if (!mounted) return;
      showTopMessage(context, 'Nieuwsbericht aangepast.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Opslaan mislukt: $e', isError: true);
    }
  }

  Future<void> _deleteNewsItem(NewsItem item) async {
    final newsId = int.tryParse(item.id);
    if (newsId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nieuwsbericht verwijderen'),
        content: Text(
          'Weet je zeker dat je "${item.title}" wilt verwijderen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _client.from('home_news').delete().eq('news_id', newsId);
      await _loadNews();
      if (!mounted) return;
      showTopMessage(context, 'Nieuwsbericht verwijderd.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Verwijderen mislukt: $e', isError: true);
    }
  }

  Future<void> _openAddAgendaDialog() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final locationController = TextEditingController();
    DateTime? pickedDateTime;
    DateTime? pickedEndDateTime;
    bool canRsvp = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            String two(int v) => v.toString().padLeft(2, '0');
            String dateStr(DateTime? dt) => dt == null
                ? 'Niet gekozen'
                : '${two(dt.day)}-${two(dt.month)}-${dt.year}';
            String timeStr(DateTime? dt) => dt == null
                ? 'Niet gekozen'
                : '${two(dt.hour)}:${two(dt.minute)}';

            return AlertDialog(
              scrollable: true,
              title: const Text('Activiteit toevoegen'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Titel *',
                      hintText: 'bijv. Algemene ledenvergadering',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Beschrijving',
                      hintText: 'Alleen zichtbaar bij Lees meer',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Begindatum', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(dateStr(pickedDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            initialDate: pickedDateTime ?? now,
                            firstDate: now.subtract(const Duration(days: 365)),
                            lastDate: now.add(const Duration(days: 365 * 2)),
                          );
                          if (d == null) return;
                          setState(() {
                            pickedDateTime = DateTime(
                              d.year, d.month, d.day,
                              pickedDateTime?.hour ?? 0, pickedDateTime?.minute ?? 0,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Begintijd', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(timeStr(pickedDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: pickedDateTime != null
                                ? TimeOfDay(hour: pickedDateTime!.hour, minute: pickedDateTime!.minute)
                                : const TimeOfDay(hour: 20, minute: 0),
                          );
                          if (t == null) return;
                          setState(() {
                            pickedDateTime = DateTime(
                              pickedDateTime?.year ?? DateTime.now().year,
                              pickedDateTime?.month ?? DateTime.now().month,
                              pickedDateTime?.day ?? DateTime.now().day,
                              t.hour, t.minute,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Einddatum', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(dateStr(pickedEndDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final startOrNow = pickedDateTime ?? now;
                          final d = await showDatePicker(
                            context: context,
                            initialDate: pickedEndDateTime ?? pickedDateTime ?? now,
                            firstDate: startOrNow,
                            lastDate: now.add(const Duration(days: 365 * 2)),
                          );
                          if (d == null) return;
                          setState(() {
                            pickedEndDateTime = DateTime(
                              d.year, d.month, d.day,
                              pickedEndDateTime?.hour ?? 23, pickedEndDateTime?.minute ?? 59,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Eindtijd', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(timeStr(pickedEndDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: pickedEndDateTime != null
                                ? TimeOfDay(hour: pickedEndDateTime!.hour, minute: pickedEndDateTime!.minute)
                                : const TimeOfDay(hour: 22, minute: 0),
                          );
                          if (t == null) return;
                          setState(() {
                            pickedEndDateTime = DateTime(
                              pickedEndDateTime?.year ?? DateTime.now().year,
                              pickedEndDateTime?.month ?? DateTime.now().month,
                              pickedEndDateTime?.day ?? DateTime.now().day,
                              t.hour, t.minute,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Locatie',
                      hintText: 'bijv. Kantine',
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: canRsvp,
                    onChanged: (v) => setState(() => canRsvp = v ?? false),
                    title: const Text('Aanmelden mogelijk'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuleren'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (titleController.text.trim().isEmpty) return;
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Opslaan'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleController.dispose();
      descriptionController.dispose();
      locationController.dispose();
    });

    if (ok != true) return;

    final title = titleController.text.trim();
    if (title.isEmpty) return;

    try {
      final payload = <String, dynamic>{
        'title': title,
        'description': descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
        'location': locationController.text.trim().isEmpty ? null : locationController.text.trim(),
        'can_rsvp': canRsvp,
      };
      if (pickedDateTime != null) {
        payload['start_datetime'] = pickedDateTime!.toUtc().toIso8601String();
      }
      if (pickedEndDateTime != null) {
        payload['end_datetime'] = pickedEndDateTime!.toUtc().toIso8601String();
      }
      await _client.from('home_agenda').insert(payload);
      await _loadAgenda();
      if (!mounted) return;
      showTopMessage(context, 'Activiteit toegevoegd.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Opslaan mislukt: $e', isError: true);
    }
  }

  Future<void> _openEditAgendaDialog(_AgendaItem existing) async {
    if (existing.id == null) return;

    final titleController = TextEditingController(text: existing.title);
    final descriptionController = TextEditingController(text: existing.description ?? '');
    final locationController = TextEditingController(text: existing.where);
    DateTime? pickedDateTime = existing.startDatetime?.toLocal();
    DateTime? pickedEndDateTime = existing.endDatetime?.toLocal();
    bool canRsvp = existing.canRsvp;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            String two(int v) => v.toString().padLeft(2, '0');
            String dateStr(DateTime? dt) => dt == null
                ? 'Niet gekozen'
                : '${two(dt.day)}-${two(dt.month)}-${dt.year}';
            String timeStr(DateTime? dt) => dt == null
                ? 'Niet gekozen'
                : '${two(dt.hour)}:${two(dt.minute)}';

            return AlertDialog(
              scrollable: true,
              title: const Text('Activiteit aanpassen'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Titel *',
                      hintText: 'bijv. Algemene ledenvergadering',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Beschrijving',
                      hintText: 'Alleen zichtbaar bij Lees meer',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Begindatum', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(dateStr(pickedDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            initialDate: pickedDateTime ?? now,
                            firstDate: now.subtract(const Duration(days: 365)),
                            lastDate: now.add(const Duration(days: 365 * 2)),
                          );
                          if (d == null) return;
                          setState(() {
                            pickedDateTime = DateTime(
                              d.year, d.month, d.day,
                              pickedDateTime?.hour ?? 0, pickedDateTime?.minute ?? 0,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Begintijd', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(timeStr(pickedDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: pickedDateTime != null
                                ? TimeOfDay(hour: pickedDateTime!.hour, minute: pickedDateTime!.minute)
                                : const TimeOfDay(hour: 20, minute: 0),
                          );
                          if (t == null) return;
                          setState(() {
                            pickedDateTime = DateTime(
                              pickedDateTime?.year ?? DateTime.now().year,
                              pickedDateTime?.month ?? DateTime.now().month,
                              pickedDateTime?.day ?? DateTime.now().day,
                              t.hour, t.minute,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Einddatum', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(dateStr(pickedEndDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            initialDate: pickedEndDateTime ?? pickedDateTime ?? now,
                            firstDate: now.subtract(const Duration(days: 365)),
                            lastDate: now.add(const Duration(days: 365 * 2)),
                          );
                          if (d == null) return;
                          setState(() {
                            pickedEndDateTime = DateTime(
                              d.year, d.month, d.day,
                              pickedEndDateTime?.hour ?? 23, pickedEndDateTime?.minute ?? 59,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Eindtijd', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            const SizedBox(height: 4),
                            Text(timeStr(pickedEndDateTime), style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: pickedEndDateTime != null
                                ? TimeOfDay(hour: pickedEndDateTime!.hour, minute: pickedEndDateTime!.minute)
                                : const TimeOfDay(hour: 22, minute: 0),
                          );
                          if (t == null) return;
                          setState(() {
                            pickedEndDateTime = DateTime(
                              pickedEndDateTime?.year ?? DateTime.now().year,
                              pickedEndDateTime?.month ?? DateTime.now().month,
                              pickedEndDateTime?.day ?? DateTime.now().day,
                              t.hour, t.minute,
                            );
                          });
                        },
                        child: const Text('Kies'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Locatie',
                      hintText: 'bijv. Kantine',
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: canRsvp,
                    onChanged: (v) => setState(() => canRsvp = v ?? false),
                    title: const Text('Aanmelden mogelijk'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuleren'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (titleController.text.trim().isEmpty) return;
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Opslaan'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleController.dispose();
      descriptionController.dispose();
      locationController.dispose();
    });

    if (ok != true) return;

    final title = titleController.text.trim();
    if (title.isEmpty) return;

    try {
      final payload = <String, dynamic>{
        'title': title,
        'description': descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
        'location': locationController.text.trim().isEmpty ? null : locationController.text.trim(),
        'can_rsvp': canRsvp,
      };
      if (pickedDateTime != null) {
        payload['start_datetime'] = pickedDateTime!.toUtc().toIso8601String();
      }
      if (pickedEndDateTime != null) {
        payload['end_datetime'] = pickedEndDateTime!.toUtc().toIso8601String();
      } else {
        payload['end_datetime'] = null;
      }
      await _client.from('home_agenda').update(payload).eq('agenda_id', existing.id!);
      await _loadAgenda();
      if (!mounted) return;
      showTopMessage(context, 'Activiteit aangepast.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Opslaan mislukt: $e', isError: true);
    }
  }

  Future<void> _deleteAgendaItem(_AgendaItem item) async {
    if (item.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activiteit verwijderen'),
        content: Text(
          'Weet je zeker dat je "${item.title}" wilt verwijderen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _client.from('home_agenda').delete().eq('agenda_id', item.id!);
      await _loadAgenda();
      if (!mounted) return;
      showTopMessage(context, 'Activiteit verwijderd.');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Verwijderen mislukt: $e', isError: true);
    }
  }

  Future<void> _upsertHighlight({
    int? id,
    required String title,
    required String subtitle,
    required String iconText,
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      'subtitle': subtitle,
      'icon_name': iconText,
    };
    if (id == null) {
      await _client.from('home_highlights').insert(payload);
    } else {
      await _client
          .from('home_highlights')
          .update(payload)
          .eq('highlight_id', id);
    }
  }

  Future<void> _deleteHighlight(int id) async {
    await _client.from('home_highlights').delete().eq('highlight_id', id);
  }

  Future<void> _openEditHighlightDialog({
    required bool canManage,
    _Highlight? existing,
  }) async {
    if (!canManage) return;

    final titleController = TextEditingController(text: existing?.title ?? '');
    final subtitleController =
        TextEditingController(text: existing?.subtitle ?? '');
    final iconController =
        TextEditingController(text: existing?.iconText ?? '🏐');

    final result = await showDialog<_HighlightEditResult>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(existing == null ? 'Punt toevoegen' : 'Punt aanpassen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Titel'),
            ),
            TextField(
              controller: subtitleController,
              decoration: const InputDecoration(labelText: 'Tekst'),
            ),
            TextField(
              controller: iconController,
              decoration: const InputDecoration(
                labelText: 'Icoon (emoji/tekst)',
                hintText: '🏐',
              ),
            ),
          ],
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(const _HighlightEditResult.delete()),
              child: const Text('Verwijderen'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Annuleren'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(
              _HighlightEditResult.save(
                titleController.text.trim(),
                subtitleController.text.trim(),
                iconController.text.trim(),
              ),
            ),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );

    // Disposal uitstellen tot na sluiting dialoog; anders "used after being disposed".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleController.dispose();
      subtitleController.dispose();
      iconController.dispose();
    });

    if (result == null) return;

    try {
      if (result.isDelete && existing != null) {
        await _deleteHighlight(existing.id ?? 0);
      } else if (result.isSave) {
        final title = result.title ?? '';
        if (title.isEmpty) return;
        await _upsertHighlight(
          id: existing?.id,
          title: title,
          subtitle: result.subtitle ?? '',
          iconText:
              (result.iconText?.isNotEmpty == true) ? result.iconText! : '🏐',
        );
      }
      await _loadHighlights();
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Opslaan mislukt: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userContext = AppUserContext.of(context);
    final canManageHighlights = userContext.canManageHighlights;
    final canManageAgenda = userContext.canManageAgenda;
    final canManageNews = userContext.canManageNews;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.darkBlue,
                  borderRadius: BorderRadius.circular(AppColors.cardRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welkom bij VV Minerva',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Updates, agenda en nieuws vanuit de vereniging.',
                      style: TextStyle(
                        color: AppColors.primary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: AppColors.darkBlue,
                    borderRadius: BorderRadius.circular(AppColors.cardRadius),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: const [
                    Tab(text: 'Uitgelicht'),
                    Tab(text: 'Agenda'),
                    Tab(text: 'Nieuws'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Uitgelicht
                  RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _refreshHome,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      children: [
                        _HomeTabHeader(
                          title: 'Uitgelicht',
                          trailing: canManageHighlights
                              ? IconButton(
                                  tooltip: 'Punt toevoegen',
                                  icon: const Icon(Icons.add_circle_outline),
                                  color: AppColors.primary,
                                  onPressed: () => _openEditHighlightDialog(
                                    canManage: true,
                                    existing: null,
                                  ),
                                )
                              : (_loadingHighlights
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary,
                                      ),
                                    )
                                  : null),
                        ),
                        const SizedBox(height: 12),
                        if (_highlightsError != null && canManageHighlights)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Let op: highlights tabel niet beschikbaar.\n'
                              'Voer supabase/home_highlights_minimal.sql uit in Supabase → SQL Editor.\n'
                              'Details: $_highlightsError',
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        SizedBox(
                          height: 135,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _highlights.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 12),
                            itemBuilder: (_, i) => SizedBox(
                              width: 260,
                              child: _HighlightCard(
                                item: _highlights[i],
                                canManage: canManageHighlights,
                                onEdit: () => _openEditHighlightDialog(
                                  canManage: canManageHighlights,
                                  existing: _highlights[i],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Agenda
                  RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _refreshHome,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      itemCount: 1 + (_agendaItems.isEmpty ? 1 : _agendaItems.length),
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return _HomeTabHeader(
                            title: 'Agenda',
                            trailing: canManageAgenda
                                ? IconButton(
                                    tooltip: 'Activiteit toevoegen',
                                    icon: const Icon(Icons.add_circle_outline),
                                    color: AppColors.primary,
                                    onPressed: () => _openAddAgendaDialog(),
                                  )
                                : (_loadingAgenda
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      )
                                    : null),
                          );
                        }

                        if (_agendaItems.isEmpty) {
                          if (_agendaError != null && canManageAgenda) {
                            return Text(
                              'Let op: agenda tabel/RSVP niet beschikbaar.\n'
                              'Voeg Supabase tabellen `home_agenda` + `home_agenda_rsvps` toe.\n'
                              'Details: $_agendaError',
                              style: const TextStyle(color: AppColors.textSecondary),
                            );
                          }
                          return const Text(
                            'Geen items in de agenda.',
                            style: TextStyle(color: AppColors.textSecondary),
                          );
                        }

                        final item = _agendaItems[i - 1];
                        final signedUp = item.id != null && _myRsvpAgendaIds.contains(item.id);
                        final enabled = item.canRsvp && item.id != null;
                        return _AgendaCard(
                          item: item,
                          signedUp: signedUp,
                          enabled: enabled,
                          canManage: canManageAgenda,
                          onToggleRsvp: () => _toggleAgendaRsvp(item),
                          onReadMore: () => _showAgendaDetail(item),
                          onEdit: item.id != null ? () => _openEditAgendaDialog(item) : null,
                          onDelete: item.id != null ? () => _deleteAgendaItem(item) : null,
                        );
                      },
                    ),
                  ),

                  // Nieuws
                  RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _refreshHome,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      itemCount: 1 + (_newsItems.isEmpty ? 1 : _newsItems.length),
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return _HomeTabHeader(
                            title: 'Nieuws',
                            trailing: canManageNews
                                ? IconButton(
                                    tooltip: 'Nieuwsbericht toevoegen',
                                    icon: const Icon(Icons.add_circle_outline),
                                    color: AppColors.primary,
                                    onPressed: () => _openAddNewsDialog(),
                                  )
                                : (_loadingNews
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      )
                                    : null),
                          );
                        }

                        if (_newsItems.isEmpty) {
                          if (_newsError != null && canManageNews) {
                            return Text(
                              'Let op: nieuwstabel niet beschikbaar. '
                              'Voer supabase/home_news_minimal.sql uit in Supabase → SQL Editor.\n'
                              'Details: $_newsError',
                              style: const TextStyle(color: AppColors.textSecondary),
                            );
                          }
                          return const Text(
                            'Geen nieuwsberichten gevonden.',
                            style: TextStyle(color: AppColors.textSecondary),
                          );
                        }

                        final n = _newsItems[i - 1];
                        return _NewsCard(
                          item: n,
                          canManage: canManageNews,
                          onReadMore: _needsLeesMeer(n) ? () => _showNewsDetail(n) : null,
                          onEdit: _newsFromSupabase ? () => _openEditNewsDialog(n) : null,
                          onDelete: _newsFromSupabase ? () => _deleteNewsItem(n) : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ----------------------- SECTIE-TITEL ----------------------- */

class _HomeTabHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _HomeTabHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkBlue,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/* ----------------------- KAART-WRAPPER ----------------------- */

class _CardBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const _CardBox({
    required this.child,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(14),
      child: child,
    );
  }
}

/* ----------------------- HIGHLIGHTS ----------------------- */

class _Highlight {
  final int? id;
  final String title;
  final String subtitle;
  final String iconText;

  const _Highlight({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconText,
  });
}

class _HighlightCard extends StatelessWidget {
  final _Highlight item;
  final bool canManage;
  final VoidCallback? onEdit;

  const _HighlightCard({
    required this.item,
    required this.canManage,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.iconText, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.onBackground,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.subtitle,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (canManage && onEdit != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 1),
              tooltip: 'Meer opties',
              onSelected: (v) {
                if (v == 'edit') onEdit?.call();
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20, color: AppColors.textSecondary),
                      SizedBox(width: 8),
                      Text('Bewerken'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HighlightEditResult {
  final bool isSave;
  final bool isDelete;
  final String? title;
  final String? subtitle;
  final String? iconText;

  const _HighlightEditResult._({
    required this.isSave,
    required this.isDelete,
    this.title,
    this.subtitle,
    this.iconText,
  });

  const _HighlightEditResult.delete()
      : this._(
          isSave: false,
          isDelete: true,
          title: null,
          subtitle: null,
          iconText: null,
        );

  const _HighlightEditResult.save(
    String title,
    String subtitle,
    String iconText,
  ) : this._(
          isSave: true,
          isDelete: false,
          title: title,
          subtitle: subtitle,
          iconText: iconText,
        );
}

List<_Highlight> _mockHighlights() => const [
      _Highlight(
        id: null,
        iconText: '📌',
        title: 'Seizoensstart',
        subtitle: 'Belangrijke clubafspraken en planning',
      ),
      _Highlight(
        id: null,
        iconText: '🏆',
        title: 'Toernooi',
        subtitle: 'Inschrijving geopend (jeugd & senioren)',
      ),
      _Highlight(
        id: null,
        iconText: '🤝',
        title: 'Vrijwilligers gezocht',
        subtitle: 'Tafelaars en scheidsrechters nodig',
      ),
    ];

/* ----------------------- AGENDA ----------------------- */

class _AgendaItem {
  final int? id;
  final String title;
  final String? description;
  final String when;
  final String where;
  final bool canRsvp;
  final DateTime? startDatetime;
  final DateTime? endDatetime;
  final String? dateLabel;
  final String? timeLabel;
  final String? endDateLabel;
  final String? endTimeLabel;

  const _AgendaItem({
    required this.id,
    required this.title,
    this.description,
    required this.when,
    required this.where,
    required this.canRsvp,
    this.startDatetime,
    this.endDatetime,
    this.dateLabel,
    this.timeLabel,
    this.endDateLabel,
    this.endTimeLabel,
  });
}

class _AgendaCard extends StatelessWidget {
  final _AgendaItem item;
  final bool signedUp;
  final bool enabled;
  final bool canManage;
  final VoidCallback onToggleRsvp;
  final VoidCallback onReadMore;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _AgendaCard({
    required this.item,
    required this.signedUp,
    required this.enabled,
    required this.canManage,
    required this.onToggleRsvp,
    required this.onReadMore,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Einddatum/eindtijd alleen tonen als expliciet ingesteld én anders dan begin.
    // Geen einddatum → niet weergeven;zelfde dag → alleen begindatum, geen "t/m".
    final dateLine = item.dateLabel != null
        ? (item.endDateLabel != null && item.endDateLabel != item.dateLabel
            ? '${item.dateLabel!} t/m ${item.endDateLabel!}'
            : item.dateLabel!)
        : null;
    final timeRange = item.timeLabel != null
        ? (item.endTimeLabel != null && item.endTimeLabel != item.timeLabel
            ? '${item.timeLabel!} – ${item.endTimeLabel!}'
            : item.timeLabel!)
        : null;
    final timeLocation = timeRange != null
        ? [timeRange, item.where].where((s) => s.isNotEmpty).join(' • ')
        : [item.when, item.where].where((s) => s.isNotEmpty).join(' • ');
    final showMenu = canManage && (onEdit != null || onDelete != null);
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        );

    return _CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.onBackground,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (dateLine != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(dateLine, style: secondaryStyle),
                        ],
                      ),
                    ],
                    if (timeLocation.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(timeLocation, style: secondaryStyle),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (showMenu)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 1),
                  tooltip: 'Meer opties',
                  onSelected: (v) {
                    if (v == 'edit') onEdit?.call();
                    if (v == 'delete') onDelete?.call();
                  },
                  itemBuilder: (context) => [
                    if (onEdit != null)
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20, color: AppColors.textSecondary),
                            SizedBox(width: 8),
                            Text('Bewerken'),
                          ],
                        ),
                      ),
                    if (onDelete != null)
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                            SizedBox(width: 8),
                            Text('Verwijderen', style: TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (item.canRsvp) ...[
                SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: enabled ? onToggleRsvp : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(signedUp ? 'Afmelden' : 'Aanmelden'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              TextButton(
                onPressed: onReadMore,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Lees meer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

List<_AgendaItem> _mockAgenda() => const [
      _AgendaItem(
        id: null,
        title: 'Algemene ledenvergadering',
        description: 'Jaarlijkse ALV met stemming over het jaarverslag.',
        when: 'Ma 15 jan • 20:00',
        where: 'Kantine',
        canRsvp: false,
        startDatetime: null,
        endDatetime: null,
        dateLabel: '15-01-2025',
        timeLabel: '20:00',
        endDateLabel: null,
        endTimeLabel: null,
      ),
      _AgendaItem(
        id: null,
        title: 'Clubdag',
        description: 'Sportieve dag voor jeugd en senioren.',
        when: 'Za 10 feb • 10:00',
        where: 'Sporthal',
        canRsvp: true,
        startDatetime: null,
        endDatetime: null,
        dateLabel: '10-02-2025',
        timeLabel: '10:00',
        endDateLabel: null,
        endTimeLabel: null,
      ),
    ];

/* ----------------------- NIEUWS ----------------------- */

/// Ongeveer 3 regels tekst (~40 karakters per regel). Bij overschrijding "Lees meer" tonen.
const int _newsBodyLeesMeerThreshold = 120;

bool _needsLeesMeer(NewsItem item) =>
    item.body.trim().length > _newsBodyLeesMeerThreshold;

String _newsDateLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(d.year, d.month, d.day);
  final diff = today.difference(date).inDays;
  if (diff == 0) return 'Vandaag';
  if (diff == 1) return 'Gisteren';
  if (diff < 7) return '$diff dagen geleden';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}-${two(d.month)}-${d.year}';
}

class _NewsCard extends StatelessWidget {
  final NewsItem item;
  final bool canManage;
  final VoidCallback? onReadMore;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _NewsCard({
    required this.item,
    required this.canManage,
    this.onReadMore,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final showMenu = canManage;
    final canEdit = onEdit != null;
    final canDelete = onDelete != null;

    return _CardBox(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(item.category.label),
              _Pill(item.author),
              Text(
                _newsDateLabel(item.date),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.onBackground,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (showMenu)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 1),
                  tooltip: 'Meer opties',
                  onSelected: (v) {
                    if (v == 'edit') onEdit?.call();
                    if (v == 'delete') onDelete?.call();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'edit',
                      enabled: canEdit,
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20, color: canEdit ? AppColors.textSecondary : AppColors.textSecondary.withValues(alpha: 0.5)),
                          const SizedBox(width: 8),
                          Text('Bewerken'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      enabled: canDelete,
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 20, color: canDelete ? AppColors.error : AppColors.error.withValues(alpha: 0.5)),
                          const SizedBox(width: 8),
                          Text('Verwijderen', style: TextStyle(color: canDelete ? AppColors.error : AppColors.error.withValues(alpha: 0.5))),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.body,
            maxLines: onReadMore != null ? 3 : null,
            overflow: onReadMore != null ? TextOverflow.ellipsis : null,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (onReadMore != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                ),
                onPressed: onReadMore,
                child: const Text('Lees meer'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;

  const _Pill(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.45),
          width: 1.4,
        ),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.onBackground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
