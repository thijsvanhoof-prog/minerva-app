/// Central display-name overrides for the app UI.
///
/// Use this when rendering user display names coming from Supabase.
String applyDisplayNameOverrides(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return trimmed;

  // Case-insensitive + tolerate weird spacing ("DARTH   vAdEr").
  final normalized = trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized == 'darth vader' || normalized == 'eindbaas') {
    return 'Max Hubben';
  }

  return trimmed;
}

