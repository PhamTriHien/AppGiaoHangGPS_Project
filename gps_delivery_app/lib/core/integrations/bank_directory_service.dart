import '../network/public_json_api.dart';
import 'delivery_api_client.dart';

class DirectoryBank {
  const DirectoryBank({
    required this.name,
    required this.shortName,
    required this.code,
    required this.bin,
  });

  final String name;
  final String shortName;
  final String code;
  final String bin;
  String get label => '$shortName ($code)';

  bool matches(String query) {
    final value = query.trim().toLowerCase();
    return '$name $shortName $code $bin'.toLowerCase().contains(value);
  }
}

class BankDirectoryService {
  BankDirectoryService({PublicJsonApi? api})
    : _api = api ?? PublicJsonApi.instance;

  static final instance = BankDirectoryService();
  final PublicJsonApi _api;

  Future<List<DirectoryBank>> load() => _api.load(
    DeliveryApiClient.uri('banks'),
    headers: DeliveryApiClient.authorizationHeaders,
    cacheFor: const Duration(hours: 24),
    parse: (json, _) {
      if (json['code'] != '00' || json['data'] is! List) {
        throw const FormatException('Invalid bank directory.');
      }
      final banks = <String, DirectoryBank>{};
      for (final row in json['data'] as List) {
        if (row is! Map<String, dynamic> || row['transferSupported'] != 1) {
          continue;
        }
        final name = row['name']?.toString().trim() ?? '';
        final shortName = row['shortName']?.toString().trim() ?? '';
        final code = row['code']?.toString().trim() ?? '';
        final bin = row['bin']?.toString().trim() ?? '';
        if (name.isEmpty ||
            shortName.isEmpty ||
            code.isEmpty ||
            !RegExp(r'^\d{6}$').hasMatch(bin)) {
          continue;
        }
        banks[bin] = DirectoryBank(
          name: name,
          shortName: shortName,
          code: code,
          bin: bin,
        );
      }
      if (banks.isEmpty) throw const FormatException('Empty bank directory.');
      return banks.values.toList()
        ..sort((a, b) => a.shortName.compareTo(b.shortName));
    },
  );
}
