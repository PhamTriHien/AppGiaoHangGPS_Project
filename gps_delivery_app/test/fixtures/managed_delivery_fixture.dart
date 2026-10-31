import 'package:gps_delivery_app/core/gps/smart_dispatch_engine.dart';
import 'package:gps_delivery_app/core/integrations/delivery_api_client.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';

// These responses are confined to tests and never seed the application database.
class ManagedDeliveryFixture extends DeliveryApiClient {
  static const places = {
    '145 Phố Huế, Hai Bà Trưng, Hà Nội': GeoPoint(
      latitude: 21.0145,
      longitude: 105.8512,
    ),
    'Số 15, Ngõ 100, Đường Lê Trọng Tấn, Quận Thanh Xuân, Hà Nội': GeoPoint(
      latitude: 20.9951,
      longitude: 105.8286,
    ),
    '123 Đường Lê Lợi Quận 1 TP.HCM': GeoPoint(
      latitude: 10.7738,
      longitude: 106.7030,
    ),
    '123 Lê Lợi, Phường Bến Thành, Quận 1': GeoPoint(
      latitude: 10.7738,
      longitude: 106.7030,
    ),
    '120 Nguyễn Trãi Quận 5 TP.HCM': GeoPoint(
      latitude: 10.7560,
      longitude: 106.6670,
    ),
    '45 Lê Duẩn Quận 1 TP.HCM': GeoPoint(
      latitude: 10.7830,
      longitude: 106.7000,
    ),
    'Cảng Tân Thuận, Khu Chế Xuất Q.7': GeoPoint(
      latitude: 10.7425,
      longitude: 106.7250,
    ),
  };

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 20),
    bool localAuth = false,
    bool cloudOnly = false,
  }) async {
    if (path == 'places') {
      final search = query?['q'] ?? '';
      return {
        'places': [
          for (final e in places.entries)
            if (e.key == search ||
                search == 'Phố Huế' && e.key.startsWith('145 Phố Huế'))
              {
                'title': e.key,
                'address': e.key,
                'latitude': e.value.latitude,
                'longitude': e.value.longitude,
              },
        ],
      };
    }
    if (path == 'route') {
      return {
        'routes': [
          {
            'distance': 14500,
            'duration': 2610,
            'geometry': {
              'coordinates': [
                [105.8512, 21.0145],
                [105.8286, 20.9951],
              ],
            },
          },
        ],
      };
    }
    throw StateError('Unexpected fixture request: $path');
  }

  Future<void> cachePlaces() async {
    for (final address in places.keys) {
      await SmartDispatchEngine.fetchLiveNominatimSuggestions(
        address,
        api: this,
      );
    }
  }
}
