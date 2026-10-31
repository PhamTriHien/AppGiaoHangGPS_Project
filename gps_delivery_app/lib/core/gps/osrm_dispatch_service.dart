import '../../domain/entities/geo_point.dart';
import '../network/public_json_api.dart';
import '../integrations/delivery_api_client.dart';

class RoadDispatchCandidate {
  const RoadDispatchCandidate({
    required this.id,
    required this.name,
    required this.location,
  });

  final String id;
  final String name;
  final GeoPoint location;
}

class RoadApproach {
  const RoadApproach({
    required this.candidate,
    this.distanceMeters,
    this.durationSeconds,
  });

  final RoadDispatchCandidate candidate;
  final double? distanceMeters;
  final double? durationSeconds;
  bool get reachable => distanceMeters != null && durationSeconds != null;
}

class OsrmDispatchService {
  OsrmDispatchService({PublicJsonApi? api})
    : _api = api ?? PublicJsonApi.instance;

  static final instance = OsrmDispatchService();
  final PublicJsonApi _api;

  Future<List<RoadApproach>> compare({
    required GeoPoint pickup,
    required List<RoadDispatchCandidate> candidates,
  }) async {
    if (candidates.isEmpty) return const [];
    if (candidates.length > 10 ||
        candidates.map((c) => c.id).toSet().length != candidates.length) {
      throw ArgumentError('Compare up to ten distinct drivers.');
    }
    final points = [...candidates.map((c) => c.location), pickup];
    if (points.any(
      (p) =>
          !p.latitude.isFinite ||
          !p.longitude.isFinite ||
          p.latitude.abs() > 90 ||
          p.longitude.abs() > 180,
    )) {
      throw ArgumentError('Invalid dispatch coordinates.');
    }
    final coordinates = points
        .map(
          (p) =>
              '${p.longitude.toStringAsFixed(5)},${p.latitude.toStringAsFixed(5)}',
        )
        .join(';');
    final uri = DeliveryApiClient.uri(
      'matrix',
      query: {'coordinates': coordinates},
    );
    // Cache the matrix, not names: a later call may reuse GPS with a new roster.
    final matrix = await _api.load<List<(double?, double?)>>(
      uri,
      headers: DeliveryApiClient.authorizationHeaders,
      cacheFor: const Duration(minutes: 2),
      parse: (json, _) {
        final durations = json['durations'];
        final distances = json['distances'];
        if (json['code'] != 'Ok' ||
            durations is! List ||
            distances is! List ||
            durations.length != candidates.length ||
            distances.length != candidates.length) {
          throw const FormatException('Invalid OSRM matrix.');
        }
        final result = <(double?, double?)>[];
        for (var i = 0; i < candidates.length; i++) {
          final durationRow = durations[i];
          final distanceRow = distances[i];
          if (durationRow is! List ||
              distanceRow is! List ||
              durationRow.length != 1 ||
              distanceRow.length != 1) {
            throw const FormatException('Invalid matrix row.');
          }
          final duration = durationRow.single;
          final distance = distanceRow.single;
          if (duration == null && distance == null) {
            result.add((null, null));
          } else if (duration is num &&
              distance is num &&
              duration.isFinite &&
              distance.isFinite &&
              duration >= 0 &&
              distance >= 0) {
            result.add((distance.toDouble(), duration.toDouble()));
          } else {
            throw const FormatException('Invalid matrix values.');
          }
        }
        return result;
      },
    );
    final results = List.generate(
      candidates.length,
      (i) => RoadApproach(
        candidate: candidates[i],
        distanceMeters: matrix[i].$1,
        durationSeconds: matrix[i].$2,
      ),
    );
    results.sort(
      (a, b) => (a.durationSeconds ?? double.infinity).compareTo(
        b.durationSeconds ?? double.infinity,
      ),
    );
    return results;
  }
}
