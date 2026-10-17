import 'package:flutter/material.dart';

import 'tokens.dart';

/// Theme factory for BlindSpot.
class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.surface,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.brandLight,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.elevated,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: TextTheme(
        displayLarge: AppTextStyles.display,
        displayMedium: AppTextStyles.countdown,
        headlineLarge: AppTextStyles.screenTitle,
        titleMedium: AppTextStyles.section,
        titleSmall: AppTextStyles.status,
        labelLarge: AppTextStyles.button,
        bodyLarge: AppTextStyles.bodyLarge,
        bodyMedium: AppTextStyles.body,
        bodySmall: AppTextStyles.caption,
      ),
    );
  }
}
