import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/utils/currency_formatter.dart';
import 'package:gps_delivery_app/data/datasources/local/app_state_store.dart';
import 'package:gps_delivery_app/data/datasources/local/sqlite_offline_queue_datasource.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/domain/enums/order_status.dart';
import 'package:gps_delivery_app/domain/enums/service_type.dart';
import 'package:gps_delivery_app/presentation/customer/customer_subsystem_views.dart';

import 'fixtures/app_state_test_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppStateStore.instance;
  final db = SqliteOfflineQueueDatasource.instance;

  setUpAll(() async {
    SqliteOfflineQueueDatasource.ensureDesktopFfiInitialized();
    await store.initializeDatabase();
  });

  setUp(() async {
    store.seedTestRecords();
    store.applyAuthenticatedUserSession(store.findUserByPhone('0912345678')!);
    await db.deleteRows(
      'local_relational_entities',
      where: 'table_name = ?',
      whereArgs: ['customer_order_drafts'],
    );
  });

  ActiveOrderRecord order(String code, OrderStatus status, {int daysAgo = 0}) {
    return ActiveOrderRecord(
      id: code,
      trackingCode: code,
      customerName: store.customerFullName,
      recipientName: 'Người nhận $code',
      recipientPhone: '0901234567',
      pickupAddress: 'Điểm lấy hàng đã lưu',
      dropoffAddress: 'Điểm giao cuối đã lưu',
      pickupLocation: const GeoPoint(latitude: 10.78, longitude: 106.70),
      dropoffLocation: const GeoPoint(latitude: 10.80, longitude: 106.73),
      serviceType: DeliveryServiceType.standard,
      packageDescription:
          'Tài liệu & Hợp đồng - Giữ nguyên tài liệu [Hẹn giờ: 09:00 - 11:00]',
      weightKg: 1.25,
      dimensionsCm: '20 x 15 x 10 cm',
      distanceMeters: 99999,
      durationSeconds: 9999,
      deliveryFee: 25000,
      surchargeFee: 5000,
      discountAmount: 2000,
      codAmount: 300000,
      totalAmount: 28000,
      paymentMethod: 'Người nhận trả phí',
      paymentStatus: 'UNPAID',
      status: status,
      createdDateLabel: 'Hôm nay',
      createdAtMs: DateTime.now()
          .subtract(Duration(days: daysAgo))
          .millisecondsSinceEpoch,
    );
  }

  Future<void> io(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, int screen, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CustomerSubsystemEntry(forcedScreenIndex: screen)),
      ),
    );
    await io(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  test(
    'Drafts persist independent snapshots and enforce account ownership',
    () async {
      final fields = <String, dynamic>{
        'recipientName': 'Người nhận A',
        'stops': [
          {'address': 'Điểm phụ A'},
        ],
      };
      final pending = store.saveCustomerOrderDraft(
        draftId: 'shared-id',
        fields: fields,
      );
      (fields['stops'] as List).first['address'] = 'Changed after save';
      await pending;
      expect(
        ((await store.customerOrderDrafts()).single['fields']['stops'] as List)
            .first['address'],
        'Điểm phụ A',
      );
      store.applyAuthenticatedUserSession(store.findUserByPhone('0909112233')!);
      expect(await store.customerOrderDrafts(), isEmpty);
      await store.deleteCustomerOrderDraft('shared-id');
      await store.saveCustomerOrderDraft(
        draftId: 'shared-id',
        fields: {'recipientName': 'Người nhận B'},
      );
      store.applyAuthenticatedUserSession(store.findUserByPhone('0912345678')!);
      expect(
        (await store.customerOrderDrafts()).single['fields']['recipientName'],
        'Người nhận A',
      );
      await store.saveCustomerOrderDraft(
        draftId: 'shared-id',
        fields: {'recipientName': 'A updated'},
      );
      expect((await store.customerOrderDrafts()).length, 1);
      expect(
        (await store.customerOrderDrafts()).single['fields']['recipientName'],
        'A updated',
      );
      await store.deleteCustomerOrderDraft('shared-id');
      expect(await store.customerOrderDrafts(), isEmpty);
      store.applyAuthenticatedUserSession(store.findUserByPhone('0909112233')!);
      expect(
        (await store.customerOrderDrafts()).single['fields']['recipientName'],
        'Người nhận B',
      );
      store.clearAuthenticatedSession();
      expect(await store.customerOrderDrafts(), isEmpty);
      await expectLater(
        store.saveCustomerOrderDraft(fields: {}),
        throwsStateError,
      );
    },
  );

  testWidgets('Drafts restore on mobile and clear the form on account change', (
    tester,
  ) async {
    await store.saveCustomerOrderDraft(
      fields: {
        'pickup': 'Địa chỉ lấy đã lưu',
        'dropoff': 'Địa chỉ giao đã lưu',
        'recipientName': 'Người nhận riêng A',
        'recipientPhone': '0901234567',
        'pickupPoint': {'latitude': 10.78, 'longitude': 106.70},
        'dropoffPoint': {'latitude': 10.80, 'longitude': 106.73},
        'stops': [
          {'address': 'Điểm phụ riêng A', 'recipientName': 'Người nhận phụ'},
        ],
      },
    );
    await open(tester, 14, const Size(360, 800));
    expect(find.text('Người nhận riêng A'), findsOneWidget);
    await tester.tap(find.text('Người nhận riêng A'));
    await io(tester);
    expect(
      tester.widget<TextField>(field('Họ tên người nhận')).controller!.text,
      'Người nhận riêng A',
    );
    expect(find.text('Điểm phụ riêng A'), findsOneWidget);
    store.applyAuthenticatedUserSession(store.findUserByPhone('0909112233')!);
    await tester.pump();
    expect(
      tester.widget<TextField>(field('Họ tên người nhận')).controller!.text,
      isEmpty,
    );
    expect(find.text('Điểm phụ riêng A'), findsNothing);
    await tester.ensureVisible(find.byTooltip('Mở đơn nháp'));
    await tester.tap(find.byTooltip('Mở đơn nháp'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(find.text('Chưa có đơn nháp.'), findsOneWidget);
    expect(find.text('Người nhận riêng A'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'History separates failures, cancellations and returns, searches phones and filters dates',
    (tester) async {
      final cancelled = order('CANCELLED-1', OrderStatus.cancelled);
      final failed = order('FAILED-1', OrderStatus.failed);
      final returned = order('RETURNED-1', OrderStatus.delivered)
        ..paymentStatus = 'RETURNED';
      final old = order('OLD-1', OrderStatus.delivered, daysAgo: 100);
      store.orders
        ..clear()
        ..addAll([cancelled, failed, returned, old]);
      await open(tester, 7, const Size(1440, 1024));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Đã hủy'));
      await tester.pump();
      expect(find.text('CANCELLED-1'), findsOneWidget);
      expect(find.text('FAILED-1'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Thất bại'));
      await tester.pump();
      expect(find.text('FAILED-1'), findsOneWidget);
      expect(find.text('CANCELLED-1'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Chuyển hoàn'));
      await tester.pump();
      expect(find.text('RETURNED-1'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tất cả'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '0901234567');
      await tester.pump();
      expect(find.text('OLD-1'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pump();
      await tester.tap(find.text('7 ngày qua').last);
      await tester.pump();
      expect(find.text('OLD-1'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'no-match');
      await tester.pump();
      expect(
        find.text('Không có đơn hàng phù hợp với bộ lọc hiện tại.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Đặt lại bộ lọc'));
      await tester.pump();
      expect(find.text('OLD-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Details show actual shipping and COD separately without fabricated POD or OTP',
    (tester) async {
      store.orders
        ..clear()
        ..add(order('DETAILS-1', OrderStatus.delivered));
      await open(tester, 7, const Size(360, 800));
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Chi tiết'));
      await tester.tap(find.widgetWithText(TextButton, 'Chi tiết'));
      await io(tester);
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('Tổng cước vận chuyển'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(CurrencyFormatter.formatVnd(28000)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(CurrencyFormatter.formatVnd(300000)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(
            'Chưa có bằng chứng giao hàng được lưu cho đơn này.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('OTP')),
        findsNothing,
      );
      expect(find.textContaining('POD: Đã ký nhận'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Đóng'));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Repeat preserves all delivery stops and resets old schedule and draft association',
    (tester) async {
      final original = order('REPEAT-1', OrderStatus.delivered);
      store.orders
        ..clear()
        ..add(original);
      await store.saveOrderStops(
        orderId: original.id,
        stops: [
          {'stopType': 'PICKUP', 'address': original.pickupAddress},
          {
            'address': 'Điểm giao đầu',
            'recipientName': 'Người nhận đầu',
            'recipientPhone': '0901111111',
            'latitude': 10.79,
            'longitude': 106.71,
          },
          {
            'address': 'Điểm giao phụ',
            'recipientName': 'Người nhận phụ',
            'recipientPhone': '0902222222',
            'latitude': 10.80,
            'longitude': 106.73,
          },
        ],
      );
      await store.scheduleOrder(
        orderId: original.id,
        scheduledAt: DateTime.now().add(const Duration(days: 1)),
      );
      await open(tester, 7, const Size(1440, 1024));
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Đặt lại'));
      await tester.tap(find.widgetWithText(TextButton, 'Đặt lại'));
      await io(tester);
      expect(
        tester.widget<TextField>(field('Họ tên người nhận')).controller!.text,
        'Người nhận đầu',
      );
      expect(find.text('Điểm giao phụ'), findsOneWidget);
      expect(
        tester.widget<TextField>(field('Trọng lượng (kg)')).controller!.text,
        '1.25',
      );
      expect(
        tester
            .widget<TextField>(field('Ghi chú cho tài xế khi lấy/giao'))
            .controller!
            .text,
        'Giữ nguyên tài liệu',
      );
      await tester.ensureVisible(find.byTooltip('Lưu đơn nháp'));
      await tester.tap(find.byTooltip('Lưu đơn nháp'));
      await io(tester);
      final drafts = await tester.runAsync(store.customerOrderDrafts);
      final saved = drafts!.single['fields'] as Map;
      expect(saved['scheduled'], isFalse);
      expect(saved['payer'], 'Người nhận trả phí');
      expect(saved['dropoff'], 'Điểm giao đầu');
      expect((saved['stops'] as List).single['recipientPhone'], '0902222222');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
