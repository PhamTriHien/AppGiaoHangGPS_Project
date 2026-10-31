import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/integrations/cloud_session_lease.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_local_import_screen.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_orders_screen.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_view.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_profile_form.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PartnerImportFixture extends CloudOrdersService {
  bool operator = false, blocked = false;
  final memberships = <Map<String, dynamic>>[];
  final calls = <Map<String, dynamic>>[];
  final importItems = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? pending;
  @override
  bool get signedIn => true;
  @override
  String get userId => 'buyer';
  @override
  String get email => 'buyer@example.com';
  @override
  String get project => 'isolated-fixture';
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body});
    final account = {
      'user_id': 'buyer',
      'role': 'customer',
      'full_name': 'Người nhận kiểm thử',
      'phone': '0901234567',
      'blocked': blocked,
      'approved_roles': [
        for (final m in memberships)
          if (m['state'] == 'active') m['role'],
      ],
      'memberships': [
        for (final m in memberships) {...m},
      ],
    };
    if (path == 'profile') {
      return {'schema_version': 3, 'operator': operator, 'account': account};
    }
    if (path == 'memberships') {
      memberships.add({
        'role': body!['role'],
        'state': 'pending',
        'version': 1,
        'reason': '',
      });
      return {'ok': true};
    }
    if (path == 'accounts') {
      return {
        'accounts': [account],
      };
    }
    if (path.contains('/memberships/')) {
      final m = memberships.firstWhere(
        (m) => m['role'] == path.split('/').last,
      );
      m['state'] = switch (body!['decision']) {
        'approve' => 'active',
        'reject' => 'rejected',
        _ => 'revoked',
      };
      m['reason'] = body['reason'];
      m['version'] = (m['version'] as int) + 1;
      return {
        'membership': {...m},
      };
    }
    if (path.startsWith('imports/')) {
      if (pending != null) return pending!.future;
      final items = (body!['items'] as List).cast<Map>();
      if (path.endsWith('commit')) {
        importItems.addAll(items.map((m) => Map<String, dynamic>.from(m)));
      }
      return {
        'ready': items.length,
        'rows': [
          for (final item in items) {...item, 'status': 'ready', 'problem': ''},
        ],
        'committed': path.endsWith('commit'),
      };
    }
    if (path == 'orders') return {'orders': []};
    if (path == 'merchants') return {'merchants': []};
    return {};
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<CloudAccountSession> session(PartnerImportFixture api) async {
    final s = CloudAccountSession(service: api);
    addTearDown(s.dispose);
    await s.refresh();
    return s;
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  final source = {
    'source_instance': 'test-device',
    'source_id': 'local-user',
    'source_name': 'Chủ dữ liệu cũ',
    'draft_count': 2,
    'addresses': [
      {
        'source_id': 'local-address',
        'details': {
          'label': 'Nhà riêng',
          'recipient_name': 'Người nhận kiểm thử',
          'recipient_phone': '0901234567',
          'full_address': '12 Nguyễn Huệ',
          'latitude': 10.77,
          'longitude': 106.7,
        },
      },
    ],
  };

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'Each partner request has independent status and workspaces at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final api = PartnerImportFixture();
        final current = await session(api);
        final lease = CloudSessionLease(session: current, profile: true);
        addTearDown(lease.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CloudProfileForm(session: current, lease: lease),
              ),
            ),
          ),
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('request-merchant')),
        );
        await tester.tap(find.byKey(const ValueKey('request-merchant')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('request-merchant')), findsNothing);
        expect(find.byKey(const ValueKey('request-driver')), findsOneWidget);
        expect(current.approvedRoles, {'customer'});
        await tester.ensureVisible(
          find.byKey(const ValueKey('request-driver')),
        );
        await tester.tap(find.byKey(const ValueKey('request-driver')));
        await tester.pumpAndSettle();
        expect(find.text('Chờ duyệt'), findsNWidgets(2));
        for (final membership in api.memberships) {
          membership['state'] = 'active';
        }
        await current.refresh();
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarketplaceView(
                session: current,
                view: MarketView.account,
                key: UniqueKey(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Cửa hàng của tôi'), findsOneWidget);
        expect(find.text('Chuyến giao của tôi'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Import source stays local, needs preview and explicit confirmation at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final api = PartnerImportFixture();
        final s = await session(api);
        final activeLease = CloudSessionLease(session: s);
        addTearDown(activeLease.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: CloudLocalImportScreen(
              session: s,
              lease: activeLease,
              readSource: ({required identifier, required password}) async {
                expect(identifier, 'old-user');
                expect(password, 'local-only-password');
                return source;
              },
            ),
          ),
        );
        await tester.enterText(field('Tài khoản trên thiết bị'), 'old-user');
        await tester.enterText(
          field('Mật khẩu trên thiết bị'),
          'local-only-password',
        );
        await tester.tap(find.text('Xác minh nguồn'));
        await tester.pumpAndSettle();
        expect(
          api.calls.where((c) => c['path'].toString().startsWith('imports/')),
          isEmpty,
        );
        await tester.tap(find.byType(CheckboxListTile).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kiểm tra bản ghi đã chọn'));
        await tester.pumpAndSettle();
        expect(api.calls.last['path'], 'imports/preview');
        expect(
          api.calls.last.toString(),
          isNot(contains('local-only-password')),
        );
        expect(api.calls.last.toString(), isNot(contains('old-user')));
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Nhập địa chỉ'),
              )
              .onPressed,
          isNull,
        );
        await tester.ensureVisible(find.byType(CheckboxListTile).last);
        await tester.tap(find.byType(CheckboxListTile).last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Nhập địa chỉ'));
        await tester.tap(find.text('Nhập địa chỉ'));
        await tester.pumpAndSettle();
        expect(api.importItems.length, 1);
        expect(find.text('Đã nhập 1 địa chỉ.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Late source read is discarded after session invalidation', (
    tester,
  ) async {
    final api = PartnerImportFixture(),
        pending = Completer<Map<String, dynamic>>();
    final s = await session(api);
    final active = CloudSessionLease(session: s);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudLocalImportScreen(
          session: s,
          lease: active,
          readSource: ({required identifier, required password}) =>
              pending.future,
        ),
      ),
    );
    await tester.enterText(field('Tài khoản trên thiết bị'), 'old-user');
    await tester.enterText(
      field('Mật khẩu trên thiết bị'),
      'local-only-password',
    );
    await tester.tap(find.text('Xác minh nguồn'));
    await tester.pump();
    s.invalidateVerification();
    pending.complete(source);
    await tester.pumpAndSettle();
    expect(find.text('Chủ dữ liệu cũ'), findsNothing);
    expect(find.text('12 Nguyễn Huệ'), findsNothing);
    expect(find.text('Phiên làm việc đã thay đổi.'), findsOneWidget);
    expect(api.importItems, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Operator approves a specific partner membership and requires a reason for revoke',
    (tester) async {
      final api = PartnerImportFixture()..operator = true;
      api.memberships.add({
        'role': 'driver',
        'state': 'pending',
        'version': 1,
        'reason': '',
      });
      final s = await session(api);
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(session: s, admin: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tài khoản'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Duyệt Tài xế'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(api.memberships.single['state'], 'active');
      await tester.tap(find.text('Tài khoản'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thu hồi Tài xế'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập lý do ít nhất 3 ký tự.'), findsOneWidget);
      expect(api.memberships.single['state'], 'active');
      await tester.enterText(find.byType(TextFormField), 'Ngừng cộng tác');
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(api.memberships.single['state'], 'revoked');
      expect(
        api.calls
            .where((c) => c['path'].toString().contains('/memberships/'))
            .last['body'],
        {'decision': 'revoke', 'version': 2, 'reason': 'Ngừng cộng tác'},
      );
    },
  );
}
