import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_colors.dart';
import '../app_user_context.dart';

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

  final _titleController = TextEditingController();
  final _locationController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 20, minute: 30);

  bool _saving = false;
  int? _selectedTeamId;

  @override
  void initState() {
    super.initState();
    if (widget.manageableTeams.isNotEmpty) {
      _selectedTeamId = widget.manageableTeams.first.teamId;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
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
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
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
    if (picked != null) setState(() => _startTime = picked);
  }

  DateTime _combine(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _formatDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year}';
  }

  String _formatTime(TimeOfDay t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _saveTraining() async {
    if (_saving) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vul een titel in')),
      );
      return;
    }

    if (_selectedTeamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kies een team')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final startDateTime = _combine(_selectedDate, _startTime);

      final insertMap = <String, dynamic>{
        'team_id': _selectedTeamId,
        'session_type': 'training',
        'title': title,
        'location': _locationController.text.trim(),
        'start_datetime': startDateTime.toUtc().toIso8601String(),
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
            TextField(
              controller: _titleController,
              style: const TextStyle(color: AppColors.onBackground),
              decoration: const InputDecoration(
                labelText: 'Titel',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textSecondary),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _locationController,
              style: const TextStyle(color: AppColors.onBackground),
              decoration: const InputDecoration(
                labelText: 'Locatie',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textSecondary),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primary),
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

            const SizedBox(height: 16),
            if (_saving)
              const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}