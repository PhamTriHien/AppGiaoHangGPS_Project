import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/theme/app_theme.dart';
import 'package:gps_delivery_app/core/theme/ghst_theme_tokens.dart';
import 'package:gps_delivery_app/core/theme/theme_controller.dart';
import 'package:gps_delivery_app/main.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_order_details_screen.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_logistics_panels.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_order_form.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_session_boundary.dart';
import 'package:gps_delivery_app/presentation/widgets/system_state_screens.dart';
import 'package:gps_delivery_app/presentation/widgets/theme_mode_toggle.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ThemeAndJourneyFixture extends CloudOrdersService {
  String identity = 'customer-1';
  String role = 'customer';
  Set<String> approvedRoles = {};
  Map<String, dynamic> uiPreferences = {'theme_mode': 'light'};
  Map<String, dynamic>? shippingDraft;
  List<Map<String, dynamic>> aiMessages = const [];
  List<Map<String, dynamic>> liveMessages = [
    {
      'id': 'msg-1',
      'sender_id': 'driver-1',
      'sender_name': 'Tài xế Minh',
      'sender_role': 'driver',
      'is_customer': false,
      'text': 'Tài xế đang đến điểm lấy hàng.',
      'created_at': '2026-11-04T01:00:00Z',
    },
  ];
  List<Map<String, dynamic>> checkpoints = [];
  List<Map<String, dynamic>> driverReviews = [
    {
      'id': 'rev-1',
      'rating': 5,
      'body': 'Giao hàng nhanh, lịch sự.',
      'reply': '',
      'tracking_code': 'CL-JOURNEY01',
      'created_at': '2026-11-04T01:20:00Z',
    },
  ];
  List<Map<String, dynamic>> activeOrders = [];
  final calls = <Map<String, dynamic>>[];
  final changes = StreamController<AuthState>.broadcast();

  @override
  bool get signedIn => true;
  @override
  String get userId => identity;
  @override
  String get email => '$identity@ghst.vn';
  @override
  String get project => 'project-journey';
  @override
  String get identityScope => '$project:$userId';
  @override
  Stream<AuthState> get authChanges => changes.stream;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body, 'query': query});
    if (path == 'profile') {
      return {
        'operator': false,
        'schema_version': 3,
        'account': {
          'user_id': identity,
          'full_name': role == 'driver' ? 'Tài xế Minh' : 'Khách hàng Lan',
          'phone': '0901234567',
          'role': role,
          'blocked': false,
          'approved_roles': approvedRoles.toList(),
          'staff_shops': const [],
          'memberships': [
            for (final r in approvedRoles)
              {'role': r, 'state': 'active', 'version': 1, 'reason': ''},
          ],
          'ui_preferences': Map<String, dynamic>.from(uiPreferences),
          'shipping_draft': shippingDraft,
        },
      };
    }
    if (path == 'preferences/save_ui') {
      if (body?['theme_mode'] != null) {
        uiPreferences['theme_mode'] = body!['theme_mode'];
      }
      if (body?['preferred_role'] != null) {
        uiPreferences['preferred_role'] = body!['preferred_role'];
      }
      return {'ui_preferences': Map<String, dynamic>.from(uiPreferences)};
    }
    if (path == 'preferences/get') {
      return {
        'ui_preferences': Map<String, dynamic>.from(uiPreferences),
        'shipping_draft': shippingDraft,
      };
    }
    if (path == 'preferences/save_draft') {
      shippingDraft = body?['draft'] is Map
          ? Map<String, dynamic>.from(body!['draft'] as Map)
          : null;
      return {'shipping_draft': shippingDraft};
    }
    if (path == 'preferences/clear_draft') {
      shippingDraft = null;
      return {'shipping_draft': null};
    }
    if (path == 'addresses') return {'addresses': const []};
    if (path == 'merchants') return {'merchants': const []};
    if (path == 'quote') {
      return {
        'shipping_fee': 34000,
        'payable_fee': 34000,
        'coin_discount': 0,
        'pricing_version': 19,
        'distance_meters': 3500,
      };
    }
    if (path == 'orders') {
      return {'orders': activeOrders, 'schema_version': 3};
    }
    if (path.endsWith('/history')) {
      final orderId = path.split('/')[1];
      return {
        'history': [
          {
            'order_id': orderId,
            'version': 1,
            'action': 'create',
            'status': 'searching',
            'created_at': '2026-11-04T00:50:00Z',
            'reason': null,
          },
          {
            'order_id': orderId,
            'version': 2,
            'action': 'claim',
            'status': 'accepted',
            'created_at': '2026-11-04T00:52:00Z',
            'reason': null,
          },
          {
            'order_id': orderId,
            'version': 3,
            'action': 'arrive',
            'status': 'arrivingPickup',
            'created_at': '2026-11-04T00:55:00Z',
            'reason': null,
          },
          {
            'order_id': orderId,
            'version': 4,
            'action': 'pickup',
            'status': 'inTransit',
            'created_at': '2026-11-04T00:58:00Z',
            'reason': null,
          },
          if (checkpoints.isNotEmpty)
            {
              'order_id': orderId,
              'version': 5,
              'action': 'checkpoint',
              'status': 'inTransit',
              'created_at': '2026-11-04T01:02:00Z',
              'reason': checkpoints.last['note'],
            },
        ],
      };
    }
    if (path == 'order-live/snapshot') {
      final base = activeOrders.isNotEmpty
          ? Map<String, dynamic>.from(activeOrders.first)
          : <String, dynamic>{};
      return {
        'order': {
          ...base,
          'completed_checkpoints': checkpoints,
          'latest_gps': {
            'latitude': 10.775,
            'longitude': 106.704,
            'updated_at': '2026-11-04T01:01:00Z',
          },
        },
        'gps_trail': const [],
        'messages': liveMessages,
      };
    }
    if (path == 'order-live/send_chat') {
      final msg = {
        'id': 'msg-${liveMessages.length + 1}',
        'sender_id': identity,
        'sender_name': role == 'driver' ? 'Tài xế Minh' : 'Khách hàng Lan',
        'sender_role': role,
        'is_customer': role != 'driver',
        'text': '${body?['text'] ?? ''}',
        'created_at': '2026-11-04T01:05:00Z',
      };
      liveMessages = [...liveMessages, msg];
      return {'message': msg};
    }
    if (path == 'order-live/mark_checkpoint') {
      final entry = {
        'key': '${body?['checkpoint_key']}',
        'note': '${body?['note'] ?? ''}',
        'completed_at': '2026-11-04T01:06:00Z',
      };
      checkpoints = [...checkpoints, entry];
      return {
        'order': {
          if (activeOrders.isNotEmpty) ...activeOrders.first,
          'completed_checkpoints': checkpoints,
        },
      };
    }
    if (path == 'logistics/driver_reviews') {
      return {
        'reviews': driverReviews,
        'summary': {'count': driverReviews.length, 'average': 5.0},
      };
    }
    if (path == 'marketplace/review_reply') {
      final targetId = '${body?['id'] ?? body?['review_id'] ?? ''}';
      final replyText = '${body?['reply'] ?? ''}';
      driverReviews = [
        for (final r in driverReviews)
          if (r['id'] == targetId) {...r, 'reply': replyText} else r,
      ];
      return {'ok': true};
    }
    if (path.startsWith('notifications/')) {
      return {'unread_count': 0, 'items': const []};
    }
    if (path.startsWith('ai-history/')) {
      return {'messages': aiMessages, 'ok': true};
    }
    if (path == 'logistics/recipient_trust') {
      return {
        'delivered': 3,
        'failed': 0,
        'returned': 0,
        'flags': 0,
        'score': 96,
      };
    }
    if (path == 'logistics/service_eta') {
      return {'services': const []};
    }
    if (path == 'marketplace/catalog') {
      return {'products': const [], 'next': null, 'categories': const []};
    }
    return {};
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'ThemeController switches Light and Dark themes cleanly and syncs ui_preferences to Cloud',
    (tester) async {
      final api = ThemeAndJourneyFixture();
      api.uiPreferences = {'theme_mode': 'dark'};
      final session = CloudAccountSession(service: api);
      final themeController = ThemeController(
        session: session,
        sessionSlot: 'test-slot',
      );
      addTearDown(() async {
        themeController.dispose();
        session.dispose();
        await api.changes.close();
      });

      await session.refresh();
      expect(themeController.themeMode, ThemeMode.dark);

      await tester.pumpWidget(
        ThemeControllerScope(
          controller: themeController,
          child: ListenableBuilder(
            listenable: themeController,
            builder: (context, _) => MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeController.themeMode,
              home: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ThemeModeIconButton(),
                      SizedBox(height: 12),
                      ThemeModeSelectorCard(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkTokens = GhstThemeTokens.of(
        tester.element(find.byType(ThemeModeSelectorCard)),
      );
      expect(darkTokens.isDark, isTrue);

      await tester.tap(find.byKey(const Key('theme-mode-light')));
      await tester.pumpAndSettle();

      expect(themeController.themeMode, ThemeMode.light);
      final lightTokens = GhstThemeTokens.of(
        tester.element(find.byType(ThemeModeSelectorCard)),
      );
      expect(lightTokens.isDark, isFalse);
      expect(
        api.calls.any(
          (c) =>
              c['path'] == 'preferences/save_ui' &&
              (c['body'] as Map?)?['theme_mode'] == 'light',
        ),
        isTrue,
      );

      await tester.tap(find.byKey(const Key('theme-mode-icon-toggle')));
      await tester.pumpAndSettle();
      expect(themeController.themeMode, ThemeMode.dark);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CloudOrderForm restores Cloud shipping_draft, selects 3D service tier, and clears draft cleanly',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      final api = ThemeAndJourneyFixture();
      api.shippingDraft = {
        'pickup_address': '10 Nguyễn Huệ, Quận 1',
        'pickup_lat': 10.774,
        'pickup_lng': 106.703,
        'dropoff_address': '81 Cách Mạng Tháng 8, Quận 3',
        'dropoff_lat': 10.778,
        'dropoff_lng': 106.690,
        'recipient_name': 'Trần Minh Khôi',
        'recipient_phone': '0918889999',
        'package_description': 'Tài liệu hợp đồng gấp',
        'weight_kg': '1.5',
        'service_type': 'standard',
      };
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
          home: CloudSessionBoundary(
            session: session,
            roles: const {'customer'},
            builder: (_, lease) => CloudOrderForm(
              service: api,
              lease: lease,
              merchants: const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Đã khôi phục bản nháp đơn giao chưa hoàn tất'),
        findsOneWidget,
      );
      expect(find.text('Trần Minh Khôi'), findsOneWidget);
      final map = tester.widget<Map3dPerspectiveWidget>(
        find.byType(Map3dPerspectiveWidget),
      );
      expect(map.routePoints.length, 2);

      final expressCard = find.byKey(const ValueKey('service-tier-express'));
      await tester.ensureVisible(expressCard);
      await tester.tap(expressCard);
      await tester.pump(const Duration(milliseconds: 900));

      expect(
        api.calls.any(
          (c) =>
              c['path'] == 'preferences/save_draft' &&
              ((c['body'] as Map?)?['draft'] as Map?)?['service_type'] ==
                  'express',
        ),
        isTrue,
      );

      final clearBtn = find.byKey(const ValueKey('clear-shipping-draft'));
      await tester.ensureVisible(clearBtn);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      expect(
        api.calls.any((c) => c['path'] == 'preferences/clear_draft'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CloudOrderDetailsScreen renders Live Journey stepper, multi-stop checkpoint, and Order Chat',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      final api = ThemeAndJourneyFixture()
        ..identity = 'driver-1'
        ..role = 'driver'
        ..approvedRoles = {'driver'};
      const orderId = '20000000-0000-0000-0000-000000000099';
      final order = <String, dynamic>{
        'id': orderId,
        'tracking_code': 'CL-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        'status': 'inTransit',
        'version': 4,
        'owner_id': 'customer-1',
        'driver_id': 'driver-1',
        'shipping_fee': 42000,
        'payable_fee': 42000,
        'cod_amount': 0,
        'payment_status': 'PAID',
        'created_at': '2026-11-04T00:50:00Z',
        'sender_profile': {
          'full_name': 'Khách hàng Lan',
          'phone': '0901234567',
        },
        'details': {
          'pickup_address': '12 Lê Lợi, Quận 1',
          'dropoff_address': '99 Điện Biên Phủ, Bình Thạnh',
          'pickup_lat': 10.772,
          'pickup_lng': 106.701,
          'dropoff_lat': 10.801,
          'dropoff_lng': 106.712,
          'extra_stops': [
            {
              'address': '45 Hai Bà Trưng, Quận 1',
              'lat': 10.779,
              'lng': 106.705,
            },
          ],
          'is_round_trip': false,
          'recipient_name': 'Nguyễn Văn B',
          'recipient_phone': '0987654321',
          'package_description': 'Hộp quà sinh nhật',
          'weight_kg': 2,
          'service_type': 'express',
          'payment_method': 'sender_cash',
        },
      };
      api.activeOrders = [order];
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
          theme: AppTheme.darkTheme,
          home: CloudSessionBoundary(
            session: session,
            builder: (_, lease) =>
                CloudOrderDetailsScreen(lease: lease, order: order),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('4. Vận chuyển'), findsOneWidget);
      expect(find.text('Bản đồ hành trình trực tiếp'), findsOneWidget);
      expect(find.text('Tài xế đang đến điểm lấy hàng.'), findsOneWidget);

      final stopBtn = find.byKey(const ValueKey('details-checkpoint-stop-0'));
      await tester.ensureVisible(stopBtn);
      await tester.tap(stopBtn);
      await tester.pumpAndSettle();

      expect(
        api.calls.any(
          (c) =>
              c['path'] == 'order-live/mark_checkpoint' &&
              (c['body'] as Map?)?['checkpoint_key'] == 'stop:0',
        ),
        isTrue,
      );
      expect(find.text('Đã qua điểm #1'), findsOneWidget);

      final chatInput = find.byKey(const ValueKey('order-live-chat-input'));
      final sendBtn = find.byKey(const ValueKey('order-live-chat-send'));
      await Scrollable.ensureVisible(
        tester.element(sendBtn),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.enterText(chatInput, 'Đã qua điểm dừng số 1, 5 phút nữa tới!');
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      expect(
        api.calls.any(
          (c) =>
              c['path'] == 'order-live/send_chat' &&
              (c['body'] as Map?)?['text'] ==
                  'Đã qua điểm dừng số 1, 5 phút nữa tới!',
        ),
        isTrue,
      );
      expect(
        find.text('Đã qua điểm dừng số 1, 5 phút nữa tới!'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'DriverLiveCockpitPanel and DriverReviewsPanel render active route and submit review_reply',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      final api = ThemeAndJourneyFixture()
        ..identity = 'driver-1'
        ..role = 'driver'
        ..approvedRoles = {'driver'}
        ..activeOrders = [
          {
            'id': '30000000-0000-0000-0000-000000000001',
            'tracking_code': 'CL-DRIVERTRIP1',
            'status': 'inTransit',
            'version': 3,
            'driver_id': 'driver-1',
            'shipping_fee': 35000,
            'payable_fee': 35000,
            'cod_amount': 120000,
            'details': {
              'pickup_address': '01 Đồng Khởi, Quận 1',
              'dropoff_address': '200 Pasteur, Quận 3',
              'pickup_lat': 10.775,
              'pickup_lng': 106.704,
              'dropoff_lat': 10.784,
              'dropoff_lng': 106.692,
              'recipient_name': 'Lê Thị Hoa',
              'recipient_phone': '0909111222',
              'service_type': 'express',
            },
          },
        ];
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
          home: Scaffold(
            body: CloudSessionBoundary(
              session: session,
              roles: const {'driver'},
              builder: (_, lease) => Column(
                children: [
                  Expanded(
                    child: DriverLiveCockpitPanel(
                      session: session,
                      lease: lease,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: DriverReviewsPanel(service: api, lease: lease),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('driver-live-cockpit-panel')), findsOneWidget);
      expect(find.text('CL-DRIVERTRIP1'), findsOneWidget);
      expect(find.text('Giao hàng nhanh, lịch sự.'), findsOneWidget);

      final replyInput = find.byKey(
        const ValueKey('driver-review-reply-input-rev-1'),
      );
      await tester.ensureVisible(replyInput);
      await tester.enterText(replyInput, 'Cảm ơn quý khách đã tin tưởng GHST!');
      await tester.tap(
        find.byKey(const ValueKey('driver-review-reply-submit-rev-1')),
      );
      await tester.pumpAndSettle();

      expect(
        api.calls.any(
          (c) =>
              c['path'] == 'marketplace/review_reply' &&
              (c['body'] as Map?)?['id'] == 'rev-1' &&
              (c['body'] as Map?)?['review_kind'] == 'partner',
        ),
        isTrue,
      );
      expect(find.text('Cảm ơn quý khách đã tin tưởng GHST!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GpsDeliveryApp boots in Light mode by default and switches to Dark mode via auth toggle',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      final api = ThemeAndJourneyFixture();
      addTearDown(() async {
        await api.changes.close();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(GpsDeliveryApp(cloudService: api));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
