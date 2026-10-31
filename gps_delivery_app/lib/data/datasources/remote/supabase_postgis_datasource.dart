import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/env_config.dart';
import '../../../core/error/app_exception.dart';
import '../../../domain/entities/driver_entity.dart';
import '../../../domain/entities/geo_point.dart';
import '../../../domain/entities/order_entity.dart';
import '../../../domain/enums/order_status.dart';
import '../../../domain/enums/service_type.dart';

/// Datasource kết nối trực tiếp tới cơ sở dữ liệu PostgreSQL + PostGIS trên Supabase
class SupabasePostgisDatasource {
  SupabasePostgisDatasource();
  SupabasePostgisDatasource._pinned(this._sessionClient);
  SupabaseClient? _sessionClient;

  Session? get authenticatedSession {
    try {
      return _requireClient().auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  SupabasePostgisDatasource? pinAuthenticatedSession() {
    final session = authenticatedSession;
    if (session == null) return null;
    final token = session.accessToken;
    return SupabasePostgisDatasource._pinned(
      SupabaseClient(
        EnvConfig.supabaseUrl,
        EnvConfig.supabaseAnonKey,
        accessToken: () async => token,
      ),
    );
  }

  Future<void> disposePinnedSession() async {
    await _sessionClient?.dispose();
    _sessionClient = null;
  }

  static SupabaseClient? _runtimeClient;
  static String? _runtimeBoundUrl;
  static String? _runtimeBoundKey;

  static void bindRuntimeClient(
    String url,
    String anonKey, {
    SupabaseClient? client,
  }) {
    final cleanUrl = url.trim();
    final cleanKey = anonKey.trim();
    if (cleanUrl.isEmpty || cleanKey.isEmpty) {
      _runtimeClient = null;
      _runtimeBoundUrl = null;
      _runtimeBoundKey = null;
      return;
    }
    if (client == null &&
        _runtimeClient != null &&
        _runtimeBoundUrl == cleanUrl &&
        _runtimeBoundKey == cleanKey) {
      return;
    }
    _runtimeBoundUrl = cleanUrl;
    _runtimeBoundKey = cleanKey;
    _runtimeClient = client ?? SupabaseClient(cleanUrl, cleanKey);
  }

  SupabaseClient _requireClient() {
    if (_sessionClient != null) return _sessionClient!;
    if (!EnvConfig.isSupabaseConfigured) {
      throw const NetworkSyncException(
        message: 'Chưa cấu hình SUPABASE_URL / SUPABASE_ANON_KEY. Chuyển sang chế độ lưu trữ SQLite Offline.',
      );
    }
    if (_runtimeClient != null &&
        _runtimeBoundUrl == EnvConfig.supabaseUrl &&
        _runtimeBoundKey == EnvConfig.supabaseAnonKey) {
      return _runtimeClient!;
    }
    try {
      if (_runtimeBoundUrl == null) {
        return Supabase.instance.client;
      }
    } catch (_) {}
    bindRuntimeClient(EnvConfig.supabaseUrl, EnvConfig.supabaseAnonKey);
    return _runtimeClient!;
  }

  /// Truy vấn tổng quát cho bất kỳ bảng nào trong cơ sở dữ liệu
  Future<List<Map<String, dynamic>>> fetchTableRecords(
    String tableName, {
    int limit = 100,
  }) async {
    final client = _requireClient();
    final rows = await client.from(tableName).select().limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  static const Uuid _uuid = Uuid();

  static String toDeterministicUuid(String rawId) {
    final trimmed = rawId.trim();
    if (RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(trimmed)) {
      return trimmed.toLowerCase();
    }
    return _uuid.v5(Namespace.url.value, 'ghst:$trimmed');
  }

  static void _validatePayloadForSync(
    String tableName,
    Map<String, dynamic> payload,
  ) {
    final id = (payload['id'] ?? '').toString().trim();
    if (id.isEmpty) {
      throw FormatException(
        'Không thể đồng bộ bảng $tableName khi thiếu id bản ghi.',
      );
    }
    if (tableName == 'orders') {
      final customerId = (payload['customer_id'] ?? '').toString().trim();
      final pickup =
          payload['pickup_location'] ??
          payload['pickup_lat'] ??
          payload['pickup_lng'];
      final dropoff =
          payload['dropoff_location'] ??
          payload['dropoff_lat'] ??
          payload['dropoff_lng'];
      if (customerId.isEmpty || pickup == null || dropoff == null) {
        throw FormatException(
          'Đơn hàng cần customer_id và tọa độ lấy/giao hàng thật trước khi đồng bộ.',
        );
      }
    }
    if (tableName == 'user_addresses' ||
        tableName == 'merchant_pickup_points') {
      final location =
          payload['location'] ?? payload['latitude'] ?? payload['longitude'];
      if (location == null) {
        throw FormatException(
          'Địa chỉ cần tọa độ đã xác thực trước khi đồng bộ.',
        );
      }
    }
  }

  static String _normalizeApprovalStatus(Object? raw) {
    final v = (raw ?? 'PENDING').toString().trim();
    final up = v.toUpperCase();
    if (up == 'APPROVED' || v == 'Đã duyệt') return 'APPROVED';
    if (up == 'REJECTED' || v == 'Từ chối') return 'REJECTED';
    if (up == 'SUSPENDED' || v == 'Đình chỉ' || v == 'Tạm khóa') {
      return 'SUSPENDED';
    }
    return 'PENDING';
  }

  static String _normalizeVehicleType(Object? raw) {
    final v = (raw ?? 'MOTORBIKE').toString().trim();
    final up = v.toUpperCase();
    final low = v.toLowerCase();
    if (up == 'EV_MOTORBIKE' ||
        up.contains('EV') ||
        low.contains('điện') ||
        low.contains('dien') ||
        low.contains('vinfast')) {
      return 'EV_MOTORBIKE';
    }
    if (up == 'VAN' || v.contains('Van')) return 'VAN';
    if (up == 'TRUCK_1T' || v.contains('1 Tấn') || v.contains('1T')) {
      return 'TRUCK_1T';
    }
    if (up == 'TRUCK_500KG' || v.contains('Tải')) return 'TRUCK_500KG';
    return 'MOTORBIKE';
  }

  static String _normalizeUserRole(Object? raw) {
    final v = (raw ?? 'CUSTOMER').toString().trim();
    final up = v.toUpperCase();
    if (up == 'DRIVER' || v.contains('Tài xế')) return 'DRIVER';
    if (up == 'MERCHANT' || v.contains('Cửa hàng') || v.contains('Người gửi')) {
      return 'MERCHANT';
    }
    if (up == 'ADMIN' || v.contains('Quản trị') || v.contains('Admin')) {
      return 'ADMIN';
    }
    return 'CUSTOMER';
  }

  static String _normalizeUserStatus(Object? raw) {
    final v = (raw ?? 'ACTIVE').toString().trim();
    final up = v.toUpperCase();
    if (up == 'LOCKED' || v == 'Đã khóa') return 'LOCKED';
    if (up == 'SUSPENDED' || v == 'Tạm khóa' || v == 'Đình chỉ') {
      return 'SUSPENDED';
    }
    return 'ACTIVE';
  }

  static String _buildPostgisPolygonEwkt(Object? rawBoundary) {
    if (rawBoundary is String &&
        rawBoundary.toUpperCase().contains('POLYGON')) {
      return rawBoundary;
    }
    final points = <GeoPoint>[];
    Object? decoded = rawBoundary;
    if (rawBoundary is String && rawBoundary.trim().startsWith('[')) {
      try {
        decoded = jsonDecode(rawBoundary);
      } catch (_) {}
    }
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map) {
          final lat = (item['lat'] ?? item['latitude']) as num?;
          final lng = (item['lng'] ?? item['longitude']) as num?;
          if (lat != null && lng != null) {
            points.add(
              GeoPoint(latitude: lat.toDouble(), longitude: lng.toDouble()),
            );
          }
        }
      }
    }
    if (points.length < 3) {
      return 'SRID=4326;POLYGON((106.6950 10.7700, 106.7080 10.7700, 106.7080 10.7830, 106.6950 10.7700))';
    }
    final closed = List<GeoPoint>.from(points);
    if (closed.first.latitude != closed.last.latitude ||
        closed.first.longitude != closed.last.longitude) {
      closed.add(closed.first);
    }
    final ring = closed.map((p) => '${p.longitude} ${p.latitude}').join(', ');
    return 'SRID=4326;POLYGON(($ring))';
  }

