import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_ui.dart';
import 'package:minerva_app/ui/auth/auth_gate.dart';
import 'package:minerva_app/ui/notifications/notification_service.dart';
import 'package:minerva_app/ui/user_app_bootstrap.dart';

Future<void> main() async {
  return runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
      if (details.stack != null) {
        debugPrint(details.stack.toString());
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('PlatformDispatcher error: $error');
      debugPrint('$stack');
      return true;
    };

    try {
      await dotenv.load(fileName: '.env');

      final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
      final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

      if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
        throw Exception(
          'SUPABASE_URL en SUPABASE_ANON_KEY moeten zijn ingesteld in .env',
        );
      }

      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseKey,
      );

      runApp(const MinervaApp());

      // OneSignal init after first frame (safer on cold-start iOS).
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final oneSignalAppId = dotenv.env['ONESIGNAL_APP_ID'] ?? '';
        await NotificationService.initialize(oneSignalAppId: oneSignalAppId);
      });
    } catch (e, stackTrace) {
      debugPrint('Startup error: $e');
      debugPrint('$stackTrace');
      runApp(_StartupErrorApp(error: e, stackTrace: stackTrace));
    }
  }, (error, stack) {
    debugPrint('Zone error: $error');
    debugPrint('$stack');
  });
}

class MinervaApp extends StatelessWidget {
  const MinervaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VV Minerva',
      debugShowCheckedModeBanner: false,

      // 🔶 Centrale styling (cards, kleuren, iconen, tekst)
      theme: AppUI.theme(),

      // ✅ Zorg dat AppUserContext beschikbaar is voor ALLE routes/dialogs.
      builder: (context, child) {
        return UserAppBootstrap(child: child ?? const SizedBox.shrink());
      },

      // 🔐 Auth bepaalt automatisch of je login of app ziet
      home: const AuthGate(),
    );
  }
}

class _StartupErrorApp extends StatelessWidget {
  final Object error;
  final StackTrace stackTrace;

  const _StartupErrorApp({
    required this.error,
    required this.stackTrace,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppUI.theme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Fout bij opstarten app',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}