import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_order_details_screen.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_orders_screen.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_order_form.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_session_boundary.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const detailsOrderId = '10000000-0000-0000-0000-000000000001';

Map<String, dynamic> detailsOrder() => {
  'id': detailsOrderId,
  'tracking_code': 'CL-PRIVATE',
  'status': 'searching',
  'version': 1,
  'owner_id': 'alice',
  'merchant_id': 'shop-current',
  'shipping_fee': 25000,
  'cod_amount': 100000,
  'payment_status': 'PAID',
  'created_at': '2026-10-29T00:00:00Z',
  'request_key': 'old-key',
  'details': {
    'pickup_address': '12 Private Pickup Street',
    'dropoff_address': '20 Private Dropoff Street',
    'pickup_lat': 10.77,
    'pickup_lng': 106.7,
    'dropoff_lat': 10.78,
    'dropoff_lng': 106.71,
    'recipient_name': 'Private Receiver',
    'recipient_phone': '0912345678',
    'package_description': 'Private documents',
    'weight_kg': 1,
    'service_type': 'express',
    'payment_method': 'recipient_cash',
    'shipping_fee': 1,
    'payment_status': 'PAID',
    'request_key': 'old-key',
  },
};

Map<String, dynamic> historyEvent(int version, String action, String status) =>
    {
      'order_id': detailsOrderId,
      'version': version,
      'action': action,
      'status': status,
      'created_at': '2026-10-29T00:00:0${version}Z',
      'reason': null,
    };

