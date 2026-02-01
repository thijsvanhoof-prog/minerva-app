import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minerva_app/ui/branded_background.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/primary_button.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';

/// Scherm om een nieuw account te registreren (e-mail + wachtwoord).
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _client = Supabase.instance.client;
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();

  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _passConfirmCtrl.dispose();
    super.dispose();
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

  Future<void> _register() async {
    final username = _usernameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final passConfirm = _passConfirmCtrl.text;

    if (email.isEmpty) {
      showTopMessage(context, 'Vul een e-mailadres in.', isError: true);
      return;
    }
    if (username.isEmpty) {
      showTopMessage(context, 'Vul een gebruikersnaam in.', isError: true);
      return;
    }
    if (pass.isEmpty) {
      showTopMessage(context, 'Vul een wachtwoord in.', isError: true);
      return;
    }
    if (pass != passConfirm) {
      showTopMessage(context, 'De wachtwoorden komen niet overeen.', isError: true);
      return;
    }

    setState(() => _loading = true);

    try {
      await _client.auth.signUp(
        email: email,
        password: pass,
        data: {'display_name': username},
      );

      // Best-effort: if we have a session immediately, also upsert into profiles so the
      // username is visible right away (some projects rely on profiles rather than metadata).
      try {
        final userId = _client.auth.currentUser?.id;
        if (userId != null) {
          await _client.from('profiles').upsert({
            'id': userId,
            'display_name': username,
            'email': email,
          });
        }
      } catch (_) {
        // ignore (RLS or schema differences)
      }

      if (!mounted) return;
      showTopMessage(context, 'Account aangemaakt.');
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (!mounted) return;
      showTopMessage(context, e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Onbekende fout: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top + 16;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: _loading ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Registreren',
                      style: TextStyle(
                        color: AppColors.onBackground,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Maak een account aan met je e-mailadres.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: const TextStyle(color: AppColors.onBackground),
                      decoration: _dec('E-mail'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _usernameCtrl,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(color: AppColors.onBackground),
                      decoration: _dec('Gebruikersnaam'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscurePass,
                      style: const TextStyle(color: AppColors.onBackground),
                      decoration: _dec('Wachtwoord').copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePass ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.iconMuted,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePass = !_obscurePass),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passConfirmCtrl,
                      obscureText: _obscureConfirm,
                      style: const TextStyle(color: AppColors.onBackground),
                      decoration: _dec('Wachtwoord bevestigen').copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.iconMuted,
                          ),
                          onPressed: () =>
                              setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: PrimaryButton(
                        onPressed: _loading ? null : _register,
                        loading: _loading,
                        child: const Text('Account aanmaken'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: _loading
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Terug naar inloggen'),
                      ),
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
