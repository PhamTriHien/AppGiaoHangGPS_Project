import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/config/default_cloud_connection.dart';
import 'package:gps_delivery_app/core/config/env_config.dart';

void main() {
  tearDown(() => EnvConfig.configureSupabaseRuntime(url: '', anonKey: ''));
  test(
    'Invalid startup configuration can disable cloud without changing defaults',
    () {
      final connection = resolveCloudConnection(
        buildUrl: '',
        buildPublicKey: '',
      );
      EnvConfig.configureSupabaseRuntime(
        url: connection.url,
        anonKey: connection.publicKey,
      );
      expect(EnvConfig.isSupabaseConfigured, isTrue);
      EnvConfig.disableSupabaseRuntime();
      expect(EnvConfig.supabaseUrl, isEmpty);
      expect(EnvConfig.supabaseAnonKey, isEmpty);
      expect(EnvConfig.isSupabaseConfigured, isFalse);
      EnvConfig.configureSupabaseRuntime(
        url: connection.url,
        anonKey: connection.publicKey,
      );
      expect(EnvConfig.isSupabaseConfigured, isTrue);
    },
  );
  test('A fresh install uses the configured public Supabase project', () {
    final connection = resolveCloudConnection(buildUrl: '', buildPublicKey: '');
    expect(connection.url, 'https://yvnbfurazjbhbopahtmx.supabase.co');
    expect(connection.publicKey, startsWith('sb_publishable_'));
  });

  test('Saved and build connection pairs override defaults without mixing projects', () {
    final build = resolveCloudConnection(
      buildUrl: 'https://build.supabase.co/',
      buildPublicKey: 'sb_publishable_build',
    );
    expect(build.url, 'https://build.supabase.co');
    final saved = resolveCloudConnection(
      saved: {
        'supabaseUrl': 'https://saved.supabase.co',
        'supabaseAnonKey': 'sb_publishable_saved',
      },
      buildUrl: build.url,
      buildPublicKey: build.publicKey,
    );
    expect(saved.url, 'https://saved.supabase.co');
    expect(saved.publicKey, 'sb_publishable_saved');
    expect(
      () => resolveCloudConnection(saved: {'supabaseUrl': saved.url}),
      throwsFormatException,
    );
    expect(
      () => resolveCloudConnection(buildUrl: build.url, buildPublicKey: ''),
      throwsFormatException,
    );
  });

  test(
    'Server secrets and malformed connection addresses cannot enter the app',
    () {
      for (final role in ['anon', 'service_role', 'authenticated']) {
        final payload = base64Url.encode(
          utf8.encode(jsonEncode({'role': role})),
        );
        ({String url, String publicKey}) action() => resolveCloudConnection(
          buildUrl: defaultSupabaseUrl,
          buildPublicKey: 'header.$payload.signature',
        );
        if (role == 'anon') {
          expect(action().url, defaultSupabaseUrl);
        } else {
          expect(action, throwsFormatException);
        }
      }
      expect(
        () => resolveCloudConnection(
          buildUrl: defaultSupabaseUrl,
          buildPublicKey: 'sb_secret_server',
        ),
        throwsFormatException,
      );
      for (final url in [
        'http://project.supabase.co',
        'https://name:password@project.supabase.co',
        'https://project.supabase.co?token=x',
        'https://project.supabase.co/path',
      ]) {
        expect(
          () => resolveCloudConnection(
            buildUrl: url,
            buildPublicKey: defaultSupabasePublishableKey,
          ),
          throwsFormatException,
        );
      }
    },
  );
}
