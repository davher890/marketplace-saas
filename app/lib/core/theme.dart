import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette taken from the current Wix site.
class AppColors {
  const AppColors._();

  /// Sage green used as the page background.
  static const sage = Color(0xFFBBCBC1);

  /// Lighter sage for cards and surfaces.
  static const sageLight = Color(0xFFDCE5DF);

  /// Dark green used for the selected menu item and primary actions.
  static const forest = Color(0xFF37453B);

  /// Warm cream used for text on dark backgrounds.
  static const cream = Color(0xFFEEE4E0);

  /// Brown used in the footer.
  static const cocoa = Color(0xFF493C36);

  /// Almost-black brown used for body text.
  static const ink = Color(0xFF251E1B);

  /// Dusty pink accent.
  static const mauve = Color(0xFFA5848D);

  static const surface = Color(0xFFFFFFFF);
}

class AppTheme {
  const AppTheme._();

  /// Handwritten style used for the "Doña Galleta" wordmark.
  static TextStyle wordmark({double size = 48, Color color = AppColors.ink}) =>
      GoogleFonts.sacramento(
        fontSize: size,
        color: color,
        fontWeight: FontWeight.w600,
      );

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.forest,
      primary: AppColors.forest,
      onPrimary: AppColors.cream,
      secondary: AppColors.mauve,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      surfaceContainerHighest: AppColors.sageLight,
    );

    final bodyText = GoogleFonts.ralewayTextTheme().apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );

    // Headings use Amatic SC like the site; body text uses Raleway.
    TextStyle? heading(TextStyle? base) =>
        GoogleFonts.amaticSc(textStyle: base, fontWeight: FontWeight.w700);

    final textTheme = bodyText.copyWith(
      displayLarge: heading(bodyText.displayLarge),
      displayMedium: heading(bodyText.displayMedium),
      displaySmall: heading(bodyText.displaySmall),
      headlineLarge: heading(bodyText.headlineLarge),
      headlineMedium: heading(bodyText.headlineMedium),
      headlineSmall: heading(bodyText.headlineSmall),
      titleLarge: bodyText.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.sage,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.sage,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.forest,
          foregroundColor: AppColors.cream,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.forest,
          side: const BorderSide(color: AppColors.forest),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.forest, width: 1.5),
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.forest,
        secondarySelectedColor: AppColors.forest,
        side: BorderSide.none,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.sageLight,
        indicatorColor: AppColors.sage,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.forest,
        contentTextStyle: TextStyle(color: AppColors.cream),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
