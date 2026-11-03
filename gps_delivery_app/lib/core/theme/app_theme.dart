import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppSpacing {
  const AppSpacing._();

  // Hệ thống lưới khoảng cách 8pt
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;

  // Hình học bo góc hiện đại, dễ nhìn chuẩn Super-App
  static const double buttonMinHeight = 46.0;
  static const double buttonRadius = 10.0;
  static const double fabSize = 56.0;
  static const double inputHeight = 50.0;
  static const double inputRadius = 10.0;
  static const double cardRadius = 14.0;
}

class AppTheme {
  const AppTheme._();

  static ThemeData get commerceTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16734F))
          .copyWith(
            surface: Colors.white,
            secondary: const Color(0xFFB86127),
            surfaceContainerLow: const Color(0xFFF0F3F5),
          ),
      scaffoldBackgroundColor: const Color(0xFFF4F7FA),
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: base.textTheme.displayLarge?.copyWith(letterSpacing: 0),
        displayMedium: base.textTheme.displayMedium?.copyWith(letterSpacing: 0),
        displaySmall: base.textTheme.displaySmall?.copyWith(letterSpacing: 0),
        headlineLarge: base.textTheme.headlineLarge?.copyWith(letterSpacing: 0),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(letterSpacing: 0),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(letterSpacing: 0),
        titleLarge: base.textTheme.titleLarge?.copyWith(letterSpacing: 0),
        titleMedium: base.textTheme.titleMedium?.copyWith(letterSpacing: 0),
        titleSmall: base.textTheme.titleSmall?.copyWith(letterSpacing: 0),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(letterSpacing: 0),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(letterSpacing: 0),
        bodySmall: base.textTheme.bodySmall?.copyWith(letterSpacing: 0),
        labelLarge: base.textTheme.labelLarge?.copyWith(letterSpacing: 0),
        labelMedium: base.textTheme.labelMedium?.copyWith(letterSpacing: 0),
        labelSmall: base.textTheme.labelSmall?.copyWith(letterSpacing: 0),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF0F172A),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Color(0xFFDDEFE5),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.pink,
      tertiary: AppColors.success,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.paper,
      dividerColor: AppColors.line,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        shape: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          letterSpacing: -0.2,
          height: 1.25,
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          letterSpacing: -0.4,
          height: 1.15,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          letterSpacing: -0.3,
          height: 1.25,
        ),
        titleLarge: TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
          letterSpacing: -0.1,
          height: 1.35,
        ),
        titleMedium: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
          height: 1.35,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
          height: 1.45,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(84, AppSpacing.buttonMinHeight),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFFDBEAFE),
        secondarySelectedColor: AppColors.primary,
        checkmarkColor: AppColors.primary,
        disabledColor: AppColors.warmStone,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
        ),
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        constraints: const BoxConstraints(minHeight: AppSpacing.inputHeight),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.8),
        ),
      ),
    );
  }
}
