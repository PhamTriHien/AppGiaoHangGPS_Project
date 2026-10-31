import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/data/repositories/cloud_orders_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RepositoryFixture extends CloudOrdersService {
  bool authenticated = true,
      operator = false,
      blocked = false,
      hasProfile = true;
  String identity = 'alice', server = 'project-A', role = 'customer';
  final changes = StreamController<AuthState>.broadcast();
  final calls = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> page = [];
  Completer<Map<String, dynamic>>? pendingOrders, pendingMerchants;
  Object? failure;

  @override
  bool get signedIn => authenticated;
  @override
  String get userId => authenticated ? identity : '';
  @override
  String get project => server;
  @override
  Stream<AuthState> get authChanges => changes.stream;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'query': query});
    if (path == 'profile') {
      return {
        'operator': operator,
        'schema_version': 2,
        'account': hasProfile
            ? {'user_id': identity, 'role': role, 'blocked': blocked}
            : null,
      };
    }
    if (failure != null) throw failure!;
    if (path == 'orders') {
      final pending = pendingOrders;
      pendingOrders = null;
      return pending == null ? {'orders': page} : pending.future;
    }
    if (path == 'merchants') {
      final pending = pendingMerchants;
      pendingMerchants = null;
      return pending == null ? {'merchants': []} : pending.future;
    }
    return {
      'accounts': [
        {'user_id': 'managed-account'},
      ],
    };
  }
}

Map<String, dynamic> row(int id, {int version = 1}) => {
  'id': '10000000-0000-0000-0000-${id.toString().padLeft(12, '0')}',
  'created_at': '2026-10-29T00:00:00Z',
  'version': version,
  'details': {'recipient_name': 'Private recipient'},
};

