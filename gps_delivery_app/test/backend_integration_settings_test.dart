import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/config/env_config.dart';
import 'package:gps_delivery_app/core/integrations/delivery_api_client.dart';
import 'package:gps_delivery_app/presentation/widgets/backend_integration_settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures/backend_admin_fixture.dart';

Map<String, dynamic> configuration() => {
  'local': false,
  'providers': {
    'ghn': {
      'label': 'GHN',
      'available': true,
      'configured': true,
      'enabled': true,
      'fields': [
        {
          'key': 'GHN_TOKEN',
          'label': 'API token',
          'type': 'text',
          'secret': true,
          'configured': true,
        },
        {
          'key': 'GHN_ENABLED',
          'label': 'Cho phép backend sử dụng',
          'type': 'boolean',
          'secret': false,
          'value': 'true',
        },
      ],
    },
    'momo': {
      'label': 'MoMo',
      'available': false,
      'configured': false,
      'enabled': false,
      'fields': [],
    },
  },
};

void main() {
  setUp(() {
    EnvConfig.configureDeliveryApiRuntime(
      baseUrl: 'http://127.0.0.1:8787/delivery/',
    );
    EnvConfig.configureAuthProvidersRuntime(otpEmailWebhookToken: 'test-token');
  });
  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'Admin API form masks secrets, preserves blanks and clears saved text at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var calls = 0;
        final saved = <Map>[];
        final api = DeliveryApiClient(
          client: MockClient((request) async {
            calls++;
            expect(request.url.host, '127.0.0.1');
            if (request.method == 'POST') {
              saved.add(jsonDecode(request.body) as Map);
            }
            return http.Response(
              jsonEncode(configuration()),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: BackendIntegrationSettings(api: api),
              ),
            ),
          ),
        );
        expect(calls, 0);
        await tester.tap(find.text('Quản lý API backend'));
        await tester.pumpAndSettle();
        expect(find.text('Chưa có luồng giao dịch'), findsOneWidget);
        await tester.tap(find.text('GHN'));
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('integration-field-GHN_TOKEN'));
        expect(tester.widget<TextField>(input).obscureText, isTrue);
        final save = find.byKey(const ValueKey('save-integration-ghn'));
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect((saved.last['values'] as Map).containsKey('GHN_TOKEN'), isFalse);
        await tester.enterText(input, 'replacement-secret');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(saved.last['values']['GHN_TOKEN'], 'replacement-secret');
        expect(tester.widget<TextField>(input).controller!.text, isEmpty);
        await tester.tap(find.byTooltip('Xóa giá trị đã lưu'));
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(saved.last['clear'], ['GHN_TOKEN']);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Forbidden backend response shows error without configuration fields',
    (tester) async {
      final api = DeliveryApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'error': 'Cần quyền điều hành.'}),
            403,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BackendIntegrationSettings(api: api)),
        ),
      );
      await tester.tap(find.text('Quản lý API backend'));
      await tester.pumpAndSettle();
      expect(find.text('Cần quyền điều hành.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cloud Admin saves a masked database connection to the displayed backend',
    (tester) async {
      EnvConfig.configureDeliveryApiRuntime(
        baseUrl: 'https://delivery.example/delivery/',
      );
      final config = configuration();
      (config['providers'] as Map)['backend'] = {
        'label': 'Triển khai backend',
        'available': true,
        'configured': false,
        'enabled': false,
        'fields': [
          {
            'key': 'DATABASE_URL',
            'label': 'Kết nối PostgreSQL',
            'type': 'text',
            'secret': true,
            'configured': false,
            'localOnly': false,
          },
        ],
      };
      final api = BackendAdminFixture((_, _) => config);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BackendIntegrationSettings(api: api),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Quản lý API backend'));
      await tester.pumpAndSettle();
      expect(find.text('Backend từ xa'), findsOneWidget);
      expect(find.text('https://delivery.example/delivery/'), findsOneWidget);
      await tester.ensureVisible(find.text('Triển khai backend'));
      await tester.tap(find.text('Triển khai backend'));
      await tester.pumpAndSettle();
      final field = find.byKey(
        const ValueKey('integration-field-DATABASE_URL'),
      );
      expect(tester.widget<TextField>(field).enabled, true);
      expect(tester.widget<TextField>(field).obscureText, true);
      await tester.enterText(
        field,
        'postgresql://postgres:private-db@db.example/postgres',
      );
      final save = find.byKey(const ValueKey('save-integration-backend'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final write = api.requests.singleWhere(
        (request) => request['body'] != null,
      );
      expect(write['localAuth'], false);
      expect((write['body'] as Map)['values'], {
        'DATABASE_URL': 'postgresql://postgres:private-db@db.example/postgres',
      });
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(find.text('test-token'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
