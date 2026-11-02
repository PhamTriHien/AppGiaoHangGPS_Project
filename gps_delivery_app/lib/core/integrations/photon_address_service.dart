import '../../domain/entities/geo_point.dart';
import 'delivery_api_client.dart';

class PhotonPlace {
  const PhotonPlace(this.title, this.address, this.point);
  final String title;
  final String address;
  final GeoPoint point;
}

class PhotonAddressService {
  PhotonAddressService({DeliveryApiClient? api})
    : _api = api ?? DeliveryApiClient.instance;
  final DeliveryApiClient _api;
  bool autocomplete = false;
  String attribution = 'OpenStreetMap contributors / Photon';

  Future<List<PhotonPlace>> search(String query, {GeoPoint? bias}) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return [];
    final queryParams = <String, String>{
      'q': trimmed,
      if (bias != null) ...{
        'lat': bias.latitude.toStringAsFixed(5),
        'lon': bias.longitude.toStringAsFixed(5),
      },
    };
    final data = await _api.request('places', query: queryParams);
    autocomplete = data['autocomplete'] == true;
    final rawAttribution = data['attribution'];
    if (rawAttribution is String && rawAttribution.trim().isNotEmpty) {
      attribution = rawAttribution.trim();
    }
    return (data['places'] as List).map((item) {
      final row = Map<String, dynamic>.from(item as Map);
      return PhotonPlace(
        row['title'] as String,
        row['address'] as String,
        GeoPoint(
          latitude: (row['latitude'] as num).toDouble(),
          longitude: (row['longitude'] as num).toDouble(),
        ),
      );
    }).toList();
  }

  Future<String> reverseGeocode(GeoPoint point) async {
    final data = await _api.request(
      'reverse',
      query: {
        'lat': point.latitude.toStringAsFixed(5),
        'lon': point.longitude.toStringAsFixed(5),
      },
    );
    final rawAttribution = data['attribution'];
    if (rawAttribution is String && rawAttribution.trim().isNotEmpty) {
      attribution = rawAttribution.trim();
    }
    final address = data['address'];
    return address is String ? address.trim() : '';
  }

  /// All-pairs road distances in meters from the backend routing provider.
  Future<List<List<double>>> roadDistances(List<GeoPoint> points) async {
    final data = await _api.request(
      'matrix',
      query: {
        'full': '1',
        'coordinates': points
            .map(
              (p) =>
                  '${p.longitude.toStringAsFixed(5)},${p.latitude.toStringAsFixed(5)}',
            )
            .join(';'),
      },
    );
    final rows = data['distances'];
    if (data['code'] != 'Ok' || rows is! List || rows.length != points.length) {
      throw const FormatException('Invalid distance matrix.');
    }
    return [
      for (final row in rows)
        if (row is List &&
            row.length == points.length &&
            row.every((v) => v is num && v.isFinite && v >= 0))
          [for (final v in row) (v as num).toDouble()]
        else
          throw const FormatException('Invalid distance matrix row.'),
    ];
  }
}
