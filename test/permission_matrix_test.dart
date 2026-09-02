import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/app_user_context.dart';

Future<T> _readContextValue<T>({
  required WidgetTester tester,
  required String profileId,
  required List<String> committees,
  required bool isGlobalAdmin,
  required bool isCommitteePowerAdmin,
  required T Function(AppUserContext ctx) read,
}) async {
  late T value;
  await tester.pumpWidget(
    MaterialApp(
      home: AppUserContext(
        profileId: profileId,
        email: 'test@example.com',
        displayName: 'Test',
        isGlobalAdmin: isGlobalAdmin,
        isCommitteePowerAdmin: isCommitteePowerAdmin,
        memberships: const [],
        committees: committees,
        loggedInProfileId: profileId.isEmpty ? '' : profileId,
        child: Builder(
          builder: (context) {
            value = read(AppUserContext.of(context));
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return value;
}

void main() {
  group('permission matrix via AppUserContext', () {
    testWidgets('alleen bestuur kan agenda en nieuws beheren', (tester) async {
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const ['bestuur'],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: false,
          read: (ctx) => ctx.canManageAgenda,
        ),
        isTrue,
      );
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const ['bestuur'],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: false,
          read: (ctx) => ctx.canManageNews,
        ),
        isTrue,
      );
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const ['bestuur'],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: false,
          read: (ctx) => ctx.canManageMatches,
        ),
        isFalse,
      );
    });

    testWidgets('alleen wedstrijdzaken kan matches en taken beheren', (tester) async {
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const ['wedstrijdzaken'],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: false,
          read: (ctx) => ctx.canManageMatches,
        ),
        isTrue,
      );
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const ['wedstrijdzaken'],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: false,
          read: (ctx) => ctx.canViewAllTasks,
        ),
        isTrue,
      );
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const ['wedstrijdzaken'],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: false,
          read: (ctx) => ctx.canManageNews,
        ),
        isFalse,
      );
    });

    testWidgets('alleen TC kan teams beheren', (tester) async {
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const ['technische-commissie'],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: false,
          read: (ctx) => ctx.canManageTeams,
        ),
        isTrue,
      );
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const ['technische-commissie'],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: false,
          read: (ctx) => ctx.canManageTc,
        ),
        isTrue,
      );
    });

    testWidgets('committee power admin zonder commissie in Contact-context', (tester) async {
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const [],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: true,
          read: (ctx) => ctx.committees,
        ),
        isEmpty,
      );
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const [],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: true,
          read: (ctx) => ctx.canManageAccounts,
        ),
        isTrue,
      );
    });

    testWidgets('communicatie + evenementen cumuleren agenda-rechten', (tester) async {
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const ['communicatie', 'evenementen'],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: false,
          read: (ctx) => ctx.canManageAgenda,
        ),
        isTrue,
      );
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const ['communicatie', 'evenementen'],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: false,
          read: (ctx) => ctx.canExportAgendaRsvps,
        ),
        isTrue,
      );
    });

    testWidgets('jeugdcommissie kan agenda maar niet exporteren', (tester) async {
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const ['jeugdcommissie'],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: false,
          read: (ctx) => ctx.canManageAgenda,
        ),
        isTrue,
      );
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const ['jeugdcommissie'],
          isGlobalAdmin: false,
          isCommitteePowerAdmin: false,
          read: (ctx) => ctx.canExportAgendaRsvps,
        ),
        isFalse,
      );
    });

    testWidgets('global admin heeft alle beheerrechten', (tester) async {
      expect(
        await _readContextValue(
          tester: tester,
          profileId: 'u1',
          committees: const [],
          isGlobalAdmin: true,
          isCommitteePowerAdmin: false,
          read: (ctx) => (
            ctx.canManageAgenda,
            ctx.canManageNews,
            ctx.canManageTeams,
            ctx.canManageMatches,
            ctx.canManageAccounts,
          ),
        ),
        (true, true, true, true, true),
      );
    });
  });
}
