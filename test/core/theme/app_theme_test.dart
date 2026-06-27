import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';

void main() {
  test('Etiketly brand tokens use warm consumer palette', () {
    expect(
      AppColors.brandBackground.toARGB32(),
      const Color(0xFFFFF9F2).toARGB32(),
    );
    expect(AppColors.brandAmber.toARGB32(), const Color(0xFFF59E2E).toARGB32());
    expect(AppColors.brandPlum.toARGB32(), const Color(0xFF2B1A2D).toARGB32());
    expect(AppColors.primary.toARGB32(), AppColors.brandPlum.toARGB32());
    expect(AppColors.accent.toARGB32(), AppColors.brandAmber.toARGB32());
  });

  test('AppTheme uses amber bottom-nav accent and plum app-bar icons', () {
    final theme = AppTheme.lightTheme(useGoogleFonts: false);

    expect(
      theme.bottomNavigationBarTheme.selectedItemColor?.toARGB32(),
      AppColors.brandAmber.toARGB32(),
    );
    expect(
      theme.appBarTheme.iconTheme?.color?.toARGB32(),
      AppColors.brandPlum.toARGB32(),
    );
    expect(
      theme.scaffoldBackgroundColor.toARGB32(),
      AppColors.brandBackground.toARGB32(),
    );
  });
}
