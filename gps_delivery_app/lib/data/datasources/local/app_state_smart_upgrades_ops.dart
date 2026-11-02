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

  /// UC36: Tạo lịch hẹn xe tải/xe van thu gom hàng loạt tại kho B2B
  ScheduledPickupRequestRecord createScheduledPickupRequest({
    required String warehouseId,
    required String vehicleType,
    required String timeSlot,
    required int packageCount,
    required double totalWeightKg,
    String note = '',
  }) {
    final activeMer = activeMerchantRecord;
    final personalWhs = merchantPersonalWarehouses;
    final wh =
        personalWhs.where((w) => w.id == warehouseId).firstOrNull ??
        personalWhs.firstOrNull;
    final merId = activeMer?.id ?? 'MER-LOCAL';
    final store = (activeMer?.storeName ?? merchantStoreName).trim().isNotEmpty
        ? (activeMer?.storeName ?? merchantStoreName).trim()
        : 'Cửa hàng đối tác B2B';
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final stamp =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} $hh:$mm';
    final reqId =
        'PKP-${(1000 + scheduledPickupRequests.length + (now.millisecond % 899)).toString()}';

    final record = ScheduledPickupRequestRecord(
      id: reqId,
      merchantId: merId,
      storeName: store,
      warehouseId: wh?.id ?? 'WH-DEFAULT',
      warehouseName: wh?.name ?? 'Kho chính',
      warehouseAddress: wh?.address ?? 'Kho trung tâm cửa hàng',
      vehicleType: vehicleType,
      timeSlot: timeSlot,
      packageCount: math.max(1, packageCount),
      totalWeightKg: math.max(0.5, totalWeightKg),
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
        recipientKey: merId,
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
  MultiStopRoutePlan computeMultiStopPlanForWarehouse([GeoPoint? customOrigin]) {
    final personalWhs = merchantPersonalWarehouses;
    final primaryWh =
        personalWhs.where((w) => w.isPrimary).firstOrNull ??
        personalWhs.firstOrNull;
    final origin =
        customOrigin ??
        primaryWh?.location ??
        const GeoPoint(latitude: 10.7769, longitude: 106.7009);
    return SmartLogisticsUpgradeEngine.optimizeMultiStopRoute(
      originWarehouse: origin,
      candidateOrders: merchantPersonalOrders,
    );
  }

  MultiStopRoutePlan applyMultiStopRouteOptimization() {
    final plan = computeMultiStopPlanForWarehouse();
    if (plan.orderedStops.isNotEmpty) {
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

  /// Pillar 3: Trợ lý AI Phân tích Vận hành & Dự báo SLA (Toàn mạng lưới & Cửa hàng)
  AiSlaInsightReport get aiOperationsInsights =>
      SmartLogisticsUpgradeEngine.analyzeOperationsAndSla(
        orders: orders,
        drivers: drivers,
        isPeakActive: isPeakSurchargeActive,
        isWeatherActive: isWeatherSurchargeActive,
      );

  AiSlaInsightReport get merchantAiInsights =>
      SmartLogisticsUpgradeEngine.analyzeOperationsAndSla(
        orders: merchantPersonalOrders,
        drivers: drivers,
        isPeakActive: isPeakSurchargeActive,
        isWeatherActive: isWeatherSurchargeActive,
      );

  /// Pillar 1b: Đồng bộ đơn tự động 1-Click từ Sàn TMĐT / POS (Shopee Mall, TikTok Shop, Sapo POS)
  List<String> syncMarketplaceOrders(String channel) {
    final seeds = SmartLogisticsUpgradeEngine.buildMarketplaceSyncBatch(
      channel,
    );
    final personalWhs = merchantPersonalWarehouses;
    final primaryWh =
        personalWhs.where((w) => w.isPrimary).firstOrNull ??
        personalWhs.firstOrNull;
    final pickupAddr =
        primaryWh?.address ?? '125 Lê Lợi, Phường Bến Thành, Quận 1, TP. HCM';
    final pickupCoord =
        primaryWh?.location ??
        const GeoPoint(latitude: 10.7731, longitude: 106.6983);
    final storeLabel =
        (activeMerchantRecord?.storeName ?? merchantStoreName).trim().isNotEmpty
        ? (activeMerchantRecord?.storeName ?? merchantStoreName).trim()
        : 'Cửa hàng đối tác B2B';

    final createdCodes = <String>[];
    for (final seed in seeds) {
      if (syncedExternalMarketplaceIds.contains(seed.externalOrderCode)) {
        continue;
      }
      final dropoffCoord = SmartDispatchEngine.resolveAddressToCoordinate(
        seed.dropoffAddress,
        fallback: const GeoPoint(latitude: 10.7798, longitude: 106.6990),
      );
      final created = createNewOrder(
        pickupAddress: pickupAddr,
        dropoffAddress: seed.dropoffAddress,
        recipientName: seed.recipientName,
        recipientPhone: seed.recipientPhone,
        packageDescription: seed.packageDescription,
        weightKg: seed.weightKg,
        dimensionsCm: '30 x 20 x 15 cm',
        serviceType: seed.serviceType,
        codAmount: seed.codAmount,
        paymentMethod: 'Người gửi trả phí',
        isFragileTag: seed.packageDescription.contains('Dễ vỡ'),
        customCustomerName: storeLabel,
        customPickupLocation: pickupCoord,
        customDropoffLocation: dropoffCoord,
      );
      syncedExternalMarketplaceIds.add(seed.externalOrderCode);
      createdCodes.add(created.trackingCode);
    }
    if (createdCodes.isNotEmpty) {
      _notifyStoreChanged();
    }
    return createdCodes;
  }
}

