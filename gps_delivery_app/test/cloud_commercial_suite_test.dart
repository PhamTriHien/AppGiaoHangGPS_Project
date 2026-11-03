import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/integrations/cloud_session_lease.dart';
import 'package:gps_delivery_app/presentation/screens/admin_portal_screen.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_order_details_screen.dart';
import 'package:gps_delivery_app/presentation/screens/market_order_services_screen.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_view.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_order_form.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_session_boundary.dart';
import 'package:gps_delivery_app/presentation/widgets/market_product_details.dart';

class CommercialCloudFixture extends CloudOrdersService {
  bool authenticated = true;
  bool operator = false;
  bool blocked = false;
  String id = 'buyer-1';
  String role = 'customer';
  int coinBalance = 15000;
  List<Map<String, dynamic>> staffShops = const [];
  final changes = StreamController<AuthState>.broadcast();
  final calls = <Map<String, dynamic>>[];
  bool shopFollowing = false;
  String lastCheckoutPaymentMethod = 'cod';

  @override
  bool get signedIn => authenticated;

  @override
  String get userId => authenticated ? id : '';

  @override
  String get email => 'operator@ghst.cloud';

  @override
  String get project => 'cloud-prod';

  @override
  String get identityScope => 'cloud-prod:$userId';

  @override
  Stream<AuthState> get authChanges => changes.stream;

  @override
  Future<String> startDraft() async => 'draft-commercial-1';

  @override
  Future<void> completeDraft(String draft) async {
    calls.add({'method': 'completeDraft', 'draft': draft});
  }

  @override
  Future<String?> authenticate(
    String email,
    String password, {
    bool register = false,
  }) async {
    calls.add({'method': 'authenticate', 'email': email, 'register': register});
    authenticated = true;
    changes.add(const AuthState(AuthChangeEvent.signedIn, null));
    return null;
  }

  @override
  Future<void> signOut() async {
    authenticated = false;
    changes.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

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
    calls.add({'path': path, 'body': body});
    if (path == 'profile') {
      return {
        'operator': operator,
        'schema_version': 3,
        'account': {
          'user_id': id,
          'full_name': 'Điều hành Cloud',
          'phone': '0901234567',
          'role': role,
          'blocked': blocked,
          'requested_role': null,
          'approved_roles': role == 'customer' ? <String>[] : <String>[role],
          'memberships': role == 'customer'
              ? <Map<String, dynamic>>[]
              : <Map<String, dynamic>>[
                  {'role': role, 'state': 'active', 'version': 1},
                ],
          'staff_shops': staffShops,
          'coin_balance': coinBalance,
        },
      };
    }
    if (path == 'quote') {
      return {
        'pricing_version': 4,
        'shipping_fee': 186000,
        'distance_meters': 8500,
        'volumetric_weight_kg': 72,
        'estimated_co2_saved_grams': 408,
        'breakdown': {
          'base_fee': 90000,
          'distance_fee': 52000,
          'weight_fee': 38000,
          'express_fee': 0,
          'stop_fee': 5000,
          'round_trip_fee': 0,
          'insurance_fee': 0,
          'green_fee': 1000,
        },
      };
    }
    if (path == 'orders') {
      return {
        'order': {
          'id': 'cloud-order-truck-1',
          'tracking_code': 'CL-0123456789ABCDEF0123456789ABCDEF',
          'status': 'searching',
        },
      };
    }
    if (path == 'orders/cloud-order-truck-1/history') {
      return {'history': <Map<String, dynamic>>[]};
    }
    if (path == 'orders/cloud-order-truck-1/otp') {
      return {'required': true, 'otp_code': '482916', 'verified_at': null};
    }
    if (path == 'addresses') {
      return {
        'addresses': [
          {
            'id': 'addr-1',
            'label': 'Văn phòng',
            'full_address': '72 Lê Thánh Tôn, Quận 1, TP. HCM',
            'is_default': true,
          },
        ],
      };
    }
    if (path == 'marketplace/checkout') {
      return {
        'purchase': {
          'id': 'purchase-prepaid-1',
          'total': 168000,
          'payment_method': lastCheckoutPaymentMethod,
          'payment_status':
              lastCheckoutPaymentMethod == 'prepaid' ? 'PENDING' : 'UNPAID',
        },
      };
    }
    if (path == 'purchases/purchase-prepaid-1/payment') {
      return {
        'configured': true,
        'payment': {
          'id': 'pay-1',
          'status': 'PENDING',
          'amount': 168000,
          'checkout_url': 'https://pay.payos.vn/web/purchase-prepaid-1',
          'qr_code': '00020101021238540010A000000727',
        },
      };
    }
    if (path.startsWith('marketplace/')) {
      return market(path.split('/').last, body ?? const {});
    }
    return {};
  }

