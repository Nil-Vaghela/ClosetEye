import 'package:flutter/material.dart';

class AppColors {
  // ── Base — warm sand / cream ──────────────────────────────────────────────
  static const bg      = Color(0xFFF8F4EE); // warm ivory sand
  static const surface = Color(0xFFFFFFFF); // pure white for elevated cards

  // ── Champagne gold accent ─────────────────────────────────────────────────
  static const gold     = Color(0xFFC49B3C); // deeper warm gold (more readable on light)
  static const goldMid  = Color(0xFFD4A853); // champagne
  static const goldDark = Color(0xFF8A6220); // deep antique gold (shadows)

  // ── Light glass system (warm-white frosted panels) ────────────────────────
  static const glass       = Color(0xB3FFFFFF); // white 70%
  static const glassMid    = Color(0xCCFFFFFF); // white 80%
  static const glassBright = Color(0xE6FFFFFF); // white 90%
  static const glassBorder = Color(0xFFE2D8CC); // warm taupe border

  // ── Text (warm dark tones — rich on sand/cream backgrounds) ──────────────
  static const textPrimary   = Color(0xFF1C1A16); // warm near-black
  static const textSecondary = Color(0x991C1A16); // 60% warm dark
  static const textMuted     = Color(0x661C1A16); // 40% warm dark
  static const textHint      = Color(0x3D1C1A16); // 24% warm dark

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const error   = Color(0xFFCF6679);
  static const success = Color(0xFF7BAE8A);

  // ── Gradients ─────────────────────────────────────────────────────────────
  // Primary: champagne gold
  static const accent = LinearGradient(
    colors: [gold, goldMid],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const accentVert = LinearGradient(
    colors: [gold, goldMid],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Background: warm ivory sand — barely-there, like quality paper
  static const bgGradient = LinearGradient(
    colors: [Color(0xFFFDF9F4), Color(0xFFF2EAE0)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Card surfaces: pure white to warm white
  static const surfaceGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFFAF5EE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.light(
      primary: AppColors.gold,
      secondary: AppColors.goldMid,
      surface: AppColors.surface,
      onPrimary: AppColors.textPrimary,
      onSurface: AppColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
    textTheme: const TextTheme(
      displayLarge:   TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
      displayMedium:  TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
      headlineLarge:  TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 32),
      headlineMedium: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 24),
      titleLarge:     TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 18),
      bodyLarge:      TextStyle(color: AppColors.textPrimary, fontSize: 16),
      bodyMedium:     TextStyle(color: AppColors.textSecondary, fontSize: 14),
      bodySmall:      TextStyle(color: AppColors.textMuted, fontSize: 12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
      ),
      hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 15),
      labelStyle: const TextStyle(color: AppColors.textMuted),
    ),
    dividerColor: AppColors.glassBorder,
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(100),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
  );

  // Keep dark alias pointing to light until dark mode is re-introduced
  static ThemeData get dark => light;
}
