import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/shell_navigation.dart';

void main() {
  group('shellTabIdsForUser', () {
    test('gast ziet Home, Contact, Profiel', () {
      expect(
        shellTabIdsForUser(isGuest: true),
        [ShellTabId.home, ShellTabId.contact, ShellTabId.profiel],
      );
    });

    test('eigen account ziet alle zes tabs', () {
      expect(shellTabIdsForUser(isGuest: false), ownAccountShellTabIds);
      expect(shellTabIdsForUser(isGuest: false).length, 6);
    });
  });

  group('remapShellTabIndex', () {
    test('login op Profiel blijft Profiel', () {
      expect(
        remapShellTabIndex(
          storedIndex: 2,
          previousTabs: guestShellTabIds,
          newTabs: ownAccountShellTabIds,
        ),
        shellTabIndexForId(ownAccountShellTabIds, ShellTabId.profiel),
      );
    });

    test('login op Contact blijft Contact', () {
      expect(
        remapShellTabIndex(
          storedIndex: 1,
          previousTabs: guestShellTabIds,
          newTabs: ownAccountShellTabIds,
        ),
        shellTabIndexForId(ownAccountShellTabIds, ShellTabId.contact),
      );
    });

    test('logout op Contact blijft Contact', () {
      expect(
        remapShellTabIndex(
          storedIndex: shellTabIndexForId(ownAccountShellTabIds, ShellTabId.contact),
          previousTabs: ownAccountShellTabIds,
          newTabs: guestShellTabIds,
        ),
        shellTabIndexForId(guestShellTabIds, ShellTabId.contact),
      );
    });

    test('logout op Teams gaat naar Home', () {
      final idx = remapShellTabIndex(
        storedIndex: shellTabIndexForId(ownAccountShellTabIds, ShellTabId.teams),
        previousTabs: ownAccountShellTabIds,
        newTabs: guestShellTabIds,
      );
      expect(idx, shellTabIndexForId(guestShellTabIds, ShellTabId.home));
    });
  });
}
