import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/config/env_config.dart';
import '../../core/gps/smart_dispatch_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/geo_math.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import 'animated_3d_ui_icons.dart';

class ScooterRouteSample3d {
  final double worldX;
  final double worldZ;
  final double tangentX;
  final double tangentZ;
  final List<(double, double)> trailPoints;

  const ScooterRouteSample3d({
    required this.worldX,
    required this.worldZ,
    required this.tangentX,
    required this.tangentZ,
    required this.trailPoints,
  });
}

/// Bộ nạp & kết xuất GPU trực tiếp mô hình 3D Xe máy Giao hàng (Meshy 3D GLB/MSH3 - 4.380 đỉnh / 10.071 đa giác)
class MeshyScooter3dMesh {
  static final MeshyScooter3dMesh instance = MeshyScooter3dMesh._();
  MeshyScooter3dMesh._();

  /// Mô hình scooter_mesh_3d.bin có bánh trước + đèn pha hướng theo trục -X cục bộ,
  /// thùng hàng phía sau tại +X, trục đứng +Y, độ sâu +Z hướng ra phía camera.
  /// Hàm này giải chính xác góc yawRadians sao cho trục dọc xe (từ đuôi tới mũi)
  /// chiếu lên mặt phẳng màn hình trùng khít 100% với vector chuyển động (tangentDx, tangentDy).
  static double yawForScreenTangent(
    double tangentDx,
    double tangentDy, {
    required double pitchRadians,
  }) {
    if (tangentDx.abs() < 1e-6 && tangentDy.abs() < 1e-6) {
      return math.pi;
    }
    final sinPitch = math.sin(pitchRadians);
    final effectiveSinPitch = sinPitch.abs() < 0.08
        ? (sinPitch < 0 ? -0.08 : 0.08)
        : sinPitch;
    return math.atan2(tangentDy / effectiveSinPitch, -tangentDx);
  }

  /// Làm mượt các góc cua gấp của lộ trình 3D bằng đường cong Bezier bậc 2 liên tục tiếp tuyến (C1)
  static List<(double, double)> buildSmoothFilletedRoute3D(
    List<(double, double)> waypoints, {
    int cornerSteps = 8,
    double filletRatio = 0.28,
  }) {
    if (waypoints.length <= 2) {
      return List<(double, double)>.from(waypoints);
    }
    final out = <(double, double)>[waypoints.first];
    for (var i = 1; i < waypoints.length - 1; i++) {
      final prev = waypoints[i - 1];
      final curr = waypoints[i];
      final next = waypoints[i + 1];

      final inDx = curr.$1 - prev.$1;
      final inDz = curr.$2 - prev.$2;
      final inLen = math.sqrt(inDx * inDx + inDz * inDz);

      final outDx = next.$1 - curr.$1;
      final outDz = next.$2 - curr.$2;
      final outLen = math.sqrt(outDx * outDx + outDz * outDz);

      if (inLen < 1e-4 || outLen < 1e-4) {
        out.add(curr);
        continue;
      }

      final cutDist = filletRatio * math.min(inLen, outLen);
      final entryX = curr.$1 - (inDx / inLen) * cutDist;
      final entryZ = curr.$2 - (inDz / inLen) * cutDist;
      final exitX = curr.$1 + (outDx / outLen) * cutDist;
      final exitZ = curr.$2 + (outDz / outLen) * cutDist;

      for (var s = 0; s <= cornerSteps; s++) {
        final u = s / cornerSteps;
        final inv = 1.0 - u;
        final bx = inv * inv * entryX + 2.0 * inv * u * curr.$1 + u * u * exitX;
        final bz = inv * inv * entryZ + 2.0 * inv * u * curr.$2 + u * u * exitZ;
        out.add((bx, bz));
      }
    }
    out.add(waypoints.last);
    return out;
  }

  /// Nội suy theo độ dài cung thực tế (Arc-Length) để xe chạy đều tốc độ và có vector tiếp tuyến mượt liên tục
  static ScooterRouteSample3d sampleRouteArcLength3D(
    List<(double, double)> curvePts,
    double progress01, {
    double trailWorldLength = 88.0,
    int trailSteps = 5,
  }) {
    if (curvePts.isEmpty) {
      return const ScooterRouteSample3d(
        worldX: 0,
        worldZ: 0,
        tangentX: 1,
        tangentZ: 0,
        trailPoints: [(0, 0)],
      );
    }
    if (curvePts.length == 1) {
      final only = curvePts.first;
      return ScooterRouteSample3d(
        worldX: only.$1,
        worldZ: only.$2,
        tangentX: 1,
        tangentZ: 0,
        trailPoints: [only],
      );
    }

    final n = curvePts.length;
    final cumDist = List<double>.filled(n, 0.0);
    for (var i = 1; i < n; i++) {
      final dx = curvePts[i].$1 - curvePts[i - 1].$1;
      final dz = curvePts[i].$2 - curvePts[i - 1].$2;
      cumDist[i] = cumDist[i - 1] + math.sqrt(dx * dx + dz * dz);
    }
    final totalLen = cumDist.last;
    if (totalLen < 1e-4) {
      final first = curvePts.first;
      return ScooterRouteSample3d(
        worldX: first.$1,
        worldZ: first.$2,
        tangentX: 1,
        tangentZ: 0,
        trailPoints: [first],
      );
    }

    (double, double, double, double) evalAtDistance(double s) {
      final clampedS = s.clamp(0.0, totalLen);
      var idx = 0;
      while (idx < n - 2 && cumDist[idx + 1] < clampedS) {
        idx++;
      }
      final segStart = cumDist[idx];
      final segLen = cumDist[idx + 1] - segStart;
      final localU = segLen > 1e-6 ? ((clampedS - segStart) / segLen).clamp(0.0, 1.0) : 0.0;
      final px = curvePts[idx].$1 + (curvePts[idx + 1].$1 - curvePts[idx].$1) * localU;
      final pz = curvePts[idx].$2 + (curvePts[idx + 1].$2 - curvePts[idx].$2) * localU;

      double tx = curvePts[idx + 1].$1 - curvePts[idx].$1;
      double tz = curvePts[idx + 1].$2 - curvePts[idx].$2;
      final norm = math.sqrt(tx * tx + tz * tz);
      if (norm > 1e-6) {
        tx /= norm;
        tz /= norm;
      } else {
        tx = 1.0;
        tz = 0.0;
      }
      return (px, pz, tx, tz);
    }

    final targetS = progress01.clamp(0.0, 1.0) * totalLen;
    final cur = evalAtDistance(targetS);
    // Làm mượt tiếp tuyến bằng cửa sổ tiến-lùi nhỏ dọc theo cung để xe vào cua cực êm
    final ahead = evalAtDistance(targetS + math.min(18.0, totalLen * 0.02));
    final behind = evalAtDistance(targetS - math.min(18.0, totalLen * 0.02));
    var smoothTx = ahead.$1 - behind.$1;
    var smoothTz = ahead.$2 - behind.$2;
    final smoothNorm = math.sqrt(smoothTx * smoothTx + smoothTz * smoothTz);
    if (smoothNorm > 1e-5) {
      smoothTx /= smoothNorm;
      smoothTz /= smoothNorm;
    } else {
      smoothTx = cur.$3;
      smoothTz = cur.$4;
    }

    final trailPts = <(double, double)>[];
    final startTrailS = math.max(0.0, targetS - trailWorldLength);
    for (var k = 0; k <= trailSteps; k++) {
      final ts = startTrailS + (targetS - startTrailS) * (k / trailSteps);
      final pt = evalAtDistance(ts);
      trailPts.add((pt.$1, pt.$2));
    }

    return ScooterRouteSample3d(
      worldX: cur.$1,
      worldZ: cur.$2,
      tangentX: smoothTx,
      tangentZ: smoothTz,
      trailPoints: trailPts,
    );
  }

  bool _isLoaded = false;
  bool _isLoading = false;
  final List<VoidCallback> _pendingCallbacks = [];
  int _numVerts = 0;
  int _numTris = 0;

  late Float32List _vx;
  late Float32List _vy;
  late Float32List _vz;
  late Float32List _nx;
  late Float32List _ny;
  late Float32List _nz;
  late Uint16List _triI0;
  late Uint16List _triI1;
  late Uint16List _triI2;
  late Uint8List _triR;
  late Uint8List _triG;
  late Uint8List _triB;

  late Float32List _projX;
  late Float32List _projY;
  late Float32List _projZ;
  late Float32List _vShade;
  late Int32List _bucketHeads;
  late Int32List _nextInBucket;
  late Float32List _gpuPositions;
  late Int32List _gpuColors;

  bool get isLoaded => _isLoaded;
  int get vertexCount => _numVerts;
  int get triangleCount => _numTris;

