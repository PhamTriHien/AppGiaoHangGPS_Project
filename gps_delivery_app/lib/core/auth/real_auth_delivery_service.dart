import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../../domain/enums/user_role.dart';
import '../config/env_config.dart';
import '../integrations/delivery_api_client.dart';
import '../integrations/turnstile_challenge_service.dart';

class OtpDeliveryReceipt {
  final bool success;
  final bool deliveredExternally;
  final String channel;
  final String destination;
  final String message;
  final String? otpCode;

  const OtpDeliveryReceipt({
    required this.success,
    required this.deliveredExternally,
    required this.channel,
    required this.destination,
    required this.message,
    this.otpCode,
  });
}

class GoogleOAuthResult {
  final String email;
  final String fullName;
  final String? phone;
  final SubsystemRole role;
  final String providerSub;

  const GoogleOAuthResult({
    required this.email,
    required this.fullName,
    this.phone,
    this.role = SubsystemRole.customer,
    required this.providerSub,
  });
}

class MobileQrVerificationEvent {
  final String status;
  final String phoneNumber;
  final String deviceUserAgent;
  final String remoteIp;
  final DateTime timestamp;

  const MobileQrVerificationEvent({
    required this.status,
    required this.phoneNumber,
    required this.deviceUserAgent,
    required this.remoteIp,
    required this.timestamp,
  });
}

class MobileQrAuthVerificationResult {
  final bool ok;
  final String? error;
  final bool tokenExpired;
  final String phone;
  final String fullName;
  final String roleTitle;
  final String deviceToken;

  const MobileQrAuthVerificationResult({
    required this.ok,
    this.error,
    this.tokenExpired = false,
    this.phone = '',
    this.fullName = '',
    this.roleTitle = '',
    this.deviceToken = '',
  });
}

class MobileQrAuthSession {
  final String sessionToken;
  final String initialPhone;
  final String lanIp;
  final int port;
  final List<String> allLanIps;

  const MobileQrAuthSession({
    required this.sessionToken,
    required this.initialPhone,
    required this.lanIp,
    required this.port,
    required this.allLanIps,
  });

  String buildVerifyUrl([String? customIp]) {
    final host = (customIp != null && customIp.trim().isNotEmpty)
        ? customIp.trim()
        : lanIp;
    return 'http://$host:$port/q/$sessionToken';
  }
}

class RealAuthDeliveryService {
  RealAuthDeliveryService._();
  static final RealAuthDeliveryService instance = RealAuthDeliveryService._();

  HttpServer? _activeOAuthServer;
  HttpServer? _activeQrAuthServer;
  Process? _activeQrTunnelProcess;

  /// Thực thi gửi mã OTP 6 chữ số qua giao thức SMTP TLS thật (Email) hoặc Đa kênh SMS OTP (eSMS / SpeedSMS / Twilio / Webhook / Thiết bị)
  Future<OtpDeliveryReceipt> deliverOtpChallenge({
    required String destination,
    required String otpCode,
  }) async {
    final target = destination.trim();
    final isEmail = target.contains('@');

    if (isEmail) {
      if (!EnvConfig.isEmailOtpConfigured) {
        return OtpDeliveryReceipt(
          success: false,
          deliveredExternally: false,
          channel: 'SMTP_NOT_CONFIGURED',
          destination: target,
          message: 'Chưa cấu hình dịch vụ gửi Email OTP.',
          otpCode: otpCode,
        );
      }
      return _sendRealSmtpTlsEmail(recipientEmail: target, otpCode: otpCode);
    } else {
      return _dispatchMultiChannelPhoneSmsOtp(
        phoneNumber: target,
        otpCode: otpCode,
      );
    }
  }

  Future<OtpDeliveryReceipt> _sendRealSmtpTlsEmail({
    required String recipientEmail,
    required String otpCode,
  }) => _sendWebEmailOtpRelay(recipientEmail: recipientEmail, otpCode: otpCode);

