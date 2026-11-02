import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/env_config.dart';
import '../../../core/config/local_auth_config.dart';
import '../../../core/gps/gps_integrity_validator.dart';
import '../../../core/gps/grab_food_recommendation_engine.dart';
import '../../../core/gps/kalman_gps_filter.dart';
import '../../../core/gps/smart_dispatch_engine.dart';
import '../../../core/gps/smart_logistics_upgrade_engine.dart';
import '../../../core/promotions/promo_event_gamification_engine.dart';
import '../../../core/integrations/live_delivery_service.dart';
import '../../../core/integrations/push_notification_service.dart';
import '../../../core/utils/geo_math.dart';
import '../../../core/utils/platform_file_and_browser_bridge.dart';
import '../../../core/utils/security_and_barcode_utils.dart';
import '../../../domain/entities/geo_point.dart';
import '../../../domain/entities/pricing_estimate.dart';
import '../../../domain/enums/order_status.dart';
import '../../../domain/enums/service_type.dart';
import '../../../domain/enums/user_role.dart';
import '../remote/supabase_postgis_datasource.dart';
import 'sqlite_offline_queue_datasource.dart';

import '../../models/app_state_records.dart';
export '../../../core/gps/grab_food_recommendation_engine.dart';
export '../../../core/gps/smart_logistics_upgrade_engine.dart';
export '../../../core/promotions/promo_event_gamification_engine.dart';
export '../../models/app_state_records.dart';

part 'app_state_seed_and_hydration.dart';
part 'app_state_auth_and_gps_ops.dart';
part 'app_state_order_and_admin_ops.dart';
part 'app_state_demo_cleanup.dart';
part 'app_state_commercial_ops.dart';
part 'app_state_live_delivery_ops.dart';
part 'app_state_customer_ops.dart';
part 'app_state_smart_upgrades_ops.dart';

class AppStateStore extends ChangeNotifier {
  static final AppStateStore instance = AppStateStore._internal();

  final SqliteOfflineQueueDatasource _sqliteDb =
      SqliteOfflineQueueDatasource.instance;
  final KalmanGpsFilter _kalmanFilter = KalmanGpsFilter();
  bool isOfflineMode = false;
  int offlineQueueCount = 0;
  bool isDriverOnline = false;
  bool isMap3dEnabled = false;
  double currentCameraPitch = 55.0;
  int batteryPercent = 85;
  double currentSpeedKmh = 0.0;
  bool isDatabaseReady = false;
  Future<void>? _initializingDbFuture;

  GeoPoint activeDriverLocation = const GeoPoint(
    latitude: 10.7776,
    longitude: 106.6916,
  );
  double activeDriverBearing = 0.0;
  int routeProgressStep = 0;
  List<GeoPoint> activeRoutePolyline = const [];
  String currentAdminRoleName = 'Super Admin';
  String lastSyncStatusMessage = 'Dữ liệu trên thiết bị';

  final Map<String, GeoPoint> verifiedDriverLocations = {};
  final Map<String, StreamSubscription<List<Map<String, dynamic>>>> _liveRooms =
      {};
  final Map<String, String> _liveRoomRoles = {};
  final Map<String, String> _publishedStatuses = {};
  final Map<String, DateTime> _lastPublishedGps = {};
  final Map<String, DateTime> _lastRemoteStatus = {};
  final Map<String, String> liveRoomMessages = {};
  final Map<String, String> liveEvidencePaths = {};
  final Set<String> _seenLiveEvents = {};
  bool _applyingLiveEvents = false;

  GeoPoint? verifiedLocationForOrder(ActiveOrderRecord? order) {
    if (order == null || order.assignedDriverName == null) return null;
    final matches = drivers.where(
      (driver) =>
          driver.fullName == order.assignedDriverName &&
          driver.licensePlate == order.assignedDriverPlate,
    );
    return matches.length == 1
        ? verifiedDriverLocations[matches.single.id]
        : null;
  }

  GeoPoint? liveDeviceLocation;
  double? liveDeviceAccuracyMeters;
  String liveDeviceAddress = '';
  bool isLiveGpsStreaming = false;
  bool isAcquiringLiveGps = false;
  String liveGpsStatusMessage = 'Đang chờ tín hiệu định vị thiết bị...';
  DateTime? lastLiveGpsFixAt;
  GeoPoint? _lastReverseGeocodedDevicePoint;
  bool _hasHardwareKalmanLock = false;
  StreamSubscription<Position>? _liveGpsStreamSub;
  Future<GeoPoint?>? _acquiringLiveGpsFuture;

  bool get hasRealDeviceGpsFix => liveDeviceLocation != null;

  final Map<String, String> registeredUserPasswordHashes = {};
  final Map<String, String> activeOtpCodesByPhone = {};
  final Map<String, int> otpExpiryEpochMsByPhone = {};
  final Set<String> processedPaymentSignatures = {};

  String customerFullName = '';
  String customerPhone = '';
  String customerEmail = '';
  String customerDefaultAddress = '';
  String customerGender = 'Chưa cập nhật';
  int customerAvatarBadgeIndex = 0;
  bool isCustomerGoogleLinked = false;
  bool isCustomerTwoFactorEnabled = false;
  String? selectedCustomerOrderCode;

