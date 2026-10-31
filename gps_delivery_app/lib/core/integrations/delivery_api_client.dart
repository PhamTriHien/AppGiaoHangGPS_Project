import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env_config.dart';
import '../network/public_json_api.dart';

class DeliveryApiClient {
  DeliveryApiClient({http.Client? client}) : _client = client ?? http.Client();
  static final instance = DeliveryApiClient();
  final http.Client _client;

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
        'Cần đăng nhập tài khoản cloud để tiếp tục.',
      );
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

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
        'Kết nối backend từ xa cần đăng nhập tài khoản cloud.',
      );
    }
    if (cloudOnly) {
      try {
        if (Supabase.instance.client.auth.currentSession == null) {
          throw StateError('No cloud session');
        }
      } catch (_) {
        throw const PublicApiException('Cần đăng nhập tài khoản cloud.');
      }
    }
    final headers = localAuth
        ? {
            'Authorization': 'Bearer ${EnvConfig.otpEmailWebhookToken}',
            'Content-Type': 'application/json',
          }
        : authorizationHeaders;
    try {
      final response =
          await (body == null
                  ? _client.get(requestUri, headers: headers)
                  : _client.post(
                      requestUri,
                      headers: headers,
                      body: jsonEncode(body),
                    ))
              .timeout(timeout);
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
