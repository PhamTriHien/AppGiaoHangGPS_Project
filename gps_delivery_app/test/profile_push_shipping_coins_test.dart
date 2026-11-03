import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_notification_center.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_order_form.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_profile_form.dart';
import 'package:gps_delivery_app/presentation/widgets/system_state_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _SuiteCloudService extends CloudOrdersService {
  final changes = StreamController<AuthState>.broadcast();
  final calls = <Map<String, dynamic>>[];

  String uid = '00000000-0000-0000-0000-000000000088';
  String? birthDate;
  String? citizenId;
  int coinBalance = 15000;
  int unreadNotifications = 2;

  Map<String, bool> preferences = {
    'push_enabled': true,
    'shipping_updates': true,
    'market_updates': true,
    'promo_updates': true,
  };

  List<Map<String, dynamic>> notices = [
    {
      'id': '11111111-1111-1111-1111-111111111111',
      'category': 'shipping',
      'kind': 'order_delivered',
      'title': 'Đơn giao thành công · +400 Xu',
      'body': 'Vận đơn CL-8801 đã hoàn tất và cộng thưởng vào Ví Xu.',
      'reference_type': 'cloud_order',
      'reference_id': '22222222-2222-2222-2222-222222222222',
      'read_at': null,
      'created_at': '2026-11-03T03:00:00Z',
    },
    {
      'id': '11111111-1111-1111-1111-111111111112',
      'category': 'promo',
      'kind': 'coin_reward',
      'title': 'Điểm danh nhận Xu',
      'body': 'Bạn vừa nhận 500 Xu từ sự kiện điểm danh.',
      'reference_type': 'account',
      'reference_id': '00000000-0000-0000-0000-000000000088',
      'read_at': null,
      'created_at': '2026-11-03T02:00:00Z',
    },
  ];

  @override
  bool get signedIn => true;
  @override
  String get userId => uid;
  @override
  String get email => 'khachhang@ghst.vn';
  @override
  String get project => 'suite-project';
  @override
  Stream<AuthState> get authChanges => changes.stream;

  Map<String, dynamic> _profilePayload() {
    final verified =
        birthDate != null &&
        birthDate!.isNotEmpty &&
        citizenId != null &&
        citizenId!.length == 12;
    return {
      'account': {
        'user_id': uid,
        'full_name': 'Nguyễn Minh',
        'phone': '0901234567',
        'role': 'customer',
        'approved_roles': const <String>[],
        'memberships': const <Map<String, dynamic>>[],
        'staff_shops': const <Map<String, dynamic>>[],
        'blocked': false,
        'coin_balance': coinBalance,
        'birth_date': birthDate,
        'citizen_id': citizenId,
        'identity_verified': verified,
        'unread_notifications': unreadNotifications,
      },
      'operator': false,
      'schema_version': 3,
    };
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body, 'query': query});
    if (path == 'profile' && body == null) {
      return _profilePayload();
    }
    if (path == 'profile' && body != null) {
      if (body.containsKey('birth_date')) {
        final raw = '${body['birth_date'] ?? ''}'.trim();
        birthDate = raw.isEmpty ? null : raw;
      }
      if (body.containsKey('citizen_id')) {
        final raw = '${body['citizen_id'] ?? ''}'.trim();
        citizenId = raw.isEmpty ? null : raw;
      }
      return _profilePayload();
    }
    if (path.startsWith('notifications/')) {
      final action = path.substring('notifications/'.length);
      final payload = body ?? const <String, dynamic>{};
      if (action == 'unread_count') {
        final unreadItems = notices.where((e) => e['read_at'] == null).toList();
        return {
          'unread_count': unreadItems.length,
          'latest': unreadItems.isEmpty ? null : unreadItems.first,
          'preferences': preferences,
        };
      }
      if (action == 'list') {
        final cat = '${payload['category'] ?? 'all'}';
        final unreadOnly = payload['unread_only'] == true;
        final filtered = notices.where((n) {
          if (cat != 'all' && n['category'] != cat) return false;
          if (unreadOnly && n['read_at'] != null) return false;
          return true;
        }).toList();
        return {
          'notifications': filtered,
          'unread_count': notices.where((e) => e['read_at'] == null).length,
          'preferences': preferences,
          'next': null,
        };
      }
      if (action == 'mark_read') {
        final id = '${payload['id'] ?? ''}';
        notices = notices
            .map(
              (n) => n['id'] == id
                  ? {...n, 'read_at': '2026-11-03T03:05:00Z'}
                  : n,
            )
            .toList();
        unreadNotifications = notices.where((e) => e['read_at'] == null).length;
        return {'unread_count': unreadNotifications};
      }
      if (action == 'mark_all_read') {
        final cat = '${payload['category'] ?? 'all'}';
        notices = notices
            .map(
              (n) => (cat == 'all' || n['category'] == cat)
                  ? {...n, 'read_at': '2026-11-03T03:06:00Z'}
                  : n,
            )
            .toList();
        unreadNotifications = notices.where((e) => e['read_at'] == null).length;
        return {'unread_count': unreadNotifications};
      }
      if (action == 'save_preferences') {
        for (final key in preferences.keys.toList()) {
          if (payload[key] is bool) {
            preferences[key] = payload[key] as bool;
          }
        }
        return {'preferences': Map<String, bool>.from(preferences)};
      }
    }
    if (path == 'logistics/service_eta') {
      return {'services': const <String, dynamic>{}};
    }
    if (path == 'logistics/recipient_trust') {
      return {'delivered': 1, 'failed': 0, 'flagged': false};
    }
    if (path == 'quote') {
      final useCoins = body?['use_coins'] == true;
      const fee = 40000;
      final maxDisc = 8000;
      final disc = useCoins ? maxDisc : 0;
      return {
        'shipping_fee': fee,
        'coin_discount': disc,
        'payable_fee': fee - disc,
        'max_coin_discount': maxDisc,
        'available_coins': coinBalance,
        'distance_meters': 4200,
        'pricing_version': 2,
        'breakdown': {
          'base_fee': 18000,
          'distance_fee': 22000,
          'weight_fee': 0,
          'express_fee': 0,
        },
      };
    }
    if (path == 'orders' && body != null) {
      final details = body['details'] as Map<String, dynamic>?;
      final useCoins = details?['use_coins'] == true || body['use_coins'] == true;
      final disc = useCoins ? 8000 : 0;
      if (disc > 0) coinBalance -= disc;
      return {
        'order': {
          'id': '33333333-3333-3333-3333-333333333333',
          'tracking_code': 'CL-COIN01',
          'status': 'pending',
          'shipping_fee': 40000,
          'coin_discount': disc,
          'payable_fee': 40000 - disc,
        },
      };
    }
    return const {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Profile helpers format, parse, validate, and mask birth date & CCCD', () {
    expect(formatIsoBirthDate('2001-08-15'), '15/08/2001');
    expect(formatIsoBirthDate(null), '');
    expect(parseBirthDateToIso('15/08/2001'), '2001-08-15');
    expect(parseBirthDateToIso('15082001'), '2001-08-15');
    expect(parseBirthDateToIso('2001-08-15'), '2001-08-15');
    expect(parseBirthDateToIso('31/02/2020'), isNull);
    expect(parseBirthDateToIso('01/01/2099'), isNull);
    expect(maskCitizenId('079201001234'), '••••••••1234');
    expect(maskCitizenId('12345'), '');

    const fmt = BirthDateSlashFormatter();
    var v = TextEditingValue.empty;
    TextEditingValue type(String nextText) {
      v = fmt.formatEditUpdate(
        v,
        TextEditingValue(
          text: nextText,
          selection: TextSelection.collapsed(offset: nextText.length),
        ),
      );
      return v;
    }

    expect(type('1').text, '1');
    expect(type('15').text, '15/');
    expect(v.selection.baseOffset, 3);
    expect(type('15/0').text, '15/0');
    expect(type('15/08').text, '15/08/');
    expect(v.selection.baseOffset, 6);
    expect(type('15/08/2001').text, '15/08/2001');
    expect(v.selection.baseOffset, 10);

    // Backspace from '15/08/' removes trailing slash without getting stuck
    v = const TextEditingValue(
      text: '15/08/',
      selection: TextSelection.collapsed(offset: 6),
    );
    expect(type('15/08').text, '15/08');
    expect(type('15/0').text, '15/0');

    // Single-digit manual slash padding & ISO paste
    v = const TextEditingValue(
      text: '5',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(type('5/').text, '05/');
    v = TextEditingValue.empty;
    expect(type('2001-08-15').text, '15/08/2001');
  });

  testWidgets(
    'CloudProfileForm saves birth_date and 12-digit citizen_id and updates KYC badge',
    (tester) async {
      final service = _SuiteCloudService();
      final session = CloudAccountSession(service: service);
      addTearDown(() async {
        session.dispose();
        await service.changes.close();
      });
      await session.refresh();
      expect(session.identityVerified, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CloudProfileForm(session: session),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Bổ sung ngày tháng năm sinh và CCCD 12 số'),
        findsOneWidget,
      );

      final birthField = find.widgetWithText(
        TextFormField,
        'Ngày tháng năm sinh',
      );
      await tester.enterText(birthField, '15082001');
      await tester.pump();
      expect(
        tester.widget<TextFormField>(birthField).controller!.text,
        '15/08/2001',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số CCCD định danh'),
        '079201001234',
      );
      await tester.pump();

      final saveBtn = find.widgetWithText(FilledButton, 'Lưu hồ sơ');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      final saveCall = service.calls.lastWhere(
        (c) => c['path'] == 'profile' && c['body'] != null,
      );
      expect(saveCall['body']['birth_date'], '2001-08-15');
      expect(saveCall['body']['citizen_id'], '079201001234');
      expect(session.birthDate, '2001-08-15');
      expect(session.citizenId, '079201001234');
      expect(session.identityVerified, isTrue);
      expect(
        find.text('Đã định danh CCCD · Hồ sơ cá nhân đã xác thực'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'CloudNotificationCenter lists, filters, marks read, and updates preferences',
    (tester) async {
      final service = _SuiteCloudService();
      final session = CloudAccountSession(service: service);
      addTearDown(() async {
        session.dispose();
        await service.changes.close();
      });
      await session.refresh();

      String? openedOrderId;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudNotificationCenter(
              session: session,
              onOpenShippingOrder: (id) => openedOrderId = id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đơn giao thành công · +400 Xu'), findsOneWidget);
      expect(find.text('Điểm danh nhận Xu'), findsOneWidget);

      await tester.tap(find.text('Đơn giao thành công · +400 Xu'));
      await tester.pumpAndSettle();
      expect(openedOrderId, '22222222-2222-2222-2222-222222222222');
      expect(
        service.calls.any((c) => c['path'] == 'notifications/mark_read'),
        isTrue,
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Khuyến mãi'));
      await tester.pumpAndSettle();
      expect(find.text('Điểm danh nhận Xu'), findsOneWidget);
      expect(find.text('Đơn giao thành công · +400 Xu'), findsNothing);

      await tester.tap(find.text('Đọc tất cả'));
      await tester.pumpAndSettle();
      expect(
        service.calls.any((c) => c['path'] == 'notifications/mark_all_read'),
        isTrue,
      );

      await tester.tap(find.byTooltip('Tùy chọn thông báo đẩy'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Ưu đãi, sự kiện & Ví Xu'),
      );
      await tester.pumpAndSettle();
      expect(service.preferences['promo_updates'], isFalse);
    },
  );

  testWidgets(
    'CloudOrderForm quotes and creates shipping order with Xu redemption and payable_fee',
    (tester) async {
      final service = _SuiteCloudService();
      final session = CloudAccountSession(service: service);
      addTearDown(() async {
        session.dispose();
        await service.changes.close();
      });
      await session.refresh();
      expect(session.coinBalance, 15000);

      var createdCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudOrderForm(
              service: service,
              session: session,
              embedded: true,
              merchants: const [],
              onCreated: () => createdCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('15000 Xu khả dụng · Giảm tối đa 20% cước phí'),
        findsOneWidget,
      );

      tester
          .widget<Map3dPerspectiveWidget>(
            find.byKey(const ValueKey('cloud-order-google-map')),
          )
          .onTapGeoPoint!(const GeoPoint(latitude: 10.77, longitude: 106.70));
      await tester.pumpAndSettle();
      tester
          .widget<Map3dPerspectiveWidget>(
            find.byKey(const ValueKey('cloud-order-google-map')),
          )
          .onTapGeoPoint!(const GeoPoint(latitude: 10.79, longitude: 106.72));
      await tester.pumpAndSettle();

      for (final entry in {
        'Địa chỉ lấy hàng': '12 Nguyễn Huệ, Quận 1',
        'Địa chỉ giao hàng': '81 Điện Biên Phủ, Bình Thạnh',
        'Tên người nhận': 'Trần Văn B',
        'Số điện thoại người nhận': '0912345678',
        'Hàng hóa': 'Hộp quà',
        'Khối lượng': '2',
        'Tiền thu hộ': '0',
      }.entries) {
        final field = find.widgetWithText(TextFormField, entry.key);
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      await tester.pumpAndSettle();

      final coinSwitch = find.widgetWithText(
        SwitchListTile,
        'Dùng Xu giảm cước phí đơn hàng',
      );
      await tester.ensureVisible(coinSwitch);
      await tester.tap(coinSwitch);
      await tester.pumpAndSettle();

      final quoteBtn = find.widgetWithText(FilledButton, 'Lấy báo giá');
      await tester.ensureVisible(quoteBtn);
      await tester.tap(quoteBtn);
      await tester.pumpAndSettle();

      final quoteCall = service.calls.lastWhere((c) => c['path'] == 'quote');
      expect(quoteCall['body']['use_coins'], isTrue);
      expect(find.textContaining('Đổi Xu giảm cước:'), findsOneWidget);
      expect(find.textContaining('Cước cần thanh toán:'), findsOneWidget);

      final createBtn = find.widgetWithText(FilledButton, 'Xác nhận tạo đơn');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      final createCall = service.calls.lastWhere(
        (c) => c['path'] == 'orders' && c['body'] != null,
      );
      expect(createCall['body']['details']['use_coins'], isTrue);
      expect(createCall['body']['expected_fee'], 32000);
      expect(createdCalled, isTrue);
      expect(session.coinBalance, 7000);
    },
  );
}
