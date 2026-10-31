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

  Future<List<PhotonPlace>> search(String query) async {
    if (query.trim().length < 3) return [];
    final data = await _api.request('places', query: {'q': query.trim()});
    autocomplete = data['autocomplete'] == true;
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
}
