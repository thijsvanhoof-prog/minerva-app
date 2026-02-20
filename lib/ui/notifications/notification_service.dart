import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pushnotificaties via Firebase Cloud Messaging (FCM).
/// Tokens en voorkeuren staan in Supabase (push_tokens, notification_preferences).
class NotificationService {
  NotificationService._();

  static bool _firebaseInitialized = false;
  static final Map<String, DateTime> _cooldowns = {};

  static bool get pushSupported {
    if (kIsWeb) return false;
    if (!Platform.isIOS && !Platform.isAndroid) return false;
    return _firebaseInitialized;
  }

  /// Initialiseer Firebase en vraag toestemming. Roept geen Supabase aan (geen user nodig).
  /// Firebase.initializeApp() wordt in main.dart aangeroepen; hier alleen permission vragen.
  static Future<void> initialize() async {
    if (kIsWeb) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;
    if (_firebaseInitialized) return;
    if (Firebase.apps.isEmpty) return; // al in main() gefaald of nog niet gedaan
    _firebaseInitialized = true;
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {}
  }

  /// Roept aan bij uitloggen: verwijdert tokens van de huidige user uit Supabase.
  static Future<void> logout() async {
    if (!pushSupported) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('push_tokens')
          .delete()
          .eq('user_id', userId);
    } catch (_) {}
  }

  /// Of de gebruiker toestemming heeft gegeven (na requestPermission).
  static Future<bool> getNotificationPermission() async {
    if (!pushSupported || !_firebaseInitialized) return false;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Vraag om toestemmingsdialoog. fallbackToSettings: of we naar app-instellingen kunnen deep linken.
  static Future<bool> requestNotificationPermission(bool fallbackToSettings) async {
    if (!pushSupported || !_firebaseInitialized) return false;
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Haal voorkeur "meldingen aan" op uit Supabase (notification_preferences).
  static Future<bool> getNotifyEnabled() async {
    if (!pushSupported) return true;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return true;
    try {
      final row = await Supabase.instance.client
          .from('notification_preferences')
          .select('notify_enabled')
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return true;
      return (row['notify_enabled'] as bool?) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Sla voorkeur "meldingen aan/uit" op in Supabase.
  static Future<void> setNotifyEnabled(bool enabled) async {
    if (!pushSupported) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client.from('notification_preferences').upsert(
            {
              'user_id': userId,
              'notify_enabled': enabled,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'user_id',
          );
    } catch (_) {
      rethrow;
    }
  }

  /// Registreer het FCM-token voor de ingelogde user in Supabase. Aanroepen na inloggen of op de notificatiepagina.
  static Future<void> registerToken() async {
    if (!pushSupported || !_firebaseInitialized) {
      throw Exception('Push niet beschikbaar op dit platform of Firebase niet geïnitialiseerd.');
    }
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Geen ingelogde gebruiker gevonden voor token-registratie.');
    }

    final messaging = FirebaseMessaging.instance;

    // Op iOS kan APNs-token vertraagd beschikbaar komen; log dit, maar faal niet direct.
    if (Platform.isIOS) {
      String? apnsToken;
      for (var i = 0; i < 8; i++) {
        apnsToken = await messaging.getAPNSToken();
        if (apnsToken != null && apnsToken.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (apnsToken == null || apnsToken.isEmpty) {
        debugPrint(
          'NotificationService: APNs-token nog niet beschikbaar, probeer toch FCM-token op te halen.',
        );
      } else {
        debugPrint('NotificationService: APNs-token ontvangen.');
      }
    }

    String? token;
    Object? tokenError;
    for (var i = 0; i < 10; i++) {
      try {
        token = await messaging.getToken();
      } catch (e) {
        tokenError = e;
      }
      if (token != null && token.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    if (token == null || token.isEmpty) {
      throw Exception(
        'FCM-token ophalen mislukt${tokenError != null ? ': $tokenError' : ''}. '
        'Controleer Push Notifications capability + juiste provisioning profile voor deze bundle id.',
      );
    }
    debugPrint('NotificationService: FCM-token ontvangen.');

    final platform = Platform.isIOS ? 'ios' : 'android';
    await Supabase.instance.client.from('push_tokens').upsert(
          {
            'user_id': userId,
            'token': token,
            'platform': platform,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'user_id,token',
        );
    debugPrint(
      'NotificationService: token opgeslagen in push_tokens ($platform).',
    );
  }

  /// Na inloggen: token registreren en standaardvoorkeur zetten als die nog niet bestaat.
  static Future<void> syncUser({required String profileId}) async {
    if (!pushSupported || !_firebaseInitialized) return;
    try {
      await registerToken();
      // Zorg dat er een rij in notification_preferences is (default aan)
      final existing = await Supabase.instance.client
          .from('notification_preferences')
          .select('user_id')
          .eq('user_id', profileId)
          .maybeSingle();
      if (existing == null) {
        await Supabase.instance.client.from('notification_preferences').insert({
          'user_id': profileId,
          'notify_enabled': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (_) {}
  }

  /// Verstuur een clubbrede push via de Supabase Edge Function `send-push-fcm`.
  /// Best-effort: fouten mogen de primaire gebruikersactie niet blokkeren.
  static Future<void> sendBroadcastUpdate({
    required String title,
    required String body,
    String? dedupeKey,
    int? cooldownSeconds,
  }) async {
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty || b.isEmpty) return;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final accessToken = session?.accessToken;
      final anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';
      final headers = <String, String>{
        if (accessToken != null && accessToken.isNotEmpty)
          'Authorization': 'Bearer $accessToken',
        if (anonKey.isNotEmpty) 'apikey': anonKey,
      };
      await Supabase.instance.client.functions.invoke(
        'send-push-fcm',
        headers: headers.isEmpty ? null : headers,
        body: {
          'title': t,
          'body': b,
          'broadcast': true,
          if (dedupeKey != null && dedupeKey.trim().isNotEmpty)
            'dedupe_key': dedupeKey.trim(),
          if (cooldownSeconds != null && cooldownSeconds > 0)
            'cooldown_seconds': cooldownSeconds,
        },
      );
    } catch (e) {
      debugPrint('NotificationService: versturen club-push mislukt: $e');
    }
  }

  /// Verstuur een push met cooldown per sleutel om spam te voorkomen.
  static Future<void> sendBroadcastUpdateWithCooldown({
    required String title,
    required String body,
    required String cooldownKey,
    Duration cooldown = const Duration(hours: 6),
  }) async {
    final key = cooldownKey.trim();
    if (key.isEmpty) return;
    final now = DateTime.now();
    final last = _cooldowns[key];
    if (last != null && now.difference(last) < cooldown) return;
    _cooldowns[key] = now;
    await sendBroadcastUpdate(
      title: title,
      body: body,
      dedupeKey: key,
      cooldownSeconds: cooldown.inSeconds,
    );
  }
}
