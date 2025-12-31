import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ui/app_ui.dart';
import 'ui/auth/auth_gate.dart';

// #region agent log
Future<void> _debugLog(String location, String message, Map<String, dynamic> data) async {
  try {
    final logEntry = jsonEncode({
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'sessionId': 'debug-session',
      'runId': 'run1',
    });
    // Also print for immediate visibility
    print('DEBUG: $message - $data');
    final file = File('/Users/bonk/Development/minerva_app/.cursor/debug.log');
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await file.writeAsString('$logEntry\n', mode: FileMode.append);
  } catch (e) {
    // Fallback to print if file logging fails
    print('DEBUG_LOG_ERROR: $e');
    print('DEBUG: $message - $data');
  }
}
// #endregion

Future<void> main() async {
  // Immediate print for debugging
  print('=== MINERVA APP STARTING ===');
  
  // #region agent log
  await _debugLog('main.dart:37', 'App starting', {'step': 'main() entry'});
  // #endregion
  
  try {
    print('DEBUG: Before WidgetsFlutterBinding');
    // #region agent log
    await _debugLog('main.dart:43', 'Before WidgetsFlutterBinding', {});
    // #endregion
    
    WidgetsFlutterBinding.ensureInitialized();
    print('DEBUG: WidgetsFlutterBinding initialized');

    print('DEBUG: Loading .env file');
    // #region agent log
    await _debugLog('main.dart:50', 'Loading .env file', {});
    // #endregion

    // Load environment variables
    // flutter_dotenv: load .env file from root (declared in pubspec.yaml)
    String? envLoadError;
    bool envLoaded = false;
    try {
      await dotenv.load(fileName: '.env');
      envLoaded = true;
      print('DEBUG: .env file loaded successfully');
      // #region agent log
      await _debugLog('main.dart:57', '.env file loaded successfully', {});
      // #endregion
    } catch (e, stackTrace) {
      envLoadError = '${e.toString()}\nStack: ${stackTrace.toString()}';
      envLoaded = false;
      print('DEBUG ERROR: .env load failed: $e');
      print('DEBUG ERROR: Stack: $stackTrace');
      // #region agent log
      await _debugLog('main.dart:65', '.env file load failed', {
        'error': e.toString(),
        'errorType': e.runtimeType.toString(),
      });
      // #endregion
    }

    // #region agent log
    // Only access dotenv.env if it was successfully loaded
    final supabaseUrl = envLoaded ? (dotenv.env['SUPABASE_URL'] ?? '') : '';
    final supabaseKey = envLoaded ? (dotenv.env['SUPABASE_ANON_KEY'] ?? '') : '';
    print('DEBUG: After loading .env - URL: ${supabaseUrl.isNotEmpty ? "LOADED" : "EMPTY"}, KEY: ${supabaseKey.isNotEmpty ? "LOADED" : "EMPTY"}');
    await _debugLog('main.dart:72', 'After loading .env', {
      'url': supabaseUrl.isNotEmpty ? '${supabaseUrl.substring(0, 20)}...' : 'EMPTY',
      'key': supabaseKey.isNotEmpty ? '${supabaseKey.substring(0, 20)}...' : 'EMPTY',
      'urlLoaded': supabaseUrl.isNotEmpty,
      'keyLoaded': supabaseKey.isNotEmpty,
      'envLoadError': envLoadError,
    });
    // #endregion

    if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
      // #region agent log
      await _debugLog('main.dart:72', 'Missing Supabase credentials', {
        'urlEmpty': supabaseUrl.isEmpty,
        'keyEmpty': supabaseKey.isEmpty,
        'envLoadError': envLoadError,
      });
      // #endregion
      final errorMsg = envLoadError != null
          ? 'Kon .env bestand niet laden: $envLoadError\n\nMaak .env aan in de root van het project met:\nSUPABASE_URL=...\nSUPABASE_ANON_KEY=...'
          : 'SUPABASE_URL en SUPABASE_ANON_KEY moeten zijn ingesteld in .env bestand';
      throw Exception(errorMsg);
    }

    // #region agent log
    await _debugLog('main.dart:65', 'Before Supabase.initialize', {
      'urlLength': supabaseUrl.length,
      'keyLength': supabaseKey.length,
    });
    // #endregion

      try {
        await Supabase.initialize(
          url: supabaseUrl,
          anonKey: supabaseKey,
        );
        
        // #region agent log
        await _debugLog('main.dart:87', 'Supabase.initialize succeeded', {
          'status': 'initialized',
        });
        // #endregion
      } catch (e, stackTrace) {
        // #region agent log
        await _debugLog('main.dart:92', 'Supabase.initialize failed', {
          'error': e.toString(),
          'stackTrace': stackTrace.toString(),
        });
        // #endregion
        rethrow;
      }

    // #region agent log
    await _debugLog('main.dart:68', 'Calling runApp', {});
    // #endregion

    print('DEBUG: About to call runApp');
    runApp(const MinervaApp());
    print('DEBUG: runApp called successfully');
  } catch (e, stackTrace) {
    print('=== FATAL ERROR IN MAIN() ===');
    print('Error: $e');
    print('Stack: $stackTrace');
    // #region agent log
    await _debugLog('main.dart:133', 'Fatal error in main()', {
      'error': e.toString(),
      'stackTrace': stackTrace.toString(),
    });
    // #endregion
    // Don't rethrow - show error in UI instead
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Fout bij opstarten app:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Text('$e', style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                Text('$stackTrace', style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ),
      ),
    ));
  }
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

      // 🔐 Auth bepaalt automatisch of je login of app ziet
      home: const AuthGate(),
    );
  }
}