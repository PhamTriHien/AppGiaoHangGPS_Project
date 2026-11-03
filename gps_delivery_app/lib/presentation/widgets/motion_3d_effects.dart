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

class _Spring1D {
  _Spring1D(this.value);

  double value;
  double velocity = 0.0;

  void step(double target, double dt, {required double stiffness}) {
    final damping = 2.0 * math.sqrt(stiffness);
    final force = (target - value) * stiffness - velocity * damping;
    velocity += force * dt;
    value += velocity * dt;
  }

  bool isSettled(double target, {double epsilon = 0.0004}) =>
      (value - target).abs() < epsilon && velocity.abs() < epsilon * 8.0;

  void snap(double target) {
    value = target;
    velocity = 0.0;
  }
}

@immutable
class _Motion3dFrame {
  const _Motion3dFrame({
    required this.tiltX,
    required this.tiltY,
    required this.scale,
    required this.liftY,
    required this.glintAlpha,
    required this.glintX,
    required this.glintY,
  });

  const _Motion3dFrame.rest()
    : tiltX = 0.0,
      tiltY = 0.0,
      scale = 1.0,
      liftY = 0.0,
      glintAlpha = 0.0,
      glintX = 0.0,
      glintY = -0.4;

  final double tiltX;
  final double tiltY;
  final double scale;
  final double liftY;
  final double glintAlpha;
  final double glintX;
  final double glintY;

  bool get atRest =>
      tiltX == 0.0 &&
      tiltY == 0.0 &&
      scale == 1.0 &&
      liftY == 0.0 &&
      glintAlpha <= 0.001;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Motion3dFrame &&
          other.tiltX == tiltX &&
          other.tiltY == tiltY &&
          other.scale == scale &&
          other.liftY == liftY &&
          other.glintAlpha == glintAlpha &&
          other.glintX == glintX &&
          other.glintY == glintY;

  @override
  int get hashCode =>
      Object.hash(tiltX, tiltY, scale, liftY, glintAlpha, glintX, glintY);
}

class Motion3dInteractiveSurface extends StatefulWidget {
  const Motion3dInteractiveSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.maxTilt = 0.042,
    this.pressScale = 0.978,
    this.hoverLift = -2.0,
    this.perspective = 0.0009,
    this.glintOpacity = 0.11,
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
  final ValueNotifier<_Motion3dFrame> _frame = ValueNotifier<_Motion3dFrame>(
    const _Motion3dFrame.rest(),
  );

  bool _hovered = false;
  bool _pressed = false;

  final _Spring1D _tiltX = _Spring1D(0.0);
  final _Spring1D _tiltY = _Spring1D(0.0);
  final _Spring1D _scale = _Spring1D(1.0);
  final _Spring1D _liftY = _Spring1D(0.0);
  final _Spring1D _glintAlpha = _Spring1D(0.0);
  final _Spring1D _glintX = _Spring1D(0.0);
  final _Spring1D _glintY = _Spring1D(-0.4);

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
    if (!mounted) {
      _ticker?.stop();
      return;
    }

    final prev = _lastElapsed;
    _lastElapsed = elapsed;
    final rawDt = prev == null
        ? (1.0 / 60.0)
        : (elapsed - prev).inMicroseconds / 1000000.0;
    final clampedDt = rawDt.clamp(0.001, 0.050);
    final subSteps = (clampedDt / (1.0 / 120.0)).ceil().clamp(1, 6);
    final subDt = clampedDt / subSteps;

    for (var i = 0; i < subSteps; i++) {
      _tiltX.step(_targetTiltX, subDt, stiffness: 280.0);
      _tiltY.step(_targetTiltY, subDt, stiffness: 280.0);
      _scale.step(_targetScale, subDt, stiffness: 380.0);
      _liftY.step(_targetLiftY, subDt, stiffness: 280.0);
      _glintAlpha.step(_targetGlintAlpha, subDt, stiffness: 260.0);
      _glintX.step(_targetGlintX, subDt, stiffness: 260.0);
      _glintY.step(_targetGlintY, subDt, stiffness: 260.0);
    }

    final settled =
        _tiltX.isSettled(_targetTiltX, epsilon: 0.0003) &&
        _tiltY.isSettled(_targetTiltY, epsilon: 0.0003) &&
        _scale.isSettled(_targetScale, epsilon: 0.0003) &&
        _liftY.isSettled(_targetLiftY, epsilon: 0.015) &&
        _glintAlpha.isSettled(_targetGlintAlpha, epsilon: 0.0015);

