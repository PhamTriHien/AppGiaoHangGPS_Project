import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../presentation/widgets/motion_3d_effects.dart';

@immutable
class TonePair {
  const TonePair({
    required this.fill,
    required this.border,
    required this.foreground,
    required this.icon,
    required this.glow,
  });

  final Color fill;
  final Color border;
  final Color foreground;
  final Color icon;
  final Color glow;

  static TonePair lerp(TonePair a, TonePair b, double t) => TonePair(
    fill: Color.lerp(a.fill, b.fill, t)!,
    border: Color.lerp(a.border, b.border, t)!,
    foreground: Color.lerp(a.foreground, b.foreground, t)!,
    icon: Color.lerp(a.icon, b.icon, t)!,
    glow: Color.lerp(a.glow, b.glow, t)!,
  );
}

@immutable
class GhstThemeTokens extends ThemeExtension<GhstThemeTokens> {
  const GhstThemeTokens({
    required this.isDark,
    required this.canvas,
    required this.canvasElevated,
    required this.cardSurface,
    required this.cardSubtle,
    required this.cardMuted,
    required this.ink,
    required this.inkSecondary,
    required this.inkMuted,
    required this.border,
    required this.borderStrong,
    required this.specularRim,
    required this.shellBg,
    required this.shellElevated,
    required this.shellBorder,
    required this.primary,
    required this.onAccentInk,
    required this.heroGradient,
    required this.driverGradient,
    required this.merchantGradient,
    required this.promoGradient,
    required this.aiGradient,
    required this.emeraldGradient,
    required this.sapphire,
    required this.emerald,
    required this.amber,
    required this.rose,
    required this.violet,
    required this.cyan,
    required this.neutral,
    required this.cardShadow,
    required this.elevatedShadow,
  });

  final bool isDark;
  final Color canvas;
  final Color canvasElevated;
  final Color cardSurface;
  final Color cardSubtle;
  final Color cardMuted;
  final Color ink;
  final Color inkSecondary;
  final Color inkMuted;
  final Color border;
  final Color borderStrong;
  final Color specularRim;
  final Color shellBg;
  final Color shellElevated;
  final Color shellBorder;
  final Color primary;
  final Color onAccentInk;
  final LinearGradient heroGradient;
  final LinearGradient driverGradient;
  final LinearGradient merchantGradient;
  final LinearGradient promoGradient;
  final LinearGradient aiGradient;
  final LinearGradient emeraldGradient;
  final TonePair sapphire;
  final TonePair emerald;
  final TonePair amber;
  final TonePair rose;
  final TonePair violet;
  final TonePair cyan;
  final TonePair neutral;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> elevatedShadow;

