import 'package:flutter/material.dart';

import '../../presentation/widgets/ghst_button_icon.dart';
import 'app_colors.dart';
import 'ghst_theme_tokens.dart';

class AppSpacing {
  const AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;

  static const double buttonMinHeight = 48.0;
  static const double buttonRadius = 12.0;
  static const double fabSize = 56.0;
  static const double inputHeight = 50.0;
  static const double inputRadius = 12.0;
  static const double cardRadius = 16.0;
}

class AppTheme {
  const AppTheme._();

  static ThemeData get commerceTheme => commerceThemeForBrightness(Brightness.light);

  static ThemeData commerceThemeFor(BuildContext context) =>
      commerceThemeForBrightness(Theme.of(context).brightness);

  static ThemeData commerceThemeForBrightness(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final tokens = isDark ? GhstThemeTokens.dark : GhstThemeTokens.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: tokens.primary,
      brightness: brightness,
    ).copyWith(
      primary: tokens.primary,
      onPrimary: Colors.white,
      secondary: isDark ? const Color(0xFF34D399) : AppColors.success,
      onSecondary: isDark ? const Color(0xFF052E16) : Colors.white,
      tertiary: isDark ? const Color(0xFFFBBF24) : AppColors.gold,
      surface: tokens.cardSurface,
      onSurface: tokens.ink,
      onSurfaceVariant: tokens.inkSecondary,
      surfaceContainerLowest: tokens.canvas,
      surfaceContainerLow: tokens.cardSubtle,
      surfaceContainer: tokens.cardSurface,
      surfaceContainerHigh: tokens.cardMuted,
      surfaceContainerHighest: isDark
          ? const Color(0xFF243757)
          : const Color(0xFFE3ECF8),
      primaryContainer: tokens.sapphire.fill,
      onPrimaryContainer: tokens.sapphire.foreground,
      secondaryContainer: tokens.emerald.fill,
      onSecondaryContainer: tokens.emerald.foreground,
      tertiaryContainer: tokens.amber.fill,
      onTertiaryContainer: tokens.amber.foreground,
      errorContainer: tokens.rose.fill,
      onErrorContainer: tokens.rose.foreground,
      outline: tokens.borderStrong,
      outlineVariant: tokens.border,
      error: AppColors.danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.canvas,
      extensions: [tokens],
    );

