import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/push_notification_service.dart';
import 'package:gps_delivery_app/core/theme/app_theme.dart';
import 'package:gps_delivery_app/core/theme/theme_controller.dart';
import 'package:gps_delivery_app/presentation/customer/ghst_ai_chat_screen.dart';
import 'package:gps_delivery_app/presentation/customer/ghst_user_shell.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_app_settings_screen.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'marketplace_test.dart' show MarketFixture;

class AppSettingsFixture extends MarketFixture {
  Set<String> approvedRoles = {};
  bool operatorRole = false;
  Map<String, dynamic> uiPrefs = {};
  Map<String, dynamic>? savedDraft = {'service_type': 'express'};
  Map<String, bool> notifPrefs = {
    'push_enabled': true,
    'shipping_updates': true,
    'market_updates': true,
    'promo_updates': true,
  };
  List<Map<String, String>> aiMessages = [
    {'role': 'user', 'content': 'Phí giao nhanh tính sao?'},
    {'role': 'assistant', 'content': 'Phí giao nhanh phụ thuộc quãng đường.'},
  ];
  String? updatedPassword;

  @override
  Future<void> updatePassword(String password) async {
    if (password.length < 8) {
      throw ArgumentError('Invalid password');
    }
    updatedPassword = password;
    calls.add({'action': 'update_password', 'length': password.length});
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body, 'query': query});
    if (path == 'profile') {
      final primaryRole =
          approvedRoles.contains('driver') && !approvedRoles.contains('merchant')
          ? 'driver'
          : approvedRoles.contains('merchant')
          ? 'merchant'
          : 'customer';
      return {
        'operator': operatorRole,
        'schema_version': 3,
        'account': {
          'user_id': id,
          'full_name': 'Nguyễn Minh An',
          'phone': '0901234567',
          'birth_date': '1998-05-15',
          'citizen_id': '079098001234',
          'identity_verified': true,
          'coin_balance': 2400,
          'unread_notifications': 2,
          'role': primaryRole,
          'blocked': blocked,
          'requested_role': null,
          'approved_roles': approvedRoles.toList(),
          'staff_shops': const <Map<String, dynamic>>[],
          'memberships': [
            for (final r in approvedRoles)
              {'role': r, 'state': 'active', 'version': 1, 'reason': ''},
          ],
          'ui_preferences': Map<String, dynamic>.from(uiPrefs),
          'shipping_draft': savedDraft,
        },
      };
    }
    if (path == 'preferences/save_ui') {
      if (body != null) {
        uiPrefs = {...uiPrefs, ...body};
      }
      return {'ui_preferences': Map<String, dynamic>.from(uiPrefs)};
    }
    if (path == 'preferences/clear_draft') {
      savedDraft = null;
      return {'cleared': true};
    }
    if (path == 'notifications/unread_count') {
      return {
        'unread_count': 2,
        'preferences': Map<String, bool>.from(notifPrefs),
        'latest': null,
      };
    }
    if (path == 'notifications/save_preferences') {
      if (body != null) {
        for (final entry in body.entries) {
          if (entry.value is bool) {
            notifPrefs[entry.key] = entry.value as bool;
          }
        }
      }
      return {'preferences': Map<String, bool>.from(notifPrefs)};
    }
    if (path == 'ai-history/list') {
      return {'messages': List<Map<String, String>>.from(aiMessages)};
    }
    if (path == 'ai-history/clear') {
      aiMessages = [];
      return {'cleared': true};
    }
    if (path == 'orders') {
      return {'orders': const <Map<String, dynamic>>[], 'schema_version': 3};
    }
    if (path == 'merchants') {
      return {'merchants': const <Map<String, dynamic>>[]};
    }
    if (path == 'logistics/pickup_list') {
      return {'pickups': const [], 'drivers': const []};
    }
    if (path == 'logistics/stats') {
      return {
        'scope': 'self',
        'summary': {
          'total': 0,
          'delivered': 0,
          'failed_or_returned': 0,
          'cancelled': 0,
          'active': 0,
          'by_service': const [],
        },
      };
    }
    return super.request(path, body: body, query: query);
  }
}

