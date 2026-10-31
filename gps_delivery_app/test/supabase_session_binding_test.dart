import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/config/env_config.dart';
import 'package:gps_delivery_app/data/datasources/remote/supabase_postgis_datasource.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'Runtime rebinding keeps the authenticated session for database reads',
    () async {
      const url = 'https://session-fixture.supabase.co';
      const key = 'fixture-public-key';
      final headers = <String?>[];
      final client = SupabaseClient(
        url,
        key,
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/v1/token') {
            return http.Response(
              jsonEncode({
                'access_token': 'fixture-user-session',
                'refresh_token': 'fixture-refresh',
                'expires_in': 3600,
                'token_type': 'bearer',
                'user': {
                  'id': '00000000-0000-0000-0000-000000000001',
                  'aud': 'authenticated',
                  'role': 'authenticated',
                  'email': 'fixture@example.test',
                  'created_at': '2026-01-01T00:00:00Z',
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          headers.add(request.headers['Authorization']);
          return http.Response(
            '[]',
            200,
            request: request,
            headers: {
              'content-type': 'application/json',
              'content-range': '0-0/0',
            },
          );
        }),
      );
      addTearDown(() async {
        SupabasePostgisDatasource.bindRuntimeClient('', '');
        EnvConfig.configureSupabaseRuntime(url: '', anonKey: '');
        await client.dispose();
      });
      EnvConfig.configureSupabaseRuntime(url: url, anonKey: key);
      await client.auth.signInWithPassword(
        email: 'fixture@example.test',
        password: 'fixture-password',
      );
      SupabasePostgisDatasource.bindRuntimeClient(url, key, client: client);
      SupabasePostgisDatasource.bindRuntimeClient(url, key);
      await SupabasePostgisDatasource().fetchTableRecords('order_stops');
      expect(headers, ['Bearer fixture-user-session']);
    },
  );
}
