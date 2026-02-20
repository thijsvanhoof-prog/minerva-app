import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:minerva_app/ui/notifications/notification_service.dart';
import 'package:minerva_app/utils/dutch_holidays.dart';

class AddTrainingPage extends StatefulWidget {
  final List<TeamMembership> manageableTeams;

  const AddTrainingPage({
    super.key,
    required this.manageableTeams,
  });

  @override
  State<AddTrainingPage> createState() => _AddTrainingPageState();
}

class _AddTrainingPageState extends State<AddTrainingPage> {
  final _client = Supabase.instance.client;

  static const List<String> _locations = [
    'De Dillenburcht',
    'Die Heygrave',
    'De Vennen',
    'De Brug',
    'De Kubus',
    'De Plek',
  ];
  String _selectedLocation = _locations.first;

  DateTime _selectedDate = DateTime.now();
  DateTime? _endDate; // null = één training, anders reeks tot einddatum
  TimeOfDay _startTime = const TimeOfDay(hour: 20, minute: 30);
  TimeOfDay _endTime = const TimeOfDay(hour: 22, minute: 30);

  /// Welke weekdagen hebben training (1=ma, 7=zo). Leeg = alle dagen.
  Set<int> _selectedWeekdays = {1, 2, 3, 4, 5, 6, 7};

  /// Feestdagen (zoals Kerst, Pasen) overslaan bij meerdere trainingen.
  bool _excludeHolidays = false;

  /// Specifieke data uitsluiten van de reeks (bijv. 9 feb, 16 feb, 6 apr).
  final Set<DateTime> _excludedDates = {};

  bool _saving = false;
  int? _selectedTeamId;

  @override
  void initState() {
    super.initState();
    if (widget.manageableTeams.isNotEmpty) {
      _selectedTeamId = widget.manageableTeams.first.teamId;
    }
    _endTime = _defaultEndTime(_startTime);
  }

  @override
  void dispose() {
    super.dispose();
  }

  String get _uid => _client.auth.currentUser!.id;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('nl', 'NL'),
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.background,
            onSurface: AppColors.onBackground,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('nl', 'NL'),
      initialDate: _endDate ?? _selectedDate,
      firstDate: _selectedDate,
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.background,
            onSurface: AppColors.onBackground,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  void _clearEndDate() {
    setState(() {
      _endDate = null;
      _excludedDates.clear();
    });
  }

