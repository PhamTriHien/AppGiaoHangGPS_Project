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

  testWidgets(
    'Saving Cloud PostgreSQL provider shows inline sync feedback and persistent secret helper',
    (tester) async {
      EnvConfig.configureDeliveryApiRuntime(
        baseUrl: 'https://delivery.example/delivery/',
      );
      final config = {
        'local': false,
        'storage': 'cloud_postgres',
        'providers': {
          'google_maps': {
            'label': 'Google Maps Platform',
            'available': true,
            'configured': false,
            'enabled': false,
            'fields': [
              {
                'key': 'GOOGLE_MAPS_API_KEY',
                'label': 'Google Maps API key',
                'type': 'text',
                'secret': true,
                'configured': false,
                'localOnly': false,
              },
              {
                'key': 'GOOGLE_MAPS_ENABLED',
                'label': 'Cho phép backend sử dụng',
                'type': 'boolean',
                'secret': false,
                'configured': true,
                'value': 'false',
                'localOnly': false,
              },
            ],
          },
        },
      };
      final api = BackendAdminFixture((path, body) {
        if (path == 'admin/integrations/config' && body != null) {
          final values = Map<String, dynamic>.from(body['values'] as Map);
          final p =
              (config['providers'] as Map)['google_maps']
                  as Map<String, dynamic>;
          final fields = (p['fields'] as List).cast<Map<String, dynamic>>();
          if (values['GOOGLE_MAPS_API_KEY']?.toString().isNotEmpty == true) {
            final raw = values['GOOGLE_MAPS_API_KEY'].toString();
            fields[0]['configured'] = true;
            fields[0]['maskedValue'] =
                '••••••••••••${raw.substring(raw.length - 4)}';
            p['configured'] = true;
          }
          if (values['GOOGLE_MAPS_ENABLED'] != null) {
            fields[1]['value'] = values['GOOGLE_MAPS_ENABLED'];
            p['enabled'] = values['GOOGLE_MAPS_ENABLED'] == 'true';
          }
          return {
            'changed': values.keys.toList(),
            'storage': 'cloud_postgres',
            'providers': config['providers'],
          };
        }
        return config;
      });

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
      await tester.tap(find.text('Google Maps Platform'));
      await tester.pumpAndSettle();

      final keyInput = find.byKey(
        const ValueKey('integration-field-GOOGLE_MAPS_API_KEY'),
      );
      await tester.enterText(keyInput, 'AIzaSyTestCloudKey');
      final saveBtn = find.byKey(
        const ValueKey('save-integration-google_maps'),
      );
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Đã lưu Google Maps Platform · đã đồng bộ hệ thống',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Bật "Cho phép backend sử dụng"'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Khóa bảo mật đã đồng bộ hệ thống — để trống nếu giữ nguyên',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(keyInput).decoration?.floatingLabelBehavior,
        FloatingLabelBehavior.always,
      );
      expect(
        tester.widget<TextField>(keyInput).decoration?.hintText,
        '••••••••••••dKey',
      );
      expect(tester.widget<TextField>(keyInput).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'payOS provider renders webhook URL derived from PUBLIC_BASE_URL without parentheses',
    (tester) async {
      EnvConfig.configureDeliveryApiRuntime(
        baseUrl: 'https://ghst-backend-admin.onrender.com/delivery/',
      );
      final config = {
        'local': false,
        'storage': 'cloud_postgres',
        'providers': {
          'server': {
            'label': 'Máy chủ backend',
            'available': true,
            'configured': true,
            'enabled': true,
            'fields': [
              {
                'key': 'PUBLIC_BASE_URL',
                'label': 'Địa chỉ công khai backend',
                'type': 'text',
                'secret': false,
                'configured': true,
                'value': 'https://ghst-backend-admin.onrender.com',
                'localOnly': false,
              },
            ],
          },
          'payos': {
            'label': 'payOS thanh toán',
            'available': false,
            'configured': false,
            'enabled': false,
            'fields': [
              {
                'key': 'PAYOS_CLIENT_ID',
                'label': 'Client ID',
                'type': 'text',
                'secret': true,
                'configured': false,
                'localOnly': false,
              },
              {
                'key': 'PAYOS_API_KEY',
                'label': 'API Key',
                'type': 'text',
                'secret': true,
                'configured': false,
                'localOnly': false,
              },
              {
                'key': 'PAYOS_CHECKSUM_KEY',
                'label': 'Checksum Key',
                'type': 'text',
                'secret': true,
                'configured': false,
                'localOnly': false,
              },
            ],
          },
        },
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
      await tester.tap(find.text('payOS thanh toán'));
      await tester.pumpAndSettle();

      final webhookFinder = find.byKey(const ValueKey('payos-webhook-url'));
      expect(webhookFinder, findsOneWidget);
      expect(
        tester.widget<SelectableText>(webhookFinder).data,
        'https://ghst-backend-admin.onrender.com/delivery/payments/webhook',
      );
      expect(find.byTooltip('Sao chép Webhook payOS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