  /// Chuyển Email OTP tới backend HTTP. Backend chịu trách nhiệm gửi SMTP,
  /// nên mật khẩu SMTP không bao giờ bị đưa vào bundle Web.
  Future<OtpDeliveryReceipt> _sendWebEmailOtpRelay({
    required String recipientEmail,
    required String otpCode,
  }) async {
    try {
      final grant = await TurnstileChallengeService.obtainOtpGrant();
      final headers = <String, String>{'Content-Type': 'application/json'};
      final token = EnvConfig.otpEmailWebhookToken.trim();
      if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      final response = await http
          .post(
            Uri.parse(EnvConfig.otpEmailWebhookUrl),
            headers: headers,
            body: jsonEncode({
              'turnstileGrant': ?grant,
              'to': recipientEmail,
              'otp': otpCode,
              'subject': '[GHST] Mã xác thực OTP của bạn',
              'message':
                  'Mã xác thực OTP GHST của bạn là $otpCode. Mã có hiệu lực trong 120 giây.',
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return OtpDeliveryReceipt(
          success: true,
          deliveredExternally: true,
          channel: 'EMAIL_WEB_RELAY',
          destination: recipientEmail,
          otpCode: otpCode,
          message: 'Đã gửi mã OTP tới Email $recipientEmail.',
        );
      }
      return OtpDeliveryReceipt(
        success: false,
        deliveredExternally: false,
        channel: 'EMAIL_WEB_RELAY_ERROR',
        destination: recipientEmail,
        otpCode: otpCode,
        message: 'Email relay trả về mã HTTP ${response.statusCode}.',
      );
    } catch (error) {
      return OtpDeliveryReceipt(
        success: false,
        deliveredExternally: false,
        channel: 'EMAIL_WEB_RELAY_ERROR',
        destination: recipientEmail,
        otpCode: otpCode,
        message: 'Không kết nối được Email relay: $error',
      );
    }
  }

  Future<OtpDeliveryReceipt> _dispatchMultiChannelPhoneSmsOtp({
    required String phoneNumber,
    required String otpCode,
  }) async {
    final phone = EnvConfig.formatVietnamPhoneE164(phoneNumber);
    try {
      final grant = await TurnstileChallengeService.obtainOtpGrant();
      final response = await DeliveryApiClient.instance.request(
        'local-auth/sms',
        localAuth: true,
        body: {'phone': phone, 'otp': otpCode, 'turnstileGrant': ?grant},
      );
      final accepted = response['accepted'] == true;
      return OtpDeliveryReceipt(
        success: accepted,
        deliveredExternally: accepted,
        channel: response['channel']?.toString() ?? 'SMS_BACKEND',
        destination: phone,
        otpCode: otpCode,
        message: accepted
            ? 'Nhà cung cấp đã tiếp nhận yêu cầu gửi SMS.'
            : 'Chưa gửi được SMS.',
      );
    } catch (_) {
      return OtpDeliveryReceipt(
        success: false,
        deliveredExternally: false,
        channel: 'SMS_BACKEND_ERROR',
        destination: phone,
        otpCode: otpCode,
        message: 'Chưa gửi được SMS. Kiểm tra cấu hình dịch vụ tại backend.',
      );
    }
  }

  Future<bool> verifyTwilioVerifyV2Code({
    required String phoneNumber,
    required String otpCode,
  }) async {
    try {
      final response = await DeliveryApiClient.instance.request(
        'local-auth/sms/verify',
        localAuth: true,
        body: {
          'phone': EnvConfig.formatVietnamPhoneE164(phoneNumber),
          'otp': otpCode,
        },
      );
      return response['approved'] == true;
    } catch (_) {
      return false;
    }
  }

  String? _oauthState;
  String? _codeVerifier;

  bool _isExchangingOAuthCode = false;
  void Function(GoogleOAuthResult result)? _activeOnAuthenticated;
  static const String defaultRedirectUri =
      'http://127.0.0.1:8765/oauth2callback';

  /// Xử lý URL callback chứa `code` từ WebView nhúng hoặc máy chủ Loopback cục bộ
  Future<GoogleOAuthResult?> tryProcessOAuthCallbackUrl(String rawUrl) async {
    if (_isExchangingOAuthCode) return null;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.path != '/oauth2callback') return null;
    final code = uri.queryParameters['code'];
    if (code == null ||
        code.isEmpty ||
        _oauthState == null ||
        uri.queryParameters['state'] != _oauthState) {
      return null;
    }

    _isExchangingOAuthCode = true;
    final authResult = await exchangeGoogleAuthCodeForUserProfile(
      code: code,
      redirectUri: defaultRedirectUri,
    );
    if (authResult != null) {
      final cb = _activeOnAuthenticated;
      _activeOnAuthenticated = null;
      cb?.call(authResult);
      await stopGoogleOAuthServer();
    } else {
      _isExchangingOAuthCode = false;
    }
    return authResult;
  }

  /// Khởi chạy máy chủ HTTP Loopback cục bộ (`127.0.0.1:8765`) và trả về URL `accounts.google.com` để nhúng trực tiếp vào WebView trong ứng dụng
  Future<String?> startGoogleOAuth2LoopbackFlow({
    required void Function(GoogleOAuthResult result) onAuthenticated,
    bool openSystemBrowser = false,
  }) async {
    if (!EnvConfig.isGoogleOAuthConfigured) {
      return null;
    }
    await stopGoogleOAuthServer();
    _isExchangingOAuthCode = false;
    _activeOnAuthenticated = onAuthenticated;

    final random = Random.secure();
    _oauthState = base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    _codeVerifier = base64Url
        .encode(List.generate(48, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(_codeVerifier!)).bytes)
        .replaceAll('=', '');
    final googleAuthUrl = Uri.https(
      'accounts.google.com',
      '/o/oauth2/v2/auth',
      {
        'client_id': EnvConfig.googleClientId,
        'redirect_uri': defaultRedirectUri,
        'response_type': 'code',
        'scope': 'openid email profile',
        'state': _oauthState!,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'prompt': 'select_account',
      },
    ).toString();

    if (!kIsWeb) {
      try {
        final server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          8765,
          shared: true,
        );
        _activeOAuthServer = server;

        server.listen((HttpRequest request) async {
          if (request.uri.path == '/oauth2callback') {
            final fullCallbackUrl =
                'http://127.0.0.1:8765${request.uri.toString()}';
            final authResult = await tryProcessOAuthCallbackUrl(
              fullCallbackUrl,
            );

            request.response.headers.contentType = ContentType(
              'text',
              'html',
              charset: 'utf-8',
            );
            if (authResult != null) {
              request.response.write(_buildOAuthSuccessHtml(authResult));
            } else {
              request.response.write(
                '<html><body style="font-family:sans-serif;padding:40px;">'
                '<h3>Đang đồng bộ phiên đăng nhập Google vào ứng dụng...</h3>'
                '</body></html>',
              );
            }
            await request.response.close();
            return;
          }

          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });
      } catch (_) {}
    }

    if (openSystemBrowser) {
      await launchUrlInSystemBrowser(googleAuthUrl);
    }
    return googleAuthUrl;
  }

