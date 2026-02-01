import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class NevoboTeam {
  final String code; // e.g. HS1, DS1, JB1, MB1
  final String category; // e.g. heren, dames, jongens-b, meiden-b
  final int number;

  const NevoboTeam({
    required this.code,
    required this.category,
    required this.number,
  });

  String get clubIdUpper => 'CKM0V2O';
  String get clubIdLower => 'ckm0v2o';

  String get teamPath => '/competitie/teams/$clubIdLower/$category/$number';

  String get icsUrl =>
      'https://api.nevobo.nl/export/team/$clubIdUpper/$category/$number/wedstrijden.ics';
}

class NevoboMatch {
  final String summary;
  final DateTime? start;
  final DateTime? end;
  final String? location;
  final String? description;
  final List<int>? eindstand; // e.g. [3,1] home-away
  final String? volledigeUitslag; // e.g. "1-3  (21-25, 13-25, ...)"
  final String? status; // e.g. "gespeeld"
  final String? urlDwf;

  const NevoboMatch({
    required this.summary,
    this.start,
    this.end,
    this.location,
    this.description,
    this.eindstand,
    this.volledigeUitslag,
    this.status,
    this.urlDwf,
  });
}

class NevoboStandingEntry {
  final int position;
  final String teamName;
  final String? teamPath; // /competitie/teams/...
  final int played;
  final int points;

  const NevoboStandingEntry({
    required this.position,
    required this.teamName,
    required this.teamPath,
    required this.played,
    required this.points,
  });
}

class NevoboApi {
  NevoboApi._();

  static final Map<String, String> _teamNameCacheByPath = {};
  static final Map<String, NevoboTeam> _resolvedTeamByCode = {};
  static final Map<String, String> _iriNameCache = {};
  static final Map<String, String> _sporthalCache = {};

  static NevoboTeam? teamFromCode(String code) => _fromCode(code);

  static String? extractCodeFromTeamName(String raw) {
    final normalized = raw.trim().toUpperCase().replaceAll(' ', '');

    // Already a compact team code?
    if (RegExp(r'^(HS|DS|JA|JB|JC|JD|MA|MB|MC|MD|MR)\d+$').hasMatch(normalized)) {
      return normalized;
    }

    // Try to derive from a descriptive name (e.g. "Heren 2", "Jongens C 1").
    return _deriveCodeFromDisplayName(raw);
  }

  /// Custom team ordering for the app:
  /// dames -> heren -> recreanten -> meiden A -> jongens A -> meiden B -> jongens B -> meiden C -> jongens C.
  ///
  /// Sorts within each group by team number (ascending).
  static int compareTeamCodes(String a, String b) {
    final ka = _teamSortKeyFromCode(a);
    final kb = _teamSortKeyFromCode(b);
    if (ka.$1 != kb.$1) return ka.$1.compareTo(kb.$1);
    if (ka.$2 != kb.$2) return ka.$2.compareTo(kb.$2);
    return a.compareTo(b);
  }

  static int compareTeams(NevoboTeam a, NevoboTeam b) => compareTeamCodes(a.code, b.code);

  /// Compare user-facing team names using derived codes when possible.
  ///
  /// Use [volleystarsLast] for training UIs, where "Volleystars" should appear last.
  static int compareTeamNames(
    String a,
    String b, {
    bool volleystarsLast = false,
  }) {
    final an = a.trim();
    final bn = b.trim();

    if (volleystarsLast) {
      final av = an.toLowerCase().contains('volleystars');
      final bv = bn.toLowerCase().contains('volleystars');
      if (av != bv) return av ? 1 : -1;
    }

    final ac = extractCodeFromTeamName(an);
    final bc = extractCodeFromTeamName(bn);
    if (ac != null && bc != null) return compareTeamCodes(ac, bc);
    if (ac != null && bc == null) return -1;
    if (ac == null && bc != null) return 1;
    return an.toLowerCase().compareTo(bn.toLowerCase());
  }

