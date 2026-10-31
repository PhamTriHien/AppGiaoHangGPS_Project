import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import 'delivery_api_client.dart';
import '../config/env_config.dart';

class TurnstileChallengeService {
  static Future<String?> obtainOtpGrant() async {
    if (EnvConfig.deliveryApiBaseUrl.isEmpty) return null;
    final api = DeliveryApiClient.instance;
    final policy = await api.request('auth-policy');
    if (policy['turnstileRequired'] != true) return null;
    final session = await api.request('challenge-session', body: {});
    final url = Uri.parse(session['url'] as String);
    final base = Uri.parse(EnvConfig.deliveryApiBaseUrl);
    if (url.origin != base.origin ||
        !url.path.startsWith('/delivery/challenge/')) {
      throw StateError('Địa chỉ xác thực không hợp lệ.');
    }
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw StateError('Không mở được trang xác thực.');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final result = await api.request('challenge-session/${session['id']}');
      if (result['status'] == 'verified') return result['grant'] as String;
    }
    throw TimeoutException('Hết thời gian xác thực chống bot.');
  }
}
