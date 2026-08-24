import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/auth/auth_email_change_pending.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('consumePendingEmailChangeIfConfirmed', () {
    test('returns true when pending matches current email', () async {
      await setPendingEmailChange(
        userId: 'user-1',
        email: 'New@Example.com',
      );

      final confirmed = await consumePendingEmailChangeIfConfirmed(
        userId: 'user-1',
        currentEmail: 'new@example.com',
      );

      expect(confirmed, isTrue);
      expect(
        await consumePendingEmailChangeIfConfirmed(
          userId: 'user-1',
          currentEmail: 'new@example.com',
        ),
        isFalse,
      );
    });

    test('returns false when pending does not match', () async {
      await setPendingEmailChange(
        userId: 'user-1',
        email: 'new@example.com',
      );

      final confirmed = await consumePendingEmailChangeIfConfirmed(
        userId: 'user-1',
        currentEmail: 'old@example.com',
      );

      expect(confirmed, isFalse);
    });
  });
}
