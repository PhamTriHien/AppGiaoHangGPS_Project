import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/config/env_config.dart';
import 'package:gps_delivery_app/core/integrations/live_delivery_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('A previous account role response cannot mark the new realtime identity as operator', () async {
    final pending = Completer<http.Response>();
    var firstRead = true;
    final client = SupabaseClient(
      'https://roles-fixture.supabase.co',
      'public-key',
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/v1/token') {
          final email = (jsonDecode(request.body) as Map)['email'] as String;
          final id = email.split('@').first;
          return http.Response(
            jsonEncode({
              'access_token': 'token-$id',
              'refresh_token': 'refresh-$id',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': id,
                'email': email,
                'aud': 'authenticated',
                'role': 'authenticated',
                'created_at': '2026-01-01T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (firstRead) {
          firstRead = false;
          final response = await pending.future;
          return http.Response(
            response.body,
            response.statusCode,
            request: request,
            headers: response.headers,
          );
        }
        return http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final live = LiveDeliveryService(client: client);
    EnvConfig.configureSupabaseRuntime(
      url: 'https://roles-fixture.supabase.co',
      anonKey: 'public-key',
    );
    addTearDown(() async {
      live.dispose();
      await client.dispose();
      EnvConfig.disableSupabaseRuntime();
    });
    await client.auth.signInWithPassword(
      email: 'alice@example.test',
      password: 'fixture',
    );
    final old = live.restoreSession();
    await Future<void>.delayed(Duration.zero);
    await client.auth.signInWithPassword(
      email: 'bob@example.test',
      password: 'fixture',
    );
    await live.restoreSession();
    pending.complete(
      http.Response(
        '[{"role":"operator"}]',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await old;
    expect(live.userId, 'bob');
    expect(live.isOperator, isFalse);
  });

  test('Realtime operator flags are invalid for another project or a signed-out user', () async {
    final client = SupabaseClient(
      'https://roles-fixture.supabase.co',
      'public-key',
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/v1/token') {
          return http.Response(
            jsonEncode({
              'access_token': 'token-alice',
              'refresh_token': 'refresh-alice',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': 'alice',
                'email': 'alice@example.test',
                'aud': 'authenticated',
                'role': 'authenticated',
                'created_at': '2026-01-01T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/auth/v1/logout') {
          return http.Response('', 204);
        }
        return http.Response(
          '[{"role":"operator"}]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final live = LiveDeliveryService(client: client);
    EnvConfig.configureSupabaseRuntime(
      url: 'https://roles-fixture.supabase.co',
      anonKey: 'public-key',
    );
    addTearDown(() async {
      live.dispose();
      await client.dispose();
      EnvConfig.disableSupabaseRuntime();
    });
    await live.signIn('alice@example.test', 'fixture');
    expect(await client.from('delivery_api_profiles').select('role'), [
      {'role': 'operator'},
    ]);
    expect(live.isOperator, isTrue, reason: live.status);
    await client.auth.signInWithPassword(
      email: 'alice@example.test',
      password: 'fixture',
    );
    expect(live.isOperator, isFalse);
    await live.restoreSession();
    expect(live.isOperator, isTrue);
    EnvConfig.configureSupabaseRuntime(
      url: 'https://other-fixture.supabase.co',
      anonKey: 'public-key',
    );
    expect(live.isOperator, isFalse);
    await live.signOut();
    expect(live.isOperator, isFalse);
  });
}
