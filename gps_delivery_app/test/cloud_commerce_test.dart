import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/core/utils/security_and_barcode_utils.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_commerce_dialog.dart';
import 'package:gps_delivery_app/presentation/widgets/vietqr_bank_payment_panel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommerceFixture extends CloudOrdersService {
  final changes = StreamController<AuthState>.broadcast();
  final calls = <Map<String, dynamic>>[];
  String identity = 'owner';
  bool configured = true;
  bool fail = false;
  Map<String, dynamic>? record;
  Completer<Map<String, dynamic>>? pending;
  @override
  bool get signedIn => true;
  @override
  String get userId => identity;
  @override
  Stream<AuthState> get authChanges => changes.stream;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body});
    if (pending != null) {
      final response = pending!;
      pending = null;
      return response.future;
    }
    if (fail) {
      throw const PublicApiException(
        'Backend chưa đủ cấu hình.',
        statusCode: 503,
      );
    }
    if (path.endsWith('/preview')) {
      return {'quote_id': 'quote-one', 'total_fee': 28000};
    }
    final shipment = path.contains('/shipment');
    if (body != null && !path.endsWith('/refresh')) {
      record = shipment
          ? {'ghn_order_code': 'GHN123', 'status': 'ready_to_pick'}
          : {'status': 'PENDING', 'amount': 30000};
    } else if (body != null && !shipment) {
      record = {'status': 'PAID', 'amount': 30000};
    }
    return {
      'configured': configured,
      shipment ? 'shipment' : 'payment': record,
    };
  }
}

const commerceOrder = {
  'id': 'order-one',
  'tracking_code': 'CL-12345678901234567890123456789012',
  'owner_id': 'owner',
  'status': 'searching',
  'payment_status': 'UNPAID',
  'shipping_fee': 30000,
  'cod_amount': 120000,
  'details': {
    'payment_method': 'sender_cash',
    'pickup_address': '12 Nguyen Hue',
    'dropoff_address': '20 Le Loi',
  },
};

