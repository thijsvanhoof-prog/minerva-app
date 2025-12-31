import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppUI {
  const AppUI._();

  static ThemeData theme() {
    final colorScheme = ColorScheme.dark(
      primary: AppColors.primary,        // oranje
      surface: AppColors.background,     // achtergrond
      onSurface: AppColors.onBackground, // tekst op achtergrond
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

      // ✅ Cards overal dezelfde styling: blauw vlak + dikke oranje rand
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(
            color: AppColors.primary,
            width: 2.2,
          ),
        ),
      ),

      // ✅ ListTile: iconen ook oranje, tekst kleuren consistent
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.primary,
        textColor: AppColors.onBackground,
      ),

      // ✅ AppBar styling
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.onBackground,
        centerTitle: true,
        elevation: 0,
      ),

      // ✅ Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.background,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
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
    );
  }
}