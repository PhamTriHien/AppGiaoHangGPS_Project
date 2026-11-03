import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';

String? _sessionRoot() {
  if (Platform.isWindows) return Platform.environment['LOCALAPPDATA'];
  return Platform.environment['XDG_CONFIG_HOME'] ??
      (Platform.environment['HOME'] == null
          ? null
          : path.join(Platform.environment['HOME']!, '.config'));
}

class _SlotFileStore {
  _SlotFileStore(this.slot);

  final String slot;

  File _file() {
    final root = _sessionRoot();
    if (root == null || root.isEmpty) {
      throw StateError('Application data directory unavailable.');
    }
    return File(path.join(root, 'GHST', 'sessions', '$slot.json'));
  }

  Future<Map<String, dynamic>> readAll() async {
    try {
      final file = _file();
      if (!await file.exists()) return <String, dynamic>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> writeAll(Map<String, dynamic> data) async {
    final file = _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data), flush: true);
  }
}

class _SlotLocalStorage extends LocalStorage {
  _SlotLocalStorage(String slot) : _store = _SlotFileStore(slot);

  static const _sessionKey = 'session';
  final _SlotFileStore _store;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    final map = await _store.readAll();
    final value = map[_sessionKey];
    return value is String && value.isNotEmpty;
  }

  @override
  Future<String?> accessToken() async {
    final map = await _store.readAll();
    final value = map[_sessionKey];
    return value is String ? value : null;
  }

  @override
  Future<void> removePersistedSession() async {
    final map = await _store.readAll();
    if (map.remove(_sessionKey) != null) {
      await _store.writeAll(map);
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    final map = await _store.readAll();
    map[_sessionKey] = persistSessionString;
    await _store.writeAll(map);
  }
}

class _SlotPkceAsyncStorage extends GotrueAsyncStorage {
  _SlotPkceAsyncStorage(String slot) : _store = _SlotFileStore(slot);

  final _SlotFileStore _store;

  @override
  Future<String?> getItem({required String key}) async {
    final map = await _store.readAll();
    final pkce = map['pkce'];
    if (pkce is Map) {
      final value = pkce[key];
      return value is String ? value : null;
    }
    return null;
  }

  @override
  Future<void> removeItem({required String key}) async {
    final map = await _store.readAll();
    final pkce = map['pkce'];
    if (pkce is Map) {
      final updated = Map<String, dynamic>.from(pkce)..remove(key);
      map['pkce'] = updated;
      await _store.writeAll(map);
    }
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    final map = await _store.readAll();
    final existing = map['pkce'];
    final updated = existing is Map
        ? Map<String, dynamic>.from(existing)
        : <String, dynamic>{};
    updated[key] = value;
    map['pkce'] = updated;
    await _store.writeAll(map);
  }
}

FlutterAuthClientOptions buildSupabaseAuthOptions(String? slot) {
  if (slot == null || slot.isEmpty) {
    return const FlutterAuthClientOptions();
  }
  return FlutterAuthClientOptions(
    localStorage: _SlotLocalStorage(slot),
    pkceAsyncStorage: _SlotPkceAsyncStorage(slot),
  );
}
