import 'dart:convert';

import '../../domain/entities/geo_point.dart';
import '../../domain/enums/order_status.dart';
import '../../domain/enums/service_type.dart';
import '../../domain/enums/user_role.dart';

class UserAccountRecord {
  final String id;
  String phone;
  String email;
  String passwordHash;
  String fullName;
  SubsystemRole role;
  String defaultAddress;
  GeoPoint defaultLocation;
  String status;
  final String createdAt;

  UserAccountRecord({
    required this.id,
    required this.phone,
    required this.email,
    required this.passwordHash,
    required this.fullName,
    required this.role,
    required this.defaultAddress,
    required this.defaultLocation,
    this.status = 'ACTIVE',
    required this.createdAt,
  });

  String get roleDbCode {
    switch (role) {
      case SubsystemRole.customer:
        return 'CUSTOMER';
      case SubsystemRole.driver:
        return 'DRIVER';
      case SubsystemRole.merchant:
        return 'MERCHANT';
      case SubsystemRole.admin:
        return 'ADMIN';
    }
  }

  static SubsystemRole parseRoleCode(String raw) {
    switch (raw.toUpperCase()) {
      case 'DRIVER':
        return SubsystemRole.driver;
      case 'MERCHANT':
        return SubsystemRole.merchant;
      case 'ADMIN':
        return SubsystemRole.admin;
      default:
        return SubsystemRole.customer;
    }
  }
}

class SavedAddressRecord {
  final String id;
  final String userPhone;
  final String label;
  final String fullAddress;
  final GeoPoint location;

  const SavedAddressRecord({
    required this.id,
    this.userPhone = '0912345678',
    required this.label,
    required this.fullAddress,
    required this.location,
  });
}

class VoucherRecord {
  final String code;
  final String title;
  final String discountLabel;
  final double discountValue;
  final bool isPercentage;
  final double maxDiscount;
  final double minOrderValue;
  final String expiryDate;
  String status;
  final int usageLimit;
  int usedCount;

  VoucherRecord({
    required this.code,
    required this.title,
    required this.discountLabel,
    required this.discountValue,
    required this.isPercentage,
    required this.maxDiscount,
    required this.minOrderValue,
    required this.expiryDate,
    required this.status,
    this.usageLimit = 1000,
    this.usedCount = 0,
  });

  bool get isExpired {
    final parts = expiryDate.trim().split('/');
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        final expiryEnd = DateTime(y, m, d, 23, 59, 59);
        return DateTime.now().isAfter(expiryEnd);
      }
    }
    return false;
  }

  bool get isUsable =>
      status == 'Đang hoạt động' && !isExpired && usedCount < usageLimit;
}

class ChatMessageRecord {
  final String id;
  final String orderId;
  final String senderName;
  final bool isCustomer;
  final String text;
  final String timeLabel;

  const ChatMessageRecord({
    required this.id,
    required this.orderId,
    required this.senderName,
    required this.isCustomer,
    required this.text,
    required this.timeLabel,
  });
}

class NotificationRecord {
  final String id;
  final String category;
  final String title;
  final String timeAgo;
  final String targetGroup;
  final String? recipientKey;
  bool isRead;

  NotificationRecord({
    required this.id,
    required this.category,
    required this.title,
    required this.timeAgo,
    this.targetGroup = 'Khách hàng',
    this.recipientKey,
    this.isRead = false,
  });
}

class DriverApplicantRecord {
  final String id;
  String fullName;
  String phone;
  String citizenId;
  String licensePlate;
  String vehicleType;
  String vehicleColor;
  String approvalStatus;
  bool isOnline;
  GeoPoint location;
  double rating;
  int totalTrips;
  int rejectedCount;
  double walletBalance;
  String bankName;
  String bankAccount;
  bool isElectricVehicle;
  int batteryPercent;
  List<String> attachedKycDocs;

