import 'package:flutter/material.dart';

class AdminStudioColors {
  const AdminStudioColors._();

  static const Color paper = Color(0xFFF5F1E8);
  static const Color paperWarm = Color(0xFFEAE5D9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF15131E);
  static const Color shellDark = Color(0xFF171421);
  static const Color shellDeep = Color(0xFF0E1118);
  static const Color shellElevated = Color(0xFF221E30);
  static const Color shellActive = Color(0xFF2F2847);
  static const Color shellLine = Color(0x2EFFFFFF);
  static const Color violet = Color(0xFF5B33E6);
  static const Color violetSoft = Color(0xFFEEE9FF);
  static const Color acid = Color(0xFFCBFF3E);
  static const Color acidSoft = Color(0xFFF2FFCC);
  static const Color acidInk = Color(0xFF2E4400);
  static const Color pink = Color(0xFFFF5E83);
  static const Color pinkSoft = Color(0xFFFFE8EE);
  static const Color gold = Color(0xFFFFD75E);
  static const Color goldSoft = Color(0xFFFFF6D6);
  static const Color goldInk = Color(0xFF6B4800);
  static const Color muted = Color(0xFF5F5A69);
  static const Color mutedOnDark = Color(0xFFA29CB0);
  static const Color line = Color(0x3815131E);
  static const Color danger = Color(0xFFB42318);
  static const Color dangerSoft = Color(0xFFFFECEB);
}

class AdminStudioTheme {
  const AdminStudioTheme._();

  static ThemeData themeData() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AdminStudioColors.violet,
      primary: AdminStudioColors.violet,
      onPrimary: Colors.white,
      secondary: AdminStudioColors.ink,
      onSecondary: AdminStudioColors.acid,
      surface: AdminStudioColors.surface,
      onSurface: AdminStudioColors.ink,
      error: AdminStudioColors.danger,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AdminStudioColors.paper,
      cardTheme: const CardThemeData(
        elevation: 0,
        color: AdminStudioColors.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: AdminStudioColors.ink, width: 1.5),
        ),
      ),
      dialogTheme: const DialogThemeData(
        elevation: 0,
        backgroundColor: AdminStudioColors.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: AdminStudioColors.ink, width: 2),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AdminStudioColors.line,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AdminStudioColors.surface,
        selectedColor: AdminStudioColors.acid,
        disabledColor: AdminStudioColors.paperWarm,
        side: const BorderSide(color: AdminStudioColors.ink, width: 1.2),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        labelStyle: const TextStyle(
          color: AdminStudioColors.ink,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AdminStudioColors.ink, width: 1.4),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AdminStudioColors.ink;
            }
            return AdminStudioColors.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AdminStudioColors.acid;
            }
            return AdminStudioColors.ink;
          }),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AdminStudioColors.surface,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AdminStudioColors.ink, width: 1.4),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AdminStudioColors.ink, width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AdminStudioColors.line, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AdminStudioColors.violet, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AdminStudioColors.danger, width: 1.6),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AdminStudioColors.danger, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AdminStudioColors.ink,
          foregroundColor: AdminStudioColors.acid,
          disabledBackgroundColor: const Color(0xFFD7D2C6),
          disabledForegroundColor: AdminStudioColors.muted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            letterSpacing: 0.2,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: AdminStudioColors.ink, width: 1.4),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: AdminStudioColors.surface,
          foregroundColor: AdminStudioColors.ink,
          disabledForegroundColor: AdminStudioColors.muted,
          side: const BorderSide(color: AdminStudioColors.ink, width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AdminStudioColors.ink,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
    final bg = onDark ? AdminStudioColors.acid : AdminStudioColors.ink;
    final fg = onDark ? AdminStudioColors.ink : Colors.white;
    final stripe = onDark ? AdminStudioColors.pink : AdminStudioColors.acid;
    final tagColor = onDark ? AdminStudioColors.violet : AdminStudioColors.acid;
    return ClipPath(
      clipper: const _ChamferStudioClipper(),
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
              alignment: const Alignment(-0.1, 0.1),
              child: Text(
                'G',
                style: TextStyle(
                  color: fg,
                  fontSize: size * 0.48,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: -0.8,
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

class _ChamferStudioClipper extends CustomClipper<Path> {
  const _ChamferStudioClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height * 0.72)
    ..lineTo(size.width * 0.72, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
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
          AdminStudioColors.violet.withValues(alpha: 0.34),
          AdminStudioColors.violet.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius));
    canvas.drawCircle(glowCenter, glowRadius, glowPaint);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
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
    this.borderColor = AdminStudioColors.ink,
    this.shadowColor = AdminStudioColors.ink,
    this.borderWidth = 1.5,
    this.shadowOffset = const Offset(3, 3),
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
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: shadowOffset == Offset.zero
            ? null
            : [
                BoxShadow(
                  color: shadowColor,
                  offset: shadowOffset,
                  blurRadius: 0,
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
