import 'dart:math' as math;
import '../../data/models/app_state_records.dart';
import '../../domain/entities/geo_point.dart';
import '../../domain/enums/order_status.dart';
import '../utils/geo_math.dart';
import 'smart_dispatch_engine.dart';

class RecipientTrustProfile {
  final String normalizedPhone;
  final int trustScore;
  final String riskTier;
  final int deliveredCount;
  final int failedOrReturnedCount;
  final bool isBlacklisted;
  final String recommendation;

  const RecipientTrustProfile({
    required this.normalizedPhone,
    required this.trustScore,
    required this.riskTier,
    required this.deliveredCount,
    required this.failedOrReturnedCount,
    required this.isBlacklisted,
    required this.recommendation,
  });

  bool get isHighRisk => isBlacklisted || trustScore < 60;
}

class MultiStopRoutePlan {
  final GeoPoint originWarehouse;
  final List<ActiveOrderRecord> orderedStops;
  final List<GeoPoint> chainedPolyline;
  final int inputOrderDistanceMeters;
  final int optimizedDistanceMeters;

  const MultiStopRoutePlan({
    required this.originWarehouse,
    required this.orderedStops,
    required this.chainedPolyline,
    required this.inputOrderDistanceMeters,
    required this.optimizedDistanceMeters,
  });

  int get savedDistanceMeters =>
      math.max(0, inputOrderDistanceMeters - optimizedDistanceMeters);

  double get savedPercent => inputOrderDistanceMeters <= 0
      ? 0.0
      : (savedDistanceMeters / inputOrderDistanceMeters) * 100.0;
}

class SmartLogisticsUpgradeEngine {
  const SmartLogisticsUpgradeEngine._();

