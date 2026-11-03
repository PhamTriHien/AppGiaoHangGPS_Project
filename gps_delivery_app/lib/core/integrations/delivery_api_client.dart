import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env_config.dart';
import '../network/public_json_api.dart';

class DeliveryApiClient {
  DeliveryApiClient({http.Client? client})
    : _ownsClient = client == null,
      _client = client ?? http.Client();
  static final instance = DeliveryApiClient();
  final bool _ownsClient;
  http.Client _client;
  Future<void>? _refreshingSession;

  /// Replaces the pooled HTTP client after OS background/tab resume so stale
  /// half-closed keep-alive sockets cannot fail the first foreground request.
  void resetConnectionPool() {
    if (!_ownsClient) return;
    final previous = _client;
    _client = http.Client();
    previous.close();
  }

  static Uri uri(String path, {Map<String, String>? query}) {
    final base = EnvConfig.deliveryApiBaseUrl;
    if (base.isEmpty) {
      throw const PublicApiException('Chưa cấu hình máy chủ dịch vụ.');
    }
    return Uri.parse(base.endsWith('/') ? base : '$base/')
        .resolve(path)
        .replace(queryParameters: query);
  }

  static Map<String, String> get authorizationHeaders {
    final loopback = const [
      'localhost',
      '127.0.0.1',
      '::1',
    ].contains(Uri.tryParse(EnvConfig.deliveryApiBaseUrl)?.host);
    String token = loopback ? EnvConfig.otpEmailWebhookToken : '';
    try {
      token =
          Supabase.instance.client.auth.currentSession?.accessToken ?? token;
    } catch (_) {}
    if (token.isEmpty) {
      throw const PublicApiException(
        'Vui lòng đăng nhập tài khoản để tiếp tục.',
      );
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  bool get _hasRefreshableCloudSession {
    try {
      final refresh =
          Supabase.instance.client.auth.currentSession?.refreshToken;
      return refresh != null && refresh.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureFreshCloudSession({bool force = false}) async {
    GoTrueClient? auth;
    Session? session;
    try {
      auth = Supabase.instance.client.auth;
      session = auth.currentSession;
    } catch (_) {
      return false;
    }
    final refreshToken = session?.refreshToken;
    if (session == null || refreshToken == null || refreshToken.isEmpty) {
      return false;
    }
    final expiresAt = session.expiresAt;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiringSoon = expiresAt != null && expiresAt <= nowSeconds + 30;
    if (!force && !session.isExpired && !expiringSoon) {
      return false;
    }
    if (_refreshingSession != null) {
      await _refreshingSession;
      final after = auth.currentSession;
      return after != null && !after.isExpired;
    }
    final operation = () async {
      try {
        await auth!.refreshSession();
      } catch (_) {}
    }();
    _refreshingSession = operation;
    try {
      await operation;
    } finally {
      if (identical(_refreshingSession, operation)) {
        _refreshingSession = null;
      }
    }
    final updated = auth.currentSession;
    return updated != null && !updated.isExpired;
  }

  Future<http.Response> _send(
    Uri requestUri, {
    required Map<String, String> headers,
    required Map<String, dynamic>? body,
    required Duration timeout,
  }) => (body == null
          ? _client.get(requestUri, headers: headers)
          : _client.post(
              requestUri,
              headers: headers,
              body: jsonEncode(body),
            ))
      .timeout(timeout);

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 20),
    bool localAuth = false,
    bool cloudOnly = false,
  }) async {
    final requestUri = uri(path, query: query);
    if (localAuth &&
        !const ['localhost', '127.0.0.1', '::1'].contains(requestUri.host)) {
      throw const PublicApiException(
        'Vui lòng đăng nhập tài khoản để kết nối dịch vụ.',
      );
    }
    if (!localAuth) {
      await _ensureFreshCloudSession();
    }
    if (cloudOnly) {
      try {
        if (Supabase.instance.client.auth.currentSession == null) {
          throw StateError('No cloud session');
        }
      } catch (_) {
        throw const PublicApiException('Vui lòng đăng nhập tài khoản.');
      }
    }
    final effectiveTimeout =
        (path == 'cloud/ai-chat' ||
                path == 'ai/chat' ||
                path == 'support-summary') &&
                timeout == const Duration(seconds: 20)
            ? const Duration(seconds: 90)
            : timeout;
    Map<String, String> buildHeaders() => localAuth
        ? {
            'Authorization': 'Bearer ${EnvConfig.otpEmailWebhookToken}',
            'Content-Type': 'application/json',
          }
        : authorizationHeaders;
    try {
      http.Response response;
      try {
        response = await _send(
          requestUri,
          headers: buildHeaders(),
          body: body,
          timeout: effectiveTimeout,
        );
      } catch (error) {
        if (!_ownsClient || body != null || error is TimeoutException) {
          rethrow;
        }
        resetConnectionPool();
        response = await _send(
          requestUri,
          headers: buildHeaders(),
          body: null,
          timeout: effectiveTimeout,
        );
      }
      if (response.statusCode == 401 &&
          !localAuth &&
          _hasRefreshableCloudSession &&
          await _ensureFreshCloudSession(force: true)) {
        response = await _send(
          requestUri,
          headers: buildHeaders(),
          body: body,
          timeout: effectiveTimeout,
        );
      }
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || value is! Map<String, dynamic>) {
        final message = value is Map ? value['error'] : null;
        throw PublicApiException(
          message is String ? message : 'Dịch vụ chưa khả dụng.',
          statusCode: response.statusCode,
        );
      }
      return value;
    } on PublicApiException {
      rethrow;
    } catch (_) {
      throw const PublicApiException('Không kết nối được máy chủ dịch vụ.');
    }
  }

  Future<Map<String, dynamic>> publicRequest(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 12),
    int maxBytes = 16000,
  }) async {
    final requestUri = uri(path);
    try {
      final response = await _client
          .post(
            requestUri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (response.bodyBytes.length > maxBytes) {
        throw const PublicApiException('Phản hồi máy chủ vượt giới hạn.');
      }
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || value is! Map<String, dynamic>) {
        final message = value is Map ? value['error'] : null;
        throw PublicApiException(
          message is String ? message : 'Dịch vụ chưa khả dụng.',
          statusCode: response.statusCode,
        );
      }
      return value;
    } on PublicApiException {
      rethrow;
    } catch (_) {
      throw const PublicApiException('Không kết nối được máy chủ dịch vụ.');
    }
  }

  Future<Map<String, dynamic>> recognizeLabel(Uint8List image) {
    if (image.length > 5000000) {
      throw const PublicApiException('Chọn ảnh PNG/JPEG tối đa 5 MB.');
    }
    return request(
      'ocr',
      body: {'image': base64Encode(image)},
      timeout: const Duration(seconds: 100),
    );
  }
}
