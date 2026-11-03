import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class Motion3dEnvironment {
  const Motion3dEnvironment._();

  static bool get isAutomatedTest {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTest') ||
        bindingType.contains('LiveTestWidgetsFlutterBinding');
  }

  static bool shouldAnimate(BuildContext context, {bool forceInTest = false}) {
    if (!forceInTest && isAutomatedTest) return false;
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations) return false;
    return TickerMode.valuesOf(context).enabled;
  }
}

class Motion3dInteractiveSurface extends StatefulWidget {
  const Motion3dInteractiveSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.maxTilt = 0.075,
    this.pressScale = 0.976,
    this.hoverLift = -2.5,
    this.perspective = 0.0016,
    this.glintOpacity = 0.14,
    this.glintColor = Colors.white,
    this.enablePressScale = true,
    this.enableSpecularGlint = true,
    this.enabled = true,
    this.forceInTest = false,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double maxTilt;
  final double pressScale;
  final double hoverLift;
  final double perspective;
  final double glintOpacity;
  final Color glintColor;
  final bool enablePressScale;
  final bool enableSpecularGlint;
  final bool enabled;
  final bool forceInTest;

  @override
  State<Motion3dInteractiveSurface> createState() =>
      _Motion3dInteractiveSurfaceState();
}

class _Motion3dInteractiveSurfaceState extends State<Motion3dInteractiveSurface>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration? _lastElapsed;

  bool _hovered = false;
  bool _pressed = false;

  double _tiltX = 0.0;
  double _tiltY = 0.0;
  double _scale = 1.0;
  double _liftY = 0.0;
  double _glintAlpha = 0.0;
  double _glintX = 0.0;
  double _glintY = -0.4;

  double _targetTiltX = 0.0;
  double _targetTiltY = 0.0;
  double _targetScale = 1.0;
  double _targetLiftY = 0.0;
  double _targetGlintAlpha = 0.0;
  double _targetGlintX = 0.0;
  double _targetGlintY = -0.4;

  bool get _canAnimate =>
      widget.enabled &&
      mounted &&
      Motion3dEnvironment.shouldAnimate(
        context,
        forceInTest: widget.forceInTest,
      );

  void _ensureTicker() {
    if (!_canAnimate) return;
    _ticker ??= createTicker(_onTick);
    if (!_ticker!.isActive) {
      _lastElapsed = null;
      _ticker!.start();
    }
  }

  void _onTick(Duration elapsed) {
    final prev = _lastElapsed;
    _lastElapsed = elapsed;
    final rawDt = prev == null
        ? (1.0 / 60.0)
        : (elapsed - prev).inMicroseconds / 1000000.0;
    final dt = rawDt.clamp(0.001, 0.050);
    final k = 1.0 - math.exp(-16.0 * dt);

    final nextTiltX = _tiltX + (_targetTiltX - _tiltX) * k;
    final nextTiltY = _tiltY + (_targetTiltY - _tiltY) * k;
    final nextScale = _scale + (_targetScale - _scale) * k;
    final nextLiftY = _liftY + (_targetLiftY - _liftY) * k;
    final nextGlintAlpha = _glintAlpha + (_targetGlintAlpha - _glintAlpha) * k;
    final nextGlintX = _glintX + (_targetGlintX - _glintX) * k;
    final nextGlintY = _glintY + (_targetGlintY - _glintY) * k;

    final settled =
        (nextTiltX - _targetTiltX).abs() < 0.0005 &&
        (nextTiltY - _targetTiltY).abs() < 0.0005 &&
        (nextScale - _targetScale).abs() < 0.0005 &&
        (nextLiftY - _targetLiftY).abs() < 0.02 &&
        (nextGlintAlpha - _targetGlintAlpha).abs() < 0.002;

    if (!mounted) {
      _ticker?.stop();
      return;
    }

    setState(() {
      if (settled) {
        _tiltX = _targetTiltX;
        _tiltY = _targetTiltY;
        _scale = _targetScale;
        _liftY = _targetLiftY;
        _glintAlpha = _targetGlintAlpha;
        _glintX = _targetGlintX;
        _glintY = _targetGlintY;
        _ticker?.stop();
      } else {
        _tiltX = nextTiltX;
        _tiltY = nextTiltY;
        _scale = nextScale;
        _liftY = nextLiftY;
        _glintAlpha = nextGlintAlpha;
        _glintX = nextGlintX;
        _glintY = nextGlintY;
      }
    });
  }

  (double, double)? _normalizedOffset(Offset localPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final size = renderObject.size;
    if (size.width <= 0 || size.height <= 0) return null;
    final nx = ((localPosition.dx / size.width) * 2.0 - 1.0).clamp(-1.0, 1.0);
    final ny = ((localPosition.dy / size.height) * 2.0 - 1.0).clamp(-1.0, 1.0);
    return (nx, ny);
  }

  void _applyPointerVector(Offset localPosition, {required bool pressing}) {
    if (!_canAnimate) return;
    final norm = _normalizedOffset(localPosition);
    if (norm == null) return;
    final (nx, ny) = norm;
    final boost = pressing ? 1.15 : 1.0;
    _targetTiltY = nx * widget.maxTilt * boost;
    _targetTiltX = -ny * widget.maxTilt * boost;
    _targetScale = pressing && widget.enablePressScale
        ? widget.pressScale
        : 1.0;
    _targetLiftY = pressing ? 0.8 : widget.hoverLift;
    _targetGlintAlpha = widget.enableSpecularGlint
        ? (pressing ? widget.glintOpacity * 1.25 : widget.glintOpacity)
        : 0.0;
    _targetGlintX = nx;
    _targetGlintY = ny;
    _ensureTicker();
  }

  void _releaseToRestOrHover() {
    if (!_hovered) {
      _targetTiltX = 0.0;
      _targetTiltY = 0.0;
      _targetScale = 1.0;
      _targetLiftY = 0.0;
      _targetGlintAlpha = 0.0;
    } else {
      _targetScale = 1.0;
      _targetLiftY = widget.hoverLift;
      _targetGlintAlpha = widget.enableSpecularGlint
          ? widget.glintOpacity
          : 0.0;
    }
    _ensureTicker();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final atRest =
        _tiltX == 0.0 &&
        _tiltY == 0.0 &&
        _scale == 1.0 &&
        _liftY == 0.0 &&
        _glintAlpha <= 0.001;

    final matrix = atRest
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..setEntry(3, 2, widget.perspective)
            ..translateByDouble(0.0, _liftY, 0.0, 1.0)
            ..scaleByDouble(_scale, _scale, 1.0, 1.0)
            ..rotateX(_tiltX)
            ..rotateY(_tiltY));

    final Widget body = widget.enableSpecularGlint
        ? Stack(
            fit: StackFit.passthrough,
            children: [
              widget.child,
              if (_glintAlpha > 0.002)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: widget.borderRadius,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(_glintX, _glintY),
                            radius: 1.05,
                            colors: [
                              widget.glintColor.withValues(
                                alpha: _glintAlpha.clamp(0.0, 0.35),
                              ),
                              widget.glintColor.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          )
        : widget.child;

    final Widget content = Transform(
      alignment: Alignment.center,
      transform: matrix,
      child: body,
    );

    return MouseRegion(
      onHover: (event) {
        _hovered = true;
        if (!_pressed) {
          _applyPointerVector(event.localPosition, pressing: false);
        }
      },
      onExit: (_) {
        _hovered = false;
        if (!_pressed) {
          _releaseToRestOrHover();
        }
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          _pressed = true;
          _applyPointerVector(event.localPosition, pressing: true);
        },
        onPointerMove: (event) {
          if (_pressed) {
            _applyPointerVector(event.localPosition, pressing: true);
          }
        },
        onPointerUp: (_) {
          _pressed = false;
          _releaseToRestOrHover();
        },
        onPointerCancel: (_) {
          _pressed = false;
          _releaseToRestOrHover();
        },
        child: content,
      ),
    );
  }
}

