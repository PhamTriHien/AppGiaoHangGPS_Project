import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/datasources/local/app_state_store.dart';
import 'animated_3d_ui_icons.dart';
import 'system_state_screens.dart';

class _StudioPolygonMarkClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.72)
      ..lineTo(size.width * 0.72, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class StudioMarkWordmark extends StatelessWidget {
  final bool light;
  final String title;
  final String suffix;
  final String badgeTag;

  const StudioMarkWordmark({
    super.key,
    this.light = true,
    this.title = 'Giao Hàng Siêu Tốc',
    this.suffix = '.vn',
    this.badgeTag = 'GHST',
  });

  @override
  Widget build(BuildContext context) {
    final markBg = light ? AppColors.acid : AppColors.ink;
    final markFg = light ? AppColors.techBg : Colors.white;
    final leftBarColor = light ? AppColors.violet : AppColors.acid;
    final tagColor = light ? AppColors.violet : AppColors.acid;
    final wordColor = light ? Colors.white : AppColors.ink;
    final suffixColor = light ? AppColors.acid : AppColors.violet;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipPath(
          clipper: _StudioPolygonMarkClipper(),
          child: Container(
            width: 40,
            height: 40,
            color: markBg,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 5,
                  child: ColoredBox(color: leftBarColor),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'G',
                      style: TextStyle(
                        color: markFg,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.0,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 5,
                  child: Text(
                    badgeTag,
                    style: TextStyle(
                      color: tagColor,
                      fontSize: 6.5,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Consolas',
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 11),
        Flexible(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                  text: title,
                  style: TextStyle(
                    color: wordColor,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.1,
                    height: 1.0,
                  ),
                ),
                TextSpan(
                  text: suffix,
                  style: TextStyle(
                    color: suffixColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Consolas',
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class StudioTechGridPainter extends CustomPainter {
  final double gridSize;
  final Color lineColor;

  const StudioTechGridPainter({
    this.gridSize = 38.0,
    this.lineColor = const Color(0x1494A0AE),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        !gridSize.isFinite ||
        gridSize <= 0) {
      return;
    }
    final gridPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0;

    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final glowCenter = Offset(size.width * 0.80, size.height * 0.30);
    final glowRadius = size.width * 0.36;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.violet.withValues(alpha: 0.22),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius));
    canvas.drawCircle(glowCenter, glowRadius, glowPaint);
  }

  @override
  bool shouldRepaint(covariant StudioTechGridPainter oldDelegate) =>
      oldDelegate.gridSize != gridSize || oldDelegate.lineColor != lineColor;
}

/// Màn hình Hoạt ảnh Khởi động 3D Đa thành phần 60 FPS xuất hiện mỗi khi mở ứng dụng
class Studio3dStartupSplashScreen extends StatefulWidget {
  final VoidCallback onCompleted;
  final Duration duration;
  final bool forceContinuousInTest;

  const Studio3dStartupSplashScreen({
    super.key,
    required this.onCompleted,
    this.duration = const Duration(milliseconds: 3400),
    this.forceContinuousInTest = false,
  });

  @override
  State<Studio3dStartupSplashScreen> createState() =>
      _Studio3dStartupSplashScreenState();
}

class _Studio3dStartupSplashScreenState
    extends State<Studio3dStartupSplashScreen>
    with SingleTickerProviderStateMixin {
  final AppStateStore _store = AppStateStore.instance;
  late final AnimationController _controller;
  double _pointerTiltX = -0.10;
  double _pointerTiltY = 0.14;
  bool _completedTriggered = false;
  bool _animationCompleted = false;
  bool _realBootCompleted = false;
  String _liveStageDetail = '';

  bool get _isAutomatedTestBinding {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTest');
  }

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animationCompleted = true;
        _tryFinishBoot();
      }
    });
    if (_isAutomatedTestBinding) {
      _realBootCompleted = true;
      if (widget.forceContinuousInTest) {
        _controller.forward(from: 0.0);
      }
    } else {
      _controller.forward(from: 0.0);
      unawaited(_executeRealBootPipeline());
    }
  }

  void _onStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _executeRealBootPipeline() async {
    try {
      unawaited(
        _store.startRealTimeDeviceGpsTracking(forcePromptPermission: true),
      );
      if (mounted) {
        setState(() {
          _liveStageDetail = 'Đang nạp lưới mô hình xe 3D GPU...';
        });
      }
      await MeshyScooter3dMesh.instance.ensureLoaded();

      if (!_store.isDatabaseReady) {
        if (mounted) {
          setState(() {
            _liveStageDetail = 'Đang đồng bộ CSDL SQLite & sổ cái vận đơn...';
          });
        }
        await _store.initializeDatabase();
      }

      if (mounted) {
        setState(() {
          _liveStageDetail = 'Đang tải lộ trình giao hàng GPS thực tế...';
        });
      }
      await _store
          .syncLiveOsrmRouteForActiveOrder()
          .timeout(
            const Duration(milliseconds: 2200),
            onTimeout: () => _store.lastSyncStatusMessage,
          );
    } catch (_) {
    } finally {
      _realBootCompleted = true;
      if (mounted) {
        setState(() {
          _liveStageDetail = _store.lastSyncStatusMessage;
        });
      }
      _tryFinishBoot();
    }
  }

  void _tryFinishBoot() {
    if (_completedTriggered || !_animationCompleted || !_realBootCompleted) {
      return;
    }
    _completedTriggered = true;
    widget.onCompleted();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleSkip() {
    if (_completedTriggered) return;
    _completedTriggered = true;
    _controller.stop();
    widget.onCompleted();
  }

  void _update3dStageTilt(Offset localPosition, Size stageSize) {
    if (stageSize.width <= 0 || stageSize.height <= 0) return;
    final normX = ((localPosition.dx - stageSize.width / 2) /
            (stageSize.width / 2))
        .clamp(-1.0, 1.0);
    final normY = ((localPosition.dy - stageSize.height / 2) /
            (stageSize.height / 2))
        .clamp(-1.0, 1.0);
    final nextTiltY = normX * 0.28;
    final nextTiltX = -normY * 0.24;
    if ((nextTiltY - _pointerTiltY).abs() < 0.015 &&
        (nextTiltX - _pointerTiltX).abs() < 0.015) {
      return;
    }
    setState(() {
      _pointerTiltY = nextTiltY;
      _pointerTiltX = nextTiltX;
    });
  }

  String _bootPhaseLabel(double progress) {
    final mesh = MeshyScooter3dMesh.instance;
    if (progress < 0.34) {
      final triText = mesh.isLoaded
          ? '${mesh.triangleCount} đa giác 3D'
          : 'mô hình 3D GPU';
      return 'KHỞI TẠO ĐỒ HỌA 3D & ĐỊNH VỊ ($triText)';
    }
    if (progress < 0.74) {
      return 'NẠP CSDL THỰC TẾ: ${_store.users.length} TK • ${_store.orders.length} ĐƠN • ${_store.drivers.length} TÀI XẾ';
    }
    if (!_realBootCompleted && _liveStageDetail.isNotEmpty) {
      return _liveStageDetail.toUpperCase();
    }
    return 'HỆ THỐNG SẴN SÀNG • ${_store.activeRoutePolyline.length} ĐIỂM LỘ TRÌNH GPS';
  }

  Widget _buildBootMetricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink, width: 1.2),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 10.0,
          fontWeight: FontWeight.w800,
          fontFamily: 'Consolas',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.techBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
              return const SizedBox.shrink();
            }
            final stageSize = Size(constraints.maxWidth, constraints.maxHeight);
            return MouseRegion(
              onHover: (e) => _update3dStageTilt(e.localPosition, stageSize),
              onExit: (_) {
                setState(() {
                  _pointerTiltX = -0.10;
                  _pointerTiltY = 0.14;
                });
              },
              child: GestureDetector(
                onPanUpdate: (d) =>
                    _update3dStageTilt(d.localPosition, stageSize),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final animVal = _controller.value.clamp(0.0, 1.0);
                    final effectiveProgress =
                        (!_realBootCompleted && animVal > 0.92)
                            ? 0.92
                            : animVal;
                    final waveAngle = animVal * math.pi * 4.0;
                    final dynamicTiltX =
                        _pointerTiltX + math.sin(waveAngle) * 0.06;
                    final dynamicTiltY =
                        _pointerTiltY + math.cos(waveAngle) * 0.08;
                    final floatY = math.sin(waveAngle) * -8.0;

                    final matrix3d = Matrix4.identity()
                      ..setEntry(3, 2, 0.0016)
                      ..translateByDouble(0.0, floatY, 0.0, 1.0)
                      ..rotateX(dynamicTiltX)
                      ..rotateY(dynamicTiltY);

                    final percent = (effectiveProgress * 100).round();
                    final onlineDrivers = _store.drivers
                        .where(
                          (d) => d.approvalStatus == 'Đã duyệt' && d.isOnline,
                        )
                        .length;
                    final mesh = MeshyScooter3dMesh.instance;

                    return Stack(
                      children: [
                        const Positioned.fill(
                          child: CustomPaint(
                            painter: StudioTechGridPainter(gridSize: 34),
                          ),
                        ),
                        Positioned(
                          top: 18,
                          right: 22,
                          child: InkWell(
                            onTap: _handleSkip,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.techPanel,
                                border: Border.all(
                                  color: AppColors.acid,
                                  width: 1.4,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: AppColors.violet,
                                    offset: Offset(4, 4),
                                    blurRadius: 0,
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Vào hệ thống ngay',
                                    style: TextStyle(
                                      color: AppColors.acid,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'Consolas',
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(
                                    Icons.north_east_rounded,
                                    color: AppColors.acid,
                                    size: 14,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.symmetric(
                              horizontal: (constraints.maxWidth * 0.05)
                                  .clamp(14.0, 48.0),
                              vertical: (constraints.maxHeight * 0.03)
                                  .clamp(14.0, 32.0),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const StudioMarkWordmark(light: true),
                                const SizedBox(height: 14),
                                Transform(
                                  alignment: Alignment.center,
                                  transform: matrix3d,
                                  child: Container(
                                    width: (constraints.maxWidth * 0.76)
                                        .clamp(240.0, 620.0),
                                    height: (constraints.maxHeight * 0.34)
                                        .clamp(172.0, 340.0),
                                    decoration: BoxDecoration(
                                      color: const Color(0xCC0A0E14),
                                      border: Border.all(
                                        color: AppColors.acid,
                                        width: 1.6,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: AppColors.violet,
                                          offset: Offset(12, 12),
                                          blurRadius: 0,
                                        ),
                                      ],
                                    ),
                                    child: CustomPaint(
                                      painter: Studio3dBootScenePainter(
                                        phase: animVal,
                                        tiltX: dynamicTiltX,
                                        tiltY: dynamicTiltY,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Wrap(
                                  spacing: 18,
                                  runSpacing: 12,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    Animated3dIconBadge(
                                      style: Icon3dStyle.scooterExpress,
                                      size: 60,
                                      isSelected: effectiveProgress >= 0.15,
                                    ),
                                    Animated3dIconBadge(
                                      style: Icon3dStyle.parcelBox,
                                      size: 60,
                                      isSelected: effectiveProgress >= 0.40,
                                    ),
                                    Animated3dIconBadge(
                                      style: Icon3dStyle.gpsPinRadar,
                                      size: 60,
                                      isSelected: effectiveProgress >= 0.65,
                                    ),
                                    Animated3dIconBadge(
                                      style: Icon3dStyle.walletVault,
                                      size: 60,
                                      isSelected: effectiveProgress >= 0.85,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                Container(
                                  width: (constraints.maxWidth * 0.82)
                                      .clamp(240.0, 650.0),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppColors.paper,
                                    border: Border.all(
                                      color: AppColors.ink,
                                      width: 2.0,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: AppColors.violet,
                                        offset: Offset(6, 6),
                                        blurRadius: 0,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _bootPhaseLabel(effectiveProgress),
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppColors.ink,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w900,
                                                fontFamily: 'Consolas',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              color: AppColors.ink,
                                              child: Text(
                                                '$percent%',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: AppColors.acid,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900,
                                                  fontFamily: 'Consolas',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        height: 13,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(
                                            color: AppColors.ink,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: effectiveProgress
                                              .clamp(0.04, 1.0),
                                          child: Container(
                                            color: AppColors.acid,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          _buildBootMetricChip(
                                            'CSDL',
                                            '${_store.users.length} TK • ${_store.orders.length} đơn',
                                          ),
                                          _buildBootMetricChip(
                                            'Đội xe',
                                            '$onlineDrivers/${_store.drivers.length} trực tuyến',
                                          ),
                                          _buildBootMetricChip(
                                            'Kho & Vùng',
                                            '${_store.merchantWarehouses.length} kho • ${_store.geofenceZones.length} vùng',
                                          ),
                                          _buildBootMetricChip(
                                            '3D & GPS',
                                            '${mesh.isLoaded ? "${mesh.triangleCount} đa giác" : "Nạp GPU"} • ${_store.activeRoutePolyline.length} điểm',
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Động cơ vẽ Cảnh 3D Khởi động: Lưới mặt phẳng Radar 3D, Khối kiện hàng 3D xoay đa diện, Vòng quỹ đạo Vệ tinh GPS & Chùm tia Laser Volumetric
class Studio3dBootScenePainter extends CustomPainter {
  final double phase;
  final double tiltX;
  final double tiltY;

  const Studio3dBootScenePainter({
    required this.phase,
    this.tiltX = 0.0,
    this.tiltY = 0.0,
  });

  Offset _project3D(
    double x,
    double y,
    double z,
    Offset center,
    double yaw,
    double pitch,
  ) {
    // Xoay quanh trục Y (Yaw)
    final cosY = math.cos(yaw);
    final sinY = math.sin(yaw);
    final x1 = x * cosY - z * sinY;
    final z1 = x * sinY + z * cosY;

    // Xoay quanh trục X (Pitch)
    final cosP = math.cos(pitch);
    final sinP = math.sin(pitch);
    final y2 = y * cosP - z1 * sinP;
    final z2 = y * sinP + z1 * cosP;

    // Phép chiếu phối cảnh (Perspective Projection)
    const fov = 420.0;
    final depth = (fov + z2 + 240.0).clamp(80.0, 3000.0);
    final scale = fov / depth;
    return Offset(center.dx + x1 * scale, center.dy + y2 * scale);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        !phase.isFinite) {
      return;
    }
    final center = Offset(size.width / 2, size.height * 0.54);
    final yaw = phase * math.pi * 2.0 + tiltY * 1.4;
    final pitch = 0.52 + tiltX * 0.8;

    // 1. Vẽ quầng sáng Volumetric trung tâm
    final bgGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.violet.withValues(alpha: 0.42),
          AppColors.acid.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * 0.44));
    canvas.drawCircle(center, size.width * 0.44, bgGlow);

    // 2. Vẽ mặt phẳng lưới đô thị 3D & sóng xung kích Radar ở độ sâu y = 68
    const floorY = 68.0;
    final gridPaint = Paint()
      ..color = const Color(0x38D1E7FF)
      ..strokeWidth = 1.0;

    for (int i = -4; i <= 4; i++) {
      final coord = i * 34.0;
      final p1 = _project3D(coord, floorY, -136.0, center, yaw * 0.35, pitch);
      final p2 = _project3D(coord, floorY, 136.0, center, yaw * 0.35, pitch);
      canvas.drawLine(p1, p2, gridPaint);

      final q1 = _project3D(-136.0, floorY, coord, center, yaw * 0.35, pitch);
      final q2 = _project3D(136.0, floorY, coord, center, yaw * 0.35, pitch);
      canvas.drawLine(q1, q2, gridPaint);
    }

    // 3 vòng sóng Radar 3D lan tỏa trên mặt phẳng
    for (int r = 0; r < 3; r++) {
      final ringPhase = (phase * 2.0 + r * 0.33) % 1.0;
      final radius = 24.0 + ringPhase * 125.0;
      final ringPaint = Paint()
        ..color = (r.isEven ? AppColors.acid : AppColors.pink)
            .withValues(alpha: (1.0 - ringPhase) * 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final ringPath = Path();
      const segments = 36;
      for (int s = 0; s <= segments; s++) {
        final theta = (s / segments) * math.pi * 2.0;
        final rx = math.cos(theta) * radius;
        final rz = math.sin(theta) * radius;
        final pt = _project3D(rx, floorY, rz, center, yaw * 0.35, pitch);
        if (s == 0) {
          ringPath.moveTo(pt.dx, pt.dy);
        } else {
          ringPath.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(ringPath, ringPaint);
    }

    // 3. Vẽ 2 Vòng quỹ đạo Vệ tinh GPS 3D nghiêng chéo
    for (int orbitIdx = 0; orbitIdx < 2; orbitIdx++) {
      final orbitTilt = orbitIdx == 0 ? 0.45 : -0.45;
      final orbitRadius = orbitIdx == 0 ? 108.0 : 92.0;
      final orbitPaint = Paint()
        ..color = (orbitIdx == 0 ? AppColors.acid : AppColors.violet)
            .withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;

      final orbitPath = Path();
      const segs = 40;
      for (int s = 0; s <= segs; s++) {
        final a = (s / segs) * math.pi * 2.0;
        final ox = math.cos(a) * orbitRadius;
        final oy = math.sin(a) * orbitRadius * math.sin(orbitTilt) - 12.0;
        final oz = math.sin(a) * orbitRadius * math.cos(orbitTilt);
        final pt = _project3D(ox, oy, oz, center, yaw * 0.5, pitch);
        if (s == 0) {
          orbitPath.moveTo(pt.dx, pt.dy);
        } else {
          orbitPath.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(orbitPath, orbitPaint);

      // Hạt vệ tinh GPS chuyển động trên quỹ đạo
      final satAngle = phase * math.pi * 4.0 + (orbitIdx * math.pi);
      final sx = math.cos(satAngle) * orbitRadius;
      final sy = math.sin(satAngle) * orbitRadius * math.sin(orbitTilt) - 12.0;
      final sz = math.sin(satAngle) * orbitRadius * math.cos(orbitTilt);
      final satPt = _project3D(sx, sy, sz, center, yaw * 0.5, pitch);

      canvas.drawCircle(
        satPt,
        8.0,
        Paint()
          ..color = (orbitIdx == 0 ? AppColors.acid : AppColors.pink)
              .withValues(alpha: 0.35),
      );
      canvas.drawCircle(
        satPt,
        4.2,
        Paint()..color = orbitIdx == 0 ? AppColors.acid : AppColors.pink,
      );
    }

    // 4. Vẽ Khối Lập Phương Kiện Hàng 3D (Isometric 3D Parcel Cube) bay lơ lửng ở trung tâm
    final floatOffset = math.sin(phase * math.pi * 4.0) * 10.0 - 16.0;
    const half = 36.0;
    final vertices = <List<double>>[
      [-half, floatOffset - half, -half], // 0: top-left-back
      [half, floatOffset - half, -half], // 1: top-right-back
      [half, floatOffset - half, half], // 2: top-right-front
      [-half, floatOffset - half, half], // 3: top-left-front
      [-half, floatOffset + half, -half], // 4: bottom-left-back
      [half, floatOffset + half, -half], // 5: bottom-right-back
      [half, floatOffset + half, half], // 6: bottom-right-front
      [-half, floatOffset + half, half], // 7: bottom-left-front
    ];

    final projected = vertices
        .map((v) => _project3D(v[0], v[1], v[2], center, yaw, pitch))
        .toList();

    final faces = <(List<int>, Color)>[
      ([4, 5, 6, 7], const Color(0xFF1E1A34)), // Mặt đáy
      ([0, 1, 5, 4], const Color(0xFF3A2399)), // Mặt sau
      ([0, 3, 7, 4], const Color(0xFF492BC4)), // Mặt trái
      ([1, 2, 6, 5], const Color(0xFF2563EB)), // Mặt phải
      ([3, 2, 6, 7], const Color(0xFF724DFF)), // Mặt trước
      ([0, 1, 2, 3], AppColors.paper), // Mặt nắp trên
    ];

    final edgePaint = Paint()
      ..color = AppColors.acid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    for (final face in faces) {
      final idxs = face.$1;
      final path = Path()
        ..moveTo(projected[idxs[0]].dx, projected[idxs[0]].dy)
        ..lineTo(projected[idxs[1]].dx, projected[idxs[1]].dy)
        ..lineTo(projected[idxs[2]].dx, projected[idxs[2]].dy)
        ..lineTo(projected[idxs[3]].dx, projected[idxs[3]].dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = face.$2.withValues(alpha: 0.90)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(path, edgePaint);
    }

    // Dải băng niêm phong 3D màu Acid Lime cắt ngang nắp hộp
    final tapeStart = Offset.lerp(projected[0], projected[3], 0.5)!;
    final tapeEnd = Offset.lerp(projected[1], projected[2], 0.5)!;
    canvas.drawLine(
      tapeStart,
      tapeEnd,
      Paint()
        ..color = AppColors.pink
        ..strokeWidth = 5.0,
    );

    // 5. Chùm tia Laser Volumetric quét dọc khối 3D
    final scanRatio = (math.sin(phase * math.pi * 4.0) + 1.0) / 2.0;
    final scanY = floatOffset - half + scanRatio * (half * 2.0);
    final scanPts = [
      _project3D(-half * 1.25, scanY, -half * 1.25, center, yaw, pitch),
      _project3D(half * 1.25, scanY, -half * 1.25, center, yaw, pitch),
      _project3D(half * 1.25, scanY, half * 1.25, center, yaw, pitch),
      _project3D(-half * 1.25, scanY, half * 1.25, center, yaw, pitch),
    ];
    final scanPath = Path()
      ..moveTo(scanPts[0].dx, scanPts[0].dy)
      ..lineTo(scanPts[1].dx, scanPts[1].dy)
      ..lineTo(scanPts[2].dx, scanPts[2].dy)
      ..lineTo(scanPts[3].dx, scanPts[3].dy)
      ..close();
    canvas.drawPath(
      scanPath,
      Paint()
        ..color = AppColors.acid.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      scanPath,
      Paint()
        ..color = AppColors.acid
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // 6. Đỉnh Ghim Định vị GPS 3D phát sáng phía trên khối hộp
    final pinCenter = _project3D(
      0,
      floatOffset - half - 32.0,
      0,
      center,
      yaw,
      pitch,
    );
    canvas.drawCircle(
      pinCenter,
      14.0,
      Paint()..color = AppColors.pink.withValues(alpha: 0.30),
    );
    canvas.drawCircle(
      pinCenter,
      7.0,
      Paint()..color = AppColors.pink,
    );
    canvas.drawCircle(
      pinCenter,
      3.0,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant Studio3dBootScenePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.tiltX != tiltX ||
        oldDelegate.tiltY != tiltY;
  }
}

/// Nền Đồ họa Bản đồ Lộ trình GPS 3D Chìm cho Màn hình Đăng nhập (Ambient 3D Isometric City & Live GPS Route Network)
class Studio3dLoginAmbientMapPainter extends CustomPainter {
  final double phase;
  final double parallaxX;
  final double parallaxY;

  const Studio3dLoginAmbientMapPainter({
    this.phase = 0.35,
    this.parallaxX = 0.0,
    this.parallaxY = 0.0,
  });

  Offset _projectWorld3D(
    double x,
    double y,
    double z,
    Size size,
  ) {
    final center = Offset(
      size.width * 0.5 + parallaxX * 28.0,
      size.height * 0.54 + parallaxY * 20.0,
    );
    final yaw = 0.32 + math.sin(phase * math.pi * 2.0) * 0.06 + parallaxX * 0.12;
    final pitch = 0.56 + parallaxY * 0.08;

    final cosY = math.cos(yaw);
    final sinY = math.sin(yaw);
    final x1 = x * cosY - z * sinY;
    final z1 = x * sinY + z * cosY;

    final cosP = math.cos(pitch);
    final sinP = math.sin(pitch);
    final y2 = y * cosP - z1 * sinP;
    final z2 = y * sinP + z1 * cosP;

    const fov = 780.0;
    final depth = (fov + z2 + 420.0).clamp(120.0, 3000.0);
    final scale = fov / depth;
    return Offset(center.dx + x1 * scale, center.dy + y2 * scale);
  }

  double _worldDepthScale(double x, double y, double z) {
    final yaw = 0.32 + math.sin(phase * math.pi * 2.0) * 0.06 + parallaxX * 0.12;
    final pitch = 0.56 + parallaxY * 0.08;
    final z1 = x * math.sin(yaw) + z * math.cos(yaw);
    final z2 = y * math.sin(pitch) + z1 * math.cos(pitch);
    final baseZ2 = y * math.sin(pitch);
    const fov = 780.0;
    final ptDepth = (fov + z2 + 420.0).clamp(120.0, 3000.0);
    final baseDepth = (fov + baseZ2 + 420.0).clamp(120.0, 3000.0);
    return (baseDepth / ptDepth).clamp(0.74, 1.30);
  }

  void _drawExtruded3dBlock(
    Canvas canvas,
    Size size, {
    required double cx,
    required double cz,
    required double w,
    required double d,
    required double h,
    required Color strokeColor,
    required Color topFillColor,
  }) {
    const groundY = 120.0;
    final topY = groundY - h;

    final b0 = _projectWorld3D(cx - w, groundY, cz - d, size);
    final b1 = _projectWorld3D(cx + w, groundY, cz - d, size);
    final b2 = _projectWorld3D(cx + w, groundY, cz + d, size);
    final b3 = _projectWorld3D(cx - w, groundY, cz + d, size);

    final t0 = _projectWorld3D(cx - w, topY, cz - d, size);
    final t1 = _projectWorld3D(cx + w, topY, cz - d, size);
    final t2 = _projectWorld3D(cx + w, topY, cz + d, size);
    final t3 = _projectWorld3D(cx - w, topY, cz + d, size);

    final topPath = Path()
      ..moveTo(t0.dx, t0.dy)
      ..lineTo(t1.dx, t1.dy)
      ..lineTo(t2.dx, t2.dy)
      ..lineTo(t3.dx, t3.dy)
      ..close();

    final frontPath = Path()
      ..moveTo(t3.dx, t3.dy)
      ..lineTo(t2.dx, t2.dy)
      ..lineTo(b2.dx, b2.dy)
      ..lineTo(b3.dx, b3.dy)
      ..close();

    final sidePath = Path()
      ..moveTo(t1.dx, t1.dy)
      ..lineTo(t2.dx, t2.dy)
      ..lineTo(b2.dx, b2.dy)
      ..lineTo(b1.dx, b1.dy)
      ..close();

    canvas.drawPath(
      frontPath,
      Paint()
        ..color = strokeColor.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      sidePath,
      Paint()
        ..color = strokeColor.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      topPath,
      Paint()
        ..color = topFillColor
        ..style = PaintingStyle.fill,
    );

    final wirePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawPath(topPath, wirePaint);
    canvas.drawLine(t0, b0, wirePaint);
    canvas.drawLine(t1, b1, wirePaint);
    canvas.drawLine(t2, b2, wirePaint);
    canvas.drawLine(t3, b3, wirePaint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        !phase.isFinite) {
      return;
    }
    // 1. Hai quầng sáng chiều sâu đối xứng (Dual Radial Volumetric Glow)
    final topRightGlow = Offset(size.width * 0.82, size.height * 0.22);
    canvas.drawCircle(
      topRightGlow,
      size.width * 0.38,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.violet.withValues(alpha: 0.26),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: topRightGlow, radius: size.width * 0.38),
        ),
    );

    final bottomLeftGlow = Offset(size.width * 0.18, size.height * 0.80);
    canvas.drawCircle(
      bottomLeftGlow,
      size.width * 0.34,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.acid.withValues(alpha: 0.12),
            AppColors.violet.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(
          Rect.fromCircle(center: bottomLeftGlow, radius: size.width * 0.34),
        ),
    );

    // 2. Lưới mặt phẳng bản đồ phối cảnh 3D (3D Ground Grid)
    const groundY = 120.0;
    final gridPaint = Paint()
      ..color = const Color(0x1694A0AE)
      ..strokeWidth = 1.0;

    for (int i = -9; i <= 9; i++) {
      final coord = i * 85.0;
      final p1 = _projectWorld3D(coord, groundY, -765.0, size);
      final p2 = _projectWorld3D(coord, groundY, 765.0, size);
      canvas.drawLine(p1, p2, gridPaint);

      final q1 = _projectWorld3D(-765.0, groundY, coord, size);
      final q2 = _projectWorld3D(765.0, groundY, coord, size);
      canvas.drawLine(q1, q2, gridPaint);
    }

    // 3. Các khối tòa nhà 3D Wireframe ở hai bên cánh (Tạo chiều sâu đô thị 3D)
    const buildingSpecs = <(double, double, double, double, double, bool)>[
      (-480, -220, 42, 42, 95, true),
      (-360, -90, 36, 36, 64, false),
      (-520, 80, 48, 38, 120, false),
      (-340, 230, 40, 40, 78, true),
      (360, -240, 44, 40, 110, false),
      (490, -70, 46, 46, 135, true),
      (370, 120, 38, 38, 72, false),
      (510, 240, 42, 42, 92, true),
    ];

    for (final b in buildingSpecs) {
      _drawExtruded3dBlock(
        canvas,
        size,
        cx: b.$1,
        cz: b.$2,
        w: b.$3,
        d: b.$4,
        h: b.$5,
        strokeColor: b.$6
            ? AppColors.acid.withValues(alpha: 0.22)
            : const Color(0x33D1E7FF),
        topFillColor: b.$6
            ? AppColors.acid.withValues(alpha: 0.06)
            : AppColors.violet.withValues(alpha: 0.08),
      );
    }

    // 4. Vòng sóng Radar 3D lan tỏa tại 2 trạm điều phối hai bên
    final radarNodes = <(double, double, Color)>[
      (-410.0, 20.0, AppColors.acid),
      (420.0, -20.0, AppColors.pink),
    ];

    for (final node in radarNodes) {
      for (int r = 0; r < 2; r++) {
        final rp = (phase * 1.5 + r * 0.5) % 1.0;
        final radius = 26.0 + rp * 150.0;
        final ringPath = Path();
        const segs = 32;
        for (int s = 0; s <= segs; s++) {
          final a = (s / segs) * math.pi * 2.0;
          final pt = _projectWorld3D(
            node.$1 + math.cos(a) * radius,
            groundY,
            node.$2 + math.sin(a) * radius,
            size,
          );
          if (s == 0) {
            ringPath.moveTo(pt.dx, pt.dy);
          } else {
            ringPath.lineTo(pt.dx, pt.dy);
          }
        }
        canvas.drawPath(
          ringPath,
          Paint()
            ..color = node.$3.withValues(alpha: (1.0 - rp) * 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // 5. Bốn tuyến lộ trình giao hàng 3D Map & Đội xe 3D Meshy Scooter chạy thực tế dưới nền Login
    final routes = <(List<(double, double)>, Color)>[
      (
        [
          (-640, 260),
          (-430, 80),
          (-360, -180),
          (360, -190),
          (450, 60),
          (640, 250),
        ],
        AppColors.acid,
      ),
      (
        [
          (650, -230),
          (430, -90),
          (360, 190),
          (-350, 210),
          (-480, -40),
          (-650, -210),
        ],
        const Color(0xFF00E5FF),
      ),
      (
        [
          (-560, 340),
          (-340, 240),
          (20, 280),
          (380, 220),
          (600, 320),
        ],
        const Color(0xFFFF6B00),
      ),
      (
        [
          (-600, -310),
          (-290, -250),
          (80, -270),
          (410, -240),
          (630, -300),
        ],
        AppColors.pink,
      ),
    ];

    for (int rIdx = 0; rIdx < routes.length; rIdx++) {
      final waypoints = routes[rIdx].$1;
      final color = routes[rIdx].$2;
      final smoothCurve = MeshyScooter3dMesh.buildSmoothFilletedRoute3D(
        waypoints,
      );
      final projectedPts = smoothCurve
          .map((wp) => _projectWorld3D(wp.$1, groundY - 2.0, wp.$2, size))
          .toList();

      final routePath = Path()
        ..moveTo(projectedPts.first.dx, projectedPts.first.dy);
      for (int i = 1; i < projectedPts.length; i++) {
        routePath.lineTo(projectedPts[i].dx, projectedPts[i].dy);
      }

      // Mặt đường nhựa 3D (3D Asphalt Road Ribbon)
      canvas.drawPath(
        routePath,
        Paint()
          ..color = const Color(0x780B1320)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      // Quầng sáng làn đường 3D
      canvas.drawPath(
        routePath,
        Paint()
          ..color = color.withValues(alpha: 0.20)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        routePath,
        Paint()
          ..color = color.withValues(alpha: 0.56)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );

      // Nội suy theo độ dài cung (Arc-Length) & tiếp tuyến 3D mượt liên tục
      final tGlobal = (phase + rIdx * 0.27) % 1.0;
      final sample = MeshyScooter3dMesh.sampleRouteArcLength3D(
        smoothCurve,
        tGlobal,
        trailWorldLength: 92.0,
      );
      final wx = sample.worldX;
      final wz = sample.worldZ;

      final groundBeacon = _projectWorld3D(wx, groundY - 2.0, wz, size);
      final aheadBeacon = _projectWorld3D(
        wx + sample.tangentX * 26.0,
        groundY - 2.0,
        wz + sample.tangentZ * 26.0,
        size,
      );

      final tangentDx = aheadBeacon.dx - groundBeacon.dx;
      final tangentDy = aheadBeacon.dy - groundBeacon.dy;
      final heading = math.atan2(tangentDy, tangentDx);
      final depthScale = _worldDepthScale(wx, groundY - 2.0, wz);

      // Vệt sáng GPS Wake Trail uốn cong bám sát mặt đường phía sau đuôi xe 3D
      if (sample.trailPoints.length >= 2) {
        final projectedTrail = sample.trailPoints
            .map((tp) => _projectWorld3D(tp.$1, groundY - 2.0, tp.$2, size))
            .toList();
        final trailPath = Path()
          ..moveTo(projectedTrail.first.dx, projectedTrail.first.dy);
        for (var i = 1; i < projectedTrail.length; i++) {
          trailPath.lineTo(projectedTrail[i].dx, projectedTrail[i].dy);
        }
        canvas.drawPath(
          trailPath,
          Paint()
            ..shader = LinearGradient(
              colors: [
                color.withValues(alpha: 0.0),
                color.withValues(alpha: 0.92),
              ],
            ).createShader(
              Rect.fromPoints(projectedTrail.first, projectedTrail.last),
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.2 * depthScale
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }

      // Luồng đèn pha 3D (Volumetric Headlight Beam) chiếu thẳng phía trước mũi xe trên mặt đường 3D
      final dirX = math.cos(heading);
      final dirY = math.sin(heading);
      final perpX = -dirY;
      final perpY = dirX;
      final beamOrigin = Offset(
        groundBeacon.dx + dirX * (8.0 * depthScale),
        groundBeacon.dy + dirY * (8.0 * depthScale),
      );
      final beamLen = 50.0 * depthScale;
      final beamSpread = 16.0 * depthScale;
      final beamTipCenter = Offset(
        groundBeacon.dx + dirX * beamLen,
        groundBeacon.dy + dirY * beamLen,
      );
      final beamPath = Path()
        ..moveTo(beamOrigin.dx, beamOrigin.dy)
        ..lineTo(
          beamTipCenter.dx + perpX * beamSpread,
          beamTipCenter.dy + perpY * beamSpread,
        )
        ..lineTo(
          beamTipCenter.dx - perpX * beamSpread,
          beamTipCenter.dy - perpY * beamSpread,
        )
        ..close();
      canvas.drawPath(
        beamPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0x88FFF6B0),
              color.withValues(alpha: 0.18),
              Colors.transparent,
            ],
          ).createShader(Rect.fromPoints(beamOrigin, beamTipCenter)),
      );

      // Vòng sóng định vị GPS dưới bánh xe 3D
      canvas.drawCircle(
        groundBeacon,
        15.0 * depthScale,
        Paint()..color = color.withValues(alpha: 0.22),
      );
      canvas.drawCircle(
        groundBeacon,
        15.0 * depthScale,
        Paint()
          ..color = color.withValues(alpha: 0.68)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );

      // Render mô hình Xe máy Giao hàng 3D thật (Meshy 10,071-triangle 3D Mesh) bám chuẩn 100% hướng tiếp tuyến lộ trình
      final scooterCenter = Offset(
        groundBeacon.dx,
        groundBeacon.dy - 14.0 * depthScale,
      );
      if (MeshyScooter3dMesh.instance.isLoaded) {
        final scooterPitch = (0.44 + parallaxY * 0.08).clamp(0.24, 0.72);
        final scooterYaw = MeshyScooter3dMesh.yawForScreenTangent(
          tangentDx,
          tangentDy,
          pitchRadians: scooterPitch,
        );
        MeshyScooter3dMesh.instance.renderToCanvas(
          canvas,
          center: scooterCenter,
          scalePx: 30.0 * depthScale,
          yawRadians: scooterYaw,
          pitchRadians: scooterPitch,
        );
      } else {
        canvas.drawCircle(
          scooterCenter,
          7.0 * depthScale,
          Paint()..color = const Color(0xFFFF6B00),
        );
      }
    }

    // 6. Bốn dấu chữ thập ngắm tọa độ ở 4 góc màn hình (Corner HUD Crosshairs)
    final crossPaint = Paint()
      ..color = const Color(0x45D1E7FF)
      ..strokeWidth = 1.2;
    const margin = 26.0;
    const arm = 8.0;
    final corners = [
      const Offset(margin, margin),
      Offset(size.width - margin, margin),
      Offset(margin, size.height - margin),
      Offset(size.width - margin, size.height - margin),
    ];
    for (final c in corners) {
      canvas.drawLine(
        Offset(c.dx - arm, c.dy),
        Offset(c.dx + arm, c.dy),
        crossPaint,
      );
      canvas.drawLine(
        Offset(c.dx, c.dy - arm),
        Offset(c.dx, c.dy + arm),
        crossPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant Studio3dLoginAmbientMapPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.parallaxX != parallaxX ||
        oldDelegate.parallaxY != parallaxY;
  }
}

/// Nền Đồ họa Bản đồ Lộ trình GPS 3D & Đội xe 3D Meshy chạy trực tiếp dưới Giao diện Chính sau khi Đăng nhập
class Studio3dMainWorkspaceMapPainter extends CustomPainter {
  final double phase;
  final double parallaxX;
  final double parallaxY;
  final Color accentColor;
  final bool lightweightBackdrop;

  const Studio3dMainWorkspaceMapPainter({
    this.phase = 0.35,
    this.parallaxX = 0.0,
    this.parallaxY = 0.0,
    this.accentColor = AppColors.violet,
    this.lightweightBackdrop = false,
  });

  Offset _projectWorkspace3D(
    double x,
    double y,
    double z,
    Size size,
  ) {
    final isWide = size.width >= 860.0;
    final center = Offset(
      size.width * (isWide ? 0.58 : 0.50) + parallaxX * 24.0,
      size.height * 0.56 + parallaxY * 18.0,
    );
    final yaw = -0.26 + math.sin(phase * math.pi * 2.0) * 0.05 + parallaxX * 0.10;
    final pitch = 0.54 + parallaxY * 0.07;

    final cosY = math.cos(yaw);
    final sinY = math.sin(yaw);
    final x1 = x * cosY - z * sinY;
    final z1 = x * sinY + z * cosY;

    final cosP = math.cos(pitch);
    final sinP = math.sin(pitch);
    final y2 = y * cosP - z1 * sinP;
    final z2 = y * sinP + z1 * cosP;

    const fov = 840.0;
    final depth = (fov + z2 + 440.0).clamp(140.0, 3200.0);
    final scale = fov / depth;
    return Offset(center.dx + x1 * scale, center.dy + y2 * scale);
  }

  double _workspaceDepthScale(double x, double y, double z) {
    final yaw = -0.26 + math.sin(phase * math.pi * 2.0) * 0.05 + parallaxX * 0.10;
    final pitch = 0.54 + parallaxY * 0.07;
    final z1 = x * math.sin(yaw) + z * math.cos(yaw);
    final z2 = y * math.sin(pitch) + z1 * math.cos(pitch);
    final baseZ2 = y * math.sin(pitch);
    const fov = 840.0;
    final ptDepth = (fov + z2 + 440.0).clamp(140.0, 3200.0);
    final baseDepth = (fov + baseZ2 + 440.0).clamp(140.0, 3200.0);
    return (baseDepth / ptDepth).clamp(0.74, 1.28);
  }

  void _drawWorkspace3dBlock(
    Canvas canvas,
    Size size, {
    required double cx,
    required double cz,
    required double w,
    required double d,
    required double h,
    required Color strokeColor,
    required Color topFillColor,
  }) {
    const groundY = 125.0;
    final topY = groundY - h;

    final b0 = _projectWorkspace3D(cx - w, groundY, cz - d, size);
    final b1 = _projectWorkspace3D(cx + w, groundY, cz - d, size);
    final b2 = _projectWorkspace3D(cx + w, groundY, cz + d, size);
    final b3 = _projectWorkspace3D(cx - w, groundY, cz + d, size);

    final t0 = _projectWorkspace3D(cx - w, topY, cz - d, size);
    final t1 = _projectWorkspace3D(cx + w, topY, cz - d, size);
    final t2 = _projectWorkspace3D(cx + w, topY, cz + d, size);
    final t3 = _projectWorkspace3D(cx - w, topY, cz + d, size);

    final topPath = Path()
      ..moveTo(t0.dx, t0.dy)
      ..lineTo(t1.dx, t1.dy)
      ..lineTo(t2.dx, t2.dy)
      ..lineTo(t3.dx, t3.dy)
      ..close();

    final frontPath = Path()
      ..moveTo(t3.dx, t3.dy)
      ..lineTo(t2.dx, t2.dy)
      ..lineTo(b2.dx, b2.dy)
      ..lineTo(b3.dx, b3.dy)
      ..close();

    final sidePath = Path()
      ..moveTo(t1.dx, t1.dy)
      ..lineTo(t2.dx, t2.dy)
      ..lineTo(b2.dx, b2.dy)
      ..lineTo(b1.dx, b1.dy)
      ..close();

    canvas.drawPath(
      frontPath,
      Paint()
        ..color = strokeColor.withValues(alpha: 0.06)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      sidePath,
      Paint()
        ..color = strokeColor.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      topPath,
      Paint()
        ..color = topFillColor
        ..style = PaintingStyle.fill,
    );

    final wirePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05;

    canvas.drawPath(topPath, wirePaint);
    canvas.drawLine(t0, b0, wirePaint);
    canvas.drawLine(t1, b1, wirePaint);
    canvas.drawLine(t2, b2, wirePaint);
    canvas.drawLine(t3, b3, wirePaint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        !phase.isFinite) {
      return;
    }
    // 1. Lưới kỹ thuật vi mô 2D kết hợp Quầng sáng chiều sâu Kiến trúc (Studio Ambient Glow)
    final fineGridPaint = Paint()
      ..color = const Color(0x0E15131E)
      ..strokeWidth = 1.0;
    const step = 42.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), fineGridPaint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), fineGridPaint);
    }

    final topRightGlow = Offset(size.width * 0.84, size.height * 0.20);
    canvas.drawCircle(
      topRightGlow,
      size.width * 0.36,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accentColor.withValues(alpha: 0.14),
            const Color(0x0D00B4D8),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(
          Rect.fromCircle(center: topRightGlow, radius: size.width * 0.36),
        ),
    );

    final bottomLeftGlow = Offset(size.width * 0.32, size.height * 0.84);
    canvas.drawCircle(
      bottomLeftGlow,
      size.width * 0.34,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.acid.withValues(alpha: 0.18),
            accentColor.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(
          Rect.fromCircle(center: bottomLeftGlow, radius: size.width * 0.34),
        ),
    );
    if (lightweightBackdrop) {
      return;
    }

    // 2. Lưới mặt phẳng Bản đồ 3D Phối cảnh (3D Perspective Ground Map Grid)
    const groundY = 125.0;
    final mapGridPaint = Paint()
      ..color = const Color(0x1D1F4E79)
      ..strokeWidth = 1.0;

    for (int i = -10; i <= 10; i++) {
      final coord = i * 90.0;
      final p1 = _projectWorkspace3D(coord, groundY, -850.0, size);
      final p2 = _projectWorkspace3D(coord, groundY, 850.0, size);
      canvas.drawLine(p1, p2, mapGridPaint);

      final q1 = _projectWorkspace3D(-850.0, groundY, coord, size);
      final q2 = _projectWorkspace3D(850.0, groundY, coord, size);
      canvas.drawLine(q1, q2, mapGridPaint);
    }

    // 3. Khối Đô thị & Trạm Điều phối Logistics 3D (Extruded 3D Smart-City Blocks)
    const buildingSpecs = <(double, double, double, double, double, bool)>[
      (-540, -260, 44, 44, 105, true),
      (-380, -110, 38, 38, 72, false),
      (-560, 90, 50, 40, 128, false),
      (-360, 250, 42, 42, 84, true),
      (380, -260, 46, 42, 118, false),
      (520, -80, 48, 48, 142, true),
      (390, 130, 40, 40, 78, false),
      (540, 260, 44, 44, 96, true),
      (-120, -320, 46, 38, 88, false),
      (160, 310, 44, 40, 90, true),
    ];

    for (final b in buildingSpecs) {
      _drawWorkspace3dBlock(
        canvas,
        size,
        cx: b.$1,
        cz: b.$2,
        w: b.$3,
        d: b.$4,
        h: b.$5,
        strokeColor: b.$6
            ? accentColor.withValues(alpha: 0.26)
            : const Color(0x2E1F4E79),
        topFillColor: b.$6
            ? AppColors.acid.withValues(alpha: 0.14)
            : accentColor.withValues(alpha: 0.08),
      );
    }

    // 4. Vòng sóng Radar 3D tại 3 Trạm Điều phối Trung tâm (3D Dispatch Hubs)
    final radarNodes = <(double, double, Color)>[
      (-410.0, 20.0, accentColor),
      (430.0, -30.0, const Color(0xFFFF6B00)),
      (30.0, 230.0, const Color(0xFF0096C7)),
    ];

    for (final node in radarNodes) {
      for (int r = 0; r < 2; r++) {
        final rp = (phase * 1.6 + r * 0.5) % 1.0;
        final radius = 28.0 + rp * 165.0;
        final ringPath = Path();
        const segs = 32;
        for (int s = 0; s <= segs; s++) {
          final a = (s / segs) * math.pi * 2.0;
          final pt = _projectWorkspace3D(
            node.$1 + math.cos(a) * radius,
            groundY,
            node.$2 + math.sin(a) * radius,
            size,
          );
          if (s == 0) {
            ringPath.moveTo(pt.dx, pt.dy);
          } else {
            ringPath.lineTo(pt.dx, pt.dy);
          }
        }
        canvas.drawPath(
          ringPath,
          Paint()
            ..color = node.$3.withValues(alpha: (1.0 - rp) * 0.32)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // 5. Bốn tuyến Đại lộ Giao hàng 3D & Đội xe 3D Meshy chạy liên tục dưới nền Giao diện Chính
    final routes = <(List<(double, double)>, Color)>[
      (
        [
          (-680, 270),
          (-440, 80),
          (-320, -190),
          (340, -200),
          (470, 70),
          (680, 260),
        ],
        const Color(0xFFFF6B00),
      ),
      (
        [
          (680, -240),
          (440, -90),
          (340, 200),
          (-340, 220),
          (-490, -50),
          (-680, -220),
        ],
        accentColor,
      ),
      (
        [
          (-600, 350),
          (-320, 250),
          (40, 290),
          (390, 230),
          (640, 330),
        ],
        const Color(0xFF0088AA),
      ),
      (
        [
          (-620, -320),
          (-280, -260),
          (90, -280),
          (420, -250),
          (660, -310),
        ],
        AppColors.pink,
      ),
    ];

    for (int rIdx = 0; rIdx < routes.length; rIdx++) {
      final waypoints = routes[rIdx].$1;
      final color = routes[rIdx].$2;
      final smoothCurve = MeshyScooter3dMesh.buildSmoothFilletedRoute3D(
        waypoints,
      );
      final projectedPts = smoothCurve
          .map((wp) => _projectWorkspace3D(wp.$1, groundY - 2.0, wp.$2, size))
          .toList();

      final routePath = Path()
        ..moveTo(projectedPts.first.dx, projectedPts.first.dy);
      for (int i = 1; i < projectedPts.length; i++) {
        routePath.lineTo(projectedPts[i].dx, projectedPts[i].dy);
      }

      // Mặt đường 3D mảnh tinh tế trên nền sáng (Architectural 3D Road Ribbon)
      canvas.drawPath(
        routePath,
        Paint()
          ..color = const Color(0x1815131E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 11.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        routePath,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        routePath,
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );

      final tGlobal = (phase + rIdx * 0.25) % 1.0;
      final sample = MeshyScooter3dMesh.sampleRouteArcLength3D(
        smoothCurve,
        tGlobal,
        trailWorldLength: 92.0,
      );
      final wx = sample.worldX;
      final wz = sample.worldZ;

      final groundBeacon = _projectWorkspace3D(wx, groundY - 2.0, wz, size);
      final aheadBeacon = _projectWorkspace3D(
        wx + sample.tangentX * 26.0,
        groundY - 2.0,
        wz + sample.tangentZ * 26.0,
        size,
      );

      final tangentDx = aheadBeacon.dx - groundBeacon.dx;
      final tangentDy = aheadBeacon.dy - groundBeacon.dy;
      final heading = math.atan2(tangentDy, tangentDx);
      final depthScale = _workspaceDepthScale(wx, groundY - 2.0, wz);

      // Vệt sáng GPS Wake Trail uốn cong bám sát mặt đường phía sau đuôi xe 3D
      if (sample.trailPoints.length >= 2) {
        final projectedTrail = sample.trailPoints
            .map((tp) => _projectWorkspace3D(tp.$1, groundY - 2.0, tp.$2, size))
            .toList();
        final trailPath = Path()
          ..moveTo(projectedTrail.first.dx, projectedTrail.first.dy);
        for (var i = 1; i < projectedTrail.length; i++) {
          trailPath.lineTo(projectedTrail[i].dx, projectedTrail[i].dy);
        }
        canvas.drawPath(
          trailPath,
          Paint()
            ..shader = LinearGradient(
              colors: [
                color.withValues(alpha: 0.0),
                color.withValues(alpha: 0.85),
              ],
            ).createShader(
              Rect.fromPoints(projectedTrail.first, projectedTrail.last),
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.8 * depthScale
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }

      // Luồng đèn pha 3D chiếu thẳng phía trước mũi xe trên mặt đường 3D
      final dirX = math.cos(heading);
      final dirY = math.sin(heading);
      final perpX = -dirY;
      final perpY = dirX;
      final beamOrigin = Offset(
        groundBeacon.dx + dirX * (7.5 * depthScale),
        groundBeacon.dy + dirY * (7.5 * depthScale),
      );
      final beamLen = 46.0 * depthScale;
      final beamSpread = 14.0 * depthScale;
      final beamTipCenter = Offset(
        groundBeacon.dx + dirX * beamLen,
        groundBeacon.dy + dirY * beamLen,
      );
      final beamPath = Path()
        ..moveTo(beamOrigin.dx, beamOrigin.dy)
        ..lineTo(
          beamTipCenter.dx + perpX * beamSpread,
          beamTipCenter.dy + perpY * beamSpread,
        )
        ..lineTo(
          beamTipCenter.dx - perpX * beamSpread,
          beamTipCenter.dy - perpY * beamSpread,
        )
        ..close();
      canvas.drawPath(
        beamPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.32),
              AppColors.acid.withValues(alpha: 0.16),
              Colors.transparent,
            ],
          ).createShader(Rect.fromPoints(beamOrigin, beamTipCenter)),
      );

      // Vòng sóng định vị GPS dưới bánh xe 3D
      canvas.drawCircle(
        groundBeacon,
        14.0 * depthScale,
        Paint()..color = color.withValues(alpha: 0.18),
      );
      canvas.drawCircle(
        groundBeacon,
        14.0 * depthScale,
        Paint()
          ..color = color.withValues(alpha: 0.62)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );

      // Render mô hình Xe máy Giao hàng 3D thật (Meshy 10,071-triangle 3D Mesh) bám chuẩn 100% hướng tiếp tuyến lộ trình
      final scooterCenter = Offset(
        groundBeacon.dx,
        groundBeacon.dy - 13.5 * depthScale,
      );
      if (MeshyScooter3dMesh.instance.isLoaded) {
        final scooterPitch = (0.44 + parallaxY * 0.07).clamp(0.24, 0.72);
        final scooterYaw = MeshyScooter3dMesh.yawForScreenTangent(
          tangentDx,
          tangentDy,
          pitchRadians: scooterPitch,
        );
        MeshyScooter3dMesh.instance.renderToCanvas(
          canvas,
          center: scooterCenter,
          scalePx: 28.0 * depthScale,
          yawRadians: scooterYaw,
          pitchRadians: scooterPitch,
        );
      } else {
        canvas.drawCircle(
          scooterCenter,
          6.5 * depthScale,
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant Studio3dMainWorkspaceMapPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.parallaxX != parallaxX ||
        oldDelegate.parallaxY != parallaxY ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.lightweightBackdrop != lightweightBackdrop;
  }
}



