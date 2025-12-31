import 'package:flutter/material.dart';

/// Centrale kleur- en UI-richtlijn voor de hele app
class AppColors {
  /* ===================== BASIS ===================== */

  /// App-achtergrond
  static const Color background = Color(0xFF07101A);

  /// Kaarten / widgets
  static const Color card = Color(0xFF0E1B2A);

  /// Primaire clubkleur (oranje)
  static const Color primary = Color(0xFFFF8A00);

  /* ===================== TEKST ===================== */

  /// Hoofdtekst op donkere achtergrond
  static const Color onBackground = Color(0xFFEAF1FF);

  /// Secundaire tekst (subtitles, hints)
  static const Color textSecondary = Color(0xFFB7C3D6);

  /* ===================== ICONEN ===================== */

  /// Inactieve / gedempte iconen
  static const Color iconMuted = Color(0xFF8FA1B8);

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
}