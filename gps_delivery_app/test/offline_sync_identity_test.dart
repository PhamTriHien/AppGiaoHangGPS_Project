import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/config/env_config.dart';
import 'package:gps_delivery_app/data/datasources/local/app_state_store.dart';
import 'package:gps_delivery_app/data/datasources/local/sqlite_offline_queue_datasource.dart';
import 'package:gps_delivery_app/data/datasources/remote/supabase_postgis_datasource.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/domain/enums/user_role.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = SqliteOfflineQueueDatasource.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EnvConfig.disableSupabaseRuntime();
    SqliteOfflineQueueDatasource.ensureDesktopFfiInitialized();
    final old = await sqlite.openDatabase(
      '${Directory.systemTemp.path}/gps_delivery_test_runtime_${pid}_${db.runtimeSessionId}.db',
      version: 8,
      onCreate: (database, _) => database.execute('''
        CREATE TABLE local_sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          idempotency_key TEXT UNIQUE NOT NULL,
          action_type TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          retry_count INTEGER NOT NULL DEFAULT 0,
          sync_status TEXT NOT NULL DEFAULT 'PENDING',
          created_at_ms INTEGER NOT NULL
        )
      '''),
    );
    await old.insert('local_sync_queue', {
      'idempotency_key': 'existing-unbound-command',
      'action_type': 'UPSERT',
      'payload_json': '{"table":"order_stops","record":{"id":"legacy"}}',
      'created_at_ms': 1,
    });
    await old.close();
  });

  tearDown(() async {
    db.syncScopeProvider = null;
    await db.deleteRows('local_sync_queue', where: 'id > ?', whereArgs: [0]);
  });

  test(
    'v8 migration preserves existing commands without assigning an owner',
    () async {
      final pending = await db.getPendingSyncItems();
      expect(pending.single.idempotencyKey, 'existing-unbound-command');
      expect(pending.single.ownerScope, isNull);
      expect(await db.getPendingSyncItems(ownerScope: 'new-account'), isEmpty);
      expect(await db.getPendingQueueCount(), 1);
      expect(await (await db.database).getVersion(), 9);
    },
  );

  test('Queue ownership is captured before persistence and filtered before limiting', () async {
    var scope = 'project-A:user-A:local-A';
    db.syncScopeProvider = () => scope;
    final firstWrite = db.enqueueAction(
      actionType: 'UPSERT',
      payload: {'n': 1},
    );
    scope = 'project-B:user-A:local-A';
    await firstWrite;
    await db.enqueueAction(actionType: 'UPSERT', payload: {'n': 2});
    scope = 'project-A:user-B:local-A';
    await db.enqueueAction(actionType: 'UPSERT', payload: {'n': 3});
    scope = 'project-A:user-A:local-B';
    await db.enqueueAction(actionType: 'UPSERT', payload: {'n': 4});
    for (final expected in [
      ('project-A:user-A:local-A', 1),
      ('project-B:user-A:local-A', 2),
      ('project-A:user-B:local-A', 3),
      ('project-A:user-A:local-B', 4),
    ]) {
      final rows = await db.getPendingSyncItems(
        ownerScope: expected.$1,
        limit: 1,
      );
      expect(rows.single.payload['n'], expected.$2);
      expect(rows.single.ownerScope, expected.$1);
    }
  });

  test('Exhausted retries stay visible as unconfirmed data', () async {
    await db.enqueueAction(actionType: 'UPSERT', payload: {});
    final item = (await db.getPendingSyncItems()).single;
    await db.incrementRetry(item.id, 9);
    expect(await db.getPendingSyncItems(), isEmpty);
    expect(await db.getPendingQueueCount(), 1);
    expect(
      (await db.queryRows('local_sync_queue')).single['sync_status'],
      'FAILED',
    );
  });

  test('Web queue filters owner and retains unbound records', () async {
    final web = WebLocalStorageRelationalEngine();
    for (final entry in [
      ('web-A', 'user-A'),
      ('web-B', 'user-B'),
      ('web-unbound', null),
    ]) {
      await web.upsertRow('local_sync_queue', {
        'idempotency_key': entry.$1,
        'owner_scope': entry.$2,
        'sync_status': 'PENDING',
      });
    }
    final rows = await web.queryRows(
      'local_sync_queue',
      where: 'sync_status = ? AND owner_scope = ?',
      whereArgs: ['PENDING', 'user-B'],
      limit: 1,
    );
    expect(rows.single['idempotency_key'], 'web-B');
    expect(await web.countRows('local_sync_queue'), 3);
  });

  test('Changing identity during a drain pins the first token and keeps remaining data', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final store = AppStateStore.instance;
    await store.initializeDatabase();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final url = 'http://127.0.0.1:${server.port}';
    final received = Completer<void>();
    final respond = Completer<void>();
    final tokens = <String?>[];
    final listener = server.listen((request) async {
      tokens.add(request.headers.value(HttpHeaders.authorizationHeader));
      await request.drain<void>();
      if (!received.isCompleted) received.complete();
      await respond.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"id":"confirmed"}');
      await request.response.close();
    });
    final client = SupabaseClient(
      url,
      'fixture-public-key',
      httpClient: MockClient((request) async {
        final email = (jsonDecode(request.body) as Map)['email'] as String;
        final id = email.startsWith('alice') ? 'alice' : 'bob';
        return http.Response(
          jsonEncode({
            'access_token': 'token-$id',
            'refresh_token': 'refresh-$id',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': id,
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': email,
              'created_at': '2026-01-01T00:00:00Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(() async {
      if (!respond.isCompleted) respond.complete();
      await listener.cancel();
      await server.close(force: true);
      await client.dispose();
      SupabasePostgisDatasource.bindRuntimeClient('', '');
      EnvConfig.disableSupabaseRuntime();
      store.activeAuthenticatedUser = null;
    });
    EnvConfig.configureSupabaseRuntime(url: url, anonKey: 'fixture-public-key');
    SupabasePostgisDatasource.bindRuntimeClient(
      url,
      'fixture-public-key',
      client: client,
    );
    await client.auth.signInWithPassword(
      email: 'alice@example.test',
      password: 'fixture',
    );
    store.applyAuthenticatedUserSession(
      UserAccountRecord(
        id: 'local-alice',
        phone: '0901111111',
        email: 'alice@example.test',
        passwordHash: 'unused',
        fullName: 'Alice',
        role: SubsystemRole.customer,
        defaultAddress: '',
        defaultLocation: const GeoPoint(latitude: 10, longitude: 106),
        createdAt: '2026-01-01',
      ),
    );
    for (final id in ['stop-1', 'stop-2']) {
      await db.enqueueAction(
        actionType: 'UPSERT',
        payload: {
          'table': 'order_stops',
          'record': {'id': id},
        },
      );
    }
    final drain = store.drainOfflineSyncQueue();
    await received.future.timeout(const Duration(seconds: 5));
    await client.auth.signInWithPassword(
      email: 'bob@example.test',
      password: 'fixture',
    );
    respond.complete();
    expect(await drain, 1);
    expect(tokens, ['Bearer token-alice']);
    expect(
      (await db.getPendingSyncItems()).single.payload['record']['id'],
      'stop-2',
    );
    expect(await store.drainOfflineSyncQueue(), 0);
    expect(await db.getPendingQueueCount(), 1);
  });
}
