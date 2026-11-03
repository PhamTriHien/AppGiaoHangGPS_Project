import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/theme/ghst_theme_tokens.dart';
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
    GeoPoint? parse(Object? lat, Object? lng) {
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

    final pickup = parse(details['pickup_lat'], details['pickup_lng']);
    final dropoff = parse(details['dropoff_lat'], details['dropoff_lng']);
    if (pickup == null || dropoff == null) return const [];
    final points = <GeoPoint>[pickup];
    final extra = details['extra_stops'];
    if (extra is List) {
      for (final item in extra.take(5)) {
        if (item is Map) {
          final stop = parse(item['lat'], item['lng']);
          if (stop != null) points.add(stop);
        }
      }
    }
    points.add(dropoff);
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

  Widget _panel(
    Widget child, {
    bool interactive = false,
    Color? accentGlow,
  }) => GhstLuminousCard(
    accentGlow: accentGlow,
    interactive3d: interactive,
    maxTilt: 0.018,
    child: Material(type: MaterialType.transparency, child: child),
  );

  Widget _heading(
    GhstThemeTokens tokens,
    String title, {
    Widget? action,
  }) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            fontSize: 14.5,
            color: tokens.ink,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1,
          ),
        ),
      ),
      ?action,
    ],
  );

  Widget _readState(
    GhstThemeTokens tokens,
    String section,
    String empty, {
    bool onDark = false,
  }) {
    if (_loading.contains(section)) return const LinearProgressIndicator();
    if (_errors.contains(section)) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Chưa tải được dữ liệu.',
              style: TextStyle(
                color: onDark ? Colors.white : tokens.ink,
                fontSize: 12.5,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _load,
            icon: Icon(
              Icons.refresh,
              color: onDark ? Colors.white : tokens.primary,
            ),
            label: Text(
              'Thử lại',
              style: TextStyle(color: onDark ? Colors.white : tokens.primary),
            ),
          ),
        ],
      );
    }
    return Text(
      empty,
      style: TextStyle(
        fontSize: 12.5,
        color: onDark
            ? Colors.white.withValues(alpha: 0.85)
            : tokens.inkSecondary,
      ),
    );
  }

  Widget _services(GhstThemeTokens tokens) => _panel(
    accentGlow: tokens.sapphire.glow,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(tokens, 'Dịch vụ Giao nhận & Ăn uống nhanh'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 520 ? 3 : 2;
            final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
            final entries = <(String, IconData, TonePair, VoidCallback?)>[
              (
                'Giao nhanh',
                Icons.bolt_rounded,
                tokens.rose,
                widget.session.canCreateShippingOrder
                    ? () => widget.onCreateOrder({'service_type': 'express'})
                    : null,
              ),
              (
                'Ghép đơn 2H',
                Icons.hub_outlined,
                tokens.cyan,
                widget.session.canCreateShippingOrder
                    ? () => widget.onCreateOrder({
                        'service_type': 'same_day_2h',
                      })
                    : null,
              ),
              (
                'Tiêu chuẩn',
                Icons.inventory_2_outlined,
                tokens.sapphire,
                widget.session.canCreateShippingOrder
                    ? () => widget.onCreateOrder({'service_type': 'standard'})
                    : null,
              ),
              (
                'Tiết kiệm 4h',
                Icons.savings_outlined,
                tokens.emerald,
                widget.session.canCreateShippingOrder
                    ? () => widget.onCreateOrder({'service_type': 'saving'})
                    : null,
              ),
              (
                'Xe tải nhẹ',
                Icons.local_shipping_outlined,
                tokens.violet,
                widget.session.canCreateShippingOrder
                    ? () => widget.onCreateOrder({'service_type': 'truck'})
                    : null,
              ),
              (
                'Ăn uống & Mua sắm',
                Icons.restaurant_menu_rounded,
                tokens.amber,
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
                                    ? tokens.cardMuted
                                    : Color.alphaBlend(
                                        entry.$3.fill.withValues(
                                          alpha: tokens.isDark ? 0.55 : 0.42,
                                        ),
                                        tokens.cardSurface,
                                      ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: entry.$4 == null
                                      ? tokens.border
                                      : entry.$3.border,
                                  width: 1.1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: entry.$3.fill,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: entry.$3.border,
                                      ),
                                    ),
                                    child: Icon(
                                      entry.$2,
                                      color: entry.$4 == null
                                          ? tokens.inkMuted
                                          : entry.$3.icon,
                                      size: 19,
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      entry.$1,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: tokens.ink,
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

  Widget _promoHub(GhstThemeTokens tokens) => _panel(
    accentGlow: tokens.amber.glow,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Săn Voucher • Flash Sale • Vòng Xoay',
              style: TextStyle(
                fontSize: 14,
                color: tokens.ink,
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
                    color: tokens.amber.fill,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: tokens.amber.border),
                  ),
                  child: Text(
                    '${widget.session.coinBalance} Xu',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: tokens.amber.foreground,
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
            final items = <(String, String, IconData, TonePair, int)>[
              (
                'Điểm danh & Sale',
                'Nhận Xu mỗi ngày',
                Icons.flash_on_rounded,
                tokens.rose,
                0,
              ),
              (
                'Vòng Xoay May Mắn',
                'Săn Voucher 50K',
                Icons.casino_outlined,
                tokens.violet,
                1,
              ),
              (
                'Hộp Mù Bí Ẩn',
                'Khui quà R/SR/SSR',
                Icons.card_giftcard,
                tokens.amber,
                2,
              ),
              (
                'Kho Voucher',
                'Đổi Xu & Mã giảm',
                Icons.confirmation_num_outlined,
                tokens.emerald,
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
                            color: item.$4.fill,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: item.$4.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: item.$4.icon,
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
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.$2,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: tokens.inkSecondary,
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

  Widget _location(GhstThemeTokens tokens) => GhstAuroraBanner(
    gradient: tokens.heroGradient,
    accentOrbColor: const Color(0x526EE7B7),
    interactive3d: true,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Animated3dIconBadge(
              style: Icon3dStyle.gpsPinRadar,
              size: 46,
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
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_loading.contains('addresses') ||
                      _errors.contains('addresses'))
                    _readState(tokens, 'addresses', '', onDark: true)
                  else
                    Text(
                      'Vị trí hiện tại: ${_defaultAddress?['full_address'] ?? 'Chưa chọn điểm lấy hàng'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.10),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
              ),
              onPressed: widget.onAddresses,
              icon: const Icon(
                Icons.bookmarks_outlined,
                size: 15,
                color: Colors.white,
              ),
              label: const Text('Sổ địa chỉ'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.10),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
              ),
              onPressed: widget.onOrders,
              icon: const Icon(
                Icons.receipt_long_outlined,
                size: 15,
                color: Colors.white,
              ),
              label: const Text('Đơn hàng của tôi'),
            ),
            if (widget.onAiAssistant != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
                ),
                onPressed: widget.onAiAssistant,
                icon: const Icon(
                  Icons.auto_awesome_outlined,
                  size: 15,
                  color: Colors.white,
                ),
                label: const Text('Hỏi Trợ lý AI'),
              ),
            if (widget.session.canCreateShippingOrder)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6EE7B7),
                  foregroundColor: tokens.onAccentInk,
                ),
                onPressed: () => widget.onCreateOrder({}),
                icon: Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: tokens.onAccentInk,
                ),
                label: const Text('Đặt đơn'),
              ),
          ],
        ),
      ],
    ),
  );

  Widget? _activeOrderBanner(GhstThemeTokens tokens) {
    final active = (_data['orders'] ?? const []).where((row) {
      final st = '${row['status'] ?? ''}';
      return !['delivered', 'returned', 'cancelled'].contains(st);
    }).firstOrNull;
    if (active == null) return null;
    final statusLabel =
        cloudStatuses[active['status']] ?? '${active['status'] ?? ''}';
    final driverProfile = active['driver_profile'];
    final driverName = driverProfile is Map
        ? '${driverProfile['full_name'] ?? ''}'.trim()
        : '';
    return GhstLuminousCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      accentGlow: tokens.emerald.glow,
      borderColor: tokens.emerald.border,
      onTap: () => _details(active),
      child: Row(
        children: [
          GhstPulseBeacon(color: tokens.emerald.icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đơn đang thực hiện • ${active['tracking_code'] ?? active['id']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: tokens.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  driverName.isNotEmpty
                      ? '$statusLabel · Tài xế: $driverName'
                      : statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: tokens.emerald.foreground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: tokens.emerald.fill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: tokens.emerald.border),
            ),
            child: Text(
              'Hành trình',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: tokens.emerald.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _map(GhstThemeTokens tokens, double viewportHeight) {
    final mapHeight = widget.trackingOnly
        ? (viewportHeight - 220).clamp(480.0, 760.0).toDouble()
        : 440.0;
    final routePts = _route(_trackedOrder);
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            tokens,
            _trackedOrder == null
                ? 'Bản đồ định vị trực tiếp'
                : 'Hành trình • ${_trackedOrder!['tracking_code'] ?? _trackedOrder!['id']}',
          ),
          if ((_data['orders'] ?? const []).any(
            (row) => _route(row).length >= 2,
          )) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey(routePts.length >= 2 ? _trackedOrder!['id'] : ''),
              isExpanded: true,
              initialValue: routePts.length >= 2
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
                  if (_route(order).length >= 2)
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
              singlePinPoint: routePts.length >= 2 ? null : _savedPoint,
              singlePinLabel: 'Địa chỉ đã lưu',
              customFleetDrivers: const [],
              useGlobalFallbackRoute: false,
              routePoints: routePts,
              pickupLabel: 'Điểm lấy',
              dropoffLabel: 'Điểm giao',
              onTapGeoPoint:
                  !widget.session.canCreateShippingOrder || routePts.isNotEmpty
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

  Widget _recent(GhstThemeTokens tokens) {
    final orders = _data['orders'] ?? const [];
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            tokens,
            'Đơn gần đây',
            action: TextButton(
              onPressed: widget.onOrders,
              child: const Text('Xem tất cả'),
            ),
          ),
          if (_loading.contains('orders') ||
              _errors.contains('orders') ||
              orders.isEmpty)
            _readState(tokens, 'orders', 'Chưa có đơn giao hàng.')
          else
            for (final order in orders.take(widget.trackingOnly ? 10 : 3))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tokens.sapphire.fill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.sapphire.border),
                  ),
                  child: Icon(
                    Icons.local_shipping_outlined,
                    color: tokens.sapphire.icon,
                    size: 19,
                  ),
                ),
                title: Text(
                  '${order['tracking_code'] ?? order['id']}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: tokens.ink,
                  ),
                ),
                subtitle: Text(
                  '${cloudStatuses[order['status']] ?? order['status'] ?? ''}',
                  style: TextStyle(color: tokens.inkSecondary),
                ),
                trailing: Icon(Icons.chevron_right, color: tokens.inkMuted),
                onTap: () => _details(order),
              ),
        ],
      ),
    );
  }

  Widget _discovery(GhstThemeTokens tokens) {
    final products = _data['catalog'] ?? const [];
    return _panel(
      interactive: true,
      accentGlow: tokens.emerald.glow,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            tokens,
            'Khám phá cửa hàng',
            action: TextButton(
              onPressed: widget.onCatalog,
              child: const Text('Xem tất cả'),
            ),
          ),
          if (_loading.contains('catalog') ||
              _errors.contains('catalog') ||
              products.isEmpty)
            _readState(tokens, 'catalog', 'Chưa có sản phẩm đang mở bán.')
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
                        ? ColoredBox(
                            color: tokens.sapphire.fill,
                            child: Icon(
                              Icons.storefront_outlined,
                              color: tokens.sapphire.icon,
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
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: tokens.ink,
                  ),
                ),
                subtitle: Text(
                  '${product['shop_name']}',
                  style: TextStyle(color: tokens.inkSecondary),
                ),
                trailing: Text(
                  CurrencyFormatter.formatVnd(
                    (product['price'] as num? ?? 0).toDouble(),
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: tokens.sapphire.foreground,
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
    final tokens = GhstThemeTokens.of(context);
    final activeBanner = _activeOrderBanner(tokens);
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
              _location(tokens),
              const SizedBox(height: 12),
              if (activeBanner != null) ...[
                activeBanner,
                const SizedBox(height: 12),
              ],
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final viewportHeight = MediaQuery.sizeOf(context).height;
                final services = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _services(tokens),
                    const SizedBox(height: 12),
                    _promoHub(tokens),
                    const SizedBox(height: 12),
                    _discovery(tokens),
                  ],
                );
                final tracking = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _map(tokens, viewportHeight),
                    const SizedBox(height: 12),
                    _recent(tokens),
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
