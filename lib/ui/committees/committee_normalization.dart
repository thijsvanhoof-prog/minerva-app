/// Pure normalisatie van commissienamen naar canonieke sleutels.
String normalizeCommitteeKey(String value) {
  final c = value.trim().toLowerCase();
  if (c.isEmpty) return '';
  if (c.contains('bestuur')) return 'bestuur';
  if (c == 'tc' || c.contains('technische')) return 'technische-commissie';
  if (c == 'cc' || c.contains('communicatie')) return 'communicatie';
  if (c == 'wz' || c.contains('wedstrijd')) return 'wedstrijdzaken';
  if (c.contains('evenement')) return 'evenementen';
  if (c.contains('jeugd')) return 'jeugdcommissie';
  if ((c.contains('scheidsrechter') && c.contains('teller')) ||
      c.contains('scheidsrechters-tellers') ||
      c.contains('scheidsrechters/tellers')) {
    return 'scheidsrechters-tellers';
  }
  if (c.contains('vrijwilliger')) return 'vrijwilligers';
  return c;
}
