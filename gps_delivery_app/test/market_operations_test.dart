import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_session_lease.dart';
import 'package:gps_delivery_app/presentation/screens/market_order_services_screen.dart';
import 'package:gps_delivery_app/presentation/screens/shared_tracking_screen.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_session_boundary.dart';
import 'package:gps_delivery_app/presentation/widgets/market_product_details.dart';

import 'marketplace_test.dart' show MarketFixture;

class OperationsFixture extends MarketFixture {
  bool operator = false, favorite = false;
  Completer<Map<String, dynamic>>? services;
  final operations = <Map<String, dynamic>>[];
  Map<String, dynamic> get order => {
    'id': 'order-1',
    'owner_id': 'buyer',
    'merchant_id': 'merchant',
    'delivered_at': '2026-10-29T00:00:00Z',
    'state': 'ready',
    'snapshot': {
      'shop_name': 'Cửa hàng kiểm thử',
      'subtotal': 100000,
      'shipping_fee': 25000,
      'items': [
        {
          'product_id': product['id'],
          'name': product['name'],
          'quantity': 2,
          'unit_price': 50000,
        },
      ],
    },
  };
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == 'profile') {
      return {
        ...await super.request(path, body: body, query: query),
        'operator': operator,
      };
    }
    if (path.startsWith('marketplace/')) {
      return market(path.split('/').last, body ?? {});
    }
    return super.request(path, body: body, query: query);
  }

  @override
  Future<Map<String, dynamic>> market(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    operations.add({'action': action, 'payload': payload});
    if (action == 'operations') {
      return {
        'finance': [
          {
            'id': payload.containsKey('before')
                ? 'second-request'
                : 'first-request',
            'order_id': 'order-1',
            'kind': 'refund',
            'amount': 10000,
            'state': 'requested',
            'version': 1,
            'reason': payload.containsKey('before')
                ? 'Yêu cầu cũ hơn'
                : 'Yêu cầu mới nhất',
            'proposer': 'other',
          },
        ],
        'returns': [],
        'jobs': {'pending': 0, 'failed': 0, 'overdue': 0},
        'failed_jobs': [],
        'next': payload.containsKey('before')
            ? null
            : {'before': '2026-10-29', 'before_id': 'first-request'},
      };
    }
    if (action == 'order_services') {
      if (services != null) return services!.future;
      return {
        'order': order,
        'collected': 125000,
        'refunded': 0,
        'settled': 0,
        'returns': [],
        'reviews': [],
        'shares': [],
        'finance': [
          {
            'id': 'finance-1',
            'order_id': 'order-1',
            'kind': 'collection',
            'amount': 125000,
            'state': 'requested',
            'proposer': id,
            'version': 1,
          },
        ],
      };
    }
    if (action == 'product_details') {
      return {
        'product': product,
        'favorite': favorite,
        'reviews': [
          {'rating': 4, 'body': 'Đã nhận đúng sản phẩm'},
        ],
      };
    }
    if (action == 'favorite_set') {
      favorite = payload['enabled'] == true;
      return {};
    }
    if ([
      'return_request',
      'review_save',
      'finance_action',
      'finance_request',
    ].contains(action)) {
      return {};
    }
    return super.market(action, payload);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> tick(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
  }

  Future<(OperationsFixture, CloudAccountSession)> setup(
    WidgetTester t, {
    double width = 360,
    bool operator = false,
  }) async {
    t.view.physicalSize = Size(width, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    final api = OperationsFixture()..operator = operator;
    final session = CloudAccountSession(service: api)..start();
    await session.refresh();
    addTearDown(() async {
      session.dispose();
      await api.changes.close();
    });
    return (api, session);
  }

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'Item return/review form validates and sends only real order references at $width',
      (t) async {
        final (api, session) = await setup(t, width: width);
        final lease = CloudSessionLease(session: session);
        addTearDown(lease.dispose);
        await t.pumpWidget(
          MaterialApp(
            home: MarketOrderServicesScreen(
              session: session,
              lease: lease,
              orderId: 'order-1',
            ),
          ),
        );
        await tick(t);
        expect(find.text('Dịch vụ đơn mua'), findsOneWidget);
        await t.ensureVisible(find.byTooltip('Trả hàng'));
        await t.tap(find.byTooltip('Trả hàng'));
        await tick(t);
        await t.tap(find.text('Xác nhận'));
        await tick(t);
        expect(find.text('Nhập ít nhất 3 ký tự'), findsOneWidget);
        await t.enterText(
          find.widgetWithText(TextFormField, 'Lý do'),
          'Sản phẩm bị hỏng',
        );
        await t.tap(find.text('Xác nhận'));
        await tick(t);
        final sent =
            api.operations.singleWhere(
                  (e) => e['action'] == 'return_request',
                )['payload']
                as Map;
        expect(sent['quantity'], 1);
        expect(sent['order_id'], 'order-1');
        expect(sent['product_id'], api.product['id']);
        expect(sent['request_key'], isNotEmpty);
        expect(sent.containsKey('price'), false);
        await t.ensureVisible(find.byTooltip('Đánh giá'));
        await t.tap(find.byTooltip('Đánh giá'));
        await tick(t);
        await t.tap(find.byTooltip('4 sao'));
        await t.enterText(
          find.widgetWithText(TextField, 'Nhận xét'),
          'Sản phẩm đúng mô tả',
        );
        await t.tap(find.text('Gửi đánh giá'));
        await tick(t);
        expect(
          api.operations.singleWhere(
            (e) => e['action'] == 'review_save',
          )['payload']['rating'],
          4,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 2));
      },
    );
  }
  testWidgets(
    'Invalidated account removes private data and drops late services response',
    (t) async {
      final (api, session) = await setup(t);
      api.services = Completer<Map<String, dynamic>>();
      await t.pumpWidget(
        MaterialApp(
          home: CloudSessionBoundary(
            session: session,
            builder: (_, lease) => MarketOrderServicesScreen(
              session: session,
              lease: lease,
              orderId: 'order-1',
            ),
          ),
        ),
      );
      await tick(t);
      await api.signOut();
      await tick(t);
      api.services!.complete({
        'order': api.order,
        'collected': 125000,
        'returns': [],
        'finance': [],
      });
      await tick(t);
      expect(find.text('Cửa hàng kiểm thử'), findsNothing);
      expect(find.textContaining('125.000'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Operator UI never offers self-approval', (t) async {
    final (_, session) = await setup(t, operator: true);
    final lease = CloudSessionLease(session: session, operator: true);
    addTearDown(lease.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: MarketOrderServicesScreen(
          session: session,
          lease: lease,
          orderId: 'order-1',
          operator: true,
        ),
      ),
    );
    await tick(t);
    expect(find.text('Duyệt'), findsNothing);
    expect(find.text('Xác nhận thu/chi'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Operator pagination retains prior entries and passes the server cursor',
    (t) async {
      final (api, session) = await setup(t, operator: true);
      final lease = CloudSessionLease(session: session, operator: true);
      addTearDown(lease.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: MarketOrderServicesScreen(
            session: session,
            lease: lease,
            operator: true,
          ),
        ),
      );
      await tick(t);
      expect(find.text('Yêu cầu mới nhất'), findsOneWidget);
      await t.ensureVisible(find.text('Giao dịch cũ hơn'));
      await t.tap(find.text('Giao dịch cũ hơn'));
      await tick(t);
      expect(find.text('Yêu cầu mới nhất'), findsOneWidget);
      expect(find.text('Yêu cầu cũ hơn'), findsOneWidget);
      final sent =
          api.operations
                  .where((e) => e['action'] == 'operations')
                  .last['payload']
              as Map;
      expect(sent['before'], '2026-10-29');
      expect(sent['before_id'], 'first-request');
      expect(find.text('Giao dịch cũ hơn'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Ordinary accounts cannot mount an operator workspace or load its data',
    (t) async {
      final (api, session) = await setup(t);
      await t.pumpWidget(
        MaterialApp(
          home: CloudSessionBoundary(
            session: session,
            operator: true,
            builder: (_, lease) => MarketOrderServicesScreen(
              session: session,
              lease: lease,
              operator: true,
            ),
          ),
        ),
      );
      await tick(t);
      expect(api.operations.where((e) => e['action'] == 'operations'), isEmpty);
      expect(find.text('Yêu cầu mới nhất'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Product reviews/favorite state come from service and clear after invalidation',
    (t) async {
      final (api, session) = await setup(t);
      final lease = CloudSessionLease(session: session);
      addTearDown(lease.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarketProductDetails(
              session: session,
              lease: lease,
              productId: api.product['id'] as String,
            ),
          ),
        ),
      );
      await tick(t);
      expect(find.text('Đã nhận đúng sản phẩm'), findsOneWidget);
      await t.tap(find.byTooltip('Yêu thích'));
      await tick(t);
      expect(api.favorite, true);
      expect(find.byTooltip('Bỏ yêu thích'), findsOneWidget);
      await api.signOut();
      await tick(t);
      expect(find.text('Đã nhận đúng sản phẩm'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Public tracking clears old result on failure and never renders private response keys',
    (t) async {
      var calls = 0;
      await t.pumpWidget(
        MaterialApp(
          home: SharedTrackingScreen(
            lookup: (token) async {
              calls++;
              if (calls > 1) throw StateError('expired');
              return {
                'shop_name': 'Shop công khai',
                'state': 'ready',
                'delivery_status': 'delivered',
                'updated_at': '2026-10-29',
                'expires_at': '2026-10-30',
                'phone': 'PRIVATE_PHONE',
                'address': 'PRIVATE_ADDRESS',
              };
            },
          ),
        ),
      );
      await t.enterText(find.byType(TextField), 'a' * 64);
      await t.tap(find.text('Tra cứu'));
      await tick(t);
      expect(find.text('Đã giao hàng'), findsOneWidget);
      expect(find.textContaining('PRIVATE_'), findsNothing);
      await t.tap(find.text('Tra cứu'));
      await tick(t);
      expect(find.text('Shop công khai'), findsNothing);
      expect(find.textContaining('hết hạn'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'bad');
      await t.tap(find.text('Tra cứu'));
      await tick(t);
      expect(calls, 2);
      expect(t.takeException(), isNull);
    },
  );
}
