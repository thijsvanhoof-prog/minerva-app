import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minerva_app/ui/app_colors.dart';
import 'package:minerva_app/ui/auth/auth_validation.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/primary_button.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Scherm om een nieuw wachtwoord in te stellen na password recovery.
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _client = Supabase.instance.client;
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();

  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _passCtrl.dispose();
    _passConfirmCtrl.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      suffixIcon: suffixIcon,
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

  Future<void> _savePassword() async {
    final pass = _passCtrl.text;
    final passConfirm = _passConfirmCtrl.text;

    if (pass.isEmpty) {
      showTopMessage(context, 'Vul een wachtwoord in.', isError: true);
      return;
    }
    if (!isPasswordLongEnough(pass)) {
      showTopMessage(context, 'Wachtwoord moet minimaal 6 tekens zijn.', isError: true);
      return;
    }
    if (!passwordsMatch(pass, passConfirm)) {
      showTopMessage(context, 'De wachtwoorden komen niet overeen.', isError: true);
      return;
    }

    setState(() => _loading = true);
    try {
      await _client.auth.updateUser(UserAttributes(password: pass));
      if (!mounted) return;
      showTopMessage(context, 'Wachtwoord is aangepast.');
      Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (!mounted) return;
      showTopMessage(context, e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Kon wachtwoord niet opslaan. Probeer het later opnieuw.', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
          title: const Text('Nieuw wachtwoord'),
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
                  const Text(
                    'Kies een nieuw wachtwoord',
                    style: TextStyle(
                      color: AppColors.onBackground,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Vul je nieuwe wachtwoord in en bevestig het. Daarna kun je weer inloggen met dit wachtwoord.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscurePass,
                    autofillHints: const [AutofillHints.newPassword],
                    style: const TextStyle(color: AppColors.onBackground),
                    decoration: _dec(
                      'Nieuw wachtwoord',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePass ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passConfirmCtrl,
                    obscureText: _obscureConfirm,
                    autofillHints: const [AutofillHints.newPassword],
                    style: const TextStyle(color: AppColors.onBackground),
                    decoration: _dec(
                      'Herhaal nieuw wachtwoord',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      onPressed: _loading ? null : _savePassword,
                      loading: _loading,
                      child: const Text('Opslaan'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _loading ? null : () => Navigator.of(context).pop(),
                      child: const Text('Annuleren'),
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
