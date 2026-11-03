import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'animated_3d_ui_icons.dart';
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
    duration: const Duration(seconds: 9),
    value: 0.35,
  );
  final _parallax = ValueNotifier<Offset>(Offset.zero);
  late final _backdrop = Listenable.merge([_animation, _parallax]);
  bool get _testing =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

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
    if ((next - _parallax.value).distance > 0.02) _parallax.value = next;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.techBg,
    body: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 400;
        return MouseRegion(
          onHover: (event) => _hover(event.localPosition, constraints.biggest),
          onExit: (_) => _parallax.value = Offset.zero,
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
                        builder: (_, value, child) => Container(
                          width: double.infinity,
                          padding: EdgeInsets.fromLTRB(
                            compact ? 18 : 28,
                            24,
                            compact ? 18 : 28,
                            26,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.85),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF020617,
                                ).withValues(alpha: 0.30),
                                blurRadius: 32,
                                offset: Offset(
                                  -value.dx * 4,
                                  14 - value.dy * 4,
                                ),
                              ),
                              BoxShadow(
                                color: AppColors.violet.withValues(alpha: 0.16),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: child,
                        ),
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
        size: 76,
        showRadarPulse: true,
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.violet.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.violet.withValues(alpha: 0.25)),
        ),
        child: const Text(
          'GHST • GIAO HÀNG SIÊU TỐC',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: AppColors.violet,
            letterSpacing: 0.3,
          ),
        ),
      ),
    ],
  );
}
