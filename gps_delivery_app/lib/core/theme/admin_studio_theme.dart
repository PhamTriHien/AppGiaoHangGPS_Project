import 'package:flutter/material.dart';

class AdminStudioColors {
  const AdminStudioColors._();

  static const Color paper = Color(0xFFEEF3F8);
  static const Color paperWarm = Color(0xFFE3EBF3);
  static const Color surface = Color(0xFFFCFDFE);
  static const Color surfaceSubtle = Color(0xFFF5F8FC);
  static const Color ink = Color(0xFF122033);
  static const Color shellDark = Color(0xFF162438);
  static const Color shellDeep = Color(0xFF101B2B);
  static const Color shellElevated = Color(0xFF1F314B);
  static const Color shellActive = Color(0xFF294163);
  static const Color shellLine = Color(0x24E2E8F0);
  static const Color violet = Color(0xFF1E56C5);
  static const Color violetSoft = Color(0xFFE8EFFC);
  static const Color violetInk = Color(0xFF163E91);
  static const Color acid = Color(0xFFA8E6CF);
  static const Color acidSoft = Color(0xFFE4F5F0);
  static const Color acidInk = Color(0xFF0C5943);
  static const Color pink = Color(0xFFC85A17);
  static const Color pinkSoft = Color(0xFFFDF0E7);
  static const Color gold = Color(0xFFEAB344);
  static const Color goldSoft = Color(0xFFFEF6E4);
  static const Color goldInk = Color(0xFF734806);
  static const Color muted = Color(0xFF516278);
  static const Color mutedOnDark = Color(0xFF9EB0C7);
  static const Color line = Color(0xFFD7E0EC);
  static const Color controlBorder = Color(0xFF78899F);
  static const Color danger = Color(0xFFC43232);
  static const Color dangerSoft = Color(0xFFFCECEC);
}

class AdminStudioTheme {
  const AdminStudioTheme._();

  static ThemeData themeData() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AdminStudioColors.violet,
      primary: AdminStudioColors.violet,
      onPrimary: Colors.white,
      secondary: AdminStudioColors.acidInk,
      onSecondary: Colors.white,
      surface: AdminStudioColors.surface,
      onSurface: AdminStudioColors.ink,
      outline: AdminStudioColors.controlBorder,
      outlineVariant: AdminStudioColors.line,
      error: AdminStudioColors.danger,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AdminStudioColors.paper,
      cardTheme: CardThemeData(
        elevation: 0,
        color: AdminStudioColors.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AdminStudioColors.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: AdminStudioColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AdminStudioColors.line),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AdminStudioColors.line,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AdminStudioColors.surface,
        selectedColor: AdminStudioColors.violetSoft,
        disabledColor: AdminStudioColors.paperWarm,
        checkmarkColor: AdminStudioColors.violet,
        side: const BorderSide(color: AdminStudioColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(
          color: AdminStudioColors.ink,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AdminStudioColors.controlBorder),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AdminStudioColors.violetSoft;
            }
            return AdminStudioColors.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AdminStudioColors.violetInk;
            }
            return AdminStudioColors.ink;
          }),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AdminStudioColors.surfaceSubtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminStudioColors.controlBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminStudioColors.controlBorder),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminStudioColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AdminStudioColors.violet,
            width: 1.8,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AdminStudioColors.danger,
            width: 1.4,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AdminStudioColors.danger,
            width: 1.8,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AdminStudioColors.violet,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AdminStudioColors.paperWarm,
          disabledForegroundColor: AdminStudioColors.muted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: AdminStudioColors.surface,
          foregroundColor: AdminStudioColors.ink,
          disabledForegroundColor: AdminStudioColors.muted,
          side: const BorderSide(color: AdminStudioColors.controlBorder),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AdminStudioColors.violet,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

