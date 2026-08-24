import 'package:flutter/material.dart';

/// Centrale kleur- en UI-richtlijn voor de hele app
class AppColors {
  /* ===================== BASIS ===================== */

  /// App-achtergrond (wit)
  static const Color background = Color(0xFFFFFFFF);
  
  /// Donkerblauw voor widgets (#1A2B4A)
  static const Color darkBlue = Color(0xFF1A2B4A);

  /// Nav bar – zelfde als darkBlue
  static const Color navBarBlue = Color(0xFF1A2B4A);

  /// Kaarten / widgets (licht wit met subtiele donkerblauwe tint)
  static const Color card = Color(0xFFFFFFFF);

  /// Primaire clubkleur (oranje #FF8A00)
  static const Color primary = Color(0xFFFF8A00);

  /* ===================== TEKST ===================== */

  /// Hoofdtekst op lichte achtergrond (donkerblauw)
  static const Color onBackground = Color(0xFF1A2B4A);

  /// Secundaire tekst (subtitles, hints)
  static const Color textSecondary = Color(0xFF5A6B7C);

  /* ===================== ICONEN ===================== */

  /// Inactieve / gedempte iconen
  static const Color iconMuted = Color(0xFF8A9BA8);

  /* ===================== STATUSKLEUREN ===================== */

  /// Succes / aanwezig
  static const Color success = Color(0xFF2ECC71);

  /// Waarschuwing / aandacht (zelfde oranje familie)
  static const Color warning = Color(0xFFFF8A00);

  /// Foutmeldingen
  static const Color error = Color(0xFFE53935);

  /* ===================== UI-RICHTLIJNEN ===================== */

  /// Standaard randdikte voor ALLE kaarten/widgets
  static const double cardBorderWidth = 2.2;

  /// Standaard afronding voor kaarten
  static const double cardRadius = 18.0;

  /// Zelfde afstand tussen header/tabbar en inhoud op alle tabbladen
  static const EdgeInsets tabContentPadding = EdgeInsets.fromLTRB(16, 12, 16, 12);
}