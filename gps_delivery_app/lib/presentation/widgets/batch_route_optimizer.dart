import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/integrations/delivery_api_client.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/enums/order_status.dart';
import '../../domain/enums/service_type.dart';
import 'ghst_button_icon.dart';

class BatchRouteOptimizer extends StatefulWidget {
  const BatchRouteOptimizer({super.key, required this.store});
  final AppStateStore store;
  @override
  State<BatchRouteOptimizer> createState() => _BatchRouteOptimizerState();
}

class _BatchRouteOptimizerState extends State<BatchRouteOptimizer> {
  bool _busy = false;
  String? _error;
  String? _signature;
  Map<String, dynamic>? _result;
  List<String> _driverNames = [];
  List<String> _orderNames = [];
  String _currentSignature() => jsonEncode({
    'orders': widget.store.orders.map((o) => o.toSqlRow()).toList(),
    'drivers': widget.store.drivers
        .map(
          (d) => [
            d.id,
            d.approvalStatus,
            d.isOnline,
            d.walletBalance,
            d.vehicleType,
            widget.store.verifiedDriverLocations[d.id]?.latitude,
            widget.store.verifiedDriverLocations[d.id]?.longitude,
          ],
        )
        .toList(),
  });
  Future<void> _optimize() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final store = widget.store;
      final orders = store.orders
          .where((o) => o.status == OrderStatus.searching)
          .toList();
      final busy = store.orders
          .where(
            (o) => [
              OrderStatus.accepted,
              OrderStatus.arrivingPickup,
              OrderStatus.inTransit,
              OrderStatus.returning,
            ].contains(o.status),
          )
          .map((o) => '${o.assignedDriverName}|${o.assignedDriverPlate}')
          .toSet();
      final drivers = store.drivers
          .where(
            (d) =>
                d.isOnline &&
                d.approvalStatus == 'Đã duyệt' &&
                d.walletBalance >= 200000 &&
                store.verifiedDriverLocations.containsKey(d.id) &&
                !busy.contains('${d.fullName}|${d.licensePlate}'),
          )
          .toList();
      if (orders.isEmpty || drivers.isEmpty) {
        throw StateError(
          'Cần đơn chờ phân công và tài xế rảnh có GPS đã xác minh.',
        );
      }
      if (orders.length > 30 || drivers.length > 10) {
        throw StateError('Mỗi lượt tối đa 30 đơn và 10 tài xế.');
      }
      final signature = _currentSignature();
      final driverNames = drivers
          .map((d) => '${d.fullName} · ${d.licensePlate}')
          .toList();
      final orderNames = orders.map((o) => o.trackingCode).toList();
      final result = await DeliveryApiClient.instance.request(
        'optimize',
        body: {
          'vehicles': drivers.map((d) {
            final point = store.verifiedDriverLocations[d.id]!;
            final vehicle = d.vehicleType.toLowerCase();
            final truck =
                vehicle.contains('truck') ||
                vehicle.contains('tải') ||
                vehicle.contains('van');
            return {
              'id': d.id,
              'start': [point.longitude, point.latitude],
              'capacity': truck ? 500000 : 30000,
              'truck': truck,
            };
          }).toList(),
          'shipments': orders
              .map(
                (o) => {
                  'id': o.trackingCode,
                  'pickup': [
                    o.pickupLocation.longitude,
                    o.pickupLocation.latitude,
                  ],
                  'delivery': [
                    o.dropoffLocation.longitude,
                    o.dropoffLocation.latitude,
                  ],
                  'amount': (o.weightKg * 1000).ceil(),
                  'truck': o.serviceType == DeliveryServiceType.truck,
                },
              )
              .toList(),
        },
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _signature = signature;
        _driverNames = driverNames;
        _orderNames = orderNames;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stale = _signature != null && _signature != _currentSignature();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _optimize,
            icon: const GhstButtonIcon(Icons.route_outlined),
            label: Text(
              _busy ? 'Đang tối ưu...' : 'Tối ưu phân tuyến nhiều đơn',
            ),
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        if (stale)
          const Text(
            'Dữ liệu đã thay đổi. Cần tính lại phương án.',
            style: TextStyle(color: Colors.red, fontSize: 12),
          ),
        if (_result != null && !stale) ...[
          ...(_result!['routes'] as List).map((route) {
            final index = (route['vehicle'] as num).toInt() - 1;
            final name = index >= 0 && index < _driverNames.length
                ? _driverNames[index]
                : 'Tài xế';
            final stops = (route['steps'] as List)
                .where((s) => s['type'] == 'pickup' || s['type'] == 'delivery')
                .map((s) {
                  final i = (((s['id'] as num).toInt() - 1) / 2).floor();
                  final code = i >= 0 && i < _orderNames.length
                      ? _orderNames[i]
                      : '';
                  return '${s['type'] == 'pickup' ? 'Lấy' : 'Giao'} $code';
                })
                .join(' → ');
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const GhstButtonIcon(Icons.local_shipping_outlined),
              title: Text(name),
              subtitle: Text(stops),
            );
          }),
          if ((_result!['unassigned'] as List).isNotEmpty)
            Text(
              'Chưa xếp được ${(_result!['unassigned'] as List).length} điểm lấy/giao.',
            ),
          const Text(
            'Phương án tham khảo theo tải trọng 30/500 kg và đường ô tô; chưa gồm giao thông trực tiếp.',
            style: TextStyle(fontSize: 11),
          ),
        ],
      ],
    );
  }
}
