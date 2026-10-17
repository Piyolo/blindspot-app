import 'package:flutter/material.dart';

/// Color tokens for the BlindSpot dark theme.
class AppColors {
  const AppColors._();

  static const Color surface = Color(0xFF0A101C);
  static const Color elevated = Color(0xFF121A2C);
  static const Color container = Color(0xFF162033);
  static const Color border = Color(0xFF334056);
  static const Color onSurface = Color(0xFFFFFFFF);
  static const Color variant = Color(0xFFB9C2D6);
  static const Color brand = Color(0xFF2C5A86);
  static const Color brandLight = Color(0xFF7FB3D9);
  static const Color cream = Color(0xFFF2DEC1);
  static const Color onCream = Color(0xFF0E2A4A);
  static const Color error = Color(0xFFD9534F);
  static const Color errorText = Color(0xFFF5A9A3);
  static const Color errorSurface = Color(0xFF3A1A18);
  static const Color warning = Color(0xFFF0B429);
  static const Color success = Color(0xFF4CAF50);
}

/// Text style tokens for the BlindSpot dark theme.
///
/// Color is [AppColors.onSurface] unless noted.
class AppTextStyles {
  const AppTextStyles._();

  static const TextStyle display = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
  );

  static const TextStyle screenTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
  );

  static const TextStyle section = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.onSurface,
  );

  /// The app default body size.
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: AppColors.onSurface,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.onSurface,
  );

  static const TextStyle button = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.onSurface,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.variant,
  );

  static const TextStyle status = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.onSurface,
  );

  static const TextStyle countdown = TextStyle(
    fontSize: 64,
    fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
  );
}
