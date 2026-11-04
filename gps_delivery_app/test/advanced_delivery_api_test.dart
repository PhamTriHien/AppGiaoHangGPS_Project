import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/config/env_config.dart';
import 'package:gps_delivery_app/core/integrations/delivery_api_client.dart';
import 'package:gps_delivery_app/core/integrations/photon_address_service.dart';
import 'package:gps_delivery_app/core/integrations/push_notification_service.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/presentation/widgets/photon_address_lookup.dart';
import 'package:gps_delivery_app/presentation/widgets/shipping_label_scanner.dart';
import 'package:gps_delivery_app/presentation/widgets/support_ai_summary.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> places(String address, {bool autocomplete = false}) => {
  'places': [
    {
      'title': address,
      'address': address,
      'longitude': 106.7,
      'latitude': 10.7,
    },
  ],
  'autocomplete': autocomplete,
};

void main() {
  setUp(() {
    EnvConfig.configureDeliveryApiRuntime(
      baseUrl: 'http://localhost:8787/delivery/',
    );
    EnvConfig.configureAuthProvidersRuntime(otpEmailWebhookToken: 'test-token');
  });
  tearDown(() {
    EnvConfig.configureDeliveryApiRuntime(baseUrl: '');
    EnvConfig.configureAuthProvidersRuntime(otpEmailWebhookToken: '');
  });
  test('Authenticated API retains provider error and never returns synthetic results', () async {
    final api = DeliveryApiClient(
      client: MockClient((request) async {
        expect(request.url.path, '/delivery/places');
        expect(request.headers['Authorization'], 'Bearer test-token');
        return http.Response(
          jsonEncode({'error': 'Dịch vụ chưa được cấu hình.'}),
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await expectLater(
      api.request('places'),
      throwsA(
        isA<PublicApiException>().having((e) => e.statusCode, 'status', 503),
      ),
    );
  });
  test('Native Windows does not request Firebase Messaging', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(PushNotificationService.fcmSupported, isFalse);
    expect(PushNotificationService.supported, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(PushNotificationService.supported, isFalse);
  });
  test('Local relay credentials are never sent to a remote backend', () async {
    EnvConfig.configureDeliveryApiRuntime(
      baseUrl: 'https://delivery.example/delivery/',
    );
    var calls = 0;
    final api = DeliveryApiClient(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      api.request('admin/integrations'),
      throwsA(isA<PublicApiException>()),
    );
    await expectLater(
      api.request('admin/integrations', localAuth: true),
      throwsA(isA<PublicApiException>()),
    );
    expect(calls, 0);
  });
  testWidgets(
    'Photon ignores outdated results and does not autocomplete against public demo',
    (tester) async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final controller = TextEditingController(text: 'First query');
      final service = PhotonAddressService(
        api: DeliveryApiClient(
          client: MockClient((request) {
            calls++;
            if (calls == 1) return pending.future;
            return Future.value(
              http.Response(jsonEncode(places('Actual selected address')), 200),
            );
          }),
        ),
      );
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(controller: controller),
                PhotonAddressLookup(
                  controller: controller,
                  service: service,
                  onSelected: (place) => selected = place.address,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Tìm địa chỉ · Photon'));
      await tester.pump();
      controller.text = 'Second query';
      await tester.pump();
      pending.complete(
        http.Response(jsonEncode(places('Outdated address')), 200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Outdated address'), findsNothing);
      await tester.tap(find.text('Tìm địa chỉ · Photon'));
      await tester.pumpAndSettle();
      expect(find.text('Actual selected address'), findsOneWidget);
      await tester.tap(find.text('Actual selected address'));
      await tester.pump();
      expect(selected, 'Actual selected address');
      controller.text = 'Third query';
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'Advanced controls fit width $width and do not call APIs at startup',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var calls = 0;
        final api = DeliveryApiClient(
          client: MockClient((_) async {
            calls++;
            return http.Response('{}', 500);
          }),
        );
        final controller = TextEditingController(text: 'Address');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PhotonAddressLookup(
                        controller: controller,
                        service: PhotonAddressService(api: api),
                        onSelected: (_) {},
                      ),
                      ShippingLabelScanner(api: api, onApply: (_) {}),
                      SupportAiSummary(
                        text: 'Package damaged',
                        onApply: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(calls, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }
}