  Future<void> ensureLoaded({VoidCallback? onReady}) async {
    if (_isLoaded) {
      onReady?.call();
      return;
    }
    if (onReady != null) {
      _pendingCallbacks.add(onReady);
    }
    if (_isLoading) return;
    _isLoading = true;
    try {
      final byteData =
          await rootBundle.load('assets/icons_3d/scooter_mesh_3d.bin');
      final bd = byteData.buffer.asByteData(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      if (bd.lengthInBytes < 12) return;
      final m0 = bd.getUint8(0);
      final m1 = bd.getUint8(1);
      final m2 = bd.getUint8(2);
      final m3 = bd.getUint8(3);
      if (m0 != 0x4D || m1 != 0x53 || m2 != 0x48 || m3 != 0x33) return;

      final nVerts = bd.getUint32(4, Endian.little);
      final nTris = bd.getUint32(8, Endian.little);
      _vx = Float32List(nVerts);
      _vy = Float32List(nVerts);
      _vz = Float32List(nVerts);
      _nx = Float32List(nVerts);
      _ny = Float32List(nVerts);
      _nz = Float32List(nVerts);

      var offset = 12;
      for (var i = 0; i < nVerts; i++) {
        _vx[i] = bd.getFloat32(offset, Endian.little);
        _vy[i] = bd.getFloat32(offset + 4, Endian.little);
        _vz[i] = bd.getFloat32(offset + 8, Endian.little);
        _nx[i] = bd.getFloat32(offset + 12, Endian.little);
        _ny[i] = bd.getFloat32(offset + 16, Endian.little);
        _nz[i] = bd.getFloat32(offset + 20, Endian.little);
        offset += 28;
      }

      _triI0 = Uint16List(nTris);
      _triI1 = Uint16List(nTris);
      _triI2 = Uint16List(nTris);
      _triR = Uint8List(nTris);
      _triG = Uint8List(nTris);
      _triB = Uint8List(nTris);

      for (var t = 0; t < nTris; t++) {
        _triI0[t] = bd.getUint16(offset, Endian.little);
        _triI1[t] = bd.getUint16(offset + 2, Endian.little);
        _triI2[t] = bd.getUint16(offset + 4, Endian.little);
        _triR[t] = bd.getUint8(offset + 6);
        _triG[t] = bd.getUint8(offset + 7);
        _triB[t] = bd.getUint8(offset + 8);
        offset += 10;
      }

      _projX = Float32List(nVerts);
      _projY = Float32List(nTris > nVerts ? nVerts : nVerts);
      _projZ = Float32List(nVerts);
      _vShade = Float32List(nVerts);
      _bucketHeads = Int32List(96);
      _nextInBucket = Int32List(nTris);
      _gpuPositions = Float32List(nTris * 6);
      _gpuColors = Int32List(nTris * 3);

      _numVerts = nVerts;
      _numTris = nTris;
      _isLoaded = true;
      final callbacks = List<VoidCallback>.from(_pendingCallbacks);
      _pendingCallbacks.clear();
      for (final cb in callbacks) {
        cb();
      }
    } catch (_) {
      _pendingCallbacks.clear();
    } finally {
      _isLoading = false;
    }
  }

  static final Paint _sharedVertexPaint = Paint();
  final Map<int, ui.Vertices> _unitVerticesCache = <int, ui.Vertices>{};

  void renderToCanvas(
    Canvas canvas, {
    required Offset center,
    required double scalePx,
    required double yawRadians,
    required double pitchRadians,
  }) {
    if (!_isLoaded || _numTris == 0 || scalePx <= 0.1) return;

    const twoPi = math.pi * 2.0;
    final normYaw = ((yawRadians % twoPi) + twoPi) % twoPi;
    final yawBucket = ((normYaw / twoPi) * 72.0).round() % 72;
    final clampedPitch = pitchRadians.clamp(-1.2, 1.2);
    final pitchBucket = (((clampedPitch + 1.2) / 2.4) * 32.0).round();
    final cacheKey = (yawBucket << 8) | pitchBucket;

    ui.Vertices? unitVerts = _unitVerticesCache.remove(cacheKey);
    if (unitVerts != null) {
      _unitVerticesCache[cacheKey] = unitVerts;
    } else {
      final qYaw = (yawBucket / 72.0) * twoPi;
      final qPitch = -1.2 + (pitchBucket / 32.0) * 2.4;
      final cy = math.cos(qYaw);
      final sy = math.sin(qYaw);
      final cp = math.cos(qPitch);
      final sp = math.sin(qPitch);

      double minZ = 1e9;
      double maxZ = -1e9;

      for (var i = 0; i < _numVerts; i++) {
        final x = _vx[i];
        final y = _vy[i];
        final z = _vz[i];

        final x1 = x * cy + z * sy;
        final z1 = -x * sy + z * cy;
        final y2 = y * cp - z1 * sp;
        final z2 = y * sp + z1 * cp;

        _projX[i] = x1;
        _projY[i] = -y2;
        _projZ[i] = z2;
        if (z2 < minZ) minZ = z2;
        if (z2 > maxZ) maxZ = z2;

        final nx1 = _nx[i] * cy + _nz[i] * sy;
        final nz1 = -_nx[i] * sy + _nz[i] * cy;
        final ny2 = _ny[i] * cp - nz1 * sp;
        final nz2 = _ny[i] * sp + nz1 * cp;
        final dot = nx1 * 0.35 + ny2 * 0.55 + nz2 * 0.75;
        _vShade[i] = 0.68 + 0.38 * (dot > 0.0 ? dot : 0.0);
      }

      for (var b = 0; b < 96; b++) {
        _bucketHeads[b] = -1;
      }

      final zSpan = (maxZ - minZ) > 1e-5 ? (maxZ - minZ) : 1.0;
      for (var t = 0; t < _numTris; t++) {
        final i0 = _triI0[t];
        final i1 = _triI1[t];
        final i2 = _triI2[t];
        final tz = (_projZ[i0] + _projZ[i1] + _projZ[i2]) * 0.333333;
        var bIdx = (((tz - minZ) / zSpan) * 95.0).floor();
        if (bIdx < 0) bIdx = 0;
        if (bIdx > 95) bIdx = 95;
        _nextInBucket[t] = _bucketHeads[bIdx];
        _bucketHeads[bIdx] = t;
      }

      var outP = 0;
      var outC = 0;
      for (var b = 0; b < 96; b++) {
        var t = _bucketHeads[b];
        while (t != -1) {
          final i0 = _triI0[t];
          final i1 = _triI1[t];
          final i2 = _triI2[t];

          _gpuPositions[outP++] = _projX[i0];
          _gpuPositions[outP++] = _projY[i0];
          _gpuPositions[outP++] = _projX[i1];
          _gpuPositions[outP++] = _projY[i1];
          _gpuPositions[outP++] = _projX[i2];
          _gpuPositions[outP++] = _projY[i2];

          final shade = (_vShade[i0] + _vShade[i1] + _vShade[i2]) * 0.333333;
          final cr = (_triR[t] * shade).round().clamp(0, 255);
          final cg = (_triG[t] * shade).round().clamp(0, 255);
          final cb = (_triB[t] * shade).round().clamp(0, 255);
          final argb = (0xFF << 24) | (cr << 16) | (cg << 8) | cb;

          _gpuColors[outC++] = argb;
          _gpuColors[outC++] = argb;
          _gpuColors[outC++] = argb;

          t = _nextInBucket[t];
        }
      }

      unitVerts = ui.Vertices.raw(
        ui.VertexMode.triangles,
        _gpuPositions,
        colors: _gpuColors,
      );
      if (_unitVerticesCache.length >= 28) {
        final oldestKey = _unitVerticesCache.keys.first;
        final evicted = _unitVerticesCache.remove(oldestKey);
        evicted?.dispose();
      }
      _unitVerticesCache[cacheKey] = unitVerts;
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scalePx, scalePx);
    canvas.drawVertices(unitVerts, BlendMode.dst, _sharedVertexPaint);
    canvas.restore();
  }
}

/// Chế độ hiển thị Bản đồ theo đúng ngữ cảnh từng vai trò sau khi đăng nhập
enum MapViewMode {
  /// Khách hàng xem trước lộ trình khi tạo đơn (ẩn đồng hồ tốc độ km/h & mũi tên buồng lái tài xế)
  customerPreview,

  /// Khách hàng theo dõi trực tiếp tài xế đang giao đơn
  customerLiveTracking,

  /// Tài xế bật Online Radar chờ nhận đơn xung quanh bán kính 3km - 8km
  driverRadar,

  /// Tài xế điều hướng Turn-by-Turn 3D Pitch 55°
  driverTurnByTurn,

  /// Cửa hàng B2B & Quản trị viên giám sát đa tài xế / đa vận đơn trên toàn thành phố
  fleetOverview,
}

/// Onboarding Screen ("Giao hàng siêu tốc 30 phút") theo phong cách Studio nghienai.click
class OnboardingStateScreen extends StatelessWidget {
  final VoidCallback onGetStarted;

