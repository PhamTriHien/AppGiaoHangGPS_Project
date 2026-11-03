import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../presentation/widgets/motion_3d_effects.dart';
import 'ghst_theme_tokens.dart';

class AdminStudioColors {
  const AdminStudioColors._();

  static const Color paper = Color(0xFFEEF3FA);
  static const Color paperWarm = Color(0xFFE7EFFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFF6F9FE);
  static const Color ink = Color(0xFF0B1324);
  static const Color onAccentInk = Color(0xFF090E1A);
  static const Color shellDark = Color(0xFF0B1324);
  static const Color shellDeep = Color(0xFF060B16);
  static const Color shellElevated = Color(0xFF16233B);
  static const Color shellActive = Color(0xFF1E3A8A);
  static const Color shellLine = Color(0x29CBD5E1);
  static const Color violet = Color(0xFF2563EB);
  static const Color violetSoft = Color(0xFFEAF2FF);
  static const Color violetInk = Color(0xFF1E40AF);
  static const Color acid = Color(0xFF6EE7B7);
  static const Color acidSoft = Color(0xFFE8FBF3);
  static const Color acidInk = Color(0xFF065F46);
  static const Color pink = Color(0xFFF43F5E);
  static const Color pinkSoft = Color(0xFFFFF0F3);
  static const Color gold = Color(0xFFF59E0B);
  static const Color goldSoft = Color(0xFFFFF7E6);
  static const Color goldInk = Color(0xFF92400E);
  static const Color muted = Color(0xFF3E4E68);
  static const Color mutedOnDark = Color(0xFF94A3B8);
  static const Color line = Color(0xFFD8E2F0);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerSoft = Color(0xFFFEF2F2);
}

@immutable
class AdminStudioPalette {
  const AdminStudioPalette({
    required this.isDark,
    required this.paper,
    required this.paperWarm,
    required this.surface,
    required this.surfaceSubtle,
    required this.ink,
    required this.onAccentInk,
    required this.muted,
    required this.line,
    required this.controlBorder,
    required this.violet,
    required this.violetSoft,
    required this.violetInk,
    required this.acid,
    required this.acidSoft,
    required this.acidInk,
    required this.pink,
    required this.pinkSoft,
    required this.pinkInk,
    required this.gold,
    required this.goldSoft,
    required this.goldInk,
    required this.danger,
    required this.dangerSoft,
    required this.dangerInk,
  });

  final bool isDark;
  final Color paper;
  final Color paperWarm;
  final Color surface;
  final Color surfaceSubtle;
  final Color ink;
  final Color onAccentInk;
  final Color muted;
  final Color line;
  final Color controlBorder;
  final Color violet;
  final Color violetSoft;
  final Color violetInk;
  final Color acid;
  final Color acidSoft;
  final Color acidInk;
  final Color pink;
  final Color pinkSoft;
  final Color pinkInk;
  final Color gold;
  final Color goldSoft;
  final Color goldInk;
  final Color danger;
  final Color dangerSoft;
  final Color dangerInk;

  static const AdminStudioPalette light = AdminStudioPalette(
    isDark: false,
    paper: AdminStudioColors.paper,
    paperWarm: AdminStudioColors.paperWarm,
    surface: AdminStudioColors.surface,
    surfaceSubtle: AdminStudioColors.surfaceSubtle,
    ink: AdminStudioColors.ink,
    onAccentInk: AdminStudioColors.onAccentInk,
    muted: AdminStudioColors.muted,
    line: AdminStudioColors.line,
    controlBorder: Color(0xFFC4D2E6),
    violet: AdminStudioColors.violet,
    violetSoft: AdminStudioColors.violetSoft,
    violetInk: AdminStudioColors.violetInk,
    acid: AdminStudioColors.acid,
    acidSoft: AdminStudioColors.acidSoft,
    acidInk: AdminStudioColors.acidInk,
    pink: AdminStudioColors.pink,
    pinkSoft: AdminStudioColors.pinkSoft,
    pinkInk: Color(0xFF9F1239),
    gold: AdminStudioColors.gold,
    goldSoft: AdminStudioColors.goldSoft,
    goldInk: AdminStudioColors.goldInk,
    danger: AdminStudioColors.danger,
    dangerSoft: AdminStudioColors.dangerSoft,
    dangerInk: Color(0xFF991B1B),
  );

