import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/env_config.dart';

class LiveDeliveryService extends ChangeNotifier {
  LiveDeliveryService({SupabaseClient? client}) : _providedClient = client;
  static final instance = LiveDeliveryService();
  final SupabaseClient? _providedClient;
  SupabaseClient? get client {
    if (!EnvConfig.isSupabaseConfigured) return null;
    if (_providedClient != null) return _providedClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get signedIn => client?.auth.currentSession != null;
  String get email => client?.auth.currentUser?.email ?? '';
  String get userId => client?.auth.currentUser?.id ?? '';
  String get cloudUrl => EnvConfig.supabaseUrl;
  String get cloudProjectRef {
    final host = Uri.tryParse(cloudUrl)?.host ?? '';
    return host
        .split('.')
        .firstWhere((part) => part.isNotEmpty, orElse: () => 'Chưa xác định');
  }

  String _installationId = '';
  String get installationId => _installationId;

  bool _operator = false;
  String? _operatorScope;
  Session? _operatorSession;
  int _roleGeneration = 0;
  String get _identityScope => '$cloudUrl:$userId';
  bool get isOperator =>
      signedIn &&
      _operator &&
      _operatorScope == _identityScope &&
      identical(_operatorSession, client?.auth.currentSession);
  String status = 'Chưa kết nối trực tuyến';

  Future<void> loadInstallationIdentity() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString('ghst_installation_id');
    _installationId = saved?.trim().isNotEmpty == true
        ? saved!.trim()
        : const Uuid().v4();
    if (saved == null || saved.trim().isEmpty) {
      await preferences.setString('ghst_installation_id', _installationId);
    }
    notifyListeners();
  }

  Future<void> restoreSession() async {
    final generation = ++_roleGeneration;
    final cloud = client;
    final user = cloud?.auth.currentUser;
    final session = cloud?.auth.currentSession;
    final scope = _identityScope;
    _operator = false;
    _operatorScope = null;
    _operatorSession = null;
    if (cloud == null || user == null) {
      status = 'Chưa kết nối trực tuyến';
      notifyListeners();
      return;
    }
    try {
      final rows = await cloud
          .from('delivery_api_profiles')
          .select('role')
          .eq('user_id', user.id);
      if (generation != _roleGeneration ||
          scope != _identityScope ||
          !identical(cloud, client) ||
          !identical(session, cloud.auth.currentSession)) {
        return;
      }
      _operator = rows.any((r) => r['role'] == 'operator');
      _operatorScope = scope;
      _operatorSession = session;
      status = isOperator
          ? 'Đã đăng nhập · Quyền điều hành'
          : 'Đã đăng nhập · Chưa có quyền điều hành';
    } catch (_) {
      if (generation != _roleGeneration ||
          scope != _identityScope ||
          !identical(cloud, client) ||
          !identical(session, cloud.auth.currentSession)) {
        return;
      }
      _operator = false;
      status = 'Đã đăng nhập · Chưa đọc được quyền';
    }
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    final cloud = client;
    if (cloud == null) throw StateError('Chưa cấu hình Supabase.');
    _roleGeneration++;
    _operator = false;
    _operatorScope = null;
    notifyListeners();
    await cloud.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    await restoreSession();
  }

  Future<void> signOut() async {
    _roleGeneration++;
    _operator = false;
    _operatorScope = null;
    status = 'Đã ngắt kết nối';
    notifyListeners();
    await client?.auth.signOut();
  }

  Stream<List<Map<String, dynamic>>> events(String room) {
    final cloud = client;
    if (cloud == null || !signedIn) throw StateError('Vui lòng đăng nhập tài khoản.');
    return cloud
        .from('delivery_live_events')
        .stream(primaryKey: ['id'])
        .eq('room_id', room)
        .order('created_at', ascending: false)
        .limit(100);
  }

  Future<String> memberRole(String room) async {
    final cloud = client!;
    if (isOperator) return 'operator';
    final result = await cloud
        .from('delivery_live_members')
        .select('role')
        .eq('room_id', room)
        .eq('user_id', cloud.auth.currentUser!.id)
        .maybeSingle();
    if (result == null) {
      throw StateError('Tài khoản chưa được cấp quyền cho đơn này.');
    }
    return result['role'] as String;
  }

  Future<void> provisionRoom(String room, String userId, String role) async {
    if (!isOperator || !['customer', 'merchant', 'driver'].contains(role)) {
      throw StateError('Cần quyền điều hành hệ thống.');
    }
    await client!
        .from('delivery_live_rooms')
        .upsert({'id': room}, onConflict: 'id', ignoreDuplicates: true);
    await client!.from('delivery_live_members').upsert({
      'room_id': room,
      'user_id': userId,
      'role': role,
    });
  }

  Future<void> publish(
    String room,
    String kind,
    Map<String, dynamic> payload, {
    String? eventId,
  }) async {
    final cloud = client;
    if (cloud == null || !signedIn) throw StateError('Vui lòng đăng nhập tài khoản.');
    await cloud.from('delivery_live_events').insert({
      'id': eventId ?? const Uuid().v4(),
      'room_id': room,
      'sender_id': cloud.auth.currentUser!.id,
      'kind': kind,
      'payload': payload,
    });
  }

  Future<String> uploadEvidence(
    String room,
    Uint8List bytes,
    String mime,
  ) async {
    if (bytes.length > 5000000 || !['image/jpeg', 'image/png'].contains(mime)) {
      throw ArgumentError('Ảnh không hợp lệ.');
    }
    final path =
        '$room/${const Uuid().v4()}.${mime == 'image/png' ? 'png' : 'jpg'}';
    await client!.storage
        .from('delivery-evidence')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    await publish(room, 'pod', {'path': path});
    return path;
  }

  Future<String> evidenceUrl(String path) =>
      client!.storage.from('delivery-evidence').createSignedUrl(path, 300);
}
