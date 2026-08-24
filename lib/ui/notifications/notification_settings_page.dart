import 'package:flutter/material.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:minerva_app/ui/app_colors.dart';
import 'notification_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _loading = true;
  bool _permissionGranted = false;
  /// Eén schakelaar: aan = ontvang alle meldingen, uit = geen meldingen.
  bool _meldingenAan = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!NotificationService.pushSupported) {
      setState(() => _loading = false);
      return;
    }

    try {
      final granted = await NotificationService.getNotificationPermission();
      final meldingenAan = await NotificationService.getNotifyEnabled();

      if (!mounted) return;
      setState(() {
        _permissionGranted = granted;
        _meldingenAan = meldingenAan;
        _loading = false;
      });

      if (!granted) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        final nowGranted =
            await NotificationService.requestNotificationPermission(true);
        if (mounted) setState(() => _permissionGranted = nowGranted);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _requestPermission() async {
    if (!NotificationService.pushSupported) return;
    final granted = await NotificationService.requestNotificationPermission(true);
    setState(() => _permissionGranted = granted);
  }

  Future<void> _save() async {
    if (!NotificationService.pushSupported) return;

    try {
      await NotificationService.setNotifyEnabled(_meldingenAan);
      await NotificationService.registerToken();

      if (!mounted) return;
      showTopMessage(
        context,
        _meldingenAan ? 'Meldingen aan. Je ontvangt berichten van Minerva.' : 'Meldingen uit. Je ontvangt geen pushberichten.',
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Opslaan mislukt: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16 + MediaQuery.paddingOf(context).top,
                  16,
                  16 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
                if (!NotificationService.pushSupported)
                  const GlassCard(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Push is hier niet beschikbaar. Controleer of Firebase is geconfigureerd '
                        '(GoogleService-Info.plist op iOS, google-services.json op Android) en of je op een echt apparaat draait.',
                        style: TextStyle(color: AppColors.onBackground),
                      ),
                    ),
                  )
                else ...[
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Push notificaties',
                          style: TextStyle(
                            color: AppColors.onBackground,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _permissionGranted
                              ? 'Toestemming is ingeschakeld. Je kunt hieronder kiezen of je meldingen ontvangt.'
                              : 'Geen toestemming. Tik op "Toestemming vragen" om meldingen van Minerva te kunnen ontvangen.',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        if (!_permissionGranted) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton(
                              onPressed: _requestPermission,
                              child: const Text('Toestemming vragen'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassCard(
                    padding: EdgeInsets.zero,
                    child: SwitchListTile.adaptive(
                      title: const Text(
                        'Ontvang meldingen',
                        style: TextStyle(color: AppColors.onBackground),
                      ),
                      subtitle: Text(
                        _meldingenAan
                            ? 'Je ontvangt nieuws, agenda en andere berichten van Minerva.'
                            : 'Je ontvangt geen pushmeldingen.',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      value: _meldingenAan,
                      onChanged: (v) => setState(() => _meldingenAan = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _save,
                    child: const Text('Opslaan'),
                  ),
                ],
              ],
            ),
    );
  }
}

