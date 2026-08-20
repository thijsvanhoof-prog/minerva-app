import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:minerva_app/ui/auth/reset_password_page.dart';
import 'package:minerva_app/ui/shell.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = Supabase.instance.client.auth;
  bool _isEnsuringGuestSession = false;
  bool _showingResetPasswordPage = false;
  bool _passwordRecoveryPending = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = _auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        _passwordRecoveryPending = true;
        _openResetPasswordPage();
        return;
      }
      // Zodra iemand uitlogt of sessie vervalt, direct terug naar gast.
      if (state.session == null) {
        _ensureGuestSession();
      }
    });
    _ensureGuestSession();
  }

  void _openResetPasswordPage() {
    if (_showingResetPasswordPage || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_showingResetPasswordPage || !mounted) return;
      final navigator = Navigator.maybeOf(context);
      if (navigator == null) return;

      _showingResetPasswordPage = true;
      try {
        await navigator.push<bool>(
          MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
        );
      } finally {
        _passwordRecoveryPending = false;
        _showingResetPasswordPage = false;
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _ensureGuestSession() async {
    if (_isEnsuringGuestSession ||
        _passwordRecoveryPending ||
        _showingResetPasswordPage) {
      return;
    }
    final currentSession = _auth.currentSession;
    final currentEmail = (_auth.currentUser?.email ?? '').trim().toLowerCase();
    final guestEmail = (dotenv.env['GUEST_EMAIL'] ?? '').trim().toLowerCase();

    // Als er al een persoonlijke sessie is, die behouden (volledige toegang volgens account).
    if (currentSession != null &&
        (guestEmail.isEmpty || currentEmail != guestEmail)) {
      return;
    }

    _isEnsuringGuestSession = true;
    try {
      final guestPassword = (dotenv.env['GUEST_PASSWORD'] ?? '').trim();
      if (guestEmail.isNotEmpty && guestPassword.isNotEmpty) {
        // Staat al op gast? klaar.
        if (currentEmail == guestEmail && currentSession != null) return;
        try {
          await _auth.signInWithPassword(
            email: guestEmail,
            password: guestPassword,
          );
          return;
        } catch (_) {
          // Als gastlogin mislukt, probeer nog anonymous zodat app bruikbaar blijft.
        }
      }

      // Fallback: anonymous gastsessie.
      if (_auth.currentSession == null) {
        try {
          await _auth.signInAnonymously();
        } catch (_) {
          // Best-effort: zonder guest credentials/anonymous blijft de app in lokale gastmodus werken.
        }
      }
    } finally {
      _isEnsuringGuestSession = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // App start altijd in de shell (gastmodus mogelijk).
    // Inloggen gebeurt via het Profiel-tabblad.
    return const Shell();
  }
}