void main() {
  Future<void> open(
    WidgetTester tester,
    CommerceFixture api, {
    bool shipment = false,
    bool operator = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CloudCommerceDialog(
                  service: api,
                  order: commerceOrder,
                  shipment: shipment,
                  operator: operator,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final width in [360.0, 1440.0]) {
    testWidgets('Commerce unavailable and pending/paid states fit $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = CommerceFixture()..configured = false;
      addTearDown(api.changes.close);
      await open(tester, api);
      expect(find.text('Tạo liên kết payOS'), findsNothing);
      expect(
        find.text('Dịch vụ chưa được bật hoặc chưa đủ cấu hình.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      api.configured = true;
      api.record = {
        'status': 'PENDING',
        'amount': 30000,
        'checkout_url': 'https://pay.payos.vn/web/test-link',
      };
      await tester.tap(find.byTooltip('Tải lại'));
      await tester.pumpAndSettle();
      expect(find.text('Chờ thanh toán'), findsOneWidget);
      expect(find.text('Tạo liên kết payOS'), findsNothing);
      expect(find.text('Xác nhận đã thanh toán'), findsNothing);
      await tester.tap(find.byTooltip('Tải lại'));
      await tester.pumpAndSettle();
      expect(api.calls.last['path'], 'orders/order-one/payment/refresh');
      expect(api.calls.last['body'], isEmpty);
      expect(find.text('Đã thanh toán'), findsOneWidget);
      expect(find.text('Hủy liên kết'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Backend errors do not enable payment creation', (tester) async {
    final api = CommerceFixture()..fail = true;
    addTearDown(api.changes.close);
    await open(tester, api);
    expect(find.text('Backend chưa đủ cấu hình.'), findsOneWidget);
    expect(find.text('Tạo liên kết payOS'), findsNothing);
    expect(api.calls, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Changing accounts discards stale commerce responses and private input',
    (tester) async {
      final delayed = Completer<Map<String, dynamic>>();
      final api = CommerceFixture()..pending = delayed;
      addTearDown(api.changes.close);
      await tester.pumpWidget(
        MaterialApp(
          home: CloudCommerceDialog(service: api, order: commerceOrder),
        ),
      );
      await tester.pump();
      api.identity = 'another-account';
      api.changes.add(AuthState(AuthChangeEvent.signedIn, null));
      await tester.pump();
      delayed.complete({
        'configured': true,
        'payment': {'status': 'PAID', 'amount': 30000},
      });
      await tester.pumpAndSettle();
      expect(
        find.text('Tài khoản đã thay đổi. Đóng cửa sổ và mở lại.'),
        findsOneWidget,
      );
      expect(find.text('Đã thanh toán'), findsNothing);
      expect(find.text('Tạo liên kết payOS'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'GHN quote invalidates on editing and shipment requires confirmation at 360px',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = CommerceFixture();
      addTearDown(api.changes.close);
      await open(tester, api, shipment: true, operator: true);
      expect(tester.takeException(), isNull);
      final field = find.widgetWithText(TextField, 'Chiều cao');
      await tester.ensureVisible(field);
      await tester.enterText(field, '10');
      await tester.ensureVisible(find.text('Xem phí GHN'));
      await tester.tap(find.text('Xem phí GHN'));
      await tester.pumpAndSettle();
      expect(find.text('Tạo vận đơn GHN'), findsOneWidget);
      expect(api.calls.last['path'], 'orders/order-one/shipment/preview');
      await tester.ensureVisible(field);
      await tester.enterText(field, '15');
      await tester.pump();
      expect(find.text('Tạo vận đơn GHN'), findsNothing);
      await tester.ensureVisible(find.text('Xem phí GHN'));
      await tester.tap(find.text('Xem phí GHN'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tạo vận đơn GHN'));
      await tester.tap(find.text('Tạo vận đơn GHN'));
      await tester.pumpAndSettle();
      expect(find.text('Tạo vận đơn GHN?'), findsOneWidget);
      expect(
        api.calls.where(
          (c) => c['path'] == 'orders/order-one/shipment' && c['body'] != null,
        ),
        isEmpty,
      );
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(api.calls.last['body'], {'quote_id': 'quote-one'});
      expect(find.text('GHN: GHN123'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Pending payOS dialog renders provider order code and auto-refreshes on app resume',
    (tester) async {
      final api = CommerceFixture()
        ..record = {
          'status': 'PENDING',
          'amount': 24950,
          'provider_order_code': 90012345,
          'checkout_url': 'https://pay.payos.vn/web/live-test',
        };
      addTearDown(api.changes.close);
      await open(tester, api);
      expect(find.text('Mã giao dịch payOS: 90012345'), findsOneWidget);
      expect(find.text('Kiểm tra thanh toán'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(api.calls.last['path'], 'orders/order-one/payment/refresh');
      expect(find.text('Đã thanh toán'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'VietQR Bank payment panel renders scannable EMVCo QR, bank selector and copy actions at 360px',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final customPayload = SecurityAndBarcodeUtils.generateEmvVietQrPayload(
        orderCode: 'GHST CL1234567890',
        amountVnd: 45000,
        bankBin: '970422',
        accountNumber: '0987654321',
      );
      expect(customPayload, startsWith('000201010212'));
      expect(customPayload, contains('970422'));
      expect(customPayload, contains('0987654321'));
      expect(customPayload.length, greaterThan(106));
      expect(RegExp(r'6304[0-9A-F]{4}$').hasMatch(customPayload), isTrue);

      final api = CommerceFixture()
        ..configured = true
        ..record = {
          'status': 'PENDING',
          'amount': 30000,
          'provider_order_code': '987654321',
          'qr_code': customPayload,
        };
      addTearDown(api.changes.close);
      await open(tester, api);

      expect(find.byType(VietQrBankPaymentPanel), findsOneWidget);
      expect(
        find.byKey(const ValueKey('vietqr-matrix-widget')),
        findsOneWidget,
      );
      expect(
        find.text('Chuyển khoản ngân hàng & Quét mã VietQR'),
        findsOneWidget,
      );
      expect(find.text('Mã QR đối soát tự động · NAPAS 247'), findsOneWidget);
      expect(find.text('GHST 987654321'), findsOneWidget);
      expect(find.text('Xác nhận đã thanh toán'), findsNothing);

      await tester.ensureVisible(find.byTooltip('Sao chép số tài khoản'));
      await tester.tap(find.byTooltip('Sao chép số tài khoản'));
      await tester.pump();
      expect(find.text('Đã sao chép số tài khoản'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