class AdminStudioMark extends StatelessWidget {
  const AdminStudioMark({
    super.key,
    this.size = 40,
    this.onDark = true,
  });

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final bg = onDark
        ? AdminStudioColors.violet
        : AdminStudioColors.violetSoft;
    final fg = onDark ? Colors.white : AdminStudioColors.violetInk;
    final stripe = onDark
        ? AdminStudioColors.acid
        : AdminStudioColors.violet;
    final tagColor = onDark
        ? AdminStudioColors.acid
        : AdminStudioColors.acidInk;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular((size * 0.28).clamp(8.0, 14.0)),
        border: Border.all(
          color: onDark
              ? Colors.white.withValues(alpha: 0.16)
              : AdminStudioColors.line,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: (size * 0.12).clamp(3.5, 5.5),
            child: ColoredBox(color: stripe),
          ),
          Align(
            alignment: const Alignment(-0.08, 0.1),
            child: Text(
              'G',
              style: TextStyle(
                color: fg,
                fontSize: size * 0.46,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: -0.6,
              ),
            ),
          ),
          Positioned(
            right: size * 0.11,
            top: size * 0.13,
            child: Text(
              'OPS',
              style: TextStyle(
                color: tagColor,
                fontSize: (size * 0.15).clamp(5.5, 7.5),
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminStudioGridBackdrop extends StatelessWidget {
  const AdminStudioGridBackdrop({
    super.key,
    required this.child,
    this.backgroundColor = AdminStudioColors.shellDark,
    this.gridSpacing = 56,
  });

  final Widget child;
  final Color backgroundColor;
  final double gridSpacing;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _StudioGridPainter(
      backgroundColor: backgroundColor,
      gridSpacing: gridSpacing,
    ),
    child: child,
  );
}

class _StudioGridPainter extends CustomPainter {
  const _StudioGridPainter({
    required this.backgroundColor,
    required this.gridSpacing,
  });

  final Color backgroundColor;
  final double gridSpacing;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = backgroundColor);

    final isDark = backgroundColor.computeLuminance() < 0.25;
    final glowCenter = Offset(size.width * 0.78, size.height * 0.16);
    final glowRadius = (size.shortestSide * 0.8).clamp(180.0, 480.0);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AdminStudioColors.violet.withValues(alpha: isDark ? 0.22 : 0.08),
          AdminStudioColors.violet.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius));
    canvas.drawCircle(glowCenter, glowRadius, glowPaint);

    final secondaryCenter = Offset(size.width * 0.18, size.height * 0.84);
    final secondaryPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AdminStudioColors.acidInk.withValues(alpha: isDark ? 0.16 : 0.06),
          AdminStudioColors.acidInk.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: secondaryCenter, radius: glowRadius * 0.85),
      );
    canvas.drawCircle(secondaryCenter, glowRadius * 0.85, secondaryPaint);

    final gridPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.04)
          : AdminStudioColors.ink.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StudioGridPainter oldDelegate) =>
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.gridSpacing != gridSpacing;
}

class AdminNeoBox extends StatelessWidget {
  const AdminNeoBox({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.backgroundColor = AdminStudioColors.surface,
    this.borderColor = AdminStudioColors.line,
    this.shadowColor = const Color(0x0E0F172A),
    this.borderWidth = 1.0,
    this.shadowOffset = const Offset(0, 4),
    this.borderRadius = 14.0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color backgroundColor;
  final Color borderColor;
  final Color shadowColor;
  final double borderWidth;
  final Offset shadowOffset;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final resolvedBorderColor = borderColor == AdminStudioColors.ink
        ? AdminStudioColors.line
        : borderColor;
    final resolvedShadowColor = shadowColor == AdminStudioColors.ink
        ? const Color(0x0E0F172A)
        : shadowColor.withValues(alpha: shadowColor.a.clamp(0.0, 0.14));
    return Semantics(
      container: true,
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: resolvedBorderColor,
            width: borderWidth.clamp(0.8, 1.4),
          ),
          boxShadow: shadowOffset == Offset.zero
              ? null
              : [
                  BoxShadow(
                    color: resolvedShadowColor,
                    offset: const Offset(0, 5),
                    blurRadius: 16,
                  ),
                  const BoxShadow(
                    color: Color(0x060F172A),
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: padding == EdgeInsets.zero
              ? child
              : Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
