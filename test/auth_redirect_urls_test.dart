import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/auth/auth_redirect_urls.dart';

void main() {
  group('isEmailChangeDeepLink', () {
    test('accepts email-change host on app scheme', () {
      expect(
        isEmailChangeDeepLink(Uri.parse('nl.minerva.clubapp://email-change/')),
        isTrue,
      );
    });

    test('rejects reset-password host', () {
      expect(
        isEmailChangeDeepLink(Uri.parse('nl.minerva.clubapp://reset-password/')),
        isFalse,
      );
    });

    test('rejects other schemes', () {
      expect(
        isEmailChangeDeepLink(Uri.parse('https://example.com/email-change/')),
        isFalse,
      );
    });
  });
}