  const OnboardingStateScreen({super.key, required this.onGetStarted});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.techBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.line),
                  boxShadow: AppColors.elevatedShadow,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.techBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.techLine),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Animated3dIconBadge(
                              style: Icon3dStyle.scooterExpress,
                              size: 124,
                              showRadarPulse: true,
                              isSelected: true,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.techPanel,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppColors.techLine),
                              ),
                              child: const Text(
                                'FLASH DELIVERY 3D GPS',
                                style: TextStyle(
                                  color: AppColors.acid,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'Consolas',
                                  fontSize: 12,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Giao hàng siêu tốc 30 phút',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Cam kết giao đến tay bạn chỉ trong vòng 30 phút. Định vị GPS 3D thời gian thực, nhanh chóng, tiện lợi mọi nơi.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 26,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.line,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.line,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: onGetStarted,
                        child: const Text('Bắt đầu ngay ↗'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty State ("Bạn chưa có đơn hàng nào!")
class EmptyOrdersStateWidget extends StatelessWidget {
  final VoidCallback onCreateOrder;

  const EmptyOrdersStateWidget({super.key, required this.onCreateOrder});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Animated3dIconBadge(
              style: Icon3dStyle.parcelBox,
              size: 108,
              showRadarPulse: true,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Bạn chưa có đơn hàng nào!',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Khám phá các dịch vụ giao hàng thông minh ngay hôm nay',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.violet,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              ),
              onPressed: onCreateOrder,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Tạo đơn hàng ngay'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Offline Banner & Local GPS Queue Card (Theo phong cách .wallet-sync nghienai.click)
class OfflineQueueBanner extends StatelessWidget {
  final AppStateStore store;

  const OfflineQueueBanner({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    if (!store.isOfflineMode) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.warningInk.withValues(alpha: 0.28),
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.techBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'CHẾ ĐỘ NGOẠI TUYẾN • Thao tác và vị trí đang lưu tạm trên thiết bị · ${store.offlineQueueCount} mục chờ đồng bộ',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.acid,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 44,
                      color: AppColors.ink,
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.add_location_alt_outlined,
                      size: 28,
                      color: AppColors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Mất kết nối mạng\ninternet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Đừng lo lắng! Tọa độ GPS và thao tác của bạn đang được lưu tạm trên máy. Vui lòng kiểm tra lại 4G/Wi-Fi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => store.toggleOfflineSimulation(false),
                    child: const Text(
                      'Thử kết nối lại ↗',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer Skeleton Loading List
class SkeletonOrderListWidget extends StatelessWidget {
  const SkeletonOrderListWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: AppColors.shimmerBase,
                    borderRadius: BorderRadius.all(Radius.zero),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 140,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: AppColors.shimmerBase,
                          borderRadius: BorderRadius.all(Radius.zero),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: AppColors.shimmerHighlight,
                          borderRadius: BorderRadius.all(Radius.zero),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 100,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: AppColors.shimmerBase,
                          borderRadius: BorderRadius.all(Radius.zero),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Bản đồ Tương tác Google Maps Web Mercator (EPSG:3857) + Định tuyến OSRM & Vùng địa lý thực tế
class Map3dPerspectiveWidget extends StatefulWidget {
  final String nextTurnInstruction;
  final String roadName;
  final double speedKmh;
  final bool is3dMode;
  final VoidCallback? onToggle3d;
  final double height;
  final bool expandToParent;
  final double progressFraction;
  final GeoPoint? driverLocation;
  final ValueChanged<Offset>? onTapRelativePoint;
  final ValueChanged<GeoPoint>? onTapGeoPoint;
  final List<Offset> drawnPolygonPoints;
  final List<GeoPoint> drawnPolygonGeoPoints;
  final List<GeofenceZoneRecord> geofenceZones;
  final GeoPoint? singlePinPoint;
  final String? singlePinLabel;
  final GeoPoint? focusedCenterPoint;
  final List<DriverApplicantRecord>? customFleetDrivers;
  final List<ActiveOrderRecord> nearbySearchingOrders;
  final List<GeoPoint> routePoints;
  final bool useGlobalFallbackRoute;
  final MapViewMode mode;
  final bool showTopBanner;
  final bool isFullScreenBackground;
  final String? pickupLabel;
  final String? dropoffLabel;

  const Map3dPerspectiveWidget({
    super.key,
    this.nextTurnInstruction = '',
    this.roadName = '',
    this.speedKmh = 0.0,
    this.is3dMode = false,
    this.onToggle3d,
    this.height = 460,
    this.expandToParent = false,
    this.progressFraction = 0.0,
    this.driverLocation,
    this.onTapRelativePoint,
    this.onTapGeoPoint,
    this.drawnPolygonPoints = const [],
    this.drawnPolygonGeoPoints = const [],
    this.geofenceZones = const [],
    this.singlePinPoint,
    this.singlePinLabel,
    this.focusedCenterPoint,
    this.customFleetDrivers,
    this.nearbySearchingOrders = const [],
    this.routePoints = const [],
    this.useGlobalFallbackRoute = false,
    this.mode = MapViewMode.customerPreview,
    this.showTopBanner = true,
    this.isFullScreenBackground = false,
    this.pickupLabel,
    this.dropoffLabel,
  });

  @override
  State<Map3dPerspectiveWidget> createState() => _Map3dPerspectiveWidgetState();
}

class _Map3dPerspectiveWidgetState extends State<Map3dPerspectiveWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  double _cameraYawOffset = 0.0;
  double _cameraPitchOffset = 0.0;
  double _manualYawRadians = 0.0;
  double _manualPitchRadians = -0.38;
  bool? _local3dOverride;
  int _zoomLevel = 15;
  int? _previousZoomLevel;
  bool _userAdjustedZoom = false;
  Offset _panPixelOffset = Offset.zero;
  Offset? _scaleLastFocalPoint;
  Offset? _doubleTapPosition;
  int _scaleStartZoom = 15;
  double _pinchVisualScale = 1.0;
  Offset _pinchFocalPoint = Offset.zero;
  GeoPoint? _customCenterGeoOverride;
  GeoPoint? _lastKnownLiveDeviceLocation;
  String _googleLayer = 'm';
  List<GeoPoint>? _liveOsrmRoutePoints;
  String _lastFetchedRouteKey = '';
  String _lastCameraTargetSignature = '';

  bool get _effective3d => _local3dOverride ?? widget.is3dMode;

  bool get _isAutomatedTestBinding {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTest');
  }

  List<DriverApplicantRecord> get _effectiveFleetDrivers {
    final store = AppStateStore.instance;
    return (widget.customFleetDrivers ?? store.drivers)
        .where((d) => d.approvalStatus == 'Đã duyệt' &&
            store.verifiedDriverLocations.containsKey(d.id))
        .toList();
  }

  List<GeoPoint> _resolveBaseRoute() {
    if (widget.singlePinPoint != null) {
      return const <GeoPoint>[];
    }
    if (widget.routePoints.length >= 2) {
      return widget.routePoints;
    }
    if (widget.useGlobalFallbackRoute &&
        AppStateStore.instance.activeRoutePolyline.length >= 2) {
      return AppStateStore.instance.activeRoutePolyline;
    }
    return const <GeoPoint>[];
  }

  bool get _shouldAnimateMapContinuously {
    if (_isAutomatedTestBinding || widget.isFullScreenBackground) {
      return false;
    }
    if (widget.mode == MapViewMode.customerLiveTracking ||
        widget.mode == MapViewMode.driverTurnByTurn) {
      return true;
    }
    if (widget.mode == MapViewMode.driverRadar) {
      return AppStateStore.instance.isDriverOnline;
    }
    return _resolveBaseRoute().length >= 2;
  }

  void _syncMapAnimationTicker() {
    if (_isAutomatedTestBinding) return;
    if (_shouldAnimateMapContinuously) {
      if (!_animController.isAnimating) {
        _animController.repeat();
      }
    } else {
      if (_animController.isAnimating) {
        _animController.stop();
      }
      _animController.value = 0.25;
    }
  }

  void _applyZoom(
    int targetZoom, {
    Offset? anchor,
    Size? viewSize,
    bool userInitiated = true,
  }) {
    final clamped = targetZoom.clamp(5, 20);
    if (clamped == _zoomLevel) {
      if (userInitiated) _userAdjustedZoom = true;
      return;
    }
    final prev = _zoomLevel;
    final factor = math.pow(2.0, (clamped - prev).toDouble()).toDouble();
    _previousZoomLevel = prev;
    if (anchor != null &&
        viewSize != null &&
        viewSize.width > 0 &&
        viewSize.height > 0) {
      final deltaFromCenter =
          anchor - Offset(viewSize.width * 0.5, viewSize.height * 0.5);
      _panPixelOffset =
          _panPixelOffset * factor + deltaFromCenter * (1.0 - factor);
    } else {
      _panPixelOffset *= factor;
    }
    _zoomLevel = clamped;
    if (userInitiated) _userAdjustedZoom = true;
  }

  @override
  void initState() {
    super.initState();
    _lastKnownLiveDeviceLocation = AppStateStore.instance.liveDeviceLocation;
    _zoomLevel = _computeInitialAutoZoom();
    _lastCameraTargetSignature = _buildTargetSignature();
    AppStateStore.instance.addListener(_onStoreLiveGpsUpdated);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
      value: 0.25,
    );
    if (!_isAutomatedTestBinding) {
      _syncMapAnimationTicker();
      _ensureLiveOsrmStreetRoute();
      if (_shouldAnimateMapContinuously) {
        MeshyScooter3dMesh.instance.ensureLoaded(
          onReady: () {
            if (mounted) setState(() {});
          },
        );
      }
    } else {
      _animController.forward(from: 0.0);
    }
  }

  void _onStoreLiveGpsUpdated() {
    if (!mounted) return;
    final nextLive = AppStateStore.instance.liveDeviceLocation;
    final prevLive = _lastKnownLiveDeviceLocation;
    _lastKnownLiveDeviceLocation = nextLive;
    if (nextLive != null &&
        _customCenterGeoOverride != null &&
        prevLive != null &&
        GeoMath.distanceMeters(_customCenterGeoOverride!, prevLive) < 25.0) {
      _customCenterGeoOverride = nextLive;
    }
    _syncMapAnimationTicker();
    setState(() {});
  }

  Future<void> _handleFocusMyRealGps(
    BuildContext context, {
    void Function(GeoPoint livePos)? onAcquiredForModal,
  }) async {
    final store = AppStateStore.instance;
    final syncDriver = widget.mode == MapViewMode.driverRadar ||
        widget.mode == MapViewMode.driverTurnByTurn;
    final livePos = await store.startRealTimeDeviceGpsTracking(
      syncDriverLocation: syncDriver,
      forcePromptPermission: true,
    );
    if (!mounted) return;
    if (livePos != null) {
      setState(() {
        _customCenterGeoOverride = livePos;
        _panPixelOffset = Offset.zero;
        _manualYawRadians = 0.0;
        _pinchVisualScale = 1.0;
        if (!_userAdjustedZoom && _zoomLevel < 16) {
          _previousZoomLevel = _zoomLevel;
          _zoomLevel = 16;
        }
      });
      onAcquiredForModal?.call(livePos);
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(store.liveGpsStatusMessage),
          action: SnackBarAction(
            label: 'Mở Cài đặt',
            textColor: AppColors.acid,
            onPressed: () {
              unawaited(store.openDeviceLocationSettings());
            },
          ),
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant Map3dPerspectiveWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.is3dMode != widget.is3dMode) {
      _local3dOverride = null;
    }
    final nextSig = _buildTargetSignature();
    if (nextSig != _lastCameraTargetSignature) {
      _lastCameraTargetSignature = nextSig;
      _customCenterGeoOverride = null;
      _userAdjustedZoom = false;
      _panPixelOffset = Offset.zero;
      _zoomLevel = _computeInitialAutoZoom();
    }
    if (!_isAutomatedTestBinding) {
      _syncMapAnimationTicker();
      _ensureLiveOsrmStreetRoute();
    }
  }

  String _buildTargetSignature() {
    final base = _resolveBaseRoute();
    final routeKey = base.length >= 2
        ? '${base.first.latitude.toStringAsFixed(4)},${base.first.longitude.toStringAsFixed(4)}->${base.last.latitude.toStringAsFixed(4)},${base.last.longitude.toStringAsFixed(4)}'
        : 'none';
    final pinKey = widget.singlePinPoint != null
        ? '${widget.singlePinPoint!.latitude.toStringAsFixed(4)},${widget.singlePinPoint!.longitude.toStringAsFixed(4)}'
        : 'nopin';
    final focusKey = widget.focusedCenterPoint != null
        ? '${widget.focusedCenterPoint!.latitude.toStringAsFixed(4)},${widget.focusedCenterPoint!.longitude.toStringAsFixed(4)}'
        : 'nofocus';
    return '${widget.mode.name}|$routeKey|$pinKey|$focusKey|${widget.geofenceZones.length}';
  }

  int _computeInitialAutoZoom({Size? viewport}) {
    final pts = <GeoPoint>[];
    final base = _resolveBaseRoute();
    if (_liveOsrmRoutePoints != null && _liveOsrmRoutePoints!.length >= 2) {
      pts.addAll(_liveOsrmRoutePoints!);
    } else if (base.length >= 2) {
      pts.addAll(base);
    } else if (widget.singlePinPoint != null ||
        widget.focusedCenterPoint != null) {
      return widget.mode == MapViewMode.driverRadar ? 15 : 16;
    } else if (widget.geofenceZones.isNotEmpty) {
      for (final z in widget.geofenceZones) {
        if (z.isActive) pts.addAll(z.boundary);
      }
    } else if (widget.mode == MapViewMode.fleetOverview) {
      for (final d in _effectiveFleetDrivers) {
        pts.add(d.location);
      }
    } else if (widget.mode == MapViewMode.driverRadar) {
      return 15;
    }

    if (pts.length < 2) {
      return widget.mode == MapViewMode.fleetOverview ? 13 : 15;
    }

    double minLat = pts.first.latitude;
    double maxLat = pts.first.latitude;
    double minLng = pts.first.longitude;
    double maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    if ((maxLat - minLat).abs() < 0.0005 && (maxLng - minLng).abs() < 0.0005) {
      return 16;
    }
    final targetW = (viewport != null && viewport.width > 120)
        ? viewport.width * 0.68
        : 520.0;
    final targetH = (viewport != null && viewport.height > 120)
        ? viewport.height * 0.62
        : 320.0;
    for (var z = 16; z >= 6; z--) {
      final dx = (_lonToWorldX(maxLng, z) - _lonToWorldX(minLng, z)).abs();
      final dy = (_latToWorldY(minLat, z) - _latToWorldY(maxLat, z)).abs();
      if (dx <= targetW && dy <= targetH) {
        return z;
      }
    }
    return 6;
  }

  Future<void> _ensureLiveOsrmStreetRoute() async {
    final baseRoute = _resolveBaseRoute();
    if (baseRoute.length < 2) {
      if (_liveOsrmRoutePoints != null) {
        setState(() => _liveOsrmRoutePoints = null);
      }
      return;
    }
    final start = baseRoute.first;
    final end = baseRoute.last;
    final key =
        '${start.latitude.toStringAsFixed(4)},${start.longitude.toStringAsFixed(4)}_${end.latitude.toStringAsFixed(4)},${end.longitude.toStringAsFixed(4)}';
    if (key == _lastFetchedRouteKey) return;
    _lastFetchedRouteKey = key;
    if (baseRoute.length > 16) {
      _liveOsrmRoutePoints = null;
      return;
    }
    final res = await SmartDispatchEngine.fetchLiveOsrmRoute(start, end);
    if (!mounted) return;
    if (res.polylinePoints.length >= 2) {
      setState(() {
        _liveOsrmRoutePoints = res.polylinePoints;
        if (!_userAdjustedZoom) {
          _zoomLevel = _computeInitialAutoZoom();
        }
      });
    }
  }

  void _handleToggle3d() {
    setState(() {
      _local3dOverride = !_effective3d;
    });
    widget.onToggle3d?.call();
  }

  Offset _unproject3dLocalPosition(
    Offset localPos,
    Size viewSize, {
    required bool is3d,
    required double pitchRadians,
    required double yawRadians,
  }) {
    if (!is3d) return localPos;
    final cx = viewSize.width * 0.5;
    final cy = viewSize.height * 0.5;
    final sx = localPos.dx - cx;
    final sy = localPos.dy - cy;
    const persp = 0.0012;
    const scale3d = 1.14;
    final cosP = math.cos(pitchRadians);
    final sinP = math.sin(pitchRadians);
    final denom = cosP - persp * sy * sinP;
    if (denom.abs() < 1e-5) return localPos;
    final y1 = sy / denom;
    final w = 1.0 + persp * y1 * sinP;
    final x1 = sx * w;
    final cosY = math.cos(yawRadians);
    final sinY = math.sin(yawRadians);
    final x0 = (x1 * cosY + y1 * sinY) / scale3d;
    final y0 = (-x1 * sinY + y1 * cosY) / scale3d;
    return Offset(cx + x0, cy + y0);
  }

  GeoPoint _screenOffsetToGeoPoint(
    Offset localPos,
    Size viewSize,
    GeoPoint centerGeo, {
    int? customZoom,
    Offset? customPan,
    bool? customIs3d,
    double? customPitch,
    double? customYaw,
  }) {
    final z = customZoom ?? _zoomLevel;
    final p = customPan ?? _panPixelOffset;
    final is3d = customIs3d ?? _effective3d;
    final pitch = customPitch ?? (_manualPitchRadians + _cameraPitchOffset);
    final yaw = customYaw ?? (_manualYawRadians + _cameraYawOffset);
    final canvasPos = _unproject3dLocalPosition(
      localPos,
      viewSize,
      is3d: is3d,
      pitchRadians: pitch,
      yawRadians: yaw,
    );
    final centerWorldX = _lonToWorldX(centerGeo.longitude, z) - p.dx;
    final centerWorldY = _latToWorldY(centerGeo.latitude, z) - p.dy;
    final targetWorldX = centerWorldX + (canvasPos.dx - viewSize.width * 0.5);
    final targetWorldY = centerWorldY + (canvasPos.dy - viewSize.height * 0.5);
    return GeoPoint(
      latitude: _worldYToLat(targetWorldY, z),
      longitude: _worldXToLon(targetWorldX, z),
    );
  }

  void _openPanoramic3dModal(
    BuildContext context,
    List<GeoPoint> effectiveRoute,
    GeoPoint centerGeo,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        bool modalIs3d = _effective3d;
        double modalPitch = _manualPitchRadians;
        double modalYaw = _manualYawRadians;
        int modalZoom = _zoomLevel;
        String modalLayer = _googleLayer;
        Offset modalPan = _panPixelOffset;
        GeoPoint modalCenterGeo = _customCenterGeoOverride ?? centerGeo;
        Offset? modalLastFocalPoint;
        int modalScaleStartZoom = _zoomLevel;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(14),
              backgroundColor: AppColors.darkSidebar,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: AppColors.techLine),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1280,
                  maxHeight: 840,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      color: AppColors.ink,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.map_rounded,
                            color: AppColors.acid,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.nextTurnInstruction.isNotEmpty
                                  ? widget.nextTurnInstruction
                                  : 'Bản đồ tương tác toàn màn hình',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: modalIs3d
                                  ? AppColors.primary
                                  : Colors.transparent,
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white38),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              setModalState(() => modalIs3d = !modalIs3d);
                              setState(() => _local3dOverride = modalIs3d);
                            },
                            icon: const Icon(Icons.layers_outlined, size: 15),
                            label: Text(
                              modalIs3d ? 'Chế độ 3D' : 'Chế độ 2D',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Đóng bản đồ toàn màn hình',
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, modalConstraints) {
                          final modalDpr = MediaQuery.devicePixelRatioOf(
                            context,
                          );
                          final modalSize = Size(
                            modalConstraints.maxWidth,
                            modalConstraints.maxHeight,
                          );
                          return Listener(
                            onPointerSignal: (signal) {
                              if (signal is PointerScrollEvent) {
                                final delta = signal.scrollDelta.dy < 0
                                    ? 1
                                    : -1;
                                final nextZ = (modalZoom + delta).clamp(5, 20);
                                if (nextZ != modalZoom) {
                                  final factor = math
                                      .pow(2.0, (nextZ - modalZoom).toDouble())
                                      .toDouble();
                                  final d =
                                      signal.localPosition -
                                      Offset(
                                        modalSize.width * 0.5,
                                        modalSize.height * 0.5,
                                      );
                                  setModalState(() {
                                    modalPan =
                                        modalPan * factor + d * (1.0 - factor);
                                    modalZoom = nextZ;
                                  });
                                  setState(() {
                                    _previousZoomLevel = _zoomLevel;
                                    _panPixelOffset = modalPan;
                                    _userAdjustedZoom = true;
                                    _zoomLevel = modalZoom;
                                  });
                                }
                              }
                            },
                            child: GestureDetector(
                              onDoubleTapDown: (d) {
                                _doubleTapPosition = d.localPosition;
                              },
                              onDoubleTap: () {
                                final nextZ = (modalZoom + 1).clamp(5, 20);
                                if (nextZ != modalZoom) {
                                  final factor = math
                                      .pow(2.0, (nextZ - modalZoom).toDouble())
                                      .toDouble();
                                  final anchor =
                                      _doubleTapPosition ??
                                      Offset(
                                        modalSize.width * 0.5,
                                        modalSize.height * 0.5,
                                      );
                                  final d =
                                      anchor -
                                      Offset(
                                        modalSize.width * 0.5,
                                        modalSize.height * 0.5,
                                      );
                                  setModalState(() {
                                    modalPan =
                                        modalPan * factor + d * (1.0 - factor);
                                    modalZoom = nextZ;
                                  });
                                  setState(() {
                                    _previousZoomLevel = _zoomLevel;
                                    _panPixelOffset = modalPan;
                                    _userAdjustedZoom = true;
                                    _zoomLevel = modalZoom;
                                  });
                                }
                              },
                              onScaleStart: (d) {
                                modalLastFocalPoint = d.localFocalPoint;
                                modalScaleStartZoom = modalZoom;
                              },
                              onScaleUpdate: (d) {
                                final focalDelta = modalLastFocalPoint != null
                                    ? (d.localFocalPoint - modalLastFocalPoint!)
                                    : Offset.zero;
                                modalLastFocalPoint = d.localFocalPoint;
                                int nextZoom = modalZoom;
                                if ((d.scale - 1.0).abs() > 0.04) {
                                  final zDelta =
                                      (math.log(d.scale) / math.ln2).round();
                                  nextZoom = (modalScaleStartZoom + zDelta)
                                      .clamp(5, 20);
                                }
                                setModalState(() {
                                  modalPan += focalDelta;
                                  if (nextZoom != modalZoom) {
                                    final factor = math
                                        .pow(
                                          2.0,
                                          (nextZoom - modalZoom).toDouble(),
                                        )
                                        .toDouble();
                                    final anchorDelta =
                                        d.localFocalPoint -
                                        Offset(
                                          modalSize.width * 0.5,
                                          modalSize.height * 0.5,
                                        );
                                    modalPan =
                                        modalPan * factor +
                                        anchorDelta * (1.0 - factor);
                                    modalZoom = nextZoom;
                                  }
                                });
                                setState(() {
                                  _panPixelOffset = modalPan;
                                  if (nextZoom != _zoomLevel) {
                                    _previousZoomLevel = _zoomLevel;
                                    _userAdjustedZoom = true;
                                    _zoomLevel = nextZoom;
                                  }
                                });
                              },
                              onTapUp: (details) {
                                if (widget.onTapGeoPoint != null) {
                                  final geo = _screenOffsetToGeoPoint(
                                    details.localPosition,
                                    modalSize,
                                    modalCenterGeo,
                                    customZoom: modalZoom,
                                    customPan: modalPan,
                                    customIs3d: modalIs3d,
                                    customPitch: modalPitch,
                                    customYaw: modalYaw,
                                  );
                                  widget.onTapGeoPoint!(geo);
                                  setModalState(() {});
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (ctx.mounted) setModalState(() {});
                                  });
                                }
                              },
                              child: AnimatedBuilder(
                                animation: _animController,
                                child: RepaintBoundary(
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CustomPaint(
                                        painter: _Map3dCanvasPainter(
                                          is3dMode: modalIs3d,
                                          progressFraction: widget.progressFraction,
                                          driverLocation: widget.driverLocation,
                                          drawnPolygonPoints:
                                              widget.drawnPolygonPoints,
                                          drawnPolygonGeoPoints:
                                              widget.drawnPolygonGeoPoints,
                                          geofenceZones: widget.geofenceZones,
                                          singlePinPoint: widget.singlePinPoint,
                                          singlePinLabel: widget.singlePinLabel,
                                          liveDeviceLocation: AppStateStore
                                              .instance
                                              .liveDeviceLocation,
                                          liveDeviceAccuracyMeters:
                                              AppStateStore
                                                  .instance
                                                  .liveDeviceAccuracyMeters,
                                          nearbySearchingOrders:
                                              widget.nearbySearchingOrders,
                                          routePoints: effectiveRoute,
                                          animPhase: 0.25,
                                          mode: widget.mode,
                                          zoomLevel: modalZoom,
                                          panPixelOffset: modalPan,
                                          centerGeo: modalCenterGeo,
                                          drawBackgroundOnly: true,
                                          pickupLabel: widget.pickupLabel,
                                          dropoffLabel: widget.dropoffLabel,
                                          fleetDrivers: _effectiveFleetDrivers,
                                        ),
                                      ),
                                      _buildGoogleMapTileLayerCustom(
                                        modalSize,
                                        modalCenterGeo,
                                        zoom: modalZoom,
                                        pan: modalPan,
                                        layer: modalLayer,
                                        devicePixelRatio: modalDpr,
                                        snapToPixelGrid: !modalIs3d,
                                        backdropZoom: _previousZoomLevel,
                                      ),
                                    ],
                                  ),
                                ),
                                builder: (context, staticModalBase) {
                                  final phase = _animController.value;
                                  final matrix3d = Matrix4.identity()
                                    ..setEntry(3, 2, 0.0012)
                                    ..rotateX(modalIs3d ? modalPitch : 0.0)
                                    ..rotateZ(modalIs3d ? modalYaw : 0.0)
                                    ..scaleByDouble(
                                      modalIs3d ? 1.14 : 1.0,
                                      modalIs3d ? 1.14 : 1.0,
                                      1.0,
                                      1.0,
                                    );

                                  return Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Container(color: const Color(0xFF0F172A)),
                                      Transform(
                                        alignment: Alignment.center,
                                        transform: matrix3d,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            staticModalBase!,
                                            CustomPaint(
                                              painter: _Map3dCanvasPainter(
                                                is3dMode: modalIs3d,
                                                progressFraction: widget.progressFraction,
                                                driverLocation: widget.driverLocation,
                                                drawnPolygonPoints:
                                                    widget.drawnPolygonPoints,
                                                drawnPolygonGeoPoints: widget
                                                    .drawnPolygonGeoPoints,
                                                geofenceZones:
                                                    widget.geofenceZones,
                                                singlePinPoint:
                                                    widget.singlePinPoint,
                                                singlePinLabel:
                                                    widget.singlePinLabel,
                                                liveDeviceLocation: AppStateStore
                                                    .instance
                                                    .liveDeviceLocation,
                                                liveDeviceAccuracyMeters:
                                                    AppStateStore.instance
                                                        .liveDeviceAccuracyMeters,
                                                nearbySearchingOrders: widget
                                                    .nearbySearchingOrders,
                                                routePoints: effectiveRoute,
                                                animPhase: phase,
                                                mode: widget.mode,
                                                zoomLevel: modalZoom,
                                                panPixelOffset: modalPan,
                                                centerGeo: modalCenterGeo,
                                                drawBackgroundOnly: false,
                                                showCalloutLabels:
                                                    !widget.isFullScreenBackground,
                                                pickupLabel: widget.pickupLabel,
                                                dropoffLabel:
                                                    widget.dropoffLabel,
                                                fleetDrivers:
                                                    _effectiveFleetDrivers,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Positioned(
                                        top: 12,
                                        left: 12,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          color: AppColors.ink.withValues(
                                            alpha: 0.86,
                                          ),
                                          child: Text(
                                            'Tọa độ tâm: ${modalCenterGeo.latitude.toStringAsFixed(5)}, ${modalCenterGeo.longitude.toStringAsFixed(5)} • Thu phóng: ${modalZoom}x',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                            ),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      color: AppColors.ink,
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Wrap(
                            spacing: 6,
                            children: [
                              ('m', 'Bản đồ'),
                              ('m,traffic', 'Giao thông'),
                              ('y', 'Vệ tinh'),
                              ('p', 'Địa hình'),
                            ].map((item) {
                              final selected = modalLayer == item.$1;
                              return ChoiceChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  item.$2,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: selected
                                        ? Colors.white
                                        : AppColors.ink,
                                  ),
                                ),
                                selected: selected,
                                selectedColor: AppColors.violet,
                                onSelected: (_) {
                                  setModalState(() => modalLayer = item.$1);
                                  setState(() => _googleLayer = item.$1);
                                },
                              );
                            }).toList(),
                          ),
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (modalIs3d) ...[
                                const Text(
                                  'Góc nghiêng:',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11.5,
                                  ),
                                ),
                                SizedBox(
                                  width: 110,
                                  child: Slider(
                                    value: modalPitch,
                                    min: -0.62,
                                    max: 0.0,
                                    activeColor: AppColors.acid,
                                    onChanged: (v) {
                                      setModalState(() => modalPitch = v);
                                      setState(() => _manualPitchRadians = v);
                                    },
                                  ),
                                ),
                              ],
                              IconButton(
                                tooltip: 'Vị trí hiện tại của tôi',
                                onPressed: () => _handleFocusMyRealGps(
                                  ctx,
                                  onAcquiredForModal: (livePos) {
                                    if (!ctx.mounted) return;
                                    setModalState(() {
                                      modalCenterGeo = livePos;
                                      modalPan = Offset.zero;
                                      modalYaw = 0.0;
                                      modalZoom = _zoomLevel;
                                    });
                                  },
                                ),
                                icon: Icon(
                                  Icons.my_location_rounded,
                                  color: AppStateStore
                                          .instance
                                          .hasRealDeviceGpsFix
                                      ? AppColors.acid
                                      : Colors.white,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Căn giữa lộ trình / khung bản đồ',
                                onPressed: () {
                                  setState(() {
                                    _customCenterGeoOverride = null;
                                  });
                                  final autoZ = _computeInitialAutoZoom();
                                  final baseCenter =
                                      _resolveCenterGeo(effectiveRoute);
                                  setModalState(() {
                                    modalCenterGeo = baseCenter;
                                    modalPan = Offset.zero;
                                    modalYaw = 0.0;
                                    modalZoom = autoZ;
                                  });
                                  setState(() {
                                    _previousZoomLevel = _zoomLevel;
                                    _panPixelOffset = Offset.zero;
                                    _manualYawRadians = 0.0;
                                    _userAdjustedZoom = false;
                                    _zoomLevel = autoZ;
                                  });
                                },
                                icon: const Icon(
                                  Icons.center_focus_strong_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Phóng to',
                                onPressed: () {
                                  final nextZ = (modalZoom + 1).clamp(5, 20);
                                  if (nextZ == modalZoom) return;
                                  final factor = math
                                      .pow(2.0, (nextZ - modalZoom).toDouble())
                                      .toDouble();
                                  setModalState(() {
                                    modalPan *= factor;
                                    modalZoom = nextZ;
                                  });
                                  setState(() {
                                    _previousZoomLevel = _zoomLevel;
                                    _panPixelOffset = modalPan;
                                    _userAdjustedZoom = true;
                                    _zoomLevel = modalZoom;
                                  });
                                },
                                icon: const Icon(
                                  Icons.zoom_in,
                                  color: Colors.white,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Thu nhỏ',
                                onPressed: () {
                                  final nextZ = (modalZoom - 1).clamp(5, 20);
                                  if (nextZ == modalZoom) return;
                                  final factor = math
                                      .pow(2.0, (nextZ - modalZoom).toDouble())
                                      .toDouble();
                                  setModalState(() {
                                    modalPan *= factor;
                                    modalZoom = nextZ;
                                  });
                                  setState(() {
                                    _previousZoomLevel = _zoomLevel;
                                    _panPixelOffset = modalPan;
                                    _userAdjustedZoom = true;
                                    _zoomLevel = modalZoom;
                                  });
                                },
                                icon: const Icon(
                                  Icons.zoom_out,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    AppStateStore.instance.removeListener(_onStoreLiveGpsUpdated);
    _animController.dispose();
    super.dispose();
  }

  static double _lonToWorldX(double lon, int zoom) {
    final mapSize = 256.0 * (1 << zoom);
    return ((lon + 180.0) / 360.0) * mapSize;
  }

  static double _latToWorldY(double lat, int zoom) {
    final mapSize = 256.0 * (1 << zoom);
    final sinLat = math.sin(lat * math.pi / 180.0).clamp(-0.9999, 0.9999);
    final mercN = math.log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * math.pi);
    return (0.5 - mercN) * mapSize;
  }

  static double _worldXToLon(double worldX, int zoom) {
    final mapSize = 256.0 * (1 << zoom);
    return ((worldX / mapSize) * 360.0 - 180.0).clamp(-180.0, 180.0);
  }

  static double _worldYToLat(double worldY, int zoom) {
    final mapSize = 256.0 * (1 << zoom);
    final n = math.pi - (2.0 * math.pi * worldY) / mapSize;
    final latRad = math.atan(0.5 * (math.exp(n) - math.exp(-n)));
    return (latRad * 180.0 / math.pi).clamp(-85.0511, 85.0511);
  }

  GeoPoint _resolveCenterGeo(List<GeoPoint> effectiveRoute) {
    if (_customCenterGeoOverride != null) {
      return _customCenterGeoOverride!;
    }
    if (widget.focusedCenterPoint != null) {
      return widget.focusedCenterPoint!;
    }
    if (widget.singlePinPoint != null) {
      return widget.singlePinPoint!;
    }
    if (effectiveRoute.isNotEmpty) {
      double minLat = effectiveRoute.first.latitude;
      double maxLat = effectiveRoute.first.latitude;
      double minLng = effectiveRoute.first.longitude;
      double maxLng = effectiveRoute.first.longitude;
      for (final pt in effectiveRoute) {
        minLat = math.min(minLat, pt.latitude);
        maxLat = math.max(maxLat, pt.latitude);
        minLng = math.min(minLng, pt.longitude);
        maxLng = math.max(maxLng, pt.longitude);
      }
      return GeoPoint(
        latitude: (minLat + maxLat) * 0.5,
        longitude: (minLng + maxLng) * 0.5,
      );
    }
    if (widget.drawnPolygonGeoPoints.isNotEmpty ||
        widget.geofenceZones.isNotEmpty) {
      final pts = <GeoPoint>[
        ...widget.drawnPolygonGeoPoints,
        for (final z in widget.geofenceZones)
          if (z.isActive) ...z.boundary,
      ];
      if (pts.isNotEmpty) {
        double minLat = pts.first.latitude;
        double maxLat = pts.first.latitude;
        double minLng = pts.first.longitude;
        double maxLng = pts.first.longitude;
        for (final pt in pts) {
          minLat = math.min(minLat, pt.latitude);
          maxLat = math.max(maxLat, pt.latitude);
          minLng = math.min(minLng, pt.longitude);
          maxLng = math.max(maxLng, pt.longitude);
        }
        return GeoPoint(
          latitude: (minLat + maxLat) * 0.5,
          longitude: (minLng + maxLng) * 0.5,
        );
      }
    }
    if (widget.mode == MapViewMode.fleetOverview) {
      final drivers = _effectiveFleetDrivers;
      if (drivers.isNotEmpty) {
        double sumLat = 0;
        double sumLng = 0;
        for (final d in drivers) {
          sumLat += d.location.latitude;
          sumLng += d.location.longitude;
        }
        return GeoPoint(
          latitude: sumLat / drivers.length,
          longitude: sumLng / drivers.length,
        );
      }
    }
    if (widget.mode == MapViewMode.driverRadar) {
      return AppStateStore.instance.liveDeviceLocation ??
          AppStateStore.instance.activeDriverLocation;
    }
    return AppStateStore.instance.liveDeviceLocation ??
        const GeoPoint(latitude: 10.7769, longitude: 106.7009);
  }

  Widget _buildGoogleMapTileLayer(
    Size viewSize,
    GeoPoint centerGeo, {
    required double devicePixelRatio,
  }) {
    return _buildGoogleMapTileLayerCustom(
      viewSize,
      centerGeo,
      zoom: _zoomLevel,
      pan: _panPixelOffset,
      layer: _googleLayer,
      hideLabels: widget.isFullScreenBackground,
      devicePixelRatio: devicePixelRatio,
      snapToPixelGrid: !_effective3d && (_pinchVisualScale - 1.0).abs() < 0.002,
      backdropZoom: _previousZoomLevel,
    );
  }

  Widget _buildSingleZoomTileStack(
    Size viewSize,
    GeoPoint centerGeo, {
    required int zoom,
    required Offset pan,
    required String layer,
    required bool hideLabels,
    required double devicePixelRatio,
    required bool snapToPixelGrid,
    String keyPrefix = 'ggtile',
  }) {
    final maxTileIndex = (1 << zoom) - 1;
    final centerWorldX = _lonToWorldX(centerGeo.longitude, zoom) - pan.dx;
    final centerWorldY = _latToWorldY(centerGeo.latitude, zoom) - pan.dy;

    final topLeftWorldX = centerWorldX - viewSize.width * 0.5;
    final topLeftWorldY = centerWorldY - viewSize.height * 0.5;
    final bottomRightWorldX = centerWorldX + viewSize.width * 0.5;
    final bottomRightWorldY = centerWorldY + viewSize.height * 0.5;

    final minTileX = (topLeftWorldX / 256.0).floor();
    final maxTileX = (bottomRightWorldX / 256.0).floor();
    final minTileY = (topLeftWorldY / 256.0).floor();
    final maxTileY = (bottomRightWorldY / 256.0).floor();

    double snap(double v) => snapToPixelGrid && devicePixelRatio > 0
        ? (v * devicePixelRatio).roundToDouble() / devicePixelRatio
        : v;

    final tiles = <Widget>[];
    final labelTag = hideLabels ? 'nolbl' : 'lbl';
    for (var ty = minTileY; ty <= maxTileY; ty++) {
      if (ty < 0 || ty > maxTileIndex) continue;
      for (var tx = minTileX; tx <= maxTileX; tx++) {
        final wrappedTx = ((tx % (maxTileIndex + 1)) + (maxTileIndex + 1)) %
            (maxTileIndex + 1);
        final rawLeft = tx * 256.0 - topLeftWorldX;
        final rawTop = ty * 256.0 - topLeftWorldY;
        final left = snap(rawLeft);
        final top = snap(rawTop);
        final tileW = snapToPixelGrid ? snap(rawLeft + 256.0) - left : 256.4;
        final tileH = snapToPixelGrid ? snap(rawTop + 256.0) - top : 256.4;
        final tileUrl = EnvConfig.buildGoogleMapTileUrl(
          x: wrappedTx,
          y: ty,
          z: zoom,
          layer: layer,
          hideLabels: hideLabels,
        );
        final osmFallbackUrl =
            'https://tile.openstreetmap.org/$zoom/$wrappedTx/$ty.png';
        tiles.add(
          Positioned(
            key: ValueKey(
              '${keyPrefix}_${layer}_${labelTag}_${zoom}_${wrappedTx}_$ty',
            ),
            left: left,
            top: top,
            width: tileW,
            height: tileH,
            child: Image.network(
              tileUrl,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => (layer.startsWith('m') || layer == 'p')
                  ? Image.network(
                      osmFallbackUrl,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        );
      }
    }
    return Stack(clipBehavior: Clip.hardEdge, children: tiles);
  }

  Widget _buildGoogleMapTileLayerCustom(
    Size viewSize,
    GeoPoint centerGeo, {
    required int zoom,
    required Offset pan,
    required String layer,
    bool hideLabels = false,
    double devicePixelRatio = 1.0,
    bool snapToPixelGrid = true,
    int? backdropZoom,
  }) {
    if (_isAutomatedTestBinding ||
        AppStateStore.instance.isOfflineMode ||
        viewSize.width <= 0 ||
        viewSize.height <= 0) {
      return const SizedBox.shrink();
    }
    final activeStack = _buildSingleZoomTileStack(
      viewSize,
      centerGeo,
      zoom: zoom,
      pan: pan,
      layer: layer,
      hideLabels: hideLabels,
      devicePixelRatio: devicePixelRatio,
      snapToPixelGrid: snapToPixelGrid,
    );
    if (backdropZoom == null ||
        backdropZoom == zoom ||
        (zoom - backdropZoom).abs() > 2) {
      return activeStack;
    }
    final scaleDiff = math.pow(2.0, (zoom - backdropZoom).toDouble()).toDouble();
    final backdropPan = pan / scaleDiff;
    return Stack(
      clipBehavior: Clip.hardEdge,
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: Transform.scale(
            scale: scaleDiff,
            alignment: Alignment.center,
            child: _buildSingleZoomTileStack(
              viewSize,
              centerGeo,
              zoom: backdropZoom,
              pan: backdropPan,
              layer: layer,
              hideLabels: hideLabels,
              devicePixelRatio: devicePixelRatio,
              snapToPixelGrid: false,
              keyPrefix: 'ggbg',
            ),
          ),
        ),
        activeStack,
      ],
    );
  }

  IconData _topBannerIcon() {
    switch (widget.mode) {
      case MapViewMode.customerPreview:
        return widget.singlePinPoint != null
            ? Icons.location_on_rounded
            : Icons.route_rounded;
      case MapViewMode.customerLiveTracking:
        return Icons.share_location_rounded;
      case MapViewMode.driverRadar:
        return Icons.radar_rounded;
      case MapViewMode.fleetOverview:
        return Icons.hub_rounded;
      case MapViewMode.driverTurnByTurn:
        return Icons.turn_right;
    }
  }

  bool get _shouldShowSpeedometer =>
      (widget.mode == MapViewMode.driverTurnByTurn ||
          widget.mode == MapViewMode.customerLiveTracking) &&
      widget.speedKmh > 0.1;

  @override
  Widget build(BuildContext context) {
    final baseRoute = _resolveBaseRoute();
    final effectiveRoute =
        (_liveOsrmRoutePoints != null && _liveOsrmRoutePoints!.length >= 2)
            ? _liveOsrmRoutePoints!
            : baseRoute;
    final centerGeo = _resolveCenterGeo(effectiveRoute);
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final double adaptiveHeight =
        (widget.isFullScreenBackground || widget.expandToParent
                ? (viewportHeight > 0 ? viewportHeight : widget.height)
                : (viewportHeight > 0 && viewportHeight < 700
                    ? widget.height
                        .clamp(280.0, math.max(320.0, viewportHeight * 0.68))
                    : widget.height.clamp(300.0, 840.0)))
            .toDouble();
    final hasTopOverlay = widget.showTopBanner &&
        !widget.isFullScreenBackground &&
        (widget.nextTurnInstruction.trim().isNotEmpty ||
            widget.roadName.trim().isNotEmpty);

    Widget buildInteractiveContent(Size viewSize) {
      return MouseRegion(
        cursor: widget.onTapGeoPoint != null
            ? SystemMouseCursors.precise
            : SystemMouseCursors.grab,
        onHover: (event) {
          if (!_effective3d ||
              viewSize.width <= 0 ||
              viewSize.height <= 0) {
            return;
          }
          final nx = (event.localPosition.dx / viewSize.width - 0.5) * 2.0;
          final ny = (event.localPosition.dy / viewSize.height - 0.5) * 2.0;
          final nextYaw = (nx * 0.045).clamp(-0.06, 0.06);
          final nextPitch = (-ny * 0.04).clamp(-0.06, 0.06);
          if ((nextYaw - _cameraYawOffset).abs() < 0.008 &&
              (nextPitch - _cameraPitchOffset).abs() < 0.008) {
            return;
          }
          setState(() {
            _cameraYawOffset = nextYaw;
            _cameraPitchOffset = nextPitch;
          });
        },
        onExit: (_) {
          if (_cameraYawOffset != 0.0 || _cameraPitchOffset != 0.0) {
            setState(() {
              _cameraYawOffset = 0.0;
              _cameraPitchOffset = 0.0;
            });
          }
        },
        child: Listener(
          onPointerSignal: (signal) {
            if (signal is PointerScrollEvent) {
              final delta = signal.scrollDelta.dy < 0 ? 1 : -1;
              setState(() {
                _applyZoom(
                  _zoomLevel + delta,
                  anchor: signal.localPosition,
                  viewSize: viewSize,
                );
              });
            }
          },
          child: AnimatedBuilder(
            animation: _animController,
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _Map3dCanvasPainter(
                      is3dMode: _effective3d,
                      progressFraction: widget.progressFraction,
                      driverLocation: widget.driverLocation,
                      drawnPolygonPoints: widget.drawnPolygonPoints,
                      drawnPolygonGeoPoints: widget.drawnPolygonGeoPoints,
                      geofenceZones: widget.geofenceZones,
                      singlePinPoint: widget.singlePinPoint,
                      singlePinLabel: widget.singlePinLabel,
                      liveDeviceLocation:
                          AppStateStore.instance.liveDeviceLocation,
                      liveDeviceAccuracyMeters:
                          AppStateStore.instance.liveDeviceAccuracyMeters,
                      nearbySearchingOrders: widget.nearbySearchingOrders,
                      routePoints: effectiveRoute,
                      animPhase: 0.25,
                      mode: widget.mode,
                      zoomLevel: _zoomLevel,
                      panPixelOffset: _panPixelOffset,
                      centerGeo: centerGeo,
                      drawBackgroundOnly: true,
                      pickupLabel: widget.pickupLabel,
                      dropoffLabel: widget.dropoffLabel,
                      fleetDrivers: _effectiveFleetDrivers,
                    ),
                  ),
                  _buildGoogleMapTileLayer(
                    viewSize,
                    centerGeo,
                    devicePixelRatio: devicePixelRatio,
                  ),
                ],
              ),
            ),
            builder: (context, staticMapBase) {
              final phase = _animController.value;
              final matrix = Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateX(
                  _effective3d
                      ? (_manualPitchRadians + _cameraPitchOffset)
                      : 0.0,
                )
                ..rotateZ(
                  _effective3d ? (_manualYawRadians + _cameraYawOffset) : 0.0,
                )
                ..scaleByDouble(
                  _effective3d ? 1.14 : 1.0,
                  _effective3d ? 1.14 : 1.0,
                  1.0,
                  1.0,
                );
              final pinchActive =
                  (_pinchVisualScale - 1.0).abs() > 0.002 &&
                  viewSize.width > 0 &&
                  viewSize.height > 0;
              final pinchAlignment = pinchActive
                  ? Alignment(
                      (_pinchFocalPoint.dx / viewSize.width) * 2.0 - 1.0,
                      (_pinchFocalPoint.dy / viewSize.height) * 2.0 - 1.0,
                    )
                  : Alignment.center;

              Widget transformedMap = Transform(
                alignment: Alignment.center,
                transform: matrix,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    staticMapBase!,
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: _Map3dCanvasPainter(
                          is3dMode: _effective3d,
                          progressFraction: widget.progressFraction,
                          driverLocation: widget.driverLocation,
                          drawnPolygonPoints: widget.drawnPolygonPoints,
                          drawnPolygonGeoPoints: widget.drawnPolygonGeoPoints,
                          geofenceZones: widget.geofenceZones,
                          singlePinPoint: widget.singlePinPoint,
                          singlePinLabel: widget.singlePinLabel,
                          liveDeviceLocation:
                              AppStateStore.instance.liveDeviceLocation,
                          liveDeviceAccuracyMeters:
                              AppStateStore.instance.liveDeviceAccuracyMeters,
                          nearbySearchingOrders: widget.nearbySearchingOrders,
                          routePoints: effectiveRoute,
                          animPhase: phase,
                          mode: widget.mode,
                          zoomLevel: _zoomLevel,
                          panPixelOffset: _panPixelOffset,
                          centerGeo: centerGeo,
                          drawBackgroundOnly: false,
                          showCalloutLabels: !widget.isFullScreenBackground,
                          pickupLabel: widget.pickupLabel,
                          dropoffLabel: widget.dropoffLabel,
                          fleetDrivers: _effectiveFleetDrivers,
                        ),
                      ),
                    ),
                  ],
                ),
              );
              if (pinchActive) {
                transformedMap = Transform.scale(
                  scale: _pinchVisualScale,
                  alignment: pinchAlignment,
                  child: transformedMap,
                );
              }

              final hasTapCallback = widget.onTapGeoPoint != null ||
                  widget.onTapRelativePoint != null;

              return Stack(
                children: [
                  Positioned.fill(
                    child: Container(color: const Color(0xFFE2E8F0)),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTapDown: hasTapCallback
                          ? null
                          : (details) {
                              _doubleTapPosition = details.localPosition;
                            },
                      onDoubleTap: hasTapCallback
                          ? null
                          : () {
                              setState(() {
                                _applyZoom(
                                  _zoomLevel + 1,
                                  anchor: _doubleTapPosition,
                                  viewSize: viewSize,
                                );
                              });
                            },
                      onScaleStart: (details) {
                        _scaleLastFocalPoint = details.localFocalPoint;
                        _scaleStartZoom = _zoomLevel;
                        _pinchFocalPoint = details.localFocalPoint;
                      },
                      onScaleUpdate: (details) {
                        final focalDelta = _scaleLastFocalPoint != null
                            ? (details.localFocalPoint - _scaleLastFocalPoint!)
                            : Offset.zero;
                        _scaleLastFocalPoint = details.localFocalPoint;
                        setState(() {
                          _panPixelOffset += focalDelta;
                          if ((details.scale - 1.0).abs() > 0.015) {
                            final continuousZoom = (_scaleStartZoom +
                                    math.log(details.scale) / math.ln2)
                                .clamp(5.0, 20.0);
                            final nextZoom = continuousZoom.round().clamp(5, 20);
                            if (nextZoom != _zoomLevel) {
                              _applyZoom(
                                nextZoom,
                                anchor: details.localFocalPoint,
                                viewSize: viewSize,
                              );
                            }
                            _pinchVisualScale = math
                                .pow(2.0, continuousZoom - _zoomLevel)
                                .toDouble();
                            _pinchFocalPoint = details.localFocalPoint;
                          }
                        });
                      },
                      onScaleEnd: (_) {
                        if ((_pinchVisualScale - 1.0).abs() > 0.001) {
                          setState(() => _pinchVisualScale = 1.0);
                        }
                      },
                      onTapUp: !hasTapCallback
                          ? null
                          : (details) {
                              if (viewSize.width <= 0 ||
                                  viewSize.height <= 0) {
                                return;
                              }
                              if (widget.onTapGeoPoint != null) {
                                final tappedGeo = _screenOffsetToGeoPoint(
                                  details.localPosition,
                                  viewSize,
                                  centerGeo,
                                );
                                widget.onTapGeoPoint!(tappedGeo);
                              }
                              if (widget.onTapRelativePoint != null) {
                                final relX =
                                    (details.localPosition.dx / viewSize.width)
                                        .clamp(0.0, 1.0);
                                final relY =
                                    (details.localPosition.dy / viewSize.height)
                                        .clamp(0.0, 1.0);
                                widget.onTapRelativePoint!(Offset(relX, relY));
                              }
                            },
                      child: transformedMap,
                    ),
                  ),
                    if (hasTopOverlay)
                      Positioned(
                        top: 10,
                        left: 10,
                        right: math.max(10.0, viewSize.width > 560 ? 72.0 : 54.0),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 540),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.darkSidebar.withValues(
                                  alpha: 0.88,
                                ),
                                border: Border.all(
                                  color: Colors.white24,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _topBannerIcon(),
                                    color: AppColors.acid,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (widget.nextTurnInstruction
                                            .trim()
                                            .isNotEmpty)
                                          Text(
                                            widget.nextTurnInstruction,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppColors.surface,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        if (widget.roadName.trim().isNotEmpty)
                                          Text(
                                            widget.roadName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 10.5,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_shouldShowSpeedometer &&
                        !widget.isFullScreenBackground)
                      Positioned(
                        top: 10,
                        right: 52,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.darkSidebar,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.danger,
                              width: 2.0,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                widget.speedKmh.toStringAsFixed(0),
                                style: const TextStyle(
                                  color: AppColors.surface,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              const Text(
                                'km/h',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 8.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!widget.isFullScreenBackground)
                      Positioned(
                        bottom: 10,
                        left: 10,
                        right: 58,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.darkSidebar.withValues(
                                  alpha: 0.88,
                                ),
                                border: Border.all(
                                  color: Colors.white24,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.layers_outlined,
                                    size: 13,
                                    color: AppColors.acid,
                                  ),
                                  const SizedBox(width: 4),
                                  _buildLayerChip('m', 'Bản đồ'),
                                  const SizedBox(width: 3),
                                  _buildLayerChip('m,traffic', 'Giao thông'),
                                  const SizedBox(width: 3),
                                  _buildLayerChip('y', 'Vệ tinh'),
                                  const SizedBox(width: 3),
                                  _buildLayerChip('p', 'Địa hình'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (!widget.isFullScreenBackground)
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildMapControlBtn(
                              icon: Icons.fullscreen_rounded,
                              tooltip: 'Mở rộng bản đồ toàn màn hình',
                              onTap: () => _openPanoramic3dModal(
                                context,
                                effectiveRoute,
                                centerGeo,
                              ),
                            ),
                            const SizedBox(height: 5),
                            _buildMapControlBtn(
                              buttonKey: const ValueKey('btn_map_my_real_gps'),
                              icon: Icons.my_location_rounded,
                              isHighlighted:
                                  AppStateStore.instance.hasRealDeviceGpsFix,
                              tooltip: 'Vị trí hiện tại của tôi',
                              onTap: () => _handleFocusMyRealGps(context),
                            ),
                            const SizedBox(height: 5),
                            _buildMapControlBtn(
                              label: '+',
                              tooltip: 'Phóng to bản đồ',
                              onTap: () {
                                setState(() {
                                  _applyZoom(
                                    _zoomLevel + 1,
                                    viewSize: viewSize,
                                  );
                                });
                              },
                            ),
                            const SizedBox(height: 5),
                            _buildMapControlBtn(
                              label: '−',
                              tooltip: 'Thu nhỏ bản đồ',
                              onTap: () {
                                setState(() {
                                  _applyZoom(
                                    _zoomLevel - 1,
                                    viewSize: viewSize,
                                  );
                                });
                              },
                            ),
                            const SizedBox(height: 5),
                            _buildMapControlBtn(
                              icon: Icons.center_focus_strong_rounded,
                              tooltip: 'Căn giữa lộ trình / khung bản đồ',
                              onTap: () {
                                setState(() {
                                  _previousZoomLevel = _zoomLevel;
                                  _customCenterGeoOverride = null;
                                  _panPixelOffset = Offset.zero;
                                  _manualYawRadians = 0.0;
                                  _pinchVisualScale = 1.0;
                                  _userAdjustedZoom = false;
                                  _zoomLevel = _computeInitialAutoZoom(
                                    viewport: viewSize,
                                  );
                                });
                              },
                            ),
                            const SizedBox(height: 5),
                            InkWell(
                              onTap: _handleToggle3d,
                              child: Container(
                                width: 34,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _effective3d
                                      ? AppColors.primary
                                      : AppColors.surface,
                                  shape: BoxShape.circle,
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _effective3d ? '3D' : '2D',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: _effective3d
                                        ? Colors.white
                                        : AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      }

      if (widget.expandToParent) {
      return ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.hasBoundedHeight &&
                    constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : adaptiveHeight;
            return SizedBox(
              width: double.infinity,
              height: h,
              child: buildInteractiveContent(Size(constraints.maxWidth, h)),
            );
          },
        ),
      );
    }

    return ClipRect(
      child: SizedBox(
        height: adaptiveHeight,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return buildInteractiveContent(
              Size(constraints.maxWidth, constraints.maxHeight),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLayerChip(String layerCode, String title) {
    final active = _googleLayer == layerCode;
    return InkWell(
      onTap: () => setState(() => _googleLayer = layerCode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        color: active ? AppColors.primary : Colors.transparent,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color: active ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildMapControlBtn({
    Key? buttonKey,
    String? label,
    IconData? icon,
    bool isHighlighted = false,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final bgColor =
        isHighlighted ? const Color(0xFF0284C7) : AppColors.surface;
    final fgColor = isHighlighted ? Colors.white : AppColors.ink;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
              ),
            ],
          ),
          child: icon != null
              ? Icon(icon, size: 16.5, color: fgColor)
              : Text(
                  label ?? '',
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w900,
                    color: fgColor,
                  ),
                ),
        ),
      ),
    );
  }
}

class _Map3dCanvasPainter extends CustomPainter {
  final bool is3dMode;
  final double progressFraction;
  final GeoPoint? driverLocation;
  final List<Offset> drawnPolygonPoints;
  final List<GeoPoint> drawnPolygonGeoPoints;
  final List<GeofenceZoneRecord> geofenceZones;
  final GeoPoint? singlePinPoint;
  final String? singlePinLabel;
  final GeoPoint? liveDeviceLocation;
  final double? liveDeviceAccuracyMeters;
  final List<ActiveOrderRecord> nearbySearchingOrders;
  final List<GeoPoint> routePoints;
  final double animPhase;
  final MapViewMode mode;
  final int zoomLevel;
  final Offset panPixelOffset;
  final GeoPoint centerGeo;
  final bool drawBackgroundOnly;
  final bool showCalloutLabels;
  final String? pickupLabel;
  final String? dropoffLabel;
  final List<DriverApplicantRecord> fleetDrivers;

  const _Map3dCanvasPainter({
    required this.is3dMode,
    required this.progressFraction,
    this.driverLocation,
    required this.drawnPolygonPoints,
    required this.drawnPolygonGeoPoints,
    required this.geofenceZones,
    required this.singlePinPoint,
    required this.singlePinLabel,
    this.liveDeviceLocation,
    this.liveDeviceAccuracyMeters,
    required this.nearbySearchingOrders,
    required this.routePoints,
    required this.animPhase,
    required this.mode,
    required this.zoomLevel,
    required this.panPixelOffset,
    required this.centerGeo,
    required this.drawBackgroundOnly,
    this.showCalloutLabels = true,
    required this.pickupLabel,
    required this.dropoffLabel,
    required this.fleetDrivers,
  });

  Offset _projectSingleGeoPoint(GeoPoint pt, Size size) {
    final centerWorldX =
        _Map3dPerspectiveWidgetState._lonToWorldX(centerGeo.longitude, zoomLevel);
    final centerWorldY =
        _Map3dPerspectiveWidgetState._latToWorldY(centerGeo.latitude, zoomLevel);
    final ptWorldX =
        _Map3dPerspectiveWidgetState._lonToWorldX(pt.longitude, zoomLevel);
    final ptWorldY =
        _Map3dPerspectiveWidgetState._latToWorldY(pt.latitude, zoomLevel);

    final rawX = size.width * 0.5 + (ptWorldX - centerWorldX) + panPixelOffset.dx;
    final rawY = size.height * 0.5 + (ptWorldY - centerWorldY) + panPixelOffset.dy;
    return Offset(rawX, rawY);
  }

  void _drawCalloutBadge(
    Canvas canvas,
    Offset anchor,
    String text,
    Color bgColor, {
    Offset offset = const Offset(0, -22),
  }) {
    if (!showCalloutLabels || text.trim().isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 165);

    final badgeRect = Rect.fromCenter(
      center: anchor + offset,
      width: tp.width + 12,
      height: tp.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
      Paint()..color = bgColor.withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    tp.paint(
      canvas,
      Offset(badgeRect.left + 6, badgeRect.top + 3),
    );
  }

  void _draw3dVerticalBeaconPillar(
    Canvas canvas,
    Offset groundPt,
    Color color,
    double height,
  ) {
    if (!is3dMode) return;
    final topPt = groundPt + Offset(0, -height);
    final pillarRect = Rect.fromPoints(
      topPt - const Offset(3, 0),
      groundPt + const Offset(3, 0),
    );
    canvas.drawRect(
      pillarRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.90),
            color.withValues(alpha: 0.12),
          ],
        ).createShader(pillarRect),
    );
    canvas.drawCircle(topPt, 4.5, Paint()..color = Colors.white);
    canvas.drawCircle(
      topPt,
      6.5,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  void _drawLocationPin(
    Canvas canvas,
    Offset pt,
    Color color, {
    required double pulse,
    String? label,
  }) {
    _draw3dVerticalBeaconPillar(canvas, pt, color, 22.0);
    canvas.drawCircle(
      pt,
      11 + 5 * pulse,
      Paint()..color = color.withValues(alpha: 0.24),
    );
    canvas.drawCircle(pt, 7.5, Paint()..color = color);
    canvas.drawCircle(pt, 3.0, Paint()..color = Colors.white);
    if (label != null && label.isNotEmpty) {
      _drawCalloutBadge(
        canvas,
        pt,
        label,
        color,
        offset: Offset(0, is3dMode ? -36 : -20),
      );
    }
  }

  Color _colorForZoneType(String zoneType) {
    switch (zoneType) {
      case 'RESTRICTED_ZONE':
        return AppColors.danger;
      case 'SURCHARGE_ZONE':
        return AppColors.accent;
      default:
        return AppColors.success;
    }
  }

  void _drawGeofencePolygons(Canvas canvas, Size size) {
    for (final zone in geofenceZones) {
      if (zone.boundary.length < 3) continue;
      final baseColor = _colorForZoneType(zone.zoneType);
      final alphaMul = zone.isActive ? 1.0 : 0.35;
      final path = Path();
      double sumX = 0;
      double sumY = 0;
      for (var i = 0; i < zone.boundary.length; i++) {
        final p = _projectSingleGeoPoint(zone.boundary[i], size);
        sumX += p.dx;
        sumY += p.dy;
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = baseColor.withValues(alpha: 0.18 * alphaMul)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = baseColor.withValues(alpha: 0.85 * alphaMul)
          ..strokeWidth = zone.isActive ? 2.2 : 1.2
          ..style = PaintingStyle.stroke,
      );
      if (zone.isActive) {
        final centroid = Offset(
          sumX / zone.boundary.length,
          sumY / zone.boundary.length,
        );
        _drawCalloutBadge(
          canvas,
          centroid,
          zone.zoneName,
          baseColor,
          offset: Offset.zero,
        );
      }
    }

    if (drawnPolygonGeoPoints.isNotEmpty) {
      final polyFill = Paint()
        ..color = AppColors.violet.withValues(alpha: 0.24)
        ..style = PaintingStyle.fill;
      final polyStroke = Paint()
        ..color = AppColors.violet
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke;

      final polyPath = Path();
      for (var i = 0; i < drawnPolygonGeoPoints.length; i++) {
        final pt = _projectSingleGeoPoint(drawnPolygonGeoPoints[i], size);
        if (i == 0) {
          polyPath.moveTo(pt.dx, pt.dy);
        } else {
          polyPath.lineTo(pt.dx, pt.dy);
        }
        canvas.drawCircle(pt, 5.5, Paint()..color = AppColors.violet);
        canvas.drawCircle(pt, 2.2, Paint()..color = Colors.white);
      }
      if (drawnPolygonGeoPoints.length >= 3) {
        polyPath.close();
        canvas.drawPath(polyPath, polyFill);
      }
      canvas.drawPath(polyPath, polyStroke);
    } else if (drawnPolygonPoints.isNotEmpty) {
      final polyPath = Path();
      for (var i = 0; i < drawnPolygonPoints.length; i++) {
        final pt = Offset(
          drawnPolygonPoints[i].dx * size.width,
          drawnPolygonPoints[i].dy * size.height,
        );
        if (i == 0) {
          polyPath.moveTo(pt.dx, pt.dy);
        } else {
          polyPath.lineTo(pt.dx, pt.dy);
        }
        canvas.drawCircle(pt, 5, Paint()..color = AppColors.danger);
      }
      if (drawnPolygonPoints.length >= 3) {
        polyPath.close();
        canvas.drawPath(
          polyPath,
          Paint()
            ..color = AppColors.accent.withValues(alpha: 0.25)
            ..style = PaintingStyle.fill,
        );
      }
      canvas.drawPath(
        polyPath,
        Paint()
          ..color = AppColors.accent
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawDriverVehicleMarker(
    Canvas canvas,
    Offset driverCenter,
    Offset tangentDir, {
    required String label,
    required bool showRadarRings,
  }) {
    _draw3dVerticalBeaconPillar(canvas, driverCenter, AppColors.success, 22.0);
    if (showRadarRings) {
      for (final ringBase in const <double>[36.0, 74.0]) {
        canvas.drawCircle(
          driverCenter,
          ringBase + 16.0 * animPhase,
          Paint()
            ..color = AppColors.routeRibbonFill.withValues(
              alpha: (1.0 - animPhase) * 0.36,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
    }
    final radarRadius =
        (showRadarRings ? 22.0 : 14.0) + 14.0 * animPhase;
    canvas.drawCircle(
      driverCenter,
      radarRadius,
      Paint()
        ..color = AppColors.success.withValues(alpha: (1.0 - animPhase) * 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    canvas.drawCircle(
      driverCenter,
      15,
      Paint()..color = AppColors.success.withValues(alpha: 0.28),
    );
    if (MeshyScooter3dMesh.instance.isLoaded) {
      final scooterPitch = is3dMode ? 0.44 : 0.62;
      final scooterYaw = MeshyScooter3dMesh.yawForScreenTangent(
        tangentDir.dx,
        tangentDir.dy,
        pitchRadians: scooterPitch,
      );
      MeshyScooter3dMesh.instance.renderToCanvas(
        canvas,
        center: driverCenter + const Offset(0, -8),
        scalePx: is3dMode ? 22.0 : 17.0,
        yawRadians: scooterYaw,
        pitchRadians: scooterPitch,
      );
    } else {
      canvas.drawCircle(driverCenter, 9.5, Paint()..color = AppColors.success);
      canvas.drawCircle(driverCenter, 3.8, Paint()..color = Colors.white);
    }
    _drawCalloutBadge(
      canvas,
      driverCenter,
      label,
      AppColors.success,
      offset: const Offset(0, 22),
    );
  }

  void _drawLiveDeviceGpsMarker(Canvas canvas, Size size, double pulse) {
    final livePt = liveDeviceLocation;
    if (livePt == null) return;
    final screenPt = _projectSingleGeoPoint(livePt, size);
    if (screenPt.dx < -160 ||
        screenPt.dx > size.width + 160 ||
        screenPt.dy < -160 ||
        screenPt.dy > size.height + 160) {
      return;
    }

    final accMeters = liveDeviceAccuracyMeters ?? 24.0;
    if (accMeters <= 1500.0) {
      final cosLat =
          math.cos(livePt.latitude * math.pi / 180.0).clamp(0.05, 1.0);
      final metersPerPixel = (156543.03392 * cosLat) / (1 << zoomLevel);
      final rawAccRadius = accMeters / math.max(0.05, metersPerPixel);
      final accRadiusPx = rawAccRadius.clamp(14.0, 96.0);

      canvas.drawCircle(
        screenPt,
        accRadiusPx,
        Paint()
          ..color = const Color(0xFF0284C7).withValues(alpha: 0.13)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        screenPt,
        accRadiusPx,
        Paint()
          ..color = const Color(0xFF0284C7).withValues(alpha: 0.44)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.drawCircle(
      screenPt,
      11.0 + 7.0 * pulse,
      Paint()
        ..color = const Color(0xFF38BDF8)
            .withValues(alpha: 0.40 * (1.0 - pulse * 0.5))
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(screenPt, 8.6, Paint()..color = Colors.white);
    canvas.drawCircle(
      screenPt,
      6.2,
      Paint()..color = const Color(0xFF2563EB),
    );
    canvas.drawCircle(
      screenPt + const Offset(-1.5, -1.5),
      1.7,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final animAngle = animPhase * math.pi * 2.0;

    if (drawBackgroundOnly) {
      final groundRect = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawRect(
        groundRect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8EEF5), Color(0xFFD6E0EB)],
          ).createShader(groundRect),
      );

      final gridPaint = Paint()
        ..color = const Color(0xFF94A3B8).withValues(alpha: 0.28)
        ..strokeWidth = 1.0;
      for (int i = 1; i <= 7; i++) {
        final y = size.height * (i / 8.0);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
      for (int i = 1; i <= 7; i++) {
        final x = size.width * (i / 8.0);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      return;
    }

    final beaconPulse = (math.sin(animAngle * 2.0) + 1.0) * 0.5;
    _drawGeofencePolygons(canvas, size);
    _drawLiveDeviceGpsMarker(canvas, size, beaconPulse);

    if (singlePinPoint != null) {
      final pinScreen = _projectSingleGeoPoint(singlePinPoint!, size);
      if (mode == MapViewMode.driverRadar) {
        for (final ord in nearbySearchingOrders) {
          final ordPt = _projectSingleGeoPoint(ord.pickupLocation, size);
          _drawLocationPin(
            canvas,
            ordPt,
            AppColors.accent,
            pulse: beaconPulse,
            label: ord.trackingCode,
          );
        }
        _drawDriverVehicleMarker(
          canvas,
          pinScreen,
          const Offset(1.0, 0.0),
          label: singlePinLabel ?? pickupLabel ?? 'Vị trí của bạn',
          showRadarRings: true,
        );
      } else {
        _drawLocationPin(
          canvas,
          pinScreen,
          AppColors.primary,
          pulse: beaconPulse,
          label: singlePinLabel ?? pickupLabel ?? 'Vị trí đã chọn',
        );
      }
      return;
    }

    if (routePoints.length >= 2) {
      final screenPts =
          routePoints.map((pt) => _projectSingleGeoPoint(pt, size)).toList();

      final casingPaint = Paint()
        ..color = AppColors.routeRibbonCasing
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final ribbonPaint = Paint()
        ..color = AppColors.routeRibbonFill
        ..strokeWidth = 6.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final routePath = Path()..moveTo(screenPts.first.dx, screenPts.first.dy);
      for (var i = 1; i < screenPts.length; i++) {
        routePath.lineTo(screenPts[i].dx, screenPts[i].dy);
      }
      canvas.drawPath(routePath, casingPaint);
      canvas.drawPath(routePath, ribbonPaint);

      final totalSegments = screenPts.length - 1;
      if (totalSegments >= 1) {
        for (int pIdx = 0; pIdx < 3; pIdx++) {
          final pulseT = (animPhase + pIdx / 3.0) % 1.0;
          final exactSeg = pulseT * totalSegments;
          final sIdx = exactSeg.floor().clamp(0, totalSegments - 1);
          final localT = (exactSeg - sIdx).clamp(0.0, 1.0);
          final pulsePt =
              Offset.lerp(screenPts[sIdx], screenPts[sIdx + 1], localT)!;
          canvas.drawCircle(
            pulsePt,
            4.5,
            Paint()
              ..color = const Color(0xFF00F5D4).withValues(alpha: 0.72)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
          );
          canvas.drawCircle(pulsePt, 2.2, Paint()..color = Colors.white);
        }
      }

      _drawLocationPin(
        canvas,
        screenPts.first,
        AppColors.primary,
        pulse: beaconPulse,
        label: pickupLabel ?? '[A] Điểm lấy',
      );
      _drawLocationPin(
        canvas,
        screenPts.last,
        AppColors.accent,
        pulse: beaconPulse,
        label: dropoffLabel ?? '[B] Điểm giao',
      );

      if (mode != MapViewMode.fleetOverview &&
          mode != MapViewMode.customerPreview &&
          driverLocation != null) {
        final driverCenter = _projectSingleGeoPoint(driverLocation!, size);
        final bearing = AppStateStore.instance.activeDriverBearing * math.pi / 180;
        final tangentDir = Offset(math.sin(bearing), -math.cos(bearing));
        _drawDriverVehicleMarker(
          canvas,
          driverCenter,
          tangentDir,
          label: mode == MapViewMode.driverRadar ? 'Vị trí của bạn' : 'Tài xế',
          showRadarRings: mode == MapViewMode.driverRadar,
        );
      }
    } else if (mode == MapViewMode.driverRadar) {
      for (final ord in nearbySearchingOrders) {
        final ordPt = _projectSingleGeoPoint(ord.pickupLocation, size);
        _drawLocationPin(
          canvas,
          ordPt,
          AppColors.accent,
          pulse: beaconPulse,
          label: ord.trackingCode,
        );
      }
      if (driverLocation != null) {
        _drawDriverVehicleMarker(
          canvas,
          _projectSingleGeoPoint(driverLocation!, size),
          const Offset(1.0, 0.0),
          label: pickupLabel ?? 'Vị trí của bạn',
          showRadarRings: true,
        );
      }
    }

    if (mode == MapViewMode.fleetOverview && fleetDrivers.isNotEmpty) {
      for (var i = 0; i < fleetDrivers.length; i++) {
        final drv = fleetDrivers[i];
        final drvOffset = _projectSingleGeoPoint(drv.location, size);
        final statusColor =
            drv.isOnline ? AppColors.success : AppColors.textSecondary;
        _draw3dVerticalBeaconPillar(canvas, drvOffset, statusColor, 20.0);
        canvas.drawCircle(
          drvOffset,
          12,
          Paint()..color = statusColor.withValues(alpha: 0.25),
        );
        canvas.drawCircle(drvOffset, 7.5, Paint()..color = statusColor);
        canvas.drawCircle(drvOffset, 3.0, Paint()..color = Colors.white);
        _drawCalloutBadge(
          canvas,
          drvOffset,
          '${drv.fullName.split(' ').last} (${drv.licensePlate})',
          statusColor,
          offset: Offset(0, i.isEven ? (is3dMode ? -32 : -18) : 18),
        );
      }
    }
  }

  static bool _zonesChanged(
    List<GeofenceZoneRecord> a,
    List<GeofenceZoneRecord> b,
  ) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].isActive != b[i].isActive ||
          a[i].zoneType != b[i].zoneType ||
          a[i].zoneName != b[i].zoneName ||
          a[i].boundary.length != b[i].boundary.length) {
        return true;
      }
    }
    return false;
  }

  static bool _driversChanged(
    List<DriverApplicantRecord> a,
    List<DriverApplicantRecord> b,
  ) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].isOnline != b[i].isOnline ||
          a[i].location != b[i].location) {
        return true;
      }
    }
    return false;
  }

  @override
  bool shouldRepaint(covariant _Map3dCanvasPainter oldDelegate) {
    if (drawBackgroundOnly && oldDelegate.drawBackgroundOnly) {
      return false;
    }
    return oldDelegate.is3dMode != is3dMode ||
      oldDelegate.progressFraction != progressFraction ||
      oldDelegate.driverLocation != driverLocation ||
      oldDelegate.animPhase != animPhase ||
      oldDelegate.mode != mode ||
      oldDelegate.zoomLevel != zoomLevel ||
      oldDelegate.panPixelOffset != panPixelOffset ||
      oldDelegate.centerGeo != centerGeo ||
      oldDelegate.singlePinPoint != singlePinPoint ||
      oldDelegate.singlePinLabel != singlePinLabel ||
      oldDelegate.liveDeviceLocation != liveDeviceLocation ||
      oldDelegate.liveDeviceAccuracyMeters != liveDeviceAccuracyMeters ||
      oldDelegate.pickupLabel != pickupLabel ||
      oldDelegate.dropoffLabel != dropoffLabel ||
      oldDelegate.drawBackgroundOnly != drawBackgroundOnly ||
      oldDelegate.showCalloutLabels != showCalloutLabels ||
      _driversChanged(oldDelegate.fleetDrivers, fleetDrivers) ||
      _zonesChanged(oldDelegate.geofenceZones, geofenceZones) ||
      oldDelegate.nearbySearchingOrders.length !=
          nearbySearchingOrders.length ||
      oldDelegate.drawnPolygonGeoPoints.length !=
          drawnPolygonGeoPoints.length ||
      oldDelegate.drawnPolygonPoints.length != drawnPolygonPoints.length ||
      oldDelegate.routePoints.length != routePoints.length ||
      (routePoints.isNotEmpty &&
          oldDelegate.routePoints.isNotEmpty &&
          (routePoints.first != oldDelegate.routePoints.first ||
              routePoints.last != oldDelegate.routePoints.last));
  }
}