Widget _buildHarness({
  required CloudAccountSession session,
  required ThemeController themeController,
}) {
  return ThemeControllerScope(
    controller: themeController,
    child: AnimatedBuilder(
      animation: themeController,
      builder: (_, _) => MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeController.themeMode,
        home: MarketplaceScreen(session: session),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PushNotificationService.instance.applyPreferences({
      'push_enabled': true,
      'shipping_updates': true,
      'market_updates': true,
      'promo_updates': true,
    });
  });

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'App Settings screen opens cleanly at ${width.toInt()}px in Light & Dark with zero Icon widgets and zero jargon',
      (tester) async {
        tester.view.physicalSize = Size(width, 920);
        tester.view.devicePixelRatio = 1;
        final api = AppSettingsFixture();
        final session = CloudAccountSession(service: api);
        final themeController = ThemeController(
          session: session,
          sessionSlot: 'test-${width.toInt()}',
        );
        addTearDown(() async {
          themeController.dispose();
          session.dispose();
          await api.changes.close();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await session.refresh();
        await tester.pumpWidget(
          _buildHarness(session: session, themeController: themeController),
        );
        await tester.pumpAndSettle();

        if (width < 860) {
          await tester.tap(find.byKey(const ValueKey('ghst-nav-profile')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('account-open-settings')),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('account-open-settings')));
          await tester.pumpAndSettle();
        } else {
          final sidebarItem = find.descendant(
            of: find.byType(GhstUserShell),
            matching: find.text('Cài đặt ứng dụng'),
          );
          expect(sidebarItem, findsOneWidget);
          await tester.tap(sidebarItem);
          await tester.pumpAndSettle();
        }

        expect(find.byType(CloudAppSettingsScreen), findsOneWidget);
        expect(find.text('Giao diện & Không gian làm việc'), findsOneWidget);
        expect(find.text('Thông báo & Cảnh báo thời gian thực'), findsOneWidget);
        expect(find.byType(Icon), findsNothing);
        expect(tester.takeException(), isNull);

        for (final element in find.byType(Text).evaluate()) {
          final widget = element.widget as Text;
          final raw = widget.data ?? widget.textSpan?.toPlainText() ?? '';
          expect(raw.contains('PostgreSQL'), isFalse, reason: raw);
          expect(raw.contains('Supabase'), isFalse, reason: raw);
          expect(raw.contains('Cloud'), isFalse, reason: raw);
          expect(raw.contains('/admin'), isFalse, reason: raw);
          expect(raw.contains('/legacy'), isFalse, reason: raw);
        }

        await tester.tap(find.byKey(const Key('theme-mode-dark')));
        await tester.pumpAndSettle();
        expect(themeController.themeMode, ThemeMode.dark);
        expect(api.uiPrefs['theme_mode'], 'dark');
        expect(tester.takeException(), isNull);

        if (width < 860) {
          await tester.tap(find.byTooltip('Quay lại'));
          await tester.pumpAndSettle();
          expect(find.byType(CloudAppSettingsScreen), findsNothing);
          await tester.tap(
            find.byKey(const ValueKey('ghst-mobile-header-settings')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(CloudAppSettingsScreen), findsOneWidget);
        } else {
          await tester.tap(find.text('Trang chủ'));
          await tester.pumpAndSettle();
          expect(find.byType(CloudAppSettingsScreen), findsNothing);
          await tester.tap(find.byKey(const ValueKey('ghst-header-settings')));
          await tester.pumpAndSettle();
          expect(find.byType(CloudAppSettingsScreen), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'App Settings syncs default role, notification categories, AI bubble visibility, password update, and data cleanup',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      final api = AppSettingsFixture()..approvedRoles = {'merchant', 'driver'};
      final session = CloudAccountSession(service: api);
      final themeController = ThemeController(
        session: session,
        sessionSlot: 'full-settings',
      );
      addTearDown(() async {
        themeController.dispose();
        session.dispose();
        await api.changes.close();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await session.refresh();
      await tester.pumpWidget(
        _buildHarness(session: session, themeController: themeController),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GhstAiFloatingBubble), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ghst-header-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(CloudAppSettingsScreen), findsOneWidget);

      Future<void> scrollAndTap(Finder finder) async {
        await Scrollable.ensureVisible(
          tester.element(finder),
          alignment: 0.3,
        );
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await scrollAndTap(
        find.byKey(const ValueKey('settings-toggle-ai-bubble')),
      );
      expect(themeController.showAiFloatingBubble, isFalse);
      expect(find.byType(GhstAiFloatingBubble), findsNothing);

      await scrollAndTap(
        find.byKey(const ValueKey('settings-default-role-driver')),
      );
      expect(api.uiPrefs['preferred_role'], 'driver');
      expect(
        tester.widget<GhstUserShell>(find.byType(GhstUserShell)).roleMode,
        GhstRoleMode.driver,
      );

      await tester.tap(find.byKey(const ValueKey('ghst-header-settings')));
      await tester.pumpAndSettle();

      await scrollAndTap(find.byKey(const ValueKey('settings-pref-promo')));
      expect(api.notifPrefs['promo_updates'], isFalse);
      expect(
        PushNotificationService.instance.preferences['promo_updates'],
        isFalse,
      );

      await scrollAndTap(
        find.byKey(const ValueKey('settings-change-password')),
      );

      await tester.enterText(
        find.byKey(const ValueKey('settings-new-password')),
        'short',
      );
      await tester.tap(find.byKey(const ValueKey('settings-submit-password')));
      await tester.pumpAndSettle();
      expect(
        find.text('Mật khẩu mới phải có tối thiểu 8 ký tự.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('settings-new-password')),
        'MatKhauMoi2026!',
      );
      await tester.enterText(
        find.byKey(const ValueKey('settings-confirm-password')),
        'KhongKhop2026!',
      );
      await tester.tap(find.byKey(const ValueKey('settings-submit-password')));
      await tester.pumpAndSettle();
      expect(
        find.text('Mật khẩu xác nhận chưa trùng khớp.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('settings-confirm-password')),
        'MatKhauMoi2026!',
      );
      await tester.tap(find.byKey(const ValueKey('settings-submit-password')));
      await tester.pumpAndSettle();
      expect(api.updatedPassword, 'MatKhauMoi2026!');
      expect(
        find.text('Đã cập nhật mật khẩu đăng nhập thành công.'),
        findsOneWidget,
      );

      expect(find.text('Đang có 1 bản nháp chưa gửi'), findsOneWidget);
      await scrollAndTap(find.byKey(const ValueKey('settings-clear-draft')));
      expect(api.savedDraft, isNull);
      expect(session.shippingDraft, isNull);
      expect(find.text('Trống'), findsOneWidget);

      await scrollAndTap(
        find.byKey(const ValueKey('settings-clear-ai-history')),
      );
      await tester.tap(find.byKey(const ValueKey('settings-confirm-clear-ai')));
      await tester.pumpAndSettle();
      expect(api.aiMessages, isEmpty);
      expect(
        find.text('Đã xóa lịch sử trò chuyện Trợ lý AI.'),
        findsOneWidget,
      );
    },
  );
}