  static (int, int) _teamSortKeyFromCode(String raw) {
    final normalized = raw.trim().toUpperCase().replaceAll(' ', '');
    final m = RegExp(r'^([A-Z]{2})(\d+)$').firstMatch(normalized);
    final prefix = m?.group(1) ?? normalized;
    final number = int.tryParse(m?.group(2) ?? '') ?? 999;

    // Order groups according to requested app ordering.
    final group = switch (prefix) {
      'DS' => 0, // dames
      'HS' => 1, // heren
      'MR' => 2, // recreanten/mix
      'MA' => 3, // meiden A
      'JA' => 4, // jongens A
      'MB' => 5, // meiden B
      'JB' => 6, // jongens B
      'MC' => 7, // meiden C
      'JC' => 8, // jongens C
      _ => 99,
    };
    return (group, number);
  }

  static String? _deriveCodeFromDisplayName(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;

    final number = RegExp(r'(\d+)').firstMatch(s)?.group(1);
    if (number == null) return null;

    // Seniors
    if (s.contains('heren')) return 'HS$number';
    if (s.contains('dames')) return 'DS$number';

    // Youth A/B/C/D
    final letter = RegExp(r'\b([a-d])\b').firstMatch(s)?.group(1);
    final isBoys = s.contains('jongens');
    final isGirls = s.contains('meiden') || s.contains('meis');
    if (isBoys && letter != null) return 'J${letter.toUpperCase()}$number';
    if (isGirls && letter != null) return 'M${letter.toUpperCase()}$number';

    // Mixed / recreanten
    if (s.contains('mix') || s.contains('recre')) return 'MR$number';

    return null;
  }

  static Future<List<NevoboTeam>> loadTeamsFromSupabase({
    required SupabaseClient client,
  }) async {
    // We don't know the exact column name in the teams table, so we try common candidates.
    final candidates = <String>[
      'team_name',
      'name',
      'short_name',
      'code',
      'team_code',
      'abbreviation',
    ];

    for (final nameField in candidates) {
      try {
        final res = await client.from('teams').select(nameField);
        final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
        final set = <String>{};
        for (final row in rows) {
          final v = row[nameField]?.toString() ?? '';
          final code = extractCodeFromTeamName(v);
          if (code == null) continue;
          if (code.isNotEmpty) {
            set.add(code);
          }
        }
        if (set.isNotEmpty) {
          final teams = set
              .map(_fromCode)
              .whereType<NevoboTeam>()
              .toList()
            ..sort(compareTeams);
          return teams;
        }
      } catch (_) {
        // Try next candidate column.
      }
    }

    // Fallback: the minimal default set.
    return const [
      NevoboTeam(code: 'HS1', category: 'heren', number: 1),
      NevoboTeam(code: 'DS1', category: 'dames', number: 1),
      NevoboTeam(code: 'JB1', category: 'jongens-b', number: 1),
      NevoboTeam(code: 'MB1', category: 'meiden-b', number: 1),
    ];
  }

  static NevoboTeam? _fromCode(String code) {
    final normalized = code.trim().toUpperCase().replaceAll(' ', '');
    final m = RegExp(r'^(HS|DS|JA|JB|JC|JD|MA|MB|MC|MD|MR)(\d+)$')
        .firstMatch(normalized);
    if (m == null) return null;
    final prefix = m.group(1)!;
    final number = int.tryParse(m.group(2)!) ?? 1;

    switch (prefix) {
      case 'HS':
        return NevoboTeam(code: normalized, category: 'heren', number: number);
      case 'DS':
        return NevoboTeam(code: normalized, category: 'dames', number: number);
      case 'JA':
        return NevoboTeam(code: normalized, category: 'jongens-a', number: number);
      case 'JB':
        return NevoboTeam(code: normalized, category: 'jongens-b', number: number);
      case 'MB':
        // In the previous working implementation, MB mapped to "meiden-b".
        return NevoboTeam(code: normalized, category: 'meiden-b', number: number);
      case 'JC':
        // Likely "jongens-c" – if Nevobo uses another value, we'll resolve dynamically.
        return NevoboTeam(code: normalized, category: 'jongens-c', number: number);
      case 'JD':
        return NevoboTeam(code: normalized, category: 'jongens-d', number: number);
      case 'MA':
        return NevoboTeam(code: normalized, category: 'meiden-a', number: number);
      case 'MC':
        return NevoboTeam(code: normalized, category: 'meiden-c', number: number);
      case 'MD':
        return NevoboTeam(code: normalized, category: 'meiden-d', number: number);
      case 'MR':
        // Mixed/recreanten naming differs; we'll resolve dynamically.
        return NevoboTeam(code: normalized, category: 'mix', number: number);
      default:
        return null;
    }
  }

