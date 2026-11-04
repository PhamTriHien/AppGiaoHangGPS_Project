import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../integrations/cloud_account_session.dart';

class ThemeController extends ChangeNotifier {
  ThemeController({this.session, String? sessionSlot})
    : _prefsKey = sessionSlot == null || sessionSlot.isEmpty
          ? 'ghst_theme_mode'
          : 'ghst_theme_mode:$sessionSlot',
      _aiBubbleKey = sessionSlot == null || sessionSlot.isEmpty
          ? 'ghst_ai_bubble'
          : 'ghst_ai_bubble:$sessionSlot' {
    session?.addListener(_onSessionChanged);
    unawaited(_hydrateLocal());
  }

  final CloudAccountSession? session;
  final String _prefsKey;
  final String _aiBubbleKey;
  ThemeMode _themeMode = ThemeMode.light;
  bool _showAiFloatingBubble = true;
  String _lastSyncedAccountScope = '';
  String? _lastCloudModeApplied;
  bool _disposed = false;

  ThemeMode get themeMode => _themeMode;
  bool get showAiFloatingBubble => _showAiFloatingBubble;

  static ThemeMode parseMode(String? raw) => switch (raw) {
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => ThemeMode.light,
  };

  static String serializeMode(ThemeMode mode) => switch (mode) {
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
    ThemeMode.light => 'light',
  };

  Future<void> _hydrateLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      var changed = false;
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        final parsed = parseMode(saved);
        if (parsed != _themeMode) {
          _themeMode = parsed;
          changed = true;
        }
      }
      final savedBubble = prefs.getBool(_aiBubbleKey);
      if (savedBubble != null && savedBubble != _showAiFloatingBubble) {
        _showAiFloatingBubble = savedBubble;
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (_) {}
  }

  void _onSessionChanged() {
    final s = session;
    if (_disposed || s == null) return;
    if (!s.verified) {
      _lastSyncedAccountScope = '';
      _lastCloudModeApplied = null;
      return;
    }
    final scope = s.service.identityScope;
    final cloudRaw = s.cloudThemeMode;
    if (cloudRaw == null) {
      _lastSyncedAccountScope = scope;
      return;
    }
    if (_lastSyncedAccountScope != scope || _lastCloudModeApplied != cloudRaw) {
      _lastSyncedAccountScope = scope;
      _lastCloudModeApplied = cloudRaw;
      final cloudMode = parseMode(cloudRaw);
      if (cloudMode != _themeMode) {
        _themeMode = cloudMode;
        notifyListeners();
        unawaited(_persistLocal(cloudMode));
      }
    }
  }

  Future<void> _persistLocal(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, serializeMode(mode));
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode, {bool syncCloud = true}) async {
    if (_disposed) return;
    final serialized = serializeMode(mode);
    _lastCloudModeApplied = serialized;
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
    }
    await _persistLocal(mode);
    final s = session;
    if (syncCloud && s != null && s.canUseBusiness) {
      unawaited(s.saveUiPreferences(themeMode: serialized));
    }
  }

  Future<void> cycleThemeMode(BuildContext context) {
    final effectiveDark = Theme.of(context).brightness == Brightness.dark;
    final next = effectiveDark ? ThemeMode.light : ThemeMode.dark;
    return setThemeMode(next);
  }

  Future<void> setShowAiFloatingBubble(bool value) async {
    if (_disposed) return;
    if (_showAiFloatingBubble != value) {
      _showAiFloatingBubble = value;
      notifyListeners();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_aiBubbleKey, value);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    session?.removeListener(_onSessionChanged);
    super.dispose();
  }
}

class ThemeControllerScope extends InheritedNotifier<ThemeController> {
  const ThemeControllerScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeControllerScope>()?.notifier;

  static ThemeController of(BuildContext context) {
    final ctrl = maybeOf(context);
    assert(ctrl != null, 'No ThemeControllerScope found in context.');
    return ctrl!;
  }
}
