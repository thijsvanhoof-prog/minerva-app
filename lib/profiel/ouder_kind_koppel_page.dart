import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minerva_app/ui/branded_background.dart';
import 'package:minerva_app/ui/components/app_logo_title.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';

/// Pagina waar een ouder een kind kan koppelen aan het eigen account.
/// Roept RPC `request_child_link` aan met het e-mailadres van het kind.
class OuderKindKoppelPage extends StatefulWidget {
  const OuderKindKoppelPage({super.key});

  @override
  State<OuderKindKoppelPage> createState() => _OuderKindKoppelPageState();
}

class _OuderKindKoppelPageState extends State<OuderKindKoppelPage> {
  final _client = Supabase.instance.client;
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _error = 'Vul het e-mailadres van het kind in.';
        _success = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });

    try {
      await _client.rpc(
        'request_child_link',
        params: {'child_email': email},
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = 'Koppelingsverzoek is verstuurd. Het kind verschijnt na verwerking in je lijst.';
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Koppelen mislukt. Neem contact op met de vereniging om een kind te koppelen.';
        _success = null;
      });
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kind koppelen',
                  style: TextStyle(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Vul het e-mailadres in waarmee je kind in de app is ingeschreven. '
                  'Na je verzoek wordt de koppeling verwerkt; het kind verschijnt dan bij "Ouder-kind account" op je profiel.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'E-mailadres van het kind',
                    hintText: 'kind@voorbeeld.nl',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ],
                if (_success != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _success!,
                    style: TextStyle(color: Colors.green.shade700),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                          )
                        : const Text('Koppelingsverzoek sturen'),
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
