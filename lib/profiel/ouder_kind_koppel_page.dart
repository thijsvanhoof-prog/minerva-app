import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';

/// Pagina om twee bestaande accounts te koppelen (ouder/verzorger ↔ gekoppeld account).
///
/// In de gewenste flow bestaat er maar één type registratie; pas bij koppelen kies je
/// welke van de twee accounts het ouder/verzorger-account is.
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
  bool _iAmParent = true;
  bool _parentRpcSupported = true;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _error = 'Vul het e-mailadres van het andere account in.';
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
      if (_iAmParent) {
        // Existing RPC: current account requests to link the other account as child/linked account.
        await _client.rpc(
          'request_child_link',
          params: {'child_email': email},
        );
      } else {
        if (!_parentRpcSupported) {
          throw Exception('Deze optie wordt nog niet ondersteund in jouw Supabase setup.');
        }
        // Preferred new RPC (if present): request that the OTHER account becomes the parent.
        // We try it best-effort so existing projects don't break.
        await _client.rpc(
          'request_parent_link',
          params: {'parent_email': email},
        );
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = 'Koppelingsverzoek is verstuurd. De koppeling verschijnt na verwerking in je lijst.';
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        final msg = e.toString();
        final missingRpc =
            msg.contains('request_parent_link') || msg.toLowerCase().contains('function') && msg.toLowerCase().contains('request_parent_link');
        if (!_iAmParent && missingRpc) {
          _parentRpcSupported = false;
        }
        _error = _iAmParent
            ? 'Koppelen mislukt. Probeer het later opnieuw.'
            : (_parentRpcSupported
                ? 'Koppelen mislukt. Probeer het later opnieuw.'
                : 'Deze optie (“De ander is ouder/verzorger”) wordt nog niet ondersteund in jouw Supabase setup.\n\n'
                  'Workaround: log in met het account dat ouder/verzorger moet zijn en kies “Ik ben ouder/verzorger”.');
        _success = null;
      });
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
        body: ListView(
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Account koppelen',
                  style: TextStyle(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Vul het e-mailadres in van het account dat je wilt koppelen. '
                  'Daarna kies je wie de ouder/verzorger is. Na verwerking verschijnt de koppeling in je profiel.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Ik ben ouder/verzorger', maxLines: 1),
                        ),
                      ),
                      ButtonSegment(
                        value: false,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('De ander is ouder/verzorger', maxLines: 1),
                        ),
                      ),
                    ],
                    selected: {_iAmParent},
                    onSelectionChanged: (set) {
                      final next = set.first;
                      setState(() => _iAmParent = next);
                    },
                  ),
                ),
                if (!_parentRpcSupported) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Tip: jouw Supabase heeft geen RPC `request_parent_link`. '
                    'Koppel daarom vanaf het ouder/verzorger-account met “Ik ben ouder/verzorger”.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'E-mailadres van het andere account',
                    hintText: 'lid@voorbeeld.nl',
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
                    onPressed: _loading
                        ? null
                        : (!_iAmParent && !_parentRpcSupported)
                            ? null
                            : _submit,
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
    );
  }
}
