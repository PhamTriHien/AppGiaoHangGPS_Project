import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/auth/real_auth_delivery_service.dart';
import 'package:gps_delivery_app/core/config/env_config.dart';
import 'package:gps_delivery_app/data/datasources/local/app_state_store.dart';
import 'package:gps_delivery_app/data/datasources/local/sqlite_offline_queue_datasource.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/domain/enums/user_role.dart';
import 'package:gps_delivery_app/main.dart';
import 'package:gps_delivery_app/presentation/widgets/auth_provider_settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppStateStore.instance;
  final database = SqliteOfflineQueueDatasource.instance;

  void resetProviders() {
    EnvConfig.configureAuthProvidersRuntime(
      smtpSenderEmail: '',
      smtpAppPassword: '',
      googleClientId: '',
      googleClientSecret: '',
      otpEmailWebhookUrl: '',
      otpEmailWebhookToken: '',
    );
  }

  setUpAll(() async {
    await store.initializeDatabase();
  });

  setUp(() async {
    resetProviders();
    store.activeAuthenticatedUser = null;
    store.currentAdminRoleName = 'Super Admin';
    await database.deleteRows(
      'local_relational_entities',
      where: 'table_name = ?',
      whereArgs: ['auth_provider_configs'],
    );
  });

  tearDown(resetProviders);

  test(
    'Desktop email OTP uses relay without client SMTP credentials',
    () async {
      EnvConfig.configureAuthProvidersRuntime(
        otpEmailWebhookUrl: 'http://127.0.0.1:8787/otp-email',
        otpEmailWebhookToken: 'test-relay-token',
      );
      expect(EnvConfig.isSmtpConfigured, isFalse);
      expect(EnvConfig.isEmailOtpConfigured, isTrue);
      var requestCount = 0;
      final receipt = await http.runWithClient(
        () => RealAuthDeliveryService.instance.deliverOtpChallenge(
          destination: 'customer@example.com',
          otpCode: '123456',
        ),
        () => MockClient((request) async {
          requestCount++;
          expect(request.url.path, '/otp-email');
          expect(request.headers['Authorization'], 'Bearer test-relay-token');
          expect(jsonDecode(request.body)['to'], 'customer@example.com');
          expect(jsonDecode(request.body)['otp'], '123456');
          return http.Response('{"success":true}', 200);
        }),
      );
      expect(requestCount, 1);
      expect(receipt.success, isTrue);
      expect(receipt.deliveredExternally, isTrue);
      expect(receipt.channel, 'EMAIL_WEB_RELAY');
    },
  );

  test('Relay delivery failure is not reported as OTP sent', () async {
    EnvConfig.configureAuthProvidersRuntime(
      otpEmailWebhookUrl: 'http://127.0.0.1:8787/otp-email',
    );
    final receipt = await http.runWithClient(
      () => RealAuthDeliveryService.instance.deliverOtpChallenge(
        destination: 'customer@example.com',
        otpCode: '123456',
      ),
      () => MockClient((_) async => http.Response('{}', 502)),
    );
    expect(receipt.success, isFalse);
    expect(receipt.deliveredExternally, isFalse);
  });

  test(
    'Native relay config survives a subsequent launch without build defines',
    () async {
      EnvConfig.configureAuthProvidersRuntime(
        otpEmailWebhookUrl: 'http://127.0.0.1:8787/otp-email',
        otpEmailWebhookToken: 'persisted-test-token',
      );
      await store.loadAuthProviderConfigsFromDatabase();
      resetProviders();
      expect(EnvConfig.isEmailOtpConfigured, isFalse);
      await store.loadAuthProviderConfigsFromDatabase();
      expect(EnvConfig.isEmailOtpConfigured, isTrue);
      expect(EnvConfig.otpEmailWebhookToken, 'persisted-test-token');
      expect(EnvConfig.isGoogleOAuthConfigured, isFalse);
    },
  );

  test(
    'Empty saved config preserves restored Google credentials across launches',
    () async {
      await database.upsertEntityRecord(
        tableName: 'auth_provider_configs',
        recordId: 'DEFAULT',
        payload: {
          'googleClientId': '',
          'googleClientSecret': '  ',
          'otpEmailWebhookUrl': 'http://127.0.0.1:8787/otp-email',
          'otpEmailWebhookToken': 'existing-relay-token',
        },
      );
      EnvConfig.configureAuthProvidersRuntime(
        googleClientId: '123456-restored.apps.googleusercontent.com',
        googleClientSecret: 'restored-test-secret',
      );
      await store.loadAuthProviderConfigsFromDatabase();
      expect(EnvConfig.isGoogleOAuthConfigured, isTrue);
      expect(EnvConfig.googleClientSecret, 'restored-test-secret');
      expect(EnvConfig.otpEmailWebhookToken, 'existing-relay-token');

      resetProviders();
      await store.loadAuthProviderConfigsFromDatabase();
      expect(
        EnvConfig.googleClientId,
        '123456-restored.apps.googleusercontent.com',
      );
      expect(EnvConfig.googleClientSecret, 'restored-test-secret');
      expect(EnvConfig.otpEmailWebhookToken, 'existing-relay-token');
    },
  );

  test(
    'Saved nonempty Google config takes precedence over startup defaults',
    () async {
      await database.upsertEntityRecord(
        tableName: 'auth_provider_configs',
        recordId: 'DEFAULT',
        payload: {
          'googleClientId': '123456-saved.apps.googleusercontent.com',
          'googleClientSecret': 'saved-test-secret',
        },
      );
      EnvConfig.configureAuthProvidersRuntime(
        googleClientId: '123456-startup.apps.googleusercontent.com',
        googleClientSecret: 'startup-test-secret',
      );
      await store.loadAuthProviderConfigsFromDatabase();
      expect(
        EnvConfig.googleClientId,
        '123456-saved.apps.googleusercontent.com',
      );
      expect(EnvConfig.googleClientSecret, 'saved-test-secret');
    },
  );

  test(
    'Unauthenticated user cannot overwrite provider configuration',
    () async {
      await expectLater(
        store.saveAuthProviderConfigsToDatabase(
          smtpHost: 'smtp.gmail.com',
          smtpPort: 465,
          smtpSenderEmail: '',
          smtpAppPassword: '',
          smsWebhookUrl: '',
          googleClientId: '',
          googleClientSecret: '',
          otpEmailWebhookUrl: 'https://example.com/otp-email',
        ),
        throwsStateError,
      );
      expect(EnvConfig.isEmailOtpConfigured, isFalse);
    },
  );

  testWidgets('Google login is hidden until Google OAuth is configured', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const GpsDeliveryApp(initialRoute: '/legacy'));
    await tester.pump();
    expect(find.text('Tiếp tục với Google'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    EnvConfig.configureAuthProvidersRuntime(
      googleClientId: '123456-test.apps.googleusercontent.com',
    );
    await tester.pumpWidget(const GpsDeliveryApp(initialRoute: '/legacy'));
    await tester.pump();
    expect(find.text('Tiếp tục với Google'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Admin save preserves existing secret fields left blank', (
    tester,
  ) async {
    store.activeAuthenticatedUser = UserAccountRecord(
      id: 'TEST-ADMIN',
      phone: '0901234567',
      email: 'admin@example.com',
      passwordHash: 'test-hash',
      fullName: 'Test Admin',
      role: SubsystemRole.admin,
      defaultAddress: '',
      defaultLocation: const GeoPoint(latitude: 0, longitude: 0),
      createdAt: DateTime.now().toIso8601String(),
    );
    EnvConfig.configureAuthProvidersRuntime(
      otpEmailWebhookUrl: 'http://127.0.0.1:8787/otp-email',
      otpEmailWebhookToken: 'existing-token',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: AuthProviderSettings(canEdit: true),
          ),
        ),
      ),
    );
    final save = find.text('Lưu cấu hình đăng nhập');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(EnvConfig.otpEmailWebhookToken, 'existing-token');
    resetProviders();
    await tester.runAsync(store.loadAuthProviderConfigsFromDatabase);
    expect(EnvConfig.otpEmailWebhookToken, 'existing-token');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
