import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The single source of truth for the app's visual identity.
///
/// Aesthetic: a "warm ledger" — parchment surfaces, deep pine-emerald for
/// trust, and a reserved brass accent used only for monetary values. Fraunces
/// (a characterful serif) carries amounts and headings; Plus Jakarta Sans
/// handles body text and labels.
class AppColors {
  AppColors._();

  static const parchment = Color(0xFFF6F1E7); // app background
  static const surface = Color(0xFFFFFDF8); // cards
  static const pine = Color(0xFF0E5A47); // primary
  static const pineDark = Color(0xFF0A3F32);
  static const sage = Color(0xFFDCE9E1); // primary container
  static const brass = Color(0xFFB07D2B); // money accent
  static const ink = Color(0xFF1B2620); // primary text
  static const muted = Color(0xFF6E7B73); // secondary text
  static const hairline = Color(0xFFE6DECF); // dividers/borders
  static const danger = Color(0xFFA8362B);
  static const success = Color(0xFF2E7D5B);
}

class AppRadius {
  AppRadius._();
  static const card = 22.0;
  static const chip = 14.0;
  static const field = 16.0;
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.pine,
      primary: AppColors.pine,
      onPrimary: Colors.white,
      primaryContainer: AppColors.sage,
      onPrimaryContainer: AppColors.pineDark,
      secondary: AppColors.brass,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.danger,
      brightness: Brightness.light,
    );

    final body = GoogleFonts.plusJakartaSansTextTheme();
    final display = GoogleFonts.fraunces(); // applied selectively below

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.parchment,
      textTheme: body.copyWith(
        displaySmall: display.copyWith(
            fontWeight: FontWeight.w600, color: AppColors.ink),
        headlineMedium: GoogleFonts.fraunces(
            fontWeight: FontWeight.w600, color: AppColors.ink),
        headlineSmall: GoogleFonts.fraunces(
            fontWeight: FontWeight.w600, color: AppColors.ink),
        titleLarge: body.titleLarge?.copyWith(
            fontWeight: FontWeight.w700, color: AppColors.ink),
        bodyMedium: body.bodyMedium?.copyWith(color: AppColors.ink),
        labelLarge:
            body.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.parchment,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.hairline),
        ),
      ),
      dividerColor: AppColors.hairline,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: AppColors.pine, width: 1.6),
        ),
        labelStyle: const TextStyle(color: AppColors.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.pine,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
          textStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700, fontSize: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.field)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.pine,
          side: const BorderSide(color: AppColors.pine, width: 1.4),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 22),
          textStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.field)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.pineDark,
        contentTextStyle: GoogleFonts.plusJakartaSans(color: Colors.white),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.chip)),
      ),
    );
  }

  /// Fraunces, for monetary figures we want to feel crafted and deliberate.
  static TextStyle money(
          {double size = 28, Color color = AppColors.ink, FontWeight? weight}) =>
      GoogleFonts.fraunces(
        fontSize: size,
        color: color,
        fontWeight: weight ?? FontWeight.w600,
        letterSpacing: -0.5,
      );

  /// Deterministic warm avatar colour derived from a name.
  static Color avatarColor(String seed) {
    const palette = [
      Color(0xFF0E5A47),
      Color(0xFFB07D2B),
      Color(0xFF3A6B8A),
      Color(0xFF8A5A3A),
      Color(0xFF6A4C93),
      Color(0xFF2E7D5B),
    ];
    if (seed.isEmpty) return palette.first;
    final code = seed.codeUnits.fold<int>(0, (a, b) => a + b);
    return palette[code % palette.length];
  }
}
