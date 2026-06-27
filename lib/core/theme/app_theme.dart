import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const brandBackground = Color(0xFFFFF9F2);
  static const brandSurface = Color(0xFFFFFFFF);
  static const brandCream = Color(0xFFFFF4E4);
  static const brandAmber = Color(0xFFF59E2E);
  static const brandAmberSoft = Color(0xFFFFF1D6);
  static const brandPlum = Color(0xFF2B1A2D);
  static const brandText = Color(0xFF1F1C1A);
  static const brandMuted = Color(0xFF756B62);
  static const brandBorder = Color(0xFFEADCCB);

  static const primary = brandPlum;
  static const primaryLight = Color(0xFF4A344C);
  static const primarySoft = brandCream;
  static const accent = brandAmber;
  static const softAccent = brandAmberSoft;
  static const background = brandBackground;
  static const surface = brandSurface;
  static const surfaceSoft = brandCream;
  static const textPrimary = brandText;
  static const textSecondary = brandMuted;
  static const border = brandBorder;
  static const positive = Color(0xFF2F8F62);
  static const positiveSoft = Color(0xFFE8F6EE);
  static const warning = Color(0xFFC7861A);
  static const warningSoft = Color(0xFFFFF3D8);
  static const danger = Color(0xFFC94D4D);
  static const dangerSoft = Color(0xFFFFECEC);
  static const info = Color(0xFF3B82F6);
  static const neutral = Color(0xFF94A3B8);

  static const success = positive;
  static const successBg = positiveSoft;
  static const successText = Color(0xFF245E45);
  static const warningBg = warningSoft;
  static const warningText = Color(0xFF8A6115);
  static const dangerBg = dangerSoft;
  static const dangerText = Color(0xFF8E3636);
  static const infoBg = Color(0xFFDBEAFE);
  static const infoText = Color(0xFF1E40AF);
  static const neutralBg = Color(0xFFFFF7EC);
  static const neutralText = Color(0xFF6C625A);
}

class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  AppRadius._();

  static const chip = 16.0;
  static const input = 20.0;
  static const button = 20.0;
  static const card = 22.0;
  static const sheet = 28.0;
}

class AppShadows {
  AppShadows._();

  static List<BoxShadow> soft([Color color = AppColors.accent]) => [
    BoxShadow(
      color: color.withValues(alpha: 0.1),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}

class AppTextStyles {
  AppTextStyles._();

  static TextStyle get badge => GoogleFonts.manrope(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.1,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData lightTheme({bool useGoogleFonts = true}) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          secondary: AppColors.accent,
          onSecondary: AppColors.brandPlum,
          error: AppColors.danger,
          onError: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          surfaceContainerHighest: AppColors.surfaceSoft,
          outline: AppColors.border,
          outlineVariant: AppColors.border,
          tertiary: AppColors.accent,
          onTertiary: AppColors.brandPlum,
        );

    final baseText =
        (useGoogleFonts
                ? GoogleFonts.manropeTextTheme()
                : ThemeData(useMaterial3: true).textTheme)
            .apply(
              bodyColor: AppColors.textPrimary,
              displayColor: AppColors.textPrimary,
            );

    final textTheme = baseText.copyWith(
      displayLarge: baseText.displayLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      titleLarge: baseText.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: baseText.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: baseText.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: baseText.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      bodyMedium: baseText.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      labelMedium: baseText.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      labelSmall: baseText.labelSmall?.copyWith(fontWeight: FontWeight.w700),
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      cardColor: AppColors.surface,
      dividerColor: AppColors.border,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: const IconThemeData(color: AppColors.primary),
        actionsIconTheme: const IconThemeData(color: AppColors.primary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
        prefixIconColor: AppColors.primary,
        suffixIconColor: AppColors.primary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.neutralBg,
        selectedColor: AppColors.softAccent,
        disabledColor: AppColors.neutralBg,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        labelStyle: textTheme.labelSmall?.copyWith(
          color: AppColors.neutralText,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: textTheme.labelSmall?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w800,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size.fromHeight(48),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textSecondary,
        selectedLabelStyle: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: textTheme.labelSmall,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}
