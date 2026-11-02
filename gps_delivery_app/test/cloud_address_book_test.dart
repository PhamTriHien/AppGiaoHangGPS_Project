import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_address_book_screen.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_order_form.dart';
import 'package:gps_delivery_app/presentation/widgets/system_state_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddressFixture extends CloudOrdersService {
  String id = 'alice';
  final changes = StreamController<AuthState>.broadcast();
  final calls = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? pending;
  bool failSave = false;
  List<Map<String, dynamic>> addresses = [];
  @override
  bool get signedIn => true;
  @override
  String get userId => id;
  @override
  String get project => 'fixture';
  @override
  Stream<AuthState> get authChanges => changes.stream;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body});
    if (pending != null) {
      final wait = pending!;
      pending = null;
      return wait.future;
    }
    if (body != null && failSave) throw const PublicApiException('Mất kết nối');
    if (body?['delete'] == true) {
      addresses = [];
    } else if (body?['details'] is Map) {
      addresses = [
        {
          ...Map<String, dynamic>.from(body!['details'] as Map),
          'id': path.split('/').last,
          'version': 1,
        },
      ];
    }
    return {'addresses': addresses};
  }
}

Map<String, dynamic> address() => {
  'id': 'saved-address',
  'version': 1,
  'label': 'Nhà riêng',
  'recipient_name': 'Nguyen An',
  'recipient_phone': '0901234567',
  'full_address': '12 Nguyen Hue',
  'latitude': 10.77,
  'longitude': 106.7,
  'is_default': true,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> finish(WidgetTester tester, AddressFixture api) async {
    await tester.pumpWidget(const SizedBox());
    await api.changes.close();
  }

  for (final width in [360.0, 1440.0]) {
    testWidgets('Address creation, retry UUID and deletion at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = AddressFixture();
      await tester.pumpWidget(
        MaterialApp(home: CloudAddressBookScreen(service: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chưa có địa chỉ đã lưu.'), findsOneWidget);
      await tester.tap(find.byTooltip('Thêm địa chỉ'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      for (final entry in [
        'Nhà riêng',
        'Nguyen An',
        '0901234567',
        '12 Nguyen Hue',
        '10.77',
        '106.7',
      ].indexed) {
        await tester.enterText(fields.at(entry.$1), entry.$2);
      }
      api.failSave = true;
      final save = find.widgetWithText(FilledButton, 'Lưu địa chỉ');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Mất kết nối'), findsOneWidget);
      final firstPath = api.calls.last['path'];
      api.failSave = false;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(api.calls.last['path'], firstPath);
      expect(api.calls.last['body']['details']['is_default'], true);
      expect(find.text('Nhà riêng · Mặc định'), findsOneWidget);
      await tester.tap(find.byTooltip('Xóa địa chỉ'));
      await tester.pumpAndSettle();
      expect(api.calls.last['body']['delete'], isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
      await tester.pumpAndSettle();
      expect(api.calls.last['body'], {'delete': true, 'version': 1});
      expect(find.text('Chưa có địa chỉ đã lưu.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester, api);
    });
  }

  testWidgets(
    'Switching accounts clears editor and rejects in-flight address data',
    (tester) async {
      final api = AddressFixture()..addresses = [address()];
      await tester.pumpWidget(
        MaterialApp(home: CloudAddressBookScreen(service: api)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sửa địa chỉ'));
      await tester.pumpAndSettle();
      expect(find.text('12 Nguyen Hue'), findsOneWidget);
      api.id = 'bob';
      api.changes.add(AuthState(AuthChangeEvent.signedIn, null));
      await tester.pumpAndSettle();
      expect(find.text('12 Nguyen Hue'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(
        find.text('Tài khoản đã thay đổi. Mở lại sổ địa chỉ.'),
        findsOneWidget,
      );
      await finish(tester, api);

      final next = AddressFixture();
      final wait = Completer<Map<String, dynamic>>();
      next.pending = wait;
      await tester.pumpWidget(
        MaterialApp(home: CloudAddressBookScreen(service: next)),
      );
      await tester.pump();
      next.id = 'bob';
      next.changes.add(AuthState(AuthChangeEvent.signedIn, null));
      wait.complete({
        'addresses': [address()],
      });
      await tester.pumpAndSettle();
      expect(find.text('12 Nguyen Hue'), findsNothing);
      await finish(tester, next);
    },
  );

  testWidgets('Saved dropoff fills order recipient and real coordinates', (
    tester,
  ) async {
    final api = AddressFixture()..addresses = [address()];
    await tester.pumpWidget(
      MaterialApp(
        home: CloudOrderForm(service: api, merchants: const []),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Chọn địa chỉ giao đã lưu'));
    await tester.tap(find.byTooltip('Chọn địa chỉ giao đã lưu'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Chọn địa chỉ'));
    await tester.pumpAndSettle();
    final values = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .map((field) => field.controller!.text)
        .toList();
    expect(values, containsAll(['12 Nguyen Hue', 'Nguyen An', '0901234567']));
    expect(find.widgetWithText(TextFormField, 'Vĩ độ'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Kinh độ'), findsNothing);
    final map = tester.widget<Map3dPerspectiveWidget>(
      find.byKey(const ValueKey('cloud-order-google-map')),
    );
    expect(
      map.singlePinPoint,
      equals(const GeoPoint(latitude: 10.77, longitude: 106.7)),
    );
    await finish(tester, api);
  });
}
