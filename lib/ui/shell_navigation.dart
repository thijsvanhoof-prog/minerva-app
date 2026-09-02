/// Identifiers voor bottom-navigation tabs in [Shell].
enum ShellTabId {
  home,
  teams,
  commissies,
  contact,
  taken,
  profiel,
}

/// Tablabels voor gastaccounts.
const guestShellTabIds = [
  ShellTabId.home,
  ShellTabId.contact,
  ShellTabId.profiel,
];

/// Tablabels voor ingelogde eigen accounts.
const ownAccountShellTabIds = [
  ShellTabId.home,
  ShellTabId.teams,
  ShellTabId.commissies,
  ShellTabId.contact,
  ShellTabId.taken,
  ShellTabId.profiel,
];

/// Bepaalt welke tabs zichtbaar zijn.
List<ShellTabId> shellTabIdsForUser({required bool isGuest}) {
  return isGuest ? guestShellTabIds : ownAccountShellTabIds;
}

/// Index van een tab op basis van id; -1 als niet aanwezig.
int shellTabIndexForId(List<ShellTabId> tabs, ShellTabId id) {
  return tabs.indexOf(id);
}

/// Behoudt de geselecteerde tab bij wissel tussen gast- en eigen-account layout.
int remapShellTabIndex({
  required int storedIndex,
  required List<ShellTabId> previousTabs,
  required List<ShellTabId> newTabs,
}) {
  if (newTabs.isEmpty) return 0;
  if (storedIndex >= 0 && storedIndex < previousTabs.length) {
    final selected = previousTabs[storedIndex];
    final remapped = shellTabIndexForId(newTabs, selected);
    if (remapped >= 0) return remapped;
  }
  return 0;
}
