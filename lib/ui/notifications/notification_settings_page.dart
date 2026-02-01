import 'package:flutter/material.dart';
import 'package:minerva_app/ui/components/glass_card.dart';
import 'package:minerva_app/ui/branded_background.dart';
import 'package:minerva_app/ui/components/top_message.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

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

  bool _agenda = true;
  bool _news = true;
  bool _highlights = true;
  bool _standings = true;
  bool _trainings = true;

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
      final granted = OneSignal.Notifications.permission;
      Map<String, String> tags = {};
      try {
        tags = await OneSignal.User.getTags();
      } catch (_) {}

      setState(() {
        _permissionGranted = granted;
        _agenda = tags['notify_agenda'] != 'false';
        _news = tags['notify_news'] != 'false';
        _highlights = tags['notify_highlights'] != 'false';
        _standings = tags['notify_standings'] != 'false';
        _trainings = tags['notify_trainings'] != 'false';
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _requestPermission() async {
    if (!NotificationService.pushSupported) return;
    final granted = await OneSignal.Notifications.requestPermission(true);
    setState(() => _permissionGranted = granted);
  }

  Future<void> _applyTags() async {
    if (!NotificationService.pushSupported) return;

    final tags = <String, String>{
      'notify_agenda': _agenda ? 'true' : 'false',
      'notify_news': _news ? 'true' : 'false',
      'notify_highlights': _highlights ? 'true' : 'false',
      'notify_standings': _standings ? 'true' : 'false',
      'notify_trainings': _trainings ? 'true' : 'false',
    };

    try {
      await OneSignal.User.addTags(tags);
      if (!mounted) return;
      showTopMessage(context, 'Notificatievoorkeuren opgeslagen');
    } catch (e) {
      if (!mounted) return;
      showTopMessage(context, 'Opslaan mislukt: $e', isError: true);
    }
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile.adaptive(
      title: Text(
        label,
        style: const TextStyle(color: AppColors.onBackground),
      ),
      subtitle: const Text(
        'Aan/uit',
        style: TextStyle(color: AppColors.textSecondary),
      ),
      value: value,
      onChanged: (v) => setState(() => onChanged(v)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandedBackground(
        child: _loading
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
                    child: Text(
                      'Push notificaties worden op dit platform niet ondersteund.',
                      style: TextStyle(color: AppColors.onBackground),
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
                              ? 'Toestemming is ingeschakeld.'
                              : 'Toestemming is uitgeschakeld.',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            onPressed: _requestPermission,
                            child: const Text('Toestemming vragen'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _toggle('Agenda', _agenda, (v) => _agenda = v),
                        _toggle('Nieuws', _news, (v) => _news = v),
                        _toggle('Uitgelicht', _highlights, (v) => _highlights = v),
                        _toggle('Stand', _standings, (v) => _standings = v),
                        _toggle('Trainingen', _trainings, (v) => _trainings = v),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _applyTags,
                    child: const Text('Opslaan'),
                  ),
                ],
              ],
            ),
      ),
    );
  }
}