  @override
  Future<Map<String, dynamic>> market(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    calls.add({'action': action, 'payload': payload});
    if (action == 'admin_analytics') {
      return {
        'cloud_orders': {
          'total': 42,
          'delivered': 38,
          'active': 4,
          'gmv': 8400000,
        },
        'market_orders': {
          'total': 19,
          'delivered': 16,
          'cancelled': 1,
          'gmv': 5200000,
          'promo_subsidy': 180000,
        },
        'finance_totals': {
          'collected': 4800000,
          'refunded': 120000,
          'settled': 3900000,
        },
        'shops': {'active': 12, 'paused': 1},
        'promotions': {
          'active_vouchers': 5,
          'active_flash_sales': 3,
          'open_review_reports': 0,
        },
        'ledger_balances': {
          'platform_escrow': 900000,
          'promo_expense': 180000,
        },
      };
    }
    if (action == 'product_details') {
      return {
        'product': {
          'id': 'prod-1',
          'shop_id': 'shop-1',
          'shop_name': 'Cửa hàng Đặc sản Cloud',
          'name': 'Cà phê Đặc sản Rang Mộc',
          'description': 'Rang mộc nguyên hạt từ Cầu Đất',
          'sku': 'CF-BASE',
          'price': 120000,
          'stock': 15,
          'published': true,
          'available': true,
        },
        'favorite': false,
        'shop_following': shopFollowing,
        'shop_followers': shopFollowing ? 9 : 8,
        'flash_sale': {
          'id': 'flash-1',
          'sale_price': 99000,
          'allocated_stock': 10,
          'sold_stock': 3,
        },
        'variants': [
          {
            'id': 'var-250g',
            'sku': 'CF-250G',
            'title': 'Gói 250g',
            'price': 120000,
            'stock': 10,
          },
          {
            'id': 'var-500g',
            'sku': 'CF-500G',
            'title': 'Gói 500g',
            'price': 210000,
            'stock': 5,
          },
        ],
        'vouchers': [
          {'code': 'CLOUD20K', 'title': 'Giảm 20.000 đ'},
        ],
        'reviews': const [],
      };
    }
    if (action == 'shop_follow_set') {
      shopFollowing = payload['enabled'] == true;
      return {'following': shopFollowing};
    }
    if (action == 'cart') {
      return {
        'items': [
          {
            'line_id': 'line-var-500g',
            'id': 'prod-1',
            'shop_id': 'shop-1',
            'shop_name': 'Cửa hàng Đặc sản Cloud',
            'name': 'Cà phê Đặc sản Rang Mộc',
            'sku': 'CF-500G',
            'variant_id': 'var-500g',
            'variant_title': 'Gói 500g',
            'price': 210000,
            'unit_price': 190000,
            'stock': 5,
            'quantity': 1,
            'published': true,
            'shop_status': 'active',
            'paused': false,
            'available': true,
          },
        ],
      };
    }
    if (action == 'quote') {
      lastCheckoutPaymentMethod =
          payload['payment_method'] as String? ?? 'cod';
      return {
        'quote': {
          'id': 'quote-prepaid-1',
          'snapshot': {
            'subtotal': 190000,
            'voucher_discount': 20000,
            'coin_discount': 15000,
            'payable_subtotal': 155000,
            'shipping_fee': 13000,
            'total': 168000,
            'shops': [
              {
                'shop_id': 'shop-1',
                'shop_name': 'Cửa hàng Đặc sản Cloud',
                'subtotal': 190000,
                'voucher_discount': 20000,
                'coin_discount': 15000,
                'shipping_fee': 13000,
                'items': const [],
              },
            ],
          },
        },
      };
    }
    if (action == 'order_services') {
      return {
        'order': {
          'id': 'mord-1',
          'owner_id': 'buyer-1',
          'merchant_id': 'owner-merchant-1',
          'shop_id': 'shop-1',
          'delivery_id': 'deliv-1',
          'delivered_at': '2026-10-31T06:30:00Z',
          'state': 'ready',
          'snapshot': {
            'shop_name': 'Cửa hàng Đặc sản Cloud',
            'subtotal': 190000,
            'payable_subtotal': 155000,
            'shipping_fee': 13000,
            'items': [
              {
                'line_id': 'line-var-500g',
                'product_id': 'prod-1',
                'name': 'Cà phê Đặc sản Rang Mộc (Gói 500g)',
                'quantity': 1,
                'unit_price': 190000,
              },
            ],
          },
        },
        'collected': 168000,
        'refunded': 0,
        'settled': 0,
        'shipments': [
          {
            'id': 'ship-1',
            'parcel_no': 1,
            'tracking_code': 'CL-0123456789ABCDEF0123456789ABCDEF',
            'status': 'delivered',
          },
          {
            'id': 'ship-2',
            'parcel_no': 2,
            'tracking_code': 'CL-FEDCBA9876543210FEDCBA9876543210',
            'status': 'inTransit',
          },
        ],
        'returns': [
          {
            'id': 'ret-1',
            'order_id': 'mord-1',
            'quantity': 1,
            'state': 'approved',
            'version': 2,
            'reason': 'Bao bì rách nhẹ khi vận chuyển',
            'attachments': ['return/mord-1/proof.webp'],
          },
        ],
        'reviews': const [],
        'partner_reviews': const [],
        'shares': const [],
        'finance': const [],
      };
    }
    return {};
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settleShort(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
  }

  test(
    'CloudAccountSession tracks delegated shop staff roles, coin wallet balance and lease invalidation',
    () async {
      final service = CommercialCloudFixture()
        ..id = 'staff-user-1'
        ..role = 'customer'
        ..coinBalance = 42000
        ..staffShops = [
          {
            'shop_id': 'shop-1',
            'shop_name': 'Cửa hàng Đặc sản Cloud',
            'role': 'manager',
          },
          {
            'shop_id': 'shop-2',
            'shop_name': 'Cửa hàng Phụ trợ',
            'role': 'staff',
          },
        ];
      final session = CloudAccountSession(service: service)..start();
      addTearDown(session.dispose);

      await session.refresh();
      expect(session.verified, isTrue);
      expect(session.coinBalance, equals(42000));
      expect(session.hasMerchantAccess, isTrue);
      expect(session.hasStaffShop, isTrue);
      expect(session.hasStaffManagerShop, isTrue);
      expect(session.isStaffOfShop('shop-1'), isTrue);
      expect(session.isManagerOfShop('shop-1'), isTrue);
      expect(session.isStaffOfShop('shop-2'), isTrue);
      expect(session.isManagerOfShop('shop-2'), isFalse);

      final lease = CloudSessionLease(
        session: session,
        roles: const {'merchant'},
      );
      addTearDown(lease.dispose);
      expect(lease.valid, isTrue);

      final prevRevision = session.revision;
      service.staffShops = const [];
      await session.refresh();
      expect(session.hasMerchantAccess, isFalse);
      expect(session.revision, greaterThan(prevRevision));
      expect(lease.valid, isFalse);
    },
  );

  testWidgets(
    'Unified /admin Cloud Portal blocks non-operators and renders Cloud Operator analytics after login',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = CommercialCloudFixture()
        ..authenticated = false
        ..operator = false;
      final session = CloudAccountSession(service: service)..start();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        MaterialApp(home: AdminPortalScreen(session: session)),
      );
      await settleShort(tester);

      expect(find.text('GHST ADMIN'), findsOneWidget);
      expect(find.text('Email quản trị'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email quản trị'),
        'customer@ghst.cloud',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mật khẩu'),
        'secret123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await settleShort(tester);

      expect(
        find.text('Tài khoản chưa có quyền quản trị.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Đăng xuất'));
      await settleShort(tester);
      expect(find.text('Email quản trị'), findsOneWidget);

      service.operator = true;
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email quản trị'),
        'operator@ghst.cloud',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mật khẩu'),
        'secret123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await settleShort(tester);

      expect(
        find.text('Chỉ số vận hành thời gian thực'),
        findsOneWidget,
      );
      expect(find.text('Khuyến mãi & Đối soát'), findsWidgets);
      expect(
        service.calls.any((c) => c['action'] == 'admin_analytics'),
        isTrue,
      );
    },
  );

  testWidgets(
    'CloudOrderForm quotes and submits heavy truck parcel with volumetric dimensions, EV, Green Fund & extra stop',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = CommercialCloudFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: CloudOrderForm(
            service: service,
            merchants: const [],
            embedded: true,
            initialDetails: const {
              'service_type': 'truck',
              'pickup_address': 'Kho Sóng Thần, Dĩ An',
              'pickup_lat': 10.8921,
              'pickup_lng': 106.7462,
              'dropoff_address': 'Bến Thành, Quận 1',
              'dropoff_lat': 10.7725,
              'dropoff_lng': 106.6980,
              'recipient_name': 'Trần Đại Quang',
              'recipient_phone': '0912345678',
              'package_description': 'Thiết bị sự kiện đóng kiện gỗ',
              'weight_kg': 65,
              'cod_amount': 0,
              'length_cm': 120,
              'width_cm': 60,
              'height_cm': 50,
              'prefer_ev': true,
              'green_fund': true,
              'require_pod': true,
              'require_otp': true,
              'extra_stops': [
                {
                  'address': 'Trạm trung chuyển Hàng Xanh',
                  'lat': 10.8012,
                  'lng': 106.7115,
                },
              ],
            },
          ),
        ),
      );
      await settleShort(tester);

