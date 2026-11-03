import 'package:flutter/material.dart';

class AdminStudioColors {
  const AdminStudioColors._();

  static const Color paper = Color(0xFFF4F7FA);
  static const Color paperWarm = Color(0xFFEFF3F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFF8FAFC);
  static const Color ink = Color(0xFF0F172A);
  static const Color shellDark = Color(0xFF0F172A);
  static const Color shellDeep = Color(0xFF090E1A);
  static const Color shellElevated = Color(0xFF1E293B);
  static const Color shellActive = Color(0xFF1E3A8A);
  static const Color shellLine = Color(0x26CBD5E1);
  static const Color violet = Color(0xFF2563EB);
  static const Color violetSoft = Color(0xFFEFF6FF);
  static const Color violetInk = Color(0xFF1E3A8A);
  static const Color acid = Color(0xFF6EE7B7);
  static const Color acidSoft = Color(0xFFECFDF5);
  static const Color acidInk = Color(0xFF065F46);
  static const Color pink = Color(0xFFF43F5E);
  static const Color pinkSoft = Color(0xFFFFF1F2);
  static const Color gold = Color(0xFFF59E0B);
  static const Color goldSoft = Color(0xFFFEF3C7);
  static const Color goldInk = Color(0xFF92400E);
  static const Color muted = Color(0xFF475569);
  static const Color mutedOnDark = Color(0xFF94A3B8);
  static const Color line = Color(0xFFE2E8F0);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerSoft = Color(0xFFFEF2F2);
}

class AdminStudioTheme {
  const AdminStudioTheme._();

  static ThemeData themeData() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AdminStudioColors.violet,
      primary: AdminStudioColors.violet,
      onPrimary: Colors.white,
      secondary: AdminStudioColors.ink,
      onSecondary: Colors.white,
      surface: AdminStudioColors.surface,
      onSurface: AdminStudioColors.ink,
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
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AdminStudioColors.line, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 6,
        shadowColor: const Color(0x1F0F172A),
        backgroundColor: AdminStudioColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AdminStudioColors.line, width: 1),
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
        secondarySelectedColor: AdminStudioColors.violet,
        checkmarkColor: AdminStudioColors.violet,
        disabledColor: AdminStudioColors.paperWarm,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
        ),
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AdminStudioColors.ink,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.1),
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
        labelStyle: const TextStyle(
          color: AdminStudioColors.muted,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AdminStudioColors.violet,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFCBD5E1),
          disabledForegroundColor: AdminStudioColors.muted,
          elevation: 0,
          minimumSize: const Size(44, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AdminStudioColors.violet,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(44, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AdminStudioColors.ink,
          backgroundColor: AdminStudioColors.surface,
          minimumSize: const Size(44, 46),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AdminStudioColors.violet,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AdminStudioColors.ink,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class AdminStudioMark extends StatelessWidget {
  const AdminStudioMark({super.key, this.size = 38, this.inverted = false});

  final double size;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final bg = inverted ? AdminStudioColors.acid : AdminStudioColors.violet;
    final fg = inverted ? AdminStudioColors.ink : Colors.white;
    final stripe = inverted ? AdminStudioColors.pink : AdminStudioColors.acid;
    final tagColor = inverted
        ? AdminStudioColors.ink.withValues(alpha: 0.72)
        : AdminStudioColors.acid;
    final radius = (size * 0.28).clamp(8.0, 14.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: bg,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: (size * 0.13).clamp(4.0, 6.0),
              child: ColoredBox(color: stripe),
            ),
            Align(
              alignment: const Alignment(-0.08, 0.1),
              child: Text(
                'G',
                style: TextStyle(
                  color: fg,
                  fontSize: size * 0.48,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: -0.6,
                ),
              ),
            ),
            Positioned(
              right: size * 0.11,
              top: size * 0.12,
              child: Text(
                'OPS',
                style: TextStyle(
                  color: tagColor,
                  fontSize: (size * 0.155).clamp(5.5, 7.5),
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminStudioGridBackdrop extends StatelessWidget {
  const AdminStudioGridBackdrop({
    super.key,
    required this.child,
    this.backgroundColor = AdminStudioColors.shellDark,
    this.gridSpacing = 48,
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

    final glowCenter = Offset(size.width * 0.78, size.height * 0.14);
    final glowRadius = (size.shortestSide * 0.75).clamp(160.0, 440.0);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AdminStudioColors.violet.withValues(alpha: 0.28),
          AdminStudioColors.violet.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius));
    canvas.drawCircle(glowCenter, glowRadius, glowPaint);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
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
    this.shadowColor = const Color(0x0D0F172A),
    this.borderWidth = 1.0,
    this.borderRadius = 14.0,
    this.shadowOffset = const Offset(0, 4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color backgroundColor;
  final Color borderColor;
  final Color shadowColor;
  final double borderWidth;
  final double borderRadius;
  final Offset shadowOffset;

  @override
  Widget build(BuildContext context) {
    final effectiveBorder = borderColor == AdminStudioColors.ink
        ? AdminStudioColors.line
        : borderColor;
    return Semantics(
      container: true,
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: effectiveBorder, width: borderWidth),
          boxShadow: shadowOffset == Offset.zero
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x0A0F172A),
                    offset: Offset(0, 4),
                    blurRadius: 14,
                  ),
                  BoxShadow(
                    color: Color(0x050F172A),
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Material(
            type: MaterialType.transparency,
            child: padding == EdgeInsets.zero
                ? child
                : Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