  /// Chuẩn hóa dữ liệu bảng SQLite nội bộ sang đúng định dạng cột, ENUM và PostGIS EWKT của 16 bảng PostgreSQL (`database_schema.sql`)
  static Map<String, dynamic> normalizeForPostgisSchema(
    String tableName,
    Map<String, dynamic> payload,
  ) {
    final src = Map<String, dynamic>.from(payload);
    switch (tableName) {
      case 'users':
        final lat = (src['latitude'] as num?)?.toDouble();
        final lng = (src['longitude'] as num?)?.toDouble();
        return <String, dynamic>{
          'id': toDeterministicUuid((src['id'] ?? 'USR-01').toString()),
          'phone': (src['phone'] ?? '').toString(),
          if (src['email'] != null && src['email'].toString().trim().isNotEmpty)
            'email': src['email'].toString().trim(),
          'password_hash': (src['password_hash'] ?? 'BCRYPT-HASH-DEFAULT')
              .toString(),
          'full_name': (src['full_name'] ?? '').toString(),
          if (src['avatar_url'] != null) 'avatar_url': src['avatar_url'],
          if (src['default_address'] != null)
            'default_address': src['default_address'],
          if (src['default_lat_lng'] != null)
            'default_lat_lng': src['default_lat_lng']
          else if (lat != null && lng != null)
            'default_lat_lng': 'SRID=4326;POINT($lng $lat)',
          'role': _normalizeUserRole(src['role']),
          'status': _normalizeUserStatus(src['status']),
        };
      case 'user_addresses':
        final lat = (src['latitude'] as num?)?.toDouble();
        final lng = (src['longitude'] as num?)?.toDouble();
        return <String, dynamic>{
          'id': toDeterministicUuid((src['id'] ?? 'ADDR-01').toString()),
          'user_id': toDeterministicUuid(
            (src['user_id'] ?? src['owner_phone'] ?? 'USR-01').toString(),
          ),
          'label': (src['label'] ?? 'Nhà').toString(),
          'recipient_name': (src['recipient_name'] ?? '').toString(),
          'recipient_phone': (src['recipient_phone'] ?? '').toString(),
          'full_address': (src['full_address'] ?? src['address'] ?? '')
              .toString(),
          if (src['location'] != null)
            'location': src['location']
          else if (lat != null && lng != null)
            'location': 'SRID=4326;POINT($lng $lat)',
          'is_default': src['is_default'] == true || src['is_default'] == 1,
        };
      case 'drivers':
        final lat = (src['latitude'] as num?)?.toDouble();
        final lng = (src['longitude'] as num?)?.toDouble();
        return <String, dynamic>{
          'id': toDeterministicUuid((src['id'] ?? 'DV10928').toString()),
          if (src['user_id'] != null)
            'user_id': toDeterministicUuid(src['user_id'].toString()),
          'phone': (src['phone'] ?? '').toString(),
          'full_name': (src['full_name'] ?? '').toString(),
          'citizen_id': (src['citizen_id'] ?? '').toString(),
          'license_plate': (src['license_plate'] ?? '').toString(),
          'vehicle_type': _normalizeVehicleType(src['vehicle_type']),
          'is_online': src['is_online'] == true || src['is_online'] == 1,
          if (src['current_location'] != null)
            'current_location': src['current_location']
          else if (lat != null && lng != null)
            'current_location': 'SRID=4326;POINT($lng $lat)',
          'current_bearing':
              (src['current_bearing'] as num?)?.toDouble() ?? 0.0,
          'rating_avg':
              ((src['rating_avg'] ?? src['rating']) as num?)?.toDouble() ?? 0.0,
          'acceptance_rate':
              (src['acceptance_rate'] as num?)?.toDouble() ?? 100.0,
          'rejected_count': (src['rejected_count'] as num?)?.toInt() ?? 0,
          if (src['bank_name'] != null) 'bank_name': src['bank_name'],
          if (src['bank_account'] != null) 'bank_account': src['bank_account'],
          'is_electric_vehicle':
              src['is_electric_vehicle'] == true ||
              src['is_electric_vehicle'] == 1 ||
              _normalizeVehicleType(src['vehicle_type']) == 'EV_MOTORBIKE',
          'battery_percent': ((src['battery_percent'] as num?)?.toInt() ?? 95)
              .clamp(0, 100),
          'approval_status': _normalizeApprovalStatus(src['approval_status']),
          'wallet_balance': (src['wallet_balance'] as num?)?.toDouble() ?? 0.0,
        };
      case 'merchants':
        return <String, dynamic>{
          'id': toDeterministicUuid((src['id'] ?? 'MRC-01').toString()),
          'owner_user_id': toDeterministicUuid(
            (src['owner_user_id'] ?? src['contact_phone'] ?? 'USR-03')
                .toString(),
          ),
          'store_name': (src['store_name'] ?? '').toString(),
          'business_type': (src['business_type'] ?? 'Bán lẻ').toString(),
          if (src['tax_code'] != null &&
              src['tax_code'].toString().trim().isNotEmpty)
            'tax_code': src['tax_code'].toString().trim(),
          'representative_name':
              (src['representative_name'] ?? src['store_name'] ?? '')
                  .toString(),
          'contact_phone': (src['contact_phone'] ?? src['phone'] ?? '')
              .toString(),
          if (src['contact_email'] != null)
            'contact_email': src['contact_email'],
          'headquarters_address':
              (src['headquarters_address'] ?? src['address'] ?? '').toString(),
          'bank_name': (src['bank_name'] ?? '').toString(),
          'bank_account_no':
              (src['bank_account_no'] ?? src['bank_account'] ?? '').toString(),
          'bank_account_holder':
              (src['bank_account_holder'] ?? src['representative_name'] ?? '')
                  .toString(),
          'webhook_url': (src['webhook_url'] ?? '').toString(),
          'cod_balance': (src['cod_balance'] as num?)?.toDouble() ?? 0.0,
          'approval_status': _normalizeApprovalStatus(src['approval_status']),
        };
      case 'merchant_pickup_points':
        final lat = (src['latitude'] as num?)?.toDouble();
        final lng = (src['longitude'] as num?)?.toDouble();
        return <String, dynamic>{
          'id': toDeterministicUuid((src['id'] ?? 'WH-01').toString()),
          'merchant_id': toDeterministicUuid(
            (src['merchant_id'] ?? 'MRC-01').toString(),
          ),
          'warehouse_name': (src['warehouse_name'] ?? src['name'] ?? '')
              .toString(),
          'contact_phone': (src['contact_phone'] ?? src['phone'] ?? '')
              .toString(),
          'full_address': (src['full_address'] ?? src['address'] ?? '')
              .toString(),
          if (src['location'] != null)
            'location': src['location']
          else if (lat != null && lng != null)
            'location': 'SRID=4326;POINT($lng $lat)',
          'open_hours':
              (src['open_hours'] ?? '08:00 - 21:00 (Thứ 2 - Chủ Nhật)')
                  .toString(),
          'is_primary': src['is_primary'] == true || src['is_primary'] == 1,
        };
      case 'vouchers':
        final rawType = (src['discount_type'] ?? 'FIXED_AMOUNT')
            .toString()
            .toUpperCase();
        final normType = rawType.contains('PERCENT')
            ? 'PERCENTAGE'
            : rawType.contains('FREE')
            ? 'FREE_SHIPPING'
            : 'FIXED_AMOUNT';
        final rawSt = (src['status'] ?? 'ACTIVE').toString().toUpperCase();
        final normSt =
            (rawSt == 'PENDING' || rawSt == 'EXPIRED' || rawSt == 'DISABLED')
            ? rawSt
            : 'ACTIVE';
        return <String, dynamic>{
          'id': toDeterministicUuid(
            (src['id'] ?? src['code'] ?? 'VCH-01').toString(),
          ),
          'code': (src['code'] ?? '').toString(),
          'title': (src['title'] ?? src['code'] ?? '').toString(),
          'discount_type': normType,
          'discount_value': (src['discount_value'] as num?)?.toDouble() ?? 0.0,
          'min_order_value':
              (src['min_order_value'] as num?)?.toDouble() ?? 0.0,
          if (src['max_discount_amount'] != null)
            'max_discount_amount': (src['max_discount_amount'] as num)
                .toDouble(),
          'usage_limit': (src['usage_limit'] as num?)?.toInt() ?? 1000,
          'used_count': (src['used_count'] as num?)?.toInt() ?? 0,
          'expired_at':
              (src['expired_at'] != null &&
                  DateTime.tryParse(src['expired_at'].toString()) != null)
              ? src['expired_at'].toString()
              : DateTime.utc(2027, 12, 31).toIso8601String(),
          'status': normSt,
        };
      case 'orders':
        final pLat = (src['pickup_lat'] as num?)?.toDouble();
        final pLng = (src['pickup_lng'] as num?)?.toDouble();
        final dLat = (src['dropoff_lat'] as num?)?.toDouble();
        final dLng = (src['dropoff_lng'] as num?)?.toDouble();
        final svc = DeliveryServiceType.fromDbCode(
          (src['service_type'] ?? 'STANDARD').toString(),
        );
        final st = OrderStatus.fromDbCode(
          (src['status'] ?? 'SEARCHING').toString(),
        );
        final rawPayMethod = (src['payment_method'] ?? 'CASH').toString();
        final pgPayMethod =
            rawPayMethod.contains('MoMo') || rawPayMethod == 'MOMO'
            ? 'MOMO'
            : rawPayMethod.contains('VNPay') || rawPayMethod == 'VNPAY'
            ? 'VNPAY'
            : rawPayMethod.contains('ZaloPay') || rawPayMethod == 'ZALOPAY'
            ? 'ZALOPAY'
            : rawPayMethod.contains('Chuyển khoản') ||
                  rawPayMethod == 'BANK_TRANSFER'
            ? 'BANK_TRANSFER'
            : rawPayMethod == 'BANK_CARD'
            ? 'BANK_CARD'
            : 'CASH';
        final rawPayStatus = (src['payment_status'] ?? 'UNPAID').toString();
        final pgPayStatus = rawPayStatus == 'PAID'
            ? 'PAID'
            : rawPayStatus == 'RETURNED'
            ? 'RETURNED'
            : rawPayStatus == 'REFUNDED'
            ? 'REFUNDED'
            : 'UNPAID';
        final rawCustomerId = src['customer_id']?.toString().trim() ?? '';
        final resolvedCustomerId = rawCustomerId.isNotEmpty
            ? rawCustomerId
            : 'USR-01';
        return <String, dynamic>{
          'id': toDeterministicUuid((src['id'] ?? 'ORD-01').toString()),
          'tracking_code': src['tracking_code'],
          'customer_id': toDeterministicUuid(resolvedCustomerId),
          if (src['driver_id'] != null &&
              src['driver_id'].toString().trim().isNotEmpty)
            'driver_id': toDeterministicUuid(src['driver_id'].toString()),
          if (src['merchant_id'] != null &&
              src['merchant_id'].toString().trim().isNotEmpty)
            'merchant_id': toDeterministicUuid(src['merchant_id'].toString()),
          'service_type': svc.dbCode,
          'pickup_address': src['pickup_address'] ?? '',
          if (src['pickup_location'] != null)
            'pickup_location': src['pickup_location']
          else if (pLat != null && pLng != null)
            'pickup_location': 'SRID=4326;POINT($pLng $pLat)',
          'dropoff_address': src['dropoff_address'] ?? '',
          if (src['dropoff_location'] != null)
            'dropoff_location': src['dropoff_location']
          else if (dLat != null && dLng != null)
            'dropoff_location': 'SRID=4326;POINT($dLng $dLat)',
          'sender_name': src['sender_name'] ?? '',
          'sender_phone': src['sender_phone'] ?? '',
          'recipient_name': src['recipient_name'] ?? '',
          'recipient_phone': src['recipient_phone'] ?? '',
          'package_category':
              src['package_category'] ??
              src['package_description'] ??
              'Hàng thông thường',
          'weight_kg': src['weight_kg'] ?? 1.0,
          'dimensions_cm': src['dimensions_cm'],
          'distance_meters': src['distance_meters'] ?? 1000,
          'duration_seconds': src['duration_seconds'] ?? 600,
          'delivery_fee': src['delivery_fee'] ?? 0,
          'surcharge_fee': src['surcharge_fee'] ?? 0,
          'discount_amount': src['discount_amount'] ?? 0,
          'cod_amount': src['cod_amount'] ?? 0,
          'total_amount': src['total_amount'] ?? 0,
          'payment_method': pgPayMethod,
          'payment_status': pgPayStatus,
          'status': st.dbCode,
          'cancel_reason': src['cancel_reason'],
          if (src['pod_image_url'] != null || src['pod_image_note'] != null)
            'pod_image_url': src['pod_image_url'] ?? src['pod_image_note'],
          if (src['pod_otp_code'] != null) 'pod_otp_code': src['pod_otp_code'],
          'prefer_eco_ev':
              src['prefer_eco_ev'] == true || src['prefer_eco_ev'] == 1,
          'declared_value_vnd':
              (src['declared_value_vnd'] as num?)?.toDouble() ?? 0.0,
          'insurance_fee': (src['insurance_fee'] as num?)?.toDouble() ?? 0.0,
          'is_round_trip':
              src['is_round_trip'] == true || src['is_round_trip'] == 1,
          'extra_stop_count': (src['extra_stop_count'] as num?)?.toInt() ?? 0,
          if (src['batch_group_id'] != null)
            'batch_group_id': src['batch_group_id'],
          'co2_saved_grams':
              (src['co2_saved_grams'] as num?)?.toDouble() ?? 0.0,
          'green_fund_contributed':
              src['green_fund_contributed'] == true ||
              src['green_fund_contributed'] == 1,
          if (src['public_tracking_token'] != null)
            'public_tracking_token': src['public_tracking_token'],
          if (src['delivered_at'] != null)
            'delivered_at': src['delivered_at']
          else if (src['delivered_at_ms'] is num)
            'delivered_at': DateTime.fromMillisecondsSinceEpoch(
              (src['delivered_at_ms'] as num).toInt(),
              isUtc: true,
            ).toIso8601String(),
        };
      case 'order_tracking_logs':
        final lat = (src['latitude'] as num?)?.toDouble();
        final lng = (src['longitude'] as num?)?.toDouble();
        return <String, dynamic>{
          'order_id': toDeterministicUuid(
            (src['order_id'] ?? src['order_code'] ?? 'ORD-01').toString(),
          ),
          'driver_id': toDeterministicUuid(
            (src['driver_id'] ?? 'DV10928').toString(),
          ),
          if (src['location'] != null)
            'location': src['location']
          else if (lat != null && lng != null)
            'location': 'SRID=4326;POINT($lng $lat)',
          'speed': (src['speed'] as num?)?.toDouble() ?? 0.0,
          'bearing': (src['bearing'] as num?)?.toDouble() ?? 0.0,
          'is_mock_location':
              src['is_mock_location'] == true || src['is_mock_location'] == 1,
        };
      case 'geofence_zones':
        final rawZt = (src['zone_type'] ?? 'CENTER_ZONE')
            .toString()
            .toUpperCase();
        final normZt = (rawZt == 'SURCHARGE_ZONE' || rawZt == 'RESTRICTED_ZONE')
            ? rawZt
            : 'CENTER_ZONE';
        return <String, dynamic>{
          'id': toDeterministicUuid((src['id'] ?? 'GEO-01').toString()),
          'zone_name': (src['zone_name'] ?? '').toString(),
          'city_name': (src['city_name'] ?? 'TP. Hồ Chí Minh').toString(),
          'zone_type': normZt,
          'polygon_boundary': _buildPostgisPolygonEwkt(
            src['polygon_boundary'] ?? src['boundary_json'] ?? src['boundary'],
          ),
          'surcharge_rate': (src['surcharge_rate'] as num?)?.toDouble() ?? 0.0,
          'is_active': src['is_active'] == true || src['is_active'] == 1,
        };
      case 'pricing_configs':
        final rawSvc = (src['service_type'] ?? 'STANDARD').toString();
        final normSvc = rawSvc == 'STANDARD_V2' ? 'STANDARD' : rawSvc;
        final svcEnum = DeliveryServiceType.fromDbCode(normSvc);
        return <String, dynamic>{
          'id': toDeterministicUuid((src['id'] ?? 'PRC-01').toString()),
          'service_type': svcEnum.dbCode,
          'service_name': (src['service_name'] ?? svcEnum.displayName)
              .toString(),
          'estimated_time_label':
              (src['estimated_time_label'] ?? svcEnum.etaLabel).toString(),
          'base_fare': src['base_fare'] ?? 25000,
          'price_per_km': src['price_per_km'] ?? 5000,
          'peak_hour_surcharge': src['peak_hour_surcharge'] ?? 10000,
          'bad_weather_surcharge': src['bad_weather_surcharge'] ?? 15000,
          'is_peak_enabled':
              src['is_peak_enabled'] == true || src['is_peak_enabled'] == 1,
          'is_weather_enabled':
              src['is_weather_enabled'] == true ||
              src['is_weather_enabled'] == 1,
        };
      case 'wallets_and_transactions':
        final rawOwnerType = (src['owner_type'] ?? 'DRIVER')
            .toString()
            .toUpperCase();
        final ownerType = rawOwnerType.contains('MERCHANT')
            ? 'MERCHANT'
            : 'DRIVER';
        final rawTx = (src['tx_type'] ?? 'DELIVERY_EARNING')
            .toString()
            .toUpperCase();
        const allowedTx = <String>{
          'DELIVERY_EARNING',
          'WITHDRAWAL',
          'COD_PAYOUT',
          'PLATFORM_COMMISSION',
          'REFUND',
          'RETURN_FEE',
          'ESCROW_TOPUP',
          'TIP',
        };
        final txType = allowedTx.contains(rawTx) ? rawTx : 'DELIVERY_EARNING';
        final rawAppr = (src['approval_status'] ?? 'PENDING').toString();
        final apprUp = rawAppr.toUpperCase();
        final appr = (apprUp == 'TRANSFERRED' || rawAppr == 'Đã chuyển')
            ? 'TRANSFERRED'
            : (apprUp == 'APPROVED' || rawAppr == 'Đã duyệt')
            ? 'APPROVED'
            : (apprUp == 'REJECTED' || rawAppr == 'Từ chối')
            ? 'REJECTED'
            : 'PENDING';
        return <String, dynamic>{
          'id': toDeterministicUuid((src['id'] ?? 'TX-01').toString()),
          'owner_id': toDeterministicUuid(
            (src['owner_id'] ?? 'DV10928').toString(),
          ),
          'owner_type': ownerType,
          'balance_after': (src['balance_after'] as num?)?.toDouble() ?? 0.0,
          'tx_type': txType,
          if (src['reference_order_id'] != null)
            'reference_order_id': toDeterministicUuid(
              src['reference_order_id'].toString(),
            ),
          'amount': (src['amount'] as num?)?.toDouble() ?? 0.0,
          if (src['bank_info_snapshot'] != null)
            'bank_info_snapshot': src['bank_info_snapshot'],
          'approval_status': appr,
        };
      case 'cod_reconciliations':
        final rawSt = (src['reconciliation_status'] ?? 'VERIFIED')
            .toString()
            .toUpperCase();
        final normSt = (rawSt == 'DISPUTED' || rawSt == 'PAID')
            ? rawSt
            : 'VERIFIED';
        return <String, dynamic>{
          'id': toDeterministicUuid((src['id'] ?? 'COD-01').toString()),
          'merchant_id': toDeterministicUuid(
            (src['merchant_id'] ?? 'MRC-01').toString(),
          ),
          'period_start': (src['period_start'] ?? '2026-10-01').toString(),
          'period_end': (src['period_end'] ?? '2026-10-31').toString(),
          'total_cod_collected':
              (src['total_cod_collected'] as num?)?.toDouble() ?? 0.0,
          'total_service_fee':
              (src['total_service_fee'] as num?)?.toDouble() ?? 0.0,
          'return_cancel_fee':
              (src['return_cancel_fee'] as num?)?.toDouble() ?? 0.0,
          'net_payout_amount':
              (src['net_payout_amount'] as num?)?.toDouble() ?? 0.0,
          'reconciliation_status': normSt,
        };
      case 'order_ratings':
        return <String, dynamic>{
          'id': toDeterministicUuid((src['id'] ?? 'RAT-01').toString()),
          'order_id': toDeterministicUuid(
            (src['order_id'] ?? src['order_code'] ?? 'ORD-01').toString(),
          ),
          'customer_id': toDeterministicUuid(
            (src['customer_id'] ?? 'USR-01').toString(),
          ),
          'driver_id': toDeterministicUuid(
            (src['driver_id'] ?? 'DV10928').toString(),
          ),
          'stars': ((src['stars'] as num?)?.toInt() ?? 5).clamp(1, 5),
          'tip_amount': (src['tip_amount'] as num?)?.toDouble() ?? 0.0,
          if (src['feedback_tags'] is List)
            'feedback_tags': src['feedback_tags'],
          if (src['comment'] != null) 'comment': src['comment'].toString(),
        };
      case 'incidents_and_complaints':
        final lat = (src['latitude'] as num?)?.toDouble();
        final lng = (src['longitude'] as num?)?.toDouble();
        final rawRes = (src['resolution_status'] ?? src['status'] ?? 'NEW')
            .toString();
        final resUp = rawRes.toUpperCase();
        final normRes =
            (resUp == 'RESOLVED' || rawRes.contains('Đã giải quyết'))
            ? 'RESOLVED'
            : (resUp == 'CLOSED' || rawRes.contains('Đóng'))
            ? 'CLOSED'
            : (resUp == 'PROCESSING' || rawRes.contains('Đang'))
            ? 'PROCESSING'
            : 'NEW';
        return <String, dynamic>{
          'id': toDeterministicUuid((src['id'] ?? 'INC-01').toString()),
          'ticket_code': (src['ticket_code'] ?? src['id'] ?? 'KN-001')
              .toString(),
          'order_id': toDeterministicUuid(
            (src['order_id'] ?? src['order_code'] ?? 'ORD-01').toString(),
          ),
          'reporter_id': toDeterministicUuid(
            (src['reporter_id'] ?? 'USR-01').toString(),
          ),
          'reporter_role': _normalizeUserRole(src['reporter_role']) == 'ADMIN'
              ? 'CUSTOMER'
              : _normalizeUserRole(src['reporter_role']),
          'issue_type': (src['issue_type'] ?? 'Khiếu nại dịch vụ').toString(),
          'description': (src['description'] ?? '').toString(),
          if (src['incident_location'] != null)
            'incident_location': src['incident_location']
          else if (lat != null && lng != null)
            'incident_location': 'SRID=4326;POINT($lng $lat)',
          if (src['admin_reply'] != null) 'admin_reply': src['admin_reply'],
          'resolution_status': normRes,
        };
      case 'chat_messages_and_notifications':
        final rawCat = (src['category'] ?? 'CHAT_MESSAGE')
            .toString()
            .toUpperCase();
        const allowedCats = <String>{
          'CHAT_MESSAGE',
          'ORDER_UPDATE',
          'PROMOTION',
          'SYSTEM_BROADCAST',
        };
        final rawGrp = (src['target_group'] ?? 'INDIVIDUAL')
            .toString()
            .toUpperCase();
        const allowedGrps = <String>{
          'INDIVIDUAL',
          'ALL_USERS',
          'ALL_CUSTOMERS',
          'ALL_DRIVERS',
          'ALL_MERCHANTS',
        };
        return <String, dynamic>{
          'id': toDeterministicUuid((src['id'] ?? 'MSG-01').toString()),
          if (src['order_id'] != null)
            'order_id': toDeterministicUuid(src['order_id'].toString()),
          if (src['sender_id'] != null)
            'sender_id': toDeterministicUuid(src['sender_id'].toString()),
          if (src['recipient_user_id'] != null)
            'recipient_user_id': toDeterministicUuid(
              src['recipient_user_id'].toString(),
            ),
          'target_group': allowedGrps.contains(rawGrp) ? rawGrp : 'INDIVIDUAL',
          'category': allowedCats.contains(rawCat) ? rawCat : 'CHAT_MESSAGE',
          if (src['title'] != null) 'title': src['title'].toString(),
          'content': (src['content'] ?? src['message'] ?? '').toString(),
          'is_read': src['is_read'] == true || src['is_read'] == 1,
        };
      case 'admin_roles_permissions':
        Map<String, dynamic> decodedPerms = const <String, dynamic>{};
        if (src['permissions_json'] is String) {
          try {
            decodedPerms = jsonDecode(
              src['permissions_json'] as String,
            ) as Map<String, dynamic>;
          } catch (_) {}
        }
        return <String, dynamic>{
          'id': toDeterministicUuid(
            (src['id'] ?? src['role_name'] ?? 'Super Admin').toString(),
          ),
          'role_name': src['role_name'],
          'order_permissions': Map.fromEntries(
            decodedPerms.entries.where((e) => e.key.startsWith('Đơn:')),
          ),
          'driver_permissions': Map.fromEntries(
            decodedPerms.entries.where((e) => e.key.startsWith('Tài xế:')),
          ),
          'finance_permissions': Map.fromEntries(
            decodedPerms.entries.where((e) => e.key.startsWith('Tài chính:')),
          ),
          'system_permissions': Map.fromEntries(
            decodedPerms.entries.where(
              (e) =>
                  e.key.startsWith('Hệ thống:') ||
                  e.key.startsWith('User:') ||
                  e.key.startsWith('Khiếu nại:'),
            ),
          ),
        };
      case 'merchant_menu_items':
        final lat = (src['latitude'] as num?)?.toDouble() ?? 10.7769;
        final lng = (src['longitude'] as num?)?.toDouble() ?? 106.6953;
        List<dynamic> slots = const [
          'breakfast',
          'lunch',
          'afternoonTea',
          'dinner',
        ];
        final rawSlots = src['meal_slots_json'];
        if (rawSlots is String && rawSlots.trim().isNotEmpty) {
          try {
            final parsed = jsonDecode(rawSlots);
            if (parsed is List) slots = parsed;
          } catch (_) {}
        } else if (rawSlots is List) {
          slots = rawSlots;
        }
        return <String, dynamic>{
          'id': toDeterministicUuid((src['id'] ?? 'MENU-01').toString()),
          'merchant_id': toDeterministicUuid(
            (src['merchant_id'] ?? 'MER-01').toString(),
          ),
          'store_name': (src['store_name'] ?? '').toString(),
          'store_address': (src['store_address'] ?? '').toString(),
          'store_location':
              src['store_location'] ?? 'SRID=4326;POINT($lng $lat)',
          'name': (src['name'] ?? '').toString(),
          'description': (src['description'] ?? '').toString(),
          'category': (src['category'] ?? 'Cơm • Bún • Phở').toString(),
          'price_vnd': (src['price_vnd'] as num?)?.toDouble() ?? 0.0,
          'prep_minutes': (src['prep_minutes'] as num?)?.toInt() ?? 15,
          'meal_slots_json': slots,
          'is_eco_packaging':
              src['is_eco_packaging'] == true || src['is_eco_packaging'] == 1,
          'is_cold_item':
              src['is_cold_item'] == true || src['is_cold_item'] == 1,
          'has_promo_badge':
              src['has_promo_badge'] == true || src['has_promo_badge'] == 1,
          'is_available': src['is_available'] == null
              ? true
              : (src['is_available'] == true || src['is_available'] == 1),
          'rating': (src['rating'] as num?)?.toDouble() ?? 4.8,
          'sold_count': (src['sold_count'] as num?)?.toInt() ?? 0,
        };
      default:
        if (src.containsKey('id') && src['id'] is String) {
          src['id'] = toDeterministicUuid(src['id'] as String);
        }
        return src;
    }
  }