      final quoteBtn = find.text('Lấy báo giá');
      await tester.ensureVisible(quoteBtn);
      await tester.tap(quoteBtn);
      await settleShort(tester);

      expect(find.text('Khối lượng quy đổi thể tích: 72 kg'), findsOneWidget);
      expect(
        find.text('Ước tính giảm phát thải EV: 408 g CO2'),
        findsOneWidget,
      );
      expect(find.textContaining('Phụ phí đa điểm dừng'), findsOneWidget);
      expect(find.textContaining('Đóng góp Quỹ Xanh'), findsOneWidget);

      final quoteDetails =
          service.calls.firstWhere((c) => c['path'] == 'quote')['body']
              as Map<String, dynamic>;
      expect(quoteDetails['service_type'], equals('truck'));
      expect(quoteDetails['weight_kg'], equals(65.0));
      expect(quoteDetails['length_cm'], equals(120.0));
      expect(quoteDetails['prefer_ev'], isTrue);
      expect(quoteDetails['green_fund'], isTrue);
      expect(quoteDetails['require_pod'], isTrue);
      expect(quoteDetails['require_otp'], isTrue);
      expect((quoteDetails['extra_stops'] as List), hasLength(1));

      final createBtn = find.text('Xác nhận tạo đơn');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await settleShort(tester);