  static bool inferElectricVehicle(String vehicleType) {
    final low = vehicleType.toLowerCase();
    return low.contains('điện') ||
        low.contains('dien') ||
        low.contains('ev') ||
        low.contains('vinfast');
  }

  DriverApplicantRecord({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.citizenId,
    required this.licensePlate,
    required this.vehicleType,
    required this.vehicleColor,
    required this.approvalStatus,
    this.isOnline = false,
    required this.location,
    this.rating = 0,
    this.totalTrips = 0,
    this.rejectedCount = 0,
    this.walletBalance = 0.0,
    this.bankName = '',
    this.bankAccount = '',
    bool? isElectricVehicle,
    int batteryPercent = 95,
    List<String>? attachedKycDocs,
  }) : isElectricVehicle =
           isElectricVehicle ?? inferElectricVehicle(vehicleType),
       batteryPercent = batteryPercent.clamp(0, 100),
       attachedKycDocs = attachedKycDocs ?? <String>[];

  double get acceptanceRate {
    final totalDecisions = totalTrips + rejectedCount;
    if (totalDecisions <= 0) return 1.0;
    return (totalTrips / totalDecisions).clamp(0.0, 1.0);
  }
}

class MerchantApplicantRecord {
  final String id;
  String ownerPhone;
  String storeName;
  String businessType;
  String taxCode;
  String representativeName;
  String openHours;
  String bankName;
  String bankAccount;
  String approvalStatus;
  double codBalance;
  String webhookUrl;
  List<String> attachedKycDocs;

  MerchantApplicantRecord({
    required this.id,
    required this.ownerPhone,
    required this.storeName,
    required this.businessType,
    required this.taxCode,
    required this.representativeName,
    this.openHours = '8:00 AM - 9:00 PM (Thứ 2 - Chủ Nhật)',
    required this.bankName,
    required this.bankAccount,
    required this.approvalStatus,
    this.codBalance = 0.0,
    this.webhookUrl = '',
    List<String>? attachedKycDocs,
  }) : attachedKycDocs = attachedKycDocs ?? <String>[];
}

class ComplaintTicketRecord {
  final String ticketCode;
  final String orderId;
  final String customerName;
  final String driverName;
  final String issueType;
  final String description;
  String status;
  final List<String> replies;
  final List<String> evidenceFiles;

  ComplaintTicketRecord({
    required this.ticketCode,
    required this.orderId,
    required this.customerName,
    required this.driverName,
    required this.issueType,
    required this.description,
    required this.status,
    required this.replies,
    this.evidenceFiles = const [],
  });
}

class WithdrawalRequestRecord {
  final String id;
  final String ownerId;
  final String ownerName;
  final String ownerRole;
  final double amount;
  final String bankName;
  final String accountMasked;
  final String requestDate;
  String status;

  WithdrawalRequestRecord({
    required this.id,
    this.ownerId = '',
    required this.ownerName,
    required this.ownerRole,
    required this.amount,
    required this.bankName,
    required this.accountMasked,
    required this.requestDate,
    required this.status,
  });
}

class CodReconciliationRecord {
  final String id;
  final String merchantId;
  final String periodLabel;
  double totalCodCollected;
  double totalServiceFee;
  double returnCancelFee;
  double netPayoutAmount;
  String status;

  CodReconciliationRecord({
    required this.id,
    required this.merchantId,
    required this.periodLabel,
    required this.totalCodCollected,
    required this.totalServiceFee,
    this.returnCancelFee = 0.0,
    required this.netPayoutAmount,
    required this.status,
  });
}

class GeofenceZoneRecord {
  final String id;
  final String zoneName;
  final String zoneType;
  final double surchargeRate;
  bool isActive;
  final List<GeoPoint> boundary;

  GeofenceZoneRecord({
    required this.id,
    required this.zoneName,
    required this.zoneType,
    required this.surchargeRate,
    required this.isActive,
    required this.boundary,
  });
}

