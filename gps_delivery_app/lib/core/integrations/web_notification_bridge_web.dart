import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<bool> webNotificationsPermitted() async {
  try {
    return web.Notification.permission == 'granted';
  } catch (_) {
    return false;
  }
}

Future<bool> requestWebNotificationPermission() async {
  try {
    if (web.Notification.permission == 'granted') return true;
    if (web.Notification.permission == 'denied') return false;
    final status = (await web.Notification.requestPermission().toDart).toDart;
    return status == 'granted';
  } catch (_) {
    return false;
  }
}

Future<bool> showWebSystemNotification({
  required String title,
  required String body,
  String tag = '',
}) async {
  if (body.trim().isEmpty) return false;
  try {
    if (web.Notification.permission != 'granted') return false;
    final options = tag.trim().isNotEmpty
        ? web.NotificationOptions(body: body.trim(), tag: tag.trim())
        : web.NotificationOptions(body: body.trim());
    web.Notification(
      title.trim().isEmpty ? 'GHST EXPRESS' : title.trim(),
      options,
    );
    return true;
  } catch (_) {
    return false;
  }
}