    return base.copyWith(
      dividerColor: tokens.border,
      actionIconTheme: _ghstActionIconTheme,
      segmentedButtonTheme: const SegmentedButtonThemeData(
        selectedIcon: GhstButtonIcon.glyph(GhstActionKind.check, size: 15),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.cardSurface,
        foregroundColor: tokens.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.cardSurface,
        indicatorColor: tokens.sapphire.fill,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.cardSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: tokens.cardSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.cardSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: tokens.border),
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.cardSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: tokens.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: isDark ? const Color(0x88000000) : const Color(0x1F0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: tokens.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.cardSubtle,
        selectedColor: tokens.sapphire.fill,
        secondarySelectedColor: tokens.primary,
        checkmarkColor: tokens.sapphire.foreground,
        disabledColor: tokens.cardMuted,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: tokens.borderStrong),
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: tokens.ink,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.cardSubtle,
        hintStyle: TextStyle(color: tokens.inkMuted, fontSize: 13),
        labelStyle: TextStyle(
          color: tokens.inkSecondary,
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: tokens.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: tokens.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: tokens.primary, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(44, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.ink,
          backgroundColor: tokens.cardSurface,
          minimumSize: const Size(44, 46),
          side: BorderSide(color: tokens.borderStrong),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF1E293B) : AppColors.ink,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData get lightTheme => _buildMainTheme(Brightness.light);
  static ThemeData get darkTheme => _buildMainTheme(Brightness.dark);

  static ThemeData _buildMainTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final tokens = isDark ? GhstThemeTokens.dark : GhstThemeTokens.light;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: tokens.primary,
      brightness: brightness,
      primary: tokens.primary,
      onPrimary: Colors.white,
      secondary: isDark ? const Color(0xFFFB7185) : AppColors.pink,
      tertiary: AppColors.acid,
      surface: tokens.cardSurface,
      onSurface: tokens.ink,
      error: AppColors.danger,
    ).copyWith(
      onSurfaceVariant: tokens.inkSecondary,
      surfaceContainerLowest: tokens.canvas,
      surfaceContainerLow: tokens.cardSubtle,
      surfaceContainer: tokens.cardSurface,
      surfaceContainerHigh: tokens.cardMuted,
      surfaceContainerHighest: isDark
          ? const Color(0xFF243757)
          : const Color(0xFFE3ECF8),
      primaryContainer: tokens.sapphire.fill,
      onPrimaryContainer: tokens.sapphire.foreground,
      secondaryContainer: tokens.emerald.fill,
      onSecondaryContainer: tokens.emerald.foreground,
      tertiaryContainer: tokens.amber.fill,
      onTertiaryContainer: tokens.amber.foreground,
      errorContainer: tokens.rose.fill,
      onErrorContainer: tokens.rose.foreground,
      outline: tokens.borderStrong,
      outlineVariant: tokens.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.canvas,
      dividerColor: tokens.border,
      extensions: [tokens],
      actionIconTheme: _ghstActionIconTheme,
      segmentedButtonTheme: const SegmentedButtonThemeData(
        selectedIcon: GhstButtonIcon.glyph(GhstActionKind.check, size: 15),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.shellBg,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -0.3,
          height: 1.2,
        ),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: tokens.ink,
          letterSpacing: -0.8,
          height: 1.1,
        ),
        headlineMedium: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          color: tokens.ink,
          letterSpacing: -0.4,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: tokens.ink,
          letterSpacing: -0.2,
          height: 1.3,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: tokens.ink,
          letterSpacing: -0.1,
          height: 1.35,
        ),
        bodyMedium: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: tokens.ink,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: tokens.inkSecondary,
          letterSpacing: 0.1,
          height: 1.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.cardSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          side: BorderSide(color: tokens.border, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: isDark ? const Color(0x88000000) : const Color(0x1F0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: tokens.border, width: 1),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.cardSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: tokens.cardSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.cardSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: tokens.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(88, AppSpacing.buttonMinHeight),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
          foregroundColor: tokens.ink,
          backgroundColor: tokens.cardSurface,
          side: BorderSide(color: tokens.borderStrong, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        backgroundColor: tokens.cardSubtle,
        selectedColor: tokens.sapphire.fill,
        secondarySelectedColor: tokens.sapphire.fill,
        checkmarkColor: tokens.sapphire.foreground,
        iconTheme: IconThemeData(color: tokens.sapphire.foreground, size: 15),
        disabledColor: tokens.cardMuted,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: tokens.borderStrong, width: 1),
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: tokens.ink,
        ),
        secondaryLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: tokens.sapphire.foreground,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.cardSubtle,
        hintStyle: TextStyle(color: tokens.inkMuted, fontSize: 13),
        labelStyle: TextStyle(
          color: tokens.inkSecondary,
          fontWeight: FontWeight.w600,
        ),
        constraints: const BoxConstraints(minHeight: AppSpacing.inputHeight),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: BorderSide(color: tokens.borderStrong, width: 1.1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: BorderSide(color: tokens.borderStrong, width: 1.1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: BorderSide(color: tokens.primary, width: 1.8),
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
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF1E293B) : AppColors.ink,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static final ActionIconThemeData _ghstActionIconTheme = ActionIconThemeData(
    backButtonIconBuilder: (_) =>
        const GhstButtonIcon.glyph(GhstActionKind.back, size: 20),
    closeButtonIconBuilder: (_) =>
        const GhstButtonIcon.glyph(GhstActionKind.close, size: 20),
    drawerButtonIconBuilder: (_) =>
        const GhstButtonIcon.glyph(GhstActionKind.grid, size: 20),
    endDrawerButtonIconBuilder: (_) =>
        const GhstButtonIcon.glyph(GhstActionKind.tune, size: 20),
  );
}
