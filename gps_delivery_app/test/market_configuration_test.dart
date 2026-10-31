import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_session_lease.dart';
import 'package:gps_delivery_app/core/utils/market_options.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_view.dart';
import 'package:gps_delivery_app/presentation/widgets/market_catalog_fields.dart';
import 'package:gps_delivery_app/presentation/widgets/market_product_details.dart';
import 'package:gps_delivery_app/presentation/widgets/marketplace_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'marketplace_test.dart' show MarketFixture;

class ConfiguredFixture extends MarketFixture {
  List<Map<String, dynamic>> lines = [];
  Map<String, dynamic>? saved;
  final groups = [
    {
      'id': 'size',
      'name': 'Kich co',
      'min': 1,
      'max': 1,
      'options': [
        {'id': 'small', 'name': 'Nho', 'price': 5000},
        {'id': 'large', 'name': 'Lon', 'price': 15000},
      ],
    },
  ];
  @override
  Map<String, dynamic> get product => {
    ...super.product,
    'option_groups': groups,
    'preparation_minutes': 15,
  };
  @override
  Future<Map<String, dynamic>> market(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (action == 'product_details') {
      return {'product': product, 'favorite': false, 'reviews': []};
    }
    if (action == 'cart') return {'version': version, 'items': lines};
    if (action == 'product_save') {
      saved = payload;
      return {'product': payload};
    }
    if (action == 'cart_set') {
      calls.add({'action': action, 'payload': payload});
      expect(payload['version'], version);
      final selected = marketRows(payload['selected_options']);
      final existing = lines
          .where(
            (l) =>
                l['line_id'] == payload['line_id'] ||
                payload['line_id'] == null &&
                    marketSelectionKey(l['selected_options']) ==
                        marketSelectionKey(selected),
          )
          .firstOrNull;
      if (existing != null) lines.remove(existing);
      if (payload['quantity'] != 0) {
        lines.add({
          ...product,
          'line_id': existing?['line_id'] ?? 'line-${lines.length}',
          'quantity': payload['quantity'],
          'selected_options': existing?['selected_options'] ?? selected,
          'unit_price': 55000,
          'options': [
            {'group_name': 'Kich co', 'name': 'Nho'},
          ],
        });
      }
      return {'version': ++version, 'items': lines};
    }
    return super.market(action, payload);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Selection identity ignores order but preserves group and option identity',
    () {
      final a = [
        {'group_id': 'b', 'option_id': '1'},
        {'group_id': 'a', 'option_id': '2'},
      ];
      expect(marketSelectionKey(a), marketSelectionKey(a.reversed.toList()));
      expect(
        marketSelectionKey(a),
        isNot(
          marketSelectionKey([
            {'group_id': 'b', 'option_id': '2'},
          ]),
        ),
      );
      expect(MarketScheduleEditor.minute('24:00'), 1440);
      expect(MarketScheduleEditor.minute('24:01'), isNull);
      expect(MarketScheduleEditor.minute('12:60'), isNull);
    },
  );

  for (final width in [360.0, 1440.0]) {
    Future<(ConfiguredFixture, CloudAccountSession, CloudSessionLease)> fixture(
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      final api = ConfiguredFixture();
      final account = CloudAccountSession(service: api);
      await account.refresh();
      final lease = CloudSessionLease(session: account);
      addTearDown(() async {
        lease.dispose();
        account.dispose();
        await api.changes.close();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      return (api, account, lease);
    }

    testWidgets(
      'Required choices update price and are sent when adding from catalog at $width',
      (tester) async {
        final (api, session, _) = await fixture(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarketplaceView(session: session, view: MarketView.catalog),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Thêm vào giỏ'));
        await tester.pumpAndSettle();
        final add = find.widgetWithText(FilledButton, 'Thêm vào giỏ');
        expect(tester.widget<FilledButton>(add).onPressed, isNull);
        await tester.ensureVisible(find.text('Nho'));
        await tester.tap(find.text('Nho'));
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(add).onPressed, isNotNull);
        await tester.tap(add);
        await tester.pumpAndSettle();
        final payload =
            api.calls.lastWhere((c) => c['action'] == 'cart_set')['payload']
                as Map;
        expect(payload['selected_options'], [
          {'group_id': 'size', 'option_id': 'small'},
        ]);
        expect(payload['quantity'], 1);
        expect(payload.containsKey('price'), false);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'Cart updates and removes the selected line without touching another choice at $width',
      (tester) async {
        final (api, session, _) = await fixture(tester);
        api.lines = [
          for (final choice in ['small', 'large'])
            {
              ...api.product,
              'line_id': choice,
              'selected_options': [
                {'group_id': 'size', 'option_id': choice},
              ],
              'quantity': 1,
              'unit_price': choice == 'small' ? 55000 : 65000,
              'options': [
                {'group_name': 'Kich co', 'name': choice},
              ],
            },
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarketplaceView(session: session, view: MarketView.cart),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Xóa sản phẩm').first);
        await tester.pumpAndSettle();
        expect(
          api.calls.lastWhere(
            (c) => c['action'] == 'cart_set',
          )['payload']['line_id'],
          'small',
        );
        expect(api.lines.single['line_id'], 'large');
        expect(find.text('Kich co: large'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'Merchant edits choices, validates overlapping hours and saves structured configuration at $width',
      (tester) async {
        final (api, _, lease) = await fixture(tester);
        final p = {...api.product, 'version': 1, 'weight_kg': 1};
        await tester.pumpWidget(
          MaterialApp(
            home: MarketplaceEditor(
              service: api,
              lease: lease,
              shop: {'id': api.product['shop_id']},
              product: p,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(TextFormField, 'Phụ thu (đ)').first,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Phụ thu (đ)').first,
          '7000',
        );
        await tester.ensureVisible(find.text('Thêm khung giờ'));
        await tester.tap(find.text('Thêm khung giờ'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Lưu').last);
        await tester.pumpAndSettle();
        expect(find.text('08:00–17:00'), findsOneWidget);
        await tester.ensureVisible(find.text('Thêm khung giờ'));
        await tester.tap(find.text('Thêm khung giờ'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Lưu').last);
        await tester.pumpAndSettle();
        expect(find.text('Khung giờ bị trùng.'), findsOneWidget);
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Lưu'));
        await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
        await tester.pumpAndSettle();
        expect(api.saved?['option_groups'][0]['options'][0]['price'], 7000);
        expect(api.saved?['sale_schedule'], [
          {'day': 1, 'open': 480, 'close': 1020},
        ]);
        expect(api.saved?['preparation_minutes'], 15);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'Private product configuration disappears after account invalidation at $width',
      (tester) async {
        final (api, session, lease) = await fixture(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarketProductDetails(
                session: session,
                lease: lease,
                productId: api.product['id'],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Nho'), findsOneWidget);
        api.blocked = true;
        await session.refresh();
        await tester.pumpAndSettle();
        expect(find.text('Nho'), findsNothing);
        expect(find.text('Thêm vào giỏ'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