  String activeDriverId = '';
  String activeDriverName = '';
  String activeDriverPhone = '';
  String? selectedDriverOrderCode;

  double baseFareConfig = 25000;
  double pricePerKmConfig = 5000;
  double peakHourSurchargeConfig = 10000;
  double badWeatherSurchargeConfig = 15000;
  bool isPeakSurchargeActive = false;
  bool isWeatherSurchargeActive = false;

  String merchantStoreName = '';
  String merchantBusinessType = '';
  String merchantTaxCode = '';
  String merchantRepresentative = '';
  String merchantOpenHours = '';
  String merchantBankName = '';
  String merchantBankAccount = '';
  double merchantCodBalance = 0;
  double driverWalletBalance = 0;

  UserAccountRecord? activeAuthenticatedUser;
  final Map<String, Map<String, dynamic>> userPreferencesByPhone = {};
  final List<UserAccountRecord> users = [];
  final List<SavedAddressRecord> savedAddresses = [];
  final List<PickupWarehouseRecord> merchantWarehouses = [];
  final List<VoucherRecord> vouchers = [];
  final List<ActiveOrderRecord> orders = [];
  final List<ChatMessageRecord> chatMessages = [];
  final List<NotificationRecord> notifications = [];
  final List<DriverApplicantRecord> drivers = [];
  final List<MerchantApplicantRecord> merchantApplicants = [];
  final List<ComplaintTicketRecord> complaints = [];
  final List<WithdrawalRequestRecord> withdrawalRequests = [];
  final List<CodReconciliationRecord> codReconciliations = [];
  final List<GeofenceZoneRecord> geofenceZones = [];
  final List<RbacRoleRecord> rbacRoles = [];
  final List<FoodMenuItemRecord> merchantMenuItems = [];
  final List<ScheduledPickupRequestRecord> scheduledPickupRequests = [];
  final Set<String> flaggedRiskPhones = {};
  final Map<String, String> quickDeliveryInstructionsByOrder = {};
  bool isMultiStopRouteActive = false;
  final List<Map<String, dynamic>> systemAuditLogs = [];

  AppStateStore._internal() {
    _sqliteDb.syncScopeProvider = () => _currentSyncScope;
    _initializeDefaultRoles();
    initializeDatabase();
  }

  /// Đường dẫn tệp cơ sở dữ liệu JSON/SQLite lưu trữ bền vững trên đĩa hệ thống
  String get snapshotFilePath {
    if (kIsWeb) {
      return 'localStorage://gps_delivery_state_snapshot.json';
    }
    final suffix = Platform.environment.containsKey('FLUTTER_TEST')
        ? '_${pid}_${_sqliteDb.runtimeSessionId}'
        : '';
    return '${Directory.systemTemp.path}${Platform.pathSeparator}gps_delivery_state_snapshot$suffix.json';
  }

  String get sqliteDatabasePath => _sqliteDb.databaseFilePath;

  Future<String> saveStateSnapshotToDisk({
    String actionType = 'STATE_SNAPSHOT',
    Map<String, dynamic>? actionPayload,
  }) async {
    final snapshot = <String, dynamic>{
      'savedAtIso': DateTime.now().toIso8601String(),
      'sqliteDatabasePath': _sqliteDb.databaseFilePath,
      'driverWalletBalance': driverWalletBalance,
      'merchantCodBalance': merchantCodBalance,
      'customerFullName': customerFullName,
      'customerPhone': customerPhone,
      'customerEmail': customerEmail,
      'customerGender': customerGender,
      'customerAvatarBadgeIndex': customerAvatarBadgeIndex,
      'isCustomerGoogleLinked': isCustomerGoogleLinked,
      'isCustomerTwoFactorEnabled': isCustomerTwoFactorEnabled,
      'userPreferencesByPhone': userPreferencesByPhone,
      'baseFareConfig': baseFareConfig,
      'pricePerKmConfig': pricePerKmConfig,
      'peakHourSurchargeConfig': peakHourSurchargeConfig,
      'badWeatherSurchargeConfig': badWeatherSurchargeConfig,
      'isPeakSurchargeActive': isPeakSurchargeActive,
      'isWeatherSurchargeActive': isWeatherSurchargeActive,
      'processedPaymentSignatures': processedPaymentSignatures.toList(),
      'orders': orders.map((o) => o.toSqlRow()).toList(),
    };
    final shouldEnqueueOffline =
        isOfflineMode &&
        actionType != 'TOGGLE_OFFLINE' &&
        actionType != 'STATE_SNAPSHOT';
    if (shouldEnqueueOffline) {
      try {
        await _sqliteDb.enqueueAction(
          actionType: actionType,
          payload: actionPayload ?? {'snapshotSaved': true},
        );
      } catch (_) {}
    }
    try {
      if (kIsWeb) {
        await _sqliteDb.upsertEntityRecord(
          tableName: 'web_state_snapshot',
          recordId: 'MAIN',
          payload: snapshot,
        );
      } else {
        final file = File(snapshotFilePath);
        await file.writeAsString(jsonEncode(snapshot), flush: true);
      }
    } catch (_) {}
    return snapshotFilePath;
  }

  Future<int>? _syncDrain;