  /// Upsert bản ghi bất kỳ vào 16 bảng chuẩn hóa (`admin_roles_permissions`, `users`,
  /// `user_addresses`, `drivers`, `merchants`, `merchant_pickup_points`, `pricing_configs`,
  /// `vouchers`, `orders`, `order_tracking_logs`, `geofence_zones`, `wallets_and_transactions`,
  /// `cod_reconciliations`, `order_ratings`, `incidents_and_complaints`, `chat_messages_and_notifications`)
  Future<Map<String, dynamic>> upsertTableRecord(
    String tableName,
    Map<String, dynamic> payload,
  ) async {
    final client = _requireClient();
    _validatePayloadForSync(tableName, payload);
    final pgPayload = normalizeForPostgisSchema(tableName, payload);
    final res = await client
        .from(tableName)
        .upsert(pgPayload)
        .select()
        .single();
    return res;
  }

  Future<OrderEntity> insertOrder(OrderEntity order) async {
    final client = _requireClient();
    _validatePayloadForSync('orders', order.toMap());
    final pgPayload = normalizeForPostgisSchema('orders', order.toMap());
    final response = await client
        .from('orders')
        .insert(pgPayload)
        .select()
        .single();
    return OrderEntity.fromMap(response);
  }

  Future<List<OrderEntity>> fetchCustomerOrders(String customerId) async {
    final client = _requireClient();
    final rows = await client
        .from('orders')
        .select()
        .eq('customer_id', toDeterministicUuid(customerId))
        .order('created_at', ascending: false);

    return rows.map((r) => OrderEntity.fromMap(r)).toList();
  }

