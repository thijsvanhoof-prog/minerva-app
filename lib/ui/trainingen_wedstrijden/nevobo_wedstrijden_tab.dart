import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_colors.dart';

/// Model voor een Nevobo-wedstrijd
class NevoboMatch {
  final String summary;
  final DateTime? start;
  final DateTime? end;
  final String? location;
  final String? description;

  const NevoboMatch({
    required this.summary,
    this.start,
    this.end,
    this.location,
    this.description,
  });
}

class NevoboWedstrijdenTab extends StatefulWidget {
  const NevoboWedstrijdenTab({super.key});

  @override
  State<NevoboWedstrijdenTab> createState() => _NevoboWedstrijdenTabState();
}

class _NevoboWedstrijdenTabState extends State<NevoboWedstrijdenTab> {
  static const String _icsUrl =
      'https://api.nevobo.nl/export/team/CKM0V2O/heren/1/wedstrijden.ics';

  bool _loading = true;
  String? _error;
  List<NevoboMatch> _matches = [];

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.get(Uri.parse(_icsUrl));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final body = utf8.decode(response.bodyBytes);
      final parsed = _parseIcs(body);

      parsed.sort((a, b) {
        final sa = a.start ?? DateTime(2100);
        final sb = b.start ?? DateTime(2100);
        return sa.compareTo(sb);
      });

      setState(() {
        _matches = parsed;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Kon Nevobo-wedstrijden niet laden.\n$e';
        _loading = false;
      });
    }
  }

  List<NevoboMatch> _parseIcs(String ics) {
    final result = <NevoboMatch>[];
    final normalized =
        ics.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final events = normalized.split('BEGIN:VEVENT');

    for (var i = 1; i < events.length; i++) {
      final block = events[i].split('END:VEVENT').first;
      final lines = block
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      final map = <String, String>{};

      for (final line in lines) {
        final idx = line.indexOf(':');
        if (idx <= 0) continue;

        var key = line.substring(0, idx);
        final value = line.substring(idx + 1);

        final semi = key.indexOf(';');
        if (semi > 0) key = key.substring(0, semi);

        map[key.toUpperCase()] = value;
      }

      result.add(
        NevoboMatch(
          summary: map['SUMMARY'] ?? 'Wedstrijd',
          start: _parseDate(map['DTSTART']),
          end: _parseDate(map['DTEND']),
          location: map['LOCATION'],
          description: map['DESCRIPTION'],
        ),
      );
    }

    return result;
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null) return null;

    try {
      if (raw.length == 8) {
        return DateTime.parse(
            '${raw.substring(0, 4)}-${raw.substring(4, 6)}-${raw.substring(6, 8)}');
      }

      if (raw.contains('T')) {
        final d = raw.substring(0, 8);
        final t = raw.substring(9, 15);
        final iso =
            '${d.substring(0, 4)}-${d.substring(4, 6)}-${d.substring(6, 8)}T'
            '${t.substring(0, 2)}:${t.substring(2, 4)}:${t.substring(4, 6)}';
        return DateTime.parse(iso);
      }
    } catch (_) {}

    return null;
  }

  String _format(DateTime? dt) {
    if (dt == null) return '-';
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      );
    }

    if (_matches.isEmpty) {
      return const Center(
        child: Text(
          'Geen wedstrijden gevonden.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadMatches,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _matches.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final m = _matches[index];

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.primary,
                width: 2.4, // vaste dikke oranje rand
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.summary,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.onBackground,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Datum: ${_format(m.start)}',
                  style:
                      const TextStyle(color: AppColors.textSecondary),
                ),
                if (m.location != null && m.location!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Locatie: ${m.location}',
                    style:
                        const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
                if (m.description != null &&
                    m.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    m.description!,
                    style:
                        const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}