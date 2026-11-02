import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/data/datasources/local/app_state_store.dart';
import 'package:gps_delivery_app/data/datasources/local/sqlite_offline_queue_datasource.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppStateStore store;

  setUpAll(() async {
    SqliteOfflineQueueDatasource.ensureDesktopFfiInitialized();
    store = AppStateStore.instance;
    await store.initializeDatabase();
  });

  test('Smart Logistics 4 Pillars + UC31/UC36 Merchant & Admin workflows', () {
    // 1. Setup approved Merchant + 2 warehouses & test UC31 default warehouse toggle
    final mer = MerchantApplicantRecord(
      id: 'MER-SMART-01',
      ownerPhone: '0909888777',
      storeName: 'Gốm Sứ Thông Minh B2B',
      businessType: 'Đồ gia dụng & Gốm sứ',
      taxCode: '0319998887',
      representativeName: 'Phạm Trí Hiển',
      bankName: 'Vietcombank',
      bankAccount: '007100999888',
      approvalStatus: 'Đã duyệt',
    );
    store.merchantApplicants.add(mer);
    store.merchantStoreName = mer.storeName;

    final wh1 = store.addMerchantWarehouse(
      name: 'Kho Quận 1',
      address: '125 Lê Lợi, Quận 1, TP. HCM',
      contactPhone: '0909888777',
      isPrimary: true,
      customLocation: const GeoPoint(latitude: 10.7731, longitude: 106.6983),
    );
    final wh2 = store.addMerchantWarehouse(
      name: 'Kho Bình Thạnh',
      address: '215 Điện Biên Phủ, Quận Bình Thạnh, TP. HCM',
      contactPhone: '0909888778',
      isPrimary: false,
      customLocation: const GeoPoint(latitude: 10.8015, longitude: 106.7112),
    );
    expect(wh1.isPrimary, isTrue);
    expect(store.setPrimaryMerchantWarehouse(wh2.id), isTrue);
    expect(
      store.merchantPersonalWarehouses.singleWhere((w) => w.id == wh2.id).isPrimary,
      isTrue,
    );

    // 2. Pillar 1b: Omnichannel sync (Shopee Mall & TikTok Shop, idempotent deduplication)
    final shopeeCodes = store.syncMarketplaceOrders('Shopee Mall');
    expect(shopeeCodes.length, 2);
    expect(store.syncMarketplaceOrders('Shopee Mall'), isEmpty);
    final tiktokCodes = store.syncMarketplaceOrders('TikTok Shop');
    expect(tiktokCodes.length, 2);

    // 3. Pillar 1: CRM Recipient Trust Score & Blacklist Flagging
    const testPhone = '0903556677';
    final beforeFlag = store.evaluateRecipientTrust(testPhone);
    expect(beforeFlag.isBlacklisted, isFalse);
    expect(store.toggleRecipientRiskFlag(testPhone), isTrue);
    final afterFlag = store.evaluateRecipientTrust(testPhone);
    expect(afterFlag.isBlacklisted, isTrue);
    expect(afterFlag.isHighRisk, isTrue);

    // 4. Pillar 2: Multi-stop 2-Opt TSP Route Optimization
    final plan = store.applyMultiStopRouteOptimization();
    expect(plan.orderedStops.length, greaterThanOrEqualTo(3));
    expect(plan.optimizedDistanceMeters, lessThanOrEqualTo(plan.naiveDistanceMeters));
    expect(store.isMultiStopRouteActive, isTrue);

    // 5. Pillar 3: AI SLA & Operations Insights
    final aiInsights = store.aiOperationsInsights;
    expect(aiInsights.predictedSlaOnTimePercent, inInclusiveRange(78.0, 100.0));
    expect(aiInsights.actionRecommendations, isNotEmpty);

    // 6. Pillar 4: Customer 1-tap Quick Delivery Instruction synced to Driver
    final firstOrderCode = shopeeCodes.first;
    store.setQuickDeliveryInstruction(firstOrderCode, 'Gửi lễ tân tầng trệt');
    expect(
      store.quickDeliveryInstructionFor(firstOrderCode),
      'Gửi lễ tân tầng trệt',
    );

    // 7. UC36 Scheduled Bulk Pickup + Admin Driver Dispatch
    final pickupReq = store.createScheduledPickupRequest(
      warehouseId: wh2.id,
      vehicleType: 'Xe tải van 500kg',
      timeSlot: '14:00 - 16:00 (Ca chiều)',
      packageCount: 25,
      totalWeightKg: 48.5,
      note: 'Hàng gốm dễ vỡ đóng thùng gỗ',
    );
    expect(pickupReq.id, startsWith('PKP-'));
    final drv = DriverApplicantRecord(
      id: 'DRV-PKP-01',
      fullName: 'Nguyễn Văn Tài',
      phone: '0911222333',
      citizenId: '079095111222',
      licensePlate: '51D-888.99',
      vehicleType: 'Xe tải van 500kg',
      vehicleColor: 'Trắng',
      approvalStatus: 'Đã duyệt',
      isOnline: true,
      location: const GeoPoint(latitude: 10.7995, longitude: 106.7100),
      walletBalance: 500000,
    );
    expect(
      store.dispatchScheduledPickupByAdmin(
        requestId: pickupReq.id,
        driver: drv,
      ),
      isTrue,
    );
    expect(pickupReq.assignedDriverName, 'Nguyễn Văn Tài');
  });
}