class RbacRoleRecord {
  final String roleName;
  final Map<String, bool> permissions;

  RbacRoleRecord({required this.roleName, required this.permissions});
}

class PickupWarehouseRecord {
  final String id;
  final String merchantId;
  final String name;
  final String address;
  final GeoPoint location;
  final String contactName;
  final String contactPhone;
  final String openHours;
  final bool isPrimary;
  final String webhookUrl;

  const PickupWarehouseRecord({
    required this.id,
    this.merchantId = '',
    required this.name,
    required this.address,
    required this.location,
    this.contactName = '',
    this.contactPhone = '',
    this.openHours = '08:00 - 21:00',
    this.isPrimary = false,
    this.webhookUrl = '',
  });
}

class ActiveOrderRecord {
  final String id;
  final String trackingCode;
  String customerName;
  String recipientName;
  String recipientPhone;
  final String pickupAddress;
  String dropoffAddress;
  final GeoPoint pickupLocation;
  GeoPoint dropoffLocation;
  final DeliveryServiceType serviceType;
  final String packageDescription;
  final double weightKg;
  final String dimensionsCm;
  int distanceMeters;
  int durationSeconds;
  double deliveryFee;
  double surchargeFee;
  final double discountAmount;
  double codAmount;
  double totalAmount;
  String paymentMethod;
  String paymentStatus;
  OrderStatus status;
  String? assignedDriverName;
  String? assignedDriverPlate;
  String? podImageNote;
  String? cancelReason;
  int? ratingStars;
  String? ratingComment;
  final String createdDateLabel;
  final int createdAtMs;
  int? deliveredAtMs;
  bool preferEcoEv;
  double declaredValueVnd;
  double insuranceFee;
  bool isRoundTrip;
  int extraStopCount;
  String? batchGroupId;
  double co2SavedGrams;
  bool greenFundContributed;
  String? publicTrackingToken;

  ActiveOrderRecord({
    required this.id,
    required this.trackingCode,
    required this.customerName,
    required this.recipientName,
    required this.recipientPhone,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.serviceType,
    required this.packageDescription,
    required this.weightKg,
    required this.dimensionsCm,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.deliveryFee,
    required this.surchargeFee,
    required this.discountAmount,
    required this.codAmount,
    required this.totalAmount,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.status,
    this.assignedDriverName,
    this.assignedDriverPlate,
    this.podImageNote,
    this.cancelReason,
    this.ratingStars,
    this.ratingComment,
    required this.createdDateLabel,
    int? createdAtMs,
    this.deliveredAtMs,
    this.preferEcoEv = false,
    this.declaredValueVnd = 0.0,
    this.insuranceFee = 0.0,
    this.isRoundTrip = false,
    this.extraStopCount = 0,
    this.batchGroupId,
    this.co2SavedGrams = 0.0,
    this.greenFundContributed = false,
    this.publicTrackingToken,
  }) : createdAtMs = createdAtMs ?? _parseCreatedAtMs(createdDateLabel);