  Future<void> _addExcludedDate() async {
    final rangeStart = _selectedDate;
    final rangeEnd = _endDate ?? _selectedDate;
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('nl', 'NL'),
      initialDate: rangeStart,
      firstDate: rangeStart,
      lastDate: rangeEnd,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.background,
            onSurface: AppColors.onBackground,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _excludedDates.add(DateTime(picked.year, picked.month, picked.day));
      });
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await _pickTimeTyped(
      title: 'Starttijd',
      current: _startTime,
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
        // Keep end time sensible when creating new trainings.
        if (_combine(_selectedDate, _endTime)
            .isBefore(_combine(_selectedDate, _startTime))) {
          _endTime = _defaultEndTime(_startTime);
        }
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await _pickTimeTyped(
      title: 'Eindtijd',
      current: _endTime,
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  Future<TimeOfDay?> _pickTimeTyped({
    required String title,
    required TimeOfDay current,
  }) async {
    var hourText = '';
    var minuteText = '';
    String? errorText;

    String two(int v) => v.toString().padLeft(2, '0');
    final currentLabel = '${two(current.hour)}:${two(current.minute)}';

    final result = await showDialog<TimeOfDay?>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Typ een tijd (huidig: $currentLabel)',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: TextFormField(
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 2,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (v) => setState(() => hourText = v),
                          decoration: const InputDecoration(
                            counterText: '',
                            hintText: 'uu',
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          ':',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 70,
                        child: TextFormField(
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 2,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (v) => setState(() => minuteText = v),
                          decoration: const InputDecoration(
                            counterText: '',
                            hintText: 'mm',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Annuleren'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final h = int.tryParse(hourText.trim());
                    final m = int.tryParse(minuteText.trim());
                    if (h == null || m == null) {
                      setState(() => errorText = 'Vul uur en minuten in.');
                      return;
                    }
                    if (h < 0 || h > 23) {
                      setState(() => errorText = 'Uur moet tussen 0 en 23 zijn.');
                      return;
                    }
                    if (m < 0 || m > 59) {
                      setState(
                        () => errorText = 'Minuten moeten tussen 0 en 59 zijn.',
                      );
                      return;
                    }
                    Navigator.of(context).pop(TimeOfDay(hour: h, minute: m));
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
    return result;
  }

  DateTime _combine(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  TimeOfDay _defaultEndTime(TimeOfDay start) {
    final hour = (start.hour + 2) % 24;
    return TimeOfDay(hour: hour, minute: start.minute);
  }

  String _formatDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year}';
  }

  String _formatTime(TimeOfDay t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  String _teamTitle() {
    final teamId = _selectedTeamId;
    if (teamId == null) return 'Training';
    TeamMembership? team;
    for (final t in widget.manageableTeams) {
      if (t.teamId == teamId) {
        team = t;
        break;
      }
    }
    final raw = (team?.teamName ?? '').trim();
    final pretty = _teamAbbreviation(raw);
    if (pretty.isNotEmpty) return pretty;
    return '(naam ontbreekt)';
  }

  Widget _weekdayChip(String label, int weekday) {
    final selected = _selectedWeekdays.contains(weekday);
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) {
        setState(() {
          if (v) {
            _selectedWeekdays = {..._selectedWeekdays, weekday};
          } else {
            _selectedWeekdays = _selectedWeekdays.where((d) => d != weekday).toSet();
          }
        });
      },
      selectedColor: AppColors.primary.withValues(alpha: 0.3),
      checkmarkColor: AppColors.primary,
    );
  }

  String _teamAbbreviation(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';

    // Already compact codes like Hs1/Ds1/Jb1/Mb1:
    final compact = s.replaceAll(' ', '');
    final lower = compact.toLowerCase();
    final codeMatch = RegExp(r'^(hs|ds|jb|mb)\d+$').firstMatch(lower);
    if (codeMatch != null) {
      return '${lower[0].toUpperCase()}${lower.substring(1)}';
    }

    // Derive from common full names.
    final normalized = s.toLowerCase();
    final number = RegExp(r'(\d+)').firstMatch(normalized)?.group(1);
    if (normalized.contains('heren')) return number != null ? 'Hs$number' : 'Hs';
    if (normalized.contains('dames')) return number != null ? 'Ds$number' : 'Ds';
    if (normalized.contains('jongens')) return number != null ? 'Jb$number' : 'Jb';
    if (normalized.contains('meis') || normalized.contains('mini')) {
      return number != null ? 'Mb$number' : 'Mb';
    }

    return s;
  }

  Future<void> _saveTraining() async {
    if (_saving) return;

    final title = _teamTitle();

    if (_selectedTeamId == null) {
      showTopMessage(context, 'Kies een team', isError: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final endDate = _endDate ?? _selectedDate;
      if (endDate.isBefore(_selectedDate)) {
        showTopMessage(context, 'Einddatum moet op of na startdatum liggen', isError: true);
        return;
      }
      if (_endDate != null && _selectedWeekdays.isEmpty) {
        showTopMessage(context, 'Kies minimaal één dag van de week', isError: true);
        return;
      }

      final startDateTime = _combine(_selectedDate, _startTime);
      final endDateTime = _combine(_selectedDate, _endTime);

      if (!endDateTime.isAfter(startDateTime)) {
        showTopMessage(context, 'Eindtijd moet na starttijd liggen', isError: true);
        return;
      }

      final baseMap = <String, dynamic>{
        'team_id': _selectedTeamId,
        'session_type': 'training',
        'title': title,
        'location': _selectedLocation,
        'created_by': _uid,
        'is_cancelled': false,
      };

      var date = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final last = DateTime(endDate.year, endDate.month, endDate.day);
      final inserts = <Map<String, dynamic>>[];

      while (!date.isAfter(last)) {
        final normalDate = DateTime(date.year, date.month, date.day);
        final skipWeekday = _selectedWeekdays.isNotEmpty &&
            !_selectedWeekdays.contains(date.weekday);
        final skipHoliday = _excludeHolidays && isDutchHoliday(date);
        final skipExcluded = _excludedDates.any((d) =>
            d.year == normalDate.year &&
            d.month == normalDate.month &&
            d.day == normalDate.day);
        if (!skipWeekday && !skipHoliday && !skipExcluded) {
          final s = _combine(date, _startTime);
          final e = _combine(date, _endTime);
          inserts.add({
            ...baseMap,
            'start_datetime': s.toUtc().toIso8601String(),
            'end_timestamp': e.toUtc().toIso8601String(),
          });
        }
        date = date.add(const Duration(days: 1));
      }

      await _client.from('sessions').insert(inserts);
      await NotificationService.sendBroadcastUpdate(
        title: 'Nieuwe training toegevoegd',
        body: '$title (${inserts.length}x)',
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Fout bij training opslaan: $e');
      if (mounted) {
        showTopMessage(context, 'Fout bij opslaan: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _saving ? null : _saveTraining,
        child: const Icon(Icons.check),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16 + MediaQuery.paddingOf(context).top,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: AppColors.onBackground),
                  ),
                  Text(
                    'Team',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.onBackground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            GlassCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: DropdownButton<int>(
                  value: _selectedTeamId,
                  isExpanded: true,
                  dropdownColor: AppColors.card,
                  underline: const SizedBox.shrink(),
                  items: widget.manageableTeams.map((t) {
                    return DropdownMenuItem<int>(
                      value: t.teamId,
                      child: Text(
                        t.teamName,
                        style: const TextStyle(color: AppColors.onBackground),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedTeamId = v),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'Algemeen',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.onBackground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            GlassCard(
              child: ListTile(
                dense: true,
                title: const Text(
                  'Titel',
                  style: TextStyle(color: AppColors.onBackground, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  _teamTitle(),
                  style: const TextStyle(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Locatie',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.onBackground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            GlassCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: DropdownButton<String>(
                  value: _selectedLocation,
                  isExpanded: true,
                  dropdownColor: AppColors.card,
                  underline: const SizedBox.shrink(),
                  items: _locations
                      .map(
                        (l) => DropdownMenuItem<String>(
                          value: l,
                          child: Text(
                            l,
                            style: const TextStyle(color: AppColors.onBackground),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _selectedLocation = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'Datum en tijd',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.onBackground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            GlassCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today, color: AppColors.onBackground),
                    title: const Text('Startdatum', style: TextStyle(color: AppColors.onBackground, fontWeight: FontWeight.w500)),
                    subtitle: Text(_formatDate(_selectedDate),
                        style: const TextStyle(color: AppColors.textSecondary)),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_calendar, color: AppColors.primary),
                      onPressed: _pickDate,
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event, color: AppColors.onBackground),
                    title: const Text('Einddatum', style: TextStyle(color: AppColors.onBackground, fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      _endDate == null ? 'Niet ingesteld (één training)' : _formatDate(_endDate!),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    trailing: _endDate == null
                        ? IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                            onPressed: _pickEndDate,
                            tooltip: 'Meerdere trainingen toevoegen',
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_calendar, color: AppColors.primary),
                                onPressed: _pickEndDate,
                              ),
                              IconButton(
                                icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                                onPressed: _clearEndDate,
                                tooltip: 'Eén training',
                              ),
                            ],
                          ),
                  ),
                  if (_endDate != null) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dagen met training',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.onBackground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _weekdayChip('Ma', 1),
                              _weekdayChip('Di', 2),
                              _weekdayChip('Wo', 3),
                              _weekdayChip('Do', 4),
                              _weekdayChip('Vr', 5),
                              _weekdayChip('Za', 6),
                              _weekdayChip('Zo', 7),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _excludeHolidays,
                      onChanged: (v) => setState(() => _excludeHolidays = v),
                      title: const Text(
                        'Feestdagen uitsluiten',
                        style: TextStyle(color: AppColors.onBackground, fontWeight: FontWeight.w500),
                      ),
                      subtitle: const Text(
                        'Kerst, Pasen, Koningsdag, etc. overslaan',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      activeThumbColor: AppColors.primary,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_busy, color: AppColors.onBackground),
                      title: const Text(
                        'Data uitsluiten',
                        style: TextStyle(color: AppColors.onBackground, fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        _excludedDates.isEmpty
                            ? 'Geen data uitgesloten'
                            : '${_excludedDates.length} datum(s) uitgesloten',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                            onPressed: _addExcludedDate,
                            tooltip: 'Datum toevoegen om uit te sluiten',
                          ),
                          if (_excludedDates.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear_all, color: AppColors.textSecondary),
                              onPressed: () => setState(() => _excludedDates.clear()),
                              tooltip: 'Alles wissen',
                            ),
                        ],
                      ),
                    ),
                    if (_excludedDates.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: (_excludedDates.toList()..sort((a, b) => a.compareTo(b)))
                              .map((d) => Chip(
                                    label: Text(_formatDate(d)),
                                    deleteIcon: const Icon(
                                        Icons.close, size: 18, color: AppColors.onBackground),
                                    onDeleted: () {
                                      setState(() {
                                        _excludedDates.removeWhere((x) =>
                                            x.year == d.year &&
                                            x.month == d.month &&
                                            x.day == d.day);
                                      });
                                    },
                                  ))
                              .toList(),
                        ),
                      ),
                  ],
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule, color: AppColors.onBackground),
                    title: const Text('Starttijd', style: TextStyle(color: AppColors.onBackground, fontWeight: FontWeight.w500)),
                    subtitle: Text(_formatTime(_startTime),
                        style: const TextStyle(color: AppColors.textSecondary)),
                    onTap: _pickStartTime,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_outlined, color: AppColors.onBackground),
                    title: const Text('Eindtijd', style: TextStyle(color: AppColors.onBackground, fontWeight: FontWeight.w500)),
                    subtitle: Text(_formatTime(_endTime),
                        style: const TextStyle(color: AppColors.textSecondary)),
                    onTap: _pickEndTime,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            if (_saving)
              const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}