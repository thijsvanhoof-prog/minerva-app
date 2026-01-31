import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minerva_app/ui/branded_background.dart';
import 'package:minerva_app/ui/components/app_logo_title.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/primary_button.dart';
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
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();
  final _kindNaamCtrl = TextEditingController();
  final _kindEmailCtrl = TextEditingController();
  final _kindPassCtrl = TextEditingController();
  final _kindPassConfirmCtrl = TextEditingController();

  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _ouderAccount = false;
  bool _obscureKindPass = true;
  bool _obscureKindConfirm = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _passConfirmCtrl.dispose();
    _kindNaamCtrl.dispose();
    _kindEmailCtrl.dispose();
    _kindPassCtrl.dispose();
    _kindPassConfirmCtrl.dispose();
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
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final passConfirm = _passConfirmCtrl.text;
    final ouderAccount = _ouderAccount;
    final kindNaam = _kindNaamCtrl.text.trim();
    final kindEmail = _kindEmailCtrl.text.trim();
    final kindPass = _kindPassCtrl.text;
    final kindPassConfirm = _kindPassConfirmCtrl.text;

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vul een e-mailadres in.')),
      );
      return;
    }
    if (pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vul een wachtwoord in.')),
      );
      return;
    }
    if (pass != passConfirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('De wachtwoorden komen niet overeen.')),
      );
      return;
    }
    if (ouderAccount) {
      if (kindNaam.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vul de naam van het kind in.')),
        );
        return;
      }
      if (kindEmail.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vul het e-mailadres van het kind in.')),
        );
        return;
      }
      if (kindEmail == email) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Het kind moet een ander e-mailadres hebben dan de ouder.')),
        );
        return;
      }
      if (kindPass.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vul een wachtwoord in voor het kind.')),
        );
        return;
      }
      if (kindPass != kindPassConfirm) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('De wachtwoorden van het kind komen niet overeen.')),
        );
        return;
      }
    }

    setState(() => _loading = true);

    try {
      await _client.auth.signUp(email: email, password: pass);

      if (!mounted) return;

      if (ouderAccount) {
        try {
          await _client.auth.signInWithPassword(email: email, password: pass);
          if (!mounted) return;
          await _client.rpc(
            'create_linked_child_account',
            params: {
              'child_name': kindNaam,
              'child_email': kindEmail,
              'child_password': kindPass,
            },
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Account aangemaakt. Het kindaccount kon niet worden gekoppeld. '
                'Koppel je kind later via Profiel → Kind koppelen.',
              ),
            ),
          );
          Navigator.of(context).pop();
          return;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ouderAccount
                ? 'Account en kindaccount aangemaakt. Je kunt wisselen via Profiel.'
                : 'Account aangemaakt.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
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

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
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
                    CheckboxListTile(
                      value: _ouderAccount,
                      onChanged: (v) => setState(() => _ouderAccount = v ?? false),
                      title: const Text(
                        'Ouderaccount aanmaken',
                        style: TextStyle(
                          color: AppColors.onBackground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Maak direct een kindaccount aan en koppel dat aan dit account. Jouw gebruikersnaam wordt "naam kind (ouder)".',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      activeColor: AppColors.primary,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (_ouderAccount) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _kindNaamCtrl,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(color: AppColors.onBackground),
                        decoration: _dec('Naam van het kind'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _kindEmailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        style: const TextStyle(color: AppColors.onBackground),
                        decoration: _dec('E-mailadres van het kind'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _kindPassCtrl,
                        obscureText: _obscureKindPass,
                        style: const TextStyle(color: AppColors.onBackground),
                        decoration: _dec('Wachtwoord voor het kind').copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureKindPass ? Icons.visibility_off : Icons.visibility,
                              color: AppColors.iconMuted,
                            ),
                            onPressed: () =>
                                setState(() => _obscureKindPass = !_obscureKindPass),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _kindPassConfirmCtrl,
                        obscureText: _obscureKindConfirm,
                        style: const TextStyle(color: AppColors.onBackground),
                        decoration: _dec('Wachtwoord kind bevestigen').copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureKindConfirm ? Icons.visibility_off : Icons.visibility,
                              color: AppColors.iconMuted,
                            ),
                            onPressed: () =>
                                setState(() => _obscureKindConfirm = !_obscureKindConfirm),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
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
