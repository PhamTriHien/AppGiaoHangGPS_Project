import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/config/env_config.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/integrations/delivery_api_client.dart';
import 'package:gps_delivery_app/core/integrations/photon_address_service.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_orders_screen.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_order_form.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_pricing_dialog.dart';
import 'package:gps_delivery_app/presentation/widgets/system_state_screens.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CloudFixture extends CloudOrdersService {
  bool authenticated = true;
  String identity = '00000000-0000-0000-0000-000000000001';
  String role = 'customer';
  bool operator = false;
  bool hasProfile = true;
  bool blocked = false, failOrders = false;
  int ordersFailureStatus = 403;
  String projectId = 'test-project';
  bool missingSchema = false;
  int schemaVersion = 2;
  Completer<Map<String, dynamic>>? pendingOrders;
  Completer<Map<String, dynamic>>? pendingCommand;
  final changes = StreamController<AuthState>.broadcast();
  final calls = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> orders = [];
  List<Map<String, dynamic>> queue = [];
  List<Map<String, dynamic>> accounts = [];
  List<Map<String, dynamic>> history = [];
  @override
  bool get signedIn => authenticated;
  @override
  String get userId => authenticated ? identity : '';
  @override
  String get email => 'user@example.com';
  @override
  String get project => projectId;
  @override
  Stream<AuthState> get authChanges => changes.stream;
  @override
  Future<String?> authenticate(
    String email,
    String password, {
    bool register = false,
  }) async {
    authenticated = true;
    changes.add(AuthState(AuthChangeEvent.signedIn, null));
    return null;
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body, 'query': query});
    if (body != null && pendingCommand != null) return pendingCommand!.future;
    if (missingSchema) {
      throw const PublicApiException(
        'Chưa cài schema đơn hàng cloud.',
        statusCode: 503,
      );
    }
    if (path == 'profile') {
      return {
        'account': !hasProfile
            ? null
            : {
                'user_id': identity,
                'full_name': 'Fixture user',
                'phone': '0901234567',
                'role': role,
                'blocked': blocked,
              },
        'operator': operator,
        'schema_version': schemaVersion,
      };
    }
    if (path == 'orders' && body == null) {
      if (failOrders) {
        throw PublicApiException(
          'Không tải được đơn hàng.',
          statusCode: ordersFailureStatus,
        );
      }
      if (pendingOrders != null) {
        final pending = pendingOrders!;
        pendingOrders = null;
        return pending.future;
      }
      return {'orders': query?['queue'] == 'true' ? queue : orders};
    }
    if (path == 'merchants') return {'merchants': []};
    if (path == 'quote') {
      return {
        'shipping_fee': 25000,
        'distance_meters': 1800,
        'pricing_version': 1,
      };
    }
    if (path == 'orders' && body != null) return {'order': order()};
    if (path.endsWith('/transition')) {
      if (body?['action'] == 'collect_cash' && orders.isNotEmpty) {
        final current = orders.first;
        orders = [
          {
            ...current,
            'version': (current['version'] as int? ?? 1) + 1,
            'payment_status': 'PAID',
            'cash_collected_fee':
                current['payable_fee'] ?? current['shipping_fee'],
            'cash_collected_cod': current['cod_amount'] ?? 0,
            'cash_collected_at': '2026-11-03T14:25:00Z',
          },
        ];
        return {'order': orders.first};
      }
      final status =
          {
            'claim': 'accepted',
            'fail': 'failed',
            'return': 'returning',
            'complete_return': 'returned',
            'deliver': 'delivered',
          }[body?['action']] ??
          'accepted';
      orders = [
        {...order(), 'status': status, 'driver_id': identity},
      ];
      queue = [];
      return {'order': orders.first};
    }
    if (path == 'accounts') return {'accounts': accounts};
    if (path.endsWith('/history')) return {'history': history};
    if (path.startsWith('accounts/') && body != null) {
      accounts = [
        for (final a in accounts)
          if (a['user_id'] == path.split('/').last)
            {...a, ...body, 'requested_role': null}
          else
            a,
      ];
      return {'accounts': accounts};
    }
    return {};
  }
}