      expect(
        service.calls.any(
          (c) => c['method'] == 'command' && c['path'] == 'orders',
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'MarketProductDetails selects SKU variant + Flash Sale and Cart prepaid checkout opens payOS purchase dialog',
    (tester) async {
      tester.view.physicalSize = const Size(960, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = CommercialCloudFixture();
      final session = CloudAccountSession(service: service)..start();
      addTearDown(session.dispose);
      await session.refresh();

      Map<String, dynamic>? addedSelection;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudSessionBoundary(
              session: session,
              builder: (context, lease) => Center(
                child: Builder(
                  builder: (inner) => FilledButton(
                    onPressed: () async {
                      addedSelection = await showDialog<Map<String, dynamic>>(
                        context: inner,
                        builder: (_) => MarketProductDetails(
                          session: session,
                          lease: lease,
                          productId: 'prod-1',
                        ),
                      );
                    },
                    child: const Text('Mở chi tiết'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await settleShort(tester);

      await tester.tap(find.text('Mở chi tiết'));
      await settleShort(tester);

      expect(find.textContaining('FLASH SALE:'), findsOneWidget);
      expect(find.textContaining('CLOUD20K'), findsOneWidget);

      await tester.tap(find.textContaining('Theo dõi shop'));
      await settleShort(tester);
      expect(find.textContaining('Đang theo dõi shop · 9'), findsOneWidget);

      await tester.tap(find.textContaining('Gói 500g'));
      await settleShort(tester);
      await tester.tap(find.text('Thêm vào giỏ'));
      await settleShort(tester);

      expect(addedSelection, isNotNull);
      expect(addedSelection!['variant_id'], equals('var-500g'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudSessionBoundary(
              session: session,
              builder: (_, lease) => MarketplaceView(
                session: session,
                view: MarketView.cart,
                lease: lease,
              ),
            ),
          ),
        ),
      );
      await settleShort(tester);

      expect(
        find.text('Cà phê Đặc sản Rang Mộc · CF-500G · Gói 500g'),
        findsOneWidget,
      );

      await tester.tap(find.text('Trả trước trực tuyến payOS'));
      await settleShort(tester);
      await tester.tap(find.text('Vận chuyển, Voucher & Xu thưởng'));
      await settleShort(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Mã giảm giá'),
        'CLOUD20K',
      );
      await tester.tap(find.textContaining('Đổi Xu thưởng'));
      await settleShort(tester);

      final calcBtn = find.text('Cập nhật báo giá');
      await tester.ensureVisible(calcBtn);
      await tester.tap(calcBtn);
      await settleShort(tester);

      final quoteCall = service.calls.lastWhere((c) => c['action'] == 'quote');
      final quotePayload = quoteCall['payload'] as Map<String, dynamic>;
      expect(quotePayload['payment_method'], equals('prepaid'));
      expect(quotePayload['voucher_code'], equals('CLOUD20K'));
      expect(quotePayload['use_coins'], isTrue);

      final placeBtn = find.text('Đặt mua');
      await tester.ensureVisible(placeBtn);
      await tester.tap(placeBtn);
      await settleShort(tester);

      expect(
        service.calls.any(
          (c) => c['path'] == 'purchases/purchase-prepaid-1/payment',
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'MarketOrderServicesScreen supports buyer partner review and delegated shop staff restock return disposition',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final buyerService = CommercialCloudFixture()
        ..id = 'buyer-1'
        ..role = 'customer';
      final buyerSession = CloudAccountSession(service: buyerService)..start();
      addTearDown(buyerSession.dispose);
      await buyerSession.refresh();

      await tester.pumpWidget(
        MaterialApp(
          home: CloudSessionBoundary(
            session: buyerSession,
            builder: (_, lease) => MarketOrderServicesScreen(
              session: buyerSession,
              lease: lease,
              orderId: 'mord-1',
            ),
          ),
        ),
      );
      await settleShort(tester);

      expect(find.text('Kiện vận chuyển · 2'), findsOneWidget);
      expect(find.text('Đánh giá cửa hàng'), findsOneWidget);
      expect(find.text('Đánh giá tài xế'), findsOneWidget);
      expect(find.text('Xem ảnh minh chứng'), findsOneWidget);

      await tester.tap(find.text('Đánh giá cửa hàng'));
      await settleShort(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Nhận xét chất lượng phục vụ'),
        'Đóng gói hút chân không cẩn thận, đúng phân loại 500g',
      );
      await tester.tap(find.text('Gửi đánh giá'));
      await settleShort(tester);

      final reviewCall = buyerService.calls.lastWhere(
        (c) => c['action'] == 'partner_review_save',
      );
      expect(reviewCall['payload']['target_kind'], equals('shop'));
      expect(reviewCall['payload']['order_id'], equals('mord-1'));

      final staffService = CommercialCloudFixture()
        ..id = 'delegated-staff-1'
        ..role = 'customer'
        ..staffShops = [
          {
            'shop_id': 'shop-1',
            'shop_name': 'Cửa hàng Đặc sản Cloud',
            'role': 'staff',
          },
        ];
      final staffSession = CloudAccountSession(service: staffService)..start();
      addTearDown(staffSession.dispose);
      await staffSession.refresh();

      await tester.pumpWidget(
        MaterialApp(
          home: CloudSessionBoundary(
            session: staffSession,
            builder: (_, lease) => MarketOrderServicesScreen(
              session: staffSession,
              lease: lease,
              orderId: 'mord-1',
            ),
          ),
        ),
      );
      await settleShort(tester);

      final receiveBtn = find.text('Đã nhận hàng trả');
      await tester.ensureVisible(receiveBtn);
      await tester.tap(receiveBtn);
      await settleShort(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phản hồi / lý do'),
        'Đã kiểm đếm gói hàng nguyên niêm phong và nhập lại kho',
      );
      await tester.tap(find.text('Xác nhận'));
      await settleShort(tester);
      await tester.pump(const Duration(seconds: 2));

      final returnCall = staffService.calls.lastWhere(
        (c) => c['action'] == 'return_action',
      );
      expect(returnCall['payload']['action'], equals('receive'));
      expect(returnCall['payload']['disposition'], equals('restock'));
    },
  );

  testWidgets(
    'CloudOrderDetailsScreen renders 6-digit otp_code returned by PostgreSQL delivery_cloud_order_otp',
    (tester) async {
      final service = CommercialCloudFixture();
      final session = CloudAccountSession(service: service)..start();
      addTearDown(session.dispose);
      await session.refresh();

      await tester.pumpWidget(
        MaterialApp(
          home: CloudSessionBoundary(
            session: session,
            builder: (_, lease) => CloudOrderDetailsScreen(
              lease: lease,
              order: const {
                'id': 'cloud-order-truck-1',
                'owner_id': 'buyer-1',
                'tracking_code': 'CL-0123456789ABCDEF0123456789ABCDEF',
                'status': 'searching',
                'shipping_fee': 35000,
                'cod_amount': 120000,
                'distance_meters': 3200,
                'details': {
                  'pickup_address': 'Pastel Inn Saigon, Quận 1, TP.HCM',
                  'dropoff_address': 'Chợ Bến Thành, Quận 1, TP.HCM',
                  'recipient_name': 'Trần Người Nhận',
                  'recipient_phone': '0918889900',
                  'package_description': 'Tài liệu hợp đồng',
                  'require_otp': true,
                },
              },
            ),
          ),
        ),
      );
      await settleShort(tester);

      final otpBtn = find.text('Mã OTP người nhận');
      await tester.ensureVisible(otpBtn);
      await tester.tap(otpBtn);
      await settleShort(tester);

      expect(find.text('482916'), findsOneWidget);
      expect(find.text('Sao chép'), findsOneWidget);
    },
  );
}
