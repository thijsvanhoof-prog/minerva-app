/// Nederlandse feestdagen (vrije dagen) voor uitsluiting bij trainingen.
///
/// Gebaseerd op officiële feestdagen in Nederland.

/// Berekent de datum van Paaszondag voor een gegeven jaar (Oudin-algoritme).
DateTime _easterSunday(int year) {
  final g = year % 19;
  final c = year ~/ 100;
  final h = (c - c ~/ 4 - (8 * c + 13) ~/ 25 + 19 * g + 15) % 30;
  final i = h - (h ~/ 28) * (1 - (h ~/ 28) * (29 ~/ (h + 1)) * ((21 - g) ~/ 11));
  final j = (year + year ~/ 4 + i + 2 - c + c ~/ 4) % 7;
  final l = i - j;
  final month = 3 + (l + 40) ~/ 44;
  final day = l + 28 - 31 * (month ~/ 4);
  return DateTime(year, month, day);
}

/// Geeft alle Nederlandse feestdagen voor een gegeven jaar (als datum-only).
///
/// Inclusief: Nieuwjaarsdag, Tweede Paasdag, Koningsdag, Bevrijdingsdag,
/// Hemelvaartsdag, Tweede Pinksterdag, Eerste en Tweede Kerstdag.
Set<DateTime> dutchHolidaysInYear(int year) {
  final easter = _easterSunday(year);
  final holidays = <DateTime>{};

  // 1 januari – Nieuwjaarsdag
  holidays.add(DateTime(year, 1, 1));

  // Tweede Paasdag (maandag na Pasen)
  holidays.add(easter.add(const Duration(days: 1)));

  // Koningsdag: 27 april, of 26 april als 27e op zondag valt
  final koningsdag = DateTime(year, 4, 27);
  if (koningsdag.weekday == DateTime.sunday) {
    holidays.add(DateTime(year, 4, 26));
  } else {
    holidays.add(koningsdag);
  }

  // 5 mei – Bevrijdingsdag
  holidays.add(DateTime(year, 5, 5));

  // Hemelvaartsdag (39 dagen na Pasen)
  holidays.add(easter.add(const Duration(days: 39)));

  // Tweede Pinksterdag (50 dagen na Pasen)
  holidays.add(easter.add(const Duration(days: 50)));

  // 25 en 26 december – Kerst
  holidays.add(DateTime(year, 12, 25));
  holidays.add(DateTime(year, 12, 26));

  return holidays;
}

/// Controleert of [date] een Nederlandse feestdag is.
bool isDutchHoliday(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return dutchHolidaysInYear(date.year).any((h) =>
      h.year == d.year && h.month == d.month && h.day == d.day);
}
