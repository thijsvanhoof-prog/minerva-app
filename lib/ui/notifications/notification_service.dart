import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'package:minerva_app/ui/app_user_context.dart';

class NotificationService {
  NotificationService._();

  static bool _oneSignalInitialized = false;

  static bool get pushSupported {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

  static void markOneSignalInitialized() {
    _oneSignalInitialized = true;
  }

  static Future<void> initialize({required String oneSignalAppId}) async {
    if (!pushSupported) return;
    if (_oneSignalInitialized) return;
    if (oneSignalAppId.trim().isEmpty) return;

    OneSignal.initialize(oneSignalAppId);
    _oneSignalInitialized = true;
  }

  /// Sync the logged-in user to OneSignal.
  ///
  /// Call this after OneSignal has been initialized.
  static Future<void> syncUser({
    required String profileId,
    required String email,
    required bool isGlobalAdmin,
    required List<TeamMembership> memberships,
    required List<String> committees,
  }) async {
    if (!pushSupported) return;
    if (!_oneSignalInitialized) return;
    if (profileId.isEmpty) return;

    // Identify the user
    OneSignal.login(profileId);
    if (email.isNotEmpty) {
      OneSignal.User.addEmail(email);
    }

    // Tag roles/teams for targeting.
    final tags = <String, String>{
      'role_global_admin': isGlobalAdmin ? 'true' : 'false',
    };

    for (final m in memberships) {
      tags['team_${m.teamId}'] = 'true';
      tags['team_role_${m.teamId}'] = m.role;
    }

    for (final c in committees) {
      final key = c.trim().toLowerCase().replaceAll(' ', '-');
      if (key.isEmpty) continue;
      tags['committee_$key'] = 'true';
    }

    await OneSignal.User.addTags(tags);
  }
}

