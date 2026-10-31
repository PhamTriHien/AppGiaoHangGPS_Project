import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_session_lease.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_screen.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_view.dart';
import 'package:gps_delivery_app/presentation/widgets/market_product_details.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'market_operations_test.dart' show OperationsFixture;

class ConsistencyFixture extends OperationsFixture {
  final failures = <String, int>{};
  bool conflict = false, read = false;
  String delivery = 'delivered', kind = 'ready';
  int orderReads = 0;

  @override
  Map<String, dynamic> get order => {
    ...super.order,
    'delivery_status': delivery,
    if (delivery == 'inTransit') 'delivered_at': null,
    'reason': '',
  };

  void fail(String action) {
    final code = failures[action];
    if (code != null) {
      throw PublicApiException('Failed $action', statusCode: code);
    }
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    fail(path);
    final result = await super.request(path, body: body, query: query);
    if (path == 'addresses') result['addresses'][0]['version'] = 7;
    return result;
  }

  @override
  Future<Map<String, dynamic>> market(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    fail(action);
    if (action == 'cart_set' && conflict) {
      conflict = false;
      quantity = 3;
      version++;
      throw const PublicApiException('Giỏ hàng đã thay đổi', statusCode: 409);
    }
    if (action == 'orders') {
      orderReads++;
      return {
        'orders': [order],
      };
    }
    if (action == 'messages') {
      operations.add({'action': action, 'payload': payload});
      return {
        'messages': [
          {'body': 'Tin nhắn của đơn được chọn', 'actor_id': 'merchant'},
        ],
      };
    }
    if (action == 'notification_read') read = true;
    if (action == 'notifications' || action == 'notification_read') {
      return {
        'notifications': [
          {
            'id': 'notice-1',
            'order_id': order['id'],
            'kind': kind,
            'read_at': read ? '2026-10-30' : null,
          },
        ],
      };
    }
    return super.market(action, payload);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(ConsistencyFixture, CloudAccountSession)> setup(
    WidgetTester tester, {
    double width = 360,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    final api = ConsistencyFixture()..quantity = 1;
    final session = CloudAccountSession(service: api);
    await session.refresh();
    addTearDown(() async {
      session.dispose();
      await api.changes.close();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    return (api, session);
  }

  Future<void> show(
    WidgetTester tester,
    CloudAccountSession session,
    MarketView view,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarketplaceView(session: session, view: view),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'Cart conflict reloads actual quantities and removes quote at $width',
      (tester) async {
        final (api, session) = await setup(tester, width: width);
        await show(tester, session, MarketView.cart);
        await tester.ensureVisible(find.text('Cập nhật báo giá'));
        await tester.tap(find.text('Cập nhật báo giá'));
        await tester.pumpAndSettle();
        expect(find.text('Đặt mua'), findsOneWidget);
        final quote = api.calls.lastWhere(
          (c) => c['action'] == 'quote',
        )['payload'];
        expect(quote, {
          'address_id': 'home',
          'cart_version': 1,
          'address_version': 7,
        });
        api.conflict = true;
        await tester.ensureVisible(find.byTooltip('Tăng số lượng'));
        await tester.tap(find.byTooltip('Tăng số lượng'));
        await tester.pumpAndSettle();
        expect(find.text('3'), findsOneWidget);
        expect(find.text('Đặt mua'), findsNothing);
        expect(find.text('Giỏ hàng đã thay đổi'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'Address failure retains cart and prevents checkout at $width',
      (tester) async {
        final (api, session) = await setup(tester, width: width);
        api.failures['addresses'] = 503;
        await show(tester, session, MarketView.cart);
        expect(find.textContaining(api.product['name']), findsOneWidget);
        expect(find.text('Giỏ hàng đang trống.'), findsNothing);
        expect(
          find.text('Chưa tải được sổ địa chỉ. Vui lòng tải lại.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Cập nhật báo giá'),
              )
              .onPressed,
          isNull,
        );
        api.failures.clear();
        await tester.tap(find.byTooltip('Tải lại'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Cập nhật báo giá'),
              )
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    for (final kind in ['ready', 'message']) {
      testWidgets(
        'Notification $kind opens the matching private destination at $width',
        (tester) async {
          final (api, session) = await setup(tester, width: width);
          api.kind = kind;
          await show(tester, session, MarketView.notifications);
          await tester.tap(find.text('Đơn order-1'));
          await tester.pumpAndSettle();
          expect(api.read, isTrue);
          expect(
            find.text(
              kind == 'message' ? 'Trao đổi đơn hàng' : 'Dịch vụ đơn mua',
            ),
            findsOneWidget,
          );
          final action = kind == 'message' ? 'messages' : 'order_services';
          expect(
            api.operations.lastWhere(
              (c) => c['action'] == action,
            )['payload']['order_id'],
            'order-1',
          );
          expect(tester.takeException(), isNull);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.notifications_none), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final view in [
    MarketView.cart,
    MarketView.orders,
    MarketView.notifications,
    MarketView.workspace,
  ]) {
    testWidgets(
      'Initial ${view.name} outage never claims an empty successful result',
      (tester) async {
        final (api, session) = await setup(tester);
        final action = switch (view) {
          MarketView.cart => 'cart',
          MarketView.orders => 'orders',
          MarketView.notifications => 'notifications',
          _ => 'workspace',
        };
        api.failures[action] = 503;
        await show(tester, session, view);
        expect(
          find.text('Dịch vụ tạm thời chưa khả dụng. Vui lòng thử lại sau.'),
          findsOneWidget,
        );
        for (final label in [
          'Giỏ hàng đang trống.',
          'Chưa có đơn mua hàng.',
          'Chưa có thông báo.',
          'Tạo cửa hàng',
        ]) {
          expect(find.text(label), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'Failed filter reload removes products from the previous category',
    (tester) async {
      final (api, session) = await setup(tester);
      await show(tester, session, MarketView.catalog);
      expect(find.text(api.product['name']), findsOneWidget);
      api.failures['catalog'] = 503;
      await tester.tap(find.text('Tất cả'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đồ dùng').last);
      await tester.pumpAndSettle();
      expect(find.text(api.product['name']), findsNothing);
      expect(
        find.text('Dịch vụ tạm thời chưa khả dụng. Vui lòng thử lại sau.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'A stale quote reloads cart and addresses before consent can be given again',
    (tester) async {
      final (api, session) = await setup(tester);
      await show(tester, session, MarketView.cart);
      api.quantity = 4;
      api.version++;
      api.failures['quote'] = 409;
      await tester.ensureVisible(find.text('Cập nhật báo giá'));
      await tester.tap(find.text('Cập nhật báo giá'));
      await tester.pumpAndSettle();
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Đặt mua'), findsNothing);
      expect(find.text('Failed quote'), findsOneWidget);
      api.failures.clear();
      await tester.ensureVisible(find.text('Cập nhật báo giá'));
      await tester.tap(find.text('Cập nhật báo giá'));
      await tester.pumpAndSettle();
      expect(
        api.calls.lastWhere(
          (c) => c['action'] == 'quote',
        )['payload']['cart_version'],
        api.version,
      );
      expect(find.text('Đặt mua'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Revoked order access clears loaded aftersales details on 404', (
    tester,
  ) async {
    final (api, session) = await setup(tester);
    await show(tester, session, MarketView.orders);
    await tester.ensureVisible(find.text('Chi tiết và hậu mãi'));
    await tester.tap(find.text('Chi tiết và hậu mãi'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Trả hàng'), findsOneWidget);
    api.failures['order_services'] = 404;
    await tester.tap(find.byTooltip('Tải lại').last);
    await tester.pumpAndSettle();
    expect(find.text('Failed order_services'), findsOneWidget);
    expect(find.byTooltip('Trả hàng'), findsNothing);
    expect(find.text('Cửa hàng kiểm thử'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final status in [401, 403]) {
    testWidgets(
      'Business $status clears private state without an automatic retry loop',
      (tester) async {
        final (api, session) = await setup(tester);
        await tester.pumpWidget(
          MaterialApp(home: MarketplaceScreen(session: session)),
        );
        await tester.pumpAndSettle();
        expect(find.text(api.product['name']), findsOneWidget);
        final old = CloudSessionLease(session: session);
        addTearDown(old.dispose);
        api.failures['catalog'] = status;
        final profileCalls = api.calls
            .where((c) => c['path'] == 'profile')
            .length;
        await tester.tap(find.byTooltip('Tải lại trang chủ'));
        await tester.pumpAndSettle();
        expect(find.text(api.product['name']), findsNothing);
        expect(find.text('Chưa tải được tài khoản.'), findsOneWidget);
        expect(old.valid, isFalse);
        expect(
          api.calls.where((c) => c['path'] == 'profile').length,
          profileCalls,
        );
        api.failures.clear();
        await tester.tap(find.text('Thử lại'));
        await tester.pumpAndSettle();
        expect(find.text(api.product['name']), findsOneWidget);
        expect(old.valid, isFalse);
        // A late failure belonging to the old view cannot revoke the new session.
        expect(
          old.handleAccessFailure(
            PublicApiException('Late', statusCode: status),
          ),
          isFalse,
        );
        expect(session.verified, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'A product removed after loading no longer exposes stale choices or add action',
    (tester) async {
      final (api, session) = await setup(tester);
      final lease = CloudSessionLease(session: session);
      addTearDown(lease.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarketProductDetails(
              session: session,
              lease: lease,
              productId: api.product['id'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      api.failures['product_details'] = 404;
      await tester.tap(find.byTooltip('Yêu thích'));
      await tester.pumpAndSettle();
      expect(find.text(api.product['name']), findsNothing);
      expect(find.text('Failed product_details'), findsOneWidget);
      expect(find.text('Thêm vào giỏ'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final entry in {
    'delivered': 'Đã giao',
    'inTransit': 'Đang giao',
    'returned': 'Đã hoàn hàng',
  }.entries) {
    testWidgets(
      'Purchase displays shipping ${entry.key} and refreshes when returning from details',
      (tester) async {
        final (api, session) = await setup(tester);
        api.delivery = entry.key;
        await show(tester, session, MarketView.orders);
        expect(find.text(entry.value), findsOneWidget);
        expect(find.text('Đã bàn giao vận chuyển'), findsNothing);
        expect(find.text('Lý do: null'), findsNothing);
        final reads = api.orderReads;
        await tester.ensureVisible(find.text('Chi tiết và hậu mãi'));
        await tester.tap(find.text('Chi tiết và hậu mãi'));
        await tester.pumpAndSettle();
        api.delivery = 'returning';
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(api.orderReads, reads + 1);
        expect(find.text('Đang hoàn hàng'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
