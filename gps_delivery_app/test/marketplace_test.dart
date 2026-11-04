import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/main.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_screen.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_view.dart';

class MarketFixture extends CloudOrdersService {
  bool authenticated = true, blocked = false;
  String id = 'buyer', role = 'customer', server = 'project-A';
  int version = 1, quantity = 0, submissions = 0;
  bool failCheckout = false;
  Completer<Map<String, dynamic>>? pending;
  final changes = StreamController<AuthState>.broadcast();
  final calls = <Map<String, dynamic>>[];
  @override
  bool get signedIn => authenticated;
  @override
  String get userId => authenticated ? id : '';
  @override
  String get email => 'account@example.com';
  @override
  String get project => server;
  @override
  String get identityScope => '$server:$userId';
  @override
  Stream<AuthState> get authChanges => changes.stream;
  @override
  Future<String?> authenticate(
    String email,
    String password, {
    bool register = false,
  }) async {
    calls.add({'action': 'authenticate', 'register': register});
    if (register) {
      return 'Kiểm tra email để xác nhận tài khoản rồi đăng nhập.';
    }
    authenticated = true;
    changes.add(const AuthState(AuthChangeEvent.signedIn, null));
    return null;
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    calls.add({'action': 'reset'});
  }

  @override
  Future<void> signOut() async {
    authenticated = false;
    changes.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  Map<String, dynamic> get product => {
    'id': '10000000-0000-0000-0000-000000000001',
    'shop_id': '20000000-0000-0000-0000-000000000001',
    'name': 'Hộp thực phẩm bảo quản lạnh',
    'description': 'Thông tin sản phẩm thật từ cửa hàng',
    'shop_name': 'Cửa hàng thực phẩm',
    'sku': 'BOX-01',
    'category': 'Thực phẩm',
    'image_url': '',
    'price': 50000,
    'stock': 5,
    'published': true,
    'quantity': quantity,
    'shop_status': 'active',
    'paused': false,
  };
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body});
    if (path == 'profile') {
      return {
        'operator': false,
        'schema_version': 2,
        'account': {
          'user_id': id,
          'full_name': 'Người mua',
          'phone': '0901234567',
          'role': role,
          'blocked': blocked,
          'requested_role': null,
        },
      };
    }
    if (path == 'addresses') {
      return {
        'addresses': [
          {
            'id': 'home',
            'label': 'Nhà',
            'full_address': '12 Đường Nguyễn Huệ',
            'is_default': true,
          },
        ],
      };
    }
    if (path == 'marketplace/checkout') {
      submissions++;
      if (failCheckout) {
        throw const PublicApiException('Mất kết nối', statusCode: 502);
      }
      quantity = 0;
      return {
        'purchase': {
          'id': 'purchase-1',
          'total': 75000,
          'payment_status': 'UNPAID',
        },
      };
    }
    if (path.startsWith('preferences/')) {
      return {
        'ui_preferences': {
          if (body?['theme_mode'] != null) 'theme_mode': body!['theme_mode'],
          if (body?['preferred_role'] != null)
            'preferred_role': body!['preferred_role'],
        },
        'shipping_draft': body?['draft'],
      };
    }
    if (path.startsWith('ai-history/')) {
      return {'messages': const [], 'ok': true};
    }
    if (path.startsWith('order-live/')) {
      return {
        'order': const {},
        'gps_trail': const [],
        'messages': const [],
        'ok': true,
      };
    }
    if (path.startsWith('notifications/')) {
      return {'unread_count': 0, 'items': const []};
    }
    if (path == 'logistics/driver_reviews') {
      return {
        'reviews': const [],
        'summary': {'count': 0, 'average': 0},
      };
    }
    if (path == 'logistics/recipient_trust') {
      return {
        'delivered': 0,
        'failed': 0,
        'returned': 0,
        'flags': 0,
        'score': 100,
      };
    }
    if (path == 'logistics/service_eta') {
      return {'services': const []};
    }
    if (path == 'marketplace/finance_request') {
      return market('finance_request', body ?? const {});
    }
    if (path.startsWith('merchant/')) {
      final action = path.substring('merchant/'.length);
      if (action == 'orders_list') {
        return market('orders', {'workspace': 'merchant', ...?body});
      }
      if (action == 'dashboard') {
        return {
          'shops': const [],
          'selected_shop_id': null,
          'my_role': 'owner',
          'kpis': null,
        };
      }
      if (action == 'aftersales_inbox') {
        return {
          'returns': const [],
          'reviews': const [],
          'finance': const [],
          'summary': const {},
        };
      }
      if (action == 'promotions') {
        return {'vouchers': const [], 'flash_sales': const []};
      }
      if (action == 'stock_ledger') {
        return {'entries': const [], 'next': null};
      }
      return {'ok': true};
    }
    throw StateError('Unexpected request $path');
  }

  @override
  Future<Map<String, dynamic>> market(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    calls.add({'action': action, 'payload': payload});
    if (action == 'catalog') {
      if (pending != null) {
        return pending!.future;
      }
      return {
        'products': [product],
        'next': null,
        'categories': ['Thực phẩm', 'Đồ dùng'],
        if (payload['shop_id'] != null)
          'shop': {
            'name': product['shop_name'],
            'description': 'Gian hàng đã xác minh',
            'address': '12 Nguyễn Huệ',
            'paused': false,
          },
      };
    }
    if (action == 'cart') {
      return {
        'version': version,
        'items': [if (quantity > 0) product],
      };
    }
    if (action == 'cart_set') {
      expect(payload['version'], version);
      version++;
      quantity = payload['quantity'] as int;
      return {
        'version': version,
        'items': [if (quantity > 0) product],
      };
    }
    if (action == 'quote') {
      return {
        'quote': {
          'id': 'quote-1',
          'expires_at': '2026-10-29T12:00:00Z',
          'snapshot': {
            'total': 75000,
            'shops': [
              {
                'shop_name': product['shop_name'],
                'subtotal': 50000,
                'shipping_fee': 25000,
              },
            ],
          },
        },
      };
    }
    if (action == 'orders') return {'orders': []};
    if (action == 'notifications') return {'notifications': []};
    if (action == 'workspace') return {'shops': [], 'products': []};
    throw StateError('Unexpected action $action');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  void size(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> tick(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  (MarketFixture, CloudAccountSession) fixture() {
    final api = MarketFixture();
    final owned = CloudAccountSession(service: api);
    addTearDown(() async {
      owned.dispose();
      await api.changes.close();
    });
    return (api, owned);
  }

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'Server catalog filters validate price and open the selected shop at $width',
      (tester) async {
        size(tester, width);
        final (api, session) = fixture();
        await session.refresh();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarketplaceView(session: session, view: MarketView.catalog),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tất cả'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Thực phẩm').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mặc định'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Giá tăng dần').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Còn hàng'));
        await tester.tap(find.text('Còn hàng'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Khoảng giá'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Giá từ'),
          '60000',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Giá đến'),
          '50000',
        );
        await tester.tap(find.text('Áp dụng'));
        await tester.pumpAndSettle();
        expect(find.text('Giá tối đa phải từ giá tối thiểu.'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Giá đến'),
          '100000',
        );
        await tester.tap(find.text('Áp dụng'));
        await tester.pumpAndSettle();
        final payload =
            api.calls.lastWhere((c) => c['action'] == 'catalog')['payload']
                as Map;
        expect(payload, {
          'category': 'Thực phẩm',
          'sort': 'price_asc',
          'in_stock': true,
          'min_price': 60000,
          'max_price': 100000,
        });
        await tester.ensureVisible(find.text('Cửa hàng thực phẩm'));
        await tester.tap(find.text('Cửa hàng thực phẩm'));
        await tester.pumpAndSettle();
        expect(
          api.calls.lastWhere((c) => c['action'] == 'catalog')['payload'],
          {'shop_id': api.product['shop_id']},
        );
        expect(find.text('Gian hàng đã xác minh'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'Default cloud login and shopping navigation at $width never use legacy OTP or Admin',
      (tester) async {
        size(tester, width);
        final (api, _) = fixture();
        api.authenticated = false;
        await tester.pumpWidget(GpsDeliveryApp(cloudService: api));
        await tick(tester);
        expect(find.text('GHST • GIAO HÀNG SIÊU TỐC'), findsOneWidget);
        expect(find.text('Đăng nhập hệ thống'), findsOneWidget);
        expect(find.text('Mã OTP'), findsNothing);
        expect(find.text('Đăng nhập quản trị'), findsNothing);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'),
          'account@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Mật khẩu'),
          'password8',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
        await tick(tester);
        expect(find.text('Hộp thực phẩm bảo quản lạnh'), findsOneWidget);
        expect(find.byTooltip('Giỏ hàng'), findsOneWidget);
        await tester.tap(
          width < 860
              ? find.byKey(const ValueKey('ghst-nav-profile'))
              : find.text('Hồ sơ cá nhân').last,
        );
        await tick(tester);
        expect(find.text('account@example.com'), findsOneWidget);
        expect(find.text('Cửa hàng của tôi'), findsNothing);
        await tester.tap(find.text('Đăng xuất').last);
        await tick(tester);
        expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);
        expect(find.text('Hộp thực phẩm bảo quản lạnh'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'Cart changes discard quotes and checkout retries preserve the same command ID',
    (tester) async {
      size(tester, 360);
      final (api, session) = fixture();
      api.quantity = 1;
      await session.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarketplaceView(session: session, view: MarketView.cart),
          ),
        ),
      );
      await tick(tester);
      expect(find.text('Thanh toán khi nhận hàng'), findsOneWidget);
      await tester.ensureVisible(find.text('Cập nhật báo giá'));
      await tester.tap(find.text('Cập nhật báo giá'));
      await tick(tester);
      expect(find.text('Đặt mua'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Tăng số lượng'));
      await tester.tap(find.byTooltip('Tăng số lượng'));
      await tick(tester);
      expect(find.text('Đặt mua'), findsNothing);
      await tester.tap(find.text('Cập nhật báo giá'));
      await tick(tester);
      api.failCheckout = true;
      await tester.ensureVisible(find.text('Đặt mua'));
      await tester.tap(find.text('Đặt mua'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tick(tester);
      expect(find.text('Mất kết nối'), findsOneWidget);
      api.failCheckout = false;
      await tester.tap(find.text('Đặt mua'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tick(tester);
      final submissions = api.calls
          .where((c) => c['path'] == 'marketplace/checkout')
          .toList();
      expect(submissions.length, 2);
      expect(
        submissions[0]['body']['request_key'],
        submissions[1]['body']['request_key'],
      );
      expect(submissions[0]['body'].keys.toSet(), {'quote_id', 'request_key'});
      expect(find.text('Giỏ hàng đang trống.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Revocation hides catalog and a late response cannot restore another account data',
    (tester) async {
      final (api, session) = fixture();
      await session.refresh();
      api.pending = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(
        MaterialApp(home: MarketplaceScreen(session: session)),
      );
      await tick(tester);
      api.id = 'other';
      api.changes.add(const AuthState(AuthChangeEvent.signedIn, null));
      await tick(tester);
      api.pending!.complete({
        'products': [api.product],
        'next': null,
      });
      api.pending = null;
      await tick(tester);
      api.blocked = true;
      await session.refresh();
      await tick(tester);
      expect(find.text('Tài khoản đang bị khóa.'), findsOneWidget);
      expect(find.text('Hộp thực phẩm bảo quản lạnh'), findsNothing);
      expect(find.byTooltip('Giỏ hàng'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Password reset requests use Auth service and never local OTP', (
    tester,
  ) async {
    final (api, session) = fixture();
    api.authenticated = false;
    await tester.pumpWidget(
      MaterialApp(home: MarketplaceScreen(session: session)),
    );
    await tick(tester);
    await tester.tap(find.text('Quên mật khẩu?'));
    await tick(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'account@example.com',
    );
    await tester.tap(find.text('Gửi email khôi phục'));
    await tick(tester);
    expect(api.calls.any((c) => c['action'] == 'reset'), isTrue);
    expect(
      find.widgetWithText(TextFormField, 'Mã xác nhận email'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Unavailable catalog renders a truthful retry state without demo products',
    (tester) async {
      final (api, session) = fixture();
      await session.refresh();
      api.pending = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarketplaceView(session: session, view: MarketView.catalog),
          ),
        ),
      );
      await tick(tester);
      api.pending!.completeError(
        const PublicApiException('Needs migration', statusCode: 503),
      );
      await tick(tester);
      expect(
        find.text('Dịch vụ tạm thời chưa khả dụng. Vui lòng thử lại sau.'),
        findsOneWidget,
      );
      expect(find.text('Hộp thực phẩm bảo quản lạnh'), findsNothing);
      expect(find.byTooltip('Tải lại'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
