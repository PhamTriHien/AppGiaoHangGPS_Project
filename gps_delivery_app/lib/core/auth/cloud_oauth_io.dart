import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

bool _pending = false;
const _windowChannel = MethodChannel('ghst/window');

String _oauthCallbackHtml({required bool success}) {
  final heading = success
      ? 'Đăng nhập Google thành công'
      : 'Chưa hoàn tất đăng nhập Google';
  final detail = success
      ? 'Phiên xác thực đã được chuyển về ứng dụng GHST EXPRESS trên máy tính. Bạn có thể đóng tab trình duyệt này.'
      : 'Không nhận được mã xác thực hợp lệ từ trình duyệt. Vui lòng quay lại ứng dụng GHST EXPRESS và thử lại.';
  final accent = success ? '#C6FF00' : '#FF5252';
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
  </style>
</head>
<body>
  <main class="card">
    <div class="badge">GHST • GIAO HÀNG SIÊU TỐC</div>
    <h1>$heading</h1>
    <p>$detail</p>
  </main>
  <script>
    if (window.history && window.history.replaceState) {
      window.history.replaceState(null, '', '/auth/callback');
    }
    if (${success ? 'true' : 'false'}) {
      setTimeout(function () { window.close(); }, 300);
    }
  </script>
</body>
</html>''';
}

Future<void> _focusDesktopWindow() async {
  if (!Platform.isWindows) return;
  try {
    await _windowChannel.invokeMethod<void>('focus');
  } catch (_) {}
}

Future<void> signInCloudGoogle(SupabaseClient client) async {
  if (_pending) throw StateError('Authentication already in progress');
  _pending = true;
  HttpServer? listener;
  try {
    listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 8766);
    const redirect = 'http://127.0.0.1:8766/auth/callback';
    final authorization = await client.auth.getOAuthSignInUrl(
      provider: OAuthProvider.google,
      redirectTo: redirect,
    );
    final response = Completer<String>();
    listener.listen((request) async {
      if (request.uri.path != '/auth/callback' || request.method != 'GET') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final code = request.uri.queryParameters['code'];
      final hasCode = code != null && code.isNotEmpty;
      request.response.headers.contentType = ContentType.html;
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.write(_oauthCallbackHtml(success: hasCode));
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
    await client.auth.exchangeCodeForSession(code);
    await _focusDesktopWindow();
  } finally {
    await listener?.close(force: true);
    _pending = false;
  }
}
