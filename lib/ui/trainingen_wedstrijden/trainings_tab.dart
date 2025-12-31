import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_colors.dart';
import '../app_user_context.dart'; // TeamMembership
import 'add_training_page.dart';

enum AttendanceStatus { aanwezig, afwezig, nietSpelend }

class TrainingsTab extends StatefulWidget {
  final List<TeamMembership> manageableTeams;

  const TrainingsTab({
    super.key,
    required this.manageableTeams,
  });

  @override
  State<TrainingsTab> createState() => _TrainingsTabState();
}

class _TrainingsTabState extends State<TrainingsTab> {
  final SupabaseClient _client = Supabase.instance.client;

  late Future<void> _loadFuture;

  List<Map<String, dynamic>> _trainings = [];
  final Map<int, AttendanceStatus> _statusBySessionId = {};

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadData();
  }

  Future<void> _refresh() async {
    setState(() {
      _loadFuture = _loadData();
    });
    await _loadFuture;
  }

  Future<void> _loadData() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _trainings = [];
      _statusBySessionId.clear();
      return;
    }

    final sessionsRes = await _client
        .from('sessions')
        .select(
          'session_id, team_id, session_type, title, start_datetime, location, created_by, is_cancelled, start_timestamp, end_timestamp',
        )
        .eq('session_type', 'training')
        .order('start_datetime', ascending: false);

    final sessions = (sessionsRes as List<dynamic>).cast<Map<String, dynamic>>();
    _trainings = sessions;

    _statusBySessionId.clear();
    if (_trainings.isEmpty) return;

    final sessionIds =
        _trainings.map((s) => (s['session_id'] as num).toInt()).toList();

    final attendanceRes = await _client
        .from('attendance')
        .select('session_id, person_id, status')
        .inFilter('session_id', sessionIds)
        .eq('person_id', user.id);

    final attendanceRows =
        (attendanceRes as List<dynamic>).cast<Map<String, dynamic>>();

    for (final row in attendanceRows) {
      final sid = (row['session_id'] as num).toInt();
      final statusStr = (row['status'] ?? '').toString();
      _statusBySessionId[sid] = _statusFromString(statusStr);
    }
  }

  AttendanceStatus _statusFromString(String value) {
    switch (value) {
      case 'aanwezig':
        return AttendanceStatus.aanwezig;
      case 'afwezig':
        return AttendanceStatus.afwezig;
      case 'nietSpelend':
      case 'niet_spelend':
      case 'nietspelend':
        return AttendanceStatus.nietSpelend;
      default:
        return AttendanceStatus.nietSpelend;
    }
  }

  String _formatDateTime(dynamic value) {
    if (value == null) return '-';
    final dt = value is DateTime ? value : DateTime.tryParse(value.toString());
    if (dt == null) return value.toString();

    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${two(local.day)}-${two(local.month)}-${local.year}';
    final time = '${two(local.hour)}:${two(local.minute)}';
    return '$date $time';
  }

  bool get _canCreateTrainings {
    final roles = widget.manageableTeams
        .map((m) => m.role.toLowerCase())
        .toList();
    return roles.any((r) => r == 'admin' || r == 'trainer' || r == 'coach');
  }

  Future<void> _openAddTraining() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddTrainingPage(manageableTeams: widget.manageableTeams),
      ),
    );

    if (created == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _updateAttendance(int sessionId, AttendanceStatus status) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    setState(() {
      _statusBySessionId[sessionId] = status;
    });

    await _client.from('attendance').upsert(
      {
        'session_id': sessionId,
        'person_id': user.id,
        'status': status.name,
      },
      onConflict: 'session_id,person_id',
    );

    // geen harde refresh nodig, maar mag wel:
    // await _refresh();
  }

  Color _attendanceColor(AttendanceStatus iconStatus, AttendanceStatus? current) {
    if (current != iconStatus) return AppColors.textSecondary;

    switch (iconStatus) {
      case AttendanceStatus.aanwezig:
        return AppColors.success;
      case AttendanceStatus.afwezig:
        return AppColors.error;
      case AttendanceStatus.nietSpelend:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: _canCreateTrainings
          ? FloatingActionButton(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              onPressed: _openAddTraining,
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: FutureBuilder<void>(
          future: _loadFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Fout bij laden van trainingen: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.error),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                    ),
                    onPressed: _refresh,
                    child: const Text('Opnieuw laden'),
                  ),
                ],
              );
            }

            if (_trainings.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(height: 40),
                  Text(
                    'Geen trainingen gevonden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _trainings.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final session = _trainings[index];
                final sessionId = (session['session_id'] as num).toInt();

                final title = (session['title'] ?? 'Training').toString();
                final location = (session['location'] ?? '').toString();

                final start = session['start_datetime'] ?? session['start_timestamp'];
                final end = session['end_timestamp'];

                final currentStatus = _statusBySessionId[sessionId];

                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.65),
                      width: 2.2, // vaste dikke oranje rand
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: AppColors.onBackground,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (location.isNotEmpty)
                                Text(
                                  location,
                                  style: const TextStyle(color: AppColors.textSecondary),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                '${_formatDateTime(start)}  →  ${_formatDateTime(end)}',
                                style: const TextStyle(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Aanwezig',
                              icon: Icon(
                                Icons.check_circle,
                                color: _attendanceColor(
                                  AttendanceStatus.aanwezig,
                                  currentStatus,
                                ),
                              ),
                              onPressed: () => _updateAttendance(
                                sessionId,
                                AttendanceStatus.aanwezig,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Afwezig',
                              icon: Icon(
                                Icons.cancel,
                                color: _attendanceColor(
                                  AttendanceStatus.afwezig,
                                  currentStatus,
                                ),
                              ),
                              onPressed: () => _updateAttendance(
                                sessionId,
                                AttendanceStatus.afwezig,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Niet spelend',
                              icon: Icon(
                                Icons.remove_circle,
                                color: _attendanceColor(
                                  AttendanceStatus.nietSpelend,
                                  currentStatus,
                                ),
                              ),
                              onPressed: () => _updateAttendance(
                                sessionId,
                                AttendanceStatus.nietSpelend,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}