  String? get _currentSyncScope {
    final local = activeAuthenticatedUser;
    final session = SupabasePostgisDatasource().authenticatedSession;
    if (local == null || session == null) return null;
    final cloud = session.user;
    final sameEmail =
        local.email.trim().isNotEmpty &&
        local.email.trim().toLowerCase() == cloud.email?.trim().toLowerCase();
    final samePhone =
        local.phone.trim().isNotEmpty &&
        _normalizePhone(local.phone) == _normalizePhone(cloud.phone ?? '');
    if (!sameEmail && !samePhone) return null;
    return jsonEncode([
      EnvConfig.supabaseUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
      cloud.id,
      local.id,
    ]);
  }

  Future<int> drainOfflineSyncQueue() {
    final pending = _syncDrain;
    if (pending != null) return pending;
    late final Future<int> operation;
    operation = _drainOfflineSyncQueue().whenComplete(() {
      if (identical(_syncDrain, operation)) _syncDrain = null;
    });
    _syncDrain = operation;
    return operation;
  }

  Future<int> _drainOfflineSyncQueue() async {
    int syncedCount = 0;
    final scope = _currentSyncScope;
    if (isOfflineMode || scope == null) return 0;
    final remote = SupabasePostgisDatasource().pinAuthenticatedSession();
    if (remote == null) return 0;
    try {
      final pending = await _sqliteDb.getPendingSyncItems(
        limit: 500,
        ownerScope: scope,
      );
      for (final item in pending) {
        if (isOfflineMode || scope != _currentSyncScope) break;
        if (EnvConfig.isSupabaseConfigured) {
          try {
            final table = item.payload['table']?.toString();
            final record = item.payload['record'];
            if (item.actionType == 'UPDATE_ORDER_STATUS' &&
                item.payload['order_id'] != null) {
              await remote.updateOrderStatus(
                orderId: item.payload['order_id'].toString(),
                nextStatus: OrderStatus.fromDbCode(
                  (item.payload['status'] ?? 'IN_TRANSIT').toString(),
                ),
                podImageUrl: item.payload['pod_image_url']?.toString(),
                podOtpCode: item.payload['pod_otp_code']?.toString(),
              );
            } else if (item.actionType == 'DRIVER_TOGGLE_ONLINE' &&
                item.payload['driver_id'] != null) {
              await remote.updateDriverOnlineState(
                driverId: item.payload['driver_id'].toString(),
                isOnline:
                    item.payload['is_online'] == true ||
                    item.payload['is_online'] == 1,
              );
            } else if (item.actionType == 'DRIVER_LOCATION_PING' &&
                item.payload['driver_id'] != null &&
                item.payload['latitude'] is num &&
                item.payload['longitude'] is num) {
              await remote.insertDriverTrackingLog(
                driverId: item.payload['driver_id'].toString(),
                orderId: null,
                smoothedLocation: GeoPoint(
                  latitude: (item.payload['latitude'] as num).toDouble(),
                  longitude: (item.payload['longitude'] as num).toDouble(),
                ),
                speedKmh: (item.payload['speed'] as num? ?? 0.0).toDouble(),
                bearing: (item.payload['bearing'] as num? ?? 0.0).toDouble(),
                isMockLocation:
                    item.payload['is_mock_location'] == true ||
                    item.payload['is_mock_location'] == 1,
              );
            } else if (table != null && record is Map) {
              await remote.upsertTableRecord(
                table,
                Map<String, dynamic>.from(record),
              );
            } else {
              // Keep unsupported commands pending until their remote handler exists.
              throw StateError('Unsupported sync command');
            }
            await _sqliteDb.markSynced(item.id);
            syncedCount++;
          } on StateError {
            // Missing handlers must not exhaust the retry budget.
            continue;
          } catch (_) {
            await _sqliteDb.incrementRetry(item.id, item.retryCount);
          }
        }
      }
      if (!isOfflineMode && scope == _currentSyncScope) {
        offlineQueueCount = await _sqliteDb.getPendingQueueCount();
        if (pending.isNotEmpty) {
          lastSyncStatusMessage = offlineQueueCount > 0
              ? 'Con $offlineQueueCount thao tac chua duoc may chu xac nhan'
              : 'Da dong bo $syncedCount thao tac duoc may chu xac nhan';
          _notifyStoreChanged();
        }
      }
    } catch (_) {
      lastSyncStatusMessage =
          'Chưa đồng bộ được; thao tác vẫn được giữ trên máy.';
      _notifyStoreChanged();
    } finally {
      await remote.disposePinnedSession();
    }
    return syncedCount;
  }

