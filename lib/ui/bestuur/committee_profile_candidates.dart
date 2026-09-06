import 'package:minerva_app/ui/display_name_overrides.dart'
    show applyDisplayNameOverrides, unknownUserName;

/// RPC-volgorde voor commissiebeheer (alle toegankelijke bronnen worden samengevoegd).
const kCommitteeManagementProfileRpcs = [
  'list_profiles_for_committee_management',
  'admin_list_profiles',
  'get_profiles_for_tc',
];

/// Gedeeld gastaccount: nooit als commissiekandidaat tonen.
const kHiddenCommitteeCandidateEmails = {'gast@mail.com'};

class CommitteeProfileCandidate {
  final String profileId;
  final String name;
  final String? email;

  const CommitteeProfileCandidate({
    required this.profileId,
    required this.name,
    this.email,
  });
}

bool isUsableCommitteeCandidateName(String name) {
  final trimmed = name.trim();
  return trimmed.isNotEmpty && trimmed != unknownUserName;
}

CommitteeProfileCandidate parseCommitteeProfileRow(Map<String, dynamic> row) {
  final id = (row['profile_id'] ?? row['id'])?.toString() ?? '';
  final rawName = (row['display_name'] ?? row['full_name'] ?? row['name'] ?? '')
      .toString()
      .trim();
  final name = applyDisplayNameOverrides(rawName);
  final email = (row['email'] ?? '').toString().trim();
  return CommitteeProfileCandidate(
    profileId: id,
    name: name.isNotEmpty ? name : (email.isNotEmpty ? email : unknownUserName),
    email: email.isNotEmpty ? email : null,
  );
}

List<CommitteeProfileCandidate> parseCommitteeProfileRows(
  List<dynamic>? rawRows,
) {
  final rows =
      rawRows?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
  final out = <CommitteeProfileCandidate>[];
  for (final row in rows) {
    final candidate = parseCommitteeProfileRow(row);
    if (candidate.profileId.isEmpty) continue;
    out.add(candidate);
  }
  return out;
}

CommitteeProfileCandidate mergeCommitteeProfileCandidatePair(
  CommitteeProfileCandidate a,
  CommitteeProfileCandidate b,
) {
  assert(a.profileId == b.profileId);
  final name = _pickRicherCandidateName(a.name, b.name);
  final email = (a.email?.trim().isNotEmpty == true)
      ? a.email!.trim()
      : (b.email?.trim().isNotEmpty == true ? b.email!.trim() : null);
  return CommitteeProfileCandidate(
    profileId: a.profileId,
    name: name,
    email: email,
  );
}

String _pickRicherCandidateName(String a, String b) {
  final aUsable = isUsableCommitteeCandidateName(a);
  final bUsable = isUsableCommitteeCandidateName(b);
  if (aUsable && !bUsable) return a;
  if (bUsable && !aUsable) return b;
  if (!aUsable && !bUsable) return a;

  if (a.trim().length != b.trim().length) {
    return a.trim().length > b.trim().length ? a : b;
  }
  return a.toLowerCase().compareTo(b.toLowerCase()) <= 0 ? a : b;
}

/// Voegt meerdere profiellijsten samen op [profileId] (deterministisch, vult naam/e-mail aan).
List<CommitteeProfileCandidate> mergeCommitteeProfileCandidates(
  Iterable<List<CommitteeProfileCandidate>> sources,
) {
  final byId = <String, CommitteeProfileCandidate>{};
  for (final list in sources) {
    for (final candidate in list) {
      if (candidate.profileId.isEmpty) continue;
      final existing = byId[candidate.profileId];
      byId[candidate.profileId] = existing == null
          ? candidate
          : mergeCommitteeProfileCandidatePair(existing, candidate);
    }
  }

  final merged = byId.values.toList()
    ..sort((a, b) {
      final nameCmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (nameCmp != 0) return nameCmp;
      final emailA = (a.email ?? '').toLowerCase();
      final emailB = (b.email ?? '').toLowerCase();
      return emailA.compareTo(emailB);
    });
  return merged;
}

bool isHiddenCommitteeCandidateEmail(String? email) {
  final normalized = email?.trim().toLowerCase() ?? '';
  return normalized.isNotEmpty &&
      kHiddenCommitteeCandidateEmails.contains(normalized);
}

bool isHiddenCommitteeCandidate(CommitteeProfileCandidate candidate) {
  return isHiddenCommitteeCandidateEmail(candidate.email);
}

/// Sluit alleen het gastaccount uit; nooit op [account_role].
List<CommitteeProfileCandidate> filterVisibleCommitteeCandidates(
  Iterable<CommitteeProfileCandidate> candidates,
) {
  return candidates
      .where((candidate) => !isHiddenCommitteeCandidate(candidate))
      .toList();
}

/// Kandidaten voor één commissie: sluit alleen bestaande leden van die commissie uit.
List<CommitteeProfileCandidate> availableCommitteeCandidates({
  required Iterable<CommitteeProfileCandidate> allCandidates,
  required Set<String> existingMemberProfileIds,
}) {
  return allCandidates
      .where(
        (candidate) => !existingMemberProfileIds.contains(candidate.profileId),
      )
      .toList();
}

/// Case-insensitive zoeken op naam en e-mail.
List<CommitteeProfileCandidate> searchCommitteeCandidates(
  Iterable<CommitteeProfileCandidate> candidates,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return candidates is List<CommitteeProfileCandidate>
        ? candidates
        : candidates.toList();
  }
  return candidates
      .where(
        (candidate) =>
            candidate.name.toLowerCase().contains(q) ||
            (candidate.email?.toLowerCase().contains(q) ?? false),
      )
      .toList();
}

List<CommitteeProfileCandidate> mergeCommitteeProfileRowsFromRpcResults(
  Iterable<List<dynamic>?> rpcResults,
) {
  final sources = rpcResults
      .map(parseCommitteeProfileRows)
      .where((list) => list.isNotEmpty)
      .toList();
  return filterVisibleCommitteeCandidates(
    mergeCommitteeProfileCandidates(sources),
  );
}
