import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'delivery_api_client.dart';

@pragma('vm:entry-point')
Future<void> deliveryBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _messages;
  String? _token;
  bool get enabled => _token != null;
  static bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ].contains(defaultTargetPlatform);
  Future<void> enable(ValueChanged<String> onMessage) async {
    if (!supported) {
      throw StateError('Thiết bị này nhận cập nhật qua kết nối realtime.');
    }
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(deliveryBackgroundMessage);
    final permission = await FirebaseMessaging.instance.requestPermission();
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      throw StateError('Quyền thông báo đang tắt.');
    }
    // The Admin SDK sender still targets FCM registration tokens, not FIDs.
    // ignore: deprecated_member_use
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) throw StateError('Chưa lấy được token thiết bị.');
    await DeliveryApiClient.instance.request(
      'push/register',
      body: {'token': token},
    );
    _token = token;
    await _refresh?.cancel();
    await _messages?.cancel();
    // ignore: deprecated_member_use
    _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      try {
        await DeliveryApiClient.instance.request(
          'push/register',
          body: {'token': token},
        );
        final old = _token;
        _token = token;
        if (old != null && old != token) {
          await DeliveryApiClient.instance.request(
            'push/unregister',
            body: {'token': old},
          );
        }
      } catch (_) {
        onMessage('Chưa cập nhật được thông báo thiết bị.');
      }
    });
    _messages = FirebaseMessaging.onMessage.listen(
      (message) => onMessage(
        message.notification?.body ?? 'Đơn hàng vừa được cập nhật.',
      ),
    );
  }

  Future<void> disable() async {
    await _refresh?.cancel();
    await _messages?.cancel();
    final token = _token;
    if (token != null) {
      await DeliveryApiClient.instance.request(
        'push/unregister',
        body: {'token': token},
      );
    }
    _token = null;
  }
}
