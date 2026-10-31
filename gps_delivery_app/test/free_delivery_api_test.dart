import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/gps/osrm_dispatch_service.dart';
import 'package:gps_delivery_app/core/config/env_config.dart';
import 'package:gps_delivery_app/core/integrations/bank_directory_service.dart';
import 'package:gps_delivery_app/core/integrations/delivery_weather_service.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/presentation/widgets/bank_directory_field.dart';
import 'package:gps_delivery_app/presentation/widgets/delivery_weather_strip.dart';
import 'package:gps_delivery_app/presentation/widgets/road_dispatch_comparison.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const pickup = GeoPoint(latitude: 10.7769, longitude: 106.6953);
const driverPoint = GeoPoint(latitude: 10.7776, longitude: 106.6916);
const candidateA = RoadDispatchCandidate(
  id: 'A',
  name: 'Driver A',
  location: driverPoint,
);
const candidateB = RoadDispatchCandidate(
  id: 'B',
  name: 'Driver B',
  location: pickup,
);

Map<String, dynamic> bankResponse() => {
  'code': '00',
  'data': [
    {
      'name': 'Bank A',
      'shortName': 'Alpha',
      'code': 'AAA',
      'bin': '970001',
      'transferSupported': 1,
    },
    {
      'name': 'Bank B',
      'shortName': 'Beta',
      'code': 'BBB',
      'bin': '970002',
      'transferSupported': 1,
    },
    {
      'name': 'Not transferable',
      'shortName': 'Other',
      'code': 'NO',
      'bin': '970003',
      'transferSupported': 0,
    },
  ],
};

Map<String, dynamic> weatherResponse(
  DateTime time, {
  double rain = 3,
  double wind = 4,
}) => {
  'properties': {
    'timeseries': [
      {
        'time': time.toIso8601String(),
        'data': {
          'instant': {
            'details': {'air_temperature': 29.4, 'wind_speed': wind},
          },
          'next_1_hours': {
            'summary': {'symbol_code': 'rain'},
            'details': {'precipitation_amount': rain},
          },
        },
      },
    ],
  },
};

PublicJsonApi mockApi(
  FutureOr<http.Response> Function(http.Request) handler, {
  DateTime Function()? now,
}) => PublicJsonApi(
  client: MockClient((request) async => handler(request)),
  now: now,
);

http.Response jsonResponse(Object data, {Map<String, String>? headers}) =>
    http.Response(
      jsonEncode(data),
      200,
      headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
    );

