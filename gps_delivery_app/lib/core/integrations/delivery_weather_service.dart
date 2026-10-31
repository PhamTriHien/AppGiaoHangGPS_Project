import '../../domain/entities/geo_point.dart';
import '../network/public_json_api.dart';
import 'delivery_api_client.dart';

class DeliveryWeather {
  const DeliveryWeather({
    required this.forecastAt,
    required this.fetchedAt,
    required this.temperatureCelsius,
    required this.windSpeedMetersPerSecond,
    required this.symbol,
    this.rainNextHourMm,
  });

  final DateTime forecastAt;
  final DateTime fetchedAt;
  final double temperatureCelsius;
  final double windSpeedMetersPerSecond;
  final String symbol;
  final double? rainNextHourMm;

  bool get needsCaution =>
      (rainNextHourMm ?? 0) >= 2.5 ||
      windSpeedMetersPerSecond >= 10.8 ||
      symbol.contains('thunder');
}

class DeliveryWeatherService {
  DeliveryWeatherService({PublicJsonApi? api})
    : _api = api ?? PublicJsonApi.instance;

  static final instance = DeliveryWeatherService();
  final PublicJsonApi _api;

  Future<DeliveryWeather> load(GeoPoint point) async {
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude.abs() > 90 ||
        point.longitude.abs() > 180) {
      throw ArgumentError('Invalid weather coordinates.');
    }
    // A local forecast needs only an area, not the device's exact GPS fix.
    final query = {
      'lat': point.latitude.toStringAsFixed(2),
      'lon': point.longitude.toStringAsFixed(2),
    };
    final uri = DeliveryApiClient.uri('weather', query: query);
    return _api.load(
      uri,
      cacheFor: const Duration(minutes: 15),
      headers: DeliveryApiClient.authorizationHeaders,
      parse: (json, now) {
        final properties = json['properties'] as Map<String, dynamic>;
        final timeseries = properties['timeseries'] as List;
        Map<String, dynamic>? selected;
        DateTime? selectedTime;
        var nearestSeconds = double.infinity;
        for (final item in timeseries) {
          if (item is! Map<String, dynamic>) continue;
          final time = DateTime.tryParse(item['time']?.toString() ?? '');
          if (time == null) continue;
          final difference = time.difference(now).inSeconds.abs();
          if (difference < nearestSeconds) {
            selected = item;
            selectedTime = time;
            nearestSeconds = difference.toDouble();
          }
        }
        if (selected == null || selectedTime == null || nearestSeconds > 7200) {
          throw const FormatException('No current forecast.');
        }
        final data = selected['data'] as Map<String, dynamic>;
        final details = (data['instant'] as Map)['details'] as Map;
        final temperature = (details['air_temperature'] as num).toDouble();
        final wind = (details['wind_speed'] as num).toDouble();
        final nextHour = data['next_1_hours'] as Map?;
        final summary =
            nextHour?['summary'] as Map? ??
            (data['next_6_hours'] as Map?)?['summary'] as Map?;
        final precipitation =
            (nextHour?['details'] as Map?)?['precipitation_amount'];
        final rain = (precipitation as num?)?.toDouble();
        if (!temperature.isFinite ||
            !wind.isFinite ||
            wind < 0 ||
            (rain != null && (!rain.isFinite || rain < 0))) {
          throw const FormatException('Invalid weather readings.');
        }
        return DeliveryWeather(
          forecastAt: selectedTime,
          fetchedAt: now,
          temperatureCelsius: temperature,
          windSpeedMetersPerSecond: wind,
          symbol: summary?['symbol_code']?.toString() ?? '',
          rainNextHourMm: rain,
        );
      },
    );
  }
}