  static int _parseCreatedAtMs(String label) {
    final now = DateTime.now();
    final trimmed = label.trim();
    if (trimmed == 'Hôm nay' || trimmed.isEmpty) {
      return now.millisecondsSinceEpoch;
    }
    if (trimmed == 'Hôm qua') {
      return now.subtract(const Duration(days: 1)).millisecondsSinceEpoch;
    }
    final datePart = trimmed.split(' ').first;
    final parts = datePart.split('/');
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d, 12).millisecondsSinceEpoch;
      }
    }
    return now.millisecondsSinceEpoch;
  }

  DateTime get createdAtDateTime {
    final trimmed = createdDateLabel.trim();
    if (trimmed == 'Hôm nay') return DateTime.now();
    if (trimmed == 'Hôm qua') {
      return DateTime.now().subtract(const Duration(days: 1));
    }
    final datePart = trimmed.split(' ').first;
    final parts = datePart.split('/');
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d, 12);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  }

  int daysAgoFrom(DateTime now) {
    final todayStart = DateTime(now.year, now.month, now.day);
    final dt = createdAtDateTime;
    final orderDayStart = DateTime(dt.year, dt.month, dt.day);
    final diff = todayStart.difference(orderDayStart).inDays;
    return diff < 0 ? 0 : diff;
  }

  Map<String, Object?> toSqlRow([int? createdAtMs]) {
    return {
      'id': id,
      'tracking_code': trackingCode,
      'customer_name': customerName,
      'recipient_name': recipientName,
      'recipient_phone': recipientPhone,
      'pickup_address': pickupAddress,
      'dropoff_address': dropoffAddress,
      'pickup_lat': pickupLocation.latitude,
      'pickup_lng': pickupLocation.longitude,
      'dropoff_lat': dropoffLocation.latitude,
      'dropoff_lng': dropoffLocation.longitude,
      'service_type': serviceType.name,
      'package_description': packageDescription,
      'weight_kg': weightKg,
      'dimensions_cm': dimensionsCm,
      'distance_meters': distanceMeters,
      'duration_seconds': durationSeconds,
      'delivery_fee': deliveryFee,
      'surcharge_fee': surchargeFee,
      'discount_amount': discountAmount,
      'cod_amount': codAmount,
      'total_amount': totalAmount,
      'payment_method': paymentMethod,
      'payment_status': paymentStatus,
      'status': status.name,
      'assigned_driver_name': assignedDriverName,
      'assigned_driver_plate': assignedDriverPlate,
      'pod_image_note': podImageNote,
      'cancel_reason': cancelReason,
      'rating_stars': ratingStars,
      'rating_comment': ratingComment,
      'created_date_label': createdDateLabel,
      'created_at_ms': createdAtMs ?? this.createdAtMs,
      'delivered_at_ms': deliveredAtMs,
      'prefer_eco_ev': preferEcoEv ? 1 : 0,
      'declared_value_vnd': declaredValueVnd,
      'insurance_fee': insuranceFee,
      'is_round_trip': isRoundTrip ? 1 : 0,
      'extra_stop_count': extraStopCount,
      'batch_group_id': batchGroupId,
      'co2_saved_grams': co2SavedGrams,
      'green_fund_contributed': greenFundContributed ? 1 : 0,
      'public_tracking_token': publicTrackingToken,
    };
  }

  static ActiveOrderRecord fromSqlRow(Map<String, dynamic> row) {
    final svcRaw = (row['service_type'] ?? 'express30m').toString();
    final svc =
        DeliveryServiceType.values
            .where((e) => e.name == svcRaw || e.dbCode == svcRaw)
            .firstOrNull ??
        DeliveryServiceType.fromDbCode(svcRaw);
    final stRaw = (row['status'] ?? 'searching').toString();
    final st =
        OrderStatus.values
            .where((e) => e.name == stRaw || e.dbCode == stRaw)
            .firstOrNull ??
        OrderStatus.searching;

    return ActiveOrderRecord(
      id: row['id'].toString(),
      trackingCode: row['tracking_code'].toString(),
      customerName: row['customer_name'].toString(),
      recipientName: row['recipient_name'].toString(),
      recipientPhone: row['recipient_phone'].toString(),
      pickupAddress: row['pickup_address'].toString(),
      dropoffAddress: row['dropoff_address'].toString(),
      pickupLocation: GeoPoint(
        latitude: (row['pickup_lat'] as num).toDouble(),
        longitude: (row['pickup_lng'] as num).toDouble(),
      ),
      dropoffLocation: GeoPoint(
        latitude: (row['dropoff_lat'] as num).toDouble(),
        longitude: (row['dropoff_lng'] as num).toDouble(),
      ),
      serviceType: svc,
      packageDescription: row['package_description'].toString(),
      weightKg: (row['weight_kg'] as num).toDouble(),
      dimensionsCm: row['dimensions_cm'].toString(),
      distanceMeters: (row['distance_meters'] as num).toInt(),
      durationSeconds: (row['duration_seconds'] as num).toInt(),
      deliveryFee: (row['delivery_fee'] as num).toDouble(),
      surchargeFee: (row['surcharge_fee'] as num).toDouble(),
      discountAmount: (row['discount_amount'] as num).toDouble(),
      codAmount: (row['cod_amount'] as num).toDouble(),
      totalAmount: (row['total_amount'] as num).toDouble(),
      paymentMethod: row['payment_method'].toString(),
      paymentStatus: row['payment_status'].toString(),
      status: st,
      assignedDriverName: row['assigned_driver_name']?.toString(),
      assignedDriverPlate: row['assigned_driver_plate']?.toString(),
      podImageNote: row['pod_image_note']?.toString(),
      cancelReason: row['cancel_reason']?.toString(),
      ratingStars: (row['rating_stars'] as num?)?.toInt(),
      ratingComment: row['rating_comment']?.toString(),
      createdDateLabel: row['created_date_label'].toString(),
      createdAtMs: (row['created_at_ms'] as num?)?.toInt(),
      deliveredAtMs: (row['delivered_at_ms'] as num?)?.toInt(),
      preferEcoEv: row['prefer_eco_ev'] == 1 || row['prefer_eco_ev'] == true,
      declaredValueVnd: (row['declared_value_vnd'] as num? ?? 0.0).toDouble(),
      insuranceFee: (row['insurance_fee'] as num? ?? 0.0).toDouble(),
      isRoundTrip: row['is_round_trip'] == 1 || row['is_round_trip'] == true,
      extraStopCount: (row['extra_stop_count'] as num? ?? 0).toInt(),
      batchGroupId: row['batch_group_id']?.toString(),
      co2SavedGrams: (row['co2_saved_grams'] as num? ?? 0.0).toDouble(),
      greenFundContributed:
          row['green_fund_contributed'] == 1 ||
          row['green_fund_contributed'] == true,
      publicTrackingToken: row['public_tracking_token']?.toString(),
    );
  }
}

