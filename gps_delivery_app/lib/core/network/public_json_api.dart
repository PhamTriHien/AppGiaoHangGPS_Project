import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class PublicApiException implements Exception {
  const PublicApiException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => message;
}

class _CachedPublicResponse {
  const _CachedPublicResponse(this.value, this.expiresAt, this.lastModified);

  final Object value;
  final DateTime expiresAt;
  final String? lastModified;
}

class PublicJsonApi {
  PublicJsonApi({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;

  static final instance = PublicJsonApi();
  static const userAgent =
      'GHSTDelivery/1.0 https://github.com/PhamTriHien/AppGiaoHangGPS_Project';

  final http.Client _client;
  final DateTime Function() _now;
  final Map<Uri, _CachedPublicResponse> _cache = {};
  final Map<Uri, Future<Object>> _pending = {};
  final Map<String, DateTime> _retryAfter = {};

  Future<T> load<T extends Object>(
    Uri uri, {
    required T Function(Map<String, dynamic> json, DateTime fetchedAt) parse,
    required Duration cacheFor,
    Map<String, String> headers = const {},
  }) async {
    final cached = _cache[uri];
    if (cached != null && _now().isBefore(cached.expiresAt)) {
      return cached.value as T;
    }
    final pending = _pending[uri];
    if (pending != null) return await pending as T;
    final retryAt = _retryAfter[uri.host];
    if (retryAt != null && _now().isBefore(retryAt)) {
      throw const PublicApiException(
        'Dịch vụ đang giới hạn yêu cầu. Thử lại sau.',
      );
    }
    final request = _fetch(uri, parse, cacheFor, cached, headers);
    _pending[uri] = request;
    try {
      return await request;
    } finally {
      _pending.remove(uri);
    }
  }

  Future<T> _fetch<T extends Object>(
    Uri uri,
    T Function(Map<String, dynamic>, DateTime) parse,
    Duration cacheFor,
    _CachedPublicResponse? previous,
    Map<String, String> headers,
  ) async {
    try {
      final response = await _client
          .get(
            uri,
            headers: {
              ...headers,
              'Accept': 'application/json',
              if (!kIsWeb) 'User-Agent': userAgent,
              if (previous?.lastModified != null)
                'If-Modified-Since': previous!.lastModified!,
            },
          )
          .timeout(const Duration(seconds: 10));
      final fetchedAt = _now();
      if (response.statusCode == 429) {
        final retrySeconds = int.tryParse(
          response.headers['retry-after'] ?? '',
        );
        _retryAfter[uri.host] = fetchedAt.add(
          Duration(seconds: (retrySeconds ?? 60).clamp(1, 86400)),
        );
        throw const PublicApiException(
          'Dịch vụ đang giới hạn yêu cầu. Thử lại sau.',
          statusCode: 429,
        );
      }
      final unchanged = response.statusCode == 304 && previous != null;
      if (!unchanged && response.statusCode != 200) {
        throw PublicApiException(
          'Không tải được dữ liệu. Vui lòng thử lại.',
          statusCode: response.statusCode,
        );
      }
      final T value;
      if (unchanged) {
        value = previous.value as T;
      } else {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Expected a JSON object.');
        }
        value = parse(decoded, fetchedAt);
      }
      var expiresAt = fetchedAt.add(cacheFor);
      try {
        final serverExpiry = DateFormat(
          "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
          'en_US',
        ).parseUtc(response.headers['expires'] ?? '');
        if (serverExpiry.isAfter(expiresAt)) expiresAt = serverExpiry;
      } on FormatException {
        // The provider may omit Expires; the local TTL still applies.
      }
      if (_cache.length >= 80 && !_cache.containsKey(uri)) {
        _cache.remove(_cache.keys.first);
      }
      _cache[uri] = _CachedPublicResponse(
        value,
        expiresAt,
        response.headers['last-modified'] ?? previous?.lastModified,
      );
      return value;
    } on PublicApiException {
      rethrow;
    } catch (error) {
      throw PublicApiException(
        'Dữ liệu chưa khả dụng hoặc mất kết nối. Vui lòng thử lại.',
        cause: error,
      );
    }
  }
}
