import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

bool _pending = false;
const _windowChannel = MethodChannel('ghst/window');
const desktopGoogleRedirectUri = 'http://127.0.0.1:8766/auth/callback';
const mobileGoogleRedirectUri = 'com.giaohanggps.gpsdelivery://auth/callback';
const googleOAuthQueryParams = <String, String>{'prompt': 'select_account'};
const _androidReturnIntentUri =
    'intent://auth/return#Intent;scheme=com.giaohanggps.gpsdelivery;'
    'package=com.giaohanggps.gps_delivery_app;end';

class _OAuthLifecycleWatcher with WidgetsBindingObserver {
  _OAuthLifecycleWatcher({required this.onReturnedWithoutCallback});

  final VoidCallback onReturnedWithoutCallback;
  bool _leftForeground = false;
  Timer? _graceTimer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftForeground = true;
      _graceTimer?.cancel();
      _graceTimer = null;
      return;
    }
    if (state == AppLifecycleState.resumed && _leftForeground) {
      _graceTimer?.cancel();
      _graceTimer = Timer(
        const Duration(milliseconds: 1800),
        onReturnedWithoutCallback,
      );
    }
  }

  void dispose() {
    _graceTimer?.cancel();
    _graceTimer = null;
  }
}

String _oauthCallbackHtml({
  required bool? success,
  required bool androidReturnIntent,
}) {
  final heading = switch (success) {
    true => 'Đăng nhập Google thành công',
    false => 'Chưa hoàn tất đăng nhập Google',
    null => 'Đang chờ xác thực Google',
  };
  final detail = switch (success) {
    true =>
      androidReturnIntent
          ? 'Phiên xác thực đã chuyển về ứng dụng GHST EXPRESS. Hệ thống đang mở lại ứng dụng tự động.'
          : 'Phiên xác thực đã được chuyển về ứng dụng GHST EXPRESS trên máy tính. Bạn có thể đóng tab trình duyệt này.',
    false => 'Không nhận được mã xác thực hợp lệ từ trình duyệt. Vui lòng quay lại ứng dụng GHST EXPRESS và thử lại.',
    null => 'Vui lòng hoàn tất đăng nhập tài khoản Google ở tab xác thực hoặc quay lại ứng dụng GHST EXPRESS.',
  };
  final accent = switch (success) {
    true => '#C6FF00',
    false => '#FF5252',
    null => '#FFD54F',
  };
  final actionButton = androidReturnIntent
      ? '<a class="btn" href="$_androidReturnIntentUri">MỞ ỨNG DỤNG GHST EXPRESS</a>'
      : '';
  final autoScript = switch ((success, androidReturnIntent)) {
    (true, true) =>
      "setTimeout(function () { window.location.replace('$_androidReturnIntentUri'); }, 120);",
    (true, false) => 'setTimeout(function () { window.close(); }, 300);',
    _ => '',
  };
  return '''<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$heading — GHST EXPRESS</title>
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      background: #12131A;
      font-family: "Segoe UI", system-ui, -apple-system, sans-serif;
      color: #111111;
    }
    .card {
      max-width: 460px;
      width: 100%;
      background: #F7F5EE;
      border: 2px solid #111111;
      box-shadow: 6px 6px 0 #111111, 12px 12px 0 #6C3CE9;
      padding: 28px 26px;
      text-align: center;
    }
    .badge {
      display: inline-block;
      background: $accent;
      border: 1.5px solid #111111;
      padding: 4px 10px;
      font-family: Consolas, monospace;
      font-size: 11px;
      font-weight: 900;
      margin-bottom: 16px;
    }
    h1 {
      margin: 0 0 10px;
      font-size: 21px;
      font-weight: 900;
    }
    p {
      margin: 0;
      font-size: 14px;
      line-height: 1.55;
      color: #3B3E4A;
      font-weight: 600;
    }
    .btn {
      display: inline-block;
      margin-top: 20px;
      padding: 12px 18px;
      background: #6C3CE9;
      color: #FFFFFF;
      text-decoration: none;
      font-size: 13px;
      font-weight: 900;
      border: 2px solid #111111;
      box-shadow: 3px 3px 0 #111111;
    }
  </style>
</head>
<body>
  <main class="card">
    <div class="badge">GHST • GIAO HÀNG SIÊU TỐC</div>
    <h1>$heading</h1>
    <p>$detail</p>
    $actionButton
  </main>
  <script>
    if (window.history && window.history.replaceState) {
      window.history.replaceState(null, '', '/auth/done');
    }
    $autoScript
  </script>
</body>
</html>''';
}

