import 'dart:math' as math;

import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import '../../domain/enums/order_status.dart';
import '../../domain/enums/service_type.dart';
import '../config/env_config.dart';
import '../integrations/delivery_api_client.dart';
import '../utils/geo_math.dart';

class DispatchCandidateScore {
  final DriverApplicantRecord driver;
  final double distanceMeters;
  final int searchRadiusTierMeters;
  final double totalScore;

  const DispatchCandidateScore({
    required this.driver,
    required this.distanceMeters,
    required this.searchRadiusTierMeters,
    required this.totalScore,
  });
}

class OptimizedMultiStopRouteResult {
  final List<Map<String, dynamic>> optimizedStops;
  final int originalDistanceMeters;
  final int optimizedDistanceMeters;
  final int savedDistanceMeters;
  final int estimatedDurationSeconds;
  final List<GeoPoint> routePolyline;

  const OptimizedMultiStopRouteResult({
    required this.optimizedStops,
    required this.originalDistanceMeters,
    required this.optimizedDistanceMeters,
    required this.savedDistanceMeters,
    required this.estimatedDurationSeconds,
    required this.routePolyline,
  });
}

class CoDirectionalBatchMatch {
  final ActiveOrderRecord partnerOrder;
  final double pickupDistanceMeters;
  final double bearingDifferenceDegrees;
  final double combinedWeightKg;
  final int estimatedCombinedDurationSeconds;

  const CoDirectionalBatchMatch({
    required this.partnerOrder,
    required this.pickupDistanceMeters,
    required this.bearingDifferenceDegrees,
    required this.combinedWeightKg,
    required this.estimatedCombinedDurationSeconds,
  });
}

class GeocodedPlaceSuggestion {
  final String title;
  final String fullAddress;
  final GeoPoint location;

  const GeocodedPlaceSuggestion({
    required this.title,
    required this.fullAddress,
    required this.location,
  });
}

class OsrmRouteResult {
  final int distanceMeters;
  final int durationSeconds;
  final List<GeoPoint> polylinePoints;
  final bool isLiveOsrm;

  const OsrmRouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.polylinePoints,
    required this.isLiveOsrm,
  });
}

/// Động cơ Điều phối Tài xế Thông minh
/// Uses backend-managed address lookup and routing.
class SmartDispatchEngine {
  const SmartDispatchEngine._();

  static const List<int> radiusTiersMeters = [3000, 5000, 8000];

  static const int _maxLiveCachedPlaces = 150;
  static final List<GeocodedPlaceSuggestion> _liveCachedPlaces = [];
  static List<GeoPoint>? _lastLiveOsrmPolyline;

  static void _cachePlaceSuggestion(GeocodedPlaceSuggestion suggestion) {
    _liveCachedPlaces.removeWhere(
      (p) =>
          p.fullAddress == suggestion.fullAddress ||
          (GeoMath.distanceMeters(p.location, suggestion.location) < 8.0 &&
              p.title == suggestion.title),
    );
    _liveCachedPlaces.insert(0, suggestion);
    if (_liveCachedPlaces.length > _maxLiveCachedPlaces) {
      _liveCachedPlaces.removeRange(
        _maxLiveCachedPlaces,
        _liveCachedPlaces.length,
      );
    }
  }

  static const List<GeocodedPlaceSuggestion> knownPlaces = [];

  static List<GeocodedPlaceSuggestion> get _allPlaces => [
    ..._liveCachedPlaces,
    ...knownPlaces,
  ];

  static String _foldVietnamese(String input) {
    const groups = <String, String>{
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'e': 'èéẹẻẽêềếệểễ',
      'i': 'ìíịỉĩ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'u': 'ùúụủũưừứựửữ',
      'y': 'ỳýỵỷỹ',
      'd': 'đ',
    };
    var out = input.trim().toLowerCase();
    groups.forEach((ascii, chars) {
      for (var i = 0; i < chars.length; i++) {
        out = out.replaceAll(chars[i], ascii);
      }
    });
    return out;
  }