  Future<bool> loadStateSnapshotFromDisk() async {
    await initializeDatabase();
    try {
      final Map<String, dynamic> decoded;
      if (kIsWeb) {
        final rows = await _sqliteDb.getEntityRecords('web_state_snapshot');
        if (rows.isEmpty) return isDatabaseReady;
        decoded = rows.first;
      } else {
        final file = File(snapshotFilePath);
        if (!await file.exists()) return isDatabaseReady;
        final raw = await file.readAsString();
        decoded = jsonDecode(raw) as Map<String, dynamic>;
      }
      customerFullName =
          decoded['customerFullName']?.toString() ?? customerFullName;
      customerPhone = decoded['customerPhone']?.toString() ?? customerPhone;
      customerEmail = decoded['customerEmail']?.toString() ?? customerEmail;
      customerGender = decoded['customerGender']?.toString() ?? customerGender;
      customerAvatarBadgeIndex =
          (decoded['customerAvatarBadgeIndex'] as num?)?.toInt() ??
          customerAvatarBadgeIndex;
      if (decoded.containsKey('isCustomerGoogleLinked')) {
        isCustomerGoogleLinked = decoded['isCustomerGoogleLinked'] == true;
      }
      if (decoded.containsKey('isCustomerTwoFactorEnabled')) {
        isCustomerTwoFactorEnabled =
            decoded['isCustomerTwoFactorEnabled'] == true;
      }
      final rawPrefs = decoded['userPreferencesByPhone'];
      if (rawPrefs is Map) {
        rawPrefs.forEach((k, v) {
          if (v is Map) {
            userPreferencesByPhone[k.toString()] = Map<String, dynamic>.from(v);
          }
        });
      }
      driverWalletBalance =
          activeDriverRecord?.walletBalance ??
          (decoded['driverWalletBalance'] as num?)?.toDouble() ??
          driverWalletBalance;
      merchantCodBalance =
          activeMerchantRecord?.codBalance ??
          (decoded['merchantCodBalance'] as num?)?.toDouble() ??
          merchantCodBalance;
      final sigs = decoded['processedPaymentSignatures'];
      if (sigs is List) {
        processedPaymentSignatures
          ..clear()
          ..addAll(sigs.map((e) => e.toString()));
      }
      notifyListeners();
      return true;
    } catch (_) {
      return isDatabaseReady;
    }
  }

  void _persistMutation(String actionType, Map<String, dynamic> payload) {
    final nowIso = DateTime.now().toIso8601String();
    final logEntry = <String, dynamic>{
      'action': actionType,
      'actor': activeAuthenticatedUser?.fullName ?? currentAdminRoleName,
      'role': activeAuthenticatedUser?.roleDbCode ?? 'SYSTEM',
      'summary': jsonEncode(payload),
      'timestamp': nowIso,
    };
    systemAuditLogs.insert(0, logEntry);
    if (systemAuditLogs.length > 80) {
      systemAuditLogs.removeRange(80, systemAuditLogs.length);
    }
    _sqliteDb
        .upsertEntityRecord(
          tableName: 'system_audit_logs',
          recordId:
              'AUDIT-${DateTime.now().millisecondsSinceEpoch}-${systemAuditLogs.length}',
          payload: logEntry,
        )
        .catchError((_) {});
    if (isOfflineMode && actionType != 'TOGGLE_OFFLINE') {
      offlineQueueCount += 1;
      lastSyncStatusMessage =
          'Đang lưu tạm $offlineQueueCount bản ghi vào SQLite local_sync_queue';
    }
    saveStateSnapshotToDisk(actionType: actionType, actionPayload: payload);
    if (EnvConfig.isSupabaseConfigured && !isOfflineMode) {
      final table = payload['table']?.toString();
      final record = payload['record'];
      if (table != null && record is Map<String, dynamic>) {
        unawaited(_persistRemoteMutation(actionType, payload));
      }
    }
  }

  Future<void> _persistRemoteMutation(
    String actionType,
    Map<String, dynamic> payload,
  ) async {
    try {
      // Persist before sending, including online writes that might time out.
      await _sqliteDb.enqueueAction(actionType: actionType, payload: payload);
      await drainOfflineSyncQueue();
      offlineQueueCount = await _sqliteDb.getPendingQueueCount();
      if (offlineQueueCount > 0) {
        lastSyncStatusMessage =
            'Còn $offlineQueueCount thao tác lưu trên máy, chưa được máy chủ xác nhận.';
      }
    } catch (_) {
      lastSyncStatusMessage = 'Không lưu được hàng đợi đồng bộ. Hãy thử lại.';
    }
    _notifyStoreChanged();
  }

  Future<List<Map<String, dynamic>>> fetchOrderStatusHistories(
    String orderId,
  ) async {
    try {
      final rows = await _sqliteDb.getEntityRecords('order_status_histories');
      return rows.where((r) => r['order_id']?.toString() == orderId).toList();
    } catch (_) {
      return const [];
    }
  }

  String allocateUniqueId(
    String prefix,
    Iterable<String> existingIds, {
    int minNumber = 1,
    int padDigits = 2,
  }) {
    final existingSet = existingIds.toSet();
    int maxNum = minNumber - 1;
    for (final raw in existingSet) {
      if (raw.startsWith(prefix)) {
        final suffix = raw.substring(prefix.length);
        final parsed = int.tryParse(suffix);
        if (parsed != null && parsed > maxNum) {
          maxNum = parsed;
        }
      }
    }
    int next = maxNum + 1;
    String candidate = '$prefix${next.toString().padLeft(padDigits, '0')}';
    while (existingSet.contains(candidate)) {
      next++;
      candidate = '$prefix${next.toString().padLeft(padDigits, '0')}';
    }
    return candidate;
  }