Future<void> _setAndroidOAuthKeepAlive(bool active) async {
  if (!Platform.isAndroid) return;
  try {
    await _windowChannel.invokeMethod<bool>(
      active ? 'startOAuthKeepAlive' : 'stopOAuthKeepAlive',
    );
  } catch (_) {}
}

Future<void> _focusAppWindow() async {
  if (!Platform.isWindows && !Platform.isAndroid) return;
  try {
    await _windowChannel.invokeMethod<void>('focus');
  } catch (_) {}
}

Future<void> signInCloudGoogle(SupabaseClient client) async {
  if (_pending) throw StateError('Authentication already in progress');
  _pending = true;
  if (Platform.isIOS) {
    try {
      final launched = await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: mobileGoogleRedirectUri,
        authScreenLaunchMode: LaunchMode.externalApplication,
        queryParams: googleOAuthQueryParams,
      );
      if (!launched) {
        throw StateError('Cannot open browser');
      }
    } finally {
      _pending = false;
    }
    return;
  }
  HttpServer? listener;
  _OAuthLifecycleWatcher? watcher;
  try {
    await _setAndroidOAuthKeepAlive(true);
    listener = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      8766,
      shared: true,
    );
    final authorization = await client.auth.getOAuthSignInUrl(
      provider: OAuthProvider.google,
      redirectTo: desktopGoogleRedirectUri,
      queryParams: googleOAuthQueryParams,
    );
    final response = Completer<String?>();
    if (Platform.isAndroid) {
      watcher = _OAuthLifecycleWatcher(
        onReturnedWithoutCallback: () {
          if (!response.isCompleted) {
            response.complete(null);
          }
        },
      );
      WidgetsBinding.instance.addObserver(watcher);
    }
    listener.listen((request) async {
      if (request.method != 'GET' ||
          (request.uri.path != '/auth/callback' &&
              request.uri.path != '/auth/done')) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.html;
      request.response.headers.set('Cache-Control', 'no-store');
      if (request.uri.path == '/auth/done') {
        request.response.write(
          _oauthCallbackHtml(
            success: true,
            androidReturnIntent: Platform.isAndroid,
          ),
        );
        await request.response.close();
        return;
      }
      final code = request.uri.queryParameters['code'];
      final hasCode = code != null && code.isNotEmpty;
      final oauthError =
          request.uri.queryParameters['error'] ??
          request.uri.queryParameters['error_code'];
      final hasOAuthError = oauthError != null && oauthError.isNotEmpty;
      if (!hasCode && !hasOAuthError) {
        request.response.write(
          _oauthCallbackHtml(
            success: response.isCompleted ? true : null,
            androidReturnIntent: Platform.isAndroid,
          ),
        );
        await request.response.close();
        return;
      }
      request.response.write(
        _oauthCallbackHtml(
          success: hasCode,
          androidReturnIntent: Platform.isAndroid,
        ),
      );
      await request.response.close();
      if (response.isCompleted) return;
      if (!hasCode) {
        response.completeError(
          const AuthException('Google authentication failed'),
        );
      } else {
        response.complete(code);
      }
    });
    // PKCE exchange verifies the locally stored verifier. Userinfo/email alone
    // must never be used to create a Supabase session.
    if (!await launchUrl(
      Uri.parse(authorization.url),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('Cannot open browser');
    }
    final code = await response.future.timeout(const Duration(minutes: 3));
    if (code == null) return;
    await client.auth.exchangeCodeForSession(code);
    await _focusAppWindow();
  } finally {
    if (watcher != null) {
      WidgetsBinding.instance.removeObserver(watcher);
      watcher.dispose();
    }
    await listener?.close(force: true);
    await _setAndroidOAuthKeepAlive(false);
    _pending = false;
  }
}