  static const GhstThemeTokens light = GhstThemeTokens(
    isDark: false,
    canvas: Color(0xFFEEF3FA),
    canvasElevated: Color(0xFFF5F8FD),
    cardSurface: Color(0xFFFFFFFF),
    cardSubtle: Color(0xFFF6F9FE),
    cardMuted: Color(0xFFEDF2FA),
    ink: Color(0xFF0B1324),
    inkSecondary: Color(0xFF3E4E68),
    inkMuted: Color(0xFF5B6B86),
    border: Color(0xFFD8E2F0),
    borderStrong: Color(0xFFBFCFDF),
    specularRim: Color(0xCCFFFFFF),
    shellBg: Color(0xFF0B1324),
    shellElevated: Color(0xFF16233B),
    shellBorder: Color(0x29CBD5E1),
    primary: Color(0xFF2563EB),
    onAccentInk: Color(0xFF090E1A),
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0B1938), Color(0xFF14326E), Color(0xFF2563EB)],
      stops: [0.0, 0.55, 1.0],
    ),
    driverGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF071C24), Color(0xFF0B3B3C), Color(0xFF059669)],
      stops: [0.0, 0.56, 1.0],
    ),
    merchantGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF131638), Color(0xFF292669), Color(0xFF4F46E5)],
      stops: [0.0, 0.56, 1.0],
    ),
    promoGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF9F1239), Color(0xFFE11D48), Color(0xFFD97706)],
      stops: [0.0, 0.58, 1.0],
    ),
    aiGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1E1B4B), Color(0xFF1D4ED8), Color(0xFF0891B2)],
      stops: [0.0, 0.54, 1.0],
    ),
    emeraldGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF065F46), Color(0xFF059669), Color(0xFF10B981)],
      stops: [0.0, 0.55, 1.0],
    ),
    sapphire: TonePair(
      fill: Color(0xFFEAF2FF),
      border: Color(0xFFBFDBFE),
      foreground: Color(0xFF1E40AF),
      icon: Color(0xFF2563EB),
      glow: Color(0x282563EB),
    ),
    emerald: TonePair(
      fill: Color(0xFFE8FBF3),
      border: Color(0xFFA7F3D0),
      foreground: Color(0xFF065F46),
      icon: Color(0xFF059669),
      glow: Color(0x2610B981),
    ),
    amber: TonePair(
      fill: Color(0xFFFFF7E6),
      border: Color(0xFFFDE68A),
      foreground: Color(0xFF92400E),
      icon: Color(0xFFD97706),
      glow: Color(0x26F59E0B),
    ),
    rose: TonePair(
      fill: Color(0xFFFFF0F3),
      border: Color(0xFFFECDD3),
      foreground: Color(0xFF9F1239),
      icon: Color(0xFFE11D48),
      glow: Color(0x24F43F5E),
    ),
    violet: TonePair(
      fill: Color(0xFFEEF0FF),
      border: Color(0xFFC7D2FE),
      foreground: Color(0xFF3730A3),
      icon: Color(0xFF4F46E5),
      glow: Color(0x244F46E5),
    ),
    cyan: TonePair(
      fill: Color(0xFFE8FAFE),
      border: Color(0xFFA5F3FC),
      foreground: Color(0xFF155E75),
      icon: Color(0xFF0891B2),
      glow: Color(0x2406B6D4),
    ),
    neutral: TonePair(
      fill: Color(0xFFF1F5FB),
      border: Color(0xFFD8E2F0),
      foreground: Color(0xFF334155),
      icon: Color(0xFF475569),
      glow: Color(0x140F172A),
    ),
    cardShadow: [
      BoxShadow(
        color: Color(0x0E0F172A),
        blurRadius: 18,
        offset: Offset(0, 6),
      ),
      BoxShadow(
        color: Color(0x062563EB),
        blurRadius: 6,
        offset: Offset(0, 1),
      ),
    ],
    elevatedShadow: [
      BoxShadow(
        color: Color(0x1A0F172A),
        blurRadius: 30,
        offset: Offset(0, 12),
      ),
      BoxShadow(
        color: Color(0x0C2563EB),
        blurRadius: 10,
        offset: Offset(0, 3),
      ),
    ],
  );

  static const GhstThemeTokens dark = GhstThemeTokens(
    isDark: true,
    canvas: Color(0xFF070D19),
    canvasElevated: Color(0xFF0D1526),
    cardSurface: Color(0xFF111C30),
    cardSubtle: Color(0xFF16233B),
    cardMuted: Color(0xFF1D2D49),
    ink: Color(0xFFF1F5FB),
    inkSecondary: Color(0xFFB4C3D9),
    inkMuted: Color(0xFF8CA0BE),
    border: Color(0xFF22324F),
    borderStrong: Color(0xFF31476E),
    specularRim: Color(0x2693C5FD),
    shellBg: Color(0xFF050A14),
    shellElevated: Color(0xFF0E182B),
    shellBorder: Color(0x33475569),
    primary: Color(0xFF3B82F6),
    onAccentInk: Color(0xFF090E1A),
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF09152E), Color(0xFF132B5E), Color(0xFF1D4ED8)],
      stops: [0.0, 0.56, 1.0],
    ),
    driverGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF061A23), Color(0xFF0A3638), Color(0xFF047857)],
      stops: [0.0, 0.56, 1.0],
    ),
    merchantGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF121336), Color(0xFF25225C), Color(0xFF4338CA)],
      stops: [0.0, 0.56, 1.0],
    ),
    promoGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF4C0519), Color(0xFF9F1239), Color(0xFFB45309)],
      stops: [0.0, 0.58, 1.0],
    ),
    aiGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF17153B), Color(0xFF1E3A8A), Color(0xFF0E7490)],
      stops: [0.0, 0.54, 1.0],
    ),
    emeraldGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF064E3B), Color(0xFF047857), Color(0xFF059669)],
      stops: [0.0, 0.55, 1.0],
    ),
    sapphire: TonePair(
      fill: Color(0x293B82F6),
      border: Color(0x5960A5FA),
      foreground: Color(0xFF93C5FD),
      icon: Color(0xFF60A5FA),
      glow: Color(0x383B82F6),
    ),
    emerald: TonePair(
      fill: Color(0x2610B981),
      border: Color(0x5234D399),
      foreground: Color(0xFF6EE7B7),
      icon: Color(0xFF34D399),
      glow: Color(0x3310B981),
    ),
    amber: TonePair(
      fill: Color(0x26F59E0B),
      border: Color(0x52FBBF24),
      foreground: Color(0xFFFCD34D),
      icon: Color(0xFFFBBF24),
      glow: Color(0x33F59E0B),
    ),
    rose: TonePair(
      fill: Color(0x26F43F5E),
      border: Color(0x52FB7185),
      foreground: Color(0xFFFDA4AF),
      icon: Color(0xFFFB7185),
      glow: Color(0x33F43F5E),
    ),
    violet: TonePair(
      fill: Color(0x298B5CF6),
      border: Color(0x52A78BFA),
      foreground: Color(0xFFC4B5FD),
      icon: Color(0xFFA78BFA),
      glow: Color(0x338B5CF6),
    ),
    cyan: TonePair(
      fill: Color(0x2606B6D4),
      border: Color(0x5222D3EE),
      foreground: Color(0xFF67E8F9),
      icon: Color(0xFF22D3EE),
      glow: Color(0x3306B6D4),
    ),
    neutral: TonePair(
      fill: Color(0xFF18253E),
      border: Color(0xFF2A3D61),
      foreground: Color(0xFFD8E3F2),
      icon: Color(0xFF94A8C7),
      glow: Color(0x29000000),
    ),
    cardShadow: [
      BoxShadow(
        color: Color(0x52020617),
        blurRadius: 20,
        offset: Offset(0, 8),
      ),
      BoxShadow(
        color: Color(0x143B82F6),
        blurRadius: 8,
        offset: Offset(0, 1),
      ),
    ],
    elevatedShadow: [
      BoxShadow(
        color: Color(0x6E020617),
        blurRadius: 32,
        offset: Offset(0, 14),
      ),
      BoxShadow(
        color: Color(0x223B82F6),
        blurRadius: 12,
        offset: Offset(0, 2),
      ),
    ],
  );

  static GhstThemeTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<GhstThemeTokens>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  GhstThemeTokens copyWith({
    bool? isDark,
    Color? canvas,
    Color? canvasElevated,
    Color? cardSurface,
    Color? cardSubtle,
    Color? cardMuted,
    Color? ink,
    Color? inkSecondary,
    Color? inkMuted,
    Color? border,
    Color? borderStrong,
    Color? specularRim,
    Color? shellBg,
    Color? shellElevated,
    Color? shellBorder,
    Color? primary,
    Color? onAccentInk,
    LinearGradient? heroGradient,
    LinearGradient? driverGradient,
    LinearGradient? merchantGradient,
    LinearGradient? promoGradient,
    LinearGradient? aiGradient,
    LinearGradient? emeraldGradient,
    TonePair? sapphire,
    TonePair? emerald,
    TonePair? amber,
    TonePair? rose,
    TonePair? violet,
    TonePair? cyan,
    TonePair? neutral,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? elevatedShadow,
  }) {
    return GhstThemeTokens(
      isDark: isDark ?? this.isDark,
      canvas: canvas ?? this.canvas,
      canvasElevated: canvasElevated ?? this.canvasElevated,
      cardSurface: cardSurface ?? this.cardSurface,
      cardSubtle: cardSubtle ?? this.cardSubtle,
      cardMuted: cardMuted ?? this.cardMuted,
      ink: ink ?? this.ink,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkMuted: inkMuted ?? this.inkMuted,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      specularRim: specularRim ?? this.specularRim,
      shellBg: shellBg ?? this.shellBg,
      shellElevated: shellElevated ?? this.shellElevated,
      shellBorder: shellBorder ?? this.shellBorder,
      primary: primary ?? this.primary,
      onAccentInk: onAccentInk ?? this.onAccentInk,
      heroGradient: heroGradient ?? this.heroGradient,
      driverGradient: driverGradient ?? this.driverGradient,
      merchantGradient: merchantGradient ?? this.merchantGradient,
      promoGradient: promoGradient ?? this.promoGradient,
      aiGradient: aiGradient ?? this.aiGradient,
      emeraldGradient: emeraldGradient ?? this.emeraldGradient,
      sapphire: sapphire ?? this.sapphire,
      emerald: emerald ?? this.emerald,
      amber: amber ?? this.amber,
      rose: rose ?? this.rose,
      violet: violet ?? this.violet,
      cyan: cyan ?? this.cyan,
      neutral: neutral ?? this.neutral,
      cardShadow: cardShadow ?? this.cardShadow,
      elevatedShadow: elevatedShadow ?? this.elevatedShadow,
    );
  }

  @override
  GhstThemeTokens lerp(ThemeExtension<GhstThemeTokens>? other, double t) {
    if (other is! GhstThemeTokens) return this;
    return GhstThemeTokens(
      isDark: t < 0.5 ? isDark : other.isDark,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      canvasElevated: Color.lerp(canvasElevated, other.canvasElevated, t)!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
      cardSubtle: Color.lerp(cardSubtle, other.cardSubtle, t)!,
      cardMuted: Color.lerp(cardMuted, other.cardMuted, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSecondary: Color.lerp(inkSecondary, other.inkSecondary, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      specularRim: Color.lerp(specularRim, other.specularRim, t)!,
      shellBg: Color.lerp(shellBg, other.shellBg, t)!,
      shellElevated: Color.lerp(shellElevated, other.shellElevated, t)!,
      shellBorder: Color.lerp(shellBorder, other.shellBorder, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onAccentInk: Color.lerp(onAccentInk, other.onAccentInk, t)!,
      heroGradient: LinearGradient.lerp(heroGradient, other.heroGradient, t)!,
      driverGradient: LinearGradient.lerp(
        driverGradient,
        other.driverGradient,
        t,
      )!,
      merchantGradient: LinearGradient.lerp(
        merchantGradient,
        other.merchantGradient,
        t,
      )!,
      promoGradient: LinearGradient.lerp(
        promoGradient,
        other.promoGradient,
        t,
      )!,
      aiGradient: LinearGradient.lerp(aiGradient, other.aiGradient, t)!,
      emeraldGradient: LinearGradient.lerp(
        emeraldGradient,
        other.emeraldGradient,
        t,
      )!,
      sapphire: TonePair.lerp(sapphire, other.sapphire, t),
      emerald: TonePair.lerp(emerald, other.emerald, t),
      amber: TonePair.lerp(amber, other.amber, t),
      rose: TonePair.lerp(rose, other.rose, t),
      violet: TonePair.lerp(violet, other.violet, t),
      cyan: TonePair.lerp(cyan, other.cyan, t),
      neutral: TonePair.lerp(neutral, other.neutral, t),
      cardShadow: _lerpShadows(cardShadow, other.cardShadow, t),
      elevatedShadow: _lerpShadows(elevatedShadow, other.elevatedShadow, t),
    );
  }

  static List<BoxShadow> _lerpShadows(
    List<BoxShadow> a,
    List<BoxShadow> b,
    double t,
  ) {
    final len = a.length < b.length ? a.length : b.length;
    return [
      for (var i = 0; i < len; i++)
        BoxShadow(
          color: Color.lerp(a[i].color, b[i].color, t)!,
          blurRadius: lerpDouble(a[i].blurRadius, b[i].blurRadius, t)!,
          spreadRadius: lerpDouble(a[i].spreadRadius, b[i].spreadRadius, t)!,
          offset: Offset.lerp(a[i].offset, b[i].offset, t)!,
        ),
    ];
  }
}

class GhstLuminousCard extends StatelessWidget {
  const GhstLuminousCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.borderRadius = 16,
    this.accentGlow,
    this.borderColor,
    this.backgroundColor,
    this.interactive3d = false,
    this.maxTilt = 0.032,
    this.enablePressScale = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color? accentGlow;
  final Color? borderColor;
  final Color? backgroundColor;
  final bool interactive3d;
  final double maxTilt;
  final bool enablePressScale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final radius = BorderRadius.circular(borderRadius);
    final bg = backgroundColor ?? tokens.cardSurface;
    final line = borderColor ?? tokens.border;

    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: content,
        ),
      );
    }

    Widget surface = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(color: line),
        boxShadow: tokens.cardShadow,
        gradient: accentGlow == null
            ? null
            : RadialGradient(
                center: const Alignment(0.92, -0.88),
                radius: 1.35,
                colors: [
                  Color.alphaBlend(accentGlow!, bg),
                  bg,
                ],
                stops: const [0.0, 0.78],
              ),
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
          stops: const [0.0, 0.16],
        ),
      ),
      child: content,
    );

    if (interactive3d) {
      surface = Motion3dInteractiveSurface(
        borderRadius: radius,
        maxTilt: maxTilt,
        enablePressScale: enablePressScale,
        child: surface,
      );
    }
    return surface;
  }
}

