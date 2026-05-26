import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color darkText = Color(0xFF111827);
  static const Color subtitleGrey = Color(0xFF6B7280);
  static const Color borderGrey = Color(0xFFE5E7EB);
  static const Color iconGrey = Color(0xFF6B7280);
  static const Color hintGrey = Color(0xFF9CA3AF);
  static const Color versionGrey = Color(0xFF9CA3AF);
  static const Color background = Colors.white;
}

class AppTheme {
  static ThemeData light = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    primaryColor: AppColors.primaryBlue,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primaryBlue,
      primary: AppColors.primaryBlue,
    ),
    fontFamily: 'Roboto',
  );
}
