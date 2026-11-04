import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_account_session.dart';
import 'delivery_api_client.dart';
import 'web_notification_bridge.dart';

@pragma('vm:entry-point')
Future<void> deliveryBackgroundMessage(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  } catch (_) {}
}

class PushNotificationService extends ChangeNotifier {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  static const MethodChannel _windowChannel = MethodChannel('ghst/window');

  final StreamController<Map<String, dynamic>> _incomingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final Set<Object> _watchers = <Object>{};
  final Set<String> _seenAlertIds = <String>{};

  CloudAccountSession? _boundSession;
  Timer? _pollTimer;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _messages;
  ValueChanged<String>? _legacyMessageHandler;

  String _scope = '';
  String? _token;
  bool _enabled = false;
  bool _polling = false;
  bool _baselineLoaded = false;
  bool _foreground = true;
  int _unreadCount = 0;

  static const Set<String> _mutablePreferenceKeys = {
    'push_enabled',
    'shipping_updates',
    'market_updates',
    'promo_updates',
  };

  Map<String, bool> _preferences = const {
    'push_enabled': true,
    'shipping_updates': true,
    'market_updates': true,
    'promo_updates': true,
  };

  bool get enabled => _enabled;
  int get unreadCount => _unreadCount;
  Map<String, bool> get preferences => Map.unmodifiable(_preferences);
  Stream<Map<String, dynamic>> get incomingAlerts => _incomingController.stream;

