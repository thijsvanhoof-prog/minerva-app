import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/app_user_context.dart';
import 'package:minerva_app/ui/commissies/commissies_tab.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _testSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
    'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV4YW1wbGUiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTY0NTk2MzUwMCwiZXhwIjoxOTYxNTM5NTAwfQ.'
    'dc_X5iR_VP_qT0zsjJtcB6NSHBiivr7-7R5yNYC9j0';

class _TestGotrueAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> removeItem({required String key}) async {
    _data.remove(key);
  }

  @override
  Future<String?> getItem({required String key}) async => _data[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _data[key] = value;
  }
}

Widget _buildCommissiesHarness({required Size viewportSize}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: viewportSize),
      child: AppUserContext(
        profileId: 'admin-user',
        email: 'admin@test.nl',
        displayName: 'Admin User',
        isGlobalAdmin: true,
        isCommitteePowerAdmin: true,
        memberships: const [],
        committees: const ['bestuur', 'technische-commissie'],
        loggedInProfileId: 'admin-user',
        reloadUserContext: () async {},
        child: SizedBox(
          width: viewportSize.width,
          height: viewportSize.height,
          child: const CommissiesTab(),
        ),
      ),
    ),
  );
}

Future<void> _pumpCommissiesTab(
  WidgetTester tester, {
  required Size viewportSize,
}) async {
  await tester.pumpWidget(_buildCommissiesHarness(viewportSize: viewportSize));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: _testSupabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _TestGotrueAsyncStorage(),
      ),
    );
  });

  group('CommissiesTab layout', () {
    testWidgets('breed scherm: geen intrinsic-dimensions exception', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpCommissiesTab(tester, viewportSize: const Size(800, 900));

      expect(tester.takeException(), isNull);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Bestuur'), findsOneWidget);
      expect(find.text('TC'), findsOneWidget);
    });

    testWidgets('smal scherm: geen intrinsic-dimensions exception', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpCommissiesTab(tester, viewportSize: const Size(360, 700));

      expect(tester.takeException(), isNull);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Bestuur'), findsOneWidget);
      expect(find.text('TC'), findsOneWidget);
    });

    testWidgets('Admin-tab toont zichtbare inhoud en klikbare knop', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpCommissiesTab(tester, viewportSize: const Size(390, 844));

      await tester.tap(find.text('Admin'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(find.text('Gebruikersnamen en accounts'), findsOneWidget);

      await tester.tap(find.text('Gebruikersnamen en accounts'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('wisselen tussen tabs toont verschillende inhoud', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpCommissiesTab(tester, viewportSize: const Size(390, 844));

      await tester.tap(find.text('Admin'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Gebruikersnamen en accounts'), findsOneWidget);
      expect(find.text('Teambeheer'), findsNothing);

      await tester.tap(find.text('TC'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.text('Gebruikersnamen en accounts'), findsNothing);
      expect(
        find.text('Teambeheer').evaluate().isNotEmpty ||
            find.text('TC tab kon niet laden').evaluate().isNotEmpty ||
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty,
        isTrue,
      );

      await tester.tap(find.text('Bestuur'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('Teambeheer'), findsNothing);
      expect(find.text('TC tab kon niet laden'), findsNothing);
      expect(find.text('Aanmeldingen'), findsOneWidget);
    });

    testWidgets('Android S/T-tab toont geen extra Taken-banner', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(360, 800)),
            child: AppUserContext(
              profileId: 'st-user',
              email: 'st@test.nl',
              displayName: 'S/T-lid',
              isGlobalAdmin: false,
              memberships: const [],
              committees: const ['scheidsrechters-tellers'],
              loggedInProfileId: 'st-user',
              reloadUserContext: () async {},
              child: const SizedBox(
                width: 360,
                height: 800,
                child: CommissiesTab(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(find.text('Commissies'), findsOneWidget);
      expect(find.text('S/T'), findsOneWidget);
      expect(find.text('Taken'), findsNothing);
    });
  });
}
