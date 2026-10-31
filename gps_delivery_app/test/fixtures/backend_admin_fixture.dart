import 'dart:async';

import 'package:gps_delivery_app/core/integrations/delivery_api_client.dart';

class BackendAdminFixture extends DeliveryApiClient {
  BackendAdminFixture(this.respond);

  final FutureOr<Map<String, dynamic>> Function(
    String path,
    Map<String, dynamic>? body,
  )
  respond;
  final requests = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 20),
    bool localAuth = false,
    bool cloudOnly = false,
  }) async {
    requests.add({'path': path, 'body': body, 'localAuth': localAuth});
    return respond(path, body);
  }
}
