import 'local_auth_config_stub.dart'
    if (dart.library.io) 'local_auth_config_io.dart'
    as platform;

Future<Map<String, dynamic>> loadLocalAuthConfig() =>
    platform.loadLocalAuthConfig();

Future<void> saveLocalIntegrationConfig(Map<String, dynamic> values) =>
    platform.saveLocalIntegrationConfig(values);
