import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pushnotificaties via Firebase Cloud Messaging (FCM).
/// Tokens en voorkeuren staan in Supabase (push_tokens, notification_preferences).
class NotificationService {
  NotificationService._();

  static bool _firebaseInitialized = false;

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
    if (!pushSupported || !_firebaseInitialized) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return;
    }
    if (token == null || token.isEmpty) return;
    final platform = Platform.isIOS ? 'ios' : 'android';
    try {
      await Supabase.instance.client.from('push_tokens').upsert(
            {
              'user_id': userId,
              'token': token,
              'platform': platform,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'user_id,token',
          );
    } catch (_) {}
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
}
