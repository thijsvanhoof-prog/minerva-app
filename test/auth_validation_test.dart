import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/auth/auth_validation.dart';

void main() {
  group('isValidEmail', () {
    test('accepts valid email', () {
      expect(isValidEmail('user@example.com'), isTrue);
    });

    test('rejects empty email', () {
      expect(isValidEmail(''), isFalse);
      expect(isValidEmail('   '), isFalse);
    });

    test('rejects email without @', () {
      expect(isValidEmail('userexample.com'), isFalse);
    });

    test('rejects email without domain extension', () {
      expect(isValidEmail('user@example'), isFalse);
    });
  });

  group('isPasswordLongEnough', () {
    test('rejects password shorter than 6 characters', () {
      expect(isPasswordLongEnough('12345'), isFalse);
    });

    test('accepts password with 6 characters', () {
      expect(isPasswordLongEnough('123456'), isTrue);
    });
  });

  group('passwordsMatch', () {
    test('accepts matching passwords', () {
      expect(passwordsMatch('secret123', 'secret123'), isTrue);
    });

    test('rejects different passwords', () {
      expect(passwordsMatch('secret123', 'secret124'), isFalse);
    });
  });
}
