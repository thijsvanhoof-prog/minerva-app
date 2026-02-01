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

      // Branded background is drawn behind all routes; keep scaffolds transparent.
      scaffoldBackgroundColor: Colors.transparent,

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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.55),
            width: AppColors.cardBorderWidth,
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
          ),
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

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return selected ? AppColors.primary : AppColors.iconMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return selected
              ? AppColors.primary.withValues(alpha: 0.45)
              : AppColors.darkBlue.withValues(alpha: 0.12);
        }),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return selected ? AppColors.primary : Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: BorderSide(color: AppColors.darkBlue.withValues(alpha: 0.25)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: AppColors.darkBlue.withValues(alpha: 0.18),
        thickness: 1,
        space: 1,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          side: BorderSide(
            color: AppColors.darkBlue.withValues(alpha: 0.15),
            width: AppColors.cardBorderWidth,
          ),
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.onBackground,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.onBackground,
        ),
      ),

      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: TextStyle(fontWeight: FontWeight.w800),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppColors.cardRadius),
            ),
          ),
          side: WidgetStateProperty.all(
            BorderSide(color: AppColors.darkBlue.withValues(alpha: 0.18), width: 1),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return selected ? AppColors.darkBlue : Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return selected ? AppColors.primary : AppColors.textSecondary;
          }),
          textStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            );
          }),
        ),
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