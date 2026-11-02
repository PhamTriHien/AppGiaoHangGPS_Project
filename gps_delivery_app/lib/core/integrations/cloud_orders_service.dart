import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/datasources/local/app_state_store.dart';
import '../auth/cloud_oauth.dart';
import '../config/env_config.dart';

import 'delivery_api_client.dart';
import 'live_delivery_service.dart';
import 'push_notification_service.dart';

class CloudOrdersService {
  CloudOrdersService({DeliveryApiClient? api})
    : _api = api ?? DeliveryApiClient.instance;
  final DeliveryApiClient _api;
  final _cloud = LiveDeliveryService.instance;
  bool get signedIn => _cloud.signedIn;
  String get userId => _cloud.userId;
  String get email => _cloud.email;
  String get project => _cloud.cloudProjectRef;
  String get _identityScope => jsonEncode([_cloud.cloudUrl, project, userId]);
  String get identityScope => _identityScope;
  // Supabase replays the latest auth event to new subscribers. Views compare
  // its Session instance with this snapshot to distinguish a new sign-in.
  Session? get authSession => _cloud.client?.auth.currentSession;

  void _requireIdentity(String scope) {
    if (!signedIn || userId.isEmpty || scope != _identityScope) {
      throw StateError('Tài khoản cloud đã thay đổi. Hãy tải lại dữ liệu.');
    }
  }

