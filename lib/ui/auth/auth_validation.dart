/// Pure validatiehelpers voor auth-formulieren (testbaar zonder Supabase/UI).
bool isValidEmail(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(trimmed);
}

bool isPasswordLongEnough(String password, {int minLength = 6}) {
  return password.length >= minLength;
}

bool passwordsMatch(String password, String confirmation) {
  return password == confirmation;
}