  static const AdminStudioPalette dark = AdminStudioPalette(
    isDark: true,
    paper: Color(0xFF070D19),
    paperWarm: Color(0xFF0D1526),
    surface: Color(0xFF111C30),
    surfaceSubtle: Color(0xFF16233B),
    ink: Color(0xFFF1F5FB),
    onAccentInk: Color(0xFF090E1A),
    muted: Color(0xFFB4C3D9),
    line: Color(0xFF22324F),
    controlBorder: Color(0xFF31476E),
    violet: Color(0xFF3B82F6),
    violetSoft: Color(0x293B82F6),
    violetInk: Color(0xFF93C5FD),
    acid: Color(0xFF6EE7B7),
    acidSoft: Color(0x2610B981),
    acidInk: Color(0xFF6EE7B7),
    pink: Color(0xFFFB7185),
    pinkSoft: Color(0x26F43F5E),
    pinkInk: Color(0xFFFDA4AF),
    gold: Color(0xFFFBBF24),
    goldSoft: Color(0x26F59E0B),
    goldInk: Color(0xFFFCD34D),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0x26EF4444),
    dangerInk: Color(0xFFFCA5A5),
  );

  static AdminStudioPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

class AdminStudioTheme {
  const AdminStudioTheme._();

  static ThemeData of(BuildContext context) =>
      themeData(brightness: Theme.of(context).brightness);