class Motion3dSectionTransition extends StatefulWidget {
  const Motion3dSectionTransition({
    super.key,
    required this.transitionKey,
    required this.child,
    this.duration = const Duration(milliseconds: 260),
    this.originAlignment = Alignment.topCenter,
    this.forceInTest = false,
  });

  final Object transitionKey;
  final Widget child;
  final Duration duration;
  final Alignment originAlignment;
  final bool forceInTest;

  @override
  State<Motion3dSectionTransition> createState() =>
      _Motion3dSectionTransitionState();
}

class _Motion3dSectionTransitionState extends State<Motion3dSectionTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1.0,
  );

  @override
  void didUpdateWidget(covariant Motion3dSectionTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.transitionKey != widget.transitionKey) {
      if (Motion3dEnvironment.shouldAnimate(
        context,
        forceInTest: widget.forceInTest,
      )) {
        _controller.forward(from: 0.0);
      } else {
        _controller.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final raw = _controller.value;
      final settled = raw >= 0.999;
      final t = settled
          ? 1.0
          : Curves.easeOutCubic.transform(raw.clamp(0.0, 1.0));
      final opacity = settled ? 1.0 : (0.82 + 0.18 * t).clamp(0.0, 1.0);
      final matrix = settled
          ? Matrix4.identity()
          : (Matrix4.identity()
              ..setEntry(3, 2, 0.0014)
              ..translateByDouble(0.0, (1.0 - t) * 10.0, 0.0, 1.0)
              ..scaleByDouble(0.986 + 0.014 * t, 0.986 + 0.014 * t, 1.0, 1.0)
              ..rotateX((1.0 - t) * 0.042));
      return Opacity(
        opacity: opacity,
        child: Transform(
          alignment: widget.originAlignment,
          transform: matrix,
          child: child,
        ),
      );
    },
  );
}

class Motion3dFloatingLayer extends StatefulWidget {
  const Motion3dFloatingLayer({
    super.key,
    required this.child,
    this.floatAmplitude = 3.5,
    this.tiltAmplitude = 0.024,
    this.period = const Duration(milliseconds: 4200),
    this.forceInTest = false,
  });

  final Widget child;
  final double floatAmplitude;
  final double tiltAmplitude;
  final Duration period;
  final bool forceInTest;

  @override
  State<Motion3dFloatingLayer> createState() => _Motion3dFloatingLayerState();
}

class _Motion3dFloatingLayerState extends State<Motion3dFloatingLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoop();
  }

  @override
  void didUpdateWidget(covariant Motion3dFloatingLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _controller.duration = widget.period;
    }
    _syncLoop();
  }

  void _syncLoop() {
    if (Motion3dEnvironment.shouldAnimate(
      context,
      forceInTest: widget.forceInTest,
    )) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else if (_controller.isAnimating) {
      _controller.stop();
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = Motion3dEnvironment.shouldAnimate(
      context,
      forceInTest: widget.forceInTest,
    );
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        if (!active) {
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity(),
            child: child,
          );
        }
        final angle = _controller.value * math.pi * 2.0;
        final dy = math.sin(angle) * widget.floatAmplitude;
        final rx = math.cos(angle) * widget.tiltAmplitude;
        final ry = math.sin(angle * 0.5) * widget.tiltAmplitude;
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..translateByDouble(0.0, dy, 0.0, 1.0)
          ..rotateX(rx)
          ..rotateY(ry);
        return Transform(
          alignment: Alignment.center,
          transform: matrix,
          child: child,
        );
      },
    );
  }
}