  static Future<List<NevoboMatch>> fetchMatchesIcs({
    required String icsUrl,
  }) async {
    final response = await http.get(Uri.parse(icsUrl));
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
    return parsed;
  }

  /// Fetch matches for a team, but robust against wrong/changed categories.
  ///
  /// The Nevobo ICS export endpoint can return 404 when the category part
  /// of the URL doesn't match what Nevobo expects for that team.
  /// We therefore probe candidate categories (using the same resolver logic
  /// we use for standings) and cache the first working one.
  static Future<List<NevoboMatch>> fetchMatchesForTeam({
    required NevoboTeam team,
  }) async {
    final resolved = await _resolveTeam(team);
    final candidates = _categoryCandidates(team.code, resolved.category);

    Exception? lastError;
    for (final category in candidates) {
      final probeTeam = NevoboTeam(
        code: team.code,
        category: category,
        number: team.number,
      );
      final uri = Uri.parse(probeTeam.icsUrl);
      try {
        final res = await http.get(uri);
        if (res.statusCode == 200) {
          final body = utf8.decode(res.bodyBytes);
          final parsed = _parseIcs(body);
          parsed.sort((a, b) {
            final sa = a.start ?? DateTime(2100);
            final sb = b.start ?? DateTime(2100);
            return sa.compareTo(sb);
          });
          _resolvedTeamByCode[team.code] = probeTeam;
          return parsed;
        }
        lastError = Exception('ICS HTTP ${res.statusCode} (${probeTeam.icsUrl})');
        // For 404 we definitely want to try other candidates.
        // For other statuses, we still try next candidates (best effort).
      } catch (e) {
        lastError = Exception('ICS error ($e) (${probeTeam.icsUrl})');
      }
    }

    throw lastError ?? Exception('ICS error (geen categorie gevonden) voor ${team.code}');
  }

