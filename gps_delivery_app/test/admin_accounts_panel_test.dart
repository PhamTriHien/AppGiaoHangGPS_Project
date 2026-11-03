import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/integrations/cloud_session_lease.dart';
import 'package:gps_delivery_app/presentation/screens/admin_portal_screen.dart';
import 'package:gps_delivery_app/presentation/widgets/admin_accounts_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AdminAccountsFixture extends CloudOrdersService {
  final calls = <Map<String, dynamic>>[];
  String candidateName = 'Ph?m Tr? Hi?n';
  String candidatePhone = '0901112223';
  bool candidateBlocked = false;
  bool candidateOperator = false;
  String? driverState = 'pending';
  int driverVersion = 1;
  String? merchantState;
  int merchantVersion = 0;
  bool incompleteCompleted = false;

  @override
  bool get signedIn => true;
  @override
  String get userId => '00000000-0000-0000-0000-000000000001';
  @override
  String get email => 'operator@example.com';
  @override
  String get project => 'admin-accounts-fixture';

  Map<String, dynamic> _operatorRow() => {
    'user_id': userId,
    'email': email,
    'email_confirmed': true,
    'auth_providers': ['email'],
    'created_at': '2026-10-30T08:00:00Z',
    'last_sign_in_at': '2026-11-03T00:00:00Z',
    'has_profile': true,
    'full_name': 'Điều hành Trung tâm',
    'phone': '0901234567',
    'role': 'customer',
    'blocked': false,
    'updated_at': '2026-11-03T00:00:00Z',
    'is_operator': true,
    'approved_roles': <String>[],
    'requested_role': null,
    'memberships': <Map<String, dynamic>>[],
    'coin_balance': 0,
    'shops_count': 0,
    'orders_count': 0,
    'driver_orders_count': 0,
    'active_driver_trips': 0,
  };

  Map<String, dynamic> _candidateRow() => {
    'user_id': '00000000-0000-0000-0000-000000000002',
    'email': 'partner-google@example.com',
    'email_confirmed': true,
    'auth_providers': ['google'],
    'created_at': '2026-11-01T08:00:00Z',
    'last_sign_in_at': '2026-11-02T14:00:00Z',
    'has_profile': true,
    'full_name': candidateName,
    'phone': candidatePhone,
    'role': driverState == 'active' ? 'driver' : 'customer',
    'blocked': candidateBlocked,
    'updated_at': '2026-11-02T14:00:00Z',
    'is_operator': candidateOperator,
    'approved_roles': [
      if (driverState == 'active') 'driver',
      if (merchantState == 'active') 'merchant',
    ],
    'requested_role': driverState == 'pending' ? 'driver' : null,
    'memberships': [
      if (driverState != null)
        {
          'role': 'driver',
          'state': driverState,
          'version': driverVersion,
          'reason': '',
        },
      if (merchantState != null)
        {
          'role': 'merchant',
          'state': merchantState,
          'version': merchantVersion,
          'reason': '',
        },
    ],
    'coin_balance': 500,
    'shops_count': merchantState == 'active' ? 1 : 0,
    'orders_count': 2,
    'driver_orders_count': 4,
    'active_driver_trips': 0,
  };

  Map<String, dynamic> _incompleteRow() => {
    'user_id': '00000000-0000-0000-0000-000000000003',
    'email': 'new-signup@example.com',
    'email_confirmed': false,
    'auth_providers': ['email'],
    'created_at': '2026-11-02T20:00:00Z',
    'last_sign_in_at': null,
    'has_profile': incompleteCompleted,
    'full_name': incompleteCompleted ? 'Khách Mới Đăng Ký' : '',
    'phone': incompleteCompleted ? '0988777666' : '',
    'role': 'customer',
    'blocked': false,
    'updated_at': null,
    'is_operator': false,
    'approved_roles': <String>[],
    'requested_role': null,
    'memberships': <Map<String, dynamic>>[],
    'coin_balance': 0,
    'shops_count': 0,
    'orders_count': 0,
    'driver_orders_count': 0,
    'active_driver_trips': 0,
  };

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body});
    if (path == 'profile') {
      return {
        'schema_version': 3,
        'operator': true,
        'account': _operatorRow(),
      };
    }
    if (path == 'marketplace/admin_analytics') {
      return {
        'cloud_orders': {'total': 5, 'searching': 1, 'in_transit': 1, 'delivered': 3, 'shipping_fee_delivered': 90000},
        'market_orders': {'total': 2, 'pending': 0, 'accepted_ready': 0, 'delivered': 2, 'cancelled': 0},
        'finance_totals': {'collections_completed': 100000, 'settlements_completed': 80000, 'refunds_completed': 0, 'pending_requests': 0},
        'shops': {'active': 1, 'pending': 0},
        'promotions': {'active_vouchers': 0, 'voucher_budget_used': 0, 'active_flash_sales': 0, 'coins_circulating': 500},
        'memberships_pending': driverState == 'pending' ? 1 : 0,
        'reported_reviews': 0,
        'ledger_balances': <String, dynamic>{},
      };
    }
    if (path == 'logistics/stats') {
      return {
        'scope': 'network',
        'summary': {'total': 5, 'delivered': 3, 'failed_or_returned': 0, 'cancelled': 0, 'active': 2, 'avg_delivery_minutes': 25, 'avg_transit_minutes': 15, 'by_service': const []},
        'pickups': {'requested': 0, 'assigned': 0},
        'drivers': {'approved': 1, 'on_trip': 0},
      };
    }
    if (path == 'admin-accounts/list') {
      final list = [_operatorRow(), _candidateRow(), _incompleteRow()];
      return {
        'accounts': list,
        'summary': {
          'total_accounts': 3,
          'completed_profiles': incompleteCompleted ? 3 : 2,
          'incomplete_profiles': incompleteCompleted ? 0 : 1,
          'operators': candidateOperator ? 2 : 1,
          'active_drivers': driverState == 'active' && !candidateBlocked ? 1 : 0,
          'active_merchants': merchantState == 'active' && !candidateBlocked ? 1 : 0,
          'pending_memberships': driverState == 'pending' ? 1 : 0,
          'blocked_accounts': candidateBlocked ? 1 : 0,
        },
      };
    }
    if (path == 'admin-accounts/update_profile') {
      if (body!['user_id'] == '00000000-0000-0000-0000-000000000003') {
        incompleteCompleted = true;
        return {'account': _incompleteRow()};
      }
      candidateName = '${body['full_name']}';
      candidatePhone = '${body['phone']}';
      return {'account': _candidateRow()};
    }
    if (path == 'admin-accounts/set_blocked') {
      candidateBlocked = body!['blocked'] == true;
      return {'account': _candidateRow()};
    }
    if (path == 'admin-accounts/set_operator') {
      candidateOperator = body!['operator'] == true;
      return {'account': _candidateRow()};
    }
    if (path == 'admin-accounts/detail') {
      return {
        'account': _candidateRow(),
        'shops': [
          {
            'id': 'shop-1',
            'name': 'Bếp Việt Quận 1',
            'status': 'active',
            'paused': false,
            'address': '12 Nguyễn Huệ, TP.HCM',
          },
        ],
        'audit': [
          {
            'id': 'au-1',
            'action': 'account_profile',
            'actor_id': userId,
            'actor_email': email,
            'after_value': {'reason': 'Chuẩn hóa dấu tiếng Việt'},
            'created_at': '2026-11-03T01:00:00Z',
          },
        ],
      };
    }
    if (path.endsWith('/memberships/driver')) {
      driverState = body!['decision'] == 'approve' ? 'active' : 'revoked';
      driverVersion++;
      return {
        'membership': {'role': 'driver', 'state': driverState, 'version': driverVersion},
      };
    }
    if (path.endsWith('/memberships/merchant')) {
      merchantState = 'active';
      merchantVersion = 1;
      return {
        'membership': {'role': 'merchant', 'state': 'active', 'version': 1},
      };
    }
    return {};
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'AdminAccountsPanel manages profile, partner grant/approval, operator role, lock guard and detail audit at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final api = _AdminAccountsFixture();
        final session = CloudAccountSession(service: api);
        addTearDown(session.dispose);
        await session.refresh();
        final lease = CloudSessionLease(session: session, operator: true);
        addTearDown(lease.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminAccountsPanel(session: session, lease: lease),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tổng tài khoản Auth'), findsOneWidget);
        expect(find.text('Google OAuth'), findsOneWidget);
        expect(find.text('Chưa hoàn tất hồ sơ'), findsWidgets);

        // Self-lock button on active operator account is disabled
        final selfLockButtons = tester
            .widgetList<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Khóa tài khoản'),
            )
            .toList();
        expect(selfLockButtons.first.onPressed, isNull);
        expect(selfLockButtons.last.onPressed, isNotNull);

        // Edit profile to fix garbled name
        final editBtn = find.widgetWithText(OutlinedButton, 'Sửa hồ sơ').last;
        await tester.ensureVisible(editBtn);
        await tester.pumpAndSettle();
        await tester.tap(editBtn);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Họ và tên'),
          'Phạm Trí Hiển',
        );
        await tester.tap(find.text('Lưu hồ sơ'));
        await tester.pumpAndSettle();
        expect(find.text('Phạm Trí Hiển'), findsOneWidget);

        // Approve pending Driver membership
        final approveDriver = find.text('Duyệt Tài xế');
        await tester.ensureVisible(approveDriver);
        await tester.pumpAndSettle();
        await tester.tap(approveDriver);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xác nhận'));
        await tester.pumpAndSettle();
        expect(find.text('Tài xế · Đã duyệt'), findsOneWidget);

        // Direct grant Merchant membership without pre-request
        final grantMerchant = find.text('Cấp quyền Cửa hàng').last;
        await tester.ensureVisible(grantMerchant);
        await tester.pumpAndSettle();
        await tester.tap(grantMerchant);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xác nhận'));
        await tester.pumpAndSettle();
        expect(find.text('Cửa hàng · Đã duyệt'), findsOneWidget);

        // Open detail & audit dialog
        final detailBtn = find
            .widgetWithText(OutlinedButton, 'Chi tiết & Phân quyền')
            .at(1);
        await tester.ensureVisible(detailBtn);
        await tester.pumpAndSettle();
        await tester.tap(detailBtn);
        await tester.pumpAndSettle();
        expect(find.textContaining('Bếp Việt Quận 1'), findsOneWidget);
        expect(find.textContaining('Cập nhật hồ sơ danh tính'), findsOneWidget);
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'AdminPortalScreen shortcut navigates to dedicated Accounts tab at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final api = _AdminAccountsFixture();
        final session = CloudAccountSession(service: api);
        addTearDown(session.dispose);
        await session.refresh();

        await tester.pumpWidget(
          MaterialApp(home: AdminPortalScreen(session: session)),
        );
        await tester.pumpAndSettle();

        final shortcut = find.text('Xét duyệt đối tác · 1');
        await tester.ensureVisible(shortcut);
        await tester.pumpAndSettle();
        await tester.tap(shortcut);
        await tester.pumpAndSettle();

        expect(
          find.text('Trung tâm Quản trị Danh tính & Phân quyền'),
          findsOneWidget,
        );
        expect(find.text('Ph?m Tr? Hi?n'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