  String allocateUniqueTrackingCode() {
    final existingCodes = orders.map((o) => o.trackingCode).toSet();
    int step = orders.length;
    String candidate = '#DH${100000 + step * 1423}';
    while (existingCodes.contains(candidate)) {
      step++;
      candidate = '#DH${100000 + step * 1423}';
    }
    return candidate;
  }

  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('84') && digits.length >= 10) {
      return '0${digits.substring(2)}';
    }
    if (!digits.startsWith('0') && digits.length == 9) {
      return '0$digits';
    }
    return digits;
  }

  /// Truy vấn bản ghi người dùng từ bảng `users` theo số điện thoại
  UserAccountRecord? findUserByPhone(String phone) {
    final norm = _normalizePhone(phone);
    if (norm.isEmpty) return null;
    return users.where((u) => _normalizePhone(u.phone) == norm).firstOrNull;
  }

  /// Truy vấn bản ghi người dùng từ bảng `users` theo Số điện thoại hoặc Email
  UserAccountRecord? findUserByPhoneOrEmail(String identifier) {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.contains('@')) {
      final lowerEmail = trimmed.toLowerCase();
      return users
          .where((u) => u.email.trim().toLowerCase() == lowerEmail)
          .firstOrNull;
    }
    return findUserByPhone(trimmed);
  }

  /// Truy vấn bản ghi tài xế đang hoạt động trong bảng `drivers` của CSDL SQLite
  DriverApplicantRecord? get activeDriverRecord {
    if (activeDriverId.isNotEmpty) {
      final byId = drivers.where((d) => d.id == activeDriverId).firstOrNull;
      if (byId != null) return byId;
    }
    final normActivePhone = _normalizePhone(activeDriverPhone);
    if (normActivePhone.isNotEmpty) {
      final byPhone = drivers
          .where((d) => _normalizePhone(d.phone) == normActivePhone)
          .firstOrNull;
      if (byPhone != null) return byPhone;
    }
    if (activeAuthenticatedUser != null &&
        activeAuthenticatedUser!.role == SubsystemRole.driver) {
      return null;
    }
    return drivers.firstOrNull;
  }

  /// Truy vấn bản ghi đối tác cửa hàng đang hoạt động trong bảng `merchants` của CSDL SQLite
  MerchantApplicantRecord? get activeMerchantRecord {
    final authPhone = activeAuthenticatedUser?.phone;
    if (authPhone != null && authPhone.isNotEmpty) {
      final byAuth = merchantApplicants
          .where(
            (m) => _normalizePhone(m.ownerPhone) == _normalizePhone(authPhone),
          )
          .firstOrNull;
      if (byAuth != null) return byAuth;
      if (activeAuthenticatedUser?.role == SubsystemRole.merchant) {
        return merchantApplicants
            .where((m) => m.storeName == merchantStoreName)
            .firstOrNull;
      }
      return null;
    }
    final byStore = merchantApplicants
        .where((m) => m.storeName == merchantStoreName)
        .firstOrNull;
    return byStore ?? merchantApplicants.firstOrNull;
  }

  /// Kiểm tra một tọa độ GPS có nằm trong vùng cấm giao nhận (`RESTRICTED_ZONE`) đang bật hay không
  GeofenceZoneRecord? findActiveRestrictedZoneForPoint(GeoPoint pt) {
    for (final z in geofenceZones) {
      if (z.isActive &&
          z.zoneType == 'RESTRICTED_ZONE' &&
          z.boundary.length >= 3 &&
          GeoMath.isPointInPolygon(pt, z.boundary)) {
        return z;
      }
    }
    return null;
  }

  /// Kiểm tra điểm lấy hoặc điểm giao của lộ trình có vi phạm `RESTRICTED_ZONE` hay không
  GeofenceZoneRecord? findActiveRestrictedZoneForRoute(
    GeoPoint pickup,
    GeoPoint dropoff,
  ) {
    return findActiveRestrictedZoneForPoint(pickup) ??
        findActiveRestrictedZoneForPoint(dropoff);
  }

  /// Tính tổng phụ phí vùng địa lý (`SURCHARGE_ZONE`) cho tọa độ giao nhận
  double computeGeofenceSurchargeForPoint(GeoPoint pt) {
    double surcharge = 0;
    for (final z in geofenceZones) {
      if (z.isActive &&
          z.zoneType != 'RESTRICTED_ZONE' &&
          z.surchargeRate > 0 &&
          z.boundary.length >= 3 &&
          GeoMath.isPointInPolygon(pt, z.boundary)) {
        surcharge += z.surchargeRate;
      }
    }
    return surcharge;
  }

  /// Danh sách phân hệ đã mở khóa hợp lệ cho tài khoản đăng nhập hiện tại
  List<SubsystemRole> unlockedRolesForUser(UserAccountRecord user) {
    if (user.role == SubsystemRole.admin) {
      return const [SubsystemRole.admin];
    }
    final normPhone = _normalizePhone(user.phone);
    final roles = <SubsystemRole>[];
    void addUnique(SubsystemRole r) {
      if (!roles.contains(r)) roles.add(r);
    }

    addUnique(user.role);
    final hasApprovedDriver = drivers.any(
      (d) =>
          _normalizePhone(d.phone) == normPhone &&
          d.approvalStatus == 'Đã duyệt',
    );
    final hasApprovedMerchant = merchantApplicants.any(
      (m) =>
          _normalizePhone(m.ownerPhone) == normPhone &&
          m.approvalStatus == 'Đã duyệt',
    );
    if (hasApprovedDriver) addUnique(SubsystemRole.driver);
    if (hasApprovedMerchant) addUnique(SubsystemRole.merchant);
    addUnique(SubsystemRole.customer);
    return roles;
  }

  /// Chuyến hàng đang thực thi dở dang của tài xế đang đăng nhập (nếu có)
  ActiveOrderRecord? get activeDriverInProgressOrder {
    return driverPersonalOrders
        .where(
          (o) =>
              o.status == OrderStatus.accepted ||
              o.status == OrderStatus.arrivingPickup ||
              o.status == OrderStatus.inTransit ||
              o.status == OrderStatus.returning,
        )
        .firstOrNull;
  }

  List<PickupWarehouseRecord> get merchantPersonalWarehouses {
    final merchant = activeMerchantRecord;
    if (merchant == null) return const [];
    return merchantWarehouses
        .where((w) => w.merchantId == merchant.id)
        .toList();
  }

  /// Truy vấn vận đơn đang hoạt động ưu tiên từ bảng `orders` của CSDL SQLite
  ActiveOrderRecord? get activeOrderRecord {
    if (selectedDriverOrderCode != null) {
      final selected = orders
          .where((o) => o.trackingCode == selectedDriverOrderCode)
          .firstOrNull;
      if (selected != null) {
        return selected;
      }
    }
    final targetDriver = activeDriverName.trim().toLowerCase();
    if (targetDriver.isNotEmpty) {
      final myInProgress = orders
          .where(
            (o) =>
                o.assignedDriverName != null &&
                o.assignedDriverName!.trim().toLowerCase() == targetDriver &&
                o.paymentStatus != 'RETURNED' &&
                (o.status == OrderStatus.inTransit ||
                    o.status == OrderStatus.returning ||
                    o.status == OrderStatus.arrivingPickup ||
                    o.status == OrderStatus.accepted ||
                    o.status == OrderStatus.failed),
          )
          .firstOrNull;
      if (myInProgress != null) return myInProgress;
    }
    final inProgress = orders
        .where(
          (o) =>
              o.paymentStatus != 'RETURNED' &&
              (o.status == OrderStatus.inTransit ||
                  o.status == OrderStatus.returning ||
                  o.status == OrderStatus.arrivingPickup ||
                  o.status == OrderStatus.accepted ||
                  o.status == OrderStatus.failed),
        )
        .firstOrNull;
    if (inProgress != null) return inProgress;
    final searching = orders
        .where((o) => o.status == OrderStatus.searching)
        .firstOrNull;
    return searching ?? orders.firstOrNull;
  }

  /// Vận đơn đang thực hiện hoặc được chọn thuộc riêng về tài xế đang đăng nhập
  ActiveOrderRecord? get activeDriverPersonalOrderRecord {
    final myOrders = driverPersonalOrders;
    if (myOrders.isEmpty) return null;
    if (selectedDriverOrderCode != null) {
      final selected = myOrders
          .where((o) => o.trackingCode == selectedDriverOrderCode)
          .firstOrNull;
      if (selected != null) return selected;
    }
    final inProgress = myOrders
        .where(
          (o) =>
              o.paymentStatus != 'RETURNED' &&
              (o.status == OrderStatus.inTransit ||
                  o.status == OrderStatus.returning ||
                  o.status == OrderStatus.arrivingPickup ||
                  o.status == OrderStatus.accepted ||
                  o.status == OrderStatus.failed),
        )
        .firstOrNull;
    return inProgress ?? myOrders.firstOrNull;
  }

  void selectDriverOrder(String trackingCode) {
    selectedDriverOrderCode = trackingCode;
    final matched = orders
        .where((o) => o.trackingCode == trackingCode)
        .firstOrNull;
    if (matched != null) {
      activeRoutePolyline = matched.status == OrderStatus.returning
          ? SmartDispatchEngine.generateRoutePolyline(
              matched.dropoffLocation,
              matched.pickupLocation,
              segments: 10,
            )
          : SmartDispatchEngine.generateRoutePolyline(
              matched.pickupLocation,
              matched.dropoffLocation,
              segments: 10,
            );
    }
    _notifyStoreChanged();
  }

  /// Kiểm tra khách hàng hiện tại đã cập nhật số điện thoại thực hay chưa
  bool get hasUserProvidedPhone {
    if (customerPhone.trim().isEmpty) return false;
    if (customerEmail.trim().isNotEmpty) {
      final cleanEmail = customerEmail.trim().toLowerCase();
      final synthetic =
          '09${10000000 + (cleanEmail.hashCode.abs() % 89999999)}';
      if (_normalizePhone(customerPhone) == synthetic) {
        return false;
      }
    }
    return true;
  }

  /// Số điện thoại hiển thị trên giao diện Khách hàng (rỗng nếu mới đăng nhập Google OAuth chưa nhập SĐT)
  String get displayCustomerPhone => hasUserProvidedPhone ? customerPhone : '';

  /// Kiểm tra xem tài khoản theo SĐT có đang bật bảo mật 2 lớp (2FA OTP) hay không
  bool isUserTwoFactorEnabled(String phone) {
    final norm = _normalizePhone(phone);
    final prefs = userPreferencesByPhone[norm];
    if (prefs != null && prefs.containsKey('twoFactorEnabled')) {
      return prefs['twoFactorEnabled'] == true;
    }
    return false;
  }

  /// Danh sách vận đơn thuộc về khách hàng đang đăng nhập
  List<ActiveOrderRecord> get customerOrders {
    final targetName = customerFullName.trim().toLowerCase();
    if (targetName.isEmpty) return const [];
    return orders
        .where((o) => o.customerName.trim().toLowerCase() == targetName)
        .toList();
  }

  /// Vận đơn đang hoạt động hoặc được chọn của khách hàng đang đăng nhập
  ActiveOrderRecord? get activeCustomerOrderRecord {
    final list = customerOrders;
    if (selectedCustomerOrderCode != null) {
      final matched = list
          .where((o) => o.trackingCode == selectedCustomerOrderCode)
          .firstOrNull;
      if (matched != null) return matched;
    }
    final inProgress = list
        .where(
          (o) =>
              o.paymentStatus != 'RETURNED' &&
              (o.status == OrderStatus.inTransit ||
                  o.status == OrderStatus.returning ||
                  o.status == OrderStatus.arrivingPickup ||
                  o.status == OrderStatus.accepted ||
                  o.status == OrderStatus.searching ||
                  o.status == OrderStatus.failed),
        )
        .firstOrNull;
    return inProgress ?? list.firstOrNull;
  }

  void selectCustomerOrder(String trackingCode) {
    selectedCustomerOrderCode = trackingCode;
    final matched = orders
        .where((o) => o.trackingCode == trackingCode)
        .firstOrNull;
    if (matched != null) {
      activeRoutePolyline = SmartDispatchEngine.generateRoutePolyline(
        matched.pickupLocation,
        matched.dropoffLocation,
        segments: 10,
      );
    }
    _notifyStoreChanged();
  }

  /// Danh sách địa chỉ đã lưu thuộc về khách hàng đang đăng nhập
  List<SavedAddressRecord> get customerSavedAddresses {
    final norm = _normalizePhone(customerPhone);
    if (norm.isEmpty) return const [];
    return savedAddresses
        .where((a) => _normalizePhone(a.userPhone) == norm)
        .toList();
  }

  /// Danh sách thông báo dành cho khách hàng đang đăng nhập
  List<NotificationRecord> get customerNotifications {
    final myCodes = customerOrders.map((o) => o.trackingCode).toSet();
    final normPhone = _normalizePhone(customerPhone);
    final lowerName = customerFullName.trim().toLowerCase();
    return notifications.where((n) {
      if (n.targetGroup == 'Tài xế' || n.targetGroup == 'Cửa hàng B2B') {
        return false;
      }
      final rk = n.recipientKey?.trim().toLowerCase();
      if (rk != null && rk.isNotEmpty) {
        return rk == normPhone || (lowerName.isNotEmpty && rk == lowerName);
      }
      if (n.title.contains('#DH')) {
        return myCodes.any((code) => n.title.contains(code));
      }
      return true;
    }).toList();
  }

  /// Danh sách thông báo dành cho tài xế đang đăng nhập
  List<NotificationRecord> get driverNotifications {
    final activeDrv = activeDriverRecord;
    final drvIdLower = (activeDrv?.id ?? activeDriverId).trim().toLowerCase();
    final drvNameLower = (activeDrv?.fullName ?? activeDriverName)
        .trim()
        .toLowerCase();
    final myCodes = driverPersonalOrders.map((o) => o.trackingCode).toSet();
    return notifications.where((n) {
      if (n.targetGroup != 'Tất cả người dùng' && n.targetGroup != 'Tài xế') {
        return false;
      }
      final rk = n.recipientKey?.trim().toLowerCase();
      if (rk != null && rk.isNotEmpty) {
        return (drvIdLower.isNotEmpty && rk == drvIdLower) ||
            (drvNameLower.isNotEmpty && rk == drvNameLower);
      }
      if (n.title.contains('#DH')) {
        return myCodes.any((code) => n.title.contains(code));
      }
      return true;
    }).toList();
  }

  /// Danh sách vận đơn được gán trực tiếp cho tài xế đang đăng nhập
  List<ActiveOrderRecord> get driverPersonalOrders {
    final targetDriver = (activeDriverRecord?.fullName ?? activeDriverName)
        .trim()
        .toLowerCase();
    if (targetDriver.isEmpty) return const [];
    return orders
        .where(
          (o) =>
              o.assignedDriverName != null &&
              o.assignedDriverName!.trim().toLowerCase() == targetDriver,
        )
        .toList();
  }

  /// Lịch sử biến động ví & lệnh rút thuộc riêng về tài xế đang đăng nhập
  List<WithdrawalRequestRecord> get driverPersonalTransactions {
    final activeDrv = activeDriverRecord;
    final targetId = activeDrv?.id ?? activeDriverId;
    final targetName = (activeDrv?.fullName ?? activeDriverName)
        .trim()
        .toLowerCase();
    return withdrawalRequests.where((w) {
      if (!w.ownerRole.startsWith('Tài xế')) return false;
      if (w.ownerId.isNotEmpty && targetId.isNotEmpty) {
        return w.ownerId == targetId;
      }
      return targetName.isNotEmpty &&
          w.ownerName.trim().toLowerCase() == targetName;
    }).toList();
  }

  /// Danh sách vận đơn thuộc về cửa hàng B2B đang đăng nhập (không lẫn đơn B2C khách lẻ)
  List<ActiveOrderRecord> get merchantPersonalOrders {
    final activeMer = activeMerchantRecord;
    final storeLower = (activeMer?.storeName ?? merchantStoreName)
        .trim()
        .toLowerCase();
    final repLower = (activeMer?.representativeName ?? '').trim().toLowerCase();
    if (storeLower.isEmpty && repLower.isEmpty) return const [];
    return orders.where((o) {
      final custLower = o.customerName.trim().toLowerCase();
      final grabStoreLower =
          GrabFoodRecommendationEngine.extractGrabFoodStoreNameFromDescription(
            o.packageDescription,
          )?.trim().toLowerCase();
      return (storeLower.isNotEmpty &&
              (custLower == storeLower || grabStoreLower == storeLower)) ||
          (repLower.isNotEmpty && custLower == repLower);
    }).toList();
  }

  /// Danh sách thực đơn ăn uống (GrabFood) thuộc riêng cửa hàng B2B đang đăng nhập
  List<FoodMenuItemRecord> get activeMerchantPersonalMenuItems {
    final activeMer = activeMerchantRecord;
    final merId = (activeMer?.id ?? '').trim();
    final storeLower = (activeMer?.storeName ?? merchantStoreName)
        .trim()
        .toLowerCase();
    if (merId.isEmpty && storeLower.isEmpty) return const [];
    return merchantMenuItems.where((item) {
      if (merId.isNotEmpty && item.merchantId.trim() == merId) return true;
      return storeLower.isNotEmpty &&
          item.storeName.trim().toLowerCase() == storeLower;
    }).toList();
  }

  /// Danh sách khiếu nại thuộc về cửa hàng B2B đang đăng nhập
  List<ComplaintTicketRecord> get merchantPersonalComplaints {
    final myOrderCodes = merchantPersonalOrders
        .map((o) => o.trackingCode)
        .toSet();
    final activeMer = activeMerchantRecord;
    final storeLower = (activeMer?.storeName ?? merchantStoreName)
        .trim()
        .toLowerCase();
    return complaints.where((c) {
      return myOrderCodes.contains(c.orderId) ||
          (storeLower.isNotEmpty &&
              c.customerName.trim().toLowerCase() == storeLower);
    }).toList();
  }

  /// Danh sách lệnh rút COD thuộc về cửa hàng B2B đang đăng nhập
  List<WithdrawalRequestRecord> get merchantPersonalWithdrawals {
    final activeMer = activeMerchantRecord;
    final targetMerId = activeMer?.id ?? '';
    final targetStore = (activeMer?.storeName ?? merchantStoreName)
        .trim()
        .toLowerCase();
    return withdrawalRequests.where((w) {
      if (w.id.startsWith('COMP-') || w.id.startsWith('REFUND-')) {
        return false;
      }
      if (!w.ownerRole.contains('Cửa hàng')) return false;
      if (w.ownerId.isNotEmpty && targetMerId.isNotEmpty) {
        return w.ownerId == targetMerId;
      }
      return targetStore.isNotEmpty &&
          w.ownerName.trim().toLowerCase() == targetStore;
    }).toList();
  }

  /// Danh sách thông báo dành cho cửa hàng B2B đang đăng nhập
  List<NotificationRecord> get merchantNotifications {
    final activeMer = activeMerchantRecord;
    final merIdLower = (activeMer?.id ?? '').trim().toLowerCase();
    final storeLower = (activeMer?.storeName ?? merchantStoreName)
        .trim()
        .toLowerCase();
    final myCodes = merchantPersonalOrders.map((o) => o.trackingCode).toSet();
    return notifications.where((n) {
      if (n.targetGroup != 'Tất cả người dùng' &&
          n.targetGroup != 'Cửa hàng B2B') {
        return false;
      }
      final rk = n.recipientKey?.trim().toLowerCase();
      if (rk != null && rk.isNotEmpty) {
        return (merIdLower.isNotEmpty && rk == merIdLower) ||
            (storeLower.isNotEmpty && rk == storeLower);
      }
      if (n.title.contains('#DH')) {
        return myCodes.any((code) => n.title.contains(code));
      }
      return true;
    }).toList();
  }

  /// Tổng tiền bồi thường khiếu nại đã được đối soát cộng trực tiếp vào số dư COD của cửa hàng
  double computeMerchantCompensationCredits(MerchantApplicantRecord? mer) {
    final targetMer = mer ?? activeMerchantRecord;
    if (targetMer == null) return 0.0;
    final merStoreLower = targetMer.storeName.trim().toLowerCase();
    final merOrderCodes = orders
        .where((o) => o.customerName.trim().toLowerCase() == merStoreLower)
        .map((o) => o.trackingCode)
        .toSet();
    final compRegex = RegExp(r'Đã cộng (\d+)đ tiền bồi thường');
    double totalComp = 0.0;
    for (final c in complaints) {
      if (merOrderCodes.contains(c.orderId) ||
          c.customerName.trim().toLowerCase() == merStoreLower) {
        for (final rep in c.replies) {
          final match = compRegex.firstMatch(rep);
          if (match != null) {
            totalComp += double.tryParse(match.group(1)!) ?? 0.0;
          }
        }
      }
    }
    return totalComp;
  }

  void _notifyStoreChanged() {
    if (!_applyingLiveEvents) _publishLiveChanges();
    notifyListeners();
  }
}
