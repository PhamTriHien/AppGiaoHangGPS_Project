import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/gps/osrm_dispatch_service.dart';
import 'package:gps_delivery_app/core/config/env_config.dart';
import 'package:gps_delivery_app/core/config/local_auth_config.dart';
import 'package:gps_delivery_app/core/integrations/bank_directory_service.dart';
import 'package:gps_delivery_app/core/integrations/delivery_weather_service.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';

void main() {
  const runLive = bool.fromEnvironment('RUN_LIVE_API_TESTS');
  setUpAll(() async {
    if (!runLive) return;
    final config = await loadLocalAuthConfig();
    EnvConfig.configureDeliveryApiRuntime(
      baseUrl: config['deliveryApiBaseUrl'] as String? ?? '',
    );
    EnvConfig.configureAuthProvidersRuntime(
      otpEmailWebhookToken: config['otpEmailWebhookToken'] as String?,
    );
  });

  test(
    'Public delivery APIs return live data without API keys',
    () async {
      const pickup = GeoPoint(latitude: 10.7769, longitude: 106.6953);
      final banks = await checked('VietQR', BankDirectoryService.instance.load);
      expect(banks.length, greaterThan(20));
      final weather = await checked(
        'MET Norway',
        () => DeliveryWeatherService.instance.load(pickup),
      );
      expect(
        weather.forecastAt.difference(DateTime.now()).inHours.abs(),
        lessThanOrEqualTo(2),
      );
      expect(weather.temperatureCelsius.isFinite, isTrue);
      final approaches = await checked(
        'OSRM',
        () => OsrmDispatchService.instance.compare(
          pickup: pickup,
          candidates: [
            const RoadDispatchCandidate(
              id: 'probe',
              name: 'Public coordinate probe',
              location: GeoPoint(latitude: 10.7776, longitude: 106.6916),
            ),
          ],
        ),
      );
      expect(approaches.single.reachable, isTrue);
      expect(approaches.single.distanceMeters, greaterThan(0));
      // This opt-in check verifies network integration, not just fixture parsing.
      // ignore: avoid_print
      print(
        'LIVE_API_OK banks=${banks.length} forecast=${weather.forecastAt.toIso8601String()} roadMeters=${approaches.single.distanceMeters}',
      );
    },
    skip: !runLive,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

Future<T> checked<T>(String provider, Future<T> Function() request) async {
  try {
    return await request();
  } on PublicApiException catch (error) {
    fail(
      '$provider: ${error.message} HTTP ${error.statusCode}; ${error.cause}',
    );
  }
}
