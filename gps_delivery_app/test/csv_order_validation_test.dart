import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/gps/smart_dispatch_engine.dart';
import 'package:gps_delivery_app/data/datasources/local/app_state_store.dart';
import 'package:gps_delivery_app/data/datasources/local/sqlite_offline_queue_datasource.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/domain/enums/service_type.dart';
import 'package:gps_delivery_app/domain/enums/user_role.dart';

import 'fixtures/app_state_test_fixtures.dart';
import 'fixtures/managed_delivery_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppStateStore.instance;
  const destination = '45 Lê Duẩn Quận 1 TP.HCM';
  const pickup = '145 Phố Huế, Hai Bà Trưng, Hà Nội';

  setUpAll(() async {
    SqliteOfflineQueueDatasource.ensureDesktopFfiInitialized();
    await store.initializeDatabase();
    store.seedTestRecords();
    await store.persistTestRecords();
    await store.reloadFromSqlite();
    await ManagedDeliveryFixture().cachePlaces();
  });

  setUp(() {
    store.applyAuthenticatedUserSession(
      store.findUserByPhone('0909112233')!,
      activeWorkspaceRole: SubsystemRole.merchant,
    );
    store.geofenceZones.clear();
    store.isPeakSurchargeActive = false;
    store.isWeatherSurchargeActive = false;
  });

  test('Quoted CSV preserves phone, comma, escaped quote and multiline text', () {
    final result = store.parseAndCreateBulkOrdersFromCsv(
      '\ufefften_nguoi_nhan,sdt_nguoi_nhan,dia_chi_giao,mo_ta_hang,khoi_luong_kg,tien_cod_vnd,loai_dich_vu\r\n'
      'Recipient,0901234567,"$destination","Box, size ""M""\nHandle carefully",2,450.000,EXPRESS',
    );
    expect(result.validCount, 1);
    expect(result.rows.single.recipientPhone, '0901234567');
    expect(
      result.rows.single.packageDescription,
      'Box, size "M"\nHandle carefully',
    );
    expect(result.rows.single.codAmount, 450000);
    expect(result.rows.single.serviceType, DeliveryServiceType.express30m);
    expect(result.createdTrackingCodes, isEmpty);
  });

  test(
    'Saved warehouse coordinates survive preview, creation and reload',
    () async {
      final warehouse = store.merchantPersonalWarehouses.first;
      expect(
        SmartDispatchEngine.tryResolveAddressToCoordinate(warehouse.address),
        isNull,
      );
      const csv = 'Recipient,0901234567,$destination,50000';
      final before = store.orders.length;
      final preview = store.parseAndCreateBulkOrdersFromCsv(csv);
      expect(preview.validCount, 1);
      expect(store.orders.length, before);
      expect(preview.rows.single.pickupLocation, warehouse.location);
      final created = store.parseAndCreateBulkOrdersFromCsv(
        csv,
        commitOrders: true,
        feePayerMethod: 'Người nhận trả phí',
      );
      expect(created.validCount, preview.validCount);
      expect(created.createdTrackingCodes, hasLength(1));
      await store.persistTestRecords();
      await store.reloadFromSqlite();
      final order = store.orders.firstWhere(
        (o) => o.trackingCode == created.createdTrackingCodes.single,
      );
      expect(order.pickupLocation.latitude, warehouse.location.latitude);
      expect(
        order.dropoffLocation.longitude,
        preview.rows.single.dropoffLocation!.longitude,
      );
      expect(order.paymentMethod, 'Người nhận trả phí');
    },
  );

  test(
    'Explicit 12-column coordinates resolve addresses without geocoding',
    () {
      final result = store.parseAndCreateBulkOrdersFromCsv(
        'Recipient,0901234567,Delivery address 17,Box,1,0,STANDARD,Pickup address 19,21.01,105.85,21.03,105.87',
      );
      expect(result.validCount, 1);
      expect(result.rows.single.pickupLocation!.latitude, 21.01);
      expect(result.rows.single.dropoffLocation!.longitude, 105.87);
    },
  );

  test('Invalid money, weight, column count and coordinate pairs never create orders', () {
    final before = store.orders.length;
    final rows = [
      for (final cod in ['garbage', 'NaN', 'Infinity', '-1', '1.5', '20000001'])
        'Recipient,0901234567,$destination,Box,1,$cod,STANDARD',
      for (final weight in ['garbage', 'NaN', 'Infinity', '0', '501'])
        'Recipient,0901234567,$destination,Box,$weight,0,STANDARD',
      for (final point in ['91,105.85', '21.01,181', 'NaN,105.85', '21.01,'])
        'Recipient,0901234567,$destination,Box,1,0,STANDARD,$pickup,$point,21.03,105.87',
      'Recipient,0901234567,$destination,Box,1,0,STANDARD,,21.01',
    ];
    for (final row in rows) {
      final result = store.parseAndCreateBulkOrdersFromCsv(
        row,
        commitOrders: true,
      );
      expect(result.invalidCount, 1, reason: row);
      expect(result.createdTrackingCodes, isEmpty, reason: row);
    }
    expect(store.orders.length, before);
  });

  test(
    'Unknown pickup never borrows device GPS or another merchant warehouse',
    () {
      store.applyVerifiedDeviceGpsFix(
        rawPoint: const GeoPoint(latitude: 21.01, longitude: 105.85),
      );
      final unknown = store.parseAndCreateBulkOrdersFromCsv(
        'Recipient,0901234567,$destination,0',
        customPickupAddress: 'Unknown pickup address 99',
      );
      expect(unknown.invalidCount, 1);
      expect(unknown.rows.single.pickupLocation, isNull);
      final warehouseAddress = store.merchantPersonalWarehouses.first.address;
      store.applyAuthenticatedUserSession(store.findUserByPhone('0912345678')!);
      final otherOwner = store.parseAndCreateBulkOrdersFromCsv(
        'Recipient,0901234567,$destination,0',
        customPickupAddress: warehouseAddress,
      );
      expect(otherOwner.invalidCount, 1);
      expect(otherOwner.rows.single.pickupLocation, isNull);
    },
  );

  test(
    'Unknown building does not reuse a substring match from a verified address',
    () {
      expect(
        SmartDispatchEngine.tryResolveAddressToCoordinate(destination),
        isNotNull,
      );
      expect(
        SmartDispatchEngine.tryResolveAddressToCoordinate('Lê Duẩn'),
        isNull,
      );
      expect(
        SmartDispatchEngine.tryResolveAddressToCoordinate('1450 Phố Huế'),
        isNull,
      );
    },
  );

  test('Unknown final stop has no geofence fee; blank stops cannot change a verified fee', () {
    store.geofenceZones.add(
      GeofenceZoneRecord(
        id: 'test-zone',
        zoneName: 'Test zone',
        zoneType: 'SURCHARGE_ZONE',
        surchargeRate: 25000,
        isActive: true,
        boundary: const [
          GeoPoint(latitude: 10, longitude: 106),
          GeoPoint(latitude: 10, longitude: 107),
          GeoPoint(latitude: 11, longitude: 107),
          GeoPoint(latitude: 11, longitude: 106),
        ],
      ),
    );
    ActiveOrderRecord create({
      GeoPoint? point,
      List<Map<String, dynamic>> stops = const [],
    }) => store.createNewOrder(
      pickupAddress: pickup,
      dropoffAddress: 'Unverified destination 123',
      recipientName: 'Recipient',
      recipientPhone: '0901234567',
      packageDescription: 'Box',
      weightKg: 1,
      dimensionsCm: '10x10x10',
      serviceType: DeliveryServiceType.standard,
      codAmount: 0,
      paymentMethod: 'Người gửi trả phí',
      customDropoffLocation: point,
      additionalStops: stops,
    );
    expect(create().surchargeFee, 0);
    const point = GeoPoint(latitude: 10.78, longitude: 106.70);
    expect(
      create(
        point: point,
        stops: [
          {'address': '  '},
        ],
      ).surchargeFee,
      25000,
    );
    expect(
      create(
        point: point,
        stops: [
          {'address': 'Unverified extra destination'},
        ],
      ).surchargeFee,
      5000, // Only the per-stop fee applies; no unverified geofence surcharge.
    );
    expect(
      () => create(point: const GeoPoint(latitude: double.nan, longitude: 106)),
      throwsArgumentError,
    );
  });
}