  static String normalizeVietnamPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('84') && digits.length >= 10) {
      return '0${digits.substring(2)}';
    }
    if (!digits.startsWith('0') && digits.length == 9) {
      return '0$digits';
    }
    return digits;
  }

  /// Pillar 1: Chấm điểm tín nhiệm SĐT người nhận & Cảnh báo rủi ro hoàn đơn/bom hàng
  static RecipientTrustProfile evaluateRecipientRisk({
    required String phone,
    required List<ActiveOrderRecord> allOrders,
    required Set<String> flaggedRiskPhones,
  }) {
    final norm = normalizeVietnamPhone(phone);
    if (norm.length < 9) {
      return RecipientTrustProfile(
        normalizedPhone: norm,
        trustScore: 85,
        riskTier: 'Chưa đủ SĐT',
        deliveredCount: 0,
        failedOrReturnedCount: 0,
        isBlacklisted: false,
        recommendation: 'Nhập đủ 10 số để hệ thống tra cứu lịch sử nhận hàng.',
      );
    }

    int delivered = 0;
    int failedOrReturned = 0;
    for (final o in allOrders) {
      if (normalizeVietnamPhone(o.recipientPhone) != norm) continue;
      if (o.status == OrderStatus.delivered && o.paymentStatus != 'RETURNED') {
        delivered++;
      } else if (o.status == OrderStatus.failed ||
          o.status == OrderStatus.returning ||
          o.status == OrderStatus.cancelled ||
          o.paymentStatus == 'RETURNED') {
        failedOrReturned++;
      }
    }

    final isFlagged = flaggedRiskPhones.contains(norm);
    int score = 88 + (delivered * 4) - (failedOrReturned * 22);
    if (isFlagged) score -= 45;
    score = score.clamp(15, 99);

    final String tier;
    final String advice;
    if (isFlagged || score < 60) {
      tier = 'Rủi ro hoàn cao';
      advice =
          'Cảnh báo: SĐT có lịch sử hoàn/bom hàng! Khuyến nghị yêu cầu chuyển khoản trước hoặc thu cọc phí ship.';
    } else if (score < 80) {
      tier = 'Cần gọi xác nhận';
      advice =
          'Khuyến nghị: Gọi xác nhận khung giờ nhận hàng trước khi xuất kho.';
    } else {
      tier = 'Tín nhiệm tốt';
      advice =
          'Khách nhận hàng uy tín ($delivered đơn thành công). Đủ điều kiện giao COD tiêu chuẩn.';
    }

    return RecipientTrustProfile(
      normalizedPhone: norm,
      trustScore: score,
      riskTier: tier,
      deliveredCount: delivered,
      failedOrReturnedCount: failedOrReturned,
      isBlacklisted: isFlagged,
      recommendation: advice,
    );
  }

  /// Pillar 2: Tối ưu lộ trình giao ghép nhiều điểm (Nearest-Neighbor + 2-Opt Local Search TSP)
  static MultiStopRoutePlan optimizeMultiStopRoute({
    required GeoPoint originWarehouse,
    required List<ActiveOrderRecord> candidateOrders,
  }) {
    final activeStops = candidateOrders.take(6).toList();
    if (activeStops.isEmpty) {
      return MultiStopRoutePlan(
        originWarehouse: originWarehouse,
        orderedStops: const [],
        chainedPolyline: [originWarehouse],
        inputOrderDistanceMeters: 0,
        optimizedDistanceMeters: 0,
      );
    }

    double pathCost(List<ActiveOrderRecord> seq) {
      double sum = 0;
      GeoPoint prev = originWarehouse;
      for (final item in seq) {
        sum += GeoMath.distanceMeters(prev, item.dropoffLocation);
        prev = item.dropoffLocation;
      }
      return sum;
    }

    final inputOrderMeters = pathCost(activeStops).round();

    // Bước 1: Khởi tạo lộ trình tham lam Nearest-Neighbor từ Kho xuất phát
    final remaining = List<ActiveOrderRecord>.from(activeStops);
    final route = <ActiveOrderRecord>[];
    GeoPoint cursor = originWarehouse;
    while (remaining.isNotEmpty) {
      remaining.sort(
        (a, b) => GeoMath.distanceMeters(cursor, a.dropoffLocation)
            .compareTo(GeoMath.distanceMeters(cursor, b.dropoffLocation)),
      );
      final chosen = remaining.removeAt(0);
      route.add(chosen);
      cursor = chosen.dropoffLocation;
    }

    // Bước 2: Tinh chỉnh cục bộ 2-Opt để loại bỏ các đoạn cắt chéo
    bool improved = true;
    int guard = 0;
    while (improved && route.length >= 3 && guard < 24) {
      improved = false;
      guard++;
      for (int i = 0; i < route.length - 1; i++) {
        for (int k = i + 1; k < route.length; k++) {
          final candidate = <ActiveOrderRecord>[
            ...route.sublist(0, i),
            ...route.sublist(i, k + 1).reversed,
            ...route.sublist(k + 1),
          ];
          if (pathCost(candidate) + 1.0 < pathCost(route)) {
            route
              ..clear()
              ..addAll(candidate);
            improved = true;
          }
        }
      }
    }

    // The heuristic may not beat a good input order; never return a longer route.
    if (pathCost(route) > pathCost(activeStops)) {
      route
        ..clear()
        ..addAll(activeStops);
    }
    final optimizedMeters = pathCost(route).round();
    final polyline = <GeoPoint>[originWarehouse];
    GeoPoint segStart = originWarehouse;
    for (final stop in route) {
      final segPts = SmartDispatchEngine.generateRoutePolyline(
        segStart,
        stop.dropoffLocation,
        segments: 4,
      );
      polyline.addAll(segPts.skip(1));
      segStart = stop.dropoffLocation;
    }

    return MultiStopRoutePlan(
      originWarehouse: originWarehouse,
      orderedStops: route,
      chainedPolyline: polyline,
      inputOrderDistanceMeters: inputOrderMeters,
      optimizedDistanceMeters: optimizedMeters,
    );
  }
}