  static ThemeData themeData({Brightness brightness = Brightness.light}) {
    final isDark = brightness == Brightness.dark;
    final p = isDark ? AdminStudioPalette.dark : AdminStudioPalette.light;
    final tokens = isDark ? GhstThemeTokens.dark : GhstThemeTokens.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: p.violet,
      brightness: brightness,
      primary: p.violet,
      onPrimary: Colors.white,
      secondary: isDark ? p.acid : p.ink,
      onSecondary: isDark ? p.onAccentInk : Colors.white,
      surface: p.surface,
      onSurface: p.ink,
      error: p.danger,
    ).copyWith(
      onSurfaceVariant: p.muted,
      surfaceContainerLowest: p.paper,
      surfaceContainerLow: p.surfaceSubtle,
      surfaceContainer: p.surface,
      surfaceContainerHigh: tokens.cardMuted,
      surfaceContainerHighest: isDark
          ? const Color(0xFF243757)
          : const Color(0xFFE3ECF8),
      primaryContainer: p.violetSoft,
      onPrimaryContainer: p.violetInk,
      secondaryContainer: p.acidSoft,
      onSecondaryContainer: p.acidInk,
      tertiaryContainer: p.goldSoft,
      onTertiaryContainer: p.goldInk,
      errorContainer: p.dangerSoft,
      onErrorContainer: p.dangerInk,
      outline: p.controlBorder,
      outlineVariant: p.line,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.paper,
      extensions: [tokens],
      cardTheme: CardThemeData(
        elevation: 0,
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.line, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 8,
        shadowColor: isDark ? const Color(0x88000000) : const Color(0x1F0F172A),
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.line, width: 1),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: p.line,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceSubtle,
        selectedColor: p.violetSoft,
        secondarySelectedColor: p.violet,
        checkmarkColor: p.violetInk,
        disabledColor: p.paperWarm,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: p.controlBorder, width: 1),
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: p.ink,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceSubtle,
        hintStyle: TextStyle(color: tokens.inkMuted, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.controlBorder, width: 1.1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.controlBorder, width: 1.1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: p.violet,
            width: 1.8,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: p.danger,
            width: 1.4,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: p.danger,
            width: 1.8,
          ),
        ),
        labelStyle: TextStyle(
          color: p.muted,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.violet,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.controlBorder,
          disabledForegroundColor: p.muted,
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
          backgroundColor: p.violet,
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
          foregroundColor: p.ink,
          backgroundColor: p.surface,
          minimumSize: const Size(44, 46),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: BorderSide(color: p.controlBorder, width: 1),
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
          foregroundColor: p.violet,
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
        backgroundColor: isDark ? const Color(0xFF1E293B) : p.ink,
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
    final fg = inverted ? AdminStudioColors.onAccentInk : Colors.white;
    final stripe = inverted ? AdminStudioColors.pink : AdminStudioColors.acid;
    final tagColor = inverted
        ? AdminStudioColors.onAccentInk.withValues(alpha: 0.72)
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

class AdminStudioGridBackdrop extends StatefulWidget {
  const AdminStudioGridBackdrop({
    super.key,
    required this.child,
    this.backgroundColor = AdminStudioColors.shellDark,
    this.gridSpacing = 48,
    this.enable3dHorizon = false,
  });

  final Widget child;
  final Color backgroundColor;
  final double gridSpacing;
  final bool enable3dHorizon;

  @override
  State<AdminStudioGridBackdrop> createState() =>
      _AdminStudioGridBackdropState();
}

class _AdminStudioGridBackdropState extends State<AdminStudioGridBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
    value: 0.25,
  )..addListener(_smoothParallax);
  final ValueNotifier<Offset> _parallax = ValueNotifier<Offset>(Offset.zero);
  Offset _targetParallax = Offset.zero;
  late final Listenable _merged = Listenable.merge([_controller, _parallax]);

  void _smoothParallax() {
    final current = _parallax.value;
    final delta = _targetParallax - current;
    if (delta.distanceSquared > 0.000004) {
      _parallax.value = Offset(
        current.dx + delta.dx * 0.11,
        current.dy + delta.dy * 0.11,
      );
    } else if (current != _targetParallax) {
      _parallax.value = _targetParallax;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant AdminStudioGridBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.enable3dHorizon && Motion3dEnvironment.shouldAnimate(context)) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_smoothParallax);
    _controller.dispose();
    _parallax.dispose();
    super.dispose();
  }

  void _onHover(Offset local, Size size) {
    if (!widget.enable3dHorizon || size.isEmpty) return;
    final next = Offset(
      ((local.dx / size.width) * 2.0 - 1.0).clamp(-1.0, 1.0),
      ((local.dy / size.height) * 2.0 - 1.0).clamp(-1.0, 1.0),
    );
    _targetParallax = next;
    if (!_controller.isAnimating && (next - _parallax.value).distance > 0.005) {
      _parallax.value = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enable3dHorizon) {
      return CustomPaint(
        painter: _StudioGridPainter(
          backgroundColor: widget.backgroundColor,
          gridSpacing: widget.gridSpacing,
          phase: 0.25,
          parallax: Offset.zero,
          drawHorizon: false,
        ),
        child: widget.child,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => MouseRegion(
        onHover: (e) => _onHover(e.localPosition, constraints.biggest),
        onExit: (_) {
          _targetParallax = Offset.zero;
          if (!_controller.isAnimating) {
            _parallax.value = Offset.zero;
          }
        },
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _merged,
                    builder: (_, _) => CustomPaint(
                      painter: _StudioGridPainter(
                        backgroundColor: widget.backgroundColor,
                        gridSpacing: widget.gridSpacing,
                        phase: _controller.value,
                        parallax: _parallax.value,
                        drawHorizon: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

class _StudioGridPainter extends CustomPainter {
  const _StudioGridPainter({
    required this.backgroundColor,
    required this.gridSpacing,
    required this.phase,
    required this.parallax,
    required this.drawHorizon,
  });

  final Color backgroundColor;
  final double gridSpacing;
  final double phase;
  final Offset parallax;
  final bool drawHorizon;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = backgroundColor);

    final glowCenter = Offset(
      size.width * (0.78 + parallax.dx * 0.06),
      size.height * (0.14 + parallax.dy * 0.06),
    );
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

    if (!drawHorizon) return;

    final mintGlowCenter = Offset(
      size.width * (0.24 - parallax.dx * 0.05),
      size.height * (0.82 - parallax.dy * 0.04),
    );
    final mintGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AdminStudioColors.acid.withValues(alpha: 0.16),
          AdminStudioColors.acid.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: mintGlowCenter, radius: glowRadius * 0.75),
      );
    canvas.drawCircle(mintGlowCenter, glowRadius * 0.75, mintGlowPaint);

    final horizonY = size.height * (0.64 + parallax.dy * 0.025);
    final vanishX = size.width * (0.50 + parallax.dx * 0.06);
    final perspectiveLinePaint = Paint()
      ..isAntiAlias = true
      ..color = AdminStudioColors.acid.withValues(alpha: 0.10)
      ..strokeWidth = 1.0;

    for (int i = -6; i <= 6; i++) {
      final bottomX = vanishX + i * (size.width * 0.15);
      canvas.drawLine(
        Offset(vanishX, horizonY),
        Offset(bottomX, size.height),
        perspectiveLinePaint,
      );
    }

    final beltOffset = phase % 1.0;
    for (int r = 0; r < 6; r++) {
      final t = ((r + beltOffset) / 6.0).clamp(0.0, 1.0);
      final depthT = t * t;
      final y = horizonY + (size.height - horizonY) * depthT;
      final rowPaint = Paint()
        ..isAntiAlias = true
        ..color = AdminStudioColors.violet.withValues(
          alpha: (0.04 + 0.15 * depthT).clamp(0.0, 0.24),
        )
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rowPaint);
    }

    final orbitCenter = Offset(
      size.width * (0.76 + parallax.dx * 0.04),
      size.height * (0.24 + parallax.dy * 0.03),
    );
    final orbitRx = (size.shortestSide * 0.22).clamp(54.0, 118.0);
    final orbitRy = orbitRx * 0.42;
    final orbitRect = Rect.fromCenter(
      center: orbitCenter,
      width: orbitRx * 2,
      height: orbitRy * 2,
    );
    canvas.drawOval(
      orbitRect,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = AdminStudioColors.acid.withValues(alpha: 0.22),
    );
    final sweepAngle = phase * math.pi * 2.0;
    final satPos = Offset(
      orbitCenter.dx + math.cos(sweepAngle) * orbitRx,
      orbitCenter.dy + math.sin(sweepAngle) * orbitRy,
    );
    canvas.drawCircle(
      satPos,
      4.0,
      Paint()
        ..isAntiAlias = true
        ..color = AdminStudioColors.acid.withValues(alpha: 0.88),
    );
    canvas.drawCircle(
      satPos,
      10.0,
      Paint()
        ..isAntiAlias = true
        ..color = AdminStudioColors.acid.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(covariant _StudioGridPainter oldDelegate) =>
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.gridSpacing != gridSpacing ||
      oldDelegate.phase != phase ||
      oldDelegate.parallax != parallax ||
      oldDelegate.drawHorizon != drawHorizon;
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
    this.interactive3d = false,
    this.maxTilt = 0.035,
    this.enablePressScale = false,
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
  final bool interactive3d;
  final double maxTilt;
  final bool enablePressScale;

  @override
  Widget build(BuildContext context) {
    final palette = AdminStudioPalette.of(context);
    final tokens = GhstThemeTokens.of(context);
    final effectiveBg = switch (backgroundColor) {
      AdminStudioColors.surface || const Color(0xFFFFFFFF) => palette.surface,
      AdminStudioColors.surfaceSubtle ||
      const Color(0xFFF8FAFC) => palette.surfaceSubtle,
      AdminStudioColors.paper || const Color(0xFFF4F7FA) => palette.paper,
      AdminStudioColors.paperWarm ||
      const Color(0xFFEFF3F8) => palette.paperWarm,
      AdminStudioColors.violetSoft ||
      const Color(0xFFEFF6FF) => palette.violetSoft,
      AdminStudioColors.acidSoft || const Color(0xFFECFDF5) => palette.acidSoft,
      AdminStudioColors.goldSoft || const Color(0xFFFEF3C7) => palette.goldSoft,
      AdminStudioColors.pinkSoft || const Color(0xFFFFF1F2) => palette.pinkSoft,
      AdminStudioColors.dangerSoft ||
      const Color(0xFFFEF2F2) => palette.dangerSoft,
      _ => backgroundColor,
    };
    final effectiveBorder = switch (borderColor) {
      AdminStudioColors.ink ||
      const Color(0xFF0F172A) ||
      AdminStudioColors.line ||
      const Color(0xFFE2E8F0) => palette.line,
      const Color(0xFFCBD5E1) => palette.controlBorder,
      _ => borderColor,
    };
    final radius = BorderRadius.circular(borderRadius);
    final Widget innerContent = Material(
      type: MaterialType.transparency,
      child: padding == EdgeInsets.zero
          ? child
          : Padding(padding: padding, child: child),
    );
    Widget box = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: radius,
        border: Border.all(color: effectiveBorder, width: borderWidth),
        boxShadow: shadowOffset == Offset.zero ? null : tokens.cardShadow,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tokens.specularRim,
            tokens.specularRim.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.14],
        ),
      ),
      child: interactive3d
          ? innerContent
          : ClipRRect(borderRadius: radius, child: innerContent),
    );
    if (interactive3d) {
      box = Motion3dInteractiveSurface(
        borderRadius: radius,
        maxTilt: maxTilt,
        enablePressScale: enablePressScale,
        child: box,
      );
    }
    return Semantics(container: true, child: box);
  }
}
