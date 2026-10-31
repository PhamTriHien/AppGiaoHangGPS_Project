import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gps_delivery_app/core/config/env_config.dart';
import 'package:gps_delivery_app/core/error/app_exception.dart';
import 'package:gps_delivery_app/core/gps/gps_integrity_validator.dart';
import 'package:gps_delivery_app/core/gps/kalman_gps_filter.dart';
import 'package:gps_delivery_app/core/gps/smart_dispatch_engine.dart';
import 'package:gps_delivery_app/core/utils/geo_math.dart';
import 'package:gps_delivery_app/core/utils/security_and_barcode_utils.dart';
import 'package:gps_delivery_app/data/datasources/local/app_state_store.dart';
import 'package:gps_delivery_app/data/datasources/local/sqlite_offline_queue_datasource.dart';
import 'package:gps_delivery_app/data/datasources/remote/supabase_postgis_datasource.dart';
import 'package:gps_delivery_app/data/repositories/driver_repository_impl.dart';
import 'package:gps_delivery_app/data/repositories/order_repository_impl.dart';
import 'package:gps_delivery_app/domain/entities/driver_entity.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/domain/entities/order_entity.dart';
import 'package:gps_delivery_app/domain/entities/pricing_estimate.dart';
import 'package:gps_delivery_app/domain/enums/order_status.dart';
import 'package:gps_delivery_app/domain/enums/service_type.dart';
import 'package:gps_delivery_app/domain/enums/user_role.dart';
import 'package:gps_delivery_app/main.dart';
import 'package:gps_delivery_app/presentation/admin/admin_subsystem_views.dart';
import 'package:gps_delivery_app/presentation/bloc/system_architecture_cubit.dart';
import 'package:gps_delivery_app/presentation/customer/customer_subsystem_views.dart';
import 'package:gps_delivery_app/presentation/driver/driver_subsystem_views.dart';
import 'package:gps_delivery_app/presentation/merchant/merchant_subsystem_views.dart';
import 'package:gps_delivery_app/presentation/widgets/animated_3d_ui_icons.dart';
import 'package:gps_delivery_app/presentation/widgets/studio_design_widgets.dart';
import 'package:gps_delivery_app/presentation/widgets/system_state_screens.dart';

import 'fixtures/app_state_test_fixtures.dart';
import 'fixtures/managed_delivery_fixture.dart';