class GhstAuroraBanner extends StatelessWidget {
  const GhstAuroraBanner({
    super.key,
    required this.child,
    this.gradient,
    this.accentOrbColor = const Color(0x556EE7B7),
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 18,
    this.interactive3d = false,
    this.onTap,
  });

  final Widget child;
  final LinearGradient? gradient;
  final Color accentOrbColor;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool interactive3d;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final radius = BorderRadius.circular(borderRadius);
    final effectiveGradient = gradient ?? tokens.heroGradient;

    Widget inner = Stack(
      children: [
        Positioned(
          right: -28,
          top: -34,
          child: IgnorePointer(
            child: Container(
              width: 148,
              height: 148,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accentOrbColor,
                    accentOrbColor.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    );

    if (onTap != null) {
      inner = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: inner,
        ),
      );
    }

    Widget box = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: effectiveGradient,
        borderRadius: radius,
        border: Border.all(
          color: Colors.white.withValues(alpha: tokens.isDark ? 0.14 : 0.22),
        ),
        boxShadow: tokens.elevatedShadow,
      ),
      child: inner,
    );

    if (interactive3d) {
      box = Motion3dInteractiveSurface(
        borderRadius: radius,
        maxTilt: 0.028,
        enablePressScale: onTap != null,
        child: box,
      );
    }
    return box;
  }
}

class GhstPulseBeacon extends StatefulWidget {
  const GhstPulseBeacon({
    super.key,
    required this.color,
    this.size = 9,
    this.active = true,
  });

  final Color color;
  final double size;
  final bool active;

  @override
  State<GhstPulseBeacon> createState() => _GhstPulseBeaconState();
}

class _GhstPulseBeaconState extends State<GhstPulseBeacon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant GhstPulseBeacon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active && Motion3dEnvironment.shouldAnimate(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outer = widget.size * 2.2;
    return SizedBox(
      width: outer,
      height: outer,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) {
          final t = _controller.value;
          final ripple = widget.active ? (0.45 + 0.55 * t) : 0.45;
          final alpha = widget.active ? (0.42 * (1.0 - t)) : 0.18;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: outer * ripple,
                height: outer * ripple,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: alpha),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.55),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
