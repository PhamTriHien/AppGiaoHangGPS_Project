Future<bool> webNotificationsPermitted() async => false;

Future<bool> requestWebNotificationPermission() async => false;

Future<bool> showWebSystemNotification({
  required String title,
  required String body,
  String tag = '',
}) async => false;
