import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gps_delivery_app/core/gps/stop_order_optimizer.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/integrations/cloud_session_lease.dart';
import 'package:gps_delivery_app/core/integrations/photon_address_service.dart';
import 'package:gps_delivery_app/core/utils/cloud_order_csv.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_pickup_screen.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_logistics_panels.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_order_form.dart';

class LogisticsCloudFixture extends CloudOrdersService {
  LogisticsCloudFixture({this.role = 'merchant', this.operator = false});
  final String role;
  final bool operator;
  final calls = <Map<String, dynamic>>[];
  final changes = StreamController<AuthState>.broadcast();
  bool flagged = false;

  @override
  bool get signedIn => true;
  @override
  String get userId => 'user-1';
  @override
  String get project => 'cloud-test';
  @override
  String get identityScope => 'cloud-test:user-1';
  @override
  Stream<AuthState> get authChanges => changes.stream;
  @override
  Future<String> startDraft() async => 'draft-1';

  @override
  Future<Map<String, dynamic>> command(
    String path,
    Map<String, dynamic> payload,
  ) async {
    calls.add({'method': 'command', 'path': path, 'body': payload});
    return request(path, body: {...payload, 'request_key': 'key-1'});
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body});
    switch (path) {
      case 'profile':
        return {
          'operator': operator,
          'schema_version': 3,
          'account': {
            'user_id': 'user-1',
            'full_name': 'Cửa hàng kiểm thử',
            'phone': '0901234567',
            'role': role,
            'blocked': false,
            'requested_role': null,
            'approved_roles': [if (role != 'customer') role],
            'memberships': [
              if (role != 'customer')
                {'role': role, 'state': 'active', 'version': 1},
            ],
            'staff_shops': const [],
          },
        };
      case 'addresses':
        return {
          'addresses': [
            {
              'id': 'addr-wh',
              'label': 'Kho chính',
              'full_address': '12 Nguyễn Huệ, Quận 1',
              'latitude': 10.77,
              'longitude': 106.7,
              'is_default': true,
            },
          ],
        };
      case 'logistics/recipient_trust':
      case 'logistics/recipient_flag':
        if (path.endsWith('flag')) flagged = body!['flagged'] == true;
        return {
          'phone': body!['phone'],
          'delivered': 1,
          'failed_or_returned': 1,
          'flagged': flagged,
          'score': flagged ? 25 : 70,
          'tier': flagged ? 'high_risk' : 'confirm',
        };
      case 'logistics/stats':
        return {
          'scope': operator ? 'network' : 'account',
          'window_days': 30,
          'summary': {
            'total': 12,
            'delivered': 9,
            'failed_or_returned': 1,
            'cancelled': 1,
            'active': 1,
            'avg_delivery_minutes': 95,
            'avg_transit_minutes': 32,
            'by_service': [
              {
                'service_type': 'express',
                'total': 4,
                'delivered': 4,
                'avg_delivery_minutes': 40,
              },
            ],
          },
          'pickups': {'requested': 2, 'assigned': 1},
          'drivers': operator ? {'approved': 5, 'on_trip': 2} : null,
        };
      case 'logistics/pickup_list':
        return {
          'pickups': [
            {
              'id': 'pickup-1',
              'merchant_id': 'merchant-2',
              'merchant_name': 'Shop Gốm',
              'pickup_address': '215 Điện Biên Phủ',
              'contact_name': 'Thủ kho',
              'contact_phone': '0907654321',
              'vehicle_type': 'van_500kg',
              'pickup_date': '2026-11-05',
              'time_slot': 'afternoon',
              'package_count': 15,
              'total_weight_kg': 25,
              'note': '',
              'status': 'requested',
              'version': 1,
              'created_at': '2026-11-02T08:00:00Z',
            },
          ],
          'drivers': operator
              ? [
                  {'user_id': 'driver-9', 'full_name': 'Tài xế Minh'},
                ]
              : const [],
        };
    }
    return {};
  }
}

class FixedRoadDistances extends PhotonAddressService {
  FixedRoadDistances(this.matrix);
  final List<List<double>> matrix;
  List<GeoPoint>? requested;

