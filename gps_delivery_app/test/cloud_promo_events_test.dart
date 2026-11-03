import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_session_lease.dart';
import 'package:gps_delivery_app/core/theme/app_theme.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_promo_events_screen.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unified_user_interface_test.dart' show UnifiedUserFixture;

class _PromoFixture extends UnifiedUserFixture {
  int coins = 120;
  int spinTickets = 0;
  int boxTickets = 1;
  int streak = 0;
  bool checkedToday = false;
  int totalSpins = 0;
  int totalBoxes = 0;
  final Map<String, dynamic> openedBoxes = {};
  final List<Map<String, dynamic>> personalVouchers = [];
  final List<Map<String, dynamic>> history = [];

  Map<String, dynamic> _statusPayload({
    Map<String, dynamic>? reward,
    int? wheelSegment,
  }) => {
    'enabled': true,
    'server_date': '2026-11-03',
    'coin_balance': coins,
    'wheel_segment': ?wheelSegment,
    'reward': ?reward,
    'settings': {
      'enabled': true,
      'spin_ticket_coin_cost': 100,
      'box_ticket_coin_cost': 150,
      'voucher_20k_coin_cost': 200,
      'voucher_40k_coin_cost': 350,
      'version': 1,
    },
    'wallet': {
      'spin_tickets': spinTickets,
      'blind_box_tickets': boxTickets,
      'checkin_streak': streak,
      'checked_in_today': checkedToday,
      'opened_boxes': Map<String, dynamic>.from(openedBoxes),
      'total_spins': totalSpins,
      'total_boxes_opened': totalBoxes,
    },
    'checkin_schedule': [
      {'day': 1, 'coins': 50, 'spin_tickets': 1, 'box_tickets': 0},
      {'day': 2, 'coins': 80, 'spin_tickets': 0, 'box_tickets': 0},
    ],
    'missions': [
      {
        'id': 'first_shipping',
        'title': 'Chuyến giao hàng đầu tiên',
        'subtitle': 'Hoàn thành 1 đơn giao hàng Cloud thành công',
        'progress': 1,
        'target': 1,
        'coins': 100,
        'spin_tickets': 1,
        'box_tickets': 0,
        'claimed': false,
        'claimable': true,
      },
    ],
    'exchange_catalog': [
      {
        'id': 'spin_ticket',
        'title': '+1 Vé Vòng Xoay May Mắn',
        'subtitle': 'Quay thưởng Voucher Cloud hoặc Xu ngay lập tức',
        'coin_cost': 100,
        'kind': 'ticket',
      },
    ],
    'wheel_segments': [
      {'index': 0, 'label': '+50 Xu', 'rarity': 'Common'},
      {'index': 1, 'label': 'Voucher 15K', 'rarity': 'Common'},
      {'index': 2, 'label': '+1 Vé Hộp Mù', 'rarity': 'Rare'},
      {'index': 3, 'label': '+150 Xu', 'rarity': 'Rare'},
      {'index': 4, 'label': 'Voucher 25K', 'rarity': 'Rare'},
      {'index': 5, 'label': '+30 Xu Lộc', 'rarity': 'Common'},
      {'index': 6, 'label': 'Giảm 50% · 35K', 'rarity': 'Epic'},
      {'index': 7, 'label': 'Siêu Cấp 50K', 'rarity': 'Legendary'},
    ],
    'vouchers': List<Map<String, dynamic>>.from(personalVouchers),
    'flash_sales': const [],
    'history': List<Map<String, dynamic>>.from(history),
  };

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == 'profile') {
      final base = await super.request(path, body: body, query: query);
      final acc = Map<String, dynamic>.from(base['account'] as Map);
      acc['coin_balance'] = coins;
      return {...base, 'account': acc};
    }
    if (path == 'promo-events/status') {
      calls.add({'path': path, 'body': body});
      return _statusPayload();
    }
    if (path == 'promo-events/checkin') {
      calls.add({'path': path, 'body': body});
      checkedToday = true;
      streak = 1;
      coins += 50;
      spinTickets += 1;
      final reward = {
        'rarity': 'Common',
        'title': 'Điểm danh Ngày 1',
        'summary': '+50 Xu & +1 Vé Vòng Xoay Cloud',
      };
      history.insert(0, {
        ...reward,
        'id': 'h-checkin',
        'created_at': '2026-11-03T05:00:00Z',
      });
      return _statusPayload(reward: reward);
    }
    if (path == 'promo-events/spin_wheel') {
      calls.add({'path': path, 'body': body});
      spinTickets -= 1;
      totalSpins += 1;
      const voucherCode = 'SPIN25-ABCD1234';
      personalVouchers.insert(0, {
        'id': 'v-1',
        'code': voucherCode,
        'personal': true,
        'title': 'Voucher Vòng Xoay 25.000đ',
        'discount_kind': 'fixed',
        'discount_value': 25000,
        'max_discount': 25000,
        'min_subtotal': 99000,
        'ends_at': '2026-11-10T05:00:00Z',
      });
      final reward = {
        'rarity': 'Rare',
        'title': 'Trúng Voucher 25.000đ',
        'summary': 'Đã cấp riêng cho tài khoản của bạn trên Cloud.',
        'voucher_code': voucherCode,
      };
      history.insert(0, {
        ...reward,
        'id': 'h-spin',
        'created_at': '2026-11-03T05:01:00Z',
      });
      return _statusPayload(reward: reward, wheelSegment: 4);
    }
    if (path == 'promo-events/open_blind_box') {
      calls.add({'path': path, 'body': body});
      boxTickets -= 1;
      totalBoxes += 1;
      final idx = '${body?['box_index'] ?? 0}';
      openedBoxes[idx] = {
        'rarity': 'SSR',
        'title': 'Kho Báu +300 Xu',
        'voucher_code': null,
      };
      coins += 300;
      final reward = {
        'rarity': 'SSR',
        'title': 'Hộp Mù SSR: +300 Xu',
        'summary': 'Đã cộng trực tiếp vào Ví Xu Cloud.',
      };
      return _statusPayload(reward: reward);
    }
    if (path == 'promo-events/exchange_coins') {
      calls.add({'path': path, 'body': body});
      coins -= 100;
      spinTickets += 1;
      return _statusPayload(
        reward: {
          'rarity': 'Common',
          'title': 'Đổi thành công +1 Vé Vòng Xoay',
          'summary': 'Đã trừ 100 Xu khỏi Ví Xu Cloud.',
        },
      );
    }
    return super.request(path, body: body, query: query);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'GhstHomeScreen renders Promo Hub and opens CloudPromoEventsScreen at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        final api = _PromoFixture();
        final session = CloudAccountSession(service: api);
        addTearDown(() async {
          session.dispose();
          await api.changes.close();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await session.refresh();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: MarketplaceScreen(session: session),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Săn Voucher • Flash Sale • Vòng Xoay'),
          findsOneWidget,
        );
        final spinTile = find.byKey(const ValueKey('home-promo-tab-1'));
        await tester.ensureVisible(spinTile);
        await tester.pumpAndSettle();
        await tester.tap(spinTile);
        await tester.pumpAndSettle();

        expect(find.byType(CloudPromoEventsScreen), findsOneWidget);
        expect(find.text('VÒNG XOAY MAY MẮN'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'CloudPromoEventsScreen syncs checkin, spin wheel, blind box, exchange & personal voucher at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        final api = _PromoFixture();
        final session = CloudAccountSession(service: api);
        await session.refresh();
        final lease = CloudSessionLease(session: session);
        addTearDown(() async {
          lease.dispose();
          session.dispose();
          await api.changes.close();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: CloudPromoEventsScreen(session: session, lease: lease),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Daily Check-in
        final checkinBtn = find.byKey(const ValueKey('btn-promo-checkin'));
        await tester.ensureVisible(checkinBtn);
        await tester.tap(checkinBtn);
        await tester.pumpAndSettle();
        expect(find.text('Điểm danh Ngày 1'), findsOneWidget);
        await tester.tap(find.text('Tuyệt vời'));
        await tester.pumpAndSettle();
        expect(find.text('Ví Xu: 170 Xu'), findsOneWidget);

        // 2. Coin Exchange (+1 Spin Ticket for 100 Coins)
        final exchangeBtn = find.text('Đổi 100 Xu');
        await tester.ensureVisible(exchangeBtn);
        await tester.pumpAndSettle();
        await tester.tap(exchangeBtn);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tuyệt vời'));
        await tester.pumpAndSettle();
        expect(find.text('Vé Vòng Xoay: 2'), findsOneWidget);

        // 3. Spin Wheel -> Server mints personal voucher SPIN25-ABCD1234
        final spinTab = find.text('Vòng Xoay');
        await tester.ensureVisible(spinTab);
        await tester.pumpAndSettle();
        await tester.tap(spinTab);
        await tester.pumpAndSettle();
        final spinBtn = find.byKey(const ValueKey('btn-promo-spin'));
        await tester.ensureVisible(spinBtn);
        await tester.pumpAndSettle();
        await tester.tap(spinBtn);
        await tester.pumpAndSettle();
        expect(find.text('Trúng Voucher 25.000đ'), findsOneWidget);
        expect(find.text('SPIN25-ABCD1234'), findsOneWidget);
        await tester.tap(find.text('Tuyệt vời'));
        await tester.pumpAndSettle();

        // 4. Open Mystery Blind Box #1
        final boxTab = find.text('Hộp Mù');
        await tester.ensureVisible(boxTab);
        await tester.pumpAndSettle();
        await tester.tap(boxTab);
        await tester.pumpAndSettle();
        final box0 = find.byKey(const ValueKey('blind-box-0'));
        await tester.ensureVisible(box0);
        await tester.pumpAndSettle();
        await tester.tap(box0);
        await tester.pumpAndSettle();
        expect(find.text('Hộp Mù SSR: +300 Xu'), findsOneWidget);
        await tester.tap(find.text('Tuyệt vời'));
        await tester.pumpAndSettle();
        expect(find.text('HẠNG SSR'), findsOneWidget);

        // 5. Personal Voucher Wallet & History
        final voucherTab = find.text('Kho Voucher');
        await tester.ensureVisible(voucherTab);
        await tester.pumpAndSettle();
        await tester.tap(voucherTab);
        await tester.pumpAndSettle();
        expect(find.text('CÁ NHÂN'), findsOneWidget);
        expect(find.textContaining('SPIN25-ABCD1234'), findsWidgets);

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