  Future<OrderEntity> updateOrderStatus({
    required String orderId,
    required OrderStatus nextStatus,
    String? podImageUrl,
    String? podOtpCode,
  }) async {
    final client = _requireClient();
    final payload = <String, dynamic>{
      'status': nextStatus.dbCode,
      'pod_image_url': ?podImageUrl,
      'pod_otp_code': ?podOtpCode,
      if (nextStatus == OrderStatus.delivered) ...{
        'payment_status': 'PAID',
        'delivered_at': DateTime.now().toUtc().toIso8601String(),
      },
    };

    final response = await client
        .from('orders')
        .update(payload)
        .eq('id', toDeterministicUuid(orderId))
        .select()
        .single();
    return OrderEntity.fromMap(response);
  }

  Future<void> updateDriverOnlineState({
    required String driverId,
    required bool isOnline,
  }) async {
    final client = _requireClient();
    await client
        .from('drivers')
        .update({'is_online': isOnline})
        .eq('id', toDeterministicUuid(driverId));
  }

  Future<void> insertDriverTrackingLog({
    required String driverId,
    String? orderId,
    required GeoPoint smoothedLocation,
    required double speedKmh,
    required double bearing,
    required bool isMockLocation,
  }) async {
    final client = _requireClient();
    final driverUuid = toDeterministicUuid(driverId);
    await client
        .from('drivers')
        .update({
          'current_location': smoothedLocation.toPostgisEwkt(),
          'current_bearing': bearing,
        })
        .eq('id', driverUuid);

    if (orderId != null && orderId != 'NO_ORDER') {
      await client.from('order_tracking_logs').insert({
        'order_id': toDeterministicUuid(orderId),
        'driver_id': driverUuid,
        'location': smoothedLocation.toPostgisEwkt(),
        'speed': speedKmh,
        'bearing': bearing,
        'is_mock_location': isMockLocation,
      });
    }
  }

