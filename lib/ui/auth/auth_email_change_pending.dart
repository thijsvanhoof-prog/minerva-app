import 'package:shared_preferences/shared_preferences.dart';

String _pendingEmailChangeKey(String userId) => 'pending_email_change_$userId';

Future<void> setPendingEmailChange({
  required String userId,
  required String email,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _pendingEmailChangeKey(userId),
    email.trim().toLowerCase(),
  );
}

/// Returns true when a pending e-mail change matches the confirmed auth e-mail.
Future<bool> consumePendingEmailChangeIfConfirmed({
  required String userId,
  required String? currentEmail,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final key = _pendingEmailChangeKey(userId);
  final pending = prefs.getString(key)?.trim().toLowerCase();
  final current = currentEmail?.trim().toLowerCase();
  if (pending == null || pending.isEmpty || current != pending) {
    return false;
  }
  await prefs.remove(key);
  return true;
}
