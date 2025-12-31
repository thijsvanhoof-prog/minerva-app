import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_page.dart';
import '../shell.dart';
import '../user_app_bootstrap.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      return const AuthPage();
    }

    // Belangrijk: UserAppBootstrap verwacht een child
    return const UserAppBootstrap(
      child: Shell(),
    );
  }
}