class DetailsFixture extends CloudOrdersService {
  String identity = 'alice', server = 'project-A', role = 'customer';
  bool operator = false, blocked = false, hasProfile = true;
  Object? historyFailure;
  Completer<Map<String, dynamic>>? pendingHistory;
  List<Map<String, dynamic>> history = [
    historyEvent(2, 'claim', 'accepted'),
    historyEvent(1, 'create', 'searching'),
  ];
  final calls = <Map<String, dynamic>>[];
  final changes = StreamController<AuthState>.broadcast();
  @override
  bool get signedIn => true;
  @override
  String get userId => identity;
  @override
  String get email => '$identity@example.com';
  @override
  String get project => server;
  @override
  Stream<AuthState> get authChanges => changes.stream;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body, 'query': query});
    if (path == 'profile') {
      return {
        'operator': operator,
        'schema_version': 2,
        'account': hasProfile
            ? {'user_id': identity, 'role': role, 'blocked': blocked}
            : null,
      };
    }
    if (path.endsWith('/history')) {
      if (historyFailure != null) throw historyFailure!;
      return pendingHistory?.future ?? Future.value({'history': history});
    }
    if (path == 'merchants') return {'merchants': []};
    if (path == 'orders') {
      return body == null
          ? {
              'orders': [detailsOrder()],
            }
          : {
              'order': {'id': 'new-order'},
            };
    }
    if (path == 'quote') {
      return {
        'shipping_fee': 31000,
        'pricing_version': 9,
        'distance_meters': 1200,
      };
    }
    return {};
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  (DetailsFixture, CloudAccountSession) setup() {
    final api = DetailsFixture();
    final session = CloudAccountSession(service: api);
    addTearDown(() async {
      session.dispose();
      await api.changes.close();
    });
    return (api, session);
  }

  Future<void> open(
    WidgetTester tester,
    CloudAccountSession session, {
    Map<String, dynamic>? order,
    bool operator = false,
    List<Map<String, dynamic>> merchants = const [],
  }) async {
    await session.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => CloudSessionBoundary(
                    session: session,
                    operator: operator,
                    builder: (_, lease) => CloudOrderDetailsScreen(
                      lease: lease,
                      order: order ?? detailsOrder(),
                      merchants: merchants,
                    ),
                  ),
                ),
              ),
              child: const Text('Open order'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open order'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
    }
  }

  Future<void> close(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  for (final width in [360.0, 1440.0]) {
    testWidgets('Private details and chronological history fit $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, session) = setup();
      await open(tester, session);
      expect(find.text('CL-PRIVATE'), findsOneWidget);
      expect(find.text('Private Receiver'), findsOneWidget);
      expect(find.text('Đã thanh toán cước'), findsOneWidget);
      await tester.ensureVisible(find.text('Lịch sử đơn hàng'));
      final first = tester.getTopLeft(find.text('Tạo đơn')).dy;
      final second = tester.getTopLeft(find.text('Nhận chuyến')).dy;
      expect(first, lessThan(second));
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  }

  testWidgets(
    'No cached details appear before server authorization or after 404; retry works',
    (tester) async {
      final (api, session) = setup();
      final pending = Completer<Map<String, dynamic>>();
      api.pendingHistory = pending;
      await open(tester, session);
      expect(find.text('CL-PRIVATE'), findsNothing);
      expect(find.text('Private Receiver'), findsNothing);
      expect(find.text('Gửi lại đơn'), findsNothing);
      pending.completeError(
        const PublicApiException('Not found', statusCode: 404),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Đơn hàng không còn khả dụng với tài khoản này.'),
        findsOneWidget,
      );
      expect(find.text('Private Receiver'), findsNothing);
      api.pendingHistory = null;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('Private Receiver'), findsOneWidget);
      await close(tester);
    },
  );

  for (final status in [401, 403]) {
    testWidgets('History rejection $status clears session permissions', (
      tester,
    ) async {
      final (api, session) = setup();
      api.historyFailure = PublicApiException('Denied', statusCode: status);
      await open(tester, session);
      expect(session.verified, isFalse);
      expect(find.text('Private Receiver'), findsNothing);
      expect(find.text('Gửi lại đơn'), findsNothing);
      await close(tester);
    });
  }

  testWidgets('Malformed or foreign-order history cannot reveal the snapshot', (
    tester,
  ) async {
    final (api, session) = setup();
    api.history = [
      {...historyEvent(1, 'create', 'searching'), 'order_id': 'another-order'},
    ];
    await open(tester, session);
    expect(find.text('Private Receiver'), findsNothing);
    expect(find.text('Thử lại'), findsOneWidget);
    api.history = [
      historyEvent(1, 'create', 'searching'),
      historyEvent(1, 'claim', 'accepted'),
    ];
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Private Receiver'), findsNothing);
    await close(tester);
  });

  for (final change in ['project', 'role', 'block', 'login']) {
    testWidgets('Late history after $change cannot restore private data', (
      tester,
    ) async {
      final (api, session) = setup();
      final pending = Completer<Map<String, dynamic>>();
      api.pendingHistory = pending;
      await open(tester, session);
      switch (change) {
        case 'project':
          api.server = 'project-B';
        case 'role':
          api.role = 'driver';
        case 'block':
          api.blocked = true;
        case 'login':
          api.changes.add(AuthState(AuthChangeEvent.signedIn, null));
      }
      await session.refresh();
      await tester.pumpAndSettle();
      pending.complete({'history': api.history});
      await tester.pumpAndSettle();
      expect(find.text('Private Receiver'), findsNothing);
      expect(find.text('Gửi lại đơn'), findsNothing);
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  }

  for (final role in ['driver', 'merchant', 'operator']) {
    testWidgets(
      '$role may read authorized orders without gaining creator actions',
      (tester) async {
        final (api, session) = setup();
        api.role = role == 'operator' ? 'customer' : role;
        api.operator = role == 'operator';
        api.hasProfile = role != 'operator';
        await open(
          tester,
          session,
          operator: api.operator,
          order: {...detailsOrder(), 'owner_id': 'other-owner'},
        );
        expect(find.text('Private Receiver'), findsOneWidget);
        expect(find.text('Gửi lại đơn'), findsNothing);
        await close(tester);
      },
    );
  }

  testWidgets(
    'Receipt copy separates shipping fee and COD and excludes internal secrets',
    (tester) async {
      final (_, session) = setup();
      String copied = '';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = call.arguments['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await open(tester, session);
      await tester.tap(find.byTooltip('Sao chép thông tin đơn'));
      await tester.pumpAndSettle();
      expect(copied, contains('Mã vận đơn: CL-PRIVATE'));
      expect(copied, contains('Cước vận chuyển: 25.000'));
      expect(copied, contains('Tiền thu hộ COD: 100.000'));
      expect(copied, isNot(contains('old-key')));
      expect(copied, isNot(contains('alice')));
      await close(tester);
    },
  );

  testWidgets(
    'Repeat prefill requires a new quote and submits no old payment/identity/version',
    (tester) async {
      final (api, session) = setup();
      await open(
        tester,
        session,
        merchants: [
          {'user_id': 'shop-current', 'full_name': 'Current shop'},
        ],
      );
      await tester.tap(find.text('Gửi lại đơn'));
      await tester.pumpAndSettle();
      expect(find.byType(CloudOrderForm), findsOneWidget);
      expect(find.text('12 Private Pickup Street'), findsOneWidget);
      expect(find.text('Xác nhận tạo đơn'), findsNothing);
      expect(
        api.calls.where((c) => c['path'] == 'orders' && c['body'] != null),
        isEmpty,
      );
      await tester.ensureVisible(find.text('Lấy báo giá'));
      await tester.tap(find.text('Lấy báo giá'));
      await tester.pumpAndSettle();
      expect(find.textContaining('31.000'), findsOneWidget);
      await tester.ensureVisible(find.text('Xác nhận tạo đơn'));
      await tester.tap(find.text('Xác nhận tạo đơn'));
      await tester.pumpAndSettle();
      expect(find.text('Open order'), findsOneWidget);
      final body =
          api.calls.lastWhere((c) => c['path'] == 'orders')['body'] as Map;
      expect(body['expected_fee'], 31000);
      expect(body['pricing_version'], 9);
      expect(body['request_key'], isNot('old-key'));
      expect(body['draft_id'], isNotEmpty);
      expect(body.containsKey('payment_status'), isFalse);
      final details = body['details'] as Map;
      expect(details['merchant_id'], 'shop-current');
      expect(details['cod_amount'], 100000);
      expect(details['service_type'], 'express');
      expect(details['payment_method'], 'recipient_cash');
      expect(details.keys, isNot(contains('shipping_fee')));
      expect(details.keys, isNot(contains('payment_status')));
      expect(details.keys, isNot(contains('request_key')));
      expect(details.keys, isNot(contains('owner_id')));
      await close(tester);
    },
  );

  testWidgets(
    'Repeat does not keep a merchant absent from the current choices',
    (tester) async {
      final (api, session) = setup();
      await open(tester, session);
      await tester.tap(find.text('Gửi lại đơn'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lấy báo giá'));
      await tester.tap(find.text('Lấy báo giá'));
      await tester.pumpAndSettle();
      final details =
          api.calls.lastWhere((c) => c['path'] == 'quote')['body'] as Map;
      expect(details.containsKey('merchant_id'), isFalse);
      await close(tester);
    },
  );

  testWidgets(
    'Invalidating the details route also removes its open repeat form',
    (tester) async {
      final (_, session) = setup();
      await open(tester, session);
      await tester.tap(find.text('Gửi lại đơn'));
      await tester.pumpAndSettle();
      expect(find.text('Private Receiver'), findsOneWidget);
      session.invalidateVerification();
      await tester.pumpAndSettle();
      expect(find.byType(CloudOrderForm), findsNothing);
      expect(find.text('Private Receiver'), findsNothing);
      await close(tester);
    },
  );

  testWidgets(
    'Orders list opens the canonical detail route and reloads on return',
    (tester) async {
      final (api, session) = setup();
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(session: session)),
      );
      await tester.pumpAndSettle();
      final reads = api.calls.where((c) => c['path'] == 'orders').length;
      await tester.tap(find.text('Chi tiết'));
      await tester.pumpAndSettle();
      expect(find.byType(CloudOrderDetailsScreen), findsOneWidget);
      expect(
        api.calls.any((c) => c['path'] == 'orders/$detailsOrderId/history'),
        isTrue,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        api.calls.where((c) => c['path'] == 'orders').length,
        greaterThan(reads),
      );
      await close(tester);
    },
  );
}