  /// Search previously verified addresses, including Vietnamese without accents.
  static List<GeocodedPlaceSuggestion> searchAddressSuggestions(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return _allPlaces.take(4).toList();
    final foldedQuery = _foldVietnamese(normalized);
    final tokens = foldedQuery
        .split(RegExp(r'[\s,]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final matches = _allPlaces.where((p) {
      final rawHay = '${p.title} ${p.fullAddress}'.toLowerCase();
      if (rawHay.contains(normalized)) return true;
      final foldedHay = _foldVietnamese(rawHay);
      if (foldedHay.contains(foldedQuery)) return true;
      return tokens.isNotEmpty && tokens.every(foldedHay.contains);
    }).toList();
    if (matches.isNotEmpty) return matches;
    if (_liveCachedPlaces.isNotEmpty) return _liveCachedPlaces.take(5).toList();
    return const <GeocodedPlaceSuggestion>[];
  }

  /// Address lookup through the managed backend; only verified results enter the cache.
  static Future<List<GeocodedPlaceSuggestion>> fetchLiveNominatimSuggestions(
    String query, {
    DeliveryApiClient? api,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return searchAddressSuggestions(trimmed);
    try {
      final response = await (api ?? DeliveryApiClient.instance).request(
        'places',
        query: {'q': trimmed},
      );
      final results = <GeocodedPlaceSuggestion>[];
      for (final row in (response['places'] as List? ?? const [])) {
        if (row is! Map) continue;
        final lat = row['latitude'];
        final lon = row['longitude'];
        final address = row['address'];
        if (lat is! num ||
            lon is! num ||
            !lat.isFinite ||
            !lon.isFinite ||
            lat.abs() > 90 ||
            lon.abs() > 180 ||
            address is! String ||
            address.isEmpty) {
          continue;
        }
        final suggestion = GeocodedPlaceSuggestion(
          title: row['title']?.toString() ?? address,
          fullAddress: address,
          location: GeoPoint(
            latitude: lat.toDouble(),
            longitude: lon.toDouble(),
          ),
        );
        results.add(suggestion);
        _cachePlaceSuggestion(suggestion);
      }
      if (results.isNotEmpty) return results;
    } catch (_) {
      // Keep previously verified places available offline.
    }
    return searchAddressSuggestions(trimmed);
  }

  /// Giải mã chuỗi Encoded Polyline chuẩn Google Maps Directions API (5-bit chunk / ZigZag)
  static List<GeoPoint> decodeGoogleEncodedPolyline(String encoded) {
    final points = <GeoPoint>[];
    var index = 0;
    final len = encoded.length;
    var lat = 0;
    var lng = 0;

    while (index < len) {
      var b = 0;
      var shift = 0;
      var result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < len);
      if (b >= 0x20) break;
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      if (index >= len) break;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < len);
      if (b >= 0x20) break;
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(GeoPoint(latitude: lat / 1e5, longitude: lng / 1e5));
    }
    return points;
  }

  static Future<OsrmRouteResult> fetchLiveOsrmRoute(
    GeoPoint start,
    GeoPoint end, {
    DeliveryApiClient? api,
  }) async {
    try {
      final decoded = await (api ?? DeliveryApiClient.instance).request(
        'route',
        query: {
          'coordinates':
              '${start.longitude},${start.latitude};${end.longitude},${end.latitude}',
        },
      );
      final route = (decoded['routes'] as List).first as Map;
      final distance = route['distance'];
      final duration = route['duration'];
      final coordinates = (route['geometry'] as Map)['coordinates'] as List;
      final points = coordinates
          .map(
            (row) => GeoPoint(
              latitude: (row[1] as num).toDouble(),
              longitude: (row[0] as num).toDouble(),
            ),
          )
          .toList();
      if (distance is num &&
          duration is num &&
          distance.isFinite &&
          duration.isFinite &&
          distance >= 0 &&
          duration >= 0 &&
          points.length >= 2) {
        _lastLiveOsrmPolyline = points;
        return OsrmRouteResult(
          distanceMeters: distance.round(),
          durationSeconds: duration.round(),
          polylinePoints: points,
          isLiveOsrm: true,
        );
      }
    } catch (_) {
      // Estimates remain explicitly marked as offline, never live routing.
    }
    final rawMeters = GeoMath.distanceMeters(start, end);
    final distance = rawMeters < 1
        ? 0
        : (rawMeters * 1.28).round().clamp(50, 3000000);
    return OsrmRouteResult(
      distanceMeters: distance,
      durationSeconds: ((distance / 1000) * 185).round(),
      polylinePoints: generateRoutePolyline(start, end),
      isLiveOsrm: false,
    );
  }

  static Future<String> reverseGeocodeCoordinate(GeoPoint point) async {
    try {
      final response = await DeliveryApiClient.instance.request(
        'reverse',
        query: {
          'lat': point.latitude.toStringAsFixed(5),
          'lon': point.longitude.toStringAsFixed(5),
        },
      );
      final address = response['address'];
      if (address is String && address.isNotEmpty) {
        _cachePlaceSuggestion(
          GeocodedPlaceSuggestion(
            title: address.split(',').take(2).join(','),
            fullAddress: address,
            location: point,
          ),
        );
        return address;
      }
    } catch (_) {
      // Use coordinates when the address service cannot verify this point.
    }
    return 'Tọa độ (${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)})';
  }

  /// Giải mã địa chỉ sang tọa độ GPS thực tế
  static GeoPoint resolveAddressToCoordinate(
    String address, {
    required GeoPoint fallback,
  }) {
    return tryResolveAddressToCoordinate(address) ?? fallback;
  }

  static GeoPoint? tryResolveAddressToCoordinate(String address) {
    final normalized = address.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final folded = _foldVietnamese(normalized);
    for (final p in _allPlaces) {
      final titleLow = p.title.toLowerCase();
      final fullLow = p.fullAddress.toLowerCase();
      if (normalized == titleLow ||
          fullLow == normalized ||
          folded == _foldVietnamese(titleLow) ||
          _foldVietnamese(fullLow) == folded) {
        return p.location;
      }
    }
    return null;
  }

  /// Quãng đường thực tế tối đa trên 100% pin xe máy điện giao hàng (VinFast Evo200/Feliz S ~90km đô thị)
  static const double evFullChargeRangeMeters = 90000.0;

  /// Quãng đường khả dụng ước tính theo % dung lượng pin hiện tại (SoC)
  static double estimateEvUsableRangeMeters(int batteryPercent) {
    return (batteryPercent.clamp(0, 100) / 100.0) * evFullChargeRangeMeters;
  }

  /// Kiểm tra an toàn dung lượng pin xe điện trước khi điều phối:
  /// Đảm bảo pin >= 15% và quãng đường khả dụng >= 1.3 * (quãng đường đón + lộ trình đơn)
  static bool hasSufficientEvBatteryForOrder({
    required DriverApplicantRecord driver,
    required GeoPoint pickupLocation,
    required int orderRouteMeters,
  }) {
    if (!driver.isElectricVehicle) return true;
    if (driver.batteryPercent < 15) return false;
    final distToPickupRoad =
        GeoMath.distanceMeters(driver.location, pickupLocation) * 1.28;
    final requiredWithReserve =
        (distToPickupRoad + math.max(0, orderRouteMeters)) * 1.30;
    return estimateEvUsableRangeMeters(driver.batteryPercent) >=
        requiredWithReserve;
  }

  /// Hạn mức ký quỹ tối thiểu theo giá trị khai báo bảo hiểm / COD của đơn hàng
  static double requiredMinWalletForOrder({
    double codAmount = 0.0,
    double declaredValueVnd = 0.0,
  }) {
    if (declaredValueVnd >= 3000000 || codAmount >= 2000000) {
      return math.max(500000.0, (codAmount * 0.25).clamp(500000.0, 2000000.0));
    }
    return 200000.0;
  }

  /// Kiểm tra tài xế đủ điều kiện nhận đơn giá trị cao / xe điện / xe tải
  static bool isDriverEligibleForOrder({
    required DriverApplicantRecord driver,
    required GeoPoint pickupLocation,
    DeliveryServiceType? serviceType,
    bool requireElectricVehicle = false,
    int totalOrderRouteMeters = 0,
    double declaredValueVnd = 0.0,
    double codAmount = 0.0,
  }) {
    if (requireElectricVehicle && !driver.isElectricVehicle) {
      return false;
    }
    if (serviceType != null) {
      final isTruckDriver = driver.vehicleType.toLowerCase().contains('tải') ||
          driver.vehicleType.toLowerCase().contains('van') ||
          driver.vehicleType.toUpperCase().contains('TRUCK');
      if (serviceType == DeliveryServiceType.truck && !isTruckDriver) {
        return false;
      }
      if (serviceType != DeliveryServiceType.truck && isTruckDriver) {
        return false;
      }
    }
    if (!hasSufficientEvBatteryForOrder(
      driver: driver,
      pickupLocation: pickupLocation,
      orderRouteMeters: totalOrderRouteMeters,
    )) {
      return false;
    }
    final minWallet = requiredMinWalletForOrder(
      codAmount: codAmount,
      declaredValueVnd: declaredValueVnd,
    );
    if (driver.walletBalance < minWallet) {
      return false;
    }
    final isHighValue = declaredValueVnd >= 3000000 || codAmount >= 2000000;
    if (isHighValue && driver.rating > 0 && driver.rating < 4.5) {
      return false;
    }
    return true;
  }

  /// Xếp hạng ứng viên tài xế theo bán kính mở rộng (3km -> 5km -> 8km)
  /// Công thức: Score = 0.5 * DistanceScore + 0.3 * RatingScore + 0.2 * AcceptanceRate (+ EcoBonus)
  static List<DispatchCandidateScore> rankDriversForPickup({
    required GeoPoint pickupLocation,
    required List<DriverApplicantRecord> drivers,
    Set<String> excludedDriverIds = const {},
    bool requireElectricVehicle = false,
    bool preferElectricVehicle = false,
    int totalOrderRouteMeters = 0,
    double declaredValueVnd = 0.0,
    double codAmount = 0.0,
    DeliveryServiceType? serviceType,
  }) {
    final eligible = drivers.where((d) {
      if (!d.isOnline ||
          d.approvalStatus != 'Đã duyệt' ||
          excludedDriverIds.contains(d.id)) {
        return false;
      }
      return isDriverEligibleForOrder(
        driver: d,
        pickupLocation: pickupLocation,
        serviceType: serviceType,
        requireElectricVehicle: requireElectricVehicle,
        totalOrderRouteMeters: totalOrderRouteMeters,
        declaredValueVnd: declaredValueVnd,
        codAmount: codAmount,
      );
    }).toList();

    for (final radiusTier in radiusTiersMeters) {
      final inTier = <DispatchCandidateScore>[];
      for (final d in eligible) {
        final dist = GeoMath.distanceMeters(pickupLocation, d.location);
        if (dist <= radiusTier) {
          final distScore = (1.0 - (dist / radiusTier)).clamp(0.0, 1.0);
          final ratingScore = (d.rating / 5.0).clamp(0.0, 1.0);
          final acceptanceRate =
              (d.acceptanceRate > 1.0
                      ? d.acceptanceRate / 100.0
                      : d.acceptanceRate)
                  .clamp(0.0, 1.0);
          final ecoBonus =
              (preferElectricVehicle && d.isElectricVehicle) ? 0.08 : 0.0;
          final weighted = (0.5 * distScore +
                  0.3 * ratingScore +
                  0.2 * acceptanceRate +
                  ecoBonus)
              .clamp(0.0, 1.08);

          inTier.add(
            DispatchCandidateScore(
              driver: d,
              distanceMeters: dist,
              searchRadiusTierMeters: radiusTier,
              totalScore: weighted,
            ),
          );
        }
      }
      if (inTier.isNotEmpty) {
        inTier.sort((a, b) => b.totalScore.compareTo(a.totalScore));
        return inTier;
      }
    }

    // Fallback khi tài xế ở xa hơn 8km (vẫn xếp hạng theo tổng điểm)
    final allRanked = eligible.map((d) {
      final dist = GeoMath.distanceMeters(pickupLocation, d.location);
      final distScore = (1.0 / (1.0 + dist / 5000.0)).clamp(0.0, 1.0);
      final ratingScore = (d.rating / 5.0).clamp(0.0, 1.0);
      final acceptanceRate =
          (d.acceptanceRate > 1.0 ? d.acceptanceRate / 100.0 : d.acceptanceRate)
              .clamp(0.0, 1.0);
      final ecoBonus =
          (preferElectricVehicle && d.isElectricVehicle) ? 0.08 : 0.0;
      final score =
          (0.5 * distScore + 0.3 * ratingScore + 0.2 * acceptanceRate + ecoBonus)
              .clamp(0.0, 1.08);
      return DispatchCandidateScore(
        driver: d,
        distanceMeters: dist,
        searchRadiusTierMeters: 8000,
        totalScore: score,
      );
    }).toList()..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    return allRanked;
  }

  /// Tối ưu hóa lộ trình đa điểm dừng (Nearest-Neighbor + 2-Opt Local Search TSP)
  /// Hỗ trợ cả giao 1 chiều và giao khứ hồi 2 chiều (quay lại điểm lấy hàng).
  static OptimizedMultiStopRouteResult optimizeMultiStopRoute({
    required GeoPoint pickup,
    required List<Map<String, dynamic>> stops,
    bool isRoundTrip = false,
  }) {
    if (stops.isEmpty) {
      return OptimizedMultiStopRouteResult(
        optimizedStops: const [],
        originalDistanceMeters: 0,
        optimizedDistanceMeters: 0,
        savedDistanceMeters: 0,
        estimatedDurationSeconds: 0,
        routePolyline: [pickup],
      );
    }

    final resolvedStops = <Map<String, dynamic>>[];
    final stopPoints = <GeoPoint>[];

    for (var i = 0; i < stops.length; i++) {
      final clone = Map<String, dynamic>.from(stops[i]);
      final rawLat = clone['latitude'] ?? clone['lat'];
      final rawLng = clone['longitude'] ?? clone['lng'];
      GeoPoint pt;
      if (rawLat is num && rawLng is num) {
        pt = GeoPoint(latitude: rawLat.toDouble(), longitude: rawLng.toDouble());
      } else {
        final addr = (clone['address'] ?? '').toString().trim();
        final cached = tryResolveAddressToCoordinate(addr);
        if (cached != null) {
          pt = cached;
        } else {
          // Nội suy tọa độ xác định quanh điểm lấy khi nhập địa chỉ mới ở chế độ ngoại tuyến
          final seed = addr.codeUnits.fold<int>(i * 97 + 31, (a, b) => a * 31 + b);
          final angle = ((seed.abs() % 360) * math.pi) / 180.0;
          final radiusDeg = 0.012 + ((seed.abs() % 18) * 0.0015);
          pt = GeoPoint(
            latitude: pickup.latitude + math.sin(angle) * radiusDeg,
            longitude: pickup.longitude + math.cos(angle) * radiusDeg,
          );
        }
      }
      clone['latitude'] = pt.latitude;
      clone['longitude'] = pt.longitude;
      resolvedStops.add(clone);
      stopPoints.add(pt);
    }

    double computeTourRoadMeters(List<int> order) {
      var total = 0.0;
      var prev = pickup;
      for (final idx in order) {
        total += GeoMath.distanceMeters(prev, stopPoints[idx]) * 1.28;
        prev = stopPoints[idx];
      }
      if (isRoundTrip) {
        total += GeoMath.distanceMeters(prev, pickup) * 1.28;
      }
      return total;
    }

    final n = stopPoints.length;
    final originalOrder = List<int>.generate(n, (i) => i);
    final originalMeters = computeTourRoadMeters(originalOrder);

    List<int> bestOrder;
    if (n <= 1) {
      bestOrder = originalOrder;
    } else {
      // Bước 1: Dựng lộ trình khởi tạo bằng thuật toán Láng giềng gần nhất (Nearest-Neighbor)
      final unvisited = Set<int>.from(originalOrder);
      final nnOrder = <int>[];
      var current = pickup;
      while (unvisited.isNotEmpty) {
        int? nearestIdx;
        var nearestDist = double.infinity;
        for (final idx in unvisited) {
          final d = GeoMath.distanceMeters(current, stopPoints[idx]);
          if (d < nearestDist) {
            nearestDist = d;
            nearestIdx = idx;
          }
        }
        nnOrder.add(nearestIdx!);
        unvisited.remove(nearestIdx);
        current = stopPoints[nearestIdx];
      }

      bestOrder = computeTourRoadMeters(nnOrder) <= originalMeters
          ? nnOrder
          : List<int>.from(originalOrder);

      // Bước 2: Tinh chỉnh cục bộ 2-Opt tháo gỡ các đoạn đường cắt chéo
      var improved = true;
      while (improved) {
        improved = false;
        final currentBestDist = computeTourRoadMeters(bestOrder);
        for (var i = 0; i < n - 1; i++) {
          for (var k = i + 1; k < n; k++) {
            final candidate = <int>[
              ...bestOrder.sublist(0, i),
              ...bestOrder.sublist(i, k + 1).reversed,
              ...bestOrder.sublist(k + 1),
            ];
            if (computeTourRoadMeters(candidate) + 0.5 < currentBestDist) {
              bestOrder = candidate;
              improved = true;
              break;
            }
          }
          if (improved) break;
        }
      }
    }

    final optimizedMeters = computeTourRoadMeters(bestOrder);
    final reorderedStops =
        bestOrder.map((idx) => resolvedStops[idx]).toList(growable: false);

    final polyline = <GeoPoint>[];
    var legStart = pickup;
    for (final idx in bestOrder) {
      final legPts = generateRoutePolyline(legStart, stopPoints[idx], segments: 6);
      if (polyline.isNotEmpty && legPts.isNotEmpty) {
        polyline.addAll(legPts.skip(1));
      } else {
        polyline.addAll(legPts);
      }
      legStart = stopPoints[idx];
    }
    if (isRoundTrip) {
      final returnPts = generateRoutePolyline(legStart, pickup, segments: 6);
      if (polyline.isNotEmpty && returnPts.isNotEmpty) {
        polyline.addAll(returnPts.skip(1));
      } else {
        polyline.addAll(returnPts);
      }
    }

    final origRounded = originalMeters.round();
    final optRounded = math.min(origRounded, optimizedMeters.round());
    final savedRounded = math.max(0, origRounded - optRounded);
    final durationSec =
        ((optRounded / 1000.0) * 180).round() + (n - 1) * 180;

    return OptimizedMultiStopRouteResult(
      optimizedStops: reorderedStops,
      originalDistanceMeters: origRounded,
      optimizedDistanceMeters: optRounded,
      savedDistanceMeters: savedRounded,
      estimatedDurationSeconds: durationSec,
      routePolyline: polyline,
    );
  }

  /// Đánh giá khả năng ghép 2 đơn nội thành 2H cùng hướng (Co-Directional Batching):
  /// - Cùng gói dịch vụ `SAME_DAY_2H` và không phải đơn khứ hồi 2 chiều
  /// - Khoảng cách giữa 2 điểm lấy hàng <= 1.500m (1.5km)
  /// - Độ lệch góc phương vị (Bearing) giữa 2 vector giao hàng <= 25°
  /// - Tổng khối lượng hàng hóa <= 20kg
  /// - Tổng thời gian hoàn thành dự kiến <= 95 phút (đảm bảo SLA 2 giờ)
  static CoDirectionalBatchMatch? evaluateBatchCompatibility(
    ActiveOrderRecord a,
    ActiveOrderRecord b,
  ) {
    if (a.id == b.id) return null;
    if (a.serviceType != DeliveryServiceType.sameDay2h ||
        b.serviceType != DeliveryServiceType.sameDay2h) {
      return null;
    }
    if (a.isRoundTrip || b.isRoundTrip) return null;
    final batchableStatuses = <OrderStatus>{
      OrderStatus.searching,
      OrderStatus.accepted,
      OrderStatus.arrivingPickup,
    };
    if (!batchableStatuses.contains(b.status)) return null;

    final pickupDist = GeoMath.distanceMeters(a.pickupLocation, b.pickupLocation);
    if (pickupDist > 1500.0) return null;

    final bearingA = GeoMath.bearingDegrees(a.pickupLocation, a.dropoffLocation);
    final bearingB = GeoMath.bearingDegrees(b.pickupLocation, b.dropoffLocation);
    final bearingDiff = GeoMath.angularDifferenceDegrees(bearingA, bearingB);
    if (bearingDiff > 25.0) return null;

    final combinedWeight = a.weightKg + b.weightKg;
    if (combinedWeight > 20.0) return null;

    final seqAB = (pickupDist +
            GeoMath.distanceMeters(b.pickupLocation, a.dropoffLocation) +
            GeoMath.distanceMeters(a.dropoffLocation, b.dropoffLocation)) *
        1.28;
    final seqBA = (pickupDist +
            GeoMath.distanceMeters(b.pickupLocation, b.dropoffLocation) +
            GeoMath.distanceMeters(b.dropoffLocation, a.dropoffLocation)) *
        1.28;
    final bestCombinedRoadMeters = math.min(seqAB, seqBA);
    final combinedDurationSec =
        ((bestCombinedRoadMeters / 1000.0) * 180).round() + 300;
    if (combinedDurationSec > 95 * 60) return null;

    return CoDirectionalBatchMatch(
      partnerOrder: b,
      pickupDistanceMeters: pickupDist,
      bearingDifferenceDegrees: bearingDiff,
      combinedWeightKg: combinedWeight,
      estimatedCombinedDurationSeconds: combinedDurationSec,
    );
  }

  /// Tìm đơn hàng đối tác tối ưu nhất để ghép cặp cùng hướng cho gói Giao nhanh 2H
  static CoDirectionalBatchMatch? findBestBatchPartner(
    ActiveOrderRecord target,
    Iterable<ActiveOrderRecord> pool,
  ) {
    final groupCounts = <String, int>{};
    for (final o in pool) {
      final gid = o.batchGroupId;
      if (gid != null && gid.trim().isNotEmpty) {
        groupCounts[gid] = (groupCounts[gid] ?? 0) + 1;
      }
    }

    final matches = <CoDirectionalBatchMatch>[];
    for (final candidate in pool) {
      if (candidate.id == target.id) continue;
      final existingGroup = candidate.batchGroupId;
      if (existingGroup != null &&
          existingGroup.trim().isNotEmpty &&
          (groupCounts[existingGroup] ?? 0) >= 2) {
        continue;
      }
      final match = evaluateBatchCompatibility(target, candidate);
      if (match != null) {
        matches.add(match);
      }
    }
    if (matches.isEmpty) return null;
    matches.sort((x, y) {
      final scoreX = x.bearingDifferenceDegrees * 25.0 + x.pickupDistanceMeters;
      final scoreY = y.bearingDifferenceDegrees * 25.0 + y.pickupDistanceMeters;
      return scoreX.compareTo(scoreY);
    });
    return matches.first;
  }

  static List<GeoPoint>? get lastLiveOsrmPolyline => _lastLiveOsrmPolyline;

  /// Nội suy danh sách điểm tọa độ Polyline giữa điểm lấy và điểm giao
  static List<GeoPoint> generateRoutePolyline(
    GeoPoint start,
    GeoPoint end, {
    int segments = 10,
  }) {
    final safeSegments = math.max(1, segments);
    final dLat = end.latitude - start.latitude;
    final dLng = end.longitude - start.longitude;
    final chord = math.sqrt(dLat * dLat + dLng * dLng);
    final maxBend = math.min(0.0035, chord * 0.18);
    final points = <GeoPoint>[];
    for (var i = 0; i <= safeSegments; i++) {
      final t = i / safeSegments;
      final bend = (t * (1.0 - t)) * maxBend;
      points.add(
        GeoPoint(
          latitude: start.latitude + dLat * t + bend,
          longitude: start.longitude + dLng * t - bend,
        ),
      );
    }
    return points;
  }

  /// Kiểm tra tài xế đã vào vùng bán kính 100m điểm giao hàng chưa
  static bool isWithinDropoffGeofence({
    required GeoPoint driverLocation,
    required GeoPoint dropoffLocation,
  }) {
    final dist = GeoMath.distanceMeters(driverLocation, dropoffLocation);
    return dist <= EnvConfig.arrivalGeofenceRadiusMeters;
  }
}
