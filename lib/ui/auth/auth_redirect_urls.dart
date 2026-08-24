import 'package:flutter_dotenv/flutter_dotenv.dart';

const authDeepLinkScheme = 'nl.minerva.clubapp';

String? supabaseResetRedirectUrl() {
  final value = (dotenv.env['SUPABASE_RESET_REDIRECT_URL'] ?? '').trim();
  return value.isNotEmpty ? value : null;
}

String? supabaseEmailChangeRedirectUrl() {
  final value = (dotenv.env['SUPABASE_EMAIL_CHANGE_REDIRECT_URL'] ?? '').trim();
  return value.isNotEmpty ? value : null;
}

/// Deep link terug naar de app na bevestiging van e-mail wijzigen.
bool isEmailChangeDeepLink(Uri uri) {
  return uri.scheme == authDeepLinkScheme && uri.host == 'email-change';
}
