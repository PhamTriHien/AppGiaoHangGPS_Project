import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/auth/cloud_oauth_io.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/theme/app_theme.dart';
import 'package:gps_delivery_app/main.dart';
import 'package:gps_delivery_app/presentation/customer/ghst_home_screen.dart';
import 'package:gps_delivery_app/presentation/customer/ghst_user_shell.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_orders_screen.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_screen.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_view.dart';
import 'package:gps_delivery_app/presentation/widgets/studio_user_auth_frame.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'marketplace_test.dart' show MarketFixture;

class UnifiedUserFixture extends MarketFixture {
  Set<String> roles = {};
  bool incomplete = false;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == 'profile') {
      if (body != null) incomplete = false;
      final data = await super.request(path, body: body, query: query);
      if (incomplete) {
        return {'operator': false, 'schema_version': 3, 'account': null};
      }
      final base = Map<String, dynamic>.from(data['account'] as Map);
      if (body != null) {
        base['full_name'] = body['full_name'];
        base['phone'] = body['phone'];
      }
      return {
        ...data,
        'schema_version': 3,
        'account': {
          ...base,
          'approved_roles': roles.toList(),
          'memberships': [
            for (final role in roles)
              {'role': role, 'state': 'active', 'version': 1, 'reason': ''},
          ],
        },
      };
    }
    if (path == 'orders') return {'orders': []};
    if (path == 'merchants') return {'merchants': []};
    return super.request(path, body: body, query: query);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<(UnifiedUserFixture, CloudAccountSession)> setup(
    WidgetTester tester,
    double width,
  ) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    final api = UnifiedUserFixture();
    final session = CloudAccountSession(service: api);
    addTearDown(() async {
      session.dispose();
      await api.changes.close();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    return (api, session);
  }

  Future<void> navigate(WidgetTester tester, String label, double width) async {
    final section = switch (label) {
      'Tài khoản' => GhstUserSection.profile,
      'Khám phá' => GhstUserSection.food,
      'Trang chủ' => GhstUserSection.home,
      _ => GhstUserSection.orders,
    };
    final target = width < 860
        ? find.byKey(ValueKey('ghst-nav-${section.name}'))
        : find
              .descendant(
                of: find.byType(GhstUserShell),
                matching: find.text(switch (section) {
                  GhstUserSection.profile => 'Hồ sơ cá nhân',
                  GhstUserSection.food => 'Ăn uống & Mua sắm',
                  GhstUserSection.home => 'Trang chủ',
                  _ => 'Đơn hàng',
                }),
              )
              .first;
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  for (final width in [360.0, 1440.0]) {
    for (final roles in [
      <String>{},
      {'merchant'},
      {'driver'},
      {'merchant', 'driver'},
    ]) {
      testWidgets(
        'One user shell retains navigation for roles $roles at $width',
        (tester) async {
          final (api, session) = await setup(tester, width);
          api.roles = roles;
          await session.refresh();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: MarketplaceScreen(session: session),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(GhstHomeScreen), findsOneWidget);
          expect(find.byType(NavigationBar), findsNothing);
          expect(
            find.text('Bạn muốn giao hàng hay đặt món đến đâu?'),
            findsOneWidget,
          );
          if (width >= 860) expect(find.text('GHST EXPRESS'), findsOneWidget);
          final root = tester.element(find.byType(MarketplaceScreen));
          expect(Navigator.of(root).canPop(), isFalse);
          await navigate(tester, 'Tài khoản', width);
          expect(find.text('account@example.com'), findsOneWidget);
          expect(
            find.text('Cửa hàng của tôi'),
            roles.contains('merchant') ? findsWidgets : findsNothing,
          );
          expect(
            find.text('Chuyến giao của tôi'),
            roles.contains('driver') ? findsWidgets : findsNothing,
          );
          if (roles.contains('merchant')) {
            await tester.tap(find.text('Cửa hàng của tôi').last);
            await tester.pumpAndSettle();
            expect(
              tester.widget<MarketplaceView>(find.byType(MarketplaceView)).view,
              MarketView.workspace,
            );
            expect(Navigator.of(root).canPop(), isFalse);
            await navigate(tester, 'Tài khoản', width);
            await tester.tap(find.text('Đơn của cửa hàng').last);
            await tester.pumpAndSettle();
            expect(
              tester.widget<MarketplaceView>(find.byType(MarketplaceView)).view,
              MarketView.merchantOrders,
            );
            expect(Navigator.of(root).canPop(), isFalse);
            await navigate(tester, 'Tài khoản', width);
          }
          if (roles.contains('driver')) {
            await tester.tap(find.text('Chuyến giao của tôi').last);
            await tester.pumpAndSettle();
          } else {
            await navigate(tester, 'Gửi hàng', width);
          }
          expect(
            tester
                .widget<CloudOrdersScreen>(find.byType(CloudOrdersScreen))
                .embedded,
            isTrue,
          );
          expect(Navigator.of(root).canPop(), isFalse);
          expect(find.byType(StudioUserAuthFrame), findsNothing);
          await navigate(tester, 'Khám phá', width);
          expect(find.text(api.product['name']), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    testWidgets(
      'Role revocation removes partner content within the common shell at $width',
      (tester) async {
        final (api, session) = await setup(tester, width);
        api.roles = {'merchant', 'driver'};
        await session.refresh();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: MarketplaceScreen(session: session),
          ),
        );
        await tester.pumpAndSettle();
        await navigate(tester, 'Tài khoản', width);
        await tester.tap(find.text('Cửa hàng của tôi').last);
        await tester.pumpAndSettle();
        api.roles = {};
        await session.refresh();
        await tester.pumpAndSettle();
        expect(find.text('Cửa hàng của tôi'), findsNothing);
        expect(find.text('Chuyến giao của tôi'), findsNothing);
        expect(
          tester.widget<MarketplaceView>(find.byType(MarketplaceView)).view,
          MarketView.account,
        );
        expect(find.byType(MarketplaceScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'The cloud route uses the original login design and real Auth registration at $width',
      (tester) async {
        final (api, _) = await setup(tester, width);
        api.authenticated = false;
        await tester.pumpWidget(
          GpsDeliveryApp(initialRoute: '/cloud', cloudService: api),
        );
        await tester.pumpAndSettle();
        expect(find.byType(StudioUserAuthFrame), findsOneWidget);
        expect(find.byType(StudioUserAuthBrand), findsOneWidget);
        expect(find.text('Đăng nhập hệ thống'), findsOneWidget);
        expect(find.text('Mã OTP'), findsNothing);
        await tester.tap(find.text('Đăng ký tài khoản'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'),
          'account@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Mật khẩu mới'),
          'password8',
        );
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Tạo tài khoản'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Tạo tài khoản'));
        await tester.pumpAndSettle();
        expect(
          api.calls
              .where((c) => c['action'] == 'authenticate')
              .single['register'],
          isTrue,
        );
        expect(
          find.text('Kiểm tra email để xác nhận tài khoản rồi đăng nhập.'),
          findsOneWidget,
        );
        expect(find.byType(StudioUserAuthFrame), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'Window focus loss keeps GHST shell visible while background pause revalidates at $width',
      (tester) async {
        final (api, session) = await setup(tester, width);
        await session.refresh();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: MarketplaceScreen(session: session),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(GhstUserShell), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        expect(find.byType(GhstUserShell), findsOneWidget);
        expect(find.text('GO-MAU'), findsNothing);
        final readsBeforePause = api.calls
            .where((c) => c['path'] == 'profile')
            .length;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        expect(session.verified, isFalse);
        await tester.pump(const Duration(seconds: 31));
        expect(
          api.calls.where((c) => c['path'] == 'profile').length,
          readsBeforePause,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(
          api.calls.where((c) => c['path'] == 'profile').length,
          greaterThan(readsBeforePause),
        );
        expect(find.byType(GhstUserShell), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'First-time account completes profile inside GHST frame and enters home at $width',
      (tester) async {
        final (api, session) = await setup(tester, width);
        api.incomplete = true;
        await session.refresh();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: MarketplaceScreen(session: session),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(StudioUserAuthFrame), findsOneWidget);
        expect(find.text('Hoàn tất hồ sơ GHST EXPRESS'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Họ và tên'),
          'Người dùng Google',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Số điện thoại'),
          '0912345678',
        );
        await tester.ensureVisible(find.text('Lưu hồ sơ'));
        await tester.tap(find.text('Lưu hồ sơ'));
        await tester.pumpAndSettle();
        expect(find.byType(GhstUserShell), findsOneWidget);
        expect(find.byType(GhstHomeScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'Desktop sidebar driver trips shortcut resets purchase orders to shipping trips',
    (tester) async {
      final (api, session) = await setup(tester, 1440.0);
      api.roles = {'merchant', 'driver'};
      await session.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MarketplaceScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();
      await navigate(tester, 'Đơn hàng', 1440.0);
      await tester.tap(find.text('Đơn mua'));
      await tester.pumpAndSettle();
      expect(find.byType(CloudOrdersScreen), findsNothing);
      await tester.tap(find.text('Chuyến giao của tôi').first);
      await tester.pumpAndSettle();
      expect(find.byType(CloudOrdersScreen), findsOneWidget);
      expect(find.text('Chuyến của tôi'), findsOneWidget);
      expect(find.text('Chờ nhận'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Signed-out auth screen surfaces async OAuth stream AuthException without unhandled errors',
    (tester) async {
      final (api, session) = await setup(tester, 360.0);
      api.authenticated = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MarketplaceScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();
      api.changes.addError(const AuthException('OAuth callback rejected'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Không xác thực được. Kiểm tra thông tin, email xác nhận hoặc thử lại sau.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'Google OAuth PKCE URL always requests account chooser prompt=select_account',
    () async {
      SharedPreferences.setMockInitialValues({});
      final client = SupabaseClient(
        'https://example.supabase.co',
        'publishable-test-key',
        authOptions: AuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          pkceAsyncStorage: SharedPreferencesGotrueAsyncStorage(),
        ),
      );
      try {
        final oauth = await client.auth.getOAuthSignInUrl(
          provider: OAuthProvider.google,
          redirectTo: desktopGoogleRedirectUri,
          queryParams: googleOAuthQueryParams,
        );
        final uri = Uri.parse(oauth.url);
        expect(uri.queryParameters['provider'], 'google');
        expect(uri.queryParameters['prompt'], 'select_account');
        expect(uri.queryParameters['code_challenge_method'], 's256');
      } finally {
        await client.dispose();
      }
    },
  );

  testWidgets(
    'Password recovery supports code resend and transitions to new-password mode on recovery session',
    (tester) async {
      final (api, session) = await setup(tester, 360.0);
      api.authenticated = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MarketplaceScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quên mật khẩu?'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'member@example.com',
      );
      await tester.tap(find.text('Gửi email khôi phục'));
      await tester.pumpAndSettle();
      expect(
        find.text('Yêu cầu đã được gửi. Vui lòng kiểm tra email.'),
        findsOneWidget,
      );
      expect(find.text('Gửi lại mã xác nhận'), findsOneWidget);
      await tester.tap(find.text('Gửi lại mã xác nhận'));
      await tester.pumpAndSettle();
      expect(
        api.calls.where((c) => c['action'] == 'reset').length,
        2,
      );
      api.authenticated = true;
      api.changes.add(const AuthState(AuthChangeEvent.passwordRecovery, null));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Mã xác nhận email'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Mật khẩu mới'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
