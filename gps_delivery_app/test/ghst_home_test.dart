import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/core/theme/app_theme.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/presentation/customer/ghst_home_screen.dart';
import 'package:gps_delivery_app/presentation/customer/ghst_user_shell.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_screen.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_orders_screen.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_order_form.dart';
import 'package:gps_delivery_app/presentation/widgets/system_state_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unified_user_interface_test.dart' show UnifiedUserFixture;

class HomeFixture extends UnifiedUserFixture {
  bool failOrders = false;
  Completer<Map<String, dynamic>>? delayedAddresses;
  List<Map<String, dynamic>> orders = [
    {
      'id': 'order-1',
      'tracking_code': 'CL-OWNED',
      'status': 'accepted',
      'shipping_fee': 25000,
      'cod_amount': 0,
      'version': 1,
      'merchant_ready': true,
      'owner_id': 'buyer',
      'created_at': '2026-10-31T00:00:00Z',
      'details': {
        'pickup_lat': 10.77,
        'pickup_lng': 106.7,
        'dropoff_lat': 10.78,
        'dropoff_lng': 106.71,
      },
    },
  ];

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == 'orders') {
      calls.add({'path': path, 'body': body});
      if (body != null) {
        orders = [
          {...orders.first, 'tracking_code': 'CL-CREATED'},
        ];
      }
      if (failOrders) {
        throw const PublicApiException('Unavailable', statusCode: 503);
      }
      return {'orders': orders};
    }
    if (path == 'addresses' && delayedAddresses != null) {
      return delayedAddresses!.future;
    }
    if (path == 'quote') {
      calls.add({'path': path, 'body': body});
      return {
        'shipping_fee': 25000,
        'distance_meters': 1800,
        'pricing_version': 1,
      };
    }
    return super.request(path, body: body, query: query);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(HomeFixture, CloudAccountSession)> setup(
    WidgetTester tester, {
    double width = 360,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    final api = HomeFixture();
    final session = CloudAccountSession(service: api);
    addTearDown(() async {
      session.dispose();
      await api.changes.close();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await session.refresh();
    return (api, session);
  }

  testWidgets(
    'Home route belongs to cloud orders and map selection opens the shared form',
    (tester) async {
      final (_, session) = await setup(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MarketplaceScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();
      var map = tester.widget<Map3dPerspectiveWidget>(
        find.byType(Map3dPerspectiveWidget),
      );
      expect(map.useGlobalFallbackRoute, isFalse);
      expect(map.customFleetDrivers, isEmpty);
      expect(map.driverLocation, isNull);
      expect(map.routePoints.map((point) => point.latitude), [10.77, 10.78]);
      expect(map.onTapGeoPoint, isNull);
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Địa chỉ đã lưu').last);
      await tester.pumpAndSettle();
      map = tester.widget<Map3dPerspectiveWidget>(
        find.byType(Map3dPerspectiveWidget),
      );
      expect(map.routePoints, isEmpty);
      map.onTapGeoPoint!(const GeoPoint(latitude: 11, longitude: 107));
      await tester.pumpAndSettle();
      expect(find.byType(GhstUserShell), findsOneWidget);
      final form = tester.widget<CloudOrderForm>(find.byType(CloudOrderForm));
      expect(form.embedded, isTrue);
      expect(form.initialDetails?['dropoff_lat'], 11);
      expect(form.initialDetails?['dropoff_lng'], 107);
      expect(
        Navigator.of(tester.element(find.byType(MarketplaceScreen))).canPop(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Failed orders stay an error and home refresh restores real emptiness',
    (tester) async {
      final (api, session) = await setup(tester, width: 1440);
      api.failOrders = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MarketplaceScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chưa tải được dữ liệu.'), findsOneWidget);
      expect(find.text('Chưa có đơn giao hàng.'), findsNothing);
      api.failOrders = false;
      api.orders.clear();
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có đơn giao hàng.'), findsOneWidget);
      expect(find.text('Chưa tải được dữ liệu.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Late home addresses cannot reappear after session revocation', (
    tester,
  ) async {
    final (api, session) = await setup(tester);
    final delayed = Completer<Map<String, dynamic>>();
    api.delayedAddresses = delayed;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MarketplaceScreen(session: session),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    session.invalidateVerification(
      error: const PublicApiException('Revoked', statusCode: 403),
    );
    await tester.pumpAndSettle();
    delayed.complete({
      'addresses': [
        {'full_address': 'PRIVATE OLD ADDRESS', 'is_default': true},
      ],
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('PRIVATE OLD ADDRESS'), findsNothing);
    expect(find.byType(GhstHomeScreen), findsNothing);
    expect(find.text('Chưa tải được tài khoản.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Embedded shipping creates from its server quote and stays inside the shell',
    (tester) async {
      final (api, session) = await setup(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MarketplaceScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Giao nhanh').first);
      await tester.tap(find.text('Giao nhanh').first);
      await tester.pumpAndSettle();
      final values = {
        'Địa chỉ lấy hàng': '12 Nguyen Hue',
        'Địa chỉ giao hàng': '20 Le Loi',
        'Tên người nhận': 'Receiver',
        'Số điện thoại người nhận': '0912345678',
        'Hàng hóa': 'Documents',
        'Khối lượng': '1',
        'Tiền thu hộ': '0',
      };
      for (final entry in values.entries) {
        final field = find.widgetWithText(TextFormField, entry.key);
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      expect(find.widgetWithText(TextFormField, 'Vĩ độ'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Kinh độ'), findsNothing);
      final orderMap = tester.widget<Map3dPerspectiveWidget>(
        find.byKey(const ValueKey('cloud-order-google-map')),
      );
      orderMap.onTapGeoPoint!(const GeoPoint(latitude: 10.77, longitude: 106.7));
      await tester.pumpAndSettle();
      tester
          .widget<Map3dPerspectiveWidget>(
            find.byKey(const ValueKey('cloud-order-google-map')),
          )
          .onTapGeoPoint!(const GeoPoint(latitude: 10.78, longitude: 106.71));
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Lấy báo giá'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lấy báo giá'));
      await tester.pumpAndSettle();
      expect(
        api.calls.lastWhere(
          (call) => call['path'] == 'quote',
        )['body']['service_type'],
        'express',
      );
      expect(
        api.calls.where(
          (call) => call['path'] == 'orders' && call['body'] != null,
        ),
        isEmpty,
      );
      await tester.ensureVisible(find.text('Xác nhận tạo đơn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận tạo đơn'));
      await tester.pumpAndSettle();
      final writes = api.calls.where(
        (call) => call['path'] == 'orders' && call['body'] != null,
      );
      expect(writes, hasLength(1));
      expect(writes.single['body']['expected_fee'], 25000);
      expect(find.byType(CloudOrderForm), findsNothing);
      expect(find.byType(CloudOrdersScreen), findsOneWidget);
      expect(find.byType(GhstUserShell), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(MarketplaceScreen))).canPop(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
