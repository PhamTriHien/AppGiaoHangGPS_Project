import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/config/env_config.dart';
import 'package:gps_delivery_app/core/integrations/delivery_api_client.dart';
import 'package:gps_delivery_app/presentation/widgets/backend_integration_settings.dart';
import 'package:gps_delivery_app/presentation/widgets/backend_readiness_dialog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures/backend_admin_fixture.dart';

Map<String, dynamic> report({bool database = true, bool canMigrate = true}) => {
  'checkedAt': '2026-10-28T10:00:00Z',
  'databaseConfigured': database,
  'canMigrate': canMigrate,
  'migrationVersion': '20261029_payments_ghn',
  'databaseRevision': 'fixture-revision',
  'migrations': [
    '20261027_delivery_integrations.sql',
    '20261028_cloud_orders.sql',
    '20261029_payments_ghn.sql',
  ],
  'checks': [
    {
      'label': 'PostgreSQL backend',
      'status': database ? 'ok' : 'missing',
      'detail': database
          ? 'Đã đọc catalog PostgreSQL.'
          : 'Lưu kết nối PostgreSQL tại Admin của backend đang kết nối.',
    },
    {
      'label': 'Schema payOS / GHN',
      'status': database ? 'missing' : 'unchecked',
      'detail': 'Cần migration thanh toán và giao hàng.',
    },
  ],
  'callbacks': [
    {
      'label': 'payOS',
      'url': 'https://delivery.example/backend/delivery/payments/webhook',
      'authentication': 'Chữ ký checksum payOS',
    },
    {
      'label': 'GHN',
      'url': null,
      'authentication': 'Header X-GHN-Webhook-Secret',
    },
  ],
};

