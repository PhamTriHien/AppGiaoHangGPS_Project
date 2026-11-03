import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'animated_3d_ui_icons.dart';
import 'motion_3d_effects.dart';
import 'studio_design_widgets.dart';
import 'system_state_screens.dart';

/// Shared presentation for the original user login and cloud authentication.
class StudioUserAuthFrame extends StatefulWidget {
  const StudioUserAuthFrame({super.key, required this.child});

  final Widget child;

  @override
  State<StudioUserAuthFrame> createState() => _StudioUserAuthFrameState();
}

class _StudioUserAuthFrameState extends State<StudioUserAuthFrame>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
    value: 0.35,
  )..addListener(_smoothParallax);
  final _parallax = ValueNotifier<Offset>(Offset.zero);
  Offset _targetParallax = Offset.zero;
  late final _backdrop = Listenable.merge([_animation, _parallax]);
  bool get _testing =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

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
  void initState() {
    super.initState();
    if (!_testing) {
      unawaited(
        MeshyScooter3dMesh.instance.ensureLoaded(
          onReady: () {
            if (mounted) setState(() {});
          },
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_testing &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled) {
      _animation.repeat();
    } else {
      _animation.stop();
    }
  }

  @override
  void dispose() {
    _animation.removeListener(_smoothParallax);
    _animation.dispose();
    _parallax.dispose();
    super.dispose();
  }

  void _hover(Offset point, Size size) {
    if (size.isEmpty) return;
    final next = Offset(
      ((point.dx - size.width / 2) / (size.width / 2)).clamp(-1, 1),
      ((point.dy - size.height / 2) / (size.height / 2)).clamp(-1, 1),
    );
    _targetParallax = next;
    if (!_animation.isAnimating && (next - _parallax.value).distance > 0.005) {
      _parallax.value = next;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.techBg,
    body: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 400;
        return MouseRegion(
          onHover: (event) => _hover(event.localPosition, constraints.biggest),
          onExit: (_) {
            _targetParallax = Offset.zero;
            if (!_animation.isAnimating) {
              _parallax.value = Offset.zero;
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _backdrop,
                      builder: (_, _) => CustomPaint(
                        painter: Studio3dLoginAmbientMapPainter(
                          phase: _animation.value,
                          parallaxX: _parallax.value.dx,
                          parallaxY: _parallax.value.dy,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: ValueListenableBuilder<Offset>(
                        valueListenable: _parallax,
                        builder: (context, value, child) {
                          final card = Container(
                            width: double.infinity,
                            padding: EdgeInsets.fromLTRB(
                              compact ? 20 : 30,
                              26,
                              compact ? 20 : 30,
                              28,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.92),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF020617,
                                  ).withValues(alpha: 0.36),
                                  blurRadius: 38,
                                  offset: Offset(
                                    -value.dx * 7,
                                    18 - value.dy * 6,
                                  ),
                                ),
                                BoxShadow(
                                  color: AppColors.violet.withValues(
                                    alpha: 0.18,
                                  ),
                                  blurRadius: 26,
                                  offset: Offset(
                                    -value.dx * 3,
                                    6 - value.dy * 2,
                                  ),
                                ),
                              ],
                            ),
                            child: child,
                          );
                          return Stack(
                            fit: StackFit.passthrough,
                            children: [
                              card,
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(24),
                                      gradient: value.distance > 0.008
                                          ? RadialGradient(
                                              center: Alignment(
                                                value.dx,
                                                value.dy,
                                              ),
                                              radius: 1.15,
                                              colors: [
                                                AppColors.primarySoft
                                                    .withValues(
                                                      alpha: (0.26 *
                                                              value.distance)
                                                          .clamp(0.0, 0.26),
                                                    ),
                                                Colors.white.withValues(
                                                  alpha: 0.0,
                                                ),
                                              ],
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class StudioUserAuthBrand extends StatelessWidget {
  const StudioUserAuthBrand({super.key});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Animated3dIconBadge(
        style: Icon3dStyle.scooterExpress,
        size: 74,
        showRadarPulse: true,
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: const Text(
          'GHST • GIAO HÀNG SIÊU TỐC',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF065F46),
            letterSpacing: 0.35,
          ),
        ),
      ),
    ],
  );
}

class StudioAuthTabBar extends StatelessWidget {
  const StudioAuthTabBar({
    super.key,
    required this.loginSelected,
    required this.onSelectLogin,
    required this.onSelectRegister,
    this.enabled = true,
  });

  final bool loginSelected;
  final VoidCallback onSelectLogin;
  final VoidCallback onSelectRegister;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        Expanded(
          child: _TabPill(
            label: 'Đăng nhập',
            selected: loginSelected,
            onTap: enabled ? onSelectLogin : null,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _TabPill(
            label: 'Đăng ký tài khoản',
            selected: !loginSelected,
            onTap: enabled ? onSelectRegister : null,
          ),
        ),
      ],
    ),
  );
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Motion3dInteractiveSurface(
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      maxTilt: 0.030,
      pressScale: 0.976,
      hoverLift: -0.8,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 40),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(color: AppColors.line.withValues(alpha: 0.9))
                : null,
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x100F172A),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? AppColors.ink : AppColors.textSecondary,
            ),
            ),
          ),
        ),
      ),
    ),
  );
}