    if (settled) {
      _tiltX.snap(_targetTiltX);
      _tiltY.snap(_targetTiltY);
      _scale.snap(_targetScale);
      _liftY.snap(_targetLiftY);
      _glintAlpha.snap(_targetGlintAlpha);
      _glintX.snap(_targetGlintX);
      _glintY.snap(_targetGlintY);
      _ticker?.stop();
    }

    _frame.value = _Motion3dFrame(
      tiltX: _tiltX.value,
      tiltY: _tiltY.value,
      scale: _scale.value,
      liftY: _liftY.value,
      glintAlpha: _glintAlpha.value,
      glintX: _glintX.value,
      glintY: _glintY.value,
    );
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
    final boost = pressing ? 1.12 : 1.0;
    _targetTiltY = nx * widget.maxTilt * boost;
    _targetTiltX = -ny * widget.maxTilt * boost;
    _targetScale = pressing && widget.enablePressScale
        ? widget.pressScale
        : 1.0;
    _targetLiftY = pressing ? 0.5 : widget.hoverLift;
    _targetGlintAlpha = widget.enableSpecularGlint
        ? (pressing ? widget.glintOpacity * 1.2 : widget.glintOpacity)
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
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget animatedSurface = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _frame,
        child: widget.child,
        builder: (context, cachedChild) {
          final current = _frame.value;
          final atRest = current.atRest;
          final matrix = atRest
              ? Matrix4.identity()
              : (Matrix4.identity()
                  ..setEntry(3, 2, widget.perspective)
                  ..translateByDouble(0.0, current.liftY, 0.0, 1.0)
                  ..scaleByDouble(current.scale, current.scale, 1.0, 1.0)
                  ..rotateX(current.tiltX)
                  ..rotateY(current.tiltY));

          final Widget body = widget.enableSpecularGlint
              ? Stack(
                  fit: StackFit.passthrough,
                  children: [
                    cachedChild!,
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: widget.borderRadius,
                            gradient: current.glintAlpha > 0.0015
                                ? RadialGradient(
                                    center: Alignment(
                                      current.glintX,
                                      current.glintY,
                                    ),
                                    radius: 1.08,
                                    colors: [
                                      widget.glintColor.withValues(
                                        alpha: current.glintAlpha.clamp(
                                          0.0,
                                          0.32,
                                        ),
                                      ),
                                      widget.glintColor.withValues(alpha: 0.0),
                                    ],
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : cachedChild!;

          return Transform(
            alignment: Alignment.center,
            filterQuality: atRest ? null : FilterQuality.medium,
            transform: matrix,
            child: body,
          );
        },
      ),
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
        child: animatedSurface,
      ),
    );
  }
}

class Motion3dSectionTransition extends StatefulWidget {
  const Motion3dSectionTransition({
    super.key,
    required this.transitionKey,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
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
  static const Cubic _easeOutQuint = Cubic(0.22, 1.0, 0.36, 1.0);

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
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final raw = _controller.value;
        final settled = raw >= 0.999;
        final t = settled ? 1.0 : _easeOutQuint.transform(raw.clamp(0.0, 1.0));
        final opacity = settled ? 1.0 : (0.88 + 0.12 * t).clamp(0.0, 1.0);
        final scale = 0.992 + 0.008 * t;
        final matrix = settled
            ? Matrix4.identity()
            : (Matrix4.identity()
                ..setEntry(3, 2, 0.00085)
                ..translateByDouble(0.0, (1.0 - t) * 6.0, 0.0, 1.0)
                ..scaleByDouble(scale, scale, 1.0, 1.0)
                ..rotateX((1.0 - t) * 0.018));
        return Opacity(
          opacity: opacity,
          child: Transform(
            alignment: widget.originAlignment,
            filterQuality: settled ? null : FilterQuality.medium,
            transform: matrix,
            child: child,
          ),
        );
      },
    ),
  );
}

class Motion3dFloatingLayer extends StatefulWidget {
  const Motion3dFloatingLayer({
    super.key,
    required this.child,
    this.floatAmplitude = 3.0,
    this.tiltAmplitude = 0.020,
    this.period = const Duration(milliseconds: 4800),
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
    return RepaintBoundary(
      child: AnimatedBuilder(
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
          final ry = math.sin(angle + 1.1) * (widget.tiltAmplitude * 0.78);
          final matrix = Matrix4.identity()
            ..setEntry(3, 2, 0.0009)
            ..translateByDouble(0.0, dy, 0.0, 1.0)
            ..rotateX(rx)
            ..rotateY(ry);
          return Transform(
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            transform: matrix,
            child: child,
          );
        },
      ),
    );
  }
}