void main() {
  setUpAll(() async {
    SqliteOfflineQueueDatasource.ensureDesktopFfiInitialized();
    await AppStateStore.instance.initializeDatabase();
    AppStateStore.instance.seedTestRecords();
    await AppStateStore.instance.persistTestRecords();
    await AppStateStore.instance.reloadFromSqlite();
    await ManagedDeliveryFixture().cachePlaces();
  });

  testWidgets(
    'TC-05..TC-08: GpsDeliveryApp mở trực tiếp màn hình UC01 Đăng ký / Đăng nhập, xác thực tài khoản thực tế trong CSDL users và phân quyền giao diện độc lập (RBAC) cho từng vai trò',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const GpsDeliveryApp(initialRoute: '/legacy'));

      await tester.tap(find.text('Mã OTP'));
      await tester.pump();

      // 1. Khi mở app: Hiển thị màn hình chính thức UC01 Đăng nhập / Đăng ký kèm nền đồ họa 3D thời gian thực
      expect(find.text('Đăng nhập hệ thống'), findsOneWidget);
      expect(find.text('Gửi mã OTP'), findsOneWidget);
      expect(
        find.text('Tiếp tục với Google'),
        EnvConfig.isGoogleOAuthConfigured ? findsOneWidget : findsNothing,
      );
      expect(find.text('Tiếp tục với Facebook'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint && w.painter is Studio3dLoginAmbientMapPainter,
        ),
        findsOneWidget,
      );

      // 2. Đăng nhập vai trò Khách hàng (0912345678 trong bảng users) -> Chỉ hiển thị giao diện Khách hàng kèm nền 3D Workspace
      await tester.enterText(find.byType(TextField).first, '0912345678');
      await tester.tap(find.text('Gửi mã OTP'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(
        find.byType(TextField).last,
        AppStateStore.instance.activeOtpCodesByPhone['0912345678']!,
      );
      await tester.tap(find.text('Xác nhận OTP & Đăng nhập'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Tạo đơn hàng mới'), findsWidgets);
      expect(find.byType(Animated3dIconBadge), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint && w.painter is Studio3dMainWorkspaceMapPainter,
        ),
        findsOneWidget,
      );
      expect(find.text('GO-MAU Admin'), findsNothing);

      // Đăng xuất khỏi Khách hàng -> Quay về UC01 Đăng nhập hệ thống
      await tester.tap(find.text('Đăng xuất').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Đăng nhập hệ thống'), findsOneWidget);

      // 3. Đăng nhập vai trò Tài xế (0987654321 trong bảng users) -> Chỉ hiển thị giao diện Tài xế
      await tester.enterText(find.byType(TextField).first, '0987654321');
      await tester.tap(find.text('Gửi mã OTP'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(
        find.byType(TextField).last,
        AppStateStore.instance.activeOtpCodesByPhone['0987654321']!,
      );
      await tester.tap(find.text('Xác nhận OTP & Đăng nhập'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Xin chào, Nguyễn Văn Nam!'), findsOneWidget);
      await tester.tap(find.text('Đăng xuất').first);
      await tester.pump(const Duration(milliseconds: 300));

      // 4. Đăng nhập vai trò Cửa hàng B2B (0909112233 trong bảng users) -> Chỉ hiển thị Merchant Web Portal
      await tester.enterText(find.byType(TextField).first, '0909112233');
      await tester.tap(find.text('Gửi mã OTP'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(
        find.byType(TextField).last,
        AppStateStore.instance.activeOtpCodesByPhone['0909112233']!,
      );
      await tester.tap(find.text('Xác nhận OTP & Đăng nhập'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Shop của tôi'), findsOneWidget);
      expect(find.text('Tạo đơn gửi hàng'), findsWidgets);
      await tester.tap(find.text('Đăng xuất').first);
      await tester.pump(const Duration(milliseconds: 300));

      // Admin accounts use a standalone portal, never the app OTP flow.
      await tester.enterText(find.byType(TextField).first, '0900999999');
      await tester.tap(find.text('Gửi mã OTP'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('cổng /admin'), findsOneWidget);
      expect(find.text('Tổng quan hệ thống'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const GpsDeliveryApp(initialRoute: '/admin'));
      await tester.pump();
      expect(find.text('GHST CLOUD ADMIN'), findsOneWidget);
      expect(find.text('Email quản trị'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        const GpsDeliveryApp(initialRoute: '/legacy-admin'),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).first, '0900999999');
      await tester.enterText(find.byType(TextFormField).last, '12345678');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('GO-MAU'), findsOneWidget);
      expect(find.text('Tổng quan hệ thống'), findsOneWidget);
    },
  );

  test('TC-01: Gói Hỏa tốc 14.5km + Giờ cao điểm + PROMO20K ra chính xác 138.250 VNĐ', () {
    final estimate = PricingEstimate.calculate(
      serviceType: DeliveryServiceType.express30m,
      distanceMeters: 14500,
      durationSeconds: 2700,
      isPeakHour: true,
      voucherDiscount: 20000,
    );

    expect(estimate.baseFare, 15000);
    expect(estimate.distanceFare, 123250);
    expect(estimate.surchargeFee, 20000);
    expect(estimate.discountAmount, 20000);
    expect(estimate.totalAmount, 138250);
  });

  test('TC-02: Máy trạng thái hữu hạn OrderStatus FSM kiểm soát chặt chẽ chuyển đổi hợp lệ và bất hợp lệ', () {
    expect(OrderStatus.draft.canTransitionTo(OrderStatus.searching), isTrue);
    expect(OrderStatus.draft.canTransitionTo(OrderStatus.delivered), isFalse);
    expect(
      OrderStatus.inTransit.canTransitionTo(OrderStatus.delivered),
      isTrue,
    );
    expect(
      OrderStatus.delivered.canTransitionTo(OrderStatus.cancelled),
      isFalse,
    );
  });

  test('TC-03 & TC-04: Thuật toán Ray-Casting Point-in-Polygon, Bộ lọc Kalman 2D & Chính sách Pin thích ứng', () {
    const polygon = [
      GeoPoint(latitude: 10.76, longitude: 106.68),
      GeoPoint(latitude: 10.76, longitude: 106.71),
      GeoPoint(latitude: 10.79, longitude: 106.71),
      GeoPoint(latitude: 10.79, longitude: 106.68),
    ];
    const insidePoint = GeoPoint(latitude: 10.7769, longitude: 106.6953);
    expect(GeoMath.isPointInPolygon(insidePoint, polygon), isTrue);

    final kalman = KalmanGpsFilter();
    final smoothed = kalman.filter(
      rawPoint: const GeoPoint(latitude: 10.7769, longitude: 106.6953),
      accuracyMeters: 8.0,
      timestampMs: 1700000000000,
    );
    expect(smoothed.latitude, closeTo(10.7769, 0.001));

    final lowBatteryPolicy = GpsIntegrityValidator.resolvePolicy(
      batteryLevelPercent: 15,
      isCharging: false,
    );
    expect(lowBatteryPolicy.enable3dBuildings, isFalse);
    expect(lowBatteryPolicy.cameraPitch, 0.0);

    // Kiểm chứng AppStateStore đồng bộ trạng thái giữa các phân hệ
    final store = AppStateStore.instance;
    final initialCount = store.orders.length;
    final newOrder = store.createNewOrder(
      pickupAddress: '123 Lê Lợi, Q.1',
      dropoffAddress: '456 Nguyễn Huệ, Q.1',
      recipientName: 'Khách Test',
      recipientPhone: '0912345678',
      packageDescription: 'Hàng kiểm thử',
      weightKg: 1.0,
      dimensionsCm: '20x10x10 cm',
      serviceType: DeliveryServiceType.express30m,
      codAmount: 200000,
      paymentMethod: 'Tiền mặt (COD)',
      voucherCode: 'PROMO20K',
    );
    expect(store.orders.length, initialCount + 1);
    store.driverAcceptOrder(newOrder.trackingCode);
    expect(newOrder.status, OrderStatus.accepted);
  });

  test('TC-09: SmartDispatchEngine, SecurityAndBarcodeUtils, RBAC & Di chuyển Lộ trình Trực tiếp', () {
    final store = AppStateStore.instance;

    // 1. Xếp hạng ứng viên tài xế SmartDispatchEngine (3km -> 5km -> 8km + công thức trọng số)
    final ranked = SmartDispatchEngine.rankDriversForPickup(
      pickupLocation: const GeoPoint(latitude: 10.7769, longitude: 106.7009),
      drivers: store.drivers,
    );
    expect(ranked, isNotEmpty);
    expect(ranked.first.totalScore, greaterThan(0.5));

    // 2. Che số điện thoại bảo mật & Tạo chữ ký thanh toán chống trùng lặp
    expect(
      SecurityAndBarcodeUtils.maskPhoneNumber('0912345678', shouldMask: true),
      '0912***678',
    );
    final sig1 = SecurityAndBarcodeUtils.generatePaymentSignature(
      orderCode: 'GH-882910',
      amount: 138250,
      method: 'Tiền mặt (COD)',
    );
    expect(sig1.length, equals(16));

    // 3. Kiểm tra thực thi phân quyền quản trị RBAC
    store.setAdminActiveRole('Hỗ trợ CSKH');
    expect(store.hasAdminPermission('Tài chính: Thanh toán'), isFalse);
    store.setAdminActiveRole('Super Admin');
    expect(store.hasAdminPermission('Tài chính: Thanh toán'), isTrue);

    // 4. Di chuyển tài xế dọc theo lộ trình & Kiểm tra hàng rào địa lý 100m
    store.stepDriverAlongRoute(snapToDropoff: true);
    expect(store.routeProgressStep, equals(10));
    expect(store.distanceFromDriverToDropoffMeters(), lessThanOrEqualTo(100.0));
  });

  test('TC-10: OpenStreetMap Nominatim, Định tuyến OSRM & Cấu hình Cloud Supabase lúc chạy', () async {
    // 1. Cấu hình nóng kết nối Cloud Supabase lúc chạy
    EnvConfig.configureSupabaseRuntime(
      url: 'https://demo-gps-postgis.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.demo',
    );
    expect(EnvConfig.isSupabaseConfigured, isTrue);

    // Đặt lại cấu hình mặc định sau khi kiểm tra
    EnvConfig.configureSupabaseRuntime(url: '', anonKey: '');
    expect(EnvConfig.isSupabaseConfigured, isFalse);

    // 2. Giải mã địa chỉ Google Maps / Nominatim & Tìm đường Google Directions / OSRM
    final tileUrl = EnvConfig.buildGoogleMapTileUrl(
      x: 26018,
      y: 15416,
      z: 15,
      layer: 'm,traffic',
    );
    expect(tileUrl.contains('.google.com/vt/lyrs=m,traffic'), isTrue);
    expect(tileUrl.contains('x=26018&y=15416&z=15'), isTrue);
    expect(tileUrl.contains('apistyle='), isFalse);

    final cleanBgTileUrl = EnvConfig.buildGoogleMapTileUrl(
      x: 26096,
      y: 15397,
      z: 15,
      hideLabels: true,
    );
    expect(cleanBgTileUrl.contains('apistyle=s.e%3Al%7Cp.v%3Aoff'), isTrue);

    final decodedPolyline = SmartDispatchEngine.decodeGoogleEncodedPolyline(
      '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
    );
    expect(decodedPolyline.length, equals(3));
    expect(decodedPolyline.first.latitude, closeTo(38.5, 0.01));
    expect(decodedPolyline.first.longitude, closeTo(-120.2, 0.01));

    final places = await SmartDispatchEngine.fetchLiveNominatimSuggestions(
      'Phố Huế',
      api: ManagedDeliveryFixture(),
    );
    expect(places, isNotEmpty);

    final route = await SmartDispatchEngine.fetchLiveOsrmRoute(
      const GeoPoint(latitude: 21.0145, longitude: 105.8512),
      const GeoPoint(latitude: 20.9951, longitude: 105.8286),
      api: ManagedDeliveryFixture(),
    );
    expect(route.distanceMeters, greaterThan(500));
    expect(route.polylinePoints.length, greaterThanOrEqualTo(2));
    expect(route.isLiveOsrm, isTrue);
  });

  test('TC-11: Kiểm tra tính nhất quán Logic Nghiệp vụ (Voucher %, Hoa hồng 80%, Chặn hủy FSM, Ký quỹ 200k & Hoàn tiền Rút)', () async {
    final store = AppStateStore.instance;
    expect(EnvConfig.driverAcceptTimeoutSeconds, equals(28));

    // 1. Kiểm tra Voucher phần trăm (GHN-BACKTOSCHOOL: giảm 10%, tối đa 25.000đ)
    final pctOrder = store.createNewOrder(
      pickupAddress: '145 Phố Huế, Hai Bà Trưng, Hà Nội',
      dropoffAddress:
          'Số 15, Ngõ 100, Đường Lê Trọng Tấn, Quận Thanh Xuân, Hà Nội',
      recipientName: 'Khách Voucher %',
      recipientPhone: '0912345678',
      packageDescription: 'Kiện hàng kiểm tra %',
      weightKg: 1.0,
      dimensionsCm: '20x10x10 cm',
      serviceType: DeliveryServiceType.express30m,
      codAmount: 100000,
      paymentMethod: 'Tiền mặt (COD)',
      voucherCode: 'GHN-BACKTOSCHOOL',
      customDistanceMeters: 14500,
      customDurationSeconds: 2610,
    );
    // Tổng cước trước giảm là 158.250đ -> 10% là 15.825đ (<= 25.000đ)
    expect(pctOrder.discountAmount, closeTo(15825, 1.0));

    // 2. Chuyển đơn qua các bước tới IN_TRANSIT -> Không được phép hủy
    store.driverAdvanceOrderStatus(pctOrder.trackingCode); // ACCEPTED
    store.driverAdvanceOrderStatus(pctOrder.trackingCode); // ARRIVING_PICKUP
    store.driverAdvanceOrderStatus(pctOrder.trackingCode); // IN_TRANSIT
    expect(pctOrder.status, equals(OrderStatus.inTransit));
    final cancelWhileInTransit = store.cancelOrder(
      pctOrder.trackingCode,
      'Đổi ý khi xe đang giao',
    );
    expect(cancelWhileInTransit, isFalse);
    expect(pctOrder.status, equals(OrderStatus.inTransit));

    // 3. Hoàn tất giao hàng (DELIVERED) -> Tài xế nhận đúng 80% cước vận chuyển
    final balanceBefore = store.driverWalletBalance;
    store.driverAdvanceOrderStatus(pctOrder.trackingCode); // DELIVERED
    final expectedDriverEarning =
        ((pctOrder.deliveryFee + pctOrder.surchargeFee) * 0.80).roundToDouble();
    expect(
      store.driverWalletBalance,
      closeTo(balanceBefore + expectedDriverEarning, 1.0),
    );

    // 4. Rút tiền vượt quá số dư ký quỹ 200.000đ bị từ chối
    final overWithdraw = store.requestWithdrawal(
      ownerName: 'Nguyễn Văn Nam',
      ownerRole: 'Tài xế',
      amount: store.driverWalletBalance - 100000, // Còn lại 100k < 200k
      bankName: 'Vietcombank',
      accountMasked: '007100****889',
    );
    expect(overWithdraw, isFalse);

    // 5. Rút tiền hợp lệ và được hoàn lại ví khi Admin Từ chối lệnh rút
    final validWithdrawAmount = 100000.0;
    final balBeforeWithdraw = store.driverWalletBalance;
    final okWithdraw = store.requestWithdrawal(
      ownerName: 'Nguyễn Văn Nam',
      ownerRole: 'Tài xế',
      amount: validWithdrawAmount,
      bankName: 'Vietcombank',
      accountMasked: '007100****889',
    );
    expect(okWithdraw, isTrue);
    expect(
      store.driverWalletBalance,
      closeTo(balBeforeWithdraw - validWithdrawAmount, 1.0),
    );

    final newestReqId = store.withdrawalRequests.first.id;
    store.updateWithdrawalStatus(newestReqId, 'Từ chối');
    expect(store.driverWalletBalance, closeTo(balBeforeWithdraw, 1.0));

    // 6. Đánh giá chuyến hàng + Tip chỉ cộng ví 1 lần duy nhất (chống cộng trùng Tip)
    final balBeforeTip = store.driverWalletBalance;
    store.submitDriverRating(
      pctOrder.trackingCode,
      5,
      'Giao nhanh đúng giờ',
      tipVnd: 10000,
    );
    expect(store.driverWalletBalance, closeTo(balBeforeTip + 10000, 1.0));
    store.submitDriverRating(
      pctOrder.trackingCode,
      4,
      'Cập nhật lại nhận xét',
      tipVnd: 10000,
    );
    expect(store.driverWalletBalance, closeTo(balBeforeTip + 10000, 1.0));
    expect(pctOrder.ratingStars, equals(4));

    // 7. Đổi tên/SĐT hồ sơ khách hàng vẫn bảo toàn danh sách đơn hàng và sổ địa chỉ
    final prevName = store.customerFullName;
    final prevPhone = store.customerPhone;
    final prevOrdersCount = store.customerOrders.length;
    final prevAddrCount = store.customerSavedAddresses.length;
    store.updateCustomerProfile(
      fullName: 'Trần Thị Bích Ngọc',
      phone: '0912345699',
      email: store.customerEmail,
      defaultAddress: store.customerDefaultAddress,
    );
    expect(store.customerOrders.length, equals(prevOrdersCount));
    expect(store.customerSavedAddresses.length, equals(prevAddrCount));
    store.updateCustomerProfile(
      fullName: prevName,
      phone: prevPhone,
      email: store.customerEmail,
      defaultAddress: store.customerDefaultAddress,
    );

    // 8. Phụ phí khối lượng (>5kg) + Dễ vỡ (+5k) + Giữ lạnh (+10k) & Luồng Sự cố -> Chuyển hoàn (RETURNING)
    final heavyFragileOrder = store.createNewOrder(
      pickupAddress: '145 Phố Huế, Hai Bà Trưng, Hà Nội',
      dropoffAddress:
          'Số 15, Ngõ 100, Đường Lê Trọng Tấn, Quận Thanh Xuân, Hà Nội',
      recipientName: 'Khách Kiểm Tra Phụ Phí',
      recipientPhone: '0912345678',
      packageDescription: 'Thực phẩm (Dễ vỡ, Giữ lạnh)',
      weightKg: 7.0, // +6.000đ (>5kg) + 5.000đ (Dễ vỡ) + 10.000đ (Giữ lạnh) = +21.000đ
      dimensionsCm: '30x20x15 cm',
      serviceType: DeliveryServiceType.express30m,
      codAmount: 250000,
      paymentMethod: 'Tiền mặt (COD)',
    );
    expect(heavyFragileOrder.surchargeFee, closeTo(20000 + 21000, 1.0));

    store.driverAcceptOrder(heavyFragileOrder.trackingCode);
    store.driverAdvanceOrderStatus(
      heavyFragileOrder.trackingCode,
    ); // ARRIVING_PICKUP
    store.driverAdvanceOrderStatus(
      heavyFragileOrder.trackingCode,
    ); // IN_TRANSIT
    expect(heavyFragileOrder.status, equals(OrderStatus.inTransit));

    store.addIncidentOrComplaint(
      orderId: heavyFragileOrder.trackingCode,
      reporterName: 'Tài xế Nguyễn Văn Nam',
      issueType: 'Khách không nhận hàng',
      description: 'Gọi 3 cuộc không nghe máy',
    );
    expect(heavyFragileOrder.status, equals(OrderStatus.failed));

    final returnOk = store.requeueOrReturnOrder(
      heavyFragileOrder.trackingCode,
      isReturn: true,
    );
    expect(returnOk, isTrue);
    expect(heavyFragileOrder.status, equals(OrderStatus.returning));

    store.driverAdvanceOrderStatus(heavyFragileOrder.trackingCode);
    expect(heavyFragileOrder.status, equals(OrderStatus.delivered));
    expect(heavyFragileOrder.paymentStatus, equals('RETURNED'));
    store.submitDriverRating(
      heavyFragileOrder.trackingCode,
      5,
      'Thử đánh giá đơn hoàn kho',
      tipVnd: 15000,
    );
    expect(heavyFragileOrder.ratingStars, isNull);

    final currentActiveName = store.customerFullName;
    final adminCreated = store.registerUserAccountWithRole(
      phone: '0909888777',
      fullName: 'Đối tác Tạo Từ Admin',
      password: '12345678',
      role: SubsystemRole.merchant,
      activateSession: false,
    );
    expect(adminCreated, isNotNull);
    expect(store.customerFullName, equals(currentActiveName));

    final dualCsv = store.parseAndCreateBulkOrdersFromCsv(
      'ten_nguoi_nhan,sdt_nguoi_nhan,dia_chi_giao,mo_ta_hang,khoi_luong_kg,tien_cod_vnd,loai_dich_vu\n'
      'Lê Văn Bốn,0901234567,120 Nguyễn Trãi Quận 5 TP.HCM,320000\n'
      'Phạm Thị Bảy,0902345678,45 Lê Duẩn Quận 1 TP.HCM,Giày thể thao,1.8,450000,EXPRESS',
      customPickupAddress: '123 Đường Lê Lợi Quận 1 TP.HCM',
    );
    expect(dualCsv.validCount, equals(2));
    expect(dualCsv.rows[0].codAmount, closeTo(320000, 1.0));
    expect(dualCsv.rows[1].codAmount, closeTo(450000, 1.0));
    expect(dualCsv.rows[1].serviceType, equals(DeliveryServiceType.express30m));

    final otp4 = SecurityAndBarcodeUtils.generateOrderDeliveryOtp4('#DH123456');
    expect(RegExp(r'^[0-9]{4}$').hasMatch(otp4), isTrue);
    expect(
      SecurityAndBarcodeUtils.generateOrderDeliveryOtp4('#DH123456'),
      equals(otp4),
    );

    final reassignTarget = store.createNewOrder(
      pickupAddress: '123 Lê Lợi, Q.1, TP.HCM',
      dropoffAddress: '456 Nguyễn Huệ, Q.1, TP.HCM',
      recipientName: 'Khách Điều Phối Lại',
      recipientPhone: '0912345678',
      packageDescription: 'Điện tử & Hàng dễ vỡ',
      weightKg: 2.0,
      dimensionsCm: '20x15x10 cm',
      serviceType: DeliveryServiceType.standard,
      codAmount: 0,
      paymentMethod: 'Ví MoMo',
    );
    final targetDriver = store.drivers.first;
    final assignOk = store.adminAssignOrReassignDriver(
      trackingCode: reassignTarget.trackingCode,
      driver: targetDriver,
    );
    expect(assignOk, isTrue);
    expect(reassignTarget.assignedDriverName, equals(targetDriver.fullName));
    expect(
      store.distanceFromDriverToOrderDropoffMeters(reassignTarget),
      greaterThanOrEqualTo(0.0),
    );

    // 9. Hàng đợi Offline chỉ tăng khi có thao tác thật & Bồi thường khiếu nại chỉ áp dụng đúng loại sự cố hàng hóa/COD
    store.toggleOfflineSimulation(false);
    expect(store.offlineQueueCount, equals(0));
    store.toggleOfflineSimulation(true);
    expect(store.offlineQueueCount, equals(0));
    store.addIncidentOrComplaint(
      orderId: reassignTarget.trackingCode,
      reporterName: 'Tài xế Nguyễn Văn Nam',
      issueType: 'Kẹt xe nghiêm trọng / Khác',
      description: 'Ùn tắc nút giao Ngã Tư Sở',
    );
    expect(store.offlineQueueCount, equals(1));
    store.toggleOfflineSimulation(false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await store.drainOfflineSyncQueue(), equals(0));
    expect(store.offlineQueueCount, equals(1));
    await SqliteOfflineQueueDatasource.instance.clearAllPendingSyncItems();
    await store.drainOfflineSyncQueue();

    final trafficTicket = store.complaints.first.ticketCode;
    final codBeforeTrafficResolve = store.merchantCodBalance;
    store.replyComplaint(
      trafficTicket,
      'Đã ghi nhận và điều chỉnh ETA',
      'Đã giải quyết',
    );
    expect(store.merchantCodBalance, closeTo(codBeforeTrafficResolve, 0.1));

    // 10. Chặn tự động đăng ký ảo khi đang ở chế độ Đăng nhập (isRegister: false), chặn tự khóa Admin & chặn gán đơn cho tài xế chưa duyệt KYC
    expect(
      store.authenticateOrRegisterAccount(
        phone: '0999888111',
        password: 'PasswordKhongTonTai',
        isRegister: false,
      ),
      isFalse,
    );
    expect(store.toggleUserAccountStatus('USR-04'), isFalse);
    final unapprovedDriver = store.drivers.firstWhere(
      (d) => d.approvalStatus != 'Đã duyệt',
    );
    expect(
      store.adminAssignOrReassignDriver(
        trackingCode: reassignTarget.trackingCode,
        driver: unapprovedDriver,
      ),
      isFalse,
    );

    store.selectDriverOrder('#DH123456');
    store.stepDriverAlongRoute(snapToDropoff: true);
  });

  test('TC-12: Thực thi thật 100% (Lưu đĩa JSON, Băm mật khẩu + OTP 6 số, EMVCo VietQR + Idempotency, Batch CSV, Xuất tệp A6 & POD SVG)', () async {
    final store = AppStateStore.instance;

    // 1. Lưu và nạp lại trạng thái bền vững trên đĩa hệ thống
    final snapshotPath = await store.saveStateSnapshotToDisk();
    expect(File(snapshotPath).existsSync(), isTrue);
    final loaded = await store.loadStateSnapshotFromDisk();
    expect(loaded, isTrue);

    // 2. Đăng ký mật khẩu băm SHA-256 + Salt và xác thực OTP 6 chữ số có thời hạn 120s
    final regOk = store.authenticateOrRegisterAccount(
      phone: '0988776655',
      password: 'MatKhauAnToan99',
      isRegister: true,
      fullName: 'Lê Minh Tuấn',
    );
    expect(regOk, isTrue);
    expect(
      store.authenticateOrRegisterAccount(
        phone: '0988776655',
        password: 'SaiMatKhau',
        isRegister: false,
      ),
      isFalse,
    );
    expect(
      store.authenticateOrRegisterAccount(
        phone: '0988776655',
        password: 'MatKhauAnToan99',
        isRegister: false,
      ),
      isTrue,
    );

    final otp6 = store.generateOtpForPhone('0988776655');
    expect(otp6.length, equals(6));
    expect(store.getRemainingOtpSeconds('0988776655'), greaterThan(100));
    expect(
      EnvConfig.formatVietnamPhoneE164('0988776655'),
      equals('+84988776655'),
    );
    expect(store.verifyOtpCode('0988776655', '000000'), isFalse);
    expect(store.verifyOtpCode('0988776655', otp6), isTrue);

    final resetOtp = store.generateOtpForPhone('+84988776655');
    final resetUser = store.resetPasswordWithOtp(
      phoneOrEmail: '0988776655',
      otpCode: resetOtp,
      newPassword: 'MatKhauMoi2026',
    );
    expect(resetUser, isNotNull);
    expect(
      store.authenticateWithPassword(
        phoneOrEmail: '0988776655',
        password: 'MatKhauMoi2026',
      ),
      isNotNull,
    );

    // 3. Chuỗi EMVCo Napas247 VietQR kèm CRC-16/CCITT-FALSE và khóa chống thu trùng Idempotency
    final emvQr = SecurityAndBarcodeUtils.generateEmvVietQrPayload(
      orderCode: '#DH123456',
      amountVnd: 138250,
    );
    expect(emvQr.startsWith('00020101021238540010A000000727'), isTrue);
    expect(emvQr.contains('6304'), isTrue);

    final payFirst = store.processOrderPayment(
      trackingCode: '#DH123456',
      gateway: 'VNPay / VietQR',
      transactionId: 'TXN-998877',
    );
    expect(payFirst, isTrue);
    final payDuplicate = store.processOrderPayment(
      trackingCode: '#DH123456',
      gateway: 'VNPay / VietQR',
      transactionId: 'TXN-998877',
    );
    expect(payDuplicate, isFalse);

    // 4. Phân tích cú pháp CSV hàng loạt và khởi tạo đơn thực tế
    final ordersBeforeCsv = store.orders.length;
    final csvRes = store.parseAndCreateBulkOrdersFromCsv(
      'Nguyễn Văn H,0912345678,123 Đường Lê Lợi Quận 1 TP.HCM,Gốm sứ,2.0,300000,EXPRESS\n'
      'Lỗi SĐT,123,Địa chỉ ngắn,Hàng lỗi,1.0,100000,STANDARD',
      commitOrders: true,
      customPickupAddress: '145 Phố Huế, Hai Bà Trưng, Hà Nội',
    );
    expect(csvRes.validCount, equals(1));
    expect(csvRes.invalidCount, equals(1));
    expect(store.orders.length, equals(ordersBeforeCsv + 1));

    // 5. Kết xuất tệp vận đơn khổ A6 (.html) và ảnh bằng chứng POD (.svg) ra đĩa hệ thống
    final a6Path = await SecurityAndBarcodeUtils.exportA6LabelToHtmlFile(
      trackingCode: '#DH123456',
      storeName: store.merchantStoreName,
      warehouseAddress: store.merchantWarehouses.first.address,
      recipientName: 'Nguyễn Thị Minh An',
      recipientPhone: '0912345678',
      dropoffAddress: '15 Lê Trọng Tấn, Thanh Xuân, Hà Nội',
      packageDescription: '2x Áo thun Polo',
      codAmount: 1500000,
    );
    expect(File(a6Path).existsSync(), isTrue);

    final podSvgPath =
        await SecurityAndBarcodeUtils.exportPodWatermarkToSvgFile(
          orderCode: '#DH123456',
          recipientName: 'Nguyễn Thị Minh An',
          otpCode: '4829',
          driverLocation: const GeoPoint(
            latitude: 20.9951,
            longitude: 105.8286,
          ),
          distanceMeters: 12.4,
        );
    expect(File(podSvgPath).existsSync(), isTrue);

    // 5b. Xác minh cấu hình SMTP TLS thực tế (RealAuthDeliveryService) và đăng nhập Google OAuth 2.0
    expect(EnvConfig.isSmtpConfigured, isFalse);
    expect(EnvConfig.smtpSenderEmail, isEmpty);

    final oauthUser = store.signInOrRegisterOAuthUser(
      email: 'khach.google.oauth@gmail.com',
      fullName: 'Khách Google OAuth',
    );
    expect(oauthUser, isNotNull);
    expect(oauthUser!.email, equals('khach.google.oauth@gmail.com'));
    expect(oauthUser.role, equals(SubsystemRole.customer));

    // 5c. Luồng chuẩn: Tài khoản mới mặc định là CUSTOMER -> Nộp KYC Chờ duyệt -> Admin Duyệt tự động nâng cấp vai trò
    final newCustomer = store.registerUserAccountWithRole(
      phone: '0966554433',
      fullName: 'Phạm Hoàng Quân',
      password: '123456',
      role: SubsystemRole.customer,
    );
    expect(newCustomer, isNotNull);
    expect(newCustomer!.role, equals(SubsystemRole.customer));

    store.registerOrUpdateDriverKyc(
      fullName: 'Phạm Hoàng Quân',
      phone: '0966554433',
      citizenId: '079098001122',
      vehicleType: 'Xe máy',
      licensePlate: '59-P1 998.87',
    );
    final pendingDrv = store.drivers.firstWhere(
      (d) => d.phone.contains('0966554433'),
    );
    expect(pendingDrv.approvalStatus, equals('Chờ duyệt'));
    expect(
      store.findUserByPhone('0966554433')!.role,
      equals(SubsystemRole.customer),
    );

    store.updateDriverApproval(pendingDrv.id, 'Đã duyệt');
    expect(pendingDrv.approvalStatus, equals('Đã duyệt'));
    expect(
      store.findUserByPhone('0966554433')!.role,
      equals(SubsystemRole.driver),
    );

    final newShopOwner = store.registerUserAccountWithRole(
      phone: '0955443322',
      fullName: 'Đặng Thu Thảo',
      password: '123456',
      role: SubsystemRole.customer,
    );
    expect(newShopOwner!.role, equals(SubsystemRole.customer));
    store.registerOrUpdateMerchantKyc(
      ownerPhone: '0955443322',
      storeName: 'Mỹ phẩm Thảo Nguyên',
      businessType: 'Công ty TNHH',
      taxCode: '0319988776',
      representativeName: 'Đặng Thu Thảo',
      bankName: 'ACB',
      bankAccount: '8899001122',
    );
    final pendingMer = store.merchantApplicants.firstWhere(
      (m) => m.ownerPhone.contains('0955443322'),
    );
    expect(pendingMer.approvalStatus, equals('Chờ duyệt'));
    expect(
      store.findUserByPhone('0955443322')!.role,
      equals(SubsystemRole.customer),
    );

    store.updateMerchantApproval(pendingMer.id, 'Đã duyệt');
    expect(pendingMer.approvalStatus, equals('Đã duyệt'));
    expect(
      store.findUserByPhone('0955443322')!.role,
      equals(SubsystemRole.merchant),
    );
    expect(pendingDrv.walletBalance, closeTo(0.0, 0.1));
    expect(pendingMer.codBalance, closeTo(0.0, 0.1));

    // Kiểm chứng cô lập ví, chuyến xe, vận đơn B2B, khiếu nại & lịch sử rút tiền giữa các tài khoản khác nhau
    store.applyAuthenticatedUserSession(store.findUserByPhone('0966554433')!);
    expect(store.driverWalletBalance, closeTo(0.0, 0.1));
    expect(store.driverPersonalOrders, isEmpty);
    expect(store.activeDriverPersonalOrderRecord, isNull);

    store.applyAuthenticatedUserSession(store.findUserByPhone('0955443322')!);
    expect(store.merchantCodBalance, closeTo(0.0, 0.1));
    expect(store.merchantPersonalWithdrawals, isEmpty);
    expect(
      store.merchantPersonalOrders.any(
        (o) => o.trackingCode == '#DH123456' || o.trackingCode == '#DH789101',
      ),
      isFalse,
    );
    expect(store.merchantPersonalComplaints, isEmpty);

    final shop2CountBefore = store.merchantPersonalOrders.length;
    final shop2Order = store.createNewOrder(
      pickupAddress: '25 Nguyễn Trãi, Quận 1, TP. HCM',
      dropoffAddress: '88 Lê Lợi, Quận 1, TP. HCM',
      recipientName: 'Khách Mỹ Phẩm',
      recipientPhone: '0911223344',
      packageDescription: 'Mỹ phẩm chính hãng',
      weightKg: 1.0,
      dimensionsCm: '15x10x10 cm',
      serviceType: DeliveryServiceType.standard,
      codAmount: 450000,
      paymentMethod: 'Tiền mặt (COD)',
      customCustomerName: store.merchantStoreName,
    );
    expect(store.merchantPersonalOrders.length, equals(shop2CountBefore + 1));
    expect(
      store.merchantPersonalOrders.first.trackingCode,
      equals(shop2Order.trackingCode),
    );

    // Khôi phục ngữ cảnh tài khoản chuẩn cho các bài kiểm thử giao diện tiếp theo
    store.applyAuthenticatedUserSession(store.findUserByPhone('0987654321')!);
    store.applyAuthenticatedUserSession(store.findUserByPhone('0909112233')!);
    expect(
      store.merchantPersonalOrders.any(
        (o) => o.trackingCode == shop2Order.trackingCode,
      ),
      isFalse,
    );
    store.applyAuthenticatedUserSession(store.findUserByPhone('0912345678')!);
    store.selectDriverOrder('#DH123456');
    store.stepDriverAlongRoute(snapToDropoff: true);

    // 6. Xác minh tồn tại thực tế của 4 tệp biểu tượng 3D AI đã tinh gọn trong assets/icons_3d
    for (final style in Icon3dStyle.values) {
      final iconFile = File(style.assetPath);
      expect(iconFile.existsSync(), isTrue);
      expect(iconFile.lengthSync(), greaterThan(100000));
    }
  });

  testWidgets(
    'TC-13: Hoạt ảnh 3D đa thành phần (Animated3dIconBadge) chuyển động liên tục 60 FPS qua các khung hình cho cả 4 mẫu Icon',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Animated3dIconBadge(
                  style: Icon3dStyle.scooterExpress,
                  forceContinuousInTest: true,
                ),
                Animated3dIconBadge(
                  style: Icon3dStyle.parcelBox,
                  forceContinuousInTest: true,
                ),
                Animated3dIconBadge(
                  style: Icon3dStyle.gpsPinRadar,
                  forceContinuousInTest: true,
                ),
                Animated3dIconBadge(
                  style: Icon3dStyle.walletVault,
                  forceContinuousInTest: true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(Animated3dIconBadge), findsNWidgets(4));

      // Tiến hành chạy qua nhiều khung hình thời gian thực để xác nhận vòng lặp hoạt ảnh liên tục không dừng
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(tester.binding.hasScheduledFrame, isTrue);

      // Kiểm chứng Màn hình Hoạt ảnh Khởi động 3D (Studio3dStartupSplashScreen)
      bool splashCompleted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Studio3dStartupSplashScreen(
            duration: const Duration(milliseconds: 1000),
            forceContinuousInTest: true,
            onCompleted: () => splashCompleted = true,
          ),
        ),
      );
      expect(find.byType(Studio3dStartupSplashScreen), findsOneWidget);
      expect(find.text('Vào hệ thống ngay'), findsOneWidget);
      expect(
        find.text(
          'CSDL: ${AppStateStore.instance.users.length} TK • ${AppStateStore.instance.orders.length} đơn',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(splashCompleted, isFalse);
      await tester.pump(const Duration(milliseconds: 600));
      expect(splashCompleted, isTrue);

      // Kiểm chứng toán học hướng xoay 3D của mô hình xe Meshy (mũi xe -X, đuôi thùng hàng +X) trên mọi góc di chuyển 360°
      for (final pitch in <double>[0.36, 0.44, 0.62]) {
        final cp = math.cos(pitch);
        final sp = math.sin(pitch);
        for (var deg = 0; deg < 360; deg += 10) {
          final targetRad = deg * math.pi / 180.0;
          final dx = math.cos(targetRad);
          final dy = math.sin(targetRad);
          final yaw = MeshyScooter3dMesh.yawForScreenTangent(
            dx,
            dy,
            pitchRadians: pitch,
          );
          final cy = math.cos(yaw);
          final sy = math.sin(yaw);

          // Phép chiếu y hệt MeshyScooter3dMesh.renderToCanvas cho mũi xe (-0.8, 0, 0) và đuôi xe (+0.8, 0, 0)
          final frontScreenX = -0.8 * cy;
          final frontZ1 = 0.8 * sy;
          final frontScreenY = frontZ1 * sp;
          final frontDepthZ2 = frontZ1 * cp;

          final rearScreenX = 0.8 * cy;
          final rearZ1 = -0.8 * sy;
          final rearScreenY = rearZ1 * sp;
          final rearDepthZ2 = rearZ1 * cp;

          final vecX = frontScreenX - rearScreenX;
          final vecY = frontScreenY - rearScreenY;
          final projectedAngle = math.atan2(vecY, vecX);
          final angleDiff = math.atan2(
            math.sin(projectedAngle - targetRad),
            math.cos(projectedAngle - targetRad),
          );
          expect(angleDiff.abs(), lessThan(1e-9));
          if (dy > 0.05) {
            expect(frontDepthZ2, greaterThan(rearDepthZ2));
          } else if (dy < -0.05) {
            expect(frontDepthZ2, lessThan(rearDepthZ2));
          }
        }
      }

      final smoothPts = MeshyScooter3dMesh.buildSmoothFilletedRoute3D(const [
        (-640.0, 260.0),
        (-430.0, 80.0),
        (-360.0, -180.0),
        (360.0, -190.0),
      ]);
      expect(smoothPts.length, greaterThan(16));
      for (final p in <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
        final sample = MeshyScooter3dMesh.sampleRouteArcLength3D(smoothPts, p);
        final norm = math.sqrt(
          sample.tangentX * sample.tangentX + sample.tangentZ * sample.tangentZ,
        );
        expect(norm, closeTo(1.0, 1e-6));
      }
    },
  );

  testWidgets(
    'TC-14: Kiểm chứng giao diện Tự động Scale linh hoạt theo khung hình mỗi thiết bị (360x800, 412x915, 768x1024, 1024x768, 1366x768, 1920x1080) đạt 0 lỗi tràn trên toàn bộ 50 màn hình',
    (WidgetTester tester) async {
      final viewports = <Size>[
        const Size(360, 800),
        const Size(412, 915),
        const Size(768, 1024),
        const Size(1024, 768),
        const Size(1366, 768),
        const Size(1920, 1080),
      ];
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const customerScreens = <int>[
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
      ];
      const driverScreens = <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
      const merchantScreens = <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      const adminScreens = <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
      final layoutErrors = <String>[];

      Future<void> pumpAndCollect(String label, Size size, Widget child) async {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(
              '$label-${size.width.toInt()}x${size.height.toInt()}',
            ),
            home: Scaffold(body: child),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        dynamic err = tester.takeException();
        while (err != null) {
          layoutErrors.add(
            '[$label @ ${size.width.toInt()}x${size.height.toInt()}] $err',
          );
          err = tester.takeException();
        }
      }

      for (final size in viewports) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await pumpAndCollect(
          'Splash3D',
          size,
          Studio3dStartupSplashScreen(onCompleted: () {}),
        );

        await pumpAndCollect('AuthGateway', size, const GpsDeliveryApp());

        for (final idx in customerScreens) {
          await pumpAndCollect(
            'Customer($idx)',
            size,
            CustomerSubsystemEntry(forcedScreenIndex: idx, onLogout: () {}),
          );
        }

        for (final idx in driverScreens) {
          await pumpAndCollect(
            'Driver($idx)',
            size,
            DriverSubsystemEntry(forcedScreenIndex: idx, onLogout: () {}),
          );
        }

        for (final idx in merchantScreens) {
          await pumpAndCollect(
            'Merchant($idx)',
            size,
            MerchantSubsystemEntry(forcedScreenIndex: idx, onLogout: () {}),
          );
        }

        for (final idx in adminScreens) {
          await pumpAndCollect(
            'Admin($idx)',
            size,
            AdminSubsystemEntry(forcedScreenIndex: idx, onLogout: () {}),
          );
        }
      }

      expect(layoutErrors, isEmpty, reason: layoutErrors.join('\n---\n'));
    },
  );

  testWidgets(
    'TC-15: Kiểm chứng tính hợp lý nghiệp vụ liên vai trò (Đối soát COD khớp 0đ, Chặn vùng RESTRICTED_ZONE, CSV RFC-4180, Luồng Giao thất bại -> Hoàn kho 50% cước, Giới hạn lượt dùng Voucher & Tách biệt RBAC Matrix)',
    (WidgetTester tester) async {
      final store = AppStateStore.instance;
      store.setAdminActiveRole('Super Admin');

      // 1. Đối soát COD của MER-01 khớp 100% toán học (0đ chênh lệch)
      final mer01 = store.merchantApplicants.firstWhere(
        (m) => m.id == 'MER-01',
      );
      final rec01 = store.codReconciliations.firstWhere(
        (r) => r.merchantId == 'MER-01',
      );
      final mer01Withdrawals = store.withdrawalRequests
          .where((w) => w.ownerId == 'MER-01' && w.status != 'Từ chối')
          .fold<double>(0.0, (s, w) => s + w.amount);
      expect(
        rec01.netPayoutAmount,
        equals(mer01.codBalance + mer01Withdrawals),
      );

      // 2. Chặn tạo đơn đi vào vùng RESTRICTED_ZONE (Cảng Tân Thuận, Q.7)
      final pickupPt = SmartDispatchEngine.resolveAddressToCoordinate(
        'Chợ Bến Thành, Quận 1',
        fallback: const GeoPoint(latitude: 10.7725, longitude: 106.6980),
      );
      final restrictedDropoffPt =
          SmartDispatchEngine.resolveAddressToCoordinate(
            'Cảng Tân Thuận, Khu Chế Xuất Q.7',
            fallback: const GeoPoint(latitude: 10.7425, longitude: 106.7250),
          );
      final restrictedZone = store.findActiveRestrictedZoneForRoute(
        pickupPt,
        restrictedDropoffPt,
      );
      expect(restrictedZone, isNotNull);
      expect(restrictedZone!.zoneType, equals('RESTRICTED_ZONE'));

      // 3. CSV RFC-4180 hỗ trợ dấu phẩy trong ngoặc kép & bỏ qua dòng thuộc RESTRICTED_ZONE
      final merUser = store.findUserByPhone('0909112233')!;
      store.applyAuthenticatedUserSession(
        merUser,
        activeWorkspaceRole: SubsystemRole.merchant,
      );
      final csvResult = store.parseAndCreateBulkOrdersFromCsv(
        'ten_nguoi_nhan,sdt_nguoi_nhan,dia_chi_giao,tien_cod_vnd\n'
        'Lê Minh Tuấn,0918223344,"123 Lê Lợi, Phường Bến Thành, Quận 1",450000\n'
        'Trần Hải Cảng,0918556677,"Cảng Tân Thuận, Khu Chế Xuất Q.7",300000',
        commitOrders: true,
      );
      expect(csvResult.validCount, equals(1));
      expect(csvResult.invalidCount, equals(1));
      final targetCode = csvResult.createdTrackingCodes.first;
      final targetOrder = store.orders.firstWhere(
        (o) => o.trackingCode == targetCode,
      );
      expect(
        targetOrder.dropoffAddress,
        equals('123 Lê Lợi, Phường Bến Thành, Quận 1'),
      );

      // 4. Luồng Tài xế báo Giao thất bại -> Shop yêu cầu Hoàn kho -> Trả kho 50% cước (80% về ví TX, khấu trừ COD Shop)
      final drvUser = store.findUserByPhone('0987654321')!;
      store.applyAuthenticatedUserSession(
        drvUser,
        activeWorkspaceRole: SubsystemRole.driver,
      );
      store.driverAcceptOrder(targetOrder.trackingCode);
      store.driverAdvanceOrderStatus(targetOrder.trackingCode);
      store.driverAdvanceOrderStatus(targetOrder.trackingCode);
      expect(targetOrder.status, equals(OrderStatus.inTransit));

      final markedFailed = store.driverMarkDeliveryFailed(
        targetOrder.trackingCode,
        'Khách đi vắng không nhận hàng',
      );
      expect(markedFailed, isTrue);
      expect(targetOrder.status, equals(OrderStatus.failed));

      store.applyAuthenticatedUserSession(
        merUser,
        activeWorkspaceRole: SubsystemRole.merchant,
      );
      final markedReturning = store.requeueOrReturnOrder(
        targetOrder.trackingCode,
        isReturn: true,
      );
      expect(markedReturning, isTrue);
      expect(targetOrder.status, equals(OrderStatus.returning));

      store.applyAuthenticatedUserSession(
        drvUser,
        activeWorkspaceRole: SubsystemRole.driver,
      );
      final drvBeforeReturn = store.activeDriverRecord!.walletBalance;
      final merBeforeReturn = mer01.codBalance;
      final expectedReturnFee =
          ((targetOrder.deliveryFee + targetOrder.surchargeFee) * 0.50)
              .roundToDouble();
      final expectedDriverReturnComp = (expectedReturnFee * 0.80)
          .roundToDouble();

      store.driverAdvanceOrderStatus(targetOrder.trackingCode);
      expect(targetOrder.status, equals(OrderStatus.delivered));
      expect(targetOrder.paymentStatus, equals('RETURNED'));
      expect(
        store.activeDriverRecord!.walletBalance,
        equals(drvBeforeReturn + expectedDriverReturnComp),
      );
      expect(mer01.codBalance, equals(merBeforeReturn - expectedReturnFee));
      final updatedRec01 = store.codReconciliations.firstWhere(
        (r) => r.merchantId == 'MER-01',
      );
      expect(
        updatedRec01.netPayoutAmount,
        equals(mer01.codBalance + mer01Withdrawals),
      );

      // 5. Giới hạn lượt dùng Voucher (usageLimit = 1)
      final adminUser = store.findUserByPhone('0900999999')!;
      store.applyAuthenticatedUserSession(
        adminUser,
        activeWorkspaceRole: SubsystemRole.admin,
      );
      store.createNewVoucher(
        code: 'ONCE15K',
        title: 'Giảm 15k dùng 1 lần',
        discountValue: 15000,
        isPercentage: false,
        minOrderValue: 20000,
        usageLimit: 1,
      );
      final vOnce = store.vouchers.firstWhere((v) => v.code == 'ONCE15K');
      expect(vOnce.isUsable, isTrue);
      final firstVoucherOrd = store.createNewOrder(
        pickupAddress: 'Chợ Bến Thành, Quận 1',
        dropoffAddress: 'Landmark 81, Bình Thạnh',
        recipientName: 'Khách Voucher 1',
        recipientPhone: '0933445566',
        packageDescription: 'Tài liệu',
        weightKg: 1.0,
        dimensionsCm: '20x15x10',
        serviceType: DeliveryServiceType.standard,
        codAmount: 0,
        paymentMethod: 'Tiền mặt (Người gửi trả phí)',
        voucherCode: 'ONCE15K',
      );
      expect(firstVoucherOrd.discountAmount, equals(15000));
      expect(vOnce.usedCount, equals(1));
      expect(vOnce.isUsable, isFalse);

      final secondVoucherOrd = store.createNewOrder(
        pickupAddress: 'Chợ Bến Thành, Quận 1',
        dropoffAddress: 'Landmark 81, Bình Thạnh',
        recipientName: 'Khách Voucher 2',
        recipientPhone: '0933445577',
        packageDescription: 'Tài liệu',
        weightKg: 1.0,
        dimensionsCm: '20x15x10',
        serviceType: DeliveryServiceType.standard,
        codAmount: 0,
        paymentMethod: 'Tiền mặt (Người gửi trả phí)',
        voucherCode: 'ONCE15K',
      );
      expect(secondVoucherOrd.discountAmount, equals(0));

      // 6. UC46 RBAC Matrix: Chọn xem vai trò khác không tự động tước quyền phiên Super Admin
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminSubsystemEntry(forcedScreenIndex: 11, onLogout: () {}),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(store.currentAdminRoleName, equals('Super Admin'));
      await tester.tap(find.text('Kế toán'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(store.currentAdminRoleName, equals('Super Admin'));

      store.clearAuthenticatedSession();
    },
  );

  test('TC-16: Hạ tầng Lõi (SQLite local_sync_queue 1:1 Offline/Drain, Mã vạch ISO/IEC 15417 Code-128B, PostGIS EWKT GeoPoint, DriverEntity Escrow & SystemArchitectureCubit)', () async {
    final store = AppStateStore.instance;
    final sqlite = SqliteOfflineQueueDatasource();

    // 1. Khi Online: các thao tác KHÔNG làm phình bảng SQLite local_sync_queue
    store.toggleOfflineSimulation(false);
    await store.drainOfflineSyncQueue();
    expect(await sqlite.getPendingQueueCount(), equals(0));
    expect(store.offlineQueueCount, equals(0));

    final onlineOrd = store.createNewOrder(
      pickupAddress: 'Chợ Bến Thành, Quận 1',
      dropoffAddress: 'Dinh Độc Lập, Quận 1',
      recipientName: 'Khách Online Sync',
      recipientPhone: '0911223344',
      packageDescription: 'Tài liệu đối soát',
      weightKg: 0.8,
      dimensionsCm: '20x15x5',
      serviceType: DeliveryServiceType.standard,
      codAmount: 0,
      paymentMethod: 'Tiền mặt (Người gửi trả phí)',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await sqlite.getPendingQueueCount(), equals(0));
    expect(store.offlineQueueCount, equals(0));

    // 2. Khi Offline: tạo đơn + hủy đơn tăng chính xác 1:1 với bản ghi SQLite, không nhân đôi
    store.toggleOfflineSimulation(true);
    final offlineOrd = store.createNewOrder(
      pickupAddress: 'Chợ Bến Thành, Quận 1',
      dropoffAddress: 'Landmark 81, Bình Thạnh',
      recipientName: 'Khách Offline Queue',
      recipientPhone: '0911223355',
      packageDescription: 'Hộp linh kiện',
      weightKg: 1.2,
      dimensionsCm: '25x20x10',
      serviceType: DeliveryServiceType.express30m,
      codAmount: 150000,
      paymentMethod: 'Tiền mặt (Người gửi trả phí)',
    );
    expect(store.offlineQueueCount, equals(1));

    final cancelledOffline = store.cancelOrder(
      offlineOrd.trackingCode,
      'Đổi địa chỉ nhận khi đang mất mạng',
    );
    expect(cancelledOffline, isTrue);
    expect(store.offlineQueueCount, equals(2));

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(await sqlite.getPendingQueueCount(), equals(2));

    // Reconnecting without a configured cloud must retain unsent commands.
    store.toggleOfflineSimulation(false);
    expect(await store.drainOfflineSyncQueue(), equals(0));
    expect(store.offlineQueueCount, equals(2));
    expect(await sqlite.getPendingQueueCount(), equals(2));
    await sqlite.clearAllPendingSyncItems();
    await store.drainOfflineSyncQueue();

    // 4. Mã vạch chuẩn ISO/IEC 15417 Code-128B (Start B=104, Mod-103 Checksum, Stop=106) & A6 SVG
    final symbols = SecurityAndBarcodeUtils.encodeCode128BSymbols('GHST-01');
    expect(symbols.first, equals(104));
    expect(symbols.last, equals(106));
    expect(symbols.length, equals('GHST-01'.length + 3));
    int verifySum = 104;
    for (var i = 0; i < 'GHST-01'.length; i++) {
      verifySum += ('GHST-01'.codeUnitAt(i) - 32) * (i + 1);
    }
    expect(symbols[symbols.length - 2], equals(verifySum % 103));

    final a6File = await SecurityAndBarcodeUtils.exportA6LabelToHtmlFile(
      trackingCode: onlineOrd.trackingCode,
      storeName: 'Thời trang Việt Nam',
      warehouseAddress: 'Quận 1, TP.HCM',
      recipientName: onlineOrd.recipientName,
      recipientPhone: onlineOrd.recipientPhone,
      dropoffAddress: onlineOrd.dropoffAddress,
      packageDescription: onlineOrd.packageDescription,
      codAmount: 250000,
    );
    final a6Content = await File(a6File).readAsString();
    expect(a6Content.contains('<svg'), isTrue);
    expect(a6Content.contains(onlineOrd.trackingCode), isTrue);

    // 5. Giải mã PostGIS EWKT / GeoJSON & Kiểm tra ký quỹ 200.000đ trên DriverEntity
    final parsedEwkt = GeoPoint.tryParsePostgis(
      'SRID=4326;POINT(106.7009 10.7769)',
    );
    expect(parsedEwkt, isNotNull);
    expect(parsedEwkt!.latitude, closeTo(10.7769, 1e-6));
    expect(parsedEwkt.longitude, closeTo(106.7009, 1e-6));

    final orderFromSqlRow = OrderEntity.fromMap({
      'id': 'ORD-SQL-01',
      'tracking_code': '#DH999888',
      'customer_id': 'USR-01',
      'service_type': 'EXPRESS',
      'pickup_address': 'Quận 1',
      'pickup_location': 'SRID=4326;POINT(106.6980 10.7725)',
      'dropoff_address': 'Quận 3',
      'dropoff_location': {'latitude': 10.7820, 'longitude': 106.6900},
      'distance_meters': 2400,
      'duration_seconds': 600,
      'delivery_fee': 25000,
      'total_amount': 25000,
      'payment_method': 'CASH',
      'status': 'SEARCHING',
      'created_at': DateTime.now().toIso8601String(),
    });
    expect(orderFromSqlRow.pickupLocation.latitude, closeTo(10.7725, 1e-5));
    expect(orderFromSqlRow.dropoffLocation.longitude, closeTo(106.6900, 1e-5));

    final lowEscrowDriver = DriverEntity.fromMap({
      'id': 'DRV-LOW',
      'phone': '0909111222',
      'full_name': 'Tài xế Thiếu Ký Quỹ',
      'license_plate': '59-X1 111.22',
      'vehicle_type': 'Xe máy',
      'citizen_id': '079099001122',
      'is_online': 1,
      'current_location': 'SRID=4326;POINT(106.7009 10.7769)',
      'approval_status': 'Đã duyệt',
      'wallet_balance': 150000,
    });
    expect(lowEscrowDriver.computeDispatchScore(parsedEwkt), equals(-1.0));

    final validDriver = DriverEntity.fromMap({
      'id': 'DRV-OK',
      'phone': '0909111333',
      'full_name': 'Tài xế Đủ Ký Quỹ',
      'license_plate': '59-X1 333.44',
      'vehicle_type': 'Xe máy',
      'citizen_id': '079099003344',
      'is_online': true,
      'current_location': 'SRID=4326;POINT(106.7009 10.7769)',
      'approval_status': 'Đã duyệt',
      'wallet_balance': 500000,
    });
    expect(validDriver.computeDispatchScore(parsedEwkt), greaterThan(0.8));

    // 6. SystemArchitectureCubit đồng bộ pin thực tế sang AppStateStore mà không làm trôi tọa độ ảo
    final cubit = SystemArchitectureCubit();
    final locBefore = store.activeDriverLocation;
    cubit.updateBatteryLevel(12);
    expect(store.batteryPercent, equals(12));
    expect(cubit.state.batteryPolicy.pingIntervalSeconds, equals(10));
    expect(cubit.state.batteryPolicy.enable3dBuildings, isFalse);
    cubit.updateBatteryLevel(8);
    expect(cubit.state.batteryPolicy.pingIntervalSeconds, equals(30));
    expect(cubit.state.lastSmoothedGps, equals(locBefore));
    await cubit.close();
    store.batteryPercent = 85;
  });

  test('TC-17: Kiểm chứng SQLite v5 16 bảng Cold Hydration (reloadFromSqlite), Loopback HTTP Webhook & Clean Architecture Repositories Offline Fallback', () async {
    final store = AppStateStore.instance;
    await store.initializeDatabase();
    store.activeAuthenticatedUser = null;
    store.merchantStoreName = 'Cửa hàng Gốm Sứ Việt';
    store.currentAdminRoleName = 'Super Admin';
    store.toggleOfflineSimulation(false);

    // 1. Tạo Voucher giới hạn lượt dùng & áp dụng vào đơn hàng mới
    final vch = store.createNewVoucher(
      code: 'VCHSQL5',
      title: 'Ưu đãi kiểm thử SQLite v5',
      discountValue: 15000,
      isPercentage: false,
      minOrderValue: 20000,
      usageLimit: 25,
    );
    expect(vch, isNotNull);
    expect(vch!.usageLimit, equals(25));
    expect(vch.usedCount, equals(0));

    final createdOrd = store.createNewOrder(
      pickupAddress: '123 Đường Lê Lợi, Quận 1, TP. HCM',
      dropoffAddress: '88 Nguyễn Huệ, Quận 1, TP. HCM',
      recipientName: 'Khách Kiểm Thử v5',
      recipientPhone: '0909555666',
      packageDescription: 'Tài liệu đối soát SQLite v5',
      weightKg: 1.2,
      dimensionsCm: '25 x 20 x 10 cm',
      serviceType: DeliveryServiceType.standard,
      codAmount: 100000,
      paymentMethod: 'Tiền mặt (COD)',
      voucherCode: 'VCHSQL5',
    );
    expect(createdOrd.discountAmount, equals(15000));
    expect(
      store.vouchers.firstWhere((v) => v.code == 'VCHSQL5').usedCount,
      equals(1),
    );

    // 2. Đổi kho chính sang kho phụ (kiểm chứng sửa lỗi WH-01 bị ép về kho chính sau Cold Restart)
    final addedWh = store.addMerchantWarehouse(
      name: 'Kho Quận 7 Kiểm Thử v5',
      address: '45 Nguyễn Thị Thập, Quận 7, TP. HCM',
      contactPhone: '0909777888',
      openHours: '07:30 - 20:30',
    );
    store.updateMerchantWarehouseDetails(
      warehouseId: addedWh.id,
      name: addedWh.name,
      address: addedWh.address,
      contactPhone: addedWh.contactPhone,
      openHours: addedWh.openHours,
      setPrimary: true,
    );
    expect(
      store.merchantWarehouses.firstWhere((w) => w.id == 'WH-01').isPrimary,
      isFalse,
    );
    expect(
      store.merchantWarehouses.firstWhere((w) => w.id == addedWh.id).isPrimary,
      isTrue,
    );

    // 3. Kiểm chứng HTTP POST Webhook thật qua Loopback Server + Lưu cột webhook_url
    Map<String, dynamic>? receivedWebhookPayload;
    String? receivedSignatureHeader;
    final webhookServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    webhookServer.listen((HttpRequest req) async {
      receivedSignatureHeader = req.headers.value('X-GoMau-Signature');
      final rawBody = await utf8.decoder.bind(req).join();
      receivedWebhookPayload = jsonDecode(rawBody) as Map<String, dynamic>;
      req.response.statusCode = HttpStatus.ok;
      req.response.write('{"ok":true}');
      await req.response.close();
    });
    final testWebhookUrl = 'http://127.0.0.1:${webhookServer.port}/b2b-webhook';
    final webhookMsg = await HttpOverrides.runZoned(
      () => store.saveAndTestMerchantWebhook(webhookUrl: testWebhookUrl),
      createHttpClient: (ctx) =>
          _RealLoopbackHttpOverrides().createHttpClient(ctx),
    );
    await webhookServer.close(force: true);
    expect(webhookMsg, contains('HTTP 200'));
    expect(receivedWebhookPayload, isNotNull);
    expect(receivedWebhookPayload!['event'], equals('ORDER_STATUS_UPDATED'));
    expect(
      receivedWebhookPayload!['signature'],
      equals(receivedSignatureHeader),
    );

    // 4. Ghi nhận từ chối chuyến của Tài xế vào cột rejected_count
    store.activeDriverId = 'DV10928';
    final rejBefore = store.activeDriverRecord!.rejectedCount;
    store.recordDriverDispatchRejection(createdOrd.trackingCode);
    final expectedRej = rejBefore + 1;
    expect(store.activeDriverRecord!.rejectedCount, equals(expectedRej));

    await Future<void>.delayed(const Duration(milliseconds: 80));

    // 5. Xóa bộ nhớ RAM & Cold Hydrate từ SQLite 16 bảng
    store.vouchers.clear();
    store.merchantWarehouses.clear();
    store.merchantApplicants.clear();
    store.drivers.clear();
    await store.reloadFromSqlite();

    final hydratedVch = store.vouchers.firstWhere((v) => v.code == 'VCHSQL5');
    expect(hydratedVch.usageLimit, equals(25));
    expect(hydratedVch.usedCount, equals(1));

    final hydratedWh01 = store.merchantWarehouses.firstWhere(
      (w) => w.id == 'WH-01',
    );
    final hydratedAddedWh = store.merchantWarehouses.firstWhere(
      (w) => w.id == addedWh.id,
    );
    expect(hydratedWh01.isPrimary, isFalse);
    expect(hydratedAddedWh.isPrimary, isTrue);
    expect(hydratedAddedWh.contactPhone, equals('0909777888'));

    final hydratedMer = store.merchantApplicants.firstWhere(
      (m) => m.id == 'MER-01',
    );
    expect(hydratedMer.webhookUrl, equals(testWebhookUrl));

    final hydratedDrv = store.drivers.firstWhere((d) => d.id == 'DV10928');
    expect(hydratedDrv.rejectedCount, equals(expectedRej));

    // Khôi phục WH-01 làm kho chính & xóa kho tạm
    store.updateMerchantWarehouseDetails(
      warehouseId: 'WH-01',
      name: hydratedWh01.name,
      address: hydratedWh01.address,
      setPrimary: true,
    );
    expect(store.deleteMerchantWarehouse(addedWh.id), isTrue);
    await store.saveAndTestMerchantWebhook(webhookUrl: '');

    // 6. Kiểm chứng Clean Architecture DriverRepositoryImpl & OrderRepositoryImpl (SQLite Offline Fallback)
    final remoteDs = SupabasePostgisDatasource();
    final localDs = SqliteOfflineQueueDatasource.instance;
    final driverRepo = DriverRepositoryImpl(
      remoteDatasource: remoteDs,
      localOfflineDatasource: localDs,
    );
    final orderRepo = OrderRepositoryImpl(
      remoteDatasource: remoteDs,
      localOfflineDatasource: localDs,
    );

    final repoOrder = OrderEntity(
      id: 'ORD-REPO-TC17',
      trackingCode: '#DH771717',
      customerId: 'USR-TC17',
      serviceType: DeliveryServiceType.express30m,
      pickupAddress: '123 Lê Lợi, Quận 1, TP. HCM',
      pickupLocation: const GeoPoint(latitude: 10.7725, longitude: 106.6980),
      dropoffAddress: '45 Nguyễn Thị Minh Khai, Quận 1, TP. HCM',
      dropoffLocation: const GeoPoint(latitude: 10.7825, longitude: 106.7010),
      distanceMeters: 2200,
      durationSeconds: 480,
      deliveryFee: 32000,
      totalAmount: 32000,
      paymentMethod: 'CASH',
      status: OrderStatus.searching,
      createdAt: DateTime.now(),
    );
    final savedRepoOrd = await orderRepo.createOrder(repoOrder);
    expect(savedRepoOrd.id, equals('ORD-REPO-TC17'));

    final customerRepoOrders = await orderRepo.getCustomerOrders('USR-TC17');
    expect(customerRepoOrders.any((o) => o.id == 'ORD-REPO-TC17'), isTrue);

    final acceptedRepoOrd = await orderRepo.updateOrderStatus(
      orderId: 'ORD-REPO-TC17',
      nextStatus: OrderStatus.accepted,
    );
    expect(acceptedRepoOrd.status, equals(OrderStatus.accepted));

    await driverRepo.recordDriverGpsSample(
      driverId: 'DV10928',
      activeOrderId: 'ORD-REPO-TC17',
      rawPoint: const GeoPoint(latitude: 10.7775, longitude: 106.6985),
      accuracyMeters: 6.0,
      speedKmh: 28.0,
      bearing: 120.0,
      isMockLocation: false,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );

    final streamedPoint = await orderRepo
        .watchDriverLocationForOrder('ORD-REPO-TC17')
        .first;
    expect(streamedPoint.latitude, closeTo(10.7775, 1e-3));
    expect(streamedPoint.longitude, closeTo(106.6985, 1e-3));

    final nearbyDrivers = await driverRepo.findNearbyOnlineDrivers(
      const GeoPoint(latitude: 10.7769, longitude: 106.6953),
    );
    expect(nearbyDrivers, isNotEmpty);

    await localDs.clearAllPendingSyncItems();
  });

  test('TC-18: Kiểm chứng Động cơ Quan hệ Web localStorage (WebLocalStorageRelationalEngine) & Giải mã Kép Enum SQLite/PostGIS', () async {
    SharedPreferences.setMockInitialValues({});
    final webEngine = WebLocalStorageRelationalEngine();

    // 1. Upsert & chống trùng lặp theo khóa chính / khóa duy nhất trên từng bảng
    await webEngine.upsertRow('users', {
      'id': 'USR-WEB-01',
      'phone': '0911000111',
      'full_name': 'Khách Web V1',
      'role': 'CUSTOMER',
    });
    await webEngine.upsertRow('users', {
      'id': 'USR-WEB-01-DUP',
      'phone': '0911000111',
      'full_name': 'Khách Web V2',
      'role': 'MERCHANT',
    });
    expect(await webEngine.countRows('users'), equals(1));

    await webEngine.upsertRow('vouchers', {
      'code': 'WEB50K',
      'discount_value': 50000,
      'used_count': 1,
    });
    await webEngine.updateRows(
      'vouchers',
      {'used_count': 4},
      where: 'code = ?',
      whereArgs: ['WEB50K'],
    );

    await webEngine.upsertRow('local_relational_entities', {
      'table_name': 'exports',
      'record_id': 'A6_DH999',
      'payload_json': '{"html":"<html></html>"}',
    });
    await webEngine.upsertRow('local_relational_entities', {
      'table_name': 'snapshots',
      'record_id': 'A6_DH999',
      'payload_json': '{"orders":[]}',
    });
    expect(await webEngine.countRows('local_relational_entities'), equals(2));

    // 2. Tự động tăng id (auto-increment) & chống trùng idempotency_key cho local_sync_queue
    await webEngine.upsertRow('local_sync_queue', {
      'idempotency_key': 'IDEM-01',
      'sync_status': 'PENDING',
      'created_at_ms': 1000,
    });
    await webEngine.upsertRow('local_sync_queue', {
      'idempotency_key': 'IDEM-02',
      'sync_status': 'PENDING',
      'created_at_ms': 3000,
    });
    await webEngine.upsertRow('local_sync_queue', {
      'idempotency_key': 'IDEM-01',
      'sync_status': 'SYNCED',
      'created_at_ms': 1000,
    });
    expect(await webEngine.countRows('local_sync_queue'), equals(2));

    final pendingRows = await webEngine.queryRows(
      'local_sync_queue',
      where: 'sync_status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'created_at_ms DESC',
      limit: 5,
    );
    expect(pendingRows.length, equals(1));
    expect(pendingRows.first['idempotency_key'], equals('IDEM-02'));
    expect(pendingRows.first['id'], isA<int>());

    // 3. Khởi tạo phiên mới hoàn toàn (Cold Reload từ SharedPreferences / localStorage)
    final reloadedWebEngine = WebLocalStorageRelationalEngine();
    final hydratedUsers = await reloadedWebEngine.queryRows(
      'users',
      where: 'phone = ? AND role = ?',
      whereArgs: ['0911000111', 'MERCHANT'],
    );
    expect(hydratedUsers.length, equals(1));
    expect(hydratedUsers.first['full_name'], equals('Khách Web V2'));

    final hydratedVouchers = await reloadedWebEngine.queryRows(
      'vouchers',
      where: 'code = ?',
      whereArgs: ['WEB50K'],
    );
    expect(hydratedVouchers.single['used_count'], equals(4));

    await reloadedWebEngine.upsertRow('local_sync_queue', {
      'idempotency_key': 'IDEM-03',
      'sync_status': 'PENDING',
      'created_at_ms': 5000,
    });
    final reloadedSyncRows = await reloadedWebEngine.queryRows(
      'local_sync_queue',
      where: 'idempotency_key = ?',
      whereArgs: ['IDEM-03'],
    );
    expect(reloadedSyncRows.single['id'], equals(3));

    await reloadedWebEngine.upsertRow('order_tracking_logs', {
      'order_code': '#DH888888',
      'driver_id': 'DV10928',
      'recorded_at': '2026-10-25T12:00:00Z',
    });
    final trackingLogs = await reloadedWebEngine.queryRows(
      'order_tracking_logs',
    );
    expect(trackingLogs.single['id'], equals(1));

    final deletedCount = await reloadedWebEngine.deleteRows(
      'local_relational_entities',
      where: 'table_name = ? AND record_id = ?',
      whereArgs: ['exports', 'A6_DH999'],
    );
    expect(deletedCount, equals(1));
    expect(
      await reloadedWebEngine.countRows('local_relational_entities'),
      equals(1),
    );

    // 4. Giải mã kép Enum OrderStatus & DeliveryServiceType (PostGIS SCREAMING_SNAKE + SQLite camelCase)
    expect(
      OrderStatus.fromDbCode('ARRIVING_PICKUP'),
      equals(OrderStatus.arrivingPickup),
    );
    expect(
      OrderStatus.fromDbCode('arrivingPickup'),
      equals(OrderStatus.arrivingPickup),
    );
    expect(OrderStatus.fromDbCode('IN_TRANSIT'), equals(OrderStatus.inTransit));
    expect(OrderStatus.fromDbCode('inTransit'), equals(OrderStatus.inTransit));

    expect(
      DeliveryServiceType.fromDbCode('EXPRESS_30M'),
      equals(DeliveryServiceType.express30m),
    );
    expect(
      DeliveryServiceType.fromDbCode('express30m'),
      equals(DeliveryServiceType.express30m),
    );
    expect(
      DeliveryServiceType.fromDbCode('EXPRESS'),
      equals(DeliveryServiceType.express30m),
    );
    expect(
      DeliveryServiceType.fromDbCode('saving'),
      equals(DeliveryServiceType.saving),
    );
    expect(
      DeliveryServiceType.fromDbCode('ECONOMY'),
      equals(DeliveryServiceType.saving),
    );

    final sqliteOrderRow = OrderEntity.fromMap({
      'id': 'ORD-SQLITE-CAMEL',
      'tracking_code': '#DH654321',
      'customer_id': 'USR-01',
      'service_type': 'express30m',
      'pickup_address': '12 Lê Lợi, Quận 1, TP. HCM',
      'pickup_lat': 10.7725,
      'pickup_lng': 106.6980,
      'dropoff_address': '90 Nguyễn Huệ, Quận 1, TP. HCM',
      'dropoff_lat': 10.7745,
      'dropoff_lng': 106.7030,
      'distance_meters': 1500,
      'duration_seconds': 300,
      'delivery_fee': 25000,
      'total_amount': 25000,
      'payment_method': 'CASH',
      'status': 'inTransit',
      'created_at': '2026-10-25T10:00:00Z',
    });
    expect(sqliteOrderRow.serviceType, equals(DeliveryServiceType.express30m));
    expect(sqliteOrderRow.status, equals(OrderStatus.inTransit));
  });

  test('TC-19: Kiểm toán toàn diện Production 6 Trụ cột (Offline Queue 1:1 cho Driver Ops, Snapshot GoogleLink=false, 2FA Pre-Verify không kích hoạt sớm, Chống bồi thường lặp & Voucher 1 lượt, RBAC Password Guard & Chuẩn hóa PostGIS EWKT + HTML Escape/QR Matrix)', () async {
    final store = AppStateStore.instance;
    final sqlite = SqliteOfflineQueueDatasource();

    // 1. Offline Queue 1:1 cho driverAdvanceOrderStatus & driverMarkDeliveryFailed (không bị nhân đôi offlineQueueCount)
    store.toggleOfflineSimulation(false);
    await store.drainOfflineSyncQueue();
    expect(await sqlite.getPendingQueueCount(), equals(0));
    expect(store.offlineQueueCount, equals(0));

    final drvOrd = store.createNewOrder(
      pickupAddress: 'Chợ Bến Thành, Quận 1, TP. HCM',
      dropoffAddress: 'Dinh Độc Lập, Quận 1, TP. HCM',
      recipientName: 'Khách Kiểm Toán Offline',
      customCustomerName: 'Khách Kiểm Toán Offline',
      recipientPhone: '0911888999',
      packageDescription: 'Hộp tài liệu kiểm toán',
      weightKg: 1.0,
      dimensionsCm: '20x15x10',
      serviceType: DeliveryServiceType.standard,
      codAmount: 120000,
      paymentMethod: 'Tiền mặt (Người gửi trả phí)',
    );
    final targetDriver = store.drivers.firstWhere(
      (d) => d.approvalStatus == 'Đã duyệt',
    );
    if (targetDriver.walletBalance < 250000) {
      targetDriver.walletBalance = 500000;
    }
    targetDriver.isOnline = true;
    store.setAdminActiveRole('Super Admin');
    expect(
      store.adminAssignOrReassignDriver(
        trackingCode: drvOrd.trackingCode,
        driver: targetDriver,
      ),
      isTrue,
    );

    store.toggleOfflineSimulation(true);
    expect(store.offlineQueueCount, equals(0));

    store.driverAdvanceOrderStatus(
      drvOrd.trackingCode,
      allowAdminOverride: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(store.offlineQueueCount, equals(1));
    expect(await sqlite.getPendingQueueCount(), equals(1));

    store.driverAdvanceOrderStatus(
      drvOrd.trackingCode,
      allowAdminOverride: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(drvOrd.status, equals(OrderStatus.inTransit));
    expect(store.offlineQueueCount, equals(2));
    expect(await sqlite.getPendingQueueCount(), equals(2));

    final failedOk = store.driverMarkDeliveryFailed(
      drvOrd.trackingCode,
      'Khách hẹn giao lại buổi chiều',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(failedOk, isTrue);
    expect(store.offlineQueueCount, equals(3));
    expect(await sqlite.getPendingQueueCount(), equals(3));

    store.toggleOfflineSimulation(false);
    expect(await store.drainOfflineSyncQueue(), equals(0));
    expect(store.offlineQueueCount, equals(3));
    expect(await sqlite.getPendingQueueCount(), equals(3));
    await sqlite.clearAllPendingSyncItems();
    await store.drainOfflineSyncQueue();

    // 2. Snapshot khôi phục chính xác isCustomerGoogleLinked = false
    store.toggleCustomerSocialLink(provider: 'GOOGLE', linked: false);
    expect(store.isCustomerGoogleLinked, isFalse);
    await store.saveStateSnapshotToDisk();
    store.isCustomerGoogleLinked = true;
    await store.loadStateSnapshotFromDisk();
    expect(store.isCustomerGoogleLinked, isFalse);

    // 3. authenticateWithPassword(activateSession: false) không làm rò rỉ phiên đăng nhập trước 2FA
    store.clearAuthenticatedSession();
    expect(store.activeAuthenticatedUser, isNull);
    final verifiedAdmin = store.authenticateWithPassword(
      phoneOrEmail: '0900999999',
      password: '12345678',
      activateSession: false,
    );
    expect(verifiedAdmin, isNotNull);
    expect(store.activeAuthenticatedUser, isNull);

    // 4. Khiếu nại: chống mở lại ticket đã đóng, chống cộng bồi thường lặp, cấp mã COMP<TICKET> 1 lượt
    store.setAdminActiveRole('Super Admin');
    store.addIncidentOrComplaint(
      orderId: drvOrd.trackingCode,
      reporterName: 'Khách Kiểm Toán Offline',
      issueType: 'Hàng bị hỏng khi vận chuyển',
      description: 'Móp góc hộp carton',
    );
    final createdTicket = store.complaints.first;
    final expectedCompCode =
        'COMP${createdTicket.ticketCode.toUpperCase().replaceAll(RegExp(r"[^A-Z0-9]"), "")}';
    store.replyComplaint(
      createdTicket.ticketCode,
      'Đã xác minh và cấp voucher đền bù',
      'Đã giải quyết',
    );
    expect(createdTicket.status, equals('Đã giải quyết'));
    final issuedVoucher = store.vouchers
        .where((v) => v.code == expectedCompCode)
        .firstOrNull;
    expect(issuedVoucher, isNotNull);
    expect(issuedVoucher!.usageLimit, equals(1));

    final repliesCountAfterResolve = createdTicket.replies.length;
    store.replyComplaint(
      createdTicket.ticketCode,
      'Thử mở lại trái phép',
      'Đang xử lý',
    );
    expect(createdTicket.status, equals('Đã giải quyết'));
    expect(createdTicket.replies.length, equals(repliesCountAfterResolve));

    // 5. RBAC Escalation Password Guard & Quản trị phương tiện / Đình chỉ tài xế
    store.authenticateWithPassword(
      phoneOrEmail: '0912345678',
      password: '12345678',
      activateSession: true,
    );
    expect(store.setAdminActiveRole('Kế toán'), isTrue);
    expect(store.currentAdminRoleName, equals('Kế toán'));
    expect(store.setAdminActiveRole('Super Admin'), isFalse);
    expect(store.setAdminActiveRole('Quản lý vận hành'), isFalse);
    expect(
      store.setAdminActiveRole(
        'Super Admin',
        adminPassword: 'wrong_password',
        requirePasswordVerification: true,
      ),
      isFalse,
    );
    expect(store.suspendOrUnsuspendDriver(targetDriver.id), isFalse);
    expect(
      store.setAdminActiveRole(
        'Super Admin',
        adminPassword: '12345678',
        requirePasswordVerification: true,
      ),
      isTrue,
    );
    expect(store.currentAdminRoleName, equals('Super Admin'));

    final currentDrv = store.drivers.firstWhere((d) => d.id == targetDriver.id);
    final oldPlate = currentDrv.licensePlate;
    expect(
      store.adminUpdateDriverVehicleInfo(
        driverId: currentDrv.id,
        vehicleType: currentDrv.vehicleType,
        licensePlate: '59-X3 888.99',
      ),
      isTrue,
    );
    expect(currentDrv.licensePlate, equals('59-X3 888.99'));
    store.adminUpdateDriverVehicleInfo(
      driverId: currentDrv.id,
      vehicleType: currentDrv.vehicleType,
      licensePlate: oldPlate,
    );

    // 6. PostGIS EWKT Schema Normalization & A6 HTML Sanitization + Real QR Matrix SVG
    final normalizedPgOrder =
        SupabasePostgisDatasource.normalizeForPostgisSchema('orders', {
          'id': 'ORD-PG-01',
          'tracking_code': '#DH888999',
          'customer_id': 'USR-01',
          'service_type': 'express30m',
          'pickup_address': '188 Phan Xích Long',
          'pickup_lat': 10.7992,
          'pickup_lng': 106.6865,
          'dropoff_address': 'Landmark 81',
          'dropoff_lat': 10.7950,
          'dropoff_lng': 106.7218,
          'package_description': 'Hàng dễ vỡ',
          'payment_method': 'Tiền mặt (Người gửi trả phí)',
          'payment_status': 'PAID',
          'status': 'inTransit',
          'delivered_at_ms': 1761400000000,
        });
    expect(normalizedPgOrder['service_type'], equals('EXPRESS_30M'));
    expect(normalizedPgOrder['status'], equals('IN_TRANSIT'));
    expect(
      normalizedPgOrder['pickup_location'],
      equals('SRID=4326;POINT(106.6865 10.7992)'),
    );
    expect(normalizedPgOrder['package_category'], equals('Hàng dễ vỡ'));
    expect(normalizedPgOrder['delivered_at'], isNotNull);

    final exportedHtmlPath =
        await SecurityAndBarcodeUtils.exportA6LabelToHtmlFile(
          trackingCode: '#DH888999',
          storeName: 'Shop <script>alert(1)</script>',
          warehouseAddress: '188 Phan Xích Long',
          recipientName: 'Nguyễn Văn B',
          recipientPhone: '0909123456',
          dropoffAddress: 'Landmark 81',
          packageDescription: 'Hộp tài liệu đối soát',
          codAmount: 150000,
        );
    final htmlContent = File(exportedHtmlPath).readAsStringSync();
    expect(htmlContent.contains('<script>alert(1)</script>'), isFalse);
    expect(htmlContent.contains('&lt;script&gt;alert(1)'), isTrue);
    expect(htmlContent.contains('viewBox="0 0 64 64"'), isTrue);

    store.clearAuthenticatedSession();
  });

  test('TC-20: Kiểm toán Chiều sâu Lượt 2 (Chuẩn hóa 16 bảng PostGIS, Bảo vệ Hijack SĐT, Lưu trạng thái Đình chỉ qua SQLite, Xe Van nhận đơn Tải, Chống trùng ID & Chuẩn hóa cước B2B)', () async {
    final store = AppStateStore.instance;
    await store.initializeDatabase();

    // 1. OrderEntity & DriverEntity nạp song song cả SQLite row lẫn PostGIS EWKT + tự động đóng dấu deliveredAt
    final sqliteHydratedOrder = OrderEntity.fromMap({
      'id': 'ORD-SQL-20',
      'tracking_code': '#DH202020',
      'customer_name': 'Nguyễn Thị Minh An',
      'service_type': 'truck',
      'pickup_address': '188 Phan Xích Long, Q. Phú Nhuận',
      'pickup_lat': 10.7992,
      'pickup_lng': 106.6865,
      'dropoff_address': 'Landmark 81, Q. Bình Thạnh',
      'dropoff_lat': 10.7950,
      'dropoff_lng': 106.7218,
      'recipient_name': 'Lê Hoàng Nam',
      'recipient_phone': '0909555666',
      'package_description': 'Thùng linh kiện',
      'weight_kg': 12.0,
      'distance_meters': 4200,
      'duration_seconds': 750,
      'delivery_fee': 65000.0,
      'surcharge_fee': 21000.0,
      'discount_amount': 0.0,
      'cod_amount': 250000.0,
      'total_amount': 86000.0,
      'payment_method': 'Tiền mặt (Người gửi trả phí)',
      'payment_status': 'UNPAID',
      'status': 'inTransit',
      'created_at_ms': 1761400000000,
    });
    expect(sqliteHydratedOrder.serviceType, equals(DeliveryServiceType.truck));
    expect(sqliteHydratedOrder.status, equals(OrderStatus.inTransit));
    final deliveredEntity = sqliteHydratedOrder.transitionTo(
      OrderStatus.delivered,
    );
    expect(deliveredEntity.deliveredAt, isNotNull);
    expect(deliveredEntity.paymentStatus, equals('PAID'));

    final hydratedDrv = DriverEntity.fromMap({
      'id': 'DV-PG-01',
      'phone': '0911223344',
      'full_name': 'Trần Quốc Tuấn',
      'license_plate': '59-D2 456.78',
      'vehicle_type': 'VAN',
      'current_location': 'SRID=4326;POINT(106.7009 10.7769)',
    });
    expect(hydratedDrv.vehicleType, equals('VAN'));
    expect(hydratedDrv.currentLocation?.latitude, closeTo(10.7769, 0.0001));

    // 2. Chuẩn hóa 16 bảng PostgreSQL/PostGIS: Đa giác khép vòng POLYGON, SUSPENDED, VAN, RETURNED & FK customer_id hợp lệ
    final pgGeo = SupabasePostgisDatasource.normalizeForPostgisSchema(
      'geofence_zones',
      {
        'id': 'GEO-TEST-01',
        'zone_name': 'Khu Công Nghệ Cao Q.9',
        'zone_type': 'SURCHARGE_ZONE',
        'surcharge_rate': 15000,
        'is_active': 1,
        'boundary_json': jsonEncode([
          {'lat': 10.8410, 'lng': 106.7850},
          {'lat': 10.8410, 'lng': 106.8050},
          {'lat': 10.8580, 'lng': 106.8050},
        ]),
      },
    );
    expect(
      pgGeo['polygon_boundary'].toString(),
      startsWith('SRID=4326;POLYGON(('),
    );
    expect(pgGeo['polygon_boundary'].toString(), endsWith('106.785 10.841))'));

    final pgDriver = SupabasePostgisDatasource.normalizeForPostgisSchema(
      'drivers',
      {
        'id': 'DV10999',
        'phone': '0909777888',
        'full_name': 'Võ Minh Khôi',
        'citizen_id': '079095009988',
        'license_plate': '51-D1 778.89',
        'vehicle_type': 'Xe Van 500kg',
        'approval_status': 'Đình chỉ',
        'latitude': 10.7769,
        'longitude': 106.7009,
      },
    );
    expect(pgDriver['vehicle_type'], equals('VAN'));
    expect(pgDriver['approval_status'], equals('SUSPENDED'));

    final pgReturnedOrd = SupabasePostgisDatasource.normalizeForPostgisSchema(
      'orders',
      {
        'id': 'ORD-RET-01',
        'tracking_code': '#DH777111',
        'customer_name': 'Tên hiển thị bất kỳ không phải ID',
        'payment_status': 'RETURNED',
        'status': 'returning',
        'pickup_lat': 10.77,
        'pickup_lng': 106.69,
        'dropoff_lat': 10.78,
        'dropoff_lng': 106.71,
      },
    );
    expect(pgReturnedOrd['payment_status'], equals('RETURNED'));
    expect(
      pgReturnedOrd['customer_id'],
      equals(SupabasePostgisDatasource.toDeterministicUuid('USR-01')),
    );

    // 3. Chặn chiếm quyền tài khoản khi đăng ký trùng số điện thoại (bao gồm Super Admin)
    final superAdminBefore =
        store.findUserByPhone('0909000114') ??
        store.users.firstWhere((u) => u.role == SubsystemRole.admin);
    final origHash = superAdminBefore.passwordHash;
    final hijackAttempt = store.registerUserAccountWithRole(
      phone: superAdminBefore.phone,
      fullName: 'Kẻ Giả Mạo',
      password: 'HackedPassword123',
      role: SubsystemRole.admin,
      activateSession: false,
    );
    expect(hijackAttempt, isNull);
    expect(superAdminBefore.passwordHash, equals(origHash));
    expect(
      store.authenticateOrRegisterAccount(
        phone: superAdminBefore.phone,
        password: 'HackedPassword123',
        isRegister: true,
        fullName: 'Kẻ Giả Mạo',
      ),
      isFalse,
    );

    // 4. Trạng thái Tài xế bị Đình chỉ ('Đình chỉ') được bảo toàn nguyên vẹn sau reloadFromSqlite()
    store.authenticateWithPassword(
      phoneOrEmail: superAdminBefore.phone,
      password: '12345678',
      activateSession: true,
    );
    store.setAdminActiveRole(
      'Super Admin',
      adminPassword: '12345678',
      requirePasswordVerification: true,
    );
    final targetSuspendDrv = store.drivers.firstWhere(
      (d) => d.approvalStatus == 'Đã duyệt',
    );
    expect(store.suspendOrUnsuspendDriver(targetSuspendDrv.id), isTrue);
    expect(targetSuspendDrv.approvalStatus, equals('Đình chỉ'));
    await store.reloadFromSqlite();
    final reloadedSuspendDrv = store.drivers.firstWhere(
      (d) => d.id == targetSuspendDrv.id,
    );
    expect(reloadedSuspendDrv.approvalStatus, equals('Đình chỉ'));
    expect(reloadedSuspendDrv.isOnline, isFalse);
    expect(store.suspendOrUnsuspendDriver(reloadedSuspendDrv.id), isTrue);
    expect(reloadedSuspendDrv.approvalStatus, equals('Đã duyệt'));

    // 5. Tài xế 'Xe Van' nhận được đơn DeliveryServiceType.truck & Cước B2B không cộng nhầm ghi chú phủ định
    final b2bTruckOrder = store.createNewOrder(
      pickupAddress: '188 Phan Xích Long, Quận Phú Nhuận, TP.HCM',
      dropoffAddress: 'Landmark 81, Quận Bình Thạnh, TP.HCM',
      recipientName: 'Khách Nhận Hàng Tải',
      recipientPhone: '0908112233',
      packageDescription: 'Nội thất (Tiêu chuẩn) • Ghi chú: Hàng không dễ vỡ, không cần giữ lạnh',
      weightKg: 3.0,
      dimensionsCm: '40 x 30 x 30 cm',
      serviceType: DeliveryServiceType.truck,
      codAmount: 0,
      paymentMethod: 'Tiền mặt (Người gửi trả phí)',
      isPrepaidConfirmed: false,
      isFragileTag: false,
      isKeepColdTag: false,
      customDistanceMeters: 3500,
      customDurationSeconds: 630,
    );
    expect(b2bTruckOrder.paymentStatus, equals('UNPAID'));
    final expectedCleanEst = PricingEstimate.calculate(
      serviceType: DeliveryServiceType.truck,
      distanceMeters: 3500,
      durationSeconds: 630,
      isPeakHour: store.isPeakSurchargeActive,
      geofenceSurcharge: 0.0,
      voucherDiscount: 0.0,
      baseFareScale: (store.baseFareConfig / 25000.0).clamp(0.4, 5.0),
      pricePerKmScale: (store.pricePerKmConfig / 5000.0).clamp(0.4, 5.0),
    );
    expect(b2bTruckOrder.surchargeFee, equals(expectedCleanEst.surchargeFee));
    expect(b2bTruckOrder.totalAmount, equals(expectedCleanEst.totalAmount));

    store.registerUserAccountWithRole(
      phone: '0933445566',
      fullName: 'Tài Xế Xe Van Sài Gòn',
      password: '12345678',
      role: SubsystemRole.customer,
      activateSession: false,
    );
    store.registerOrUpdateDriverKyc(
      fullName: 'Tài Xế Xe Van Sài Gòn',
      phone: '0933445566',
      citizenId: '079092004455',
      vehicleType: 'Xe Van',
      licensePlate: '51-D4 556.67',
    );
    final vanDrv = store.drivers.firstWhere((d) => d.phone == '0933445566');
    store.updateDriverApproval(vanDrv.id, 'Đã duyệt');
    vanDrv.walletBalance = 500000;
    store.authenticateWithPassword(
      phoneOrEmail: '0933445566',
      password: '12345678',
      activateSession: true,
    );
    store.setDriverOnlineStatus(true);
    store.driverAcceptOrder(b2bTruckOrder.trackingCode);
    expect(b2bTruckOrder.status, equals(OrderStatus.accepted));
    expect(b2bTruckOrder.assignedDriverName, equals('Tài Xế Xe Van Sài Gòn'));

    // 6. Chống trùng khóa chính ADDR-* / WH-* sau khi xóa phần tử ở giữa & Lưu contactName của kho
    final custUser = store.findUserByPhone('0901234567') ?? store.users.first;
    store.applyAuthenticatedUserSession(
      custUser,
      activeWorkspaceRole: SubsystemRole.customer,
    );
    store.addCustomerAddress(
      'Kho Tạm 1',
      '10 Nguyễn Thị Minh Khai, Q.1, TP.HCM',
    );
    final firstAddedId = store.savedAddresses.last.id;
    store.addCustomerAddress('Kho Tạm 2', '20 Điện Biên Phủ, Q.3, TP.HCM');
    final secondAddedId = store.savedAddresses.last.id;
    store.removeCustomerAddress(firstAddedId);
    store.addCustomerAddress('Kho Tạm 3', '30 Võ Văn Tần, Q.3, TP.HCM');
    final thirdAddedId = store.savedAddresses.last.id;
    expect(thirdAddedId, isNot(equals(secondAddedId)));
    expect(
      store.savedAddresses.map((a) => a.id).toSet().length,
      equals(store.savedAddresses.length),
    );

    final addedWh = store.addMerchantWarehouse(
      name: 'Kho Phú Nhuận Mở Rộng',
      address: '200 Phan Xích Long, Quận Phú Nhuận, TP.HCM',
      contactName: 'Trần Quản Kho',
      contactPhone: '0909334455',
    );
    expect(addedWh.contactName, equals('Trần Quản Kho'));
    await store.reloadFromSqlite();
    final reloadedWh = store.merchantWarehouses.firstWhere(
      (w) => w.id == addedWh.id,
    );
    expect(reloadedWh.contactName, equals('Trần Quản Kho'));

    store.clearAuthenticatedSession();
  });

  testWidgets(
    'TC-21: Kiểm chứng toàn diện PostGIS Hex EWKB, GPS Anti-Teleport & Kalman, Khóa tài khoản LOCKED, Phụ phí động Standard và Render 46 màn hình Mobile 360x800 + Empty-State 0 lỗi',
    (WidgetTester tester) async {
      final store = AppStateStore.instance;
      await store.initializeDatabase();
      await store.reloadFromSqlite();

      // 1. Giải mã nhị phân PostGIS Hex EWKB Point (SRID=4326, Little-Endian) & kiểm tra biên WGS84
      final ewkbBuf = ByteData(25);
      ewkbBuf.setUint8(0, 1); // Little-endian
      ewkbBuf.setUint32(1, 0x20000001, Endian.little); // Point + SRID flag
      ewkbBuf.setUint32(5, 4326, Endian.little);
      ewkbBuf.setFloat64(9, 106.7009, Endian.little); // X = lng
      ewkbBuf.setFloat64(17, 10.7769, Endian.little); // Y = lat
      final ewkbHex = ewkbBuf.buffer
          .asUint8List()
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join();
      final decodedEwkb = GeoPoint.tryParsePostgis(ewkbHex);
      expect(decodedEwkb, isNotNull);
      expect(decodedEwkb!.latitude, closeTo(10.7769, 1e-9));
      expect(decodedEwkb.longitude, closeTo(106.7009, 1e-9));

      final pointZ = GeoPoint.tryParsePostgis(
        'POINT Z (106.6953 10.7769 12.5)',
      );
      expect(pointZ, isNotNull);
      expect(pointZ!.latitude, closeTo(10.7769, 1e-6));
      expect(GeoPoint.tryParsePostgis('POINT(200.0 95.0)'), isNull);

      // 2. GpsIntegrityValidator (chặn dịch chuyển tức thời dt<=0 & biên WGS84) + KalmanGpsFilter
      final p1 = const GeoPoint(latitude: 10.7769, longitude: 106.6953);
      final p2Far = const GeoPoint(latitude: 10.7850, longitude: 106.7050);
      final p2Jitter = const GeoPoint(latitude: 10.77691, longitude: 106.69531);
      const tNowMs = 1700000000000;
      expect(
        () => GpsIntegrityValidator.validateSample(
          currentPoint: p2Far,
          currentTimestampMs: tNowMs,
          isMockFlaggedByOs: false,
          previousPoint: p1,
          previousTimestampMs: tNowMs,
        ),
        throwsA(
          isA<GpsIntegrityException>().having(
            (e) => e.ruleId,
            'ruleId',
            equals('RULE-GEO-02'),
          ),
        ),
      );

      expect(
        () => GpsIntegrityValidator.validateSample(
          currentPoint: p2Jitter,
          currentTimestampMs: tNowMs,
          isMockFlaggedByOs: false,
          previousPoint: p1,
          previousTimestampMs: tNowMs,
        ),
        returnsNormally,
      );

      final kalman = KalmanGpsFilter();
      final k1 = kalman.filter(
        rawPoint: p1,
        accuracyMeters: 8.0,
        timestampMs: 1000,
      );
      expect(k1.latitude, closeTo(p1.latitude, 1e-6));
      final kNan = kalman.filter(
        rawPoint: const GeoPoint(latitude: double.nan, longitude: 106.7),
        accuracyMeters: 8.0,
        timestampMs: 2000,
      );
      expect(kNan.latitude, closeTo(p1.latitude, 1e-6));
      final kAfterGap = kalman.filter(
        rawPoint: p2Far,
        accuracyMeters: 6.0,
        timestampMs: 90000,
      );
      expect(kAfterGap.latitude, closeTo(p2Far.latitude, 1e-6));

      // 3. DriverRepositoryImpl cách ly bộ lọc theo driverId & enqueue DRIVER_LOCATION_PING sạch (không ghi 'NO_ORDER')
      store.toggleOfflineSimulation(false);
      await store.drainOfflineSyncQueue();
      store.toggleOfflineSimulation(true);
      final drvRepo = DriverRepositoryImpl(
        remoteDatasource: SupabasePostgisDatasource(),
        localOfflineDatasource: SqliteOfflineQueueDatasource.instance,
      );
      await drvRepo.recordDriverGpsSample(
        driverId: 'DV10928',
        activeOrderId: null,
        rawPoint: p1,
        accuracyMeters: 6.0,
        speedKmh: 22.0,
        bearing: 90.0,
        isMockLocation: false,
        timestampMs: tNowMs,
      );
      final pendingItems = await SqliteOfflineQueueDatasource.instance
          .getPendingSyncItems();
      expect(
        pendingItems.any((e) => e.actionType == 'DRIVER_LOCATION_PING'),
        isTrue,
      );
      expect(
        pendingItems.any((e) => e.payload['order_id'] == 'NO_ORDER'),
        isFalse,
      );
      store.toggleOfflineSimulation(false);
      await store.drainOfflineSyncQueue();

      // 4. Phụ phí cao điểm cấu hình động cho gói Standard & chặn tài khoản LOCKED
      final prevPeakCfg = store.peakHourSurchargeConfig;
      final prevPeakFlag = store.isPeakSurchargeActive;
      store.peakHourSurchargeConfig = 18000;
      store.isPeakSurchargeActive = true;
      final stdPeakEst = PricingEstimate.calculate(
        serviceType: DeliveryServiceType.standard,
        distanceMeters: 2000,
        durationSeconds: 360,
        isPeakHour: true,
        configuredStandardPeakSurcharge: store.peakHourSurchargeConfig,
      );
      expect(stdPeakEst.surchargeFee, equals(18000));
      store.peakHourSurchargeConfig = prevPeakCfg;
      store.isPeakSurchargeActive = prevPeakFlag;

      final drvUser = store.findUserByPhone('0987654321');
      if (drvUser != null) {
        store.applyAuthenticatedUserSession(
          drvUser,
          activeWorkspaceRole: SubsystemRole.driver,
        );
        drvUser.status = 'LOCKED';
        store.setDriverOnlineStatus(true);
        expect(store.isDriverOnline, isFalse);
        drvUser.status = 'ACTIVE';
        store.setDriverOnlineStatus(true);
        expect(store.isDriverOnline, isTrue);
      }
      store.clearAuthenticatedSession();

      // 5. Render toàn bộ 46 màn hình phân hệ trên khung nhìn Mobile hẹp 360x800 + Empty-State (0 Overflow / 0 RangeError)
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Future<void> pumpClean(Widget child, String label) async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
        await tester.pump(const Duration(milliseconds: 60));
        final err = tester.takeException();
        expect(err, isNull, reason: 'Lỗi render trên $label: $err');
      }

      for (var i = 0; i < 15; i++) {
        await pumpClean(
          CustomerSubsystemEntry(
            key: ValueKey('cust_$i'),
            forcedScreenIndex: i,
          ),
          'Customer[$i]@360x800',
        );
      }
      for (var i = 0; i < 10; i++) {
        await pumpClean(
          DriverSubsystemEntry(key: ValueKey('drv_$i'), forcedScreenIndex: i),
          'Driver[$i]@360x800',
        );
      }
      for (var i = 0; i < 11; i++) {
        await pumpClean(
          MerchantSubsystemEntry(key: ValueKey('mer_$i'), forcedScreenIndex: i),
          'Merchant[$i]@360x800',
        );
      }
      for (var i = 0; i < 12; i++) {
        await pumpClean(
          AdminSubsystemEntry(key: ValueKey('adm_$i'), forcedScreenIndex: i),
          'Admin[$i]@360x800',
        );
      }

      // Kiểm tra chỉ số ngoài biên forcedScreenIndex = 999
      await pumpClean(
        const CustomerSubsystemEntry(
          key: ValueKey('cust_oob'),
          forcedScreenIndex: 999,
        ),
        'Customer[999]',
      );
      await pumpClean(
        const DriverSubsystemEntry(
          key: ValueKey('drv_oob'),
          forcedScreenIndex: 999,
        ),
        'Driver[999]',
      );
      await pumpClean(
        const MerchantSubsystemEntry(
          key: ValueKey('mer_oob'),
          forcedScreenIndex: 999,
        ),
        'Merchant[999]',
      );
      await pumpClean(
        const AdminSubsystemEntry(
          key: ValueKey('adm_oob'),
          forcedScreenIndex: 999,
        ),
        'Admin[999]',
      );

      // Kiểm tra trạng thái rỗng toàn bộ danh sách (Empty-State Guard)
      final bakOrders = List<ActiveOrderRecord>.from(store.orders);
      final bakVouchers = List<VoucherRecord>.from(store.vouchers);
      final bakZones = List<GeofenceZoneRecord>.from(store.geofenceZones);
      final bakRoles = List<RbacRoleRecord>.from(store.rbacRoles);
      final bakNotis = List<NotificationRecord>.from(store.notifications);
      final bakDrivers = List<DriverApplicantRecord>.from(store.drivers);
      final bakMerchants = List<MerchantApplicantRecord>.from(
        store.merchantApplicants,
      );
      try {
        store.orders.clear();
        store.vouchers.clear();
        store.geofenceZones.clear();
        store.rbacRoles.clear();
        store.notifications.clear();
        store.drivers.clear();
        store.merchantApplicants.clear();

        for (final idx in const [0, 3, 14]) {
          await pumpClean(
            CustomerSubsystemEntry(
              key: ValueKey('empty_cust_$idx'),
              forcedScreenIndex: idx,
            ),
            'EmptyCustomer[$idx]',
          );
        }
        await pumpClean(
          const DriverSubsystemEntry(
            key: ValueKey('empty_drv_6'),
            forcedScreenIndex: 6,
          ),
          'EmptyDriver[6]',
        );
        await pumpClean(
          const MerchantSubsystemEntry(
            key: ValueKey('empty_mer_5'),
            forcedScreenIndex: 5,
          ),
          'EmptyMerchant[5]',
        );
        for (final idx in const [0, 1, 2, 4, 8, 9, 10, 11]) {
          await pumpClean(
            AdminSubsystemEntry(
              key: ValueKey('empty_adm_$idx'),
              forcedScreenIndex: idx,
            ),
            'EmptyAdmin[$idx]',
          );
        }
      } finally {
        store.orders
          ..clear()
          ..addAll(bakOrders);
        store.vouchers
          ..clear()
          ..addAll(bakVouchers);
        store.geofenceZones
          ..clear()
          ..addAll(bakZones);
        store.rbacRoles
          ..clear()
          ..addAll(bakRoles);
        store.notifications
          ..clear()
          ..addAll(bakNotis);
        store.drivers
          ..clear()
          ..addAll(bakDrivers);
        store.merchantApplicants
          ..clear()
          ..addAll(bakMerchants);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'TC-22: Định vị GPS Phần cứng Thời gian thực (applyVerifiedDeviceGpsFix, Reset Kalman Liên Tỉnh, Chấm xanh GPS + Vòng sai số Web Mercator, Nút Định vị Thật & Zoom 5..19)',
    (WidgetTester tester) async {
      final store = AppStateStore.instance;
      final prevDriverLoc = store.activeDriverLocation;
      const realBienHoaFix = GeoPoint(
        latitude: 10.953299,
        longitude: 106.870323,
      );

      try {
        // 1. Khi nhận tín hiệu GPS thật cách xa tọa độ khởi tạo > 1.5km: Kalman tự động reset thay vì kéo ngược về Quận 1
        store.applyVerifiedDeviceGpsFix(
          rawPoint: realBienHoaFix,
          accuracyMeters: 250.0,
          speedKmh: 0.0,
          syncToActiveDriver: true,
        );
        store.liveDeviceAddress =
            'Phường Tân Hiệp, Thành phố Biên Hòa, Tỉnh Đồng Nai';

        expect(store.hasRealDeviceGpsFix, isTrue);
        expect(store.liveDeviceLocation!.latitude, closeTo(10.953299, 1e-6));
        expect(store.liveDeviceLocation!.longitude, closeTo(106.870323, 1e-6));
        expect(store.liveDeviceAccuracyMeters, equals(250.0));
        expect(store.activeDriverLocation.latitude, closeTo(10.953299, 1e-4));
        expect(store.activeDriverLocation.longitude, closeTo(106.870323, 1e-4));

        // Không chèn bản ghi rác 'NO_ORDER' vào bảng order_tracking_logs
        final trackingRows = await SqliteOfflineQueueDatasource.instance
            .queryRows('order_tracking_logs');
        expect(trackingRows.any((r) => r['order_id'] == 'NO_ORDER'), isFalse);

        // 2. Map3dPerspectiveWidget hiển thị nhãn GPS Thật, nút Định vị thật của tôi & hỗ trợ thu phóng sâu 5..19
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: CustomerSubsystemEntry(forcedScreenIndex: 0)),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('btn_map_my_real_gps')), findsWidgets);
        expect(
          find.textContaining('GPS Thật (10.9533, 106.8703 ±250m)'),
          findsWidgets,
        );
        expect(find.textContaining('Biên Hòa'), findsWidgets);

        // Kiểm tra màn hình Tạo đơn tự động nạp điểm lấy theo GPS thật của thiết bị
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: CustomerSubsystemEntry(forcedScreenIndex: 2)),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
        expect(find.text('Vị trí GPS thật của tôi'), findsWidgets);
      } finally {
        store.liveDeviceLocation = null;
        store.liveDeviceAccuracyMeters = null;
        store.liveDeviceAddress = '';
        store.activeDriverLocation = prevDriverLoc;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );
}

class _RealLoopbackHttpOverrides extends HttpOverrides {}
