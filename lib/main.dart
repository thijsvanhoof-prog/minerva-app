import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/app_ui.dart';
import 'package:minerva_app/ui/auth/auth_gate.dart';
import 'package:minerva_app/ui/notifications/notification_service.dart';
import 'package:minerva_app/ui/branded_background.dart';
import 'package:minerva_app/ui/user_app_bootstrap.dart';

Future<void> main() async {
  return runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Statusbalk: donkerblauwe achtergrond + witte iconen (tijd, batterij, wifi).
    // Op iOS wordt statusBarColor genegeerd; Info.plist UIStatusBarStyleLightContent + donkerblauwe strook in shell doen de rest.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: AppColors.darkBlue,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

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
      // Firebase moet vóór elk Firebase-gebruik (incl. plugins) geïnitialiseerd zijn.
      try {
        await Firebase.initializeApp();
      } catch (e) {
        debugPrint('Firebase init failed (push uit): $e');
      }

      await dotenv.load(fileName: '.env');

      final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
      final configuredKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
      final supabaseKey = configuredKey;

      if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
        throw Exception(
          'SUPABASE_URL en SUPABASE_ANON_KEY moeten zijn ingesteld in .env.',
        );
      }

      // Safe debug: helps confirm which key is actually loaded from the bundled `.env` asset.
      final keyPreview = supabaseKey.length <= 24
          ? supabaseKey
          : '${supabaseKey.substring(0, 20)}…${supabaseKey.substring(supabaseKey.length - 4)}';
      debugPrint('Supabase URL: $supabaseUrl');
      debugPrint('Supabase key preview: $keyPreview');

      // Guardrails: a common misconfig is pasting a secret key (sb_secret_...) instead of the
      // project's anon/public (JWT-like) key. That will cause "Invalid API key" errors at runtime.
      if (supabaseKey.startsWith('sb_secret_')) {
        throw Exception(
          'SUPABASE_ANON_KEY lijkt op een secret key (sb_secret_...). '
          'Gebruik de "anon/public" key (legacy JWT) óf de "Publishable key" (sb_publishable_...) '
          'uit Supabase Dashboard → Project Settings → API Keys. '
          'Plak nooit een service/secret key in de app.',
        );
      }

      // Supabase now shows "Publishable key" (sb_publishable_...) for client usage.
      // Older projects may still use a JWT-like anon key; accept both formats.
      final looksLikePublishable = supabaseKey.startsWith('sb_publishable_');
      if (looksLikePublishable && supabaseKey.contains('...')) {
        throw Exception(
          'SUPABASE_ANON_KEY lijkt afgekapt (bevat "..."). '
          'Gebruik in Supabase Dashboard → Settings → API Keys de copy-knop bij "Publishable key" '
          'en plak de volledige waarde in `.env`.',
        );
      }
      final jwtLike = RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$');
      if (!looksLikePublishable && !jwtLike.hasMatch(supabaseKey)) {
        throw Exception(
          'SUPABASE_ANON_KEY lijkt niet op een geldige Supabase client key. '
          'Gebruik de "Publishable key" (sb_publishable_...) uit Supabase Dashboard → Settings → API Keys.',
        );
      }

      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseKey,
      );

      // Firebase (FCM) – vereist GoogleService-Info.plist (iOS) en google-services.json (Android).
      try {
        await NotificationService.initialize();
      } catch (e) {
        debugPrint('Notification init failed (push uit): $e');
      }

      runApp(const MinervaApp());
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

      // Force Dutch locale (calendars Monday-first, Dutch month/day names).
      locale: const Locale('nl', 'NL'),
      supportedLocales: const [
        Locale('nl', 'NL'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // 🔶 Centrale styling (cards, kleuren, iconen, tekst)
      theme: AppUI.theme(),

      // ✅ Zorg dat AppUserContext beschikbaar is voor ALLE routes/dialogs.
      builder: (context, child) {
        return BrandedBackground(
          child: UserAppBootstrap(child: child ?? const SizedBox.shrink()),
        );
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
      locale: const Locale('nl', 'NL'),
      supportedLocales: const [
        Locale('nl', 'NL'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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