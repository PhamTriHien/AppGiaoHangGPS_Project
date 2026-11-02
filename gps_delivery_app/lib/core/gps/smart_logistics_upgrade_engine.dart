import 'dart:math' as math;
import '../../data/models/app_state_records.dart';
import '../../domain/entities/geo_point.dart';
import '../../domain/enums/order_status.dart';
import '../../domain/enums/service_type.dart';
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
  final int naiveDistanceMeters;
  final int optimizedDistanceMeters;
  final double savedFeeVnd;

  const MultiStopRoutePlan({
    required this.originWarehouse,
    required this.orderedStops,
    required this.chainedPolyline,
    required this.naiveDistanceMeters,
    required this.optimizedDistanceMeters,
    required this.savedFeeVnd,
  });

  int get savedDistanceMeters =>
      math.max(0, naiveDistanceMeters - optimizedDistanceMeters);

  double get savedPercent => naiveDistanceMeters <= 0
      ? 0.0
      : (savedDistanceMeters / naiveDistanceMeters) * 100.0;
}

class AiSlaInsightReport {
  final double predictedSlaOnTimePercent;
  final int extraCongestionMinutes;
  final String hotspotZoneName;
  final String peakWindowAdvice;
  final List<String> actionRecommendations;

  const AiSlaInsightReport({
    required this.predictedSlaOnTimePercent,
    required this.extraCongestionMinutes,
    required this.hotspotZoneName,
    required this.peakWindowAdvice,
    required this.actionRecommendations,
  });
}

class OmnichannelOrderSeed {
  final String channelName;
  final String externalOrderCode;
  final String recipientName;
  final String recipientPhone;
  final String dropoffAddress;
  final String packageDescription;
  final double weightKg;
  final double codAmount;
  final DeliveryServiceType serviceType;

