import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/primary_button.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/auth/auth_redirect_urls.dart';
import 'package:minerva_app/ui/auth/auth_validation.dart';

/// Scherm om een wachtwoord-resetlink per e-mail aan te vragen.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _client = Supabase.instance.client;
  final _emailCtrl = TextEditingController();

  bool _loading = false;
  bool _sent = false;

  String get _reservedGuestEmail {
    final configured = (dotenv.env['GUEST_EMAIL'] ?? '').trim().toLowerCase();
    if (configured.isNotEmpty) return configured;
    return 'gast@mail.com';
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEmail?.trim();
    if (initial != null && initial.isNotEmpty) {
      _emailCtrl.text = initial;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    final email = _emailCtrl.text.trim();
    if (!isValidEmail(email)) {
      showTopMessage(context, 'Vul een geldig e-mailadres in.', isError: true);
      return;
    }
    if (email.toLowerCase() == _reservedGuestEmail) {
      showTopMessage(
        context,
        'Het gastaccount heeft geen persoonlijk wachtwoord. Log in met je eigen account.',
        isError: true,
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final redirectTo = supabaseResetRedirectUrl();
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectTo,
      );
      if (!mounted) return;
      setState(() => _sent = true);
      showTopMessage(context, 'Resetlink verstuurd. Check je e-mail.');
    } on AuthException catch (e) {
      if (!mounted) return;
      showTopMessage(context, e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Kon resetlink niet versturen. Probeer het later opnieuw.', isError: true);
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
    final topPadding = MediaQuery.paddingOf(context).top + 16;
    final overlayStyle = Theme.of(context).platform == TargetPlatform.android
        ? const SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarIconBrightness: Brightness.dark,
          )
        : const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.onBackground,
          title: const Text('Wachtwoord vergeten'),
        ),
        body: ListView(
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _sent ? 'Check je e-mail' : 'Wachtwoord resetten',
                    style: const TextStyle(
                      color: AppColors.onBackground,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _sent
                        ? 'Als dit e-mailadres bij ons bekend is, ontvang je een e-mail met een link om een nieuw wachtwoord in te stellen. '
                            'Klik op de link in de mail en kies daarna een nieuw wachtwoord. '
                            'Daarna kun je weer inloggen in de app.'
                        : 'Vul het e-mailadres in van je account. We sturen je een link om een nieuw wachtwoord te kiezen.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  if (!_sent) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      style: const TextStyle(color: AppColors.onBackground),
                      decoration: _dec('E-mail'),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: PrimaryButton(
                        onPressed: _loading ? null : _sendResetLink,
                        loading: _loading,
                        child: const Text('Resetlink versturen'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _loading ? null : () => Navigator.of(context).pop(),
                      child: Text(_sent ? 'Terug naar inloggen' : 'Annuleren'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
