import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/profiel/account_link_code.dart';

void main() {
  group('account link code', () {
    test('normaliseert kleine letters, spaties en streepjes', () {
      expect(normalizeAccountLinkCode(' ab-c 123 '), 'ABC123');
    });

    test('accepteert exact zes hexadecimale tekens', () {
      expect(isValidAccountLinkCode('aBc123'), isTrue);
      expect(isValidAccountLinkCode('ABC12'), isFalse);
      expect(isValidAccountLinkCode('ABC12G'), isFalse);
    });
  });
}