  Future<GoogleOAuthResult?> exchangeGoogleAuthCodeForUserProfile({
    required String code,
    required String redirectUri,
  }) async {
    try {
      final infoMap = await DeliveryApiClient.instance.request(
        'local-auth/google/exchange',
        localAuth: true,
        body: {'code': code, 'codeVerifier': _codeVerifier},
      );

      final email = infoMap['email']?.toString() ?? '';
      final name = infoMap['name']?.toString() ?? email.split('@').first;
      final sub = infoMap['sub']?.toString() ?? 'google-$email';
      if (!email.contains('@')) return null;

      return GoogleOAuthResult(email: email, fullName: name, providerSub: sub);
    } catch (_) {
      return null;
    }
  }

  Future<void> stopGoogleOAuthServer() async {
    final srv = _activeOAuthServer;
    _activeOAuthServer = null;
    _oauthState = null;
    _codeVerifier = null;
    if (srv != null) {
      try {
        await srv.close(force: true);
      } catch (_) {}
    }
  }

  Future<void> launchUrlInSystemBrowser(String url) async {
    final parsed = Uri.tryParse(url);
    if (parsed != null) {
      try {
        final launched = await url_launcher.launchUrl(
          parsed,
          mode: url_launcher.LaunchMode.externalApplication,
        );
        if (launched || kIsWeb) return;
      } catch (_) {
        if (kIsWeb) return;
      }
    }
    if (kIsWeb) return;
    try {
      if (Platform.isWindows) {
        final escaped = url.replaceAll("'", "''");
        await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          "Start-Process '$escaped'",
        ]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }

  String _buildOAuthSuccessHtml(GoogleOAuthResult res) {
    const esc = HtmlEscape();
    final safeName = esc.convert(res.fullName);
    final safeEmail = esc.convert(res.email);
    return '''<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="UTF-8">
<title>Đã xác thực Google — GHST</title>
</head>
<body style="margin:0;background:#080B0F;color:#15131E;font-family:Segoe UI,Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;">
  <div style="background:#F5F1E8;border:2px solid #15131E;box-shadow:12px 12px 0 #CBFF3E;max-width:440px;width:100%;padding:28px;text-align:center;">
    <div style="background:#CBFF3E;border:1px solid #15131E;display:inline-block;padding:4px 12px;font-weight:900;font-size:12px;">
      XÁC THỰC GOOGLE THÀNH CÔNG
    </div>
    <h2 style="margin:14px 0 8px;">Xin chào, $safeName!</h2>
    <p style="font-size:14px;color:#333;">Tài khoản <strong>$safeEmail</strong> đã được đồng bộ vào ứng dụng <strong>Giao Hàng Siêu Tốc (GHST)</strong>.</p>
    <p style="font-size:12.5px;color:#555;margin-top:16px;">Bạn có thể đóng tab trình duyệt này và quay lại cửa sổ ứng dụng.</p>
  </div>
</body>
</html>''';
  }

  /// Tự động dò tìm địa chỉ IPv4 mạng LAN/Wi-Fi thực của máy tính (ưu tiên Wi-Fi/Ethernet, loại bỏ VirtualBox/APIPA)
  Future<List<String>> detectBestLanIpv4List() async {
    if (kIsWeb) {
      final host = Uri.base.host.isNotEmpty ? Uri.base.host : '127.0.0.1';
      return [host];
    }
    final scored = <(String ip, int score)>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        final nameLower = iface.name.toLowerCase();
        final isVirtual =
            nameLower.contains('virtual') ||
            nameLower.contains('vbox') ||
            nameLower.contains('vmware') ||
            nameLower.contains('vethernet') ||
            nameLower.contains('wsl') ||
            nameLower.contains('hyper-v') ||
            nameLower.contains('docker') ||
            nameLower.contains('loopback');
        for (final addr in iface.addresses) {
          final ip = addr.address.trim();
          if (ip.isEmpty ||
              ip.startsWith('127.') ||
              ip.startsWith('169.254.') ||
              ip == '192.168.56.1') {
            continue;
          }
          var score = 50;
          if (isVirtual) {
            score = 10;
          } else if (nameLower.contains('wi-fi') ||
              nameLower.contains('wifi') ||
              nameLower.contains('wlan') ||
              nameLower.contains('wireless')) {
            score = 100;
          } else if (nameLower.contains('ethernet') ||
              nameLower.contains('eth') ||
              nameLower.contains('lan')) {
            score = 90;
          } else if (ip.startsWith('192.168.') || ip.startsWith('10.')) {
            score = 80;
          }
          scored.add((ip, score));
        }
      }
    } catch (_) {}

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final uniqueIps = <String>[];
    for (final item in scored) {
      if (!uniqueIps.contains(item.$1)) {
        uniqueIps.add(item.$1);
      }
    }
    if (uniqueIps.isEmpty) {
      uniqueIps.add('127.0.0.1');
    }
    return uniqueIps;
  }

  /// Khởi tạo máy chủ HTTP Đăng nhập QR từ Điện thoại (Xác thực bằng Phiên Thiết bị đã ký số hoặc Mật khẩu thật — Chuẩn Zalo / Shopee)
  Future<MobileQrAuthSession> startMobileQrAuthSession({
    required String initialPhone,
    required void Function(MobileQrVerificationEvent event) onEvent,
    required MobileQrAuthVerificationResult Function({
      required String mode,
      required String phoneOrEmail,
      required String password,
      required String deviceToken,
      required String fullName,
    })
    onAuthenticateMobileRequest,
  }) async {
    await stopMobileQrAuthServer();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final sessionToken = (nowMs % 900000 + 100000).toString();
    final cleanedInitial = initialPhone.trim();
    if (kIsWeb) {
      final host = Uri.base.host.isNotEmpty ? Uri.base.host : '127.0.0.1';
      final port = Uri.base.hasPort ? Uri.base.port : 80;
      return MobileQrAuthSession(
        sessionToken: sessionToken,
        initialPhone: cleanedInitial,
        lanIp: host,
        port: port,
        allLanIps: [host],
      );
    }

    final lanIps = await detectBestLanIpv4List();
    final primaryIp = lanIps.first;

    HttpServer server;
    try {
      server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        8788,
        shared: true,
      );
    } catch (_) {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
    }
    _activeQrAuthServer = server;

    server.listen((HttpRequest req) async {
      req.response.headers.set('Access-Control-Allow-Origin', '*');
      req.response.headers.set(
        'Access-Control-Allow-Methods',
        'GET, POST, OPTIONS',
      );
      req.response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
      if (req.method == 'OPTIONS') {
        req.response.statusCode = HttpStatus.ok;
        await req.response.close();
        return;
      }

      final forwardedFor = req.headers.value('x-forwarded-for');
      final remoteIp = (forwardedFor != null && forwardedFor.trim().isNotEmpty)
          ? '${forwardedFor.split(',').first.trim()} (Internet/4G/Wi-Fi)'
          : (req.connectionInfo?.remoteAddress.address ?? 'Thiết bị di động');
      final userAgent =
          req.headers.value(HttpHeaders.userAgentHeader) ?? 'Mobile Browser';
      final path = req.uri.path;

      if (req.method == 'GET' && (path == '/' || path.startsWith('/q/'))) {
        onEvent(
          MobileQrVerificationEvent(
            status: 'SCANNED',
            phoneNumber: cleanedInitial,
            deviceUserAgent: userAgent,
            remoteIp: remoteIp,
            timestamp: DateTime.now(),
          ),
        );
        req.response.headers.contentType = ContentType(
          'text',
          'html',
          charset: 'utf-8',
        );
        req.response.write(
          _buildMobileQrVerifyHtml(
            sessionToken: sessionToken,
            initialPhone: cleanedInitial,
            remoteIp: remoteIp,
          ),
        );
        await req.response.close();
        return;
      }

      if (req.method == 'POST' && path.endsWith('/confirm')) {
        try {
          final bodyStr = await utf8.decoder.bind(req).join();
          final map = bodyStr.trim().startsWith('{')
              ? (jsonDecode(bodyStr) as Map<String, dynamic>)
              : <String, dynamic>{};
          final mode = (map['mode']?.toString() ?? 'PASSWORD').toUpperCase();
          final rawPhone = map['phone']?.toString().trim() ?? cleanedInitial;
          final rawPassword = map['password']?.toString() ?? '';
          final rawToken = map['deviceToken']?.toString() ?? '';
          final rawFullName = map['fullName']?.toString().trim() ?? '';
          final clientDevice = map['device']?.toString() ?? userAgent;

          final authRes = onAuthenticateMobileRequest(
            mode: mode,
            phoneOrEmail: rawPhone,
            password: rawPassword,
            deviceToken: rawToken,
            fullName: rawFullName,
          );

          req.response.headers.contentType = ContentType(
            'application',
            'json',
            charset: 'utf-8',
          );

          if (!authRes.ok) {
            req.response.write(
              jsonEncode({
                'ok': false,
                'tokenExpired': authRes.tokenExpired,
                'error': authRes.error ?? 'Xác thực không thành công.',
              }),
            );
            await req.response.close();
            return;
          }

          onEvent(
            MobileQrVerificationEvent(
              status: 'CONFIRMED',
              phoneNumber: authRes.phone,
              deviceUserAgent: clientDevice,
              remoteIp: remoteIp,
              timestamp: DateTime.now(),
            ),
          );

          req.response.write(
            jsonEncode({
              'ok': true,
              'phone': authRes.phone,
              'fullName': authRes.fullName,
              'roleTitle': authRes.roleTitle,
              'deviceToken': authRes.deviceToken,
            }),
          );
          await req.response.close();
        } catch (e) {
          req.response.statusCode = HttpStatus.badRequest;
          req.response.write(jsonEncode({'ok': false, 'error': '$e'}));
          await req.response.close();
        }
        return;
      }

      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    });

    _startPublic4gHttpsTunnel(
      port: server.port,
      sessionToken: sessionToken,
      initialPhone: cleanedInitial,
      onEvent: onEvent,
    );

    return MobileQrAuthSession(
      sessionToken: sessionToken,
      initialPhone: cleanedInitial,
      lanIp: primaryIp,
      port: server.port,
      allLanIps: lanIps,
    );
  }

  Future<void> _startPublic4gHttpsTunnel({
    required int port,
    required String sessionToken,
    required String initialPhone,
    required void Function(MobileQrVerificationEvent event) onEvent,
  }) async {
    if (kIsWeb) return;
    try {
      final nullKnownHosts = Platform.isWindows ? 'NUL' : '/dev/null';
      final proc = await Process.start('ssh', [
        '-o',
        'StrictHostKeyChecking=no',
        '-o',
        'UserKnownHostsFile=$nullKnownHosts',
        '-o',
        'ServerAliveInterval=30',
        '-T',
        '-R',
        '80:127.0.0.1:$port',
        'nokey@localhost.run',
      ], runInShell: false);
      _activeQrTunnelProcess = proc;
      bool emitted = false;
      final urlRegex = RegExp(r'https://[a-zA-Z0-9-]+\.lhr\.life');

      void checkChunk(String text) {
        if (emitted) return;
        final match = urlRegex.firstMatch(text);
        if (match != null) {
          final baseUrl = match.group(0);
          if (baseUrl != null && baseUrl.isNotEmpty) {
            emitted = true;
            onEvent(
              MobileQrVerificationEvent(
                status: 'TUNNEL_READY',
                phoneNumber: initialPhone,
                deviceUserAgent: '$baseUrl/q/$sessionToken',
                remoteIp: '4G/Internet HTTPS',
                timestamp: DateTime.now(),
              ),
            );
          }
        }
      }

      proc.stdout.transform(utf8.decoder).listen(checkChunk, onError: (_) {});
      proc.stderr.transform(utf8.decoder).listen(checkChunk, onError: (_) {});
    } catch (_) {}
  }

  Future<void> stopMobileQrAuthServer() async {
    final tunnel = _activeQrTunnelProcess;
    _activeQrTunnelProcess = null;
    if (tunnel != null) {
      try {
        tunnel.kill();
      } catch (_) {}
    }
    final srv = _activeQrAuthServer;
    _activeQrAuthServer = null;
    if (srv != null) {
      try {
        await srv.close(force: true);
      } catch (_) {}
    }
  }

  String _buildMobileQrVerifyHtml({
    required String sessionToken,
    required String initialPhone,
    required String remoteIp,
  }) {
    return '''<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>Đăng Nhập QR Từ Điện Thoại — GHST</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:#0B0F17;color:#15131E;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:14px}
  .card{background:#F5F1E8;border:3px solid #15131E;box-shadow:8px 8px 0 #CBFF3E;border-radius:14px;width:100%;max-width:430px;padding:20px}
  .badge{display:inline-block;background:#CBFF3E;border:1.5px solid #15131E;padding:4px 10px;font-weight:900;font-size:11px;border-radius:6px}
  h1{font-size:18px;font-weight:900;margin:10px 0 5px;color:#15131E}
  .sub{font-size:12px;color:#475569;margin-bottom:12px;line-height:1.4}
  .saved-box{margin-bottom:14px;display:none}
  .saved-title{font-size:11.5px;font-weight:900;color:#15131E;margin-bottom:6px}
  .acc-item{background:#FFF;border:2px solid #15131E;border-radius:10px;padding:10px 12px;margin-bottom:8px;display:flex;justify-content:space-between;align-items:center;cursor:pointer;box-shadow:3px 3px 0 #15131E}
  .acc-item:active{transform:translate(1px,1px);box-shadow:1px 1px 0 #15131E}
  .acc-phone{font-size:14.5px;font-weight:900;color:#15131E}
  .acc-meta{font-size:11px;color:#475569;font-weight:700;margin-top:2px}
  .acc-btn{background:#28A745;color:#FFF;border:1.5px solid #15131E;border-radius:6px;padding:6px 10px;font-size:11.5px;font-weight:900}
  .tabs{display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-bottom:12px}
  .tab{padding:8px;text-align:center;font-size:12px;font-weight:900;background:#FFF;border:2px solid #15131E;border-radius:8px;cursor:pointer}
  .tab.active{background:#CBFF3E}
  label{display:block;font-size:11.5px;font-weight:800;margin:8px 0 4px;color:#15131E}
  input{width:100%;padding:11px 12px;font-size:15px;font-weight:800;border:2px solid #15131E;border-radius:9px;background:#FFF;color:#15131E;outline:none}
  .err-box{display:none;background:#FEE2E2;border:1.5px solid #DC2626;color:#991B1B;border-radius:8px;padding:8px 10px;font-size:11.5px;font-weight:800;margin-top:10px}
  .btn{width:100%;margin-top:14px;padding:14px;background:#15131E;color:#CBFF3E;border:2px solid #15131E;box-shadow:4px 4px 0 #28A745;border-radius:10px;font-size:14px;font-weight:900;cursor:pointer}
  .ok-view{display:none;text-align:center;padding:16px 0}
</style>
</head>
<body>
<div class="card">
  <div id="formView">
    <span class="badge">GHST • ĐĂNG NHẬP QR</span>
    <h1>Duyệt đăng nhập</h1>
    <p class="sub">Xác nhận tài khoản để đăng nhập trên máy tính:</p>

    <div class="saved-box" id="savedBox">
      <div class="saved-title">Tài khoản đã lưu:</div>
      <div id="savedList"></div>
    </div>

    <div class="tabs">
      <div class="tab active" id="tabLogin" onclick="setFormMode('PASSWORD')">Đăng nhập</div>
      <div class="tab" id="tabReg" onclick="setFormMode('REGISTER')">Đăng ký mới</div>
    </div>

    <div id="nameGroup" style="display:none">
      <label for="nameInput">Họ và tên:</label>
      <input id="nameInput" type="text" autocomplete="name" placeholder="Nhập họ và tên" />
    </div>

    <label for="phoneInput">Số điện thoại / Email:</label>
    <input id="phoneInput" type="text" autocomplete="username" placeholder="Nhập SĐT hoặc Email" value="$initialPhone" />

    <label for="pwdInput">Mật khẩu:</label>
    <input id="pwdInput" type="password" autocomplete="current-password" placeholder="Nhập mật khẩu" />

    <div class="err-box" id="errBox"></div>

    <button class="btn" id="submitBtn" onclick="submitCredentials()">Đăng nhập</button>
  </div>

  <div class="ok-view" id="okView">
    <div style="font-size:44px;margin-bottom:8px">✅</div>
    <h1>Đã duyệt đăng nhập!</h1>
    <p class="sub" id="okMsg" style="margin-top:8px;font-size:14px;font-weight:800;color:#15803D"></p>
  </div>
</div>
<script>
  let formMode = 'PASSWORD';
  const errBox = document.getElementById('errBox');

  function loadTrustedAccounts() {
    try {
      const raw = localStorage.getItem('ghst_trusted_accounts');
      return raw ? JSON.parse(raw) : [];
    } catch (_) {
      return [];
    }
  }

  function saveTrustedAccount(acc) {
    const list = loadTrustedAccounts().filter(x => x.phone !== acc.phone);
    list.unshift(acc);
    localStorage.setItem('ghst_trusted_accounts', JSON.stringify(list.slice(0, 5)));
  }

  function removeTrustedAccount(phone) {
    const list = loadTrustedAccounts().filter(x => x.phone !== phone);
    localStorage.setItem('ghst_trusted_accounts', JSON.stringify(list));
    renderSavedAccounts();
  }

  function renderSavedAccounts() {
    const list = loadTrustedAccounts();
    const box = document.getElementById('savedBox');
    const container = document.getElementById('savedList');
    if (!list.length) {
      box.style.display = 'none';
      return;
    }
    box.style.display = 'block';
    container.innerHTML = '';
    list.forEach(item => {
      const row = document.createElement('div');
      row.className = 'acc-item';
      row.onclick = () => quickTokenLogin(item);
      row.innerHTML =
        '<div><div class="acc-phone">' + item.phone + '</div>' +
        '<div class="acc-meta">' + (item.fullName || 'Tài khoản GHST') + ' • ' + (item.roleTitle || 'Đã xác thực') + '</div></div>' +
        '<span class="acc-btn">Đăng nhập</span>';
      container.appendChild(row);
    });
  }

  function setFormMode(m) {
    formMode = m;
    errBox.style.display = 'none';
    document.getElementById('tabLogin').className = 'tab' + (m === 'PASSWORD' ? ' active' : '');
    document.getElementById('tabReg').className = 'tab' + (m === 'REGISTER' ? ' active' : '');
    document.getElementById('nameGroup').style.display = m === 'REGISTER' ? 'block' : 'none';
    document.getElementById('submitBtn').textContent = m === 'REGISTER'
      ? 'Đăng ký & Đăng nhập'
      : 'Đăng nhập';
  }

  function showError(msg) {
    errBox.style.display = 'block';
    errBox.textContent = msg;
  }

  async function quickTokenLogin(item) {
    errBox.style.display = 'none';
    try {
      const res = await fetch('/q/$sessionToken/confirm', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          mode: 'TOKEN',
          phone: item.phone,
          deviceToken: item.deviceToken,
          device: navigator.userAgent
        })
      });
      const data = await res.json();
      if (data.ok) {
        document.getElementById('formView').style.display = 'none';
        document.getElementById('okView').style.display = 'block';
        document.getElementById('okMsg').textContent =
          data.fullName + ' (' + data.phone + ' • ' + data.roleTitle + ')';
      } else {
        if (data.tokenExpired) {
          removeTrustedAccount(item.phone);
          document.getElementById('phoneInput').value = item.phone;
        }
        showError(data.error || 'Không thể duyệt đăng nhập.');
      }
    } catch (e) {
      showError('Lỗi kết nối: ' + e);
    }
  }

  async function submitCredentials() {
    errBox.style.display = 'none';
    const phone = (document.getElementById('phoneInput').value || '').trim();
    const password = (document.getElementById('pwdInput').value || '').trim();
    const fullName = (document.getElementById('nameInput').value || '').trim();
    if (!phone) {
      showError('Vui lòng nhập Số điện thoại hoặc Email.');
      return;
    }
    if (password.length < 6) {
      showError('Vui lòng nhập mật khẩu từ 6 ký tự trở lên.');
      return;
    }
    if (formMode === 'REGISTER' && !fullName) {
      showError('Vui lòng nhập Họ và tên để đăng ký tài khoản mới.');
      return;
    }

    const btn = document.getElementById('submitBtn');
    btn.disabled = true;
    try {
      const res = await fetch('/q/$sessionToken/confirm', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          mode: formMode,
          phone: phone,
          password: password,
          fullName: fullName,
          device: navigator.userAgent
        })
      });
      const data = await res.json();
      btn.disabled = false;
      if (data.ok) {
        saveTrustedAccount({
          phone: data.phone,
          fullName: data.fullName,
          roleTitle: data.roleTitle,
          deviceToken: data.deviceToken
        });
        document.getElementById('formView').style.display = 'none';
        document.getElementById('okView').style.display = 'block';
        document.getElementById('okMsg').textContent =
          data.fullName + ' (' + data.phone + ' • ' + data.roleTitle + ')';
      } else {
        showError(data.error || 'Xác thực thất bại.');
      }
    } catch (e) {
      btn.disabled = false;
      showError('Lỗi kết nối: ' + e);
    }
  }

  renderSavedAccounts();
</script>
</body>
</html>''';
  }
}