void main() {
  (RepositoryFixture, CloudAccountSession, CloudOrdersRepository) setup({
    bool admin = false,
  }) {
    final api = RepositoryFixture();
    final session = CloudAccountSession(service: api);
    final repository = CloudOrdersRepository(session: session, admin: admin);
    addTearDown(() async {
      repository.dispose();
      session.dispose();
      await api.changes.close();
    });
    return (api, session, repository);
  }

  test(
    'Requires verified business or operator rights before any resource read',
    () async {
      final (api, session, repository) = setup();
      await expectLater(repository.load(), throwsStateError);
      expect(api.calls, isEmpty);
      api.hasProfile = false;
      await session.refresh();
      await expectLater(repository.load(), throwsStateError);
      api.hasProfile = true;
      await session.refresh();
      await expectLater(
        repository.load(view: CloudOrderView.queue),
        throwsStateError,
      );
      await expectLater(
        repository.load(view: CloudOrderView.accounts),
        throwsStateError,
      );
      expect(api.calls.every((call) => call['path'] == 'profile'), isTrue);
    },
  );

  test(
    'Admin requires operator rights; operator needs no business profile',
    () async {
      final (api, session, repository) = setup(admin: true);
      await session.refresh();
      await expectLater(repository.load(), throwsStateError);
      api.operator = true;
      api.hasProfile = false;
      await session.refresh();
      await repository.load(view: CloudOrderView.accounts);
      expect(repository.accounts.single['user_id'], 'managed-account');
      await repository.load();
      expect(repository.accounts, isEmpty);
      expect(api.calls.last['path'], 'orders');
    },
  );

  test('Snapshots cannot mutate nested cached recipient data', () async {
    final (api, session, repository) = setup();
    api.page = [row(1)];
    await session.refresh();
    await repository.load();
    expect(() => repository.orders.clear(), throwsUnsupportedError);
    expect(
      () => repository.orders.single['version'] = 9,
      throwsUnsupportedError,
    );
    expect(
      () => (repository.orders.single['details'] as Map)['recipient_name'] =
          'Changed',
      throwsUnsupportedError,
    );
    (api.page.single['details'] as Map)['recipient_name'] = 'Mutated transport';
    expect(
      (repository.orders.single['details'] as Map)['recipient_name'],
      'Private recipient',
    );
  });

  test(
    'Pagination uses timestamp and ID, merges updates and coalesces retries',
    () async {
      final (api, session, repository) = setup();
      api.page = [for (var id = 100; id > 50; id--) row(id)];
      await session.refresh();
      await repository.load();
      expect(repository.hasMore, isTrue);
      final pending = Completer<Map<String, dynamic>>();
      api.pendingOrders = pending;
      final first = repository.load(more: true);
      final retry = repository.load(more: true);
      expect(identical(first, retry), isTrue);
      expect(api.calls.last['query'], {
        'before': '2026-10-29T00:00:00Z',
        'before_id': row(51)['id'],
      });
      pending.complete({
        'orders': [row(51, version: 2), row(50)],
      });
      await first;
      expect(repository.orders, hasLength(51));
      expect(
        repository.orders
            .where((o) => o['id'] == row(51)['id'])
            .single['version'],
        2,
      );
      expect(repository.hasMore, isFalse);
      final count = api.calls.length;
      await repository.load(more: true);
      expect(api.calls, hasLength(count));
    },
  );

  for (final change in ['project', 'account', 'verification']) {
    test('Late pages cannot restore data after $change changes', () async {
      final (api, session, repository) = setup();
      api.page = [for (var id = 100; id > 50; id--) row(id)];
      await session.refresh();
      await repository.load();
      final pending = Completer<Map<String, dynamic>>();
      api.pendingOrders = pending;
      final old = repository.load(more: true);
      if (change == 'project') api.server = 'project-B';
      if (change == 'account') api.identity = 'bob';
      if (change == 'verification') session.invalidateVerification();
      expect(repository.orders, isEmpty);
      expect(repository.hasMore, isFalse);
      await session.refresh();
      api.page = [row(2)];
      await repository.load();
      pending.complete({
        'orders': [row(3)],
      });
      await old;
      expect(repository.orders.single['id'], row(2)['id']);
    });
  }

  test(
    'Revocation and sign-out immediately remove all cached resources',
    () async {
      final (api, session, repository) = setup(admin: true);
      api.operator = true;
      api.page = [row(1)];
      await session.refresh();
      await repository.load(view: CloudOrderView.accounts);
      api.operator = false;
      await session.refresh();
      expect(repository.accounts, isEmpty);
      api.operator = true;
      await session.refresh();
      await repository.load();
      expect(repository.orders, hasLength(1));
      api.authenticated = false;
      expect(repository.orders, isEmpty);
      await expectLater(repository.load(), throwsStateError);
    },
  );

  test(
    'Switching queue while orders are pending accepts only the selected view',
    () async {
      final (api, session, repository) = setup();
      api.role = 'driver';
      await session.refresh();
      final pending = Completer<Map<String, dynamic>>();
      api.pendingOrders = pending;
      final old = repository.load();
      api.page = [row(2)];
      await repository.load(view: CloudOrderView.queue);
      expect(api.calls.last['query'], {'queue': 'true'});
      pending.complete({
        'orders': [row(1)],
      });
      await old;
      expect(repository.orders.single['id'], row(2)['id']);
      api.blocked = true;
      await session.refresh();
      expect(repository.orders, isEmpty);
      await expectLater(
        repository.load(view: CloudOrderView.queue),
        throwsStateError,
      );
    },
  );

  test(
    'Identity change during merchant read discards the entire batch',
    () async {
      final (api, session, repository) = setup();
      api.page = [row(1)];
      await session.refresh();
      final pending = Completer<Map<String, dynamic>>();
      api.pendingMerchants = pending;
      final old = repository.load();
      await Future<void>.delayed(Duration.zero);
      expect(api.calls.last['path'], 'merchants');
      session.invalidateVerification();
      pending.complete({
        'merchants': [
          {'user_id': 'private-merchant'},
        ],
      });
      await old;
      expect(repository.orders, isEmpty);
      expect(repository.merchants, isEmpty);
    },
  );

  test(
    'Transient pagination failure preserves rows; denied access clears them',
    () async {
      final (api, session, repository) = setup();
      api.page = [for (var id = 100; id > 50; id--) row(id)];
      await session.refresh();
      await repository.load();
      api.failure = const PublicApiException(
        'Network unavailable',
        statusCode: 502,
      );
      await expectLater(
        repository.load(more: true),
        throwsA(isA<PublicApiException>()),
      );
      expect(repository.orders, hasLength(50));
      expect(repository.hasMore, isTrue);
      api.failure = const PublicApiException('Access denied', statusCode: 403);
      await expectLater(
        repository.load(more: true),
        throwsA(isA<PublicApiException>()),
      );
      expect(repository.orders, isEmpty);
      expect(repository.hasMore, isFalse);
    },
  );

  test(
    'Refresh failure clears the prior list and malformed pages are rejected',
    () async {
      final (api, session, repository) = setup();
      await session.refresh();
      api.page = [row(1)];
      await repository.load();
      api.failure = const PublicApiException('Offline', statusCode: 502);
      await expectLater(repository.load(), throwsA(isA<PublicApiException>()));
      expect(repository.orders, isEmpty);
      api.failure = null;
      final pending = Completer<Map<String, dynamic>>();
      api.pendingOrders = pending;
      final malformed = repository.load();
      pending.complete({'orders': null});
      await expectLater(malformed, throwsFormatException);
      expect(repository.orders, isEmpty);
    },
  );

  test(
    'A repeated full-page cursor is rejected without losing the loaded page',
    () async {
      final (api, session, repository) = setup();
      api.page = [for (var id = 100; id > 50; id--) row(id)];
      await session.refresh();
      await repository.load();
      await expectLater(repository.load(more: true), throwsFormatException);
      expect(repository.orders, hasLength(50));
    },
  );

  test(
    'Disposed repository ignores pending responses and refuses new reads',
    () async {
      final (api, session, repository) = setup();
      await session.refresh();
      final pending = Completer<Map<String, dynamic>>();
      api.pendingOrders = pending;
      final old = repository.load();
      repository.dispose();
      pending.complete({
        'orders': [row(1)],
      });
      await old;
      expect(repository.orders, isEmpty);
      await expectLater(repository.load(), throwsStateError);
    },
  );
}
