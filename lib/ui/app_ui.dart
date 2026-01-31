import 'package:flutter/material.dart';
import 'package:minerva_app/ui/app_colors.dart';

class AppUI {
  const AppUI._();

  static ThemeData theme() {
    final colorScheme = ColorScheme.light(
      primary: AppColors.primary,        // oranje
      surface: AppColors.background,     // lichte achtergrond
      onSurface: AppColors.onBackground, // donkerblauwe tekst
      error: AppColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,

      scaffoldBackgroundColor: AppColors.background,

      // ✅ Alle iconen standaard oranje (tenzij je ze lokaal overschrijft)
      iconTheme: const IconThemeData(
        color: AppColors.primary,
      ),

      // Default CardTheme (legacy pages). New UI uses GlassCard instead.
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          side: BorderSide(
            color: const Color(0xFF1A2B4A).withValues(alpha: 0.15),
            width: AppColors.cardBorderWidth,
          ),
        ),
      ),

      // ✅ ListTile: iconen ook oranje, tekst kleuren consistent
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.primary,
        textColor: AppColors.onBackground,
      ),

      // ✅ AppBar styling (transparant, donkerblauwe omheining)
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.onBackground,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: AppColors.darkBlue, width: 1),
        ),
      ),

      // ✅ Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.darkBlue,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.primary : Colors.white,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.primary : Colors.white,
          );
        }),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1A2B4A).withValues(alpha: 0.95),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),

      // ✅ Progress indicator
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),

      // ✅ Tekst (optioneel, maar netjes)
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: AppColors.onBackground),
        bodySmall: TextStyle(color: AppColors.textSecondary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          borderSide: BorderSide(color: const Color(0xFF1A2B4A).withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.3),
        ),
      ),
    );
  }
}