  /// Fetch wedstrijden (incl. uitslagen) via de officiële competitie API.
  ///
  /// Dit endpoint bevat o.a. `eindstand` en `volledigeUitslag`, en is betrouwbaarder
  /// dan proberen te parsen uit de ICS export.
  static Future<List<NevoboMatch>> fetchMatchesForTeamViaCompetitionApi({
    required NevoboTeam team,
  }) async {
    final resolved = await _resolveTeam(team);
    final candidates = _categoryCandidates(team.code, resolved.category);

    Exception? lastError;
    for (final category in candidates) {
      final teamPath = '/competitie/teams/${team.clubIdLower}/${category.toLowerCase()}/${team.number}';
      final uri = Uri.parse(
        'https://api.nevobo.nl/competitie/wedstrijden?team=${Uri.encodeComponent(teamPath)}',
      );

      try {
        final res = await http.get(
          uri,
          headers: const {'Accept': 'application/json'},
        );
        if (res.statusCode != 200) {
          lastError = Exception('Wedstrijden HTTP ${res.statusCode} ($teamPath)');
          continue;
        }

        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final list = _asList(decoded);
        if (list == null) {
          lastError = Exception('Onverwachte response voor wedstrijden ($teamPath)');
          continue;
        }

        final out = <NevoboMatch>[];
        for (final item in list) {
          if (item is! Map) continue;
          final m = item.cast<String, dynamic>();

          final tijdstip = m['tijdstip']?.toString();
          final start = _parseDateTime(tijdstip);
          final lengteMin = (m['lengte'] is num) ? (m['lengte'] as num).toInt() : int.tryParse('${m['lengte'] ?? ''}');
          final end = (start != null && (lengteMin ?? 0) > 0) ? start.add(Duration(minutes: lengteMin!)) : null;

          final statusObj = m['status'];
          final status = statusObj is Map ? (statusObj['waarde']?.toString()) : statusObj?.toString();

          final eindstand = _asIntList(m['eindstand']);
          final volledigeUitslag = m['volledigeUitslag']?.toString();
          final urlDwf = m['urlDwf']?.toString();

          final teams = _asStringList(m['teams']);
          final teamNames = <String>[];
          for (final iri in teams) {
            final name = await _resolveIriName(iri);
            teamNames.add(name);
          }
          final summary = teamNames.length >= 2
              ? '${teamNames[0]} - ${teamNames[1]}'
              : (teamNames.isNotEmpty ? teamNames.join(' - ') : 'Wedstrijd');

          final sporthalIri = m['sporthal']?.toString();
          final sporthal = sporthalIri == null || sporthalIri.isEmpty ? null : await _resolveSporthal(sporthalIri);

          out.add(
            NevoboMatch(
              summary: summary,
              start: start,
              end: end,
              location: sporthal,
              // Keep description for any legacy parsing fallback.
              description: volledigeUitslag,
              eindstand: eindstand,
              volledigeUitslag: volledigeUitslag,
              status: status,
              urlDwf: urlDwf,
            ),
          );
        }

        out.sort((a, b) {
          final sa = a.start ?? DateTime(2100);
          final sb = b.start ?? DateTime(2100);
          return sa.compareTo(sb);
        });

        _resolvedTeamByCode[team.code] = NevoboTeam(code: team.code, category: category, number: team.number);
        return out;
      } catch (e) {
        lastError = Exception('Wedstrijden error ($e) ($teamPath)');
      }
    }

    throw lastError ?? Exception('Wedstrijden error (geen categorie gevonden) voor ${team.code}');
  }

  static List<NevoboMatch> _parseIcs(String ics) {
    final result = <NevoboMatch>[];
    final normalized = ics.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
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
        final value = _icsUnescape(line.substring(idx + 1));

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

  static String _icsUnescape(String value) {
    // Common ICS escapes: \n, \\, \, \; \:
    // Order matters: translate newlines first, then unescape other sequences.
    var v = value;
    v = v.replaceAll(r'\n', '\n');
    v = v.replaceAll(r'\,', ',');
    v = v.replaceAll(r'\;', ';');
    v = v.replaceAll(r'\:', ':');
    v = v.replaceAll(r'\\', r'\');
    return v;
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    try {
      if (raw.length == 8) {
        return DateTime.parse(
          '${raw.substring(0, 4)}-${raw.substring(4, 6)}-${raw.substring(6, 8)}',
        );
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

  static DateTime? _parseDateTime(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  static Future<NevoboTeam> _resolveTeam(NevoboTeam team) async {
    final cached = _resolvedTeamByCode[team.code];
    if (cached != null) return cached;

    final candidates = _categoryCandidates(team.code, team.category);
    for (final category in candidates) {
      final teamPath =
          '/competitie/teams/${team.clubIdLower}/${category.toLowerCase()}/${team.number}';
      final probe = Uri.parse(
        'https://api.nevobo.nl/competitie/pouleindelingen?team=${Uri.encodeComponent(teamPath)}',
      );
      try {
        final res = await http.get(probe);
        if (res.statusCode == 200) {
          final resolved =
              NevoboTeam(code: team.code, category: category, number: team.number);
          _resolvedTeamByCode[team.code] = resolved;
          return resolved;
        }
      } catch (_) {
        // keep trying
      }
    }

    _resolvedTeamByCode[team.code] = team;
    return team;
  }

  static List<String> _categoryCandidates(String code, String preferred) {
    final prefix = RegExp(r'^([A-Z]{2})').firstMatch(code)?.group(1) ?? '';

    final list = <String>[preferred];
    switch (prefix) {
      case 'MR':
        list.addAll(const [
          'mix',
          'mix-recreanten',
          'recreanten',
          'recreanten-mix',
          'mix-recreatie',
          'mix-recreatief',
          'mix-senioren',
        ]);
        break;
      case 'JA':
        list.addAll(const [
          'jongens-a',
          'jongens-a-jeugd',
          'jongens-a-competitie',
        ]);
        break;
      case 'JC':
        list.addAll(const [
          'jongens-c',
          'jongens-c-jeugd',
          'jongens-c-1',
          'jongens-c-competitie',
        ]);
        break;
      case 'JD':
        list.addAll(const [
          'jongens-d',
          'jongens-d-jeugd',
          'jongens-d-competitie',
        ]);
        break;
      case 'MA':
        list.addAll(const [
          'meiden-a',
          'meiden-a-jeugd',
          'meiden-a-competitie',
        ]);
        break;
      case 'MC':
        list.addAll(const [
          'meiden-c',
          'meiden-c-jeugd',
          'meiden-c-competitie',
        ]);
        break;
      case 'MD':
        list.addAll(const [
          'meiden-d',
          'meiden-d-jeugd',
          'meiden-d-competitie',
        ]);
        break;
      default:
        break;
    }

    final seen = <String>{};
    final out = <String>[];
    for (final c in list) {
      final v = c.trim().toLowerCase();
      if (v.isEmpty) continue;
      if (seen.add(v)) out.add(v);
    }
    return out;
  }

  static List<dynamic>? _asList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map && decoded['hydra:member'] is List) {
      return (decoded['hydra:member'] as List);
    }
    return null;
  }

  static List<String> _asStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }

  static List<int>? _asIntList(dynamic value) {
    if (value is List) {
      final out = <int>[];
      for (final v in value) {
        if (v is int) out.add(v);
        if (v is num) out.add(v.toInt());
        if (v is String) {
          final p = int.tryParse(v.trim());
          if (p != null) out.add(p);
        }
      }
      return out.isEmpty ? null : out;
    }
    return null;
  }

  static Future<String> _resolveIriName(String iri) async {
    final cached = _iriNameCache[iri];
    if (cached != null) return cached;
    try {
      final url = iri.startsWith('http') ? iri : 'https://api.nevobo.nl$iri';
      final res = await http.get(Uri.parse(url), headers: const {'Accept': 'application/json'});
      if (res.statusCode != 200) {
        _iriNameCache[iri] = iri;
        return iri;
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      String? name;
      if (decoded is Map) {
        final m = decoded.cast<String, dynamic>();
        name = _readString(m, const ['naam', 'name', 'teamNaam', 'teamnaam', 'omschrijving', 'displayName']);
      } else if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        final m = (decoded.first as Map).cast<String, dynamic>();
        name = _readString(m, const ['naam', 'name', 'teamNaam', 'teamnaam', 'omschrijving', 'displayName']);
      }
      final v = (name == null || name.trim().isEmpty) ? iri : name.trim();
      _iriNameCache[iri] = v;
      return v;
    } catch (_) {
      _iriNameCache[iri] = iri;
      return iri;
    }
  }

  static Future<String?> _resolveSporthal(String iri) async {
    final cached = _sporthalCache[iri];
    if (cached != null) return cached.isEmpty ? null : cached;
    try {
      final url = iri.startsWith('http') ? iri : 'https://api.nevobo.nl$iri';
      final res = await http.get(Uri.parse(url), headers: const {'Accept': 'application/json'});
      if (res.statusCode != 200) {
        _sporthalCache[iri] = '';
        return null;
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));

      Map<String, dynamic>? m;
      if (decoded is Map) m = decoded.cast<String, dynamic>();
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        m = (decoded.first as Map).cast<String, dynamic>();
      }
      if (m == null) {
        _sporthalCache[iri] = '';
        return null;
      }

      final name = _readString(m, const ['naam', 'name', 'omschrijving']) ?? '';
      final plaats = _readString(m, const ['plaats', 'city']) ?? '';

      String? addr;
      final adres = m['adres'];
      if (adres is Map) {
        final a = adres.cast<String, dynamic>();
        final straat = _readString(a, const ['straat', 'street']) ?? '';
        final huisnr = _readString(a, const ['huisnummer', 'number', 'huisnr']) ?? '';
        final postcode = _readString(a, const ['postcode', 'zip']) ?? '';
        final p = _readString(a, const ['plaats', 'city']) ?? plaats;
        final parts = <String>[
          [straat, huisnr].where((x) => x.trim().isNotEmpty).join(' ').trim(),
          [postcode, p].where((x) => x.trim().isNotEmpty).join(' ').trim(),
        ].where((x) => x.trim().isNotEmpty).toList();
        addr = parts.isEmpty ? null : parts.join(', ');
      }

      final labelParts = <String>[
        name.trim(),
        (addr ?? '').trim(),
        (addr == null ? plaats.trim() : '').trim(),
      ].where((x) => x.isNotEmpty).toList();

      final label = labelParts.isEmpty ? '' : labelParts.join(', ');
      _sporthalCache[iri] = label;
      return label.isEmpty ? null : label;
    } catch (_) {
      _sporthalCache[iri] = '';
      return null;
    }
  }

  static Future<List<NevoboStandingEntry>> fetchStandingsForTeam({
    required NevoboTeam team,
  }) async {
    final resolvedTeam = await _resolveTeam(team);
    // Step 1: resolve the poule URL for the team
    final teamUri = Uri.parse(
      'https://api.nevobo.nl/competitie/pouleindelingen?team=${Uri.encodeComponent(resolvedTeam.teamPath)}',
    );
    final teamRes = await http.get(teamUri);
    if (teamRes.statusCode != 200) {
      throw Exception('Team poule HTTP ${teamRes.statusCode}');
    }

    final decodedTeam = jsonDecode(utf8.decode(teamRes.bodyBytes));
    final poulePath = _extractPoulePath(decodedTeam);
    if (poulePath == null || poulePath.isEmpty) {
      throw Exception('Kon poule niet bepalen voor ${team.code}');
    }

    // Step 2: fetch poule standings
    final pouleUri = Uri.parse(
      'https://api.nevobo.nl/competitie/pouleindelingen?poule=${Uri.encodeComponent(poulePath)}',
    );
    final pouleRes = await http.get(pouleUri);
    if (pouleRes.statusCode != 200) {
      throw Exception('Poule HTTP ${pouleRes.statusCode}');
    }

    final decodedPoule = jsonDecode(utf8.decode(pouleRes.bodyBytes));
    final standings = await _resolveStandingNames(_parseStandings(decodedPoule));
    if (kDebugMode) {
      debugPrint('Nevobo standings: ${resolvedTeam.code} -> ${standings.length} entries');
    }
    return standings;
  }

  static String? _extractPoulePath(dynamic decoded) {
    // The endpoint may return multiple entries (e.g. first half / second half).
    // We try to pick the most relevant one for "now" (or otherwise the latest).

    String? extractFromMap(Map<String, dynamic> m) {
      // Direct keys
      for (final k in const ['poule', 'pouleUrl', 'poule_path', 'poulePath', 'href']) {
        final v = m[k];
        if (v is String && v.startsWith('/competitie/poules/')) return v;
        if (v is String && v.contains('/competitie/poules/')) {
          final idx = v.indexOf('/competitie/poules/');
          return v.substring(idx);
        }
        if (v is Map) {
          final inner = v.cast<String, dynamic>();
          final url = inner['url'] ?? inner['href'] ?? inner['poule'];
          if (url is String && url.startsWith('/competitie/poules/')) return url;
        }
      }

      // Search any string value that looks like a poule path
      for (final entry in m.entries) {
        final v = entry.value;
        if (v is String && v.startsWith('/competitie/poules/')) return v;
      }

      return null;
    }

    DateTime? tryParseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    int scoreCandidate(Map<String, dynamic> m, String poulePath) {
      final now = DateTime.now();
      final lowerText = m.values
          .whereType<Object?>()
          .map((e) => e?.toString().toLowerCase() ?? '')
          .join(' ');
      final lowerPoulePath = poulePath.toLowerCase();

      DateTime? start = tryParseDate(
        m['startDatum'] ?? m['startdatum'] ?? m['starts_at'] ?? m['start'] ?? m['beginDatum'] ?? m['begin'] ?? m['van'],
      );
      DateTime? end = tryParseDate(
        m['eindDatum'] ?? m['einddatum'] ?? m['ends_at'] ?? m['end'] ?? m['tot'] ?? m['einde'] ?? m['datumTot'],
      );

      // Prefer entries active "now"
      final startOk = start == null || !now.isBefore(start.toLocal());
      final endOk = end == null || !now.isAfter(end.toLocal());
      int score = 0;
      if (startOk && endOk) score += 1_000_000;

      // Prefer second half / later phases if the API includes such text (common in poule path).
      final looksSecondHalf = lowerPoulePath.contains('tweede-helft') ||
          lowerPoulePath.contains('2e-helft') ||
          lowerPoulePath.contains('voorjaar') ||
          lowerPoulePath.contains('fase-2') ||
          lowerText.contains('tweede-helft') ||
          lowerText.contains('2e-helft') ||
          lowerText.contains('voorjaar') ||
          lowerText.contains('fase 2');
      final looksFirstHalf = lowerPoulePath.contains('eerste-helft') ||
          lowerPoulePath.contains('najaars') ||
          lowerText.contains('eerste-helft') ||
          lowerText.contains('najaars');
      if (looksSecondHalf) score += 50_000;
      if (looksFirstHalf) score -= 10_000;

      // Prefer the most recent start date if multiple remain.
      final startEpoch = start?.toUtc().millisecondsSinceEpoch ?? 0;
      score += startEpoch ~/ 10_000; // keep it bounded-ish

      // Minor tie-breaker: longer/unique poule path tends to be newer in practice.
      score += poulePath.length;
      return score;
    }

    if (decoded is List) {
      final candidates = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is Map) candidates.add(item.cast<String, dynamic>());
      }
      if (candidates.isEmpty) return null;

      String? bestPath;
      int bestScore = -1;
      for (final m in candidates) {
        final path = extractFromMap(m);
        if (path == null || path.isEmpty) continue;
        final score = scoreCandidate(m, path);
        if (score > bestScore) {
          bestScore = score;
          bestPath = path;
        }
      }
      if (kDebugMode && candidates.length > 1) {
        final allPaths = candidates
            .map((m) => extractFromMap(m))
            .whereType<String>()
            .where((p) => p.isNotEmpty)
            .toList();
        if (allPaths.isNotEmpty) {
          debugPrint('Nevobo poule candidates: ${allPaths.join(' | ')} -> selected: $bestPath');
        }
      }
      if (bestPath != null) return bestPath;

      // Fallback: try first map if nothing scored.
      return extractFromMap(candidates.first);
    }

