import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

Future<Map<String, dynamic>> loadLocalAuthConfig() async {
  // Keep local settings outside the release directory so rebuilds preserve them.
  final root = Platform.isWindows
      ? Platform.environment['LOCALAPPDATA']
      : Platform.environment['XDG_CONFIG_HOME'] ??
            (Platform.environment['HOME'] == null
                ? null
                : path.join(Platform.environment['HOME']!, '.config'));
  if (root == null) return {};
  final file = File(path.join(root, 'GHST', 'auth-providers.json'));
  if (!await file.exists()) return {};
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid local authentication configuration.');
  }
  return decoded;
}

Future<void> saveLocalIntegrationConfig(Map<String, dynamic> values) async {
  final existing = await loadLocalAuthConfig();
  final root = Platform.isWindows
      ? Platform.environment['LOCALAPPDATA']
      : Platform.environment['XDG_CONFIG_HOME'] ??
            (Platform.environment['HOME'] == null
                ? null
                : path.join(Platform.environment['HOME']!, '.config'));
  if (root == null) throw StateError('Application data directory unavailable.');
  final directory = Directory(path.join(root, 'GHST'));
  await directory.create(recursive: true);
  final file = File(path.join(directory.path, 'auth-providers.json'));
  await file.writeAsString(jsonEncode({...existing, ...values}), flush: true);
}