  Stream<AuthState> get authChanges =>
      _cloud.client?.auth.onAuthStateChange ?? const Stream.empty();

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final scope = _identityScope;
    _requireIdentity(scope);
    final response = await _api.request(
      'cloud/$path',
      body: body,
      query: query,
      cloudOnly: true,
    );
    _requireIdentity(scope);
    return response;
  }

  Future<String?> authenticate(
    String email,
    String password, {
    bool register = false,
  }) async {
    final client = _cloud.client;
    if (client == null) throw StateError('Chưa cấu hình Supabase.');
    if (register) {
      final result = await client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      if (result.session == null) {
        return 'Kiểm tra email để xác nhận tài khoản rồi đăng nhập.';
      }
    } else {
      await _cloud.signIn(email, password);
    }
    return null;
  }

  Future<void> signOut() async {
    final scope = _identityScope;
    try {
      await AppStateStore.instance.disconnectLiveRooms();
      await PushNotificationService.instance.disable();
    } finally {
      if (scope == _identityScope) await _cloud.signOut();
    }
  }

  Future<void> authenticateGoogle() async {
    final client = _cloud.client;
    if (client == null) throw StateError('Authentication unavailable');
    await signInCloudGoogle(client);
  }

  Future<bool> googleSignInAvailable() async {
    if (_cloud.client == null) return false;
    try {
      final response = await http
          .get(
            Uri.parse('${_cloud.cloudUrl}/auth/v1/settings'),
            headers: {'apikey': EnvConfig.supabaseAnonKey},
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200 || response.bodyBytes.length > 100000) {
        return false;
      }
      final settings = jsonDecode(response.body) as Map;
      return (settings['external'] as Map?)?['google'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestPasswordReset(String email) async {
    final client = _cloud.client;
    if (client == null) throw StateError('Authentication unavailable');
    await client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> recoverPassword(
    String email,
    String code,
    String password,
  ) async {
    final client = _cloud.client;
    if (client == null) throw StateError('Authentication unavailable');
    if (password.length < 8) throw ArgumentError('Invalid password');
    final recovery = await client.auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.recovery,
    );
    if (recovery.session == null ||
        !identical(client, _cloud.client) ||
        !identical(recovery.session, client.auth.currentSession)) {
      throw StateError('Recovery session changed');
    }
    await client.auth.updateUser(UserAttributes(password: password));
  }

  Future<void> updatePassword(String password) async {
    final scope = identityScope;
    _requireIdentity(scope);
    if (password.length < 8) throw ArgumentError('Invalid password');
    await _cloud.client!.auth.updateUser(UserAttributes(password: password));
    _requireIdentity(scope);
  }

  Future<Map<String, dynamic>> market(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) => request('marketplace/$action', body: payload);

  Future<Map<String, dynamic>> logistics(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) => request('logistics/$action', body: payload);

  Future<Map<String, dynamic>> adminAccounts(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) => request('admin-accounts/$action', body: payload);

  Future<Map<String, dynamic>> aiChat(List<Map<String, String>> messages) =>
      request('ai-chat', body: {'messages': messages});

  Future<Map<String, dynamic>> publicTracking(String token) => _api
      .publicRequest('tracking', body: {'token': token.trim()}, maxBytes: 4000);

  Future<Map<String, dynamic>> publicLookup(
    String trackingCode,
    String phoneLast4,
  ) => _api.publicRequest(
    'tracking/lookup',
    body: {
      'tracking_code': trackingCode.trim().toUpperCase(),
      'phone_last4': phoneLast4.trim(),
    },
  );

  Future<Map<String, dynamic>> uploadAttachment({
    required String orderId,
    required String scope,
    required Uint8List bytes,
  }) => request(
    'attachments',
    body: {'order_id': orderId, 'scope': scope, 'image': base64Encode(bytes)},
  );

  Future<String> signAttachment(String name) async {
    final res = await request('attachments/sign', body: {'name': name});
    final url = res['url'];
    if (url is! String || Uri.tryParse(url)?.scheme != 'https') {
      throw const FormatException('Invalid signed attachment URL');
    }
    return url;
  }

  Future<String> uploadPod({
    required String trackingCode,
    required Uint8List bytes,
  }) async {
    final res = await request(
      'pod',
      body: {'tracking_code': trackingCode, 'image': base64Encode(bytes)},
    );
    final path = res['path'];
    if (path is! String || path.isEmpty) {
      throw const FormatException('Invalid POD storage path');
    }
    return path;
  }

  Future<String> signPod(String path) async {
    final res = await request('pod/sign', body: {'path': path});
    final url = res['url'];
    if (url is! String || Uri.tryParse(url)?.scheme != 'https') {
      throw const FormatException('Invalid signed POD URL');
    }
    return url;
  }

  Future<Map<String, dynamic>> orderOtp(String orderId) =>
      request('orders/$orderId/otp');

  Future<Map<String, dynamic>> orderShares(
    String orderId, {
    bool create = false,
    String? revokeId,
  }) => revokeId != null
      ? request('orders/$orderId/shares/$revokeId/revoke', body: const {})
      : create
      ? request('orders/$orderId/shares', body: const {})
      : request('orders/$orderId/shares');

  Future<String> startDraft() async {
    final scope = _identityScope;
    _requireIdentity(scope);
    final key = 'ghst_cloud_draft:$project:$userId';
    final preferences = await SharedPreferences.getInstance();
    _requireIdentity(scope);
    final draft = preferences.getString(key) ?? const Uuid().v4();
    await preferences.setString(key, draft);
    _requireIdentity(scope);
    return draft;
  }

  Future<void> completeDraft(String draft) async {
    final scope = _identityScope;
    _requireIdentity(scope);
    final key = 'ghst_cloud_draft:$project:$userId';
    final preferences = await SharedPreferences.getInstance();
    _requireIdentity(scope);
    if (preferences.getString(key) == draft) await preferences.remove(key);
  }

  // Persist just command IDs/hashes: retries after a timeout or restart reuse the
  // same transaction key, without storing recipient data or provider secrets.
  Future<Map<String, dynamic>> command(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final scope = _identityScope;
    _requireIdentity(scope);
    final commandScope = '$project:$userId';
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode([path, payload])))
        .toString();
    final preferences = await SharedPreferences.getInstance();
    _requireIdentity(scope);
    // Preserve keys from earlier builds, including a timed-out order submission.
    final key = 'ghst_cloud_command:$commandScope:$fingerprint';
    var requestKey = preferences.getString(key);
    if (requestKey == null) {
      requestKey = const Uuid().v4();
      await preferences.setString(key, requestKey);
    }
    _requireIdentity(scope);
    final response = await request(
      path,
      body: {...payload, 'request_key': requestKey},
    );
    _requireIdentity(scope);
    return response;
  }
}
