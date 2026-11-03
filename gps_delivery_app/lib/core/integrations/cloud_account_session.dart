import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_orders_service.dart';
import '../network/public_json_api.dart';

enum CloudAccountPhase {
  signedOut,
  loading,
  incomplete,
  active,
  blocked,
  unavailable,
}

/// Server-verified account state. No SQLite identity or client-selected role is
/// used here, and an older request cannot restore privileges after sign-out.
class CloudAccountSession extends ChangeNotifier {
  CloudAccountSession({required this.service});

  final CloudOrdersService service;
  StreamSubscription<AuthState>? _auth;
  Future<void>? _pending;
  bool _disposed = false, _started = false, _saving = false;
  int _epoch = 0;
  String _scope = '';
  String? _permissions;
  Map<String, dynamic>? _account;
  bool _operator = false;
  int _schemaVersion = 1, _revision = 0;
  Object? _error;
  CloudAccountPhase _phase = CloudAccountPhase.signedOut;

  CloudAccountPhase get phase => _phase;
  Map<String, dynamic>? get account => verified ? _account : null;
  bool get isOperator => verified && _operator;
  bool get canUseBusiness =>
      verified && _account != null && _account!['blocked'] != true;
  Set<String> get approvedRoles => !canUseBusiness
      ? const {}
      : Set.unmodifiable({
          'customer',
          if (_schemaVersion >= 3)
            ...(_account!['approved_roles'] as List).cast<String>()
          else if (_account!['role'] != 'customer')
            _account!['role'] as String,
        });
  bool hasRole(String role) => approvedRoles.contains(role);
  List<Map<String, dynamic>> get staffShops => !canUseBusiness
      ? const []
      : List<Map<String, dynamic>>.unmodifiable(
          (_account!['staff_shops'] as List? ?? const [])
              .cast<Map<String, dynamic>>(),
        );
  bool get hasStaffShop => staffShops.isNotEmpty;
  bool get hasStaffManagerShop =>
      staffShops.any((shop) => shop['role'] == 'manager');
  bool isStaffOfShop(String? shopId) =>
      shopId != null && staffShops.any((shop) => shop['shop_id'] == shopId);
  bool isManagerOfShop(String? shopId) =>
      shopId != null &&
      staffShops.any(
        (shop) => shop['shop_id'] == shopId && shop['role'] == 'manager',
      );
  bool canManageShop(String? shopId) =>
      hasRole('merchant') || isManagerOfShop(shopId);
  bool get hasMerchantAccess => hasRole('merchant') || hasStaffShop;
  int get coinBalance =>
      !canUseBusiness ? 0 : (_account!['coin_balance'] as int? ?? 0);
  String? get birthDate =>
      !canUseBusiness ? null : _account!['birth_date'] as String?;
  String? get citizenId =>
      !canUseBusiness ? null : _account!['citizen_id'] as String?;
  bool get identityVerified =>
      canUseBusiness && _account!['identity_verified'] == true;
  int get unreadNotifications =>
      !canUseBusiness ? 0 : (_account!['unread_notifications'] as int? ?? 0);
  bool get canCreateShippingOrder =>
      canUseBusiness && (_schemaVersion >= 3 || _account!['role'] != 'driver');
  int get schemaVersion => _schemaVersion;
  int get revision => _revision;
  Object? get error => _error;
  bool get verified =>
      !_disposed &&
      service.signedIn &&
      _scope == service.identityScope &&
      [
        CloudAccountPhase.incomplete,
        CloudAccountPhase.active,
        CloudAccountPhase.blocked,
      ].contains(_phase);

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _scope = service.identityScope;
    _phase = service.signedIn
        ? CloudAccountPhase.loading
        : CloudAccountPhase.signedOut;
    _auth = service.authChanges.listen(
      (state) {
        if (_disposed) return;
        if (_scope != service.identityScope ||
            !service.signedIn ||
            state.event == AuthChangeEvent.signedOut) {
          _invalidate();
        }
        if (service.signedIn) {
          unawaited(refresh().catchError((Object _) {}));
        }
      },
      onError: (Object error) {
        if (!_disposed) _invalidate(error: error);
      },
    );
  }

  void _invalidate({Object? error}) {
    _epoch++;
    _revision++;
    _scope = service.identityScope;
    _pending = null;
    _account = null;
    _operator = false;
    _schemaVersion = 1;
    _permissions = null;
    _error = error;
    _phase = !service.signedIn
        ? CloudAccountPhase.signedOut
        : error != null
        ? CloudAccountPhase.unavailable
        : CloudAccountPhase.loading;
    notifyListeners();
  }

  void invalidateVerification({Object? error}) {
    if (_disposed) return;
    start();
    _invalidate(error: error);
  }

  bool _current(int epoch, String scope) =>
      !_disposed &&
      service.signedIn &&
      epoch == _epoch &&
      scope == service.identityScope &&
      scope == _scope;

  void _accept(Map<String, dynamic> response) {
    final raw = response['account'];
    final schema = response['schema_version'];
    if (response['operator'] is! bool ||
        schema is! int ||
        schema < 1 ||
        raw != null &&
            (raw is! Map ||
                raw['user_id'] != service.userId ||
                !['customer', 'merchant', 'driver'].contains(raw['role']) ||
                raw['blocked'] != null && raw['blocked'] is! bool ||
                raw['requested_role'] != null &&
                    !['merchant', 'driver'].contains(raw['requested_role']) ||
                raw['birth_date'] != null &&
                    (raw['birth_date'] is! String ||
                        !RegExp(
                          r'^\d{4}-\d{2}-\d{2}$',
                        ).hasMatch(raw['birth_date'] as String)) ||
                raw['citizen_id'] != null &&
                    (raw['citizen_id'] is! String ||
                        !RegExp(
                          r'^\d{12}$',
                        ).hasMatch(raw['citizen_id'] as String)) ||
                raw['identity_verified'] != null &&
                    raw['identity_verified'] is! bool ||
                raw['unread_notifications'] != null &&
                    (raw['unread_notifications'] is! int ||
                        (raw['unread_notifications'] as int) < 0))) {
      throw const FormatException('Invalid cloud account profile');
    }
    var account = raw == null
        ? null
        : Map<String, dynamic>.unmodifiable(
            Map<String, dynamic>.from(raw as Map),
          );
    if (schema >= 3 && account != null) {
      final roles = account['approved_roles'];
      final memberships = account['memberships'];
      if (roles is! List ||
          memberships is! List ||
          roles.length > 2 ||
          memberships.length > 2 ||
          roles.toSet().length != roles.length ||
          roles.any((role) => !['merchant', 'driver'].contains(role)) ||
          memberships.any(
            (m) =>
                m is! Map ||
                !['merchant', 'driver'].contains(m['role']) ||
                ![
                  'pending',
                  'active',
                  'rejected',
                  'revoked',
                ].contains(m['state']) ||
                m['version'] is! int ||
                (m['version'] as int) < 1,
          ) ||
          memberships.map((m) => (m as Map)['role']).toSet().length !=
              memberships.length ||
          !setEquals(
            roles.toSet(),
            memberships
                .where((m) => m['state'] == 'active')
                .map((m) => m['role'])
                .toSet(),
          )) {
        throw const FormatException('Invalid partner memberships');
      }
      final rawStaff = account['staff_shops'] ?? const <dynamic>[];
      final rawCoins = account['coin_balance'] ?? 0;
      if (rawStaff is! List ||
          rawStaff.any(
            (s) =>
                s is! Map ||
                s['shop_id'] is! String ||
                s['shop_name'] is! String ||
                !['manager', 'staff'].contains(s['role']),
          ) ||
          rawCoins is! int ||
          rawCoins < 0) {
        throw const FormatException('Invalid delegated shop or coin state');
      }
      account = Map<String, dynamic>.unmodifiable({
        ...account,
        'approved_roles': List<String>.unmodifiable(roles.cast<String>()),
        'memberships': List<Map<String, dynamic>>.unmodifiable(
          memberships.map(
            (m) => Map<String, dynamic>.unmodifiable(
              Map<String, dynamic>.from(m as Map),
            ),
          ),
        ),
        'staff_shops': List<Map<String, dynamic>>.unmodifiable(
          rawStaff.map(
            (s) => Map<String, dynamic>.unmodifiable(
              Map<String, dynamic>.from(s as Map),
            ),
          ),
        ),
        'coin_balance': rawCoins,
      });
    }
    final operator = response['operator'] as bool;
    final partnerRoles = schema >= 3 && account != null
        ? (List<String>.from(
            account['approved_roles'] as List,
          )..sort()).join(',')
        : '';
    final staffKey = schema >= 3 && account != null
        ? (List<String>.from(
            (account['staff_shops'] as List? ?? const []).map(
              (s) => '${(s as Map)['shop_id']}:${s['role']}',
            ),
          )..sort()).join(',')
        : '';
    final permissions =
        '${account?['role']}:${account?['blocked'] == true}:$operator:$schema:${account != null}:$partnerRoles:$staffKey';
    if (_permissions != null && _permissions != permissions) _revision++;
    _permissions = permissions;
    _account = account;
    _operator = operator;
    _schemaVersion = schema;
    _error = null;
    _phase = account == null
        ? CloudAccountPhase.incomplete
        : account['blocked'] == true
        ? CloudAccountPhase.blocked
        : CloudAccountPhase.active;
    notifyListeners();
  }

  Future<void> refresh() {
    start();
    if (_disposed) return Future.error(StateError('Session disposed'));
    if (_scope != service.identityScope ||
        !service.signedIn && _phase != CloudAccountPhase.signedOut) {
      _invalidate();
    }
    if (!service.signedIn) return Future.value();
    if (_pending != null) return _pending!;
    final epoch = _epoch, scope = _scope;
    late final Future<void> operation;
    operation = _load(epoch, scope).whenComplete(() {
      if (identical(_pending, operation)) _pending = null;
    });
    _pending = operation;
    return operation;
  }

  bool _isTransientRefreshError(Object error) {
    if (error is TimeoutException) return true;
    if (error is PublicApiException) {
      final code = error.statusCode;
      return code == null ||
          code == 408 ||
          code == 429 ||
          code == 502 ||
          code == 504;
    }
    return false;
  }

  Future<void> _load(int epoch, String scope) async {
    try {
      final response = await service.request('profile');
      if (_current(epoch, scope)) _accept(response);
    } catch (error) {
      if (_current(epoch, scope) &&
          !(verified && _isTransientRefreshError(error))) {
        _fail(error);
      }
      rethrow;
    }
  }

  void _fail(Object error) {
    _account = null;
    _operator = false;
    _permissions = null;
    _schemaVersion = 1;
    _error = error;
    _phase = CloudAccountPhase.unavailable;
    _revision++;
    notifyListeners();
  }

  static bool _isValidIsoBirthDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final y = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    final d = int.parse(match.group(3)!);
    final parsed = DateTime.utc(y, m, d);
    if (parsed.year != y || parsed.month != m || parsed.day != d) return false;
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    return !parsed.isBefore(DateTime.utc(1900, 1, 1)) &&
        !parsed.isAfter(today);
  }

  Future<void> saveProfile({
    required String fullName,
    required String phone,
    required String requestedRole,
    String? birthDate,
    String? citizenId,
  }) async {
    start();
    if (_disposed || _saving) throw StateError('Profile update unavailable');
    final epoch = _epoch, scope = _scope;
    final normalizedBirthDate = birthDate?.trim();
    final normalizedCitizenId = citizenId?.trim();
    if (!service.signedIn ||
        fullName.trim().isEmpty ||
        fullName.trim().length > 120 ||
        !RegExp(r'^0[35789][0-9]{8}$').hasMatch(phone.trim()) ||
        !['customer', 'merchant', 'driver'].contains(requestedRole) ||
        (normalizedBirthDate != null &&
            normalizedBirthDate.isNotEmpty &&
            !_isValidIsoBirthDate(normalizedBirthDate)) ||
        (normalizedCitizenId != null &&
            normalizedCitizenId.isNotEmpty &&
            !RegExp(r'^\d{12}$').hasMatch(normalizedCitizenId))) {
      throw ArgumentError('Invalid account details');
    }
    _saving = true;
    try {
      final response = await service.request(
        'profile',
        body: {
          'full_name': fullName.trim(),
          'phone': phone.trim(),
          'requested_role': requestedRole,
          'birth_date': ?normalizedBirthDate,
          'citizen_id': ?normalizedCitizenId,
        },
      );
      if (!_current(epoch, scope)) throw StateError('Cloud account changed');
      // An earlier GET must not overwrite the profile just saved by this command.
      _epoch++;
      _pending = null;
      try {
        _accept(response);
      } catch (error) {
        _fail(error);
        rethrow;
      }
    } catch (error) {
      if (_current(epoch, scope) &&
          error is PublicApiException &&
          [401, 403].contains(error.statusCode)) {
        _invalidate(error: error);
      }
      rethrow;
    } finally {
      _saving = false;
    }
  }

  Future<void> requestMembership(String role) async {
    if (!canUseBusiness ||
        _schemaVersion < 3 ||
        _saving ||
        !['merchant', 'driver'].contains(role)) {
      throw StateError('Partner request unavailable');
    }
    final epoch = _epoch, scope = _scope;
    _saving = true;
    try {
      await service.request('memberships', body: {'role': role});
      if (!_current(epoch, scope)) throw StateError('Cloud account changed');
      _epoch++;
      _pending = null;
      await refresh();
    } catch (error) {
      if (_current(epoch, scope) &&
          error is PublicApiException &&
          [401, 403].contains(error.statusCode)) {
        _invalidate(error: error);
      }
      rethrow;
    } finally {
      _saving = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    unawaited(_auth?.cancel());
    super.dispose();
  }
}