http.Response response(Map<String, dynamic> value, [int status = 200]) =>
    http.Response(
      jsonEncode(value),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  setUp(() {
    EnvConfig.configureDeliveryApiRuntime(
      baseUrl: 'http://127.0.0.1:8787/delivery/',
    );
    EnvConfig.configureAuthProvidersRuntime(
      otpEmailWebhookToken: 'private-local-token',
    );
  });
  Future<void> open(
    WidgetTester tester,
    DeliveryApiClient api, {
    bool local = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackendReadinessDialog(api: api, local: local, localAuth: local),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'Readiness fits $width and migrates only after explicit confirmation',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var writes = 0;
        final api = DeliveryApiClient(
          client: MockClient((request) async {
            expect(
              request.headers['Authorization'],
              'Bearer private-local-token',
            );
            if (request.method == 'POST') {
              writes++;
              expect(
                request.url.path,
                '/delivery/admin/integrations/migrate-cloud',
              );
              expect(jsonDecode(request.body), {
                'confirm': '20261029_payments_ghn',
                'databaseRevision': 'fixture-revision',
              });
              return response({'completed': true, 'readiness': report()});
            }
            return response(report());
          }),
        );
        await open(tester, api);
        expect(find.text('Schema payOS / GHN · Còn thiếu'), findsOneWidget);
        expect(
          find.text('Giao dịch payOS/GHN thực tế: chưa nghiệm thu.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      widget.tooltip == 'Sao chép callback GHN',
                ),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
        final migrate = find.text('Cập nhật cấu trúc dữ liệu');
        await tester.ensureVisible(migrate);
        await tester.tap(migrate);
        await tester.pumpAndSettle();
        expect(writes, 0);
        expect(find.text('Cập nhật cấu trúc dữ liệu?'), findsOneWidget);
        await tester.tap(find.text('Quay lại'));
        await tester.pumpAndSettle();
        expect(writes, 0);
        await tester.tap(migrate);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Áp dụng'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(
          find.text('Đã áp dụng migration. Kết quả kiểm tra lại ở bên dưới.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Missing database disables migration and server permissions control its visibility',
    (tester) async {
      final api = DeliveryApiClient(
        client: MockClient((_) async => response(report(database: false))),
      );
      await open(tester, api);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Cập nhật cấu trúc dữ liệu'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Schema payOS / GHN · Chưa kiểm tra'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await open(tester, api, local: false);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Cập nhật cấu trúc dữ liệu'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      final denied = DeliveryApiClient(
        client: MockClient((_) async => response(report(canMigrate: false))),
      );
      await open(tester, denied);
      expect(find.text('Cập nhật cấu trúc dữ liệu'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('A failed refresh clears old successful checks', (tester) async {
    var fail = false;
    final api = DeliveryApiClient(
      client: MockClient(
        (_) async => fail
            ? response({'error': 'Không truy cập được backend.'}, 503)
            : response(report()),
      ),
    );
    await open(tester, api);
    expect(find.text('PostgreSQL backend · Đạt'), findsOneWidget);
    fail = true;
    await tester.tap(find.byTooltip('Kiểm tra lại triển khai'));
    await tester.pumpAndSettle();
    expect(find.text('Không truy cập được backend.'), findsOneWidget);
    expect(find.text('PostgreSQL backend · Đạt'), findsNothing);
    expect(find.text('Cập nhật cấu trúc dữ liệu'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Cloud operator can confirm a schema update without local credentials',
    (tester) async {
      EnvConfig.configureDeliveryApiRuntime(
        baseUrl: 'https://delivery.example/delivery/',
      );
      final api = BackendAdminFixture(
        (path, body) => body == null
            ? report()
            : {'completed': true, 'readiness': report()},
      );
      await open(tester, api, local: false);
      await tester.ensureVisible(find.text('Cập nhật cấu trúc dữ liệu'));
      await tester.tap(find.text('Cập nhật cấu trúc dữ liệu'));
      await tester.pumpAndSettle();
      expect(api.requests.where((request) => request['body'] != null), isEmpty);
      await tester.tap(find.text('Áp dụng'));
      await tester.pumpAndSettle();
      final write = api.requests.singleWhere(
        (request) => request['body'] != null,
      );
      expect(write['localAuth'], false);
      expect(write['body'], {
        'confirm': '20261029_payments_ghn',
        'databaseRevision': 'fixture-revision',
      });
      expect(
        find.text('Đã áp dụng migration. Kết quả kiểm tra lại ở bên dưới.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Unconfirmed migration results never show success or retry automatically',
    (tester) async {
      var writes = 0;
      final pending = Completer<http.Response>();
      final api = DeliveryApiClient(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            writes++;
            return pending.future;
          }
          return response(report());
        }),
      );
      await open(tester, api);
      await tester.ensureVisible(find.text('Cập nhật cấu trúc dữ liệu'));
      await tester.tap(find.text('Cập nhật cấu trúc dữ liệu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Áp dụng'));
      await tester.pump();
      expect(writes, 1);
      expect(find.text('Đang cập nhật cấu trúc dữ liệu...'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Đóng'))
            .onPressed,
        isNull,
      );
      pending.complete(
        response({'error': 'Chưa xác nhận cập nhật schema.'}, 503),
      );
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('Chưa xác nhận cập nhật schema.'), findsOneWidget);
      expect(find.textContaining('Đã áp dụng migration'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Admin offers readiness without loading checks or credentials at startup',
    (tester) async {
      var calls = 0;
      final api = DeliveryApiClient(
        client: MockClient((request) async {
          calls++;
          if (request.url.path.endsWith('/readiness')) {
            return response(report(database: false));
          }
          return response({'local': true, 'providers': <String, dynamic>{}});
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BackendIntegrationSettings(api: api)),
        ),
      );
      expect(calls, 0);
      await tester.tap(find.text('Quản lý API backend'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.byTooltip('Sẵn sàng triển khai'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('PostgreSQL backend · Còn thiếu'), findsOneWidget);
      expect(find.text('private-local-token'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
