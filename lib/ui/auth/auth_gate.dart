import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:minerva_app/ui/auth/auth_email_change_pending.dart';
import 'package:minerva_app/ui/auth/reset_password_page.dart';
import 'package:minerva_app/ui/components/top_message.dart';
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
      if (state.session != null &&
          (state.event == AuthChangeEvent.signedIn ||
              state.event == AuthChangeEvent.userUpdated)) {
        unawaited(_maybeHandleEmailChangeConfirmed());
      }
      // Zonder persoonlijke sessie blijft de app als publieke gast werken.
      if (state.session == null) {
        _ensureGuestSession();
      }
    });
    _ensureGuestSession();
  }

  Future<void> _maybeHandleEmailChangeConfirmed() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final confirmed = await consumePendingEmailChangeIfConfirmed(
      userId: user.id,
      currentEmail: user.email,
    );
    if (!confirmed) return;

    try {
      await _auth.refreshSession();
    } catch (_) {}

    final freshUser = _auth.currentUser ?? user;
    try {
      await Supabase.instance.client.from('profiles').upsert({
        'id': freshUser.id,
        'email': freshUser.email ?? '',
      });
    } catch (_) {}

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        showTopMessageWithMessenger(messenger, 'E-mailadres is bevestigd.');
      }
    });
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

    if (currentSession == null) {
      return;
    }

    // Persoonlijke en anonieme sessies blijven behouden. Een oude gedeelde
    // gastlogin wordt eenmalig lokaal verwijderd; publieke content gebruikt
    // daarna rechtstreeks de anon-rol van Supabase.
    if (guestEmail.isEmpty || currentEmail != guestEmail) {
      return;
    }

    _isEnsuringGuestSession = true;
    try {
      await _auth.signOut(scope: SignOutScope.local);
    } catch (error) {
      debugPrint('Oude gast-sessie kon niet lokaal worden verwijderd: $error');
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