  @override
  Future<List<List<double>>> roadDistances(List<GeoPoint> points) async {
    requested = points;
    return matrix;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  Future<CloudSessionLease> leaseFor(LogisticsCloudFixture service) async {
    final session = CloudAccountSession(service: service)..start();
    addTearDown(session.dispose);
    await session.refresh();
    final lease = CloudSessionLease(
      session: session,
      operator: service.operator,
    );
    addTearDown(lease.dispose);
    return lease;
  }

  test(
    'bestStopOrder finds the shortest asymmetric order between fixed ends',
    () {
      // 0 = pickup, 1..3 = stops, 4 = dropoff.
      final plan = bestStopOrder(const [
        [0, 9, 1, 9, 50],
        [9, 0, 9, 9, 1],
        [9, 9, 0, 1, 50],
        [9, 1, 9, 0, 50],
        [50, 50, 50, 50, 0],
      ]);
      expect(plan.order, [1, 2, 0]);
      expect(plan.optimizedMeters, 4);
      expect(plan.currentMeters, 9 + 9 + 1 + 50);
      expect(plan.improves, isTrue);
      expect(
        () => bestStopOrder(List.generate(8, (_) => List.filled(8, 1.0))),
        throwsArgumentError,
      );
    },
  );

  test('parseCloudOrderCsv validates rows without inventing defaults', () {
    final rows = parseCloudOrderCsv(
      '\uFEFFrecipient_name,recipient_phone,address,goods,weight,cod,service\n'
      'Lý Minh,0903556677,68 Nguyễn Huệ Quận 1,Đĩa gốm,3.1,"620.000",express\n'
      'Trâm,12345,215 Điện Biên Phủ,Ấm trà,2,0,\n'
      'Hưng,0917334455,86 Nguyễn Thị Minh Khai,Bình hoa,1.8,350000,bay\n'
      'Ngân,0938667788,102 CMT8 Quận 3,Đèn,1.6,,standard,10.78,106.69\n',
    );
    expect(rows, hasLength(4));
    expect(rows[0].error, isNull);
    expect(rows[0].details['cod_amount'], 620000);
    expect(rows[0].details['service_type'], 'express');
    expect(rows[1].error, 'Số điện thoại Việt Nam không hợp lệ');
    expect(rows[2].error, 'Dịch vụ không hỗ trợ');
    expect(rows[3].error, isNull);
    expect(rows[3].details['cod_amount'], 0);
    expect(rows[3].point?.latitude, 10.78);
    expect(
      () => parseCloudOrderCsv(
        List.filled(51, 'A,0903556677,68 Nguyễn Huệ,Hàng,1,0').join('\n'),
      ),
      throwsFormatException,
    );
  });

  testWidgets(
    'CloudRecipientTrust shows own history and toggles a private flag',
    (tester) async {
      final service = LogisticsCloudFixture();
      final phone = TextEditingController();
      addTearDown(phone.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudRecipientTrust(service: service, phone: phone),
          ),
        ),
      );
      phone.text = '0903556677';
      await settle(tester);
      expect(
        find.text('Tín nhiệm người nhận: 70/100 · Cần gọi xác nhận'),
        findsOneWidget,
      );
      expect(
        service.calls.where((c) => c['path'] == 'logistics/recipient_trust'),
        hasLength(1),
      );
      await tester.tap(find.text('Cảnh báo bom hàng'));
      await settle(tester);
      expect(
        find.text('Tín nhiệm người nhận: 25/100 · Rủi ro hoàn cao'),
        findsOneWidget,
      );
      expect(service.calls.last['body'], {
        'phone': '0903556677',
        'flagged': true,
      });
      phone.text = '0903';
      await settle(tester);
      expect(find.byKey(const ValueKey('cloud-recipient-trust')), findsNothing);
    },
  );

  testWidgets(
    'Delivery instruction menu sends the order version and refreshes',
    (tester) async {
      final service = LogisticsCloudFixture(role: 'customer');
      var refreshed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudDeliveryInstructionButton(
              service: service,
              order: const {
                'id': 'order-1',
                'version': 3,
                'delivery_instruction': '',
              },
              onUpdated: () => refreshed++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Chỉ dẫn giao'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi lễ tân tầng trệt'));
      await settle(tester);
      expect(service.calls.last['path'], 'logistics/instruction_set');
      expect(service.calls.last['body'], {
        'order_id': 'order-1',
        'version': 3,
        'instruction': 'Gửi lễ tân tầng trệt',
      });
      expect(refreshed, 1);
    },
  );

  testWidgets('Delivery statistics render server-derived values', (
    tester,
  ) async {
    final service = LogisticsCloudFixture(operator: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CloudDeliveryStatsCard(service: service),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Thống kê giao hàng toàn mạng (30 ngày)'), findsOneWidget);
    expect(find.text('90.0%'), findsOneWidget);
    expect(find.text('1 giờ 35 phút'), findsOneWidget);
    expect(find.text('5 / 2'), findsOneWidget);
    expect(
      find.textContaining('Giao nhanh: 4/4 đơn đã giao · TB 40 phút'),
      findsOneWidget,
    );
  });

  testWidgets('Merchant schedules a bulk pickup from the cloud address book', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = LogisticsCloudFixture();
    final lease = await leaseFor(service);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudPickupScreen(session: lease.session, lease: lease),
        ),
      ),
    );
    await settle(tester);
    expect(find.textContaining('Kho chính · 12 Nguyễn Huệ'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Số lượng kiện'),
      '20',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tổng khối lượng (kg)'),
      '600',
    );
    await tester.tap(find.text('Chọn ngày thu gom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đặt lịch xe thu gom'));
    await settle(tester);
    expect(find.text('Lớn hơn 0 và tối đa 500 kg'), findsOneWidget);
    expect(service.calls.where((c) => c['method'] == 'command'), isEmpty);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tổng khối lượng (kg)'),
      '48.5',
    );
    await tester.tap(find.text('Đặt lịch xe thu gom'));
    await settle(tester);
    final create = service.calls.firstWhere((c) => c['method'] == 'command');
    expect(create['path'], 'logistics/pickup_create');
    final body = create['body'] as Map<String, dynamic>;
    expect(body['address_id'], 'addr-wh');
    expect(body['vehicle_type'], 'van_500kg');
    expect(body['time_slot'], 'afternoon');
    expect(body['package_count'], 20);
    expect(body['total_weight_kg'], 48.5);
    expect(body['pickup_date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(find.text('Đã tạo phiếu hẹn xe thu gom.'), findsOneWidget);
  });

  testWidgets(
    'Operator dispatches an approved driver with the pickup version',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = LogisticsCloudFixture(role: 'customer', operator: true);
      final lease = await leaseFor(service);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudPickupScreen(
              session: lease.session,
              lease: lease,
              operator: true,
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Đặt lịch xe thu gom số lượng lớn'), findsNothing);
      expect(find.text('Cửa hàng: Shop Gốm'), findsOneWidget);
      await tester.tap(find.text('Tài xế đã duyệt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tài xế Minh').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Điều xe thu gom'));
      await settle(tester);
      final assign = service.calls.firstWhere(
        (c) => c['path'] == 'logistics/pickup_assign',
      );
      expect(assign['body'], {
        'id': 'pickup-1',
        'version': 1,
        'driver_id': 'driver-9',
      });
    },
  );

  testWidgets('CloudOrderForm reorders stops by real road distances', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final roads = FixedRoadDistances(const [
      [0, 9000, 1000, 50000],
      [9000, 0, 9000, 1000],
      [1000, 9000, 0, 50000],
      [50000, 50000, 50000, 0],
    ]);
    final service = LogisticsCloudFixture(role: 'customer');
    await tester.pumpWidget(
      MaterialApp(
        home: CloudOrderForm(
          service: service,
          merchants: const [],
          embedded: true,
          addressService: roads,
          initialDetails: const {
            'pickup_address': 'Kho A Quận 1',
            'pickup_lat': 10.77,
            'pickup_lng': 106.70,
            'dropoff_address': 'Điểm B Thủ Đức',
            'dropoff_lat': 10.85,
            'dropoff_lng': 106.77,
            'recipient_name': 'Người nhận',
            'recipient_phone': '0912345678',
            'package_description': 'Hàng',
            'weight_kg': 2,
            'extra_stops': [
              {'address': 'Điểm dừng xa', 'lat': 10.82, 'lng': 106.75},
              {'address': 'Điểm dừng gần', 'lat': 10.775, 'lng': 106.705},
            ],
          },
        ),
      ),
    );
    await settle(tester);
    final optimize = find.text('Tối ưu thứ tự điểm dừng theo đường bộ');
    await tester.ensureVisible(
      find.text(
        'Tùy chọn nâng cao (Kích thước, Bảo hiểm, Đa điểm dừng, POD/OTP)',
      ),
    );
    await tester.tap(
      find.text(
        'Tùy chọn nâng cao (Kích thước, Bảo hiểm, Đa điểm dừng, POD/OTP)',
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(optimize);
    await tester.tap(optimize);
    await settle(tester);
    expect(roads.requested, hasLength(4));
    expect(
      find.text('Đã sắp xếp lại điểm dừng: 68.0 km → 11.0 km đường bộ.'),
      findsOneWidget,
    );
    final first = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Địa chỉ điểm dừng #1'),
    );
    expect(first.controller!.text, 'Điểm dừng gần');
  });
}
