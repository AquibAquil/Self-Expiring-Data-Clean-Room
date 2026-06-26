import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand color palette — muted, professional, enterprise-security tone.
///
/// Colors are paired with semantic names so the rest of the app never refers
/// to raw hex values directly.
class AppColors {
  // Primary (deep teal — reads as "secure, professional, considered")
  static const Color primary = Color(0xFF0F4C5C);
  static const Color primaryDark = Color(0xFF0A3540);
  static const Color primaryLight = Color(0xFF2A6B7C);

  // Surfaces
  static const Color surface = Color(0xFFFAFAF8);     // off-white with warmth
  static const Color surfaceAlt = Color(0xFFF1F1ED);  // subtle card differentiation
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // Text
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF5A5A5A);
  static const Color textTertiary = Color(0xFF8A8A8A);

  // Borders
  static const Color border = Color(0xFFE0E0DC);
  static const Color borderStrong = Color(0xFFC8C8C2);

  // State colors — muted, not consumer-bright
  static const Color success = Color(0xFF4F7942);            // muted green
  static const Color successBg = Color(0xFFEEF3EB);
  static const Color successBorder = Color(0xFFD0DECA);

  static const Color warning = Color(0xFFC77B00);            // warm amber
  static const Color warningBg = Color(0xFFFAF1E1);
  static const Color warningBorder = Color(0xFFE8D5A8);

  static const Color danger = Color(0xFF8B3A3A);             // muted red-brown
  static const Color dangerBg = Color(0xFFF6E8E8);
  static const Color dangerBorder = Color(0xFFE5C9C9);

  static const Color info = Color(0xFF2A6B7C);
  static const Color infoBg = Color(0xFFE4EEF1);
  static const Color infoBorder = Color(0xFFB8D2D9);
}

/// Builds the app-wide ThemeData. Material 3, light theme, custom palette.
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.surface,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.surface,
      surfaceContainerHighest: AppColors.surfaceAlt,
    ),
    textTheme: GoogleFonts.interTextTheme().apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceElevated,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceElevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
      hintStyle: GoogleFonts.jetBrainsMono(
        color: AppColors.textTertiary,
        fontSize: 15,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: BorderSide(color: AppColors.primary, width: 1.2),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
  );
}

/// Monospace style for cryptographic identifiers (atSigns, key names, etc.).
TextStyle monoStyle({double size = 14, FontWeight weight = FontWeight.w400, Color? color}) {
  return GoogleFonts.jetBrainsMono(
    fontSize: size,
    fontWeight: weight,
    color: color ?? AppColors.textSecondary,
  );
}