    if (decoded is Map) {
      return extractFromMap(decoded.cast<String, dynamic>());
    }

    return null;
  }

  static List<NevoboStandingEntry> _parseStandings(dynamic decoded) {
    if (decoded is! List) return const [];
    final list = decoded.cast<dynamic>();
    final result = <NevoboStandingEntry>[];
    for (final item in list) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();

      final pos = _readInt(m, const ['positie', 'plaats', 'rank', 'position']) ?? 0;
      final played = _readInt(m, const ['gespeeld', 'wedstrijden', 'played']) ?? 0;
      final points = _readInt(m, const ['punten', 'point', 'points']) ?? 0;

      final teamPath = _extractTeamPath(m);
      String teamName =
          _readString(m, const ['teamNaam', 'teamnaam', 'naam', 'name']) ?? '';
      // Some APIs store the team as a nested object with a name.
      if (teamName.isEmpty && m['team'] is Map) {
        final t = (m['team'] as Map).cast<String, dynamic>();
        teamName = _readString(t, const ['naam', 'name', 'teamNaam', 'teamnaam']) ?? '';
      }
      // Or as a URL/path string.
      if (teamName.isEmpty && m['team'] is String) {
        teamName = (m['team'] as String);
      }

      result.add(
        NevoboStandingEntry(
          position: pos,
          teamName: teamName.isEmpty ? '-' : teamName,
          teamPath: teamPath,
          played: played,
          points: points,
        ),
      );
    }

    // Keep a stable ordering
    result.sort((a, b) {
      if (a.position == 0 && b.position == 0) return 0;
      if (a.position == 0) return 1;
      if (b.position == 0) return -1;
      return a.position.compareTo(b.position);
    });
    return result;
  }

  static String? _extractTeamPath(Map<String, dynamic> m) {
    // Direct string
    for (final k in const ['team', 'teamUrl', 'team_url', 'href', 'url']) {
      final v = m[k];
      if (v is String && v.startsWith('/competitie/teams/')) return v;
      if (v is Map) {
        final inner = v.cast<String, dynamic>();
        final url = inner['url'] ?? inner['href'] ?? inner['team'];
        if (url is String && url.startsWith('/competitie/teams/')) return url;
      }
    }
    // Search any value that looks like a team path
    for (final entry in m.entries) {
      final v = entry.value;
      if (v is String && v.startsWith('/competitie/teams/')) return v;
    }
    return null;
  }

  static Future<List<NevoboStandingEntry>> _resolveStandingNames(
    List<NevoboStandingEntry> entries,
  ) async {
    final paths = <String>{};
    for (final e in entries) {
      final p = e.teamPath;
      if (p == null || p.isEmpty) continue;
      // If the visible "name" is still a path, we must resolve it.
      if (e.teamName.startsWith('/competitie/teams/')) {
        paths.add(p);
      }
    }
    if (paths.isEmpty) return entries;

    for (final p in paths) {
      await _resolveTeamName(p);
    }

    return entries
        .map((e) {
          final p = e.teamPath;
          if (p == null) return e;
          final resolved = _teamNameCacheByPath[p];
          if (resolved == null || resolved.trim().isEmpty) return e;
          if (!e.teamName.startsWith('/competitie/teams/')) return e;
          return NevoboStandingEntry(
            position: e.position,
            teamName: resolved,
            teamPath: e.teamPath,
            played: e.played,
            points: e.points,
          );
        })
        .toList();
  }

  static Future<void> _resolveTeamName(String teamPath) async {
    if (_teamNameCacheByPath.containsKey(teamPath)) return;
    try {
      final uri = Uri.parse('https://api.nevobo.nl$teamPath');
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        _teamNameCacheByPath[teamPath] = teamPath;
        return;
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      String? name;

      if (decoded is Map) {
        final m = decoded.cast<String, dynamic>();
        name = _readString(m, const ['naam', 'name', 'teamNaam', 'teamnaam', 'omschrijving']);
      } else if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        final m = (decoded.first as Map).cast<String, dynamic>();
        name = _readString(m, const ['naam', 'name', 'teamNaam', 'teamnaam', 'omschrijving']);
      }

      _teamNameCacheByPath[teamPath] = (name == null || name.trim().isEmpty) ? teamPath : name;
    } catch (_) {
      _teamNameCacheByPath[teamPath] = teamPath;
    }
  }

  static int? _readInt(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final p = int.tryParse(v.trim());
        if (p != null) return p;
      }
    }
    return null;
  }

  static String? _readString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String) return v;
    }
    return null;
  }
}