class CsvBatchRowResult {
  final int rowNumber;
  final String recipientName;
  final String recipientPhone;
  final String dropoffAddress;
  final String packageDescription;
  final double weightKg;
  final double codAmount;
  final DeliveryServiceType serviceType;
  final bool isValid;
  final String statusNote;
  final String pickupAddress;
  final GeoPoint? pickupLocation;
  final GeoPoint? dropoffLocation;

  const CsvBatchRowResult({
    required this.rowNumber,
    required this.recipientName,
    required this.recipientPhone,
    required this.dropoffAddress,
    required this.packageDescription,
    required this.weightKg,
    required this.codAmount,
    required this.serviceType,
    required this.isValid,
    required this.statusNote,
    this.pickupAddress = '',
    this.pickupLocation,
    this.dropoffLocation,
  });
}

class CsvBatchParseResult {
  final List<CsvBatchRowResult> rows;
  final int validCount;
  final int invalidCount;
  final List<String> createdTrackingCodes;

  const CsvBatchParseResult({
    required this.rows,
    required this.validCount,
    required this.invalidCount,
    required this.createdTrackingCodes,
  });
}

class FoodMenuItemRecord {
  final String id;
  final String merchantId;
  final String storeName;
  final String storeAddress;
  final GeoPoint storeLocation;
  final String name;
  final String description;
  final String category;
  final double priceVnd;
  final int prepMinutes;
  final List<String> mealSlots;
  final bool isEcoPackaging;
  final bool isColdItem;
  final bool hasPromoBadge;
  bool isAvailable;
  final double rating;
  int soldCount;
  final bool isPartnerMerchant;
  final int createdAtMs;

