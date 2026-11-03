import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/data/datasources/local/app_state_store.dart';
import 'package:gps_delivery_app/data/datasources/local/sqlite_offline_queue_datasource.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/domain/enums/user_role.dart';
import 'package:gps_delivery_app/main.dart';

import 'fixtures/app_state_test_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = SqliteOfflineQueueDatasource.instance;
  late AppStateStore store;

  setUpAll(() async {
    SqliteOfflineQueueDatasource.ensureDesktopFfiInitialized();
    store = AppStateStore.instance;
    await store.initializeDatabase();
  });

  test('Fresh installation has no demo accounts, orders or money', () async {
    expect(store.isDatabaseReady, isTrue);
    for (final table in [
      'users',
      'drivers',
      'merchants',
      'orders',
      'user_addresses',
      'merchant_pickup_points',
      'vouchers',
      'wallets_and_transactions',
      'cod_reconciliations',
      'incidents_and_complaints',
      'chat_messages_and_notifications',
      'geofence_zones',
    ]) {
      expect(await db.countRows(table), 0, reason: table);
    }
    expect(store.driverWalletBalance, 0);
    expect(store.merchantCodBalance, 0);
    expect(store.isDriverOnline, isFalse);
    expect(store.hasRealDeviceGpsFix, isFalse);
    expect(store.merchantPersonalWarehouses, isEmpty);
    expect(GrabFoodRecommendationEngine.curatedMenuCatalog, isEmpty);
    expect(store.merchantMenuItems, isEmpty);
    expect(store.rbacRoles, isNotEmpty);
    await store.initializeDatabase();
    expect(store.users, isEmpty);
    expect(store.orders, isEmpty);
  });

  testWidgets(
    'Consumer signup and standalone admin portal keep their roles separate',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final size in [const Size(360, 800), const Size(1440, 1024)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(const GpsDeliveryApp(initialRoute: '/legacy'));
        await tester.pump();
        expect(find.text('Đăng nhập hệ thống'), findsOneWidget);
        expect(find.text('Đơn hàng cloud'), findsNothing);
        expect(find.byTooltip('Đơn hàng cloud'), findsNothing);
        expect(find.text('Đăng ký tài khoản'), findsOneWidget);
        expect(find.text('Thiết lập quản trị viên'), findsNothing);
        expect(find.text('Tiếp tục với Google'), findsNothing);
        expect(find.text('Thiết lập quản trị'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(const GpsDeliveryApp(initialRoute: '/admin'));
        await tester.pump();
        expect(find.text('GHST ADMIN'), findsOneWidget);
        expect(find.text('Đăng nhập quản trị'), findsOneWidget);
        expect(find.text('Email quản trị'), findsOneWidget);
        expect(find.text('Đăng ký tài khoản'), findsNothing);
        expect(find.text('Tiếp tục với Google'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          const GpsDeliveryApp(initialRoute: '/legacy-admin'),
        );
        await tester.pump();
        expect(find.text('Đăng nhập quản trị'), findsOneWidget);
        expect(find.text('Đăng ký tài khoản'), findsNothing);
        expect(find.text('Tiếp tục với Google'), findsNothing);
        expect(find.text('Thiết lập quản trị viên đầu tiên'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      await tester.pumpWidget(const GpsDeliveryApp(initialRoute: '/legacy'));
      await tester.pump();
      await tester.tap(find.text('Đăng ký tài khoản'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Họ và tên'),
        'Test Customer',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Số điện thoại'),
        '0908777666',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Tạo mật khẩu đăng nhập'),
        'test-password',
      );
      await tester.ensureVisible(find.text('Gửi mã OTP'));
      await tester.tap(find.text('Gửi mã OTP'));
      await tester.pump();
      await tester.enterText(
        find.byType(TextField).last,
        store.activeOtpCodesByPhone['0908777666']!,
      );
      await tester.ensureVisible(find.text('Xác nhận OTP & Tạo tài khoản'));
      await tester.tap(find.text('Xác nhận OTP & Tạo tài khoản'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(store.users.single.role, SubsystemRole.customer);
      expect(find.text('Tạo đơn hàng mới'), findsWidgets);
      expect(find.text('Đơn hàng cloud'), findsNothing);
      expect(find.byTooltip('Đơn hàng cloud'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      store.clearAuthenticatedSession();
      await tester.pumpWidget(
        const GpsDeliveryApp(initialRoute: '/legacy-admin'),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).first, '0908777666');
      await tester.enterText(find.byType(TextFormField).last, 'test-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pump();
      expect(find.textContaining('không có quyền quản trị'), findsOneWidget);
      expect(store.activeAuthenticatedUser, isNull);
      await tester.tap(find.text('Thiết lập quản trị viên đầu tiên'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Họ và tên'),
        'Test Admin',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Số điện thoại'),
        '0908999888',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mật khẩu'),
        'test-password',
      );
      await tester.tap(find.text('Tạo quản trị viên'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(store.users, hasLength(2));
      expect(store.findUserByPhone('0908999888')!.role, SubsystemRole.admin);
      expect(find.text('Tổng quan hệ thống'), findsOneWidget);
      await tester.tap(find.text('Đăng xuất').first);
      await tester.pump();
      expect(find.text('Đăng nhập quản trị'), findsOneWidget);
      expect(find.text('Đăng nhập hệ thống'), findsNothing);
      expect(find.text('Thiết lập quản trị viên đầu tiên'), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, '0908999888');
      await tester.enterText(find.byType(TextFormField).last, 'wrong-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pump();
      expect(find.textContaining('không có quyền quản trị'), findsOneWidget);
      expect(store.activeAuthenticatedUser, isNull);
      final admin = store.findUserByPhone('0908999888')!;
      admin.status = 'LOCKED';
      await tester.enterText(find.byType(TextFormField).last, 'test-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pump();
      expect(store.activeAuthenticatedUser, isNull);
      admin.status = 'ACTIVE';
      store.userPreferencesByPhone[admin.phone] = {'twoFactorEnabled': true};
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pump();
      expect(find.textContaining('Chưa cấu hình kênh gửi OTP'), findsOneWidget);
      expect(store.activeAuthenticatedUser, isNull);
      store.userPreferencesByPhone.remove(admin.phone);
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pump();
      expect(find.text('Tổng quan hệ thống'), findsOneWidget);
      await tester.tap(find.text('Đăng xuất').first);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const GpsDeliveryApp(initialRoute: '/legacy'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '0908999888');
      await tester.enterText(
        find.widgetWithText(TextField, 'Mật khẩu'),
        'test-password',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Đăng nhập'));
      await tester.pump();
      expect(find.textContaining('cổng /admin'), findsOneWidget);
      expect(store.activeAuthenticatedUser, isNull);
      await tester.tap(find.text('Mã OTP'));
      await tester.pump();
      await tester.tap(find.text('Gửi mã OTP'));
      await tester.pump();
      expect(find.textContaining('cổng /admin'), findsOneWidget);
      expect(store.activeAuthenticatedUser, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await db.queryRows('users');
      await db.deleteRows(
        'users',
        where: 'phone = ?',
        whereArgs: ['0908999888'],
      );
      await store.reloadFromSqlite();
      expect(store.users.single.role, SubsystemRole.customer);
      await tester.pumpWidget(const GpsDeliveryApp(initialRoute: '/legacy'));
      await tester.pump();
      expect(find.text('Đăng nhập hệ thống'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await db.deleteRows(
        'users',
        where: 'phone = ?',
        whereArgs: ['0908777666'],
      );
      await store.reloadFromSqlite();
    },
  );

  test(
    'New driver retains empty KYC and wallet after reload; mock GPS is ignored',
    () async {
      final account = store.registerUserAccountWithRole(
        phone: '0908111222',
        fullName: 'Test Driver',
        password: 'test-password',
        role: SubsystemRole.driver,
      );
      expect(account, isNotNull);
      expect(account!.email, isEmpty);
      // The database read runs after the queued local writes.
      await db.queryRows('drivers');
      await store.reloadFromSqlite();
      final driver = store.drivers.single;
      expect(driver.citizenId, isEmpty);
      expect(driver.licensePlate, isEmpty);
      expect(driver.attachedKycDocs, isEmpty);
      expect(driver.walletBalance, 0);
      expect(driver.bankAccount, isEmpty);
      expect(driver.rating, 0);
      expect(store.verifiedDriverLocations, isEmpty);
      store.applyVerifiedDeviceGpsFix(
        rawPoint: const GeoPoint(latitude: 10.77, longitude: 106.69),
        isMocked: true,
        syncToActiveDriver: true,
      );
      expect(store.hasRealDeviceGpsFix, isFalse);
      expect(store.verifiedDriverLocations, isEmpty);
      store.applyVerifiedDeviceGpsFix(
        rawPoint: const GeoPoint(latitude: 10.77, longitude: 106.69),
        speedKmh: 0,
        syncToActiveDriver: true,
      );
      expect(store.verifiedDriverLocations[driver.id], isNotNull);
      await db.queryRows('local_relational_entities');
      await store.reloadFromSqlite();
      expect(store.verifiedDriverLocations[driver.id], isNotNull);
      await db.deleteRows('users', where: 'id = ?', whereArgs: [account.id]);
      await db.deleteRows('drivers', where: 'id = ?', whereArgs: [driver.id]);
      await db.clearAllPendingSyncItems();
      await db.deleteRows(
        'local_relational_entities',
        where: 'table_name = ? AND record_id = ?',
        whereArgs: ['driver_meta', driver.id],
      );
      await db.deleteRows(
        'local_relational_entities',
        where: 'table_name = ?',
        whereArgs: ['verified_driver_locations'],
      );
    },
  );

  test(
    'Legacy cleanup archives sample dependencies and preserves reused real IDs',
    () async {
      store.seedTestRecords();
      await store.persistTestRecords();
      await db.deleteRows(
        'local_relational_entities',
        where: 'table_name = ?',
        whereArgs: ['data_migrations'],
      );
      await db.updateRows(
        'users',
        {
          'phone': '0908222333',
          'full_name': 'Real Customer',
          'email': 'real@example.test',
          'created_at': '2026-10-26',
        },
        where: 'id = ?',
        whereArgs: ['USR-01'],
      );
      await db.updateRows(
        'orders',
        {'recipient_phone': '0908333444'},
        where: 'id = ?',
        whereArgs: ['ORD-01'],
      );
      await db.upsertRow('order_tracking_logs', {
        'order_id': 'ORD-02',
        'driver_id': 'DV10928',
        'latitude': 10.77,
        'longitude': 106.69,
        'speed': 20,
        'bearing': 0,
        'is_mock_location': 0,
        'recorded_at': '2026-10-01',
      });
      await db.enqueueAction(
        actionType: 'UPSERT',
        payload: {
          'table': 'orders',
          'record': {'id': 'ORD-02'},
        },
      );
      final realQueueKey = await db.enqueueAction(
        actionType: 'UPSERT',
        payload: {
          'table': 'orders',
          'record': {'id': 'ORD-01'},
        },
      );

      await store.removeLegacyDemoRecords();
      await store.reloadFromSqlite();
      expect(store.users.single.phone, '0908222333');
      expect(store.orders.single.recipientPhone, '0908333444');
      expect(store.drivers, isEmpty);
      expect(store.merchantApplicants, isEmpty);
      expect(store.savedAddresses, isEmpty);
      expect(store.merchantWarehouses, isEmpty);
      expect(store.vouchers, isEmpty);
      expect(store.withdrawalRequests, isEmpty);
      expect(store.codReconciliations, isEmpty);
      expect(store.complaints, isEmpty);
      expect(store.chatMessages, isEmpty);
      expect(store.notifications, isEmpty);
      expect(store.geofenceZones, isEmpty);
      expect(await db.getEntityRecords('driver_meta'), isEmpty);
      expect(await db.countRows('order_tracking_logs'), 0);
      expect(
        (await db.getPendingSyncItems()).single.idempotencyKey,
        realQueueKey,
      );
      final archive = await db.getEntityRecords('archived_demo_v1');
      expect(archive.any((row) => row['table'] == 'users'), isTrue);
      expect(
        archive.any((row) => row['table'] == 'order_tracking_logs'),
        isTrue,
      );
      expect(archive.any((row) => row['table'] == 'local_sync_queue'), isTrue);

      await store.removeLegacyDemoRecords();
      await store.reloadFromSqlite();
      expect(
        (await db.getEntityRecords('archived_demo_v1')).length,
        archive.length,
      );
      expect(store.users.single.fullName, 'Real Customer');
      expect(store.orders, hasLength(1));
      expect(store.drivers, isEmpty);
    },
  );
}