void main() {
  setUp(() {
    EnvConfig.configureDeliveryApiRuntime(
      baseUrl: 'http://127.0.0.1:8787/delivery/',
    );
    EnvConfig.configureAuthProvidersRuntime(
      otpEmailWebhookToken: 'test-backend-token',
    );
  });
  test(
    'Concurrent requests share one fetch and cache respects provider expiry',
    () async {
      var now = DateTime.utc(2026, 10, 27, 6);
      var calls = 0;
      final response = Completer<http.Response>();
      final api = mockApi((request) {
        calls++;
        expect(request.headers['User-Agent'], contains('GHSTDelivery'));
        if (calls == 1) return response.future;
        expect(
          request.headers['If-Modified-Since'],
          'Tue, 27 Oct 2026 05:00:00 GMT',
        );
        return http.Response('', 304);
      }, now: () => now);
      final service = BankDirectoryService(api: api);
      final first = service.load();
      final second = service.load();
      response.complete(
        jsonResponse(
          bankResponse(),
          headers: {
            'expires': 'Thu, 29 Oct 2026 06:00:00 GMT',
            'last-modified': 'Tue, 27 Oct 2026 05:00:00 GMT',
          },
        ),
      );
      final results = await Future.wait([first, second]);
      expect(calls, 1);
      expect(results.first.map((b) => b.shortName), ['Alpha', 'Beta']);
      now = now.add(const Duration(hours: 25));
      await service.load();
      expect(calls, 1);
      now = now.add(const Duration(hours: 24));
      expect((await service.load()).length, 2);
      expect(calls, 2);
    },
  );

  test('429 honors Retry-After without sending repeated requests', () async {
    var now = DateTime.utc(2026, 10, 27, 6);
    var calls = 0;
    final service = BankDirectoryService(
      api: mockApi((_) {
        calls++;
        return calls == 1
            ? http.Response('', 429, headers: {'retry-after': '120'})
            : jsonResponse(bankResponse());
      }, now: () => now),
    );
    await expectLater(service.load(), throwsA(isA<PublicApiException>()));
    await expectLater(service.load(), throwsA(isA<PublicApiException>()));
    expect(calls, 1);
    now = now.add(const Duration(seconds: 121));
    expect((await service.load()).length, 2);
    expect(calls, 2);
  });

  test(
    'Invalid bank data is not cached or replaced with sample banks',
    () async {
      var calls = 0;
      final service = BankDirectoryService(
        api: mockApi((_) {
          calls++;
          return calls == 1
              ? jsonResponse({'code': '99', 'data': []})
              : jsonResponse(bankResponse());
        }),
      );
      await expectLater(service.load(), throwsA(isA<PublicApiException>()));
      final banks = await service.load();
      expect(calls, 2);
      expect(banks.singleWhere((b) => b.matches('970001')).shortName, 'Alpha');
      expect(banks.any((b) => b.code == 'NO'), isFalse);
    },
  );

  test(
    'Weather uses an area coordinate and derives caution from actual values',
    () async {
      final now = DateTime.utc(2026, 10, 27, 6);
      final service = DeliveryWeatherService(
        api: mockApi((request) {
          expect(request.url.queryParameters, {
            'lat': '10.78',
            'lon': '106.70',
          });
          return jsonResponse(weatherResponse(now));
        }, now: () => now),
      );
      final result = await service.load(pickup);
      expect(result.rainNextHourMm, 3);
      expect(result.needsCaution, isTrue);
      expect(result.forecastAt, now);
      expect(result.temperatureCelsius, 29.4);
    },
  );

  test('Configured weather proxy uses local relay authentication', () async {
    final previousBase = EnvConfig.deliveryApiBaseUrl;
    final previousToken = EnvConfig.otpEmailWebhookToken;
    addTearDown(() {
      EnvConfig.configureDeliveryApiRuntime(baseUrl: previousBase);
      EnvConfig.configureAuthProvidersRuntime(
        otpEmailWebhookToken: previousToken,
      );
    });
    EnvConfig.configureDeliveryApiRuntime(
      baseUrl: 'http://127.0.0.1:8787/delivery/',
    );
    EnvConfig.configureAuthProvidersRuntime(
      otpEmailWebhookToken: 'test-proxy-token',
    );
    final now = DateTime.utc(2026, 10, 27, 6);
    final service = DeliveryWeatherService(
      api: mockApi((request) {
        expect(request.url.host, '127.0.0.1');
        expect(request.url.path, '/delivery/weather');
        expect(request.headers['Authorization'], 'Bearer test-proxy-token');
        return jsonResponse(weatherResponse(now));
      }, now: () => now),
    );
    expect((await service.load(pickup)).needsCaution, isTrue);
  });

  test(
    'Stale weather and invalid coordinates never produce a current forecast',
    () async {
      final now = DateTime.utc(2026, 10, 27, 6);
      var calls = 0;
      final service = DeliveryWeatherService(
        api: mockApi((_) {
          calls++;
          return jsonResponse(
            weatherResponse(now.subtract(const Duration(days: 1))),
          );
        }, now: () => now),
      );
      expect(
        () => service.load(const GeoPoint(latitude: 100, longitude: 10)),
        throwsArgumentError,
      );
      expect(calls, 0);
      await expectLater(
        service.load(pickup),
        throwsA(isA<PublicApiException>()),
      );
    },
  );

  test(
    'OSRM sends one sources-to-pickup matrix and sorts actual road ETA',
    () async {
      var calls = 0;
      final service = OsrmDispatchService(
        api: mockApi((request) {
          calls++;
          expect(request.url.path, '/delivery/matrix');
          expect(
            request.url.queryParameters['coordinates']!.split(';').length,
            3,
          );
          expect(request.headers['Authorization'], 'Bearer test-backend-token');
          expect(
            request.url.queryParameters.containsKey('fallback_speed'),
            isFalse,
          );
          return jsonResponse({
            'code': 'Ok',
            'durations': [
              [600],
              [180],
            ],
            'distances': [
              [2000],
              [3500],
            ],
          });
        }),
      );
      final results = await service.compare(
        pickup: pickup,
        candidates: [candidateA, candidateB],
      );
      expect(results.first.candidate.id, 'B');
      expect(results.first.distanceMeters, 3500);
      expect(results.first.durationSeconds, 180);
      final renamed = RoadDispatchCandidate(
        id: 'C',
        name: 'New roster',
        location: driverPoint,
      );
      final cached = await service.compare(
        pickup: pickup,
        candidates: [renamed, candidateB],
      );
      expect(calls, 1);
      expect(cached.last.candidate.id, 'C');
    },
  );

  test(
    'Unreachable OSRM destinations stay unreachable with no fabricated ETA',
    () async {
      final service = OsrmDispatchService(
        api: mockApi(
          (_) => jsonResponse({
            'code': 'Ok',
            'durations': [
              [null],
              [120],
            ],
            'distances': [
              [null],
              [800],
            ],
          }),
        ),
      );
      final result = await service.compare(
        pickup: pickup,
        candidates: [candidateA, candidateB],
      );
      expect(result.first.candidate.id, 'B');
      expect(result.last.reachable, isFalse);
      expect(result.last.durationSeconds, isNull);
    },
  );

  test(
    'Invalid or missing OSRM matrix rows fail instead of estimating values',
    () async {
      final service = OsrmDispatchService(
        api: mockApi(
          (_) => jsonResponse({
            'code': 'Ok',
            'durations': [
              [120],
            ],
            'distances': [
              [-1],
            ],
          }),
        ),
      );
      await expectLater(
        service.compare(pickup: pickup, candidates: [candidateA]),
        throwsA(isA<PublicApiException>()),
      );
      await expectLater(
        service.compare(pickup: pickup, candidates: [candidateA, candidateA]),
        throwsArgumentError,
      );
      expect(await service.compare(pickup: pickup, candidates: []), isEmpty);
    },
  );

  for (final width in [360.0, 1440.0]) {
    testWidgets('Forecast and road comparison fit at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final now = DateTime.utc(2026, 10, 27, 6);
      final api = mockApi(
        (request) => request.url.path == '/delivery/weather'
            ? jsonResponse(weatherResponse(now))
            : jsonResponse({
                'code': 'Ok',
                'durations': [
                  [180],
                ],
                'distances': [
                  [1200],
                ],
              }),
        now: () => now,
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DeliveryWeatherStrip(
                      point: pickup,
                      service: DeliveryWeatherService(api: api),
                    ),
                    RoadDispatchComparison(
                      pickup: pickup,
                      candidates: [candidateA],
                      service: OsrmDispatchService(api: api),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('So sánh thời gian đường bộ'));
      await tester.pumpAndSettle();
      expect(find.textContaining('29.4'), findsOneWidget);
      expect(find.textContaining('Mưa hoặc gió mạnh'), findsOneWidget);
      expect(find.text('1.2 km · 3 phút'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_API_UI')) {
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final bitmap = await render.toImage();
          final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/verification/free-api-${width.toInt()}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          bitmap.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'Bank selection searches API data and preserves input at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final controller = TextEditingController(text: 'Existing linked bank');
        addTearDown(controller.dispose);
        final service = BankDirectoryService(
          api: mockApi((_) => jsonResponse(bankResponse())),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: BankDirectoryField(
                  controller: controller,
                  label: 'Bank',
                  service: service,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Chọn ngân hàng'));
        await tester.pumpAndSettle();
        expect(controller.text, 'Existing linked bank');
        await tester.enterText(
          find.widgetWithText(TextField, 'Tên, mã ngân hàng hoặc BIN'),
          '970002',
        );
        await tester.pumpAndSettle();
        expect(find.text('Alpha (AAA)'), findsNothing);
        await tester.tap(find.text('Beta (BBB)'));
        await tester.pumpAndSettle();
        expect(controller.text, 'Beta (BBB)');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Bank API failure permits manual input without sample options', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Keep existing');
    addTearDown(controller.dispose);
    final service = BankDirectoryService(
      api: mockApi((_) => http.Response('', 503)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BankDirectoryField(
            controller: controller,
            label: 'Bank',
            service: service,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Chọn ngân hàng'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa tải được danh sách ngân hàng.'), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Keep existing');
    await tester.enterText(find.byType(TextFormField), 'Manual bank');
    expect(controller.text, 'Manual bank');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Weather stays empty without coordinates and shows real error on failure',
    (tester) async {
      var calls = 0;
      final service = DeliveryWeatherService(
        api: mockApi((_) {
          calls++;
          return http.Response('', 503);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeliveryWeatherStrip(point: null, service: service),
          ),
        ),
      );
      expect(calls, 0);
      expect(find.textContaining('°C'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeliveryWeatherStrip(point: pickup, service: service),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Chưa có dự báo thời tiết.'), findsOneWidget);
      expect(find.textContaining('°C'), findsNothing);
    },
  );

  testWidgets(
    'Weather handles missing backend configuration without a build exception',
    (tester) async {
      final savedBase = EnvConfig.deliveryApiBaseUrl;
      addTearDown(
        () => EnvConfig.configureDeliveryApiRuntime(baseUrl: savedBase),
      );
      EnvConfig.configureDeliveryApiRuntime(baseUrl: '');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DeliveryWeatherStrip(point: pickup)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chưa có dự báo thời tiết.'), findsOneWidget);
      expect(find.textContaining('°C'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Road comparison requires an explicit action and handles empty roster',
    (tester) async {
      var calls = 0;
      final service = OsrmDispatchService(
        api: mockApi((_) {
          calls++;
          return jsonResponse({
            'code': 'Ok',
            'durations': [
              [180],
            ],
            'distances': [
              [1200],
            ],
          });
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoadDispatchComparison(
              pickup: pickup,
              candidates: [],
              service: service,
            ),
          ),
        ),
      );
      expect(calls, 0);
      expect(find.textContaining('GPS đã xác minh'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoadDispatchComparison(
              pickup: pickup,
              candidates: [candidateA],
              service: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.byTooltip('So sánh thời gian đường bộ'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('1.2 km · 3 phút'), findsOneWidget);
      expect(
        find.textContaining('chưa gồm giao thông trực tiếp'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