  const OmnichannelOrderSeed({
    required this.channelName,
    required this.externalOrderCode,
    required this.recipientName,
    required this.recipientPhone,
    required this.dropoffAddress,
    required this.packageDescription,
    required this.weightKg,
    required this.codAmount,
    required this.serviceType,
  });
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
        naiveDistanceMeters: 0,
        optimizedDistanceMeters: 0,
        savedFeeVnd: 0,
      );
    }

    // Khoảng cách đặt lẻ từng chuyến (Origin -> Stop_i)
    int naiveMeters = 0;
    for (final ord in activeStops) {
      final d = (GeoMath.distanceMeters(originWarehouse, ord.dropoffLocation) *
              1.28)
          .round();
      naiveMeters += d;
      if (activeStops.length > 1) {
        // Phản ánh quãng đường tài xế phải quay đầu hoặc điều xe rời rạc
        naiveMeters += (d * 0.42).round();
      }
    }

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
    double pathCost(List<ActiveOrderRecord> seq) {
      double sum = 0;
      GeoPoint prev = originWarehouse;
      for (final item in seq) {
        sum += GeoMath.distanceMeters(prev, item.dropoffLocation);
        prev = item.dropoffLocation;
      }
      return sum;
    }

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

    final optimizedMeters = (pathCost(route) * 1.28).round();
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

    final savedKm = math.max(0.0, (naiveMeters - optimizedMeters) / 1000.0);
    final savedVnd = route.length <= 1
        ? 0.0
        : ((savedKm * 5200) + ((route.length - 1) * 6500)).roundToDouble();

    return MultiStopRoutePlan(
      originWarehouse: originWarehouse,
      orderedStops: route,
      chainedPolyline: polyline,
      naiveDistanceMeters: naiveMeters,
      optimizedDistanceMeters: optimizedMeters,
      savedFeeVnd: savedVnd,
    );
  }

  /// Pillar 3: Trợ lý AI Phân tích Vận hành & Dự báo SLA / Điểm nóng nhu cầu
  static AiSlaInsightReport analyzeOperationsAndSla({
    required List<ActiveOrderRecord> orders,
    required List<DriverApplicantRecord> drivers,
    required bool isPeakActive,
    required bool isWeatherActive,
  }) {
    final total = math.max(1, orders.length);
    final failedOrReturned = orders
        .where(
          (o) =>
              o.status == OrderStatus.failed ||
              o.status == OrderStatus.returning ||
              o.paymentStatus == 'RETURNED',
        )
        .length;
    final onlineDrivers =
        drivers.where((d) => d.isOnline && d.approvalStatus == 'Đã duyệt').length;

    int extraMins = 0;
    if (isPeakActive) extraMins += 8;
    if (isWeatherActive) extraMins += 11;
    if (onlineDrivers <= 1) extraMins += 6;

    double sla = 98.4 -
        ((failedOrReturned / total) * 18.0) -
        (isPeakActive ? 2.1 : 0.0) -
        (isWeatherActive ? 3.4 : 0.0);
    sla = sla.clamp(78.5, 99.5);

    final activeInTransit = orders
        .where(
          (o) =>
              o.status == OrderStatus.searching ||
              o.status == OrderStatus.inTransit ||
              o.status == OrderStatus.arrivingPickup,
        )
        .length;

    final recommendations = <String>[
      if (activeInTransit >= 2)
        'Gom $activeInTransit đơn đang chờ/giao vào lộ trình ghép tuyến 2-Opt để giảm ~24% quãng đường rỗng.',
      if (isPeakActive || isWeatherActive)
        'Cộng tự động +$extraMins phút vào cam kết ETA khách hàng do phụ phí Cao điểm/Thời tiết đang bật.',
      if (failedOrReturned > 0)
        'Kích hoạt bộ lọc CRM Cảnh báo SĐT rủi ro cho $failedOrReturned đơn hoàn/sự cố để giảm tỷ lệ giao thất bại.',
      'Khung giờ vàng xuất kho tiếp theo: 14:00 - 16:00 ($onlineDrivers tài xế đã duyệt đang trực tuyến quanh tâm kho).',
    ];

    return AiSlaInsightReport(
      predictedSlaOnTimePercent: sla,
      extraCongestionMinutes: extraMins,
      hotspotZoneName: 'Quận 1 - Quận 3 - Bình Thạnh (Mật độ cao)',
      peakWindowAdvice: extraMins > 0
          ? 'Đang cao điểm (+$extraMins phút ETA) — Ưu tiên ghép tuyến đa điểm'
          : 'Luồng giao thông thông thoáng — Tốc độ trung bình 32–35 km/h',
      actionRecommendations: recommendations,
    );
  }

  /// Pillar 1b: Dữ liệu đồng bộ đơn tự động từ Sàn TMĐT / POS (Shopee, TikTok Shop, Sapo)
  static List<OmnichannelOrderSeed> buildMarketplaceSyncBatch(String channel) {
    switch (channel) {
      case 'TikTok Shop':
        return const [
          OmnichannelOrderSeed(
            channelName: 'TikTok Shop',
            externalOrderCode: 'TTS-88241',
            recipientName: 'Hoàng Ngọc Bảo Trâm',
            recipientPhone: '0908112233',
            dropoffAddress: '215 Điện Biên Phủ, Quận Bình Thạnh, TP. HCM',
            packageDescription: '[TikTok #TTS-88241] Bộ ấm trà gốm Bát Tràng (Dễ vỡ)',
            weightKg: 2.2,
            codAmount: 480000,
            serviceType: DeliveryServiceType.express30m,
          ),
          OmnichannelOrderSeed(
            channelName: 'TikTok Shop',
            externalOrderCode: 'TTS-88242',
            recipientName: 'Đỗ Quốc Hưng',
            recipientPhone: '0917334455',
            dropoffAddress: '86 Nguyễn Thị Minh Khai, Quận 3, TP. HCM',
            packageDescription: '[TikTok #TTS-88242] Bình hoa men rạn cao cấp (Dễ vỡ)',
            weightKg: 1.8,
            codAmount: 350000,
            serviceType: DeliveryServiceType.standard,
          ),
        ];
      case 'Sapo POS':
        return const [
          OmnichannelOrderSeed(
            channelName: 'Sapo POS',
            externalOrderCode: 'SAPO-5091',
            recipientName: 'Võ Thị Thanh Ngân',
            recipientPhone: '0938667788',
            dropoffAddress: '102 Cách Mạng Tháng 8, Quận 3, TP. HCM',
            packageDescription: '[Sapo #SAPO-5091] Đèn ngủ gốm thủ công',
            weightKg: 1.6,
            codAmount: 0,
            serviceType: DeliveryServiceType.standard,
          ),
        ];
      default:
        return const [
          OmnichannelOrderSeed(
            channelName: 'Shopee Mall',
            externalOrderCode: 'SPX-99410',
            recipientName: 'Lý Minh Khôi',
            recipientPhone: '0903556677',
            dropoffAddress: '68 Nguyễn Huệ, Quận 1, TP. HCM',
            packageDescription: '[Shopee #SPX-99410] Set 6 đĩa gốm xuất khẩu (Dễ vỡ)',
            weightKg: 3.1,
            codAmount: 620000,
            serviceType: DeliveryServiceType.express30m,
          ),
          OmnichannelOrderSeed(
            channelName: 'Shopee Mall',
            externalOrderCode: 'SPX-99411',
            recipientName: 'Trương Mỹ Linh',
            recipientPhone: '0977445566',
            dropoffAddress: '190 Pasteur, Quận 3, TP. HCM',
            packageDescription: '[Shopee #SPX-99411] Chậu cây bonsai mini',
            weightKg: 1.4,
            codAmount: 240000,
            serviceType: DeliveryServiceType.saving,
          ),
        ];
    }
  }
}