  Future<List<DriverEntity>> fetchOnlineApprovedDrivers() async {
    final client = _requireClient();
    final rows = await client
        .from('drivers')
        .select()
        .eq('is_online', true)
        .eq('approval_status', 'APPROVED');

    return rows.map((r) => DriverEntity.fromMap(r)).toList();
  }

  Stream<GeoPoint> subscribeToOrderTrackingStream(String orderId) {
    final client = _requireClient();
    return client
        .from('order_tracking_logs')
        .stream(primaryKey: ['id'])
        .eq('order_id', toDeterministicUuid(orderId))
        .order('recorded_at', ascending: false)
        .limit(1)
        .map((rows) {
          if (rows.isEmpty) {
            throw const DatabaseException(
              message: 'Chưa có tín hiệu GPS từ tài xế cho đơn hàng này.',
            );
          }
          final firstRow = rows.first;
          final parsed =
              GeoPoint.tryParsePostgis(firstRow['location']) ??
              ((firstRow['latitude'] is num && firstRow['longitude'] is num)
                  ? GeoPoint(
                      latitude: (firstRow['latitude'] as num).toDouble(),
                      longitude: (firstRow['longitude'] as num).toDouble(),
                    )
                  : null);
          if (parsed == null) {
            throw const DatabaseException(
              message: 'Định dạng tọa độ PostGIS trong order_tracking_logs không hợp lệ.',
            );
          }
          return parsed;
        });
  }
}
