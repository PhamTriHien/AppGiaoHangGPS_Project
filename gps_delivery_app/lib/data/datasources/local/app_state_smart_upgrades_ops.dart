part of 'app_state_store.dart';

extension AppStateSmartUpgradesOps on AppStateStore {
  /// Danh sách phiếu đặt lịch xe thu gom số lượng lớn (UC36) của cửa hàng đang đăng nhập
  List<ScheduledPickupRequestRecord> get merchantPersonalPickupRequests {
    final activeMer = activeMerchantRecord;
    final merId = activeMer?.id ?? '';
    final storeLower =
        (activeMer?.storeName ?? merchantStoreName).trim().toLowerCase();
    return scheduledPickupRequests.where((req) {
      if (merId.isNotEmpty && req.merchantId.isNotEmpty) {
        return req.merchantId == merId;
      }
      return storeLower.isNotEmpty &&
          req.storeName.trim().toLowerCase() == storeLower;
    }).toList();
  }

  /// UC31: Chuyển đổi nhanh kho lấy hàng mặc định 1-chạm
  bool setPrimaryMerchantWarehouse(String warehouseId) {
    final personalList = merchantPersonalWarehouses;
    final target = personalList.where((w) => w.id == warehouseId).firstOrNull;
    if (target == null) return false;
    updateMerchantWarehouseDetails(
      warehouseId: target.id,
      name: target.name,
      address: target.address,
      contactName: target.contactName,
      contactPhone: target.contactPhone,
      openHours: target.openHours,
      setPrimary: true,
      customLocation: target.location,
    );
    return true;
  }

  /// UC36: Tạo lịch hẹn xe tải/xe van thu gom hàng loạt tại kho B2B.
  /// Trả về null khi chưa có hồ sơ cửa hàng hoặc kho đã đăng ký.
  ScheduledPickupRequestRecord? createScheduledPickupRequest({
    required String warehouseId,
    required String vehicleType,
    required String timeSlot,
    required int packageCount,
    required double totalWeightKg,
    String note = '',
  }) {
    final activeMer = activeMerchantRecord;
    final personalWhs = merchantPersonalWarehouses;
    final wh = personalWhs.where((w) => w.id == warehouseId).firstOrNull;
    if (activeMer == null ||
        wh == null ||
        packageCount < 1 ||
        !totalWeightKg.isFinite ||
        totalWeightKg <= 0) {
      return null;
    }
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final stamp =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} $hh:$mm';
    final reqId = 'PKP-${now.microsecondsSinceEpoch}';

