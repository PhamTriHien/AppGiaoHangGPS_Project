import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/integrations/cloud_session_lease.dart';
import 'package:gps_delivery_app/core/theme/app_theme.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/presentation/customer/ghst_user_shell.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_order_details_screen.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_screen.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_view.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_session_boundary.dart';
import 'package:gps_delivery_app/presentation/widgets/marketplace_editor.dart';
import 'package:gps_delivery_app/presentation/widgets/merchant_cloud_panels.dart';
import 'package:gps_delivery_app/presentation/widgets/system_state_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MerchantSuiteFixture extends CloudOrdersService {
  bool authenticated = true;
  bool operator = false;
  bool blocked = false;
  String id = 'merchant-owner-1';
  String role = 'merchant';
  List<Map<String, dynamic>> staffShops = const [];
  final changes = StreamController<AuthState>.broadcast();
  final calls = <Map<String, dynamic>>[];

  bool shopPaused = false;
  int shopVersion = 2;
  bool productPublished = true;
  int productStock = 8;
  int productVersion = 3;
  String orderState = 'pending';
  int orderVersion = 1;
  bool voucherActive = true;
  String returnState = 'requested';
  String reviewReply = '';
  final List<Map<String, dynamic>> liveChatMessages = [
    {
      'id': 'live-msg-1',
      'sender_role': 'driver',
      'sender_name': 'Tài xế Nguyễn Hoàng',
      'body': 'Tôi đang cách cửa hàng 400m để nhận kiện hàng.',
      'created_at': '2026-11-04T06:00:00Z',
    },
  ];

  @override
  bool get signedIn => authenticated;

  @override
  String get userId => authenticated ? id : '';

  @override
  String get email => '$id@ghst.vn';

  @override
  String get project => 'ghst-prod';

  @override
  String get identityScope => 'ghst-prod:$userId';

  @override
  Stream<AuthState> get authChanges => changes.stream;

  @override
  Future<void> signOut() async {
    authenticated = false;
    changes.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  Map<String, dynamic> get shopRow => {
    'id': 'shop-1',
    'owner_id': 'merchant-owner-1',
    'name': 'Bếp Cơm Nhà Sài Gòn',
    'description': 'Cơm trưa văn phòng chuẩn vị truyền thống',
    'address': '86 Nguyễn Huệ, Quận 1, TP.HCM',
    'latitude': 10.7745,
    'longitude': 106.7035,
    'status': 'active',
    'paused': shopPaused,
    'open_now': true,
    'service_radius_km': 12,
    'version': shopVersion,
    'my_role': role == 'merchant'
        ? 'owner'
        : (staffShops.firstOrNull?['role'] ?? 'staff'),
  };

  Map<String, dynamic> get productRow => {
    'id': 'prod-1',
    'shop_id': 'shop-1',
    'name': 'Cơm tấm sườn bì chả đặc biệt',
    'sku': 'CT-SBC-01',
    'category': 'Thực phẩm',
    'price': 65000,
    'stock': productStock,
    'published': productPublished,
    'version': productVersion,
    'variants': [
      {
        'id': 'var-1',
        'sku': 'CT-SBC-STD',
        'title': 'Phần tiêu chuẩn',
        'price': 65000,
        'stock': productStock,
        'published': true,
      },
    ],
  };

  Map<String, dynamic> get deliveryOrderRow => {
    'id': 'deliv-101',
    'owner_id': 'merchant-owner-1',
    'driver_id': 'driver-9',
    'tracking_code': 'CL-889900112233445566778899AABBCCDD',
    'status': 'inTransit',
    'service_type': 'express',
    'shipping_fee': 28000,
    'payable_fee': 28000,
    'cod_amount': 130000,
    'payment_status': 'UNPAID',
    'distance_meters': 3400,
    'pickup_lat': 10.7745,
    'pickup_lng': 106.7035,
    'dropoff_lat': 10.7812,
    'dropoff_lng': 106.6951,
    'latest_gps': {
      'lat': 10.7780,
      'lng': 106.6990,
      'recorded_at': '2026-11-04T06:02:00Z',
    },
    'driver_profile': {
      'full_name': 'Nguyễn Hoàng',
      'phone': '0908887766',
    },
    'details': {
      'pickup_address': '86 Nguyễn Huệ, Quận 1, TP.HCM',
      'dropoff_address': '120 Võ Văn Tần, Quận 3, TP.HCM',
      'recipient_name': 'Lê Minh Khôi',
      'recipient_phone': '0912345678',
      'package_description': '2 × Cơm tấm sườn bì chả đặc biệt',
      'require_otp': true,
    },
  };

  Map<String, dynamic> get merchantOrderRow => {
    'id': 'mord-1',
    'owner_id': 'buyer-1',
    'merchant_id': 'merchant-owner-1',
    'shop_id': 'shop-1',
    'shop_name': 'Bếp Cơm Nhà Sài Gòn',
    'purchase_id': 'pur-1',
    'state': orderState,
    'version': orderVersion,
    'payment_method': 'cod',
    'payment_status': 'UNPAID',
    'accept_by': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 11))
        .toIso8601String(),
    'delivery_id': orderState == 'ready' ? 'deliv-101' : null,
    'tracking_code': orderState == 'ready'
        ? deliveryOrderRow['tracking_code']
        : null,
    'delivery_status': orderState == 'ready' ? 'inTransit' : null,
    'delivery_order': orderState == 'ready' ? deliveryOrderRow : null,
    'shipments': orderState == 'ready'
        ? [
            {
              'id': 'mship-1',
              'parcel_index': 1,
              'delivery_id': 'deliv-101',
              'tracking_code': deliveryOrderRow['tracking_code'],
              'status': 'inTransit',
              'delivery_order': deliveryOrderRow,
            },
          ]
        : const [],
    'open_returns_count': 0,
    'message_count': 2,
    'buyer_profile': {
      'full_name': 'Lê Minh Khôi',
      'phone': '0912345678',
    },
    'snapshot': {
      'shop_name': 'Bếp Cơm Nhà Sài Gòn',
      'subtotal': 130000,
      'payable_subtotal': 130000,
      'shipping_fee': 28000,
      'buyer_note': 'Thêm nước mắm ớt riêng giúp mình',
      'address': {'full_address': '120 Võ Văn Tần, Quận 3, TP.HCM'},
      'items': [
        {
          'line_id': 'line-1',
          'product_id': 'prod-1',
          'name': 'Cơm tấm sườn bì chả đặc biệt',
          'quantity': 2,
          'unit_price': 65000,
        },
      ],
    },
  };

  @override
  Future<Map<String, dynamic>> command(
    String path,
    Map<String, dynamic> payload,
  ) async {
    calls.add({'method': 'command', 'path': path, 'body': payload});
    return request(path, body: payload);
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body, 'query': query});
    if (path == 'profile') {
      final isDirectMerchant = role == 'merchant';
      return {
        'operator': operator,
        'schema_version': 3,
        'account': {
          'user_id': id,
          'full_name': isDirectMerchant ? 'Chủ quán Minh Tâm' : 'Nhân sự Thu Hà',
          'phone': '0909112233',
          'role': role,
          'blocked': blocked,
          'requested_role': null,
          'approved_roles': isDirectMerchant ? ['merchant'] : <String>[],
          'memberships': isDirectMerchant
              ? [
                  {'role': 'merchant', 'state': 'active', 'version': 1},
                ]
              : <Map<String, dynamic>>[],
          'staff_shops': staffShops,
          'coin_balance': 12000,
        },
      };
    }
    if (path.startsWith('preferences/')) {
      return {
        'ui_preferences': {
          if (body?['theme_mode'] != null) 'theme_mode': body!['theme_mode'],
          if (body?['preferred_role'] != null)
            'preferred_role': body!['preferred_role'],
        },
      };
    }
    if (path.startsWith('notifications/')) {
      return {'unread_count': 0, 'items': const []};
    }
    if (path == 'logistics/stats') {
      return {
        'scope': 'self',
        'summary': {
          'total': 12,
          'delivered': 11,
          'failed_or_returned': 0,
          'cancelled': 1,
          'active': 1,
          'by_service': const [],
        },
      };
    }
    if (path == 'logistics/pickup_list') {
      return {'pickups': const [], 'drivers': const []};
    }
    if (path == 'orders/deliv-101/history') {
      return {
        'history': [
          {
            'order_id': 'deliv-101',
            'version': 1,
            'action': 'pickup',
            'status': 'inTransit',
            'created_at': '2026-11-04T05:55:00Z',
          },
        ],
      };
    }
    if (path == 'order-live/snapshot') {
      return {
        'order': deliveryOrderRow,
        'gps_trail': [deliveryOrderRow['latest_gps']],
        'messages': liveChatMessages,
      };
    }
    if (path == 'order-live/send_chat') {
      final msg = {
        'id': 'live-msg-${liveChatMessages.length + 1}',
        'sender_role': 'merchant',
        'sender_name': role == 'merchant'
            ? 'Chủ quán Minh Tâm'
            : 'Nhân sự Thu Hà',
        'text': '${body?['text'] ?? body?['body'] ?? ''}',
        'created_at': '2026-11-04T06:05:00Z',
      };
      liveChatMessages.add(msg);
      return {'ok': true, 'message': msg, 'messages': liveChatMessages};
    }
    if (path == 'marketplace/finance_request') {
      return {'ok': true};
    }
    if (path.startsWith('merchant/')) {
      final action = path.substring('merchant/'.length);
      final myRole = operator
          ? 'operator'
          : (role == 'merchant'
                ? 'owner'
                : '${staffShops.firstOrNull?['role'] ?? 'staff'}');
      final canManage = const {'owner', 'manager', 'operator'}.contains(myRole);

      if (action == 'dashboard') {
        return {
          'shops': [shopRow],
          'selected_shop_id': 'shop-1',
          'my_role': myRole,
          'kpis': {
            'orders': {
              'pending': orderState == 'pending' ? 1 : 0,
              'overdue_pending': 0,
              'accepted': orderState == 'accepted' ? 1 : 0,
              'ready': orderState == 'ready' ? 1 : 0,
              'in_transit': orderState == 'ready' ? 1 : 0,
              'delivered': 14,
            },
            'catalog': {
              'products_total': 1,
              'published_count': productPublished ? 1 : 0,
              'low_stock_count': productStock <= 5 && productStock > 0 ? 1 : 0,
              'out_of_stock_count': productStock <= 0 ? 1 : 0,
            },
            'aftersales': {
              'open_returns': returnState == 'requested' ? 1 : 0,
              'unreplied_reviews': reviewReply.isEmpty ? 1 : 0,
              'active_vouchers': voucherActive ? 1 : 0,
              'active_flash_sales': 1,
            },
            'finance': canManage
                ? {
                    'gross_subtotal': 4200000,
                    'collected_total': 3900000,
                    'refunded_total': 0,
                    'settled_total': 2500000,
                    'pending_settlement_total': 350000,
                    'eligible_settlement_total': 1050000,
                    'eligible_orders': [
                      {
                        'order_id': 'mord-settled-1',
                        'delivered_at': '2026-10-20T09:00:00Z',
                        'eligible_amount': 1050000,
                      },
                    ],
                  }
                : null,
          },
        };
      }
      if (action == 'shop_quick_pause') {
        shopPaused = body?['paused'] == true;
        shopVersion++;
        return {'shop': shopRow};
      }
      if (action == 'product_quick_update') {
        if (body?.containsKey('published') == true) {
          productPublished = body!['published'] == true;
        }
        if (body?.containsKey('stock') == true) {
          productStock = (body!['stock'] as num).toInt();
        }
        productVersion++;
        return {'product': productRow};
      }
      if (action == 'stock_ledger') {
        return {
          'entries': [
            {
              'id': 'led-1',
              'product_name': productRow['name'],
              'product_sku': productRow['sku'],
              'delta': 10,
              'stock_after': productStock,
              'reason': 'merchant_quick_adjust',
              'actor_name': 'Chủ quán Minh Tâm',
              'created_at': '2026-11-04T05:30:00Z',
            },
          ],
          'next': null,
        };
      }
      if (action == 'orders_list') {
        return {
          'orders': [merchantOrderRow],
          'next': null,
        };
      }
      if (action == 'promotions') {
        return {
          'vouchers': [
            {
              'id': 'vch-1',
              'version': 1,
              'shop_id': 'shop-1',
              'code': 'COMNHA15K',
              'title': 'Giảm 15K đơn trưa',
              'discount_kind': 'fixed',
              'discount_value': 15000,
              'max_discount': 15000,
              'min_subtotal': 80000,
              'budget_total': 1500000,
              'budget_used': 300000,
              'usage_count': 20,
              'per_user_limit': 2,
              'starts_at': '2026-11-01T00:00:00Z',
              'ends_at': '2026-12-01T00:00:00Z',
              'active': voucherActive,
            },
          ],
          'flash_sales': [
            {
              'id': 'fs-1',
              'version': 1,
              'product_id': 'prod-1',
              'product_name': productRow['name'],
              'product_sku': productRow['sku'],
              'original_price': 65000,
              'sale_price': 52000,
              'allocated_stock': 20,
              'sold_stock': 6,
              'per_user_limit': 2,
              'starts_at': '2026-11-04T04:00:00Z',
              'ends_at': '2026-11-05T04:00:00Z',
              'active': true,
            },
          ],
        };
      }
      if (action == 'aftersales_inbox') {
        final tab = '${body?['tab'] ?? 'all'}';
        return {
          'finance': tab == 'finance' && canManage
              ? [
                  {
                    'id': 'fin-1',
                    'order_id': 'mord-prev-1',
                    'kind': 'settlement',
                    'amount': 2500000,
                    'state': 'completed',
                    'created_at': '2026-11-01T08:00:00Z',
                  },
                ]
              : const [],
          'returns': [
            {
              'id': 'ret-open-1',
              'order_id': 'mord-1',
              'quantity': 1,
              'item_name': productRow['name'],
              'state': returnState,
              'version': 1,
              'reason': 'Hộp canh bị nghiêng nhẹ khi giao',
              'buyer_name': 'Lê Minh Khôi',
              'buyer_phone': '0912345678',
              'attachments': const [],
            },
          ],
          'reviews': [
            {
              'id': 'rev-1',
              'review_kind': 'partner',
              'target_title': 'Bếp Cơm Nhà Sài Gòn',
              'reviewer_name': 'Lê Minh Khôi',
              'rating': 5,
              'body': 'Sườn nướng thơm mềm, đóng gói sạch sẽ!',
              'reply': reviewReply,
              'created_at': '2026-11-03T12:00:00Z',
            },
          ],
          'summary': {
            'shop_rating_avg': 4.9,
            'shop_rating_count': 28,
            'product_rating_avg': 4.8,
            'product_rating_count': 41,
            'unreplied_count': reviewReply.isEmpty ? 1 : 0,
          },
        };
      }
      return {'ok': true};
    }
    if (path.startsWith('marketplace/')) {
      return market(path.substring('marketplace/'.length), body ?? const {});
    }
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> market(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    calls.add({'action': action, 'payload': payload});
    if (action == 'workspace') {
      return {
        'shops': [shopRow],
        'products': [productRow],
        'staff': const [],
      };
    }
    if (action == 'shop_save') {
      return {'shop': {...shopRow, ...payload}};
    }
    if (action == 'order_action') {
      final act = '${payload['action'] ?? ''}';
      if (act == 'accept') orderState = 'accepted';
      if (act == 'ready') orderState = 'ready';
      if (act == 'cancel') orderState = 'cancelled';
      orderVersion++;
      return {'order': merchantOrderRow};
    }
    if (action == 'voucher_save') {
      voucherActive = payload['active'] == true;
      return {'ok': true};
    }
    if (action == 'return_action') {
      if (payload['action'] == 'approve') returnState = 'approved';
      if (payload['action'] == 'receive') returnState = 'received';
      return {'ok': true};
    }
    if (action == 'review_reply') {
      reviewReply = '${payload['reply'] ?? ''}';
      return {'ok': true};
    }
    return {'ok': true};
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpShort(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'Merchant workspace renders real-time KPIs, 1-tap pause/publish toggles, quick stock & stock ledger at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final api = MerchantSuiteFixture();
        final session = CloudAccountSession(service: api)..start();
        addTearDown(() async {
          session.dispose();
          await api.changes.close();
        });
        await session.refresh();

        await tester.pumpWidget(
          MaterialApp(
            theme: width == 360.0 ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: MarketplaceScreen(session: session),
          ),
        );
        await pumpShort(tester);

        expect(find.text('Bếp Cơm Nhà Sài Gòn'), findsWidgets);
        expect(find.text('Đủ điều kiện quyết toán'), findsOneWidget);
        expect(find.textContaining('1.050.000'), findsOneWidget);

        final pauseSwitch = find.byKey(
          const ValueKey('merchant-shop-pause-toggle'),
        );
        await tester.ensureVisible(pauseSwitch);
        await tester.tap(pauseSwitch);
        await pumpShort(tester);
        expect(api.shopPaused, isTrue);
        expect(
          api.calls.any(
            (c) =>
                c['path'] == 'merchant/shop_quick_pause' &&
                (c['body'] as Map?)?['paused'] == true,
          ),
          isTrue,
        );

        final publishSwitch = find.byKey(
          const ValueKey('merchant-product-publish-prod-1'),
        );
        await tester.ensureVisible(publishSwitch);
        await tester.tap(publishSwitch);
        await pumpShort(tester);
        expect(api.productPublished, isFalse);

        final quickStockChip = find.byKey(
          const ValueKey('merchant-product-stock-prod-1'),
        );
        await tester.ensureVisible(quickStockChip);
        await tester.tap(quickStockChip);
        await pumpShort(tester);
        await tester.enterText(
          find.byKey(const ValueKey('merchant-quick-stock-input')),
          '24',
        );
        await tester.tap(
          find.byKey(const ValueKey('merchant-quick-stock-save')),
        );
        await pumpShort(tester);
        expect(api.productStock, 24);

        final ledgerBtn = find.byKey(
          const ValueKey('merchant-open-stock-ledger'),
        );
        await tester.ensureVisible(ledgerBtn);
        await tester.tap(ledgerBtn);
        await pumpShort(tester);
        expect(find.textContaining('Điều chỉnh nhanh tồn kho'), findsOneWidget);
        await tester.tap(find.text('Đóng'));
        await pumpShort(tester);

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'MarketplaceEditor shop mode removes manual coordinate fields and saves interactive 3D map pin coordinates',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final api = MerchantSuiteFixture();
      final session = CloudAccountSession(service: api)..start();
      await session.refresh();
      final lease = CloudSessionLease(
        session: session,
        roles: const {'merchant'},
      );
      addTearDown(() async {
        lease.dispose();
        session.dispose();
        await api.changes.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MarketplaceEditor(
            service: api,
            lease: lease,
            shop: const {},
            editShop: true,
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.widgetWithText(TextFormField, 'Vĩ độ'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Kinh độ'), findsNothing);
      expect(
        find.byKey(const ValueKey('merchant-shop-map-picker')),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên cửa hàng'),
        'Tiệm Trà Trái Cây Quận 1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mô tả'),
        'Trà trái cây tươi mỗi ngày',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Địa chỉ lấy hàng'),
        '45 Lê Thánh Tôn, Quận 1, TP.HCM',
      );

      final saveBtn = find.widgetWithText(FilledButton, 'Lưu');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await pumpShort(tester);
      expect(
        find.textContaining('chạm lên bản đồ hoặc chọn gợi ý địa chỉ'),
        findsOneWidget,
      );

      tester
          .widget<Map3dPerspectiveWidget>(
            find.byKey(const ValueKey('merchant-shop-map-picker')),
          )
          .onTapGeoPoint!(const GeoPoint(latitude: 10.7782, longitude: 106.7019));
      await pumpShort(tester);

      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await pumpShort(tester);

      final saved =
          api.calls.lastWhere((c) => c['action'] == 'shop_save')['payload']
              as Map<String, dynamic>;
      expect(saved['name'], 'Tiệm Trà Trái Cây Quận 1');
      expect(saved['latitude'], closeTo(10.7782, 0.0001));
      expect(saved['longitude'], closeTo(106.7019, 0.0001));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Merchant orders workflow transitions pending -> accepted -> ready and opens live journey + chat for delegated shop staff without owner-only controls',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final api = MerchantSuiteFixture()
        ..id = 'delegated-staff-1'
        ..role = 'customer'
        ..staffShops = const [
          {
            'shop_id': 'shop-1',
            'shop_name': 'Bếp Cơm Nhà Sài Gòn',
            'role': 'staff',
          },
        ];
      final session = CloudAccountSession(service: api)..start();
      addTearDown(() async {
        session.dispose();
        await api.changes.close();
      });
      await session.refresh();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: CloudSessionBoundary(
            session: session,
            roles: const {'merchant'},
            builder: (_, lease) => Scaffold(
              body: MarketplaceView(
                session: session,
                lease: lease,
                view: MarketView.merchantOrders,
              ),
            ),
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.textContaining('phút xác nhận'), findsOneWidget);
      expect(find.textContaining('Lê Minh Khôi'), findsOneWidget);

      await tester.tap(find.text('Xác nhận đơn'));
      await pumpShort(tester);
      expect(api.orderState, 'accepted');

      await tester.tap(find.text('Sẵn sàng giao'));
      await pumpShort(tester);
      expect(api.orderState, 'ready');

      final trackBtn = find.byKey(
        const ValueKey('merchant-track-journey-mord-1'),
      );
      expect(trackBtn, findsOneWidget);
      await tester.ensureVisible(trackBtn);
      await tester.tap(trackBtn);
      await pumpShort(tester);

      expect(find.byType(CloudOrderDetailsScreen), findsOneWidget);
      expect(
        find.text('Tôi đang cách cửa hàng 400m để nhận kiện hàng.'),
        findsOneWidget,
      );
      expect(find.text('Mã OTP người nhận'), findsNothing);
      expect(find.text('Hủy đơn'), findsNothing);

      final chatInput = find.byKey(const ValueKey('order-live-chat-input'));
      expect(chatInput, findsOneWidget);
      await tester.ensureVisible(chatInput);
      await tester.enterText(chatInput, 'Quán đã đóng gói xong 2 phần cơm.');
      final sendBtn = find.byKey(const ValueKey('order-live-chat-send'));
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await pumpShort(tester);

      expect(
        api.calls.any(
          (c) =>
              c['path'] == 'order-live/send_chat' &&
              (c['body'] as Map?)?['text'] ==
                  'Quán đã đóng gói xong 2 phần cơm.',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'MerchantOperationsCenter enforces RBAC between owner/manager and staff while executing settlement, promotions, returns & review reply',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final ownerApi = MerchantSuiteFixture();
      final ownerSession = CloudAccountSession(service: ownerApi)..start();
      await ownerSession.refresh();
      final ownerLease = CloudSessionLease(
        session: ownerSession,
        roles: const {'merchant'},
      );
      addTearDown(() async {
        ownerLease.dispose();
        ownerSession.dispose();
        await ownerApi.changes.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: MerchantOperationsCenter(
              session: ownerSession,
              lease: ownerLease,
            ),
          ),
        ),
      );
      await pumpShort(tester);

      expect(
        find.byKey(const ValueKey('merchant-ops-tab-finance')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('merchant-ops-tab-promotions')),
        findsOneWidget,
      );

      final settleBtn = find.byKey(
        const ValueKey('merchant-propose-settlement-mord-settled-1'),
      );
      await tester.ensureVisible(settleBtn);
      await tester.tap(settleBtn);
      await pumpShort(tester);
      await tester.tap(find.text('Gửi đề nghị'));
      await pumpShort(tester);
      expect(
        ownerApi.calls.any(
          (c) =>
              c['method'] == 'command' &&
              c['path'] == 'marketplace/finance_request' &&
              (c['body'] as Map?)?['kind'] == 'settlement' &&
              (c['body'] as Map?)?['amount'] == 1050000,
        ),
        isTrue,
      );

      await tester.tap(
        find.byKey(const ValueKey('merchant-ops-tab-promotions')),
      );
      await pumpShort(tester);
      expect(find.textContaining('COMNHA15K'), findsOneWidget);
      final voucherToggle = find.byKey(
        const ValueKey('merchant-voucher-toggle-vch-1'),
      );
      await tester.ensureVisible(voucherToggle);
      await tester.tap(voucherToggle);
      await pumpShort(tester);
      expect(ownerApi.voucherActive, isFalse);

      await tester.tap(find.byKey(const ValueKey('merchant-ops-tab-returns')));
      await pumpShort(tester);
      final approveBtn = find.byKey(
        const ValueKey('merchant-return-approve-ret-open-1'),
      );
      await tester.ensureVisible(approveBtn);
      await tester.tap(approveBtn);
      await pumpShort(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phản hồi gửi khách hàng'),
        'Cửa hàng đồng ý nhận hoàn và đổi hộp mới cho bạn',
      );
      await tester.tap(find.text('Xác nhận'));
      await pumpShort(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(ownerApi.returnState, 'approved');

      await tester.tap(find.byKey(const ValueKey('merchant-ops-tab-reviews')));
      await pumpShort(tester);
      final replyBtn = find.byKey(
        const ValueKey('merchant-review-reply-rev-1'),
      );
      await tester.ensureVisible(replyBtn);
      await tester.tap(replyBtn);
      await pumpShort(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'Cảm ơn anh Khôi đã ủng hộ Bếp Cơm Nhà Sài Gòn ạ!',
      );
      await tester.tap(find.text('Gửi phản hồi'));
      await pumpShort(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(
        ownerApi.reviewReply,
        'Cảm ơn anh Khôi đã ủng hộ Bếp Cơm Nhà Sài Gòn ạ!',
      );

      final staffApi = MerchantSuiteFixture()
        ..id = 'staff-only-1'
        ..role = 'customer'
        ..staffShops = const [
          {
            'shop_id': 'shop-1',
            'shop_name': 'Bếp Cơm Nhà Sài Gòn',
            'role': 'staff',
          },
        ];
      final staffSession = CloudAccountSession(service: staffApi)..start();
      await staffSession.refresh();
      addTearDown(() async {
        staffSession.dispose();
        await staffApi.changes.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: MarketplaceScreen(session: staffSession),
        ),
      );
      await pumpShort(tester);

      expect(
        tester.widget<GhstUserShell>(find.byType(GhstUserShell)).roleMode,
        GhstRoleMode.merchant,
      );
      expect(find.text('Đủ điều kiện quyết toán'), findsNothing);

      await tester.tap(find.text('Kinh doanh & Hậu mãi').first);
      await pumpShort(tester);
      expect(find.byType(MerchantOperationsCenter), findsOneWidget);
      expect(
        find.byKey(const ValueKey('merchant-ops-tab-finance')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('merchant-ops-tab-promotions')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('merchant-ops-tab-returns')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('merchant-ops-tab-reviews')),
        findsOneWidget,
      );
      expect(find.text('Doanh thu hàng ròng'), findsNothing);

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
