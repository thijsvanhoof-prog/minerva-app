import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minerva_app/ui/components/app_logo_title.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/primary_button.dart';
import 'package:minerva_app/ui/auth/register_page.dart';
import 'package:minerva_app/ui/branded_background.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final SupabaseClient _client = Supabase.instance.client;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);

    try {
      await _client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingelogd')),
      );
    } on AuthException catch (e) {
      if (!mounted) return;

      final msg = e.message.toLowerCase().contains('invalid login credentials')
          ? 'Email en wachtwoord komen niet overeen'
          : e.message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Onbekende fout: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.55),
          width: AppColors.cardBorderWidth,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        borderSide: const BorderSide(
          color: AppColors.primary,
          width: AppColors.cardBorderWidth,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const AppLogoTitle(),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          forceMaterialTransparency: true,
        ),
        body: BrandedBackground(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              topPadding,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
            GlassCard(
            child: Column(
              children: [
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppColors.onBackground),
                  decoration: _dec('E-mail'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  style: const TextStyle(color: AppColors.onBackground),
                  decoration: _dec('Wachtwoord'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        onPressed: _loading ? null : _signIn,
                        loading: _loading,
                        child: const Text('Inloggen'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.onBackground,
                          side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.55),
                            width: AppColors.cardBorderWidth,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _loading
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const RegisterPage(),
                                  ),
                                );
                              },
                        child: const Text('Registreren'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }
}