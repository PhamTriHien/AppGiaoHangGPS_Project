import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../domain/entities/geo_point.dart';
import '../screens/cloud_order_details_screen.dart';
import '../screens/cloud_promo_events_screen.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/cloud_order_labels.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/motion_3d_effects.dart';
import '../widgets/system_state_screens.dart';

/// Original customer home composition, with exclusively session-scoped reads.
class GhstHomeScreen extends StatefulWidget {
  const GhstHomeScreen({
    super.key,
    required this.session,
    required this.onCreateOrder,
    required this.onCatalog,
    required this.onAddresses,
    required this.onOrders,
    required this.onAddressChanged,
    this.onAiAssistant,
    this.onOpenPromoHub,
    this.trackingOnly = false,
  });
  final CloudAccountSession session;
  final ValueChanged<Map<String, dynamic>> onCreateOrder;
  final VoidCallback onCatalog, onAddresses, onOrders;
  final VoidCallback? onAiAssistant;
  final ValueChanged<int>? onOpenPromoHub;
  final ValueChanged<String> onAddressChanged;
  final bool trackingOnly;

  @override
  State<GhstHomeScreen> createState() => _GhstHomeScreenState();
}

class _GhstHomeScreenState extends State<GhstHomeScreen> {
  late final _lease = CloudSessionLease(session: widget.session);
  final _data = <String, List<Map<String, dynamic>>>{};
  final _errors = <String>{};
  final _loading = <String>{};
  int _generation = 0;
  String? _trackedId;
  bool get _allowed => mounted && _lease.valid;

  @override
  void initState() {
    super.initState();
    _lease.addListener(_invalidated);
    unawaited(_load());
  }

  void _invalidated() {
    if (mounted && !_lease.valid) {
      _generation++;
      setState(() {
        _data.clear();
        _errors.clear();
        _loading.clear();
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _lease.removeListener(_invalidated);
    _lease.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_allowed) return;
    final generation = ++_generation;
    setState(() {
      _errors.clear();
      _data.clear();
      _loading.addAll([
        'orders',
        'addresses',
        if (!widget.trackingOnly) 'catalog',
      ]);
    });
    await Future.wait([
      _read(
        'orders',
        'orders',
        () => widget.session.service.request('orders'),
        generation,
      ),
      _read(
        'addresses',
        'addresses',
        () => widget.session.service.request('addresses'),
        generation,
      ),
      if (!widget.trackingOnly)
        _read(
          'catalog',
          'products',
          () => widget.session.service.market('catalog'),
          generation,
        ),
    ]);
  }

  Future<void> _read(
    String section,
    String key,
    Future<Map<String, dynamic>> Function() request,
    int generation,
  ) async {
    try {
      final response = await request();
      if (!_allowed || generation != _generation) return;
      final raw = response[key];
      if (raw is! List || raw.any((row) => row is! Map)) {
        throw const FormatException('Invalid home response');
      }
      final rows = raw
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      setState(() {
        _data[section] = rows;
        _loading.remove(section);
      });
      if (section == 'addresses') {
        widget.onAddressChanged('${_defaultAddress?['full_address'] ?? ''}');
      }
    } catch (error) {
      if (!_allowed ||
          generation != _generation ||
          _lease.handleAccessFailure(error)) {
        return;
      }
      setState(() {
        _data.remove(section);
        _loading.remove(section);
        _errors.add(section);
      });
    }
  }

  Map<String, dynamic>? get _defaultAddress {
    final addresses = _data['addresses'] ?? const [];
    return addresses.where((row) => row['is_default'] == true).firstOrNull ??
        addresses.firstOrNull;
  }

  GeoPoint? get _savedPoint {
    final address = _defaultAddress;
    final lat = address?['latitude'], lng = address?['longitude'];
    if (lat is! num ||
        lng is! num ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return null;
    }
    return GeoPoint(latitude: lat.toDouble(), longitude: lng.toDouble());
  }

  Map<String, dynamic>? get _trackedOrder {
    if (_trackedId == '') return null;
    final orders = _data['orders'] ?? const [];
    return orders.where((row) => row['id'] == _trackedId).firstOrNull ??
        orders
            .where(
              (row) => ![
                'delivered',
                'returned',
                'cancelled',
              ].contains(row['status']),
            )
            .firstOrNull;
  }

  List<GeoPoint> _route(Map<String, dynamic>? order) {
    final details = order?['details'];
    if (details is! Map) return const [];
    final points = <GeoPoint>[];
    for (final prefix in ['pickup', 'dropoff']) {
      final lat = details['${prefix}_lat'], lng = details['${prefix}_lng'];
      if (lat is! num ||
          lng is! num ||
          !lat.isFinite ||
          !lng.isFinite ||
          lat.abs() > 90 ||
          lng.abs() > 180) {
        return const [];
      }
      points.add(GeoPoint(latitude: lat.toDouble(), longitude: lng.toDouble()));
    }
    return points;
  }

  Future<void> _details(Map<String, dynamic> order) async {
    if (!_allowed) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudSessionBoundary(
          session: widget.session,
          builder: (_, lease) =>
              CloudOrderDetailsScreen(lease: lease, order: order),
        ),
      ),
    );
    if (_allowed) await _load();
  }

  Widget _panel(Widget child, {bool interactive = false}) {
    final box = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
    if (!interactive) return box;
    return Motion3dInteractiveSurface(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      maxTilt: 0.018,
      hoverLift: -1.4,
      enablePressScale: false,
      glintOpacity: 0.08,
      child: box,
    );
  }

  Widget _heading(String title, {Widget? action}) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14.5,
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1,
          ),
        ),
      ),
      ?action,
    ],
  );

  Widget _readState(String section, String empty) {
    if (_loading.contains(section)) return const LinearProgressIndicator();
    if (_errors.contains(section)) {
      return Row(
        children: [
          const Expanded(child: Text('Chưa tải được dữ liệu.')),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      );
    }
    return Text(
      empty,
      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
    );
  }

  Widget _services() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('Dịch vụ Giao nhận & Ăn uống nhanh'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 520 ? 3 : 2;
            final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
            final entries = <(String, IconData, Color, VoidCallback?)>[
              (
                'Giao nhanh',
                Icons.bolt_rounded,
                AppColors.pink,
                widget.session.canCreateShippingOrder
                    ? () => widget.onCreateOrder({'service_type': 'express'})
                    : null,
              ),
              (
                'Ghép đơn 2H',
                Icons.hub_outlined,
                const Color(0xFF0EA5E9),
                widget.session.canCreateShippingOrder
                    ? () => widget.onCreateOrder({
                        'service_type': 'same_day_2h',
                      })
                    : null,
              ),
              (
                'Tiêu chuẩn',
                Icons.inventory_2_outlined,
                AppColors.violet,
                widget.session.canCreateShippingOrder
                    ? () => widget.onCreateOrder({'service_type': 'standard'})
                    : null,
              ),
              (
                'Tiết kiệm 4h',
                Icons.savings_outlined,
                AppColors.success,
                widget.session.canCreateShippingOrder
                    ? () => widget.onCreateOrder({'service_type': 'saving'})
                    : null,
              ),
              (
                'Xe tải nhẹ',
                Icons.local_shipping_outlined,
                const Color(0xFF334155),
                widget.session.canCreateShippingOrder
                    ? () => widget.onCreateOrder({'service_type': 'truck'})
                    : null,
              ),
              (
                'Ăn uống & Mua sắm',
                Icons.restaurant_menu_rounded,
                const Color(0xFF059669),
                widget.onCatalog,
              ),
            ];
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final entry in entries)
                  SizedBox(
                    width: width,
                    child: Tooltip(
                      message: entry.$4 == null
                          ? 'Dịch vụ chưa được mở'
                          : entry.$1,
                      child: Semantics(
                        button: true,
                        enabled: entry.$4 != null,
                        child: Motion3dInteractiveSurface(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(12),
                          ),
                          maxTilt: 0.044,
                          pressScale: 0.976,
                          hoverLift: -1.8,
                          enabled: entry.$4 != null,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: entry.$4,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 68),
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: entry.$4 == null
                                  ? const Color(0xFFF8FAFC)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: entry.$4 == null
                                    ? const Color(0xFFE2E8F0)
                                    : entry.$3.withValues(alpha: 0.30),
                                width: 1.1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: entry.$3.withValues(alpha: .12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    entry.$2,
                                    color: entry.$4 == null
                                        ? AppColors.textSecondary
                                        : entry.$3,
                                    size: 19,
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    entry.$1,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );

  void _openPromo(int tab) {
    if (!_allowed) return;
    if (widget.onOpenPromoHub != null) {
      widget.onOpenPromoHub!(tab);
      return;
    }
    unawaited(
      openCloudPromoEvents(
        context,
        widget.session,
        initialTab: tab,
        onOpenCatalog: widget.onCatalog,
      ),
    );
  }

  Widget _promoHub() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Săn Voucher • Flash Sale • Vòng Xoay',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: Text(
                    '${widget.session.coinBalance} Xu',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  key: const ValueKey('btn-home-promo-hub'),
                  onPressed: () => _openPromo(0),
                  child: const Text('Mở trung tâm'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 520 ? 4 : 2;
            final width = (constraints.maxWidth - 10 * (cols - 1)) / cols;
            final items = <(String, String, IconData, Color, int)>[
              (
                'Điểm danh & Sale',
                'Nhận Xu mỗi ngày',
                Icons.flash_on_rounded,
                AppColors.pink,
                0,
              ),
              (
                'Vòng Xoay May Mắn',
                'Săn Voucher 50K',
                Icons.casino_outlined,
                AppColors.violet,
                1,
              ),
              (
                'Hộp Mù Bí Ẩn',
                'Khui quà R/SR/SSR',
                Icons.card_giftcard,
                const Color(0xFFD97706),
                2,
              ),
              (
                'Kho Voucher',
                'Đổi Xu & Mã giảm',
                Icons.confirmation_num_outlined,
                const Color(0xFF059669),
                3,
              ),
            ];
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final item in items)
                  SizedBox(
                    width: width,
                    child: Motion3dInteractiveSurface(
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                      maxTilt: 0.044,
                      pressScale: 0.976,
                      hoverLift: -1.8,
                      child: InkWell(
                        key: ValueKey('home-promo-tab-${item.$5}'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openPromo(item.$5),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 76),
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: item.$4.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: item.$4.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: item.$4,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                item.$3,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.$1,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.$2,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _location() => _panel(
    interactive: true,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Animated3dIconBadge(
              style: Icon3dStyle.gpsPinRadar,
              size: 44,
              showRadarPulse: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bạn muốn giao hàng hay đặt món đến đâu?',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_loading.contains('addresses') ||
                      _errors.contains('addresses'))
                    _readState('addresses', '')
                  else
                    Text(
                      'Vị trí hiện tại: ${_defaultAddress?['full_address'] ?? 'Chưa chọn điểm lấy hàng'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onAddresses,
              icon: const Icon(Icons.bookmarks_outlined, size: 15),
              label: const Text('Sổ địa chỉ'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onOrders,
              icon: const Icon(Icons.receipt_long_outlined, size: 15),
              label: const Text('Đơn hàng của tôi'),
            ),
            if (widget.onAiAssistant != null)
              OutlinedButton.icon(
                onPressed: widget.onAiAssistant,
                icon: const Icon(Icons.auto_awesome_outlined, size: 15),
                label: const Text('Hỏi Trợ lý AI'),
              ),
            if (widget.session.canCreateShippingOrder)
              FilledButton.icon(
                onPressed: () => widget.onCreateOrder({}),
                icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                label: const Text('Đặt đơn'),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _map(double viewportHeight) {
    final mapHeight = widget.trackingOnly
        ? (viewportHeight - 220).clamp(480.0, 760.0).toDouble()
        : 440.0;
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            _trackedOrder == null
                ? 'Bản đồ định vị trực tiếp'
                : 'Hành trình • ${_trackedOrder!['tracking_code'] ?? _trackedOrder!['id']}',
          ),
          if ((_data['orders'] ?? const []).any(
            (row) => _route(row).length == 2,
          )) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey(
                _route(_trackedOrder).length == 2 ? _trackedOrder!['id'] : '',
              ),
              isExpanded: true,
              initialValue: _route(_trackedOrder).length == 2
                  ? '${_trackedOrder!['id']}'
                  : '',
              decoration: const InputDecoration(
                labelText: 'Hành trình đơn hàng',
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Địa chỉ đã lưu'),
                ),
                for (final order in _data['orders'] ?? <Map<String, dynamic>>[])
                  if (_route(order).length == 2)
                    DropdownMenuItem(
                      value: '${order['id']}',
                      child: Text('${order['tracking_code'] ?? order['id']}'),
                    ),
              ],
              onChanged: (id) => setState(() => _trackedId = id),
            ),
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Map3dPerspectiveWidget(
              key: const ValueKey('ghst-home-map'),
              height: mapHeight,
              showTopBanner: false,
              mode: MapViewMode.customerPreview,
              singlePinPoint: _route(_trackedOrder).length == 2
                  ? null
                  : _savedPoint,
              singlePinLabel: 'Địa chỉ đã lưu',
              customFleetDrivers: const [],
              useGlobalFallbackRoute: false,
              routePoints: _route(_trackedOrder),
              pickupLabel: 'Điểm lấy',
              dropoffLabel: 'Điểm giao',
              onTapGeoPoint:
                  !widget.session.canCreateShippingOrder ||
                      _route(_trackedOrder).isNotEmpty
                  ? null
                  : (point) {
                      if (_allowed) {
                        widget.onCreateOrder({
                          'dropoff_lat': point.latitude,
                          'dropoff_lng': point.longitude,
                        });
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _recent() {
    final orders = _data['orders'] ?? const [];
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            'Đơn gần đây',
            action: TextButton(
              onPressed: widget.onOrders,
              child: const Text('Xem tất cả'),
            ),
          ),
          if (_loading.contains('orders') ||
              _errors.contains('orders') ||
              orders.isEmpty)
            _readState('orders', 'Chưa có đơn giao hàng.')
          else
            for (final order in orders.take(widget.trackingOnly ? 10 : 3))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.violet.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.local_shipping_outlined,
                    color: AppColors.violet,
                    size: 19,
                  ),
                ),
                title: Text(
                  '${order['tracking_code'] ?? order['id']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${cloudStatuses[order['status']] ?? order['status'] ?? ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _details(order),
              ),
        ],
      ),
    );
  }

  Widget _discovery() {
    final products = _data['catalog'] ?? const [];
    return _panel(
      interactive: true,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            'Khám phá cửa hàng',
            action: TextButton(
              onPressed: widget.onCatalog,
              child: const Text('Xem tất cả'),
            ),
          ),
          if (_loading.contains('catalog') ||
              _errors.contains('catalog') ||
              products.isEmpty)
            _readState('catalog', 'Chưa có sản phẩm đang mở bán.')
          else
            for (final product in products.take(4))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: (product['image_url'] as String? ?? '').isEmpty
                        ? const ColoredBox(
                            color: Color(0xFFEFF6FF),
                            child: Icon(
                              Icons.storefront_outlined,
                              color: AppColors.violet,
                            ),
                          )
                        : Image.network(
                            '${product['image_url']}',
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.image_not_supported_outlined),
                          ),
                  ),
                ),
                title: Text(
                  '${product['name']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('${product['shop_name']}'),
                trailing: Text(
                  CurrencyFormatter.formatVnd(
                    (product['price'] as num? ?? 0).toDouble(),
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: AppColors.violet,
                  ),
                ),
                onTap: widget.onCatalog,
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_lease.valid) return const SizedBox.shrink();
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Tải lại trang chủ',
                onPressed: _loading.isEmpty ? _load : null,
                icon: const Icon(Icons.refresh),
              ),
            ),
            if (!widget.trackingOnly) ...[
              _location(),
              const SizedBox(height: 12),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final viewportHeight = MediaQuery.sizeOf(context).height;
                final services = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _services(),
                    const SizedBox(height: 12),
                    _promoHub(),
                    const SizedBox(height: 12),
                    _discovery(),
                  ],
                );
                final tracking = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _map(viewportHeight),
                    const SizedBox(height: 12),
                    _recent(),
                  ],
                );
                if (widget.trackingOnly) return tracking;
                if (constraints.maxWidth >= 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: services),
                      const SizedBox(width: 14),
                      Expanded(flex: 5, child: tracking),
                    ],
                  );
                }
                return Column(
                  children: [services, const SizedBox(height: 12), tracking],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