  static bool get fcmSupported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ].contains(defaultTargetPlatform);

  static bool get supported =>
      kIsWeb ||
      fcmSupported ||
      defaultTargetPlatform == TargetPlatform.windows;

  Object attachWatcher(CloudAccountSession session) {
    final marker = Object();
    _watchers.add(marker);
    if (!identical(_boundSession, session)) {
      _boundSession?.removeListener(_handleSessionChanged);
      _boundSession = session;
      _boundSession!.addListener(_handleSessionChanged);
      _handleSessionChanged();
    } else {
      _ensurePollingState();
    }
    return marker;
  }

  void detachWatcher(Object marker) {
    _watchers.remove(marker);
    if (_watchers.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  bool _canPollSession(CloudAccountSession? session) =>
      session != null && session.canUseBusiness && session.schemaVersion >= 3;

  void setAppForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
  }

  void applyUnreadCount(int count) {
    final normalized = count < 0 ? 0 : count;
    if (_unreadCount == normalized) return;
    _unreadCount = normalized;
    notifyListeners();
  }

  void applyPreferences(Object? rawPrefs) {
    if (rawPrefs is! Map) return;
    final nextPrefs = <String, bool>{
      'push_enabled': rawPrefs['push_enabled'] != false,
      'shipping_updates': rawPrefs['shipping_updates'] != false,
      'market_updates': rawPrefs['market_updates'] != false,
      'promo_updates': rawPrefs['promo_updates'] != false,
    };
    if (!mapEquals(_preferences, nextPrefs)) {
      _preferences = nextPrefs;
      notifyListeners();
    }
  }

  void _handleSessionChanged() {
    final session = _boundSession;
    if (session == null) return;
    final nextScope = session.service.signedIn
        ? session.service.identityScope
        : '';
    if (_scope != nextScope) {
      _scope = nextScope;
      _unreadCount = 0;
      _baselineLoaded = false;
      _seenAlertIds.clear();
      _enabled = false;
      _preferences = const {
        'push_enabled': true,
        'shipping_updates': true,
        'market_updates': true,
        'promo_updates': true,
      };
      if (nextScope.isNotEmpty) {
        unawaited(_restoreScopeState(nextScope));
      } else {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
      notifyListeners();
    }

    if (session.canUseBusiness) {
      final accountUnread = session.account?['unread_notifications'];
      if (accountUnread is int) {
        final normalized = accountUnread < 0 ? 0 : accountUnread;
        if (_unreadCount != normalized) {
          _unreadCount = normalized;
          notifyListeners();
        }
      }
    }
    _ensurePollingState();
  }

  void _ensurePollingState() {
    final session = _boundSession;
    final shouldPoll = _watchers.isNotEmpty && _canPollSession(session);
    if (!shouldPoll) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    if (_pollTimer == null) {
      unawaited(pollNow());
      _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        if (_foreground || _enabled) {
          unawaited(pollNow());
        }
      });
    }
  }

  Future<void> _restoreScopeState(String scope) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_scope != scope) return;
      final savedPref = prefs.getBool('ghst_push_enabled:$scope');
      final systemPermitted = await areSystemNotificationsPermitted();
      if (_scope != scope) return;
      final nextEnabled = systemPermitted && (savedPref ?? true);
      if (_enabled != nextEnabled) {
        _enabled = nextEnabled;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<bool> areSystemNotificationsPermitted() async {
    if (!supported) return false;
    if (kIsWeb) return webNotificationsPermitted();
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.windows) {
      try {
        return await _windowChannel.invokeMethod<bool>(
              'areNotificationsEnabled',
            ) ??
            false;
      } on MissingPluginException {
        return false;
      } catch (_) {
        return false;
      }
    }
    try {
      if (Firebase.apps.isEmpty) return false;
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestSystemPermission() async {
    if (!supported) return false;
    if (kIsWeb) return requestWebNotificationPermission();
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.windows) {
      try {
        return await _windowChannel.invokeMethod<bool>(
              'requestNotificationPermission',
            ) ??
            false;
      } on MissingPluginException {
        return false;
      } catch (_) {
        return false;
      }
    }
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final permission = await FirebaseMessaging.instance.requestPermission();
      return permission.authorizationStatus == AuthorizationStatus.authorized ||
          permission.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  Future<bool> showSystemNotification({
    required String title,
    required String body,
    String id = '',
  }) async {
    if (!supported || body.trim().isEmpty) return false;
    if (kIsWeb) {
      return showWebSystemNotification(title: title, body: body, tag: id);
    }
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.windows) {
      try {
        return await _windowChannel.invokeMethod<bool>(
              'showLocalNotification',
              {'title': title, 'body': body, 'id': id},
            ) ??
            false;
      } on MissingPluginException {
        return false;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  Future<void> pollNow() async {
    final session = _boundSession;
    if (_polling || !_canPollSession(session)) return;
    final activeSession = session!;
    final scope = activeSession.service.identityScope;
    if (scope.isEmpty || scope != _scope) return;
    _polling = true;
    try {
      final res = await activeSession.service.notifications('unread_count');
      if (scope != _scope || !_canPollSession(activeSession)) return;

      final count = (res['unread_count'] as num? ?? _unreadCount).toInt();
      final rawPrefs = res['preferences'];
      var changed = false;

      if (rawPrefs is Map) {
        final nextPrefs = <String, bool>{
          'push_enabled': rawPrefs['push_enabled'] != false,
          'shipping_updates': rawPrefs['shipping_updates'] != false,
          'market_updates': rawPrefs['market_updates'] != false,
          'promo_updates': rawPrefs['promo_updates'] != false,
        };
        if (!mapEquals(_preferences, nextPrefs)) {
          _preferences = nextPrefs;
          changed = true;
        }
        if (nextPrefs['push_enabled'] == false && _enabled) {
          _enabled = false;
          changed = true;
        } else if (nextPrefs['push_enabled'] == true && !_enabled) {
          final prefs = await SharedPreferences.getInstance();
          final localPref = prefs.getBool('ghst_push_enabled:$scope');
          if (localPref != false && await areSystemNotificationsPermitted()) {
            _enabled = true;
            changed = true;
          }
        }
      }

      if (_unreadCount != count) {
        _unreadCount = count < 0 ? 0 : count;
        changed = true;
      }

      final latest = res['latest'];
      if (latest is Map) {
        final item = Map<String, dynamic>.from(latest);
        final id = '${item['id'] ?? ''}'.trim();
        if (id.isNotEmpty) {
          final isNew = _seenAlertIds.add(id);
          if (_seenAlertIds.length > 200) {
            _seenAlertIds.remove(_seenAlertIds.first);
          }
          if (_baselineLoaded && isNew && item['read_at'] == null) {
            final title = '${item['title'] ?? 'GHST EXPRESS'}'.trim();
            final body = '${item['body'] ?? ''}'.trim();
            _incomingController.add(item);
            _legacyMessageHandler?.call(body.isNotEmpty ? body : title);
            if (_enabled && _preferences['push_enabled'] != false) {
              unawaited(
                showSystemNotification(
                  title: title.isEmpty ? 'GHST EXPRESS' : title,
                  body: body.isEmpty ? title : body,
                  id: id,
                ),
              );
            }
            final category = '${item['category'] ?? ''}';
            if (['account', 'promo', 'shipping'].contains(category)) {
              unawaited(session.refresh().catchError((Object _) {}));
            }
          }
        }
      }

      _baselineLoaded = true;
      if (changed) notifyListeners();
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  Future<void> _tryRegisterFcm(ValueChanged<String>? onMessage) async {
    if (!fcmSupported) {
      return;
    }
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(deliveryBackgroundMessage);
      final permission = await FirebaseMessaging.instance.requestPermission();
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await DeliveryApiClient.instance.request(
        'push/register',
        body: {'token': token},
      );
      _token = token;
      await _refresh?.cancel();
      await _messages?.cancel();
      // ignore: deprecated_member_use
      _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((next) async {
        try {
          await DeliveryApiClient.instance.request(
            'push/register',
            body: {'token': next},
          );
          final old = _token;
          _token = next;
          if (old != null && old != next) {
            await DeliveryApiClient.instance.request(
              'push/unregister',
              body: {'token': old},
            );
          }
        } catch (_) {
          onMessage?.call('Chưa cập nhật được thông báo thiết bị.');
        }
      });
      _messages = FirebaseMessaging.onMessage.listen((message) {
        final title = message.notification?.title ?? 'GHST EXPRESS';
        final body =
            message.notification?.body ?? 'Đơn hàng vừa được cập nhật.';
        onMessage?.call(body);
        unawaited(showSystemNotification(title: title, body: body));
        unawaited(pollNow());
      });
    } catch (_) {}
  }

  Future<void> enable([ValueChanged<String>? onMessage]) async {
    if (!supported) {
      throw StateError('Thiết bị này nhận cập nhật qua kết nối trực tiếp.');
    }
    if (onMessage != null) _legacyMessageHandler = onMessage;
    final permitted = await requestSystemPermission();
    if (!permitted) {
      throw StateError(
        kIsWeb
            ? 'Trình duyệt đang tắt quyền thông báo. Vui lòng cho phép thông báo trên thanh địa chỉ.'
            : 'Quyền thông báo đang tắt trên thiết bị. Vui lòng bật quyền thông báo cho GHST EXPRESS.',
      );
    }

    await _tryRegisterFcm(onMessage);

    final scope = _scope;
    if (scope.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('ghst_push_enabled:$scope', true);
      } catch (_) {}
    }

    _enabled = true;
    _preferences = {..._preferences, 'push_enabled': true};
    notifyListeners();

    final session = _boundSession;
    if (session != null && session.canUseBusiness) {
      try {
        await session.service.notifications('save_preferences', {
          'push_enabled': true,
        });
      } catch (_) {}
      unawaited(pollNow());
    }
  }

  Future<void> disable({bool clearRemotePreference = false}) async {
    await _refresh?.cancel();
    await _messages?.cancel();
    _refresh = null;
    _messages = null;
    final token = _token;
    _token = null;
    if (token != null) {
      try {
        await DeliveryApiClient.instance.request(
          'push/unregister',
          body: {'token': token},
        );
      } catch (_) {}
    }

    if (clearRemotePreference) {
      final scope = _scope;
      if (scope.isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('ghst_push_enabled:$scope', false);
        } catch (_) {}
      }
      _preferences = {..._preferences, 'push_enabled': false};
      final session = _boundSession;
      if (session != null && session.canUseBusiness) {
        try {
          await session.service.notifications('save_preferences', {
            'push_enabled': false,
          });
        } catch (_) {}
      }
    }

    if (_enabled) {
      _enabled = false;
      notifyListeners();
    }
  }

  Future<Map<String, bool>> updatePreferences(
    Map<String, bool> patch, {
    CloudAccountSession? session,
  }) async {
    final targetSession = session ?? _boundSession;
    if (targetSession == null || !targetSession.canUseBusiness) {
      throw StateError('Phiên tài khoản chưa sẵn sàng.');
    }
    final sanitized = <String, bool>{
      for (final entry in patch.entries)
        if (_mutablePreferenceKeys.contains(entry.key)) entry.key: entry.value,
    };
    if (sanitized['push_enabled'] == true && !_enabled) {
      await enable();
    } else if (sanitized['push_enabled'] == false && _enabled) {
      await disable(clearRemotePreference: true);
    }
    final res = await targetSession.service.notifications(
      'save_preferences',
      sanitized,
    );
    final raw = res['preferences'];
    if (raw is Map) {
      _preferences = {
        'push_enabled': raw['push_enabled'] != false,
        'shipping_updates': raw['shipping_updates'] != false,
        'market_updates': raw['market_updates'] != false,
        'promo_updates': raw['promo_updates'] != false,
      };
      if (_preferences['push_enabled'] == false) {
        _enabled = false;
      }
      final scope = _scope;
      if (scope.isNotEmpty && sanitized.containsKey('push_enabled')) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(
            'ghst_push_enabled:$scope',
            _preferences['push_enabled'] == true,
          );
        } catch (_) {}
      }
      notifyListeners();
    }
    return Map<String, bool>.unmodifiable(_preferences);
  }
}