    final record = ScheduledPickupRequestRecord(
      id: reqId,
      merchantId: activeMer.id,
      storeName: activeMer.storeName,
      warehouseId: wh.id,
      warehouseName: wh.name,
      warehouseAddress: wh.address,
      vehicleType: vehicleType,
      timeSlot: timeSlot,
      packageCount: packageCount,
      totalWeightKg: totalWeightKg,
      note: note.trim(),
      status: 'Chờ điều xe thu gom',
      createdAt: stamp,
    );
    scheduledPickupRequests.insert(0, record);
    _sqliteDb.upsertEntityRecord(
      tableName: 'scheduled_pickups',
      recordId: record.id,
      payload: record.toSqlRow(),
    );
    notifications.insert(
      0,
      NotificationRecord(
        id: 'NTF-PKP-${now.millisecondsSinceEpoch}',
        category: 'Thu gom B2B',
        title:
            'Đã đặt lịch thu gom lô hàng ${record.id} (${record.timeSlot} • ${record.vehicleType} • ${record.packageCount} kiện)',
        timeAgo: stamp,
        targetGroup: 'Cửa hàng B2B',
        recipientKey: activeMer.id,
      ),
    );
    _notifyStoreChanged();
    return record;
  }

  /// Admin điều phối tài xế nhận phiếu thu gom lô hàng lớn (PKP-...)
  bool dispatchScheduledPickupByAdmin({
    required String requestId,
    required DriverApplicantRecord driver,
  }) {
    final req = scheduledPickupRequests
        .where((r) => r.id == requestId)
        .firstOrNull;
    if (req == null) return false;
    req.status = 'Đã điều xe: ${driver.fullName} (${driver.licensePlate})';
    req.assignedDriverName = driver.fullName;
    _sqliteDb.upsertEntityRecord(
      tableName: 'scheduled_pickups',
      recordId: req.id,
      payload: req.toSqlRow(),
    );
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    notifications.insert(
      0,
      NotificationRecord(
        id: 'NTF-PKP-DISP-${now.millisecondsSinceEpoch}',
        category: 'Thu gom B2B',
        title:
            'Đã điều xe thu gom phiếu ${req.id}: Tài xế ${driver.fullName} (${driver.licensePlate}) đến ${req.warehouseName}',
        timeAgo: stamp,
        targetGroup: 'Cửa hàng B2B',
        recipientKey: req.merchantId,
      ),
    );
    _notifyStoreChanged();
    return true;
  }

  /// Pillar 1: Chấm điểm tín nhiệm SĐT người nhận & Cảnh báo hoàn hàng / bom hàng
  RecipientTrustProfile evaluateRecipientTrust(String rawPhone) {
    return SmartLogisticsUpgradeEngine.evaluateRecipientRisk(
      phone: rawPhone,
      allOrders: orders,
      flaggedRiskPhones: flaggedRiskPhones,
    );
  }

  bool toggleRecipientRiskFlag(String rawPhone) {
    final norm = SmartLogisticsUpgradeEngine.normalizeVietnamPhone(rawPhone);
    if (norm.length < 9) return false;
    final added = !flaggedRiskPhones.remove(norm);
    if (added) {
      flaggedRiskPhones.add(norm);
    }
    _sqliteDb.upsertEntityRecord(
      tableName: 'smart_upgrade_meta',
      recordId: 'RISK_PHONES',
      payload: {'phones': flaggedRiskPhones.toList()},
    );
    _notifyStoreChanged();
    return added;
  }

  /// Pillar 4: Khách hàng chọn chỉ dẫn giao hàng nhanh 1-chạm đồng bộ tức thì sang Tài xế
  void setQuickDeliveryInstruction(String trackingCode, String instruction) {
    final code = trackingCode.trim();
    if (code.isEmpty) return;
    final trimmed = instruction.trim();
    if (trimmed.isEmpty) {
      quickDeliveryInstructionsByOrder.remove(code);
    } else {
      quickDeliveryInstructionsByOrder[code] = trimmed;
    }
    _sqliteDb.upsertEntityRecord(
      tableName: 'smart_upgrade_meta',
      recordId: 'QUICK_NOTE_$code',
      payload: {'trackingCode': code, 'instruction': trimmed},
    );
    _notifyStoreChanged();
  }

  String quickDeliveryInstructionFor(String trackingCode) =>
      quickDeliveryInstructionsByOrder[trackingCode.trim()] ?? '';

  /// Pillar 2: Tính toán lộ trình ghép đơn đa điểm (Nearest-Neighbor + 2-Opt TSP)
  /// Trả về null khi cửa hàng chưa có kho để làm điểm xuất phát.
  MultiStopRoutePlan? computeMultiStopPlanForWarehouse([
    GeoPoint? customOrigin,
  ]) {
    final personalWhs = merchantPersonalWarehouses;
    final primaryWh =
        personalWhs.where((w) => w.isPrimary).firstOrNull ??
        personalWhs.firstOrNull;
    final origin = customOrigin ?? primaryWh?.location;
    if (origin == null) return null;
    return SmartLogisticsUpgradeEngine.optimizeMultiStopRoute(
      originWarehouse: origin,
      candidateOrders: merchantPersonalOrders,
    );
  }

  MultiStopRoutePlan? applyMultiStopRouteOptimization() {
    final plan = computeMultiStopPlanForWarehouse();
    if (plan != null && plan.orderedStops.isNotEmpty) {
      activeRoutePolyline = plan.chainedPolyline;
      isMultiStopRouteActive = true;
      final stopIds = plan.orderedStops.map((o) => o.id).toSet();
      final remaining = orders.where((o) => !stopIds.contains(o.id)).toList();
      orders
        ..clear()
        ..addAll(plan.orderedStops)
        ..addAll(remaining);
      _notifyStoreChanged();
    }
    return plan;
  }
}
