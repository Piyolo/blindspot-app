import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Theme factory for BlindSpot.
class AppTheme {
  const AppTheme._();

  /// Status-bar overlay for the app's dark surface: dark background with
  /// light (white) icons — Phase 0 rendered the status bar light against
  /// the dark app (the pinned on-device fix). `elevated` is the app's
  /// chrome color, so the bar blends with the AppBar directly beneath it
  /// instead of fighting the cream/blue identity.
  ///
  /// What actually reaches the platform (verified by the smoke tests):
  /// an imperative `SystemChrome` call does NOT — MaterialApp's theme
  /// builder re-sends `SystemUiOverlayStyle.light` (its statusBarColor
  /// is null) during every build. The effective carriers are layer-tree
  /// `AnnotatedRegion<SystemUiOverlayStyle>`s: every AppBar picks this
  /// style up from [appBarTheme] and re-announces it in its own region,
  /// and the AppBar-less SplashScreen embeds the same value in its own.
  /// AppBar-less Welcome/Home still get only the framework's light-icons
  /// default until they gain an AppBar or their own region.
  static const SystemUiOverlayStyle statusBarStyle = SystemUiOverlayStyle(
    statusBarColor: AppColors.elevated,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );

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
        systemOverlayStyle: statusBarStyle,
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
