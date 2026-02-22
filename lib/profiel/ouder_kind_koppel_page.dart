import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:minerva_app/ui/app_colors.dart';

/// Pagina om twee bestaande accounts te koppelen (ouder/verzorger ↔ kind).
/// Koppelen gaat volledig in de app: de ene genereert een code, de andere voert die in.
class OuderKindKoppelPage extends StatefulWidget {
  const OuderKindKoppelPage({super.key});

  @override
  State<OuderKindKoppelPage> createState() => _OuderKindKoppelPageState();
}

class _OuderKindKoppelPageState extends State<OuderKindKoppelPage> {
  final _client = Supabase.instance.client;
  final _codeController = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _success;

  /// true = "Genereer code", false = "Voer code in"
  bool _modeGenerate = true;
  bool _iAmParent = true;

  /// Na succesvol genereren: getoonde code en verloopdatum
  String? _generatedCode;
  DateTime? _expiresAt;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _generateCode() async {
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
      _generatedCode = null;
    });

    try {
      final res = await _client.rpc(
        'create_link_code',
        params: {'p_is_parent': _iAmParent},
      );
      if (!mounted) return;
      final map = res is Map ? Map<String, dynamic>.from(res) : null;
      final code = map?['code']?.toString();
      final expiresStr = map?['expires_at']?.toString();
      if (code == null || code.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Geen code ontvangen. Probeer het opnieuw.';
        });
        return;
      }
      setState(() {
        _loading = false;
        _generatedCode = code.toUpperCase();
        _expiresAt = expiresStr != null ? DateTime.tryParse(expiresStr)?.toLocal() : null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _formatError(e);
        _generatedCode = null;
      });
    }
  }

  Future<void> _consumeCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() {
        _error = 'Voer de 6-cijferige code in.';
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
      await _client.rpc('consume_link_code', params: {'p_code': code});
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = 'De accounts zijn gekoppeld. Herstart de app op beide apparaten om de koppeling te activeren.';
        _codeController.clear();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _formatError(e);
        _success = null;
      });
    }
  }

  String _formatError(dynamic e) {
    final msg = e.toString();
    if (msg.contains('Code niet gevonden')) return 'Code niet gevonden. Controleer de code of vraag een nieuwe aan.';
    if (msg.contains('verlopen')) return 'Deze code is verlopen. Vraag een nieuwe code aan.';
    if (msg.contains('jezelf')) return 'Je kunt geen account met jezelf koppelen.';
    if (msg.contains('Ongeldige code')) return 'Voer een geldige code in.';
    return msg.replaceFirst(RegExp(r'^Exception:?\s*', caseSensitive: false), '').trim();
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
                    'Koppelen gaat in de app: de een genereert een code, de ander voert die in. Geen e-mail nodig.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Genereer code')),
                      ButtonSegment(value: false, label: Text('Voer code in')),
                    ],
                    selected: {_modeGenerate},
                    onSelectionChanged: (set) {
                      setState(() {
                        _modeGenerate = set.first;
                        _error = null;
                        _success = null;
                        _generatedCode = null;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  if (_modeGenerate) ...[
                    const Text(
                      'Wie ben jij in deze koppeling?',
                      style: TextStyle(
                        color: AppColors.onBackground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
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
                            child: Text('Ik ben het kind', maxLines: 1),
                          ),
                        ),
                      ],
                      selected: {_iAmParent},
                      onSelectionChanged: (set) => setState(() => _iAmParent = set.first),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.background,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _loading ? null : _generateCode,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.background,
                                ),
                              )
                            : const Text('Genereer code'),
                      ),
                    ),
                    if (_generatedCode != null) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Geef deze code aan de andere persoon (code is 15 min geldig):',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _generatedCode!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Code gekopieerd')),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            color: AppColors.darkBlue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _generatedCode!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 6,
                              color: AppColors.onBackground,
                            ),
                          ),
                        ),
                      ),
                      if (_expiresAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Geldig tot ${_expiresAt!.hour.toString().padLeft(2, '0')}:${_expiresAt!.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ],
                  ] else ...[
                    const Text(
                      'Voer de code in die je van de andere persoon hebt gekregen:',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 8,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        hintText: 'ABC123',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _consumeCode(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.error)),
                    ],
                    if (_success != null) ...[
                      const SizedBox(height: 12),
                      Text(_success!, style: TextStyle(color: Colors.green.shade700)),
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
                        onPressed: _loading ? null : _consumeCode,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.background,
                                ),
                              )
                            : const Text('Koppelen'),
                      ),
                    ),
                  ],
                  if (_error != null && _modeGenerate) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.error)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
