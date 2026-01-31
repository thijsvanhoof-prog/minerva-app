import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_user_context.dart';

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
  TimeOfDay _startTime = const TimeOfDay(hour: 20, minute: 30);
  TimeOfDay _endTime = const TimeOfDay(hour: 22, minute: 30);

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
    final hourController = TextEditingController();
    final minuteController = TextEditingController();
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
                        child: TextField(
                          controller: hourController,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 2,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
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
                        child: TextField(
                          controller: minuteController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 2,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
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
                    final h = int.tryParse(hourController.text.trim());
                    final m = int.tryParse(minuteController.text.trim());
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

    hourController.dispose();
    minuteController.dispose();
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
    return 'Team $teamId';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kies een team')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final startDateTime = _combine(_selectedDate, _startTime);
      final endDateTime = _combine(_selectedDate, _endTime);

      if (!endDateTime.isAfter(startDateTime)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Eindtijd moet na starttijd liggen')),
        );
        return;
      }

      final insertMap = <String, dynamic>{
        'team_id': _selectedTeamId,
        'session_type': 'training',
        'title': title,
        'location': _selectedLocation,
        'start_datetime': startDateTime.toUtc().toIso8601String(),
        'end_timestamp': endDateTime.toUtc().toIso8601String(),
        'created_by': _uid,
        'is_cancelled': false,
      };

      await _client.from('sessions').insert(insertMap);

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Fout bij training opslaan: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout bij opslaan: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Training toevoegen'),
        actions: [
          IconButton(
            onPressed: _saving ? null : _saveTraining,
            icon: const Icon(Icons.check),
            color: AppColors.primary,
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Team',
              style: theme.textTheme.titleMedium?.copyWith(color: AppColors.onBackground),
            ),
            const SizedBox(height: 8),
            Card(
              color: AppColors.card,
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
              style: theme.textTheme.titleMedium?.copyWith(color: AppColors.onBackground),
            ),
            const SizedBox(height: 8),
            Card(
              color: AppColors.card,
              child: ListTile(
                dense: true,
                title: const Text(
                  'Titel',
                  style: TextStyle(color: AppColors.textSecondary),
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
              style:
                  theme.textTheme.titleSmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Card(
              color: AppColors.card,
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
              style: theme.textTheme.titleMedium?.copyWith(color: AppColors.onBackground),
            ),
            const SizedBox(height: 8),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today, color: AppColors.textSecondary),
              title: const Text('Datum', style: TextStyle(color: AppColors.textSecondary)),
              subtitle: Text(_formatDate(_selectedDate),
                  style: const TextStyle(color: AppColors.onBackground)),
              trailing: IconButton(
                icon: const Icon(Icons.edit_calendar, color: AppColors.primary),
                onPressed: _pickDate,
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule, color: AppColors.textSecondary),
              title: const Text('Starttijd', style: TextStyle(color: AppColors.textSecondary)),
              subtitle: Text(_formatTime(_startTime),
                  style: const TextStyle(color: AppColors.onBackground)),
              onTap: _pickStartTime,
            ),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined,
                  color: AppColors.textSecondary),
              title: const Text('Eindtijd',
                  style: TextStyle(color: AppColors.textSecondary)),
              subtitle: Text(_formatTime(_endTime),
                  style: const TextStyle(color: AppColors.onBackground)),
              onTap: _pickEndTime,
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