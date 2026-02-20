/// Central display-name overrides for the app UI.
///
/// Use this when rendering user display names coming from Supabase.

/// Fallback wanneer geen gebruikersnaam of e-mail bekend is (nooit ID tonen in UI).
const String unknownUserName = 'Onbekend';

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

