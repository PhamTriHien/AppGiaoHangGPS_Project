import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_session_lease.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionFixture extends CloudOrdersService {
  bool authenticated = true,
      operator = false,
      blocked = false,
      hasProfile = true;
  String id = 'alice', role = 'customer', name = 'Alice', server = 'project-A';
  Object? failure;
  Map<String, dynamic>? overrideResponse;
  Completer<Map<String, dynamic>>? pendingGet, pendingSave;
  final changes = StreamController<AuthState>.broadcast();
  final calls = <Map<String, dynamic>>[];
  @override
  bool get signedIn => authenticated;
  @override
  String get userId => authenticated ? id : '';
  @override
  String get project => server;
  @override
  Stream<AuthState> get authChanges => changes.stream;
  Map<String, dynamic> response() => {
    'operator': operator,
    'schema_version': 2,
    'account': hasProfile
        ? {
            'user_id': id,
            'role': role,
            'blocked': blocked,
            'full_name': name,
            'phone': '0901234567',
            'requested_role': 'driver',
          }
        : null,
  };
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body});
    if (body == null && pendingGet != null) {
      final pending = pendingGet!;
      pendingGet = null;
      return pending.future;
    }
    if (body != null && pendingSave != null) {
      final pending = pendingSave!;
      pendingSave = null;
      return pending.future;
    }
    if (failure != null) throw failure!;
    if (body != null) name = body['full_name'] as String;
    return overrideResponse ?? response();
  }
}

