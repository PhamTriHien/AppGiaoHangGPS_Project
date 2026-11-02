import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/integrations/cloud_session_lease.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/main.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_address_book_screen.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_orders_screen.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_screen.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_commerce_dialog.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_order_form.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_profile_form.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_session_boundary.dart';
import 'package:gps_delivery_app/presentation/widgets/system_state_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PrivateViewFixture extends CloudOrdersService {
  bool authenticated = true,
      blocked = false,
      operator = false,
      hasProfile = true;
  String identity = 'alice', server = 'project-A', role = 'customer';
  String name = 'Private Alice', phone = '0901234567';
  String? requested;
  Object? saveFailure;
  bool replaySignIn = false;
  Session? currentAuthSession;
  Completer<Map<String, dynamic>>? pendingSave, pendingQuote, pendingAdmin;
  final changes = StreamController<AuthState>.broadcast();
  final calls = <Map<String, dynamic>>[];
  @override
  bool get signedIn => authenticated;
  @override
  String get userId => authenticated ? identity : '';
  @override
  String get email => '$identity@example.com';
  @override
  String get project => server;
  @override
  Session? get authSession => currentAuthSession;
  @override
  Stream<AuthState> get authChanges => replaySignIn
      ? Stream<AuthState>.multi((controller) {
          controller.add(
            AuthState(AuthChangeEvent.signedIn, currentAuthSession),
          );
          final subscription = changes.stream.listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
          controller.onCancel = subscription.cancel;
        }, isBroadcast: true)
      : changes.stream;

  Map<String, dynamic> profile() => {
    'schema_version': 2,
    'operator': operator,
    'account': hasProfile
        ? {
            'user_id': identity,
            'role': role,
            'full_name': name,
            'phone': phone,
            'requested_role': requested,
            'blocked': blocked,
          }
        : null,
  };

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body});
    if (path == 'profile') {
      if (body != null) {
        if (pendingSave != null) return pendingSave!.future;
        if (saveFailure != null) throw saveFailure!;
        hasProfile = true;
        name = body['full_name'] as String;
        phone = body['phone'] as String;
        requested = body['requested_role'] == 'customer'
            ? null
            : body['requested_role'] as String;
      }
      return profile();
    }
    if (path == 'orders') return {'orders': []};
    if (path == 'merchants') return {'merchants': []};
    if (path == 'accounts') return {'accounts': []};
    if (path == 'pricing' || path == 'audit') return pendingAdmin!.future;
    if (path == 'quote') {
      return pendingQuote?.future ??
          Future.value({
            'shipping_fee': 25000,
            'pricing_version': 1,
            'distance_meters': 1000,
          });
    }
    if (path == 'addresses') {
      return {
        'addresses': [
          {
            'id': 'private-address',
            'version': 1,
            'label': 'Private home',
            'full_address': '12 Private Street',
            'recipient_name': name,
            'recipient_phone': phone,
            'is_default': true,
            'latitude': 10.77,
            'longitude': 106.7,
          },
        ],
      };
    }
    if (path.contains('/payment')) {
      return {
        'configured': true,
        'payment': {
          'status': 'PAID',
          'amount': 25000,
          'checkout_url': 'https://example.com/private-payment',
        },
      };
    }
    return {};
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  (PrivateViewFixture, CloudAccountSession) setup() {
    final api = PrivateViewFixture();
    final session = CloudAccountSession(service: api);
    addTearDown(() async {
      session.dispose();
      await api.changes.close();
    });
    return (api, session);
  }

  Future<void> profileForm(
    WidgetTester tester,
    CloudAccountSession session,
  ) async {
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
  }

  Future<void> fillOrder(WidgetTester tester) async {
    for (final entry in <int, String>{
      0: '12 Nguyen Hue',
      1: '20 Le Loi',
      2: 'Private recipient',
      3: '0912345678',
      4: 'Private documents',
      5: '1',
      6: '100000',
    }.entries) {
      await tester.enterText(
        find.byType(TextFormField).at(entry.key),
        entry.value,
      );
    }
    tester
        .widget<Map3dPerspectiveWidget>(
          find.byKey(const ValueKey('cloud-order-google-map')),
        )
        .onTapGeoPoint!(const GeoPoint(latitude: 10.77, longitude: 106.7));
    await tester.pump();
    tester
        .widget<Map3dPerspectiveWidget>(
          find.byKey(const ValueKey('cloud-order-google-map')),
        )
        .onTapGeoPoint!(const GeoPoint(latitude: 10.78, longitude: 106.71));
    await tester.pump();
  }

  Session fixtureAuthSession() => Session(
    accessToken: 'fixture-only',
    tokenType: 'bearer',
    user: const User(
      id: 'alice',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-10-29T00:00:00Z',
    ),
  );

  for (final target in ['addresses', 'order', 'payment']) {
    testWidgets(
      '$target accepts replayed login but rejects a new same-user login',
      (tester) async {
        final (api, _) = setup();
        api.replaySignIn = true;
        api.currentAuthSession = fixtureAuthSession();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: switch (target) {
                'addresses' => CloudAddressBookScreen(service: api),
                'order' => CloudOrderForm(service: api, merchants: const []),
                _ => CloudCommerceDialog(
                  service: api,
                  order: const {
                    'id': 'order-A',
                    'owner_id': 'alice',
                    'shipping_fee': 25000,
                  },
                ),
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Tài khoản đã thay đổi'), findsNothing);
        if (target == 'addresses') {
          await tester.tap(find.byTooltip('Thêm địa chỉ'));
          await tester.pumpAndSettle();
          expect(find.byType(TextFormField), findsWidgets);
        } else if (target == 'order') {
          await tester.enterText(
            find.byType(TextFormField).first,
            'Private pickup',
          );
        } else {
          expect(find.text('Đã thanh toán'), findsOneWidget);
        }
        api.currentAuthSession = fixtureAuthSession();
        api.changes.add(
          AuthState(AuthChangeEvent.signedIn, api.currentAuthSession),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Tài khoản đã thay đổi'), findsOneWidget);
        expect(find.text('Private pickup'), findsNothing);
        expect(find.text('Đã thanh toán'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test('Business views stay revoked after a same-user revalidation', () async {
    final (_, session) = setup();
    await session.refresh();
    final lease = CloudSessionLease(session: session);
    addTearDown(lease.dispose);
    expect(lease.valid, isTrue);
    session.invalidateVerification();
    expect(lease.valid, isFalse);
    await session.refresh();
    expect(session.canUseBusiness, isTrue);
    expect(lease.valid, isFalse);
  });

  for (final status in [401, 403]) {
    test(
      'Profile save rejection $status clears verified permissions',
      () async {
        final (api, session) = setup();
        api.operator = true;
        await session.refresh();
        final lease = CloudSessionLease(session: session);
        addTearDown(lease.dispose);
        api.saveFailure = PublicApiException(
          'Access denied',
          statusCode: status,
        );
        await expectLater(
          session.saveProfile(
            fullName: 'Alice',
            phone: '0901234567',
            requestedRole: 'customer',
          ),
          throwsA(isA<PublicApiException>()),
        );
        expect(session.verified, isFalse);
        expect(session.isOperator, isFalse);
        expect(lease.valid, isFalse);
        api.saveFailure = null;
        await session.refresh();
        expect(lease.valid, isFalse);
      },
    );
  }

  for (final endpoint in ['pricing', 'audit']) {
    testWidgets('Late $endpoint cannot open a dialog for a new operator', (
      tester,
    ) async {
      final (api, session) = setup();
      api.operator = true;
      api.pendingAdmin = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(session: session, admin: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip(
          endpoint == 'pricing' ? 'Bảng giá cloud' : 'Nhật ký điều hành',
        ),
      );
      await tester.pump();
      expect(api.calls.where((call) => call['path'] == endpoint), hasLength(1));
      api.identity = 'bob';
      api.changes.add(AuthState(AuthChangeEvent.signedIn, null));
      await tester.pumpAndSettle();
      api.pendingAdmin!.complete({
        'pricing': {
          'base_fee': 12345,
          'per_km': 1000,
          'express_fee': 5000,
          'extra_kg': 2000,
          'version': 1,
        },
        'entries': [
          {
            'action': 'pricing',
            'target_id': 'private-alice-data',
            'actor_id': 'alice',
          },
        ],
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('private-alice-data'), findsNothing);
      expect(session.account!['user_id'], 'bob');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  test(
    'Role revocation invalidates a view even if the new role is active',
    () async {
      final (api, session) = setup();
      api.role = 'driver';
      await session.refresh();
      final lease = CloudSessionLease(session: session, roles: {'driver'});
      addTearDown(lease.dispose);
      api.role = 'customer';
      await session.refresh();
      expect(session.canUseBusiness, isTrue);
      expect(lease.valid, isFalse);
    },
  );

  test(
    'Profile lease permits initial profile creation but no blocked account',
    () async {
      final (api, session) = setup();
      api.hasProfile = false;
      await session.refresh();
      final lease = CloudSessionLease(session: session, profile: true);
      addTearDown(lease.dispose);
      expect(lease.valid, isTrue);
      await session.saveProfile(
        fullName: 'New User',
        phone: '0901234567',
        requestedRole: 'driver',
      );
      expect(lease.valid, isTrue);
      expect(session.account!['role'], 'customer');
      expect(session.account!['requested_role'], 'driver');
      api.blocked = true;
      await session.refresh();
      expect(lease.valid, isFalse);
    },
  );

  test(
    'Project changes hide private views before an auth event arrives',
    () async {
      final (api, session) = setup();
      await session.refresh();
      final lease = CloudSessionLease(session: session);
      addTearDown(lease.dispose);
      api.server = 'project-B';
      expect(lease.valid, isFalse);
      await session.refresh();
      expect(lease.valid, isFalse);
    },
  );

  test(
    'A token refresh with unchanged permissions keeps the view valid',
    () async {
      final (api, session) = setup();
      await session.refresh();
      final lease = CloudSessionLease(session: session);
      addTearDown(lease.dispose);
      api.changes.add(AuthState(AuthChangeEvent.tokenRefreshed, null));
      await Future<void>.delayed(Duration.zero);
      expect(lease.valid, isTrue);
    },
  );

  for (final width in [360.0, 1440.0]) {
    testWidgets('Profile validates and saves only supported fields at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (api, session) = setup();
      await session.refresh();
      await profileForm(tester, session);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Private Alice',
      );
      await tester.enterText(find.byType(TextFormField).first, '  New Alice  ');
      await tester.enterText(find.byType(TextFormField).last, '123');
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu hồ sơ'));
      await tester.pumpAndSettle();
      expect(api.calls.where((call) => call['body'] != null), isEmpty);
      await tester.enterText(find.byType(TextFormField).last, '0901234567');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tài xế').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu hồ sơ'));
      await tester.pumpAndSettle();
      expect(api.calls.last['body'], {
        'full_name': 'New Alice',
        'phone': '0901234567',
        'requested_role': 'driver',
      });
      expect(session.account!['role'], 'customer');
      expect(find.text('Chờ duyệt vai trò Tài xế'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Profile save failure keeps edits available for retry', (
    tester,
  ) async {
    final (api, session) = setup();
    await session.refresh();
    await profileForm(tester, session);
    await tester.enterText(find.byType(TextFormField).first, 'Retry Alice');
    api.saveFailure = const PublicApiException('Offline', statusCode: 502);
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu hồ sơ'));
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'Retry Alice',
    );
    api.saveFailure = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu hồ sơ'));
    await tester.pumpAndSettle();
    expect(session.account!['full_name'], 'Retry Alice');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'An in-flight profile save cannot update or close a new identity',
    (tester) async {
      final (api, session) = setup();
      await session.refresh();
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudProfileForm(
              session: session,
              onSaved: () => saved = true,
            ),
          ),
        ),
      );
      api.pendingSave = Completer<Map<String, dynamic>>();
      final old = api.profile();
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu hồ sơ'));
      await tester.pump();
      api.identity = 'bob';
      api.changes.add(AuthState(AuthChangeEvent.signedIn, null));
      await tester.pump();
      api.pendingSave!.complete(old);
      await tester.pumpAndSettle();
      expect(saved, isFalse);
      expect(find.byType(TextFormField), findsNothing);
      expect(session.account!['user_id'], 'bob');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Invalidation removes private fields and a confirmation above the page',
    (tester) async {
      final (_, session) = setup();
      await session.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: CloudSessionBoundary(
            session: session,
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      const AlertDialog(content: Text('PRIVATE CONFIRMATION')),
                ),
                child: const Text('PRIVATE PAGE'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('PRIVATE PAGE'));
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE CONFIRMATION'), findsOneWidget);
      session.invalidateVerification();
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE CONFIRMATION'), findsNothing);
      expect(find.text('PRIVATE PAGE'), findsNothing);
      await session.refresh();
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE PAGE'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Role/lock change removes an open address delete confirmation', (
    tester,
  ) async {
    final (api, session) = setup();
    await session.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: CloudSessionBoundary(
          session: session,
          builder: (_, lease) =>
              CloudAddressBookScreen(service: api, lease: lease),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Xóa địa chỉ'));
    await tester.pumpAndSettle();
    expect(find.text('Xóa địa chỉ?'), findsOneWidget);
    api.blocked = true;
    await session.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Xóa địa chỉ?'), findsNothing);
    expect(find.textContaining('Private home'), findsNothing);
    expect(find.textContaining('12 Private Street'), findsNothing);
    expect(api.calls.where((call) => call['body'] != null), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Late quote cannot restore pricing or submit from an invalidated form',
    (tester) async {
      final (api, session) = setup();
      await session.refresh();
      final lease = CloudSessionLease(session: session);
      addTearDown(lease.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: CloudOrderForm(service: api, merchants: const [], lease: lease),
        ),
      );
      await tester.pumpAndSettle();
      await fillOrder(tester);
      api.pendingQuote = Completer<Map<String, dynamic>>();
      final quote = find.widgetWithText(FilledButton, 'Lấy báo giá');
      await tester.ensureVisible(quote);
      await tester.tap(quote);
      await tester.pump();
      session.invalidateVerification();
      api.pendingQuote!.complete({
        'shipping_fee': 25000,
        'pricing_version': 1,
        'distance_meters': 1000,
      });
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận tạo đơn'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty,
      );
      expect(tester.widget<FilledButton>(quote).onPressed, isNull);
      expect(api.calls.where((call) => call['path'] == 'orders'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Same-ID project switch cannot retain a payment or its actions', (
    tester,
  ) async {
    final (api, _) = setup();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudCommerceDialog(
            service: api,
            order: {
              'id': 'order-A',
              'owner_id': 'alice',
              'shipping_fee': 25000,
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đã thanh toán'), findsOneWidget);
    api.server = 'project-B';
    api.changes.add(AuthState(AuthChangeEvent.tokenRefreshed, null));
    await tester.pumpAndSettle();
    expect(find.text('Đã thanh toán'), findsNothing);
    expect(find.text('Mở thanh toán'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Profile route edits the shared session and returns to the current orders',
    (tester) async {
      final (api, session) = setup();
      await tester.pumpWidget(
        MaterialApp(home: CloudOrdersScreen(session: session)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thông tin tài khoản'));
      await tester.pumpAndSettle();
      expect(find.text('Hồ sơ cá nhân'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Updated from profile',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu hồ sơ'));
      await tester.pumpAndSettle();
      expect(find.text('Hồ sơ cá nhân'), findsNothing);
      expect(session.account!['full_name'], 'Updated from profile');
      expect(
        api.calls.where(
          (call) => call['path'] == 'profile' && call['body'] != null,
        ),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
      await session.refresh();
      expect(session.canUseBusiness, isTrue);
    },
  );

  testWidgets(
    'App keeps the cloud session when switching consumer and operator routes',
    (tester) async {
      final (api, _) = setup();
      api.operator = true;
      await tester.pumpWidget(
        GpsDeliveryApp(initialRoute: '/cloud', cloudService: api),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Bảng giá cloud'), findsNothing);
      final shared = tester
          .widget<CloudOrdersScreen>(find.byType(CloudOrdersScreen))
          .session;
      Navigator.of(tester.element(find.byType(CloudOrdersScreen)))
          .pushReplacementNamed('/cloud-admin');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Bảng giá cloud'), findsOneWidget);
      Navigator.of(tester.element(find.byType(CloudOrdersScreen)))
          .pushReplacementNamed('/cloud');
      await tester.pumpAndSettle();
      expect(find.byType(MarketplaceScreen), findsOneWidget);
      final consumer = tester.widget<CloudOrdersScreen>(
        find.byType(CloudOrdersScreen),
      );
      expect(consumer.embedded, isTrue);
      expect(consumer.session, same(shared));
      expect(find.byTooltip('Bảng giá cloud'), findsNothing);
      api.authenticated = false;
      api.changes.add(AuthState(AuthChangeEvent.signedOut, null));
      await tester.pumpAndSettle();
      expect(find.text('Mật khẩu'), findsOneWidget);
      expect(find.byTooltip('Thông tin tài khoản'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