  FoodMenuItemRecord({
    required this.id,
    required this.merchantId,
    required this.storeName,
    required this.storeAddress,
    required this.storeLocation,
    required this.name,
    this.description = '',
    this.category = 'Cơm • Bún • Phở',
    required this.priceVnd,
    this.prepMinutes = 15,
    this.mealSlots = const <String>[
      'breakfast',
      'lunch',
      'afternoonTea',
      'dinner',
    ],
    this.isEcoPackaging = false,
    this.isColdItem = false,
    this.hasPromoBadge = false,
    this.isAvailable = true,
    this.rating = 4.8,
    this.soldCount = 0,
    this.isPartnerMerchant = false,
    this.createdAtMs = 0,
  });

  Map<String, Object?> toSqlRow() => <String, Object?>{
    'id': id,
    'merchant_id': merchantId,
    'store_name': storeName,
    'store_address': storeAddress,
    'latitude': storeLocation.latitude,
    'longitude': storeLocation.longitude,
    'name': name,
    'description': description,
    'category': category,
    'price_vnd': priceVnd,
    'prep_minutes': prepMinutes,
    'meal_slots_json': jsonEncode(mealSlots),
    'is_eco_packaging': isEcoPackaging ? 1 : 0,
    'is_cold_item': isColdItem ? 1 : 0,
    'has_promo_badge': hasPromoBadge ? 1 : 0,
    'is_available': isAvailable ? 1 : 0,
    'rating': rating,
    'sold_count': soldCount,
    'created_at_ms': createdAtMs,
  };

  static FoodMenuItemRecord fromSqlRow(Map<String, dynamic> row) {
    final parsedSlots = <String>[];
    final rawSlots = row['meal_slots_json'];
    if (rawSlots is String && rawSlots.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSlots);
        if (decoded is List) {
          for (final entry in decoded) {
            final s = entry.toString().trim();
            if (s.isNotEmpty) parsedSlots.add(s);
          }
        }
      } catch (_) {}
    } else if (rawSlots is List) {
      for (final entry in rawSlots) {
        final s = entry.toString().trim();
        if (s.isNotEmpty) parsedSlots.add(s);
      }
    }
    return FoodMenuItemRecord(
      id: (row['id'] ?? '').toString(),
      merchantId: (row['merchant_id'] ?? '').toString(),
      storeName: (row['store_name'] ?? '').toString(),
      storeAddress: (row['store_address'] ?? '').toString(),
      storeLocation: GeoPoint(
        latitude: (row['latitude'] as num?)?.toDouble() ?? 10.7769,
        longitude: (row['longitude'] as num?)?.toDouble() ?? 106.6953,
      ),
      name: (row['name'] ?? '').toString(),
      description: (row['description'] ?? '').toString(),
      category: (row['category'] ?? 'Cơm • Bún • Phở').toString(),
      priceVnd: (row['price_vnd'] as num?)?.toDouble() ?? 0.0,
      prepMinutes: (row['prep_minutes'] as num?)?.toInt() ?? 15,
      mealSlots: parsedSlots.isNotEmpty
          ? parsedSlots
          : const <String>['breakfast', 'lunch', 'afternoonTea', 'dinner'],
      isEcoPackaging:
          row['is_eco_packaging'] == 1 || row['is_eco_packaging'] == true,
      isColdItem: row['is_cold_item'] == 1 || row['is_cold_item'] == true,
      hasPromoBadge:
          row['has_promo_badge'] == 1 || row['has_promo_badge'] == true,
      isAvailable: row['is_available'] == null
          ? true
          : (row['is_available'] == 1 || row['is_available'] == true),
      rating: (row['rating'] as num?)?.toDouble() ?? 4.8,
      soldCount: (row['sold_count'] as num?)?.toInt() ?? 0,
      isPartnerMerchant: true,
      createdAtMs: (row['created_at_ms'] as num?)?.toInt() ?? 0,
    );
  }
}
