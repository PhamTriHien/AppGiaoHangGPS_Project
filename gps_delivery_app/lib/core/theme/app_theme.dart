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

  // Hình học góc vuông sắc nét chuẩn Neo-Brutalist Studio (border-radius: 0)
  static const double buttonMinHeight = 48.0;
  static const double buttonRadius = 0.0;
  static const double fabSize = 56.0;
  static const double inputHeight = 52.0;
  static const double inputRadius = 0.0;
  static const double cardRadius = 0.0;
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
      scaffoldBackgroundColor: const Color(0xFFF7F9FA),
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
        foregroundColor: Color(0xFF20282B),
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
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE1E7E9)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.violet,
      primary: AppColors.violet,
      secondary: AppColors.pink,
      tertiary: AppColors.acid,
      surface: AppColors.surface,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.paper,
      dividerColor: AppColors.line,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.techBg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -0.6,
          height: 1.2,
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w900,
          color: AppColors.ink,
          letterSpacing: -1.1,
          height: 1.05,
        ),
        headlineMedium: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          letterSpacing: -0.7,
          height: 1.15,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          letterSpacing: -0.4,
          height: 1.3,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
          letterSpacing: -0.2,
          height: 1.35,
        ),
        bodyMedium: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
          height: 1.55,
        ),
        bodySmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.3,
          height: 1.4,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: AppColors.ink, width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.violet,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(88, AppSpacing.buttonMinHeight),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: AppColors.ink, width: 1.2),
          ),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.acid,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: AppColors.ink, width: 1.2),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.ink, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: AppColors.ink,
        secondarySelectedColor: AppColors.violet,
        disabledColor: AppColors.warmStone,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: AppColors.ink, width: 1.0),
        ),
        labelStyle: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        secondaryLabelStyle: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        constraints: BoxConstraints(minHeight: AppSpacing.inputHeight),
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.ink, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.ink, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.violet, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.pink, width: 1.6),
        ),
      ),
    );
  }
}
