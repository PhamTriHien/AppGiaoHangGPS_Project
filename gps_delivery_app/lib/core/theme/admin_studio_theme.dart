import 'package:flutter/material.dart';

class AdminStudioColors {
  const AdminStudioColors._();

  static const Color paper = Color(0xFFF4F7FA);
  static const Color paperWarm = Color(0xFFEFF3F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF0F172A);
  static const Color shellDark = Color(0xFF0F172A);
  static const Color shellDeep = Color(0xFF090E1A);
  static const Color shellElevated = Color(0xFF1E293B);
  static const Color shellActive = Color(0xFF1E3A8A);
  static const Color shellLine = Color(0x26CBD5E1);
  static const Color violet = Color(0xFF2563EB);
  static const Color violetSoft = Color(0xFFEFF6FF);
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
        elevation: 4,
        backgroundColor: AdminStudioColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
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
        selectedColor: const Color(0xFFDBEAFE),
        checkmarkColor: AdminStudioColors.violet,
        disabledColor: AdminStudioColors.paperWarm,
        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: Color(0xFFCBD5E1), width: 1),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AdminStudioColors.violet;
            }
            return AdminStudioColors.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return AdminStudioColors.ink;
          }),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AdminStudioColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AdminStudioColors.line,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AdminStudioColors.violet,
            width: 1.8,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AdminStudioColors.danger,
            width: 1.4,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
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
          disabledBackgroundColor: const Color(0xFFE2E8F0),
          disabledForegroundColor: AdminStudioColors.muted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: AdminStudioColors.surface,
          foregroundColor: AdminStudioColors.ink,
          disabledForegroundColor: AdminStudioColors.muted,
          side: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AdminStudioColors.violet,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    final bg = onDark ? AdminStudioColors.violet : AdminStudioColors.ink;
    const fg = Colors.white;
    final tagColor = AdminStudioColors.acid;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(-0.08, 0.12),
            child: Text(
              'G',
              style: TextStyle(
                color: fg,
                fontSize: size * 0.48,
                fontWeight: FontWeight.w900,
                height: 1,
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
    this.shadowColor = const Color(0x120F172A),
    this.borderWidth = 1.0,
    this.shadowOffset = const Offset(0, 4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color backgroundColor;
  final Color borderColor;
  final Color shadowColor;
  final double borderWidth;
  final Offset shadowOffset;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: Container(
      margin: margin,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor == AdminStudioColors.ink
              ? const Color(0xFFCBD5E1)
              : borderColor,
          width: borderWidth > 1.2 ? 1.0 : borderWidth,
        ),
        boxShadow: shadowOffset == Offset.zero
            ? null
            : [
                BoxShadow(
                  color: shadowColor == AdminStudioColors.ink
                      ? const Color(0x100F172A)
                      : shadowColor.withValues(
                          alpha: shadowColor.a > 0.3 ? 0.14 : shadowColor.a,
                        ),
                  offset: const Offset(0, 4),
                  blurRadius: 14,
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