Map<String, dynamic> order({String tracking = 'CL-TEST'}) => {
  'id': '10000000-0000-0000-0000-000000000001',
  'tracking_code': tracking,
  'status': 'searching',
  'version': 1,
  'merchant_ready': true,
  'owner_id': '00000000-0000-0000-0000-000000000001',
  'shipping_fee': 25000,
  'cod_amount': 100000,
  'created_at': '2026-10-27T12:00:00Z',
  'details': {
    'pickup_address': '12 Nguyen Hue',
    'dropoff_address': '20 Le Loi',
    'recipient_name': 'Receiver',
    'recipient_phone': '0912345678',
    'package_description': 'Documents',
    'weight_kg': 1,
    'payment_method': 'sender_cash',
  },
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> finish(WidgetTester tester, CloudFixture api) async {
    await tester.pumpWidget(const SizedBox());
    await api.changes.close();
  }

  testWidgets(
    'Cloud login works without a local app account and never shows privileged controls',
    (tester) async {
      final api = CloudFixture()..authenticated = false;
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(service: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mật khẩu'), findsOneWidget);
      expect(find.byTooltip('Bảng giá cước'), findsNothing);
      expect(api.calls, isEmpty);
      await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'password-test');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();
      expect(find.text('Tạo đơn hàng'), findsOneWidget);
      expect(find.textContaining('test-project'), findsNothing);
      expect(find.text('Đơn hàng cloud'), findsNothing);
      expect(find.text('Đăng nhập cloud'), findsNothing);
      await finish(tester, api);
    },
  );

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'Driver sees queue, claims once and reloads server state at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = CloudFixture()
          ..role = 'driver'
          ..queue = [
            {
              ...order(),
              'details': {'weight_kg': 1},
            },
          ];
        await tester.pumpWidget(
          MaterialApp(home: CloudOrdersScreen(service: api)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chờ nhận'));
        await tester.pumpAndSettle();
        expect(find.textContaining('0912345678'), findsNothing);
        await tester.tap(find.text('Nhận chuyến'));
        await tester.pumpAndSettle();
        expect(
          api.calls.where((c) => '${c['path']}'.endsWith('/transition')),
          hasLength(1),
        );
        await tester.tap(find.text('Chuyến của tôi'));
        await tester.pumpAndSettle();
        expect(find.text('Đã nhận chuyến'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await finish(tester, api);
      },
    );
  }

  testWidgets(
    'An account switch discards an in-flight response from the previous identity',
    (tester) async {
      final api = CloudFixture();
      final pending = Completer<Map<String, dynamic>>();
      api.pendingOrders = pending;
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(service: api)),
      );
      await tester.pump();
      api.identity = '00000000-0000-0000-0000-000000000002';
      api.changes.add(AuthState(AuthChangeEvent.signedIn, null));
      await tester.pump();
      pending.complete({
        'orders': [order(tracking: 'OLD-PRIVATE-ORDER')],
      });
      await tester.pumpAndSettle();
      expect(find.text('OLD-PRIVATE-ORDER'), findsNothing);
      expect(find.text('Chưa có đơn hàng.'), findsOneWidget);
      await finish(tester, api);
    },
  );

  testWidgets(
    'A failed profile refresh removes operator controls and cached orders',
    (tester) async {
      final api = CloudFixture()
        ..operator = true
        ..orders = [order()];
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(service: api, admin: true)),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Bảng giá cước'), findsOneWidget);
      expect(find.textContaining('CL-TEST'), findsWidgets);
      api.missingSchema = true;
      await tester.tap(find.byTooltip('Tải lại đơn hàng'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Bảng giá cước'), findsNothing);
      expect(find.textContaining('CL-TEST'), findsNothing);
      expect(find.text('Chưa cài schema đơn hàng cloud.'), findsOneWidget);
      await finish(tester, api);
    },
  );

  testWidgets(
    'A revoked driver role clears the queue even when the next order read fails',
    (tester) async {
      final api = CloudFixture()
        ..role = 'driver'
        ..orders = [order()];
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(service: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chờ nhận'), findsOneWidget);
      api.role = 'customer';
      api.failOrders = true;
      api.changes.add(AuthState(AuthChangeEvent.userUpdated, null));
      await tester.pumpAndSettle();
      expect(find.text('Chờ nhận'), findsNothing);
      expect(find.textContaining('CL-TEST'), findsNothing);
      expect(find.text('Không tải được đơn hàng.'), findsOneWidget);
      await finish(tester, api);
    },
  );

  testWidgets(
    'Blocked profiles immediately lose order and address controls after revalidation',
    (tester) async {
      final api = CloudFixture()..orders = [order()];
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(service: api)),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Sổ địa chỉ'), findsOneWidget);
      api.blocked = true;
      await tester.tap(find.byTooltip('Tải lại đơn hàng'));
      await tester.pumpAndSettle();
      expect(find.text('Tài khoản đang bị khóa.'), findsOneWidget);
      expect(find.byTooltip('Sổ địa chỉ'), findsNothing);
      expect(find.text('Tạo đơn hàng'), findsNothing);
      expect(find.textContaining('CL-TEST'), findsNothing);
      await finish(tester, api);
    },
  );

  for (final verificationFails in [false, true]) {
    testWidgets(
      'Resume revalidates before restoring data (failure=$verificationFails)',
      (tester) async {
        final api = CloudFixture()..orders = [order()];
        await tester.pumpWidget(
          MaterialApp(home: CloudOrdersScreen(service: api)),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('CL-TEST'), findsWidgets);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('CL-TEST'), findsWidgets);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(find.textContaining('CL-TEST'), findsWidgets);
        final reads = api.calls.length;
        await tester.pump(const Duration(seconds: 21));
        expect(api.calls, hasLength(reads));
        api.blocked = true;
        api.missingSchema = verificationFails;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(api.calls.skip(reads).first['path'], 'profile');
        expect(
          api.calls.skip(reads).where((c) => c['path'] == 'orders'),
          isEmpty,
        );
        expect(find.textContaining('CL-TEST'), findsNothing);
        expect(find.byType(CloudOrderForm), findsNothing);
        expect(tester.takeException(), isNull);
        await finish(tester, api);
      },
    );
  }

  testWidgets('A late pre-pause order response cannot replace resumed data', (
    tester,
  ) async {
    final api = CloudFixture();
    final pending = Completer<Map<String, dynamic>>();
    api.pendingOrders = pending;
    await tester.pumpWidget(MaterialApp(home: CloudOrdersScreen(service: api)));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    pending.complete({
      'orders': [order(tracking: 'STALE-PRIVATE')],
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('STALE-PRIVATE'), findsNothing);
    expect(
      api.calls.where((c) => c['path'] == 'profile').length,
      greaterThan(1),
    );
    expect(tester.takeException(), isNull);
    await finish(tester, api);
  });

  testWidgets(
    'Pagination keeps loaded history after a transient error and retries the same cursor',
    (tester) async {
      final firstPage = [
        for (var id = 0; id < 50; id++)
          {
            ...order(tracking: 'CL-PAGE-$id'),
            'id': '10000000-0000-0000-0000-${id.toString().padLeft(12, '0')}',
          },
      ];
      final api = CloudFixture()..orders = firstPage;
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(service: api)),
      );
      await tester.pumpAndSettle();
      final more = find.widgetWithText(TextButton, 'Tải thêm');
      await tester.ensureVisible(more);
      api.failOrders = true;
      api.ordersFailureStatus = 502;
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.textContaining('CL-PAGE-0'), findsWidgets);
      expect(find.text('Không tải được đơn hàng.'), findsOneWidget);
      expect(more, findsOneWidget);
      final failedQuery = api.calls.last['query'];
      api.failOrders = false;
      api.orders = [
        {
          ...order(tracking: 'CL-NEXT-PAGE'),
          'id': '10000000-0000-0000-0000-000000000999',
        },
      ];
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(api.calls.last['query'], failedQuery);
      expect(failedQuery, {
        'before': firstPage.last['created_at'],
        'before_id': firstPage.last['id'],
      });
      expect(find.textContaining('CL-NEXT-PAGE'), findsWidgets);
      expect(find.text('Hiển thị 51 / 51 đơn đã tải'), findsOneWidget);
      expect(more, findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester, api);
    },
  );

  testWidgets(
    'A project switch with the same user ID cannot reuse old order data',
    (tester) async {
      final api = CloudFixture()..orders = [order()];
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(service: api)),
      );
      await tester.pumpAndSettle();
      api.projectId = 'another-project';
      api.orders = [];
      api.changes.add(AuthState(AuthChangeEvent.tokenRefreshed, null));
      await tester.pumpAndSettle();
      expect(find.textContaining('CL-TEST'), findsNothing);
      await finish(tester, api);
    },
  );

  testWidgets(
    'Missing schema reports an actionable error without fabricated orders',
    (tester) async {
      final api = CloudFixture()..missingSchema = true;
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(service: api)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Dịch vụ đơn hàng tạm thời chưa khả dụng. Vui lòng thử lại sau.',
        ),
        findsOneWidget,
      );
      expect(find.text('Chưa cài schema đơn hàng cloud.'), findsNothing);
      expect(find.text('Tạo đơn hàng'), findsNothing);
      await finish(tester, api);
    },
  );

  testWidgets(
    'A non-operator cannot access admin account and pricing controls',
    (tester) async {
      final api = CloudFixture();
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(service: api, admin: true)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Tài khoản chưa có quyền quản trị.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Bảng giá cước'), findsNothing);
      expect(api.calls.any((c) => c['path'] == 'accounts'), isFalse);
      await finish(tester, api);
    },
  );

  testWidgets(
    'An operator needs no business profile and sees an explicit migration requirement for old cloud schemas',
    (tester) async {
      final api = CloudFixture()
        ..operator = true
        ..hasProfile = false
        ..schemaVersion = 1;
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(service: api, admin: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Operator'), findsOneWidget);
      expect(find.text('Họ và tên'), findsNothing);
      expect(
        find.textContaining('Cơ sở dữ liệu cần cập nhật'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Bảng giá cước',
              ),
            )
            .onPressed,
        isNull,
      );
      await finish(tester, api);
    },
  );

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'Operator filters pending profiles and confirms approval at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = CloudFixture()
          ..operator = true
          ..hasProfile = false
          ..accounts = [
            {
              'user_id': 'driver-user',
              'full_name': 'Pending Driver',
              'phone': '0901234567',
              'role': 'customer',
              'requested_role': 'driver',
              'blocked': false,
            },
            {
              'user_id': 'other-user',
              'full_name': 'Another Customer',
              'phone': '0912345678',
              'role': 'customer',
              'blocked': false,
            },
          ];
        await tester.pumpWidget(
          MaterialApp(home: CloudOrdersScreen(service: api, admin: true)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tài khoản'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Pending');
        await tester.pumpAndSettle();
        expect(find.textContaining('Another Customer'), findsNothing);
        expect(find.text('Hiển thị 1 / 2 tài khoản đã tải'), findsOneWidget);
        await tester.ensureVisible(find.text('Duyệt Tài xế'));
        await tester.tap(find.text('Duyệt Tài xế'));
        await tester.pumpAndSettle();
        expect(
          api.calls.any((c) => '${c['path']}'.startsWith('accounts/')),
          isFalse,
        );
        await tester.tap(find.text('Quay lại'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Duyệt Tài xế'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xác nhận'));
        await tester.pumpAndSettle();
        final write = api.calls.singleWhere(
          (c) => c['path'] == 'accounts/driver-user',
        );
        expect(write['body'], {'role': 'driver', 'blocked': false});
        expect(find.text('Duyệt Tài xế'), findsNothing);
        expect(tester.takeException(), isNull);
        await finish(tester, api);
      },
    );
  }

  testWidgets(
    'Failure requires a reason and returning orders expose only the return completion action',
    (tester) async {
      final api = CloudFixture()..role = 'driver';
      api.orders = [
        {...order(), 'status': 'inTransit', 'driver_id': api.identity},
      ];
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(service: api)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Giao thất bại'));
      await tester.tap(find.text('Giao thất bại'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(find.text('Lý do cần ít nhất 3 ký tự.'), findsOneWidget);
      expect(
        api.calls.any((c) => '${c['path']}'.endsWith('/transition')),
        isFalse,
      );
      await tester.tap(find.text('Giao thất bại'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Recipient unavailable',
      );
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(
        api.calls.lastWhere(
          (c) => '${c['path']}'.endsWith('/transition'),
        )['body']['reason'],
        'Recipient unavailable',
      );
      api.orders = [
        {...order(), 'status': 'returning', 'driver_id': api.identity},
      ];
      await tester.tap(find.byTooltip('Tải lại đơn hàng'));
      await tester.pumpAndSettle();
      expect(find.text('Giao thành công'), findsNothing);
      await tester.ensureVisible(find.text('Đã trả hàng cho người gửi'));
      await tester.tap(find.text('Đã trả hàng cho người gửi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đã hoàn hàng'));
      await tester.pumpAndSettle();
      expect(
        api.calls.lastWhere(
          (c) => '${c['path']}'.endsWith('/transition'),
        )['body']['action'],
        'complete_return',
      );
      expect(find.text('Đã hoàn hàng'), findsOneWidget);
      await finish(tester, api);
    },
  );

  testWidgets(
    'Pricing rejects out-of-range input and submits the original version for concurrency protection',
    (tester) async {
      final api = CloudFixture()..operator = true;
      await tester.pumpWidget(
        MaterialApp(
          home: CloudPricingDialog(
            service: api,
            pricing: const {
              'base_fee': 25000,
              'per_km': 5000,
              'express_fee': 10000,
              'extra_kg': 3000,
              'version': 7,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(1), '100001');
      await tester.tap(find.text('Lưu bảng giá'));
      await tester.pumpAndSettle();
      expect(find.text('Giá trị từ 0 đến 100000'), findsOneWidget);
      expect(api.calls, isEmpty);
      await tester.enterText(find.byType(TextFormField).at(1), '6000');
      await tester.tap(find.text('Lưu bảng giá'));
      await tester.pumpAndSettle();
      expect(api.calls.single['body'], {
        'base_fee': 25000,
        'per_km': 6000,
        'express_fee': 10000,
        'extra_kg': 3000,
        'version': 7,
      });
      await finish(tester, api);
    },
  );

  test(
    'Command IDs survive retries, are scoped per identity and change for a new order draft',
    () async {
      final api = CloudFixture();
      final draft = await api.startDraft();
      expect(await api.startDraft(), draft);
      await api.command('orders', {'draft_id': draft, 'details': 'same-details'});
      final first = api.calls.last['body']['request_key'];
      await api.command('orders', {'draft_id': draft, 'details': 'same-details'});
      expect(api.calls.last['body']['request_key'], first);
      api.identity = 'another-identity';
      await api.command('orders', {'draft_id': draft, 'details': 'same-details'});
      expect(api.calls.last['body']['request_key'], isNot(first));
      api.identity = '00000000-0000-0000-0000-000000000001';
      await api.completeDraft(draft);
      expect(await api.startDraft(), isNot(draft));
      await api.changes.close();
    },
  );

  test(
    'Retries after an upgrade reuse the previously persisted command key',
    () async {
      final api = CloudFixture();
      final payload = {'draft_id': 'previous-build-draft'};
      final fingerprint = sha256.convert(
        utf8.encode(jsonEncode(['orders', payload])),
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'ghst_cloud_command:${api.project}:${api.userId}:$fingerprint',
        'previous-request-key',
      );
      await api.command('orders', payload);
      expect(api.calls.last['body']['request_key'], 'previous-request-key');
      await api.changes.close();
    },
  );

  test('A command response from the previous identity is rejected', () async {
    final api = CloudFixture()
      ..pendingCommand = Completer<Map<String, dynamic>>();
    final command = api.command('orders', {'draft_id': 'race-draft'});
    final rejected = expectLater(command, throwsStateError);
    for (var attempt = 0; api.calls.isEmpty && attempt < 20; attempt++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(api.calls, hasLength(1));
    api.identity = 'another-account';
    api.pendingCommand!.complete({'order': order()});
    await rejected;
    await api.changes.close();
  });

  test('Signed-out sessions cannot create drafts or command keys', () async {
    final api = CloudFixture()..authenticated = false;
    await expectLater(api.startDraft(), throwsStateError);
    await expectLater(api.command('orders', {}), throwsStateError);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), isEmpty);
    expect(api.calls, isEmpty);
    await api.changes.close();
  });

  testWidgets(
    'Order form requires real coordinates and an authoritative quote before creation',
    (tester) async {
      final api = CloudFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: CloudOrderForm(service: api, merchants: const []),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Vĩ độ'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Kinh độ'), findsNothing);
      final fields = find.byType(TextFormField);
      final values = [
        '12 Nguyen Hue',
        '20 Le Loi',
        'Receiver',
        '0912345678',
        'Documents',
        '1',
        '100000',
      ];
      for (var i = 0; i < values.length; i++) {
        await tester.ensureVisible(fields.at(i));
        await tester.enterText(fields.at(i), values[i]);
      }
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Lấy báo giá'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lấy báo giá'));
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận tạo đơn'), findsNothing);
      expect(
        find.textContaining('Chưa ghim được Địa chỉ lấy hàng trên Google Map'),
        findsOneWidget,
      );
      expect(api.calls.where((c) => c['path'] == 'quote'), isEmpty);

      tester
          .widget<Map3dPerspectiveWidget>(
            find.byKey(const ValueKey('cloud-order-google-map')),
          )
          .onTapGeoPoint!(const GeoPoint(latitude: 10.77, longitude: 106.7));
      await tester.pumpAndSettle();
      tester
          .widget<Map3dPerspectiveWidget>(
            find.byKey(const ValueKey('cloud-order-google-map')),
          )
          .onTapGeoPoint!(const GeoPoint(latitude: 10.78, longitude: 106.71));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Lấy báo giá'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lấy báo giá'));
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận tạo đơn'), findsOneWidget);
      expect(api.calls.where((c) => c['path'] == 'orders'), isEmpty);
      final weight = tester.widget<TextFormField>(fields.at(5)).controller!;
      weight.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận tạo đơn'), findsOneWidget);
      await tester.ensureVisible(fields.at(5));
      await tester.enterText(fields.at(5), '2');
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận tạo đơn'), findsNothing);
      await finish(tester, api);
    },
  );

  testWidgets(
    'Order form searches addresses on Google Map and reverse-geocodes direct map taps without manual coordinate inputs',
    (tester) async {
      EnvConfig.configureDeliveryApiRuntime(
        baseUrl: 'http://127.0.0.1:8787/delivery/',
      );
      EnvConfig.configureAuthProvidersRuntime(
        otpEmailWebhookToken: 'test-backend-token',
      );
      addTearDown(() {
        EnvConfig.configureDeliveryApiRuntime(baseUrl: '');
        EnvConfig.configureAuthProvidersRuntime(otpEmailWebhookToken: '');
      });
      final addressService = PhotonAddressService(
        api: DeliveryApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/reverse')) {
              return http.Response.bytes(
                utf8.encode(
                  jsonEncode({
                    'address': 'Chợ Bến Thành, Quận 1, TP.HCM',
                    'attribution': 'Google Maps',
                  }),
                ),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            if (request.url.path.endsWith('/places')) {
              expect(request.url.queryParameters['q'], 'Landmark 81');
              expect(request.url.queryParameters['lat'], '10.77250');
              expect(request.url.queryParameters['lon'], '106.69800');
              return http.Response.bytes(
                utf8.encode(
                  jsonEncode({
                    'autocomplete': true,
                    'attribution': 'Google Maps',
                    'places': [
                      {
                        'title': 'Landmark 81',
                        'address':
                            'Vinhomes Central Park, Bình Thạnh, TP.HCM',
                        'latitude': 10.795,
                        'longitude': 106.7218,
                      },
                    ],
                  }),
                ),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            return http.Response('{}', 404);
          }),
        ),
      );

      final api = CloudFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: CloudOrderForm(
            service: api,
            merchants: const [],
            addressService: addressService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      tester
          .widget<Map3dPerspectiveWidget>(
            find.byKey(const ValueKey('cloud-order-google-map')),
          )
          .onTapGeoPoint!(
            const GeoPoint(latitude: 10.7725, longitude: 106.698),
          );
      await tester.pumpAndSettle();
      final pickupField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Địa chỉ lấy hàng'),
      );
      expect(
        pickupField.controller!.text,
        'Chợ Bến Thành, Quận 1, TP.HCM',
      );

      final dropoffFinder = find.widgetWithText(
        TextFormField,
        'Địa chỉ giao hàng',
      );
      await tester.ensureVisible(dropoffFinder);
      await tester.enterText(dropoffFinder, 'Landmark 81');
      final searchBtn = find.text('Tìm điểm giao trên Google Map');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.ensureVisible(searchBtn);
      await tester.pumpAndSettle();
      await tester.tap(searchBtn);
      await tester.pumpAndSettle();
      expect(find.text('Google Maps'), findsOneWidget);
      final suggestion = find.text('Vinhomes Central Park, Bình Thạnh, TP.HCM');
      await tester.ensureVisible(suggestion);
      await tester.pumpAndSettle();
      await tester.tap(suggestion);
      await tester.pumpAndSettle();

      for (final entry in {
        'Tên người nhận': 'Receiver',
        'Số điện thoại người nhận': '0912345678',
        'Hàng hóa': 'Documents',
        'Khối lượng': '1',
        'Tiền thu hộ': '100000',
      }.entries) {
        final f = find.widgetWithText(TextFormField, entry.key);
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.enterText(f, entry.value);
      }
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Lấy báo giá'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lấy báo giá'));
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận tạo đơn'), findsOneWidget);
      final quoteBody =
          api.calls.lastWhere((c) => c['path'] == 'quote')['body']
              as Map<String, dynamic>;
      expect(quoteBody['pickup_address'], 'Chợ Bến Thành, Quận 1, TP.HCM');
      expect(quoteBody['pickup_lat'], 10.7725);
      expect(quoteBody['pickup_lng'], 106.698);
      expect(
        quoteBody['dropoff_address'],
        'Vinhomes Central Park, Bình Thạnh, TP.HCM',
      );
      expect(quoteBody['dropoff_lat'], 10.795);
      expect(quoteBody['dropoff_lng'], 106.7218);
      await finish(tester, api);
    },
  );

  testWidgets(
    'Driver confirms cash shipping fee and COD collection while customer hides stale online pay button on delivered cash order',
    (tester) async {
      final driverId = '00000000-0000-0000-0000-000000000002';
      final deliveredOrder = {
        ...order(tracking: 'CL-CASH-SETTLE'),
        'status': 'delivered',
        'version': 5,
        'driver_id': driverId,
        'shipping_fee': 25000,
        'coin_discount': 50,
        'payable_fee': 24950,
        'cod_amount': 100000,
        'payment_status': 'UNPAID',
        'cash_collected_fee': 0,
        'cash_collected_cod': 0,
      };
      final driverApi = CloudFixture()
        ..identity = driverId
        ..role = 'driver'
        ..orders = [deliveredOrder];

      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(service: driverApi)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Xác nhận thu tiền mặt'), findsOneWidget);
      expect(
        find.text('Người gửi trả phí · Chưa ghi nhận thanh toán cước'),
        findsOneWidget,
      );
      await tester.tap(find.text('Xác nhận thu tiền mặt'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Cước vận chuyển thu tiền mặt:'),
        findsOneWidget,
      );
      expect(find.textContaining('24.950'), findsWidgets);
      expect(find.textContaining('Tiền thu hộ COD:'), findsOneWidget);
      expect(find.textContaining('Tổng tiền mặt cần thu:'), findsOneWidget);

      await tester.tap(find.text('Xác nhận đã thu'));
      await tester.pumpAndSettle();

      final transitionCall = driverApi.calls.firstWhere(
        (c) => (c['path'] as String).endsWith('/transition'),
      );
      expect(transitionCall['body']['action'], 'collect_cash');
      expect(transitionCall['body']['version'], 5);
      expect(find.text('Xác nhận thu tiền mặt'), findsNothing);
      expect(
        find.text(
          'Người gửi trả phí · Đã thu tiền mặt cước · Đã thu hộ COD',
        ),
        findsOneWidget,
      );
      await finish(tester, driverApi);

      final customerApi = CloudFixture()
        ..orders = [
          {
            ...deliveredOrder,
            'payment_status': 'PAID',
            'cash_collected_fee': 24950,
            'cash_collected_cod': 100000,
          },
        ];
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(service: customerApi)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Thanh toán cước'), findsNothing);
      expect(
        find.text(
          'Người gửi trả phí · Đã thu tiền mặt cước · Đã thu hộ COD',
        ),
        findsOneWidget,
      );
      await finish(tester, customerApi);
    },
  );
}