void main() {
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  (SessionFixture, CloudAccountSession) setup() {
    final api = SessionFixture();
    final session = CloudAccountSession(service: api);
    addTearDown(() async {
      session.dispose();
      await api.changes.close();
    });
    return (api, session);
  }

  test('Restores server profile without a local account and never grants a pending role', () async {
    final (api, session) = setup();
    api.operator = true;
    await session.refresh();
    expect(session.phase, CloudAccountPhase.active);
    expect(session.account!['user_id'], 'alice');
    expect(session.account!['role'], 'customer');
    expect(session.canUseBusiness, isTrue);
    expect(session.isOperator, isTrue);
    expect(() => session.account!['role'] = 'driver', throwsUnsupportedError);
    expect(api.calls.single['path'], 'profile');
  });

  test('Signed out sessions make no profile request', () async {
    final (api, session) = setup();
    api.authenticated = false;
    await session.refresh();
    expect(api.calls, isEmpty);
    expect(session.account, isNull);
    expect(session.phase, CloudAccountPhase.signedOut);
  });

  test(
    'Coalesces profile reads and blocks a disabled business profile',
    () async {
      final (api, session) = setup();
      final wait = Completer<Map<String, dynamic>>();
      api.pendingGet = wait;
      final first = session.refresh(), second = session.refresh();
      expect(identical(first, second), isTrue);
      expect(api.calls, hasLength(1));
      api.blocked = true;
      wait.complete(api.response());
      await first;
      expect(session.phase, CloudAccountPhase.blocked);
      expect(session.canUseBusiness, isFalse);
      expect(session.account!['blocked'], isTrue);
    },
  );

  test(
    'Switching account rejects the previous in-flight operator profile',
    () async {
      final (api, session) = setup();
      final wait = Completer<Map<String, dynamic>>();
      final old = {...api.response(), 'operator': true};
      api.pendingGet = wait;
      final first = session.refresh();
      api.id = 'bob';
      api.changes.add(AuthState(AuthChangeEvent.signedIn, null));
      await tick();
      await session.refresh();
      expect(session.account!['user_id'], 'bob');
      wait.complete(old);
      await first;
      expect(session.account!['user_id'], 'bob');
      expect(session.isOperator, isFalse);
    },
  );

  test('An old response cannot restore rights after sign-out and same-user sign-in', () async {
    final (api, session) = setup();
    final wait = Completer<Map<String, dynamic>>();
    api.pendingGet = wait;
    final old = {...api.response(), 'operator': true};
    final first = session.refresh();
    api.authenticated = false;
    api.changes.add(AuthState(AuthChangeEvent.signedOut, null));
    await tick();
    api.authenticated = true;
    api.changes.add(AuthState(AuthChangeEvent.signedIn, null));
    await tick();
    await session.refresh();
    wait.complete(old);
    await first;
    expect(session.isOperator, isFalse);
    expect(session.canUseBusiness, isTrue);
  });

  test(
    'Project switches hide cached identity before another auth event',
    () async {
      final (api, session) = setup();
      api.operator = true;
      await session.refresh();
      api.server = 'project-B';
      expect(session.account, isNull);
      expect(session.isOperator, isFalse);
      api.operator = false;
      await session.refresh();
      expect(session.account!['user_id'], 'alice');
    },
  );

  test('Role revocation invalidates loaded resources; transient failure also clears rights', () async {
    final (api, session) = setup();
    api.operator = true;
    api.role = 'driver';
    await session.refresh();
    final revision = session.revision;
    api.operator = false;
    api.role = 'customer';
    await session.refresh();
    expect(session.revision, greaterThan(revision));
    expect(session.isOperator, isFalse);
    api.failure = const PublicApiException(
      'Không xác minh được phiên.',
      statusCode: 401,
    );
    await expectLater(session.refresh(), throwsA(isA<PublicApiException>()));
    expect(session.account, isNull);
    expect(session.verified, isFalse);
    expect(session.canUseBusiness, isFalse);
    api.failure = null;
    await session.refresh();
    expect(session.verified, isTrue);
  });

  test('Malformed or foreign profile responses fail closed', () async {
    final (api, session) = setup();
    for (final invalid in [
      {...api.response(), 'operator': 'true'},
      {...api.response(), 'schema_version': null},
      {
        ...api.response(),
        'account': {
          ...(api.response()['account'] as Map),
          'user_id': 'someone-else',
        },
      },
      {
        ...api.response(),
        'account': {...(api.response()['account'] as Map), 'role': 'admin'},
      },
      {
        ...api.response(),
        'account': {...(api.response()['account'] as Map), 'blocked': 'false'},
      },
      {
        ...api.response(),
        'account': {
          ...(api.response()['account'] as Map),
          'requested_role': 'admin',
        },
      },
    ]) {
      api.overrideResponse = invalid;
      await expectLater(session.refresh(), throwsFormatException);
      expect(session.isOperator, isFalse);
      expect(session.account, isNull);
    }
  });

  test('Saving uses only editable fields and an earlier GET cannot undo the result', () async {
    final (api, session) = setup();
    await session.refresh();
    final old = api.response();
    final wait = Completer<Map<String, dynamic>>();
    api.pendingGet = wait;
    final get = session.refresh();
    await session.saveProfile(
      fullName: '  New Name  ',
      phone: '0901234567',
      requestedRole: 'driver',
    );
    expect(api.calls.last['body'], {
      'full_name': 'New Name',
      'phone': '0901234567',
      'requested_role': 'driver',
    });
    wait.complete(old);
    await get;
    expect(session.account!['full_name'], 'New Name');
    expect(session.account!['role'], 'customer');
  });

  test('Concurrent saves are rejected and foreign-account save responses are discarded', () async {
    final (api, session) = setup();
    await session.refresh();
    final wait = Completer<Map<String, dynamic>>();
    api.pendingSave = wait;
    final first = session.saveProfile(
      fullName: 'New Name',
      phone: '0901234567',
      requestedRole: 'customer',
    );
    final rejected = expectLater(first, throwsStateError);
    await expectLater(
      session.saveProfile(
        fullName: 'Second',
        phone: '0901234567',
        requestedRole: 'customer',
      ),
      throwsStateError,
    );
    api.id = 'bob';
    api.changes.add(AuthState(AuthChangeEvent.signedIn, null));
    await tick();
    final old = api.response();
    (old['account'] as Map)['user_id'] = 'alice';
    wait.complete(old);
    await rejected;
    expect(session.account?['user_id'], 'bob');
  });

  test(
    'Invalidation clears privileges and rejects a pending verification',
    () async {
      final (api, session) = setup();
      api.operator = true;
      await session.refresh();
      final old = api.response();
      final pending = Completer<Map<String, dynamic>>();
      api.pendingGet = pending;
      final refresh = session.refresh();
      final revision = session.revision;
      session.invalidateVerification();
      expect(session.revision, greaterThan(revision));
      expect(session.account, isNull);
      expect(session.isOperator, isFalse);
      expect(session.verified, isFalse);
      pending.complete(old);
      await refresh;
      expect(session.verified, isFalse);
      api.operator = false;
      api.blocked = true;
      await session.refresh();
      expect(session.phase, CloudAccountPhase.blocked);
      expect(session.canUseBusiness, isFalse);
    },
  );

  test('A disposed session ignores a late response', () async {
    final api = SessionFixture();
    final session = CloudAccountSession(service: api);
    final wait = Completer<Map<String, dynamic>>();
    api.pendingGet = wait;
    final get = session.refresh();
    session.dispose();
    wait.complete(api.response());
    await get;
    expect(session.account, isNull);
    await api.changes.close();
  });

  Map<String, dynamic> partnerResponse(
    SessionFixture api,
    List<String> roles,
  ) => {
    ...api.response(),
    'schema_version': 3,
    'account': {
      ...(api.response()['account'] as Map<String, dynamic>),
      'approved_roles': roles,
      'memberships': [
        for (final role in ['merchant', 'driver'])
          {
            'role': role,
            'state': roles.contains(role) ? 'active' : 'pending',
            'version': 1,
            'reason': '',
          },
      ],
    },
  };

  test('Independent approved roles authorize leases and revoke irreversibly on permission change', () async {
    final (api, session) = setup();
    api.role = 'driver';
    api.overrideResponse = partnerResponse(api, ['driver', 'merchant']);
    await session.refresh();
    final merchant = CloudSessionLease(
      session: session,
      roles: const {'merchant'},
    );
    final driver = CloudSessionLease(session: session, roles: const {'driver'});
    addTearDown(merchant.dispose);
    addTearDown(driver.dispose);
    expect(session.approvedRoles, {'customer', 'driver', 'merchant'});
    expect(merchant.valid, isTrue);
    expect(driver.valid, isTrue);
    expect(session.isOperator, isFalse);
    expect(
      () => (session.account!['approved_roles'] as List).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => ((session.account!['memberships'] as List).first as Map)['state'] =
          'pending',
      throwsUnsupportedError,
    );
    final revision = session.revision;
    api.overrideResponse = partnerResponse(api, ['merchant']);
    await session.refresh();
    expect(session.revision, greaterThan(revision));
    expect(driver.valid, isFalse);
    expect(merchant.valid, isFalse);
    expect(session.hasRole('driver'), isFalse);
    expect(session.hasRole('merchant'), isTrue);
    api.overrideResponse = partnerResponse(api, ['driver', 'merchant']);
    await session.refresh();
    expect(driver.valid, isFalse);
  });

  test('Rejects malformed membership data and ignores the legacy role for schema three privileges', () async {
    final (api, session) = setup();
    api.role = 'driver';
    api.overrideResponse = partnerResponse(api, []);
    await session.refresh();
    expect(session.hasRole('driver'), isFalse);
    expect(session.hasRole('customer'), isTrue);
    for (final invalid in [
      {
        'approved_roles': ['operator'],
      },
      {
        'approved_roles': ['driver'],
      },
      {
        'approved_roles': ['driver', 'driver'],
      },
      {
        'memberships': [
          {'role': 'driver', 'state': 'active', 'version': 0},
        ],
      },
      {
        'memberships': [
          {'role': 'operator', 'state': 'active', 'version': 1},
        ],
      },
      {'memberships': null},
    ]) {
      final response = partnerResponse(api, []);
      (response['account'] as Map).addAll(invalid);
      api.overrideResponse = response;
      await expectLater(session.refresh(), throwsFormatException);
      expect(session.approvedRoles, isEmpty);
      expect(session.isOperator, isFalse);
    }
  });

  test('Preserves verified session across same-account auth replay and transient wake-up network errors', () async {
    final (api, session) = setup();
    api.operator = true;
    await session.refresh();
    final lease = CloudSessionLease(session: session);
    addTearDown(lease.dispose);
    final revision = session.revision;
    api.changes.add(AuthState(AuthChangeEvent.signedIn, null));
    await tick();
    expect(session.verified, isTrue);
    expect(lease.valid, isTrue);
    expect(session.revision, revision);

    for (final transient in <Object>[
      const PublicApiException('Không kết nối được máy chủ dịch vụ.'),
      const PublicApiException('Bad Gateway', statusCode: 502),
      const PublicApiException('Gateway Timeout', statusCode: 504),
      TimeoutException('wake-up timeout'),
    ]) {
      api.failure = transient;
      await expectLater(session.refresh(), throwsA(anything));
      expect(session.verified, isTrue);
      expect(lease.valid, isTrue);
      expect(session.revision, revision);
    }

    api.failure = const PublicApiException('Unauthorized', statusCode: 401);
    await expectLater(session.refresh(), throwsA(isA<PublicApiException>()));
    expect(session.verified, isFalse);
    expect(lease.valid, isFalse);
  });
}
