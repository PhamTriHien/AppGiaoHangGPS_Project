import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/market_options.dart';
import '../screens/cloud_order_import_screen.dart';
import '../screens/cloud_pickup_screen.dart';
import '../screens/market_order_services_screen.dart';
import 'cloud_logistics_panels.dart';
import 'cloud_order_labels.dart';
import 'cloud_session_boundary.dart';
import 'market_commercial_sheets.dart';

String _vnd(dynamic value) =>
    CurrencyFormatter.formatVnd((value as num? ?? 0).toDouble());

List<Map<String, dynamic>> _rows(dynamic raw) => (raw as List? ?? const [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();

String _errText(Object error) =>
    error is PublicApiException && error.statusCode != 503
    ? error.message
    : 'Dịch vụ tạm thời chưa khả dụng. Vui lòng thử lại sau.';

String _roleLabel(String? role) => switch (role) {
  'owner' => 'Chủ cửa hàng',
  'manager' => 'Quản lý',
  'operator' => 'Điều hành viên',
  _ => 'Nhân viên',
};

(String label, TonePair tone, bool active) _shopStatus(
  Map<String, dynamic> shop,
  GhstThemeTokens tokens,
) {
  final status = '${shop['status'] ?? 'active'}';
  if (status == 'pending') return ('Chờ duyệt', tokens.amber, false);
  if (status == 'suspended') return ('Tạm khóa', tokens.rose, false);
  if (shop['paused'] == true) return ('Tạm nghỉ', tokens.amber, false);
  if (shop['open_now'] == false) return ('Ngoài giờ mở cửa', tokens.cyan, false);
  return ('Đang hoạt động', tokens.emerald, true);
}

Widget _toneBadge(
  String text,
  TonePair tone, {
  IconData? icon,
  bool pulse = false,
}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  decoration: BoxDecoration(
    color: tone.fill,
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: tone.border),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (pulse) ...[
        GhstPulseBeacon(color: tone.icon, size: 7, active: true),
        const SizedBox(width: 6),
      ] else if (icon != null) ...[
        Icon(icon, size: 14, color: tone.icon),
        const SizedBox(width: 5),
      ],
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tone.foreground,
          ),
        ),
      ),
    ],
  ),
);

Future<void> showMerchantStockLedgerDialog(
  BuildContext context, {
  required CloudAccountSession session,
  required Map<String, dynamic> shop,
  String? productId,
  String? productName,
}) => showDialog<void>(
  context: context,
  builder: (_) => CloudSessionBoundary(
    session: session,
    roles: const {'merchant'},
    dialog: true,
    builder: (_, lease) => _StockLedgerDialog(
      session: session,
      lease: lease,
      shop: shop,
      productId: productId,
      productName: productName,
    ),
  ),
);

class _StockLedgerDialog extends StatefulWidget {
  const _StockLedgerDialog({
    required this.session,
    required this.lease,
    required this.shop,
    this.productId,
    this.productName,
  });

  final CloudAccountSession session;
  final CloudSessionLease lease;
  final Map<String, dynamic> shop;
  final String? productId;
  final String? productName;

  @override
  State<_StockLedgerDialog> createState() => _StockLedgerDialogState();
}

class _StockLedgerDialogState extends State<_StockLedgerDialog> {
  List<Map<String, dynamic>> _entries = const [];
  Map<String, dynamic>? _next;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!widget.lease.valid) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.session.service.merchant('stock_ledger', {
        'shop_id': widget.shop['id'],
        if (widget.productId != null) 'product_id': widget.productId,
        if (more && _next != null) ..._next!,
      });
      if (!mounted || !widget.lease.valid) return;
      final incoming = _rows(res['entries']);
      setState(() {
        _entries = more ? [..._entries, ...incoming] : incoming;
        _next = res['next'] is Map
            ? Map<String, dynamic>.from(res['next'] as Map)
            : null;
        _loading = false;
      });
    } catch (e) {
      if (mounted && !widget.lease.handleAccessFailure(e)) {
        setState(() {
          _error = _errText(e);
          _loading = false;
        });
      }
    }
  }

  String _reasonLabel(String raw) => switch (raw) {
    'merchant_quick_adjust' => 'Điều chỉnh nhanh tồn kho',
    'merchant_variant_quick_adjust' => 'Điều chỉnh nhanh tồn kho SKU',
    'merchant_edit' || 'product_save' => 'Cập nhật sản phẩm',
    'variant_save' => 'Cập nhật biến thể SKU',
    'checkout' => 'Khách đặt mua hàng',
    'cancel' || 'order_cancel' || 'shipping_cancel' => 'Hoàn tồn do hủy đơn',
    'return_restock' => 'Nhập lại kho từ hàng hoàn',
    'return_writeoff' => 'Hàng hoàn hỏng (không nhập kho)',
    _ => raw.isEmpty ? 'Biến động tồn kho' : raw,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final title = widget.productName != null
        ? 'Sổ tồn kho · ${widget.productName}'
        : 'Sổ biến động tồn kho · ${widget.shop['name']}';
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              if (!_loading && _entries.isEmpty && _error == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Chưa ghi nhận biến động tồn kho nào.'),
                ),
              for (final row in _entries)
                Builder(
                  builder: (context) {
                    final delta = (row['delta'] as num? ?? 0).toInt();
                    final tone = delta >= 0 ? tokens.emerald : tokens.rose;
                    final variantTitle = '${row['variant_title'] ?? ''}'.trim();
                    final sku = '${row['variant_sku'] ?? row['product_sku'] ?? ''}'
                        .trim();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: tokens.cardSubtle,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${row['product_name'] ?? 'Sản phẩm'}'
                                    '${variantTitle.isEmpty ? '' : ' · $variantTitle'}'
                                    '${sku.isEmpty ? '' : ' ($sku)'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_reasonLabel('${row['reason'] ?? ''}')} · '
                                    '${row['actor_name'] ?? 'Hệ thống'} · '
                                    '${cloudDate(row['created_at'])}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: tokens.inkSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _toneBadge(
                              '${delta >= 0 ? '+' : ''}$delta',
                              tone,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              if (_next != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _loading ? null : () => _load(more: true),
                    child: const Text('Tải thêm'),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

Future<bool?> showMerchantQuickStockDialog(
  BuildContext context, {
  required CloudAccountSession session,
  required Map<String, dynamic> product,
  Map<String, dynamic>? variant,
}) => showDialog<bool>(
  context: context,
  builder: (_) => CloudSessionBoundary(
    session: session,
    roles: const {'merchant'},
    dialog: true,
    builder: (_, lease) => _QuickStockDialog(
      session: session,
      lease: lease,
      product: product,
      variant: variant,
    ),
  ),
);

class _QuickStockDialog extends StatefulWidget {
  const _QuickStockDialog({
    required this.session,
    required this.lease,
    required this.product,
    this.variant,
  });

  final CloudAccountSession session;
  final CloudSessionLease lease;
  final Map<String, dynamic> product;
  final Map<String, dynamic>? variant;

  @override
  State<_QuickStockDialog> createState() => _QuickStockDialogState();
}

class _QuickStockDialogState extends State<_QuickStockDialog> {
  late final TextEditingController _stock = TextEditingController(
    text: '${(widget.variant ?? widget.product)['stock'] ?? 0}',
  );
  late bool _published = (widget.variant ?? widget.product)['published'] == true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _stock.dispose();
    super.dispose();
  }

  void _adjust(int delta, {int? exact}) {
    final current = int.tryParse(_stock.text.trim()) ?? 0;
    final next = exact ?? (current + delta).clamp(0, 1000000);
    setState(() {
      _stock.text = '$next';
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_busy || !widget.lease.valid) return;
    final parsed = int.tryParse(_stock.text.trim());
    if (parsed == null || parsed < 0 || parsed > 1000000) {
      setState(() => _error = 'Tồn kho cần là số nguyên từ 0 đến 1.000.000.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final target = widget.variant ?? widget.product;
      await widget.session.service.merchant('product_quick_update', {
        'product_id': widget.product['id'],
        if (widget.variant != null) 'variant_id': widget.variant!['id'],
        'version': target['version'] ?? 1,
        'stock': parsed,
        'published': _published,
      });
      if (mounted && widget.lease.valid) Navigator.pop(context, true);
    } catch (e) {
      if (mounted && !widget.lease.handleAccessFailure(e)) {
        setState(() => _error = _errText(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.variant == null
        ? '${widget.product['name']}'
        : '${widget.product['name']} · ${widget.variant!['title']}';
    return AlertDialog(
      title: Text('Cập nhật nhanh tồn kho · $label'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              TextField(
                key: const ValueKey('merchant-quick-stock-input'),
                controller: _stock,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số lượng tồn kho thực tế',
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final step in [-5, -1, 1, 5, 10])
                    ActionChip(
                      label: Text('${step > 0 ? '+' : ''}$step'),
                      onPressed: _busy ? null : () => _adjust(step),
                    ),
                  ActionChip(
                    label: const Text('Hết hàng (0)'),
                    onPressed: _busy ? null : () => _adjust(0, exact: 0),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Đang mở bán cho khách'),
                value: _published,
                onChanged: _busy ? null : (v) => setState(() => _published = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const ValueKey('merchant-quick-stock-save'),
          onPressed: _busy ? null : _save,
          child: const Text('Lưu tồn kho'),
        ),
      ],
    );
  }
}

class MerchantWorkspacePanel extends StatefulWidget {
  const MerchantWorkspacePanel({
    super.key,
    required this.session,
    required this.lease,
    required this.shops,
    required this.products,
    required this.staff,
    this.dashboard,
    this.selectedShopId,
    required this.onSelectShop,
    required this.onEdit,
    required this.onReload,
    this.onOpenMerchantOrders,
    this.onOpenOperations,
  });

  final CloudAccountSession session;
  final CloudSessionLease lease;
  final List<Map<String, dynamic>> shops;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> staff;
  final Map<String, dynamic>? dashboard;
  final String? selectedShopId;
  final ValueChanged<String> onSelectShop;
  final Future<void> Function({
    Map<String, dynamic>? shop,
    Map<String, dynamic>? product,
    bool editShop,
  }) onEdit;
  final Future<void> Function() onReload;
  final VoidCallback? onOpenMerchantOrders;
  final VoidCallback? onOpenOperations;

  @override
  State<MerchantWorkspacePanel> createState() => _MerchantWorkspacePanelState();
}

class _MerchantWorkspacePanelState extends State<MerchantWorkspacePanel> {
  final TextEditingController _catalogSearch = TextEditingController();
  String _catalogFilter = 'all';
  bool _actionBusy = false;
  String? _actionError;

  @override
  void dispose() {
    _catalogSearch.dispose();
    super.dispose();
  }

  Map<String, dynamic> _mergedShop(Map<String, dynamic> base) {
    final dashShops = _rows(widget.dashboard?['shops']);
    final extra = dashShops.where((s) => s['id'] == base['id']).firstOrNull;
    if (extra == null) return base;
    return {...base, ...extra};
  }

  Future<void> _runQuick(Future<void> Function() fn) async {
    if (_actionBusy || !widget.lease.valid) return;
    setState(() {
      _actionBusy = true;
      _actionError = null;
    });
    try {
      await fn();
      if (mounted && widget.lease.valid) await widget.onReload();
    } catch (e) {
      if (mounted && !widget.lease.handleAccessFailure(e)) {
        setState(() => _actionError = _errText(e));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  List<Map<String, dynamic>> _filteredProducts(
    List<Map<String, dynamic>> allShopProducts,
  ) {
    final q = _catalogSearch.text.trim().toLowerCase();
    return allShopProducts.where((p) {
      final stock = (p['stock'] as num? ?? 0).toInt();
      final pub = p['published'] == true;
      final matchFilter = switch (_catalogFilter) {
        'published' => pub,
        'low_stock' => pub && stock > 0 && stock <= 5,
        'out_of_stock' => stock <= 0,
        'hidden' => !pub,
        _ => true,
      };
      if (!matchFilter) return false;
      if (q.isEmpty) return true;
      final text =
          '${p['name'] ?? ''} ${p['sku'] ?? ''} ${p['category'] ?? ''}'
              .toLowerCase();
      return text.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final mergedShops = widget.shops.map(_mergedShop).toList();
    final targetId =
        widget.selectedShopId ??
        '${widget.dashboard?['selected_shop_id'] ?? ''}'.trim();
    final activeShop =
        mergedShops.where((s) => '${s['id']}' == targetId).firstOrNull ??
        mergedShops.first;
    final shopId = '${activeShop['id']}';
    final canManage = widget.session.canManageShop(shopId);
    final isDirectOwner =
        widget.session.isOperator ||
        (widget.session.hasRole('merchant') &&
            (activeShop['owner_id'] == null ||
                activeShop['owner_id'] == widget.session.service.userId));
    final myRole =
        '${activeShop['my_role'] ?? widget.dashboard?['my_role'] ?? (isDirectOwner ? 'owner' : (canManage ? 'manager' : 'staff'))}';
    final statusInfo = _shopStatus(activeShop, tokens);
    final shopProducts = widget.products
        .where((p) => '${p['shop_id']}' == shopId)
        .toList();
    final visibleProducts = _filteredProducts(shopProducts);
    final kpis = widget.dashboard != null &&
            ('${widget.dashboard!['selected_shop_id'] ?? shopId}' == shopId) &&
            widget.dashboard!['kpis'] is Map
        ? Map<String, dynamic>.from(widget.dashboard!['kpis'] as Map)
        : null;
    final ordersKpi = kpis?['orders'] is Map
        ? Map<String, dynamic>.from(kpis!['orders'] as Map)
        : null;
    final catalogKpi = kpis?['catalog'] is Map
        ? Map<String, dynamic>.from(kpis!['catalog'] as Map)
        : null;
    final aftersalesKpi = kpis?['aftersales'] is Map
        ? Map<String, dynamic>.from(kpis!['aftersales'] as Map)
        : null;
    final financeKpi = canManage && kpis?['finance'] is Map
        ? Map<String, dynamic>.from(kpis!['finance'] as Map)
        : null;
    final bannerUrl = '${activeShop['banner_url'] ?? ''}'.trim();
    final radiusKm = (activeShop['service_radius_km'] as num? ?? 0).toDouble();
    final ratingAvg = (activeShop['rating_avg'] as num? ?? 0).toDouble();
    final ratingCount = (activeShop['rating_count'] as num? ?? 0).toInt();
    final followers = (activeShop['followers'] as num? ?? 0).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_actionBusy)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(),
          ),
        if (_actionError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _actionError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (mergedShops.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sh in mergedShops)
                ChoiceChip(
                  key: ValueKey('merchant-shop-chip-${sh['id']}'),
                  label: Text(
                    '${sh['name']} · ${_roleLabel('${sh['my_role'] ?? ''}')}',
                  ),
                  selected: '${sh['id']}' == shopId,
                  onSelected: _actionBusy
                      ? null
                      : (sel) {
                          if (sel) widget.onSelectShop('${sh['id']}');
                        },
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        GhstAuroraBanner(
          gradient: tokens.merchantGradient,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bannerUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 112,
                    width: double.infinity,
                    child: Image.network(
                      bannerUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Text(
                      _roleLabel(myRole),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.26),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GhstPulseBeacon(
                          color: statusInfo.$3
                              ? const Color(0xFF34D399)
                              : const Color(0xFFFBBF24),
                          size: 7,
                          active: statusInfo.$3,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusInfo.$1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (ratingCount > 0)
                    Text(
                      '★ ${ratingAvg.toStringAsFixed(1)} ($ratingCount)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (followers > 0)
                    Text(
                      '$followers người theo dõi',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: 12.5,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${activeShop['name']}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${activeShop['address']}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13.5,
                ),
              ),
              if (radiusKm > 0) ...[
                const SizedBox(height: 3),
                Text(
                  'Phạm vi phục vụ: ${radiusKm.toStringAsFixed(radiusKm.truncateToDouble() == radiusKm ? 0 : 1)} km',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12.5,
                  ),
                ),
              ],
              if (canManage && activeShop['status'] != 'suspended') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.storefront_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          activeShop['paused'] == true
                              ? 'Gian hàng đang tạm nghỉ nhận đơn mới'
                              : 'Gian hàng đang mở nhận đơn trực tuyến',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        key: const ValueKey('merchant-shop-pause-toggle'),
                        value: activeShop['paused'] != true,
                        onChanged: _actionBusy
                            ? null
                            : (openSelected) => _runQuick(
                                () => widget.session.service.merchant(
                                  'shop_quick_pause',
                                  {
                                    'shop_id': shopId,
                                    'paused': !openSelected,
                                    'version': activeShop['version'] ?? 1,
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (kpis != null) ...[
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 720 ? 3 : 2;
              final spacing = 10.0;
              final tileWidth =
                  (constraints.maxWidth - spacing * (cols - 1)) / cols;
              final overdue =
                  (ordersKpi?['overdue_pending'] as num? ?? 0).toInt();
              final tiles = <Widget>[
                _buildKpiTile(
                  width: tileWidth,
                  title: 'Chờ xác nhận',
                  value: '${ordersKpi?['pending'] ?? 0}',
                  subtitle: overdue > 0
                      ? '$overdue đơn quá hạn 15 phút'
                      : 'SLA xác nhận 15 phút',
                  icon: Icons.pending_actions_outlined,
                  tone: overdue > 0 ? tokens.rose : tokens.amber,
                  onTap: widget.onOpenMerchantOrders,
                ),
                _buildKpiTile(
                  width: tileWidth,
                  title: 'Đang chuẩn bị',
                  value: '${ordersKpi?['accepted'] ?? 0}',
                  subtitle: 'Chờ lấy: ${ordersKpi?['ready'] ?? 0}',
                  icon: Icons.inventory_2_outlined,
                  tone: tokens.sapphire,
                  onTap: widget.onOpenMerchantOrders,
                ),
                _buildKpiTile(
                  width: tileWidth,
                  title: 'Đang giao hàng',
                  value: '${ordersKpi?['in_transit'] ?? 0}',
                  subtitle: 'Đã giao: ${ordersKpi?['delivered'] ?? 0}',
                  icon: Icons.local_shipping_outlined,
                  tone: tokens.cyan,
                  onTap: widget.onOpenMerchantOrders,
                ),
                _buildKpiTile(
                  width: tileWidth,
                  title: 'Đổi trả cần xử lý',
                  value: '${aftersalesKpi?['open_returns'] ?? 0}',
                  subtitle: 'Yêu cầu hoàn / khiếu nại',
                  icon: Icons.assignment_return_outlined,
                  tone: tokens.rose,
                  onTap: widget.onOpenOperations,
                ),
                _buildKpiTile(
                  width: tileWidth,
                  title: 'Đánh giá chờ phản hồi',
                  value: '${aftersalesKpi?['unreplied_reviews'] ?? 0}',
                  subtitle:
                      'KM đang chạy: ${(aftersalesKpi?['active_vouchers'] as num? ?? 0) + (aftersalesKpi?['active_flash_sales'] as num? ?? 0)}',
                  icon: Icons.reviews_outlined,
                  tone: tokens.violet,
                  onTap: widget.onOpenOperations,
                ),
                if (canManage && financeKpi != null)
                  _buildKpiTile(
                    width: tileWidth,
                    title: 'Đủ điều kiện quyết toán',
                    value: _vnd(financeKpi['eligible_settlement_total']),
                    subtitle:
                        'Chờ duyệt chi: ${_vnd(financeKpi['pending_settlement_total'])}',
                    icon: Icons.account_balance_wallet_outlined,
                    tone: tokens.emerald,
                    onTap: widget.onOpenOperations,
                  )
                else
                  _buildKpiTile(
                    width: tileWidth,
                    title: 'Sản phẩm mở bán',
                    value:
                        '${catalogKpi?['published_count'] ?? shopProducts.where((p) => p['published'] == true).length}/${catalogKpi?['products_total'] ?? shopProducts.length}',
                    subtitle:
                        'Sắp hết/hết: ${(catalogKpi?['low_stock_count'] as num? ?? 0) + (catalogKpi?['out_of_stock_count'] as num? ?? 0)}',
                    icon: Icons.fact_check_outlined,
                    tone: tokens.emerald,
                  ),
              ];
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: tiles,
              );
            },
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _actionBusy || !canManage
                  ? null
                  : () => widget.onEdit(shop: activeShop, editShop: true),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Sửa cửa hàng'),
            ),
            FilledButton.icon(
              onPressed:
                  _actionBusy || !canManage || activeShop['status'] == 'suspended'
                  ? null
                  : () => widget.onEdit(shop: activeShop),
              icon: const Icon(Icons.add),
              label: const Text('Thêm sản phẩm'),
            ),
            if (canManage)
              OutlinedButton.icon(
                key: const ValueKey('merchant-open-stock-ledger'),
                onPressed: _actionBusy
                    ? null
                    : () => showMerchantStockLedgerDialog(
                        context,
                        session: widget.session,
                        shop: activeShop,
                      ),
                icon: const Icon(Icons.history_edu_outlined),
                label: const Text('Sổ tồn kho'),
              ),
            if (canManage)
              OutlinedButton.icon(
                onPressed: _actionBusy
                    ? null
                    : () async {
                        final ok = await showVoucherEditorDialog(
                          context,
                          session: widget.session,
                          shopId: shopId,
                        );
                        if (ok == true && widget.lease.valid) {
                          await widget.onReload();
                        }
                      },
                icon: const Icon(Icons.confirmation_num_outlined),
                label: const Text('Voucher shop'),
              ),
            if (canManage && shopProducts.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _actionBusy
                    ? null
                    : () async {
                        final ok = await showFlashSaleEditorDialog(
                          context,
                          session: widget.session,
                          products: shopProducts,
                        );
                        if (ok == true && widget.lease.valid) {
                          await widget.onReload();
                        }
                      },
                icon: const Icon(Icons.flash_on_outlined),
                label: const Text('Flash Sale'),
              ),
            if (widget.onOpenOperations != null)
              OutlinedButton.icon(
                key: const ValueKey('merchant-open-operations-btn'),
                onPressed: _actionBusy ? null : widget.onOpenOperations,
                icon: const Icon(Icons.analytics_outlined),
                label: Text(
                  canManage ? 'Khuyến mãi & Đối soát' : 'Đổi trả & Đánh giá',
                ),
              ),
            if (isDirectOwner)
              OutlinedButton.icon(
                onPressed: _actionBusy
                    ? null
                    : () async {
                        await showShopStaffDialog(
                          context,
                          session: widget.session,
                          shop: activeShop,
                          initialStaff: widget.staff,
                        );
                        if (widget.lease.valid) await widget.onReload();
                      },
                icon: const Icon(Icons.group_outlined),
                label: const Text('Nhân sự'),
              ),
            if (isDirectOwner && widget.session.hasRole('merchant'))
              OutlinedButton.icon(
                onPressed: _actionBusy
                    ? null
                    : () => widget.onEdit(editShop: true),
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Mở thêm chi nhánh'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        GhstLuminousCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Danh mục mặt hàng (${shopProducts.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('merchant-catalog-search'),
                controller: _catalogSearch,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Tìm theo tên sản phẩm, mã SKU hoặc danh mục...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _catalogSearch.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Xóa tìm kiếm',
                          onPressed: () => setState(_catalogSearch.clear),
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in const [
                    ('all', 'Tất cả'),
                    ('published', 'Đang bán'),
                    ('low_stock', 'Sắp hết ≤5'),
                    ('out_of_stock', 'Hết hàng'),
                    ('hidden', 'Đã ẩn'),
                  ])
                    ChoiceChip(
                      label: Text(item.$2),
                      selected: _catalogFilter == item.$1,
                      onSelected: (_) =>
                          setState(() => _catalogFilter = item.$1),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (visibleProducts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    shopProducts.isEmpty
                        ? 'Gian hàng chưa có sản phẩm nào. Hãy bấm Thêm sản phẩm để mở bán.'
                        : 'Không có sản phẩm khớp bộ lọc hiện tại.',
                    style: TextStyle(color: tokens.inkSecondary),
                  ),
                ),
              for (var i = 0; i < visibleProducts.length; i++) ...[
                if (i > 0) const Divider(height: 20),
                _buildProductRow(
                  context,
                  tokens: tokens,
                  shop: activeShop,
                  product: visibleProducts[i],
                  canManage: canManage && activeShop['status'] != 'suspended',
                ),
              ],
            ],
          ),
        ),
        if (widget.session.hasRole('merchant')) ...[
          const SizedBox(height: 20),
          Text(
            'Vận hành giao hàng',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _actionBusy
                    ? null
                    : () => openCloudPickups(context, widget.session),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Lịch xe thu gom'),
              ),
              OutlinedButton.icon(
                onPressed: _actionBusy
                    ? null
                    : () => openCloudOrderImport(context, widget.session),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Nhập đơn từ CSV'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CloudDeliveryStatsCard(
            service: widget.session.service,
            lease: widget.lease,
          ),
        ],
      ],
    );
  }

  Widget _buildKpiTile({
    required double width,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required TonePair tone,
    VoidCallback? onTap,
  }) => SizedBox(
    width: width,
    child: GhstLuminousCard(
      padding: const EdgeInsets.all(14),
      accentGlow: tone.glow,
      borderColor: tone.border,
      interactive3d: onTap != null,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: tone.fill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tone.border),
                ),
                child: Icon(icon, size: 16, color: tone.icon),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: tone.foreground),
          ),
        ],
      ),
    ),
  );

  Widget _buildProductRow(
    BuildContext context, {
    required GhstThemeTokens tokens,
    required Map<String, dynamic> shop,
    required Map<String, dynamic> product,
    required bool canManage,
  }) {
    final stock = (product['stock'] as num? ?? 0).toInt();
    final published = product['published'] == true;
    final variants = _rows(product['variants']);
    final imgUrl = '${product['image_url'] ?? ''}'.trim();
    final stockTone = stock <= 0
        ? tokens.rose
        : stock <= 5
        ? tokens.amber
        : tokens.emerald;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: imgUrl.isEmpty
                    ? ColoredBox(
                        color: tokens.cardSubtle,
                        child: Icon(
                          Icons.inventory_2_outlined,
                          color: tokens.inkMuted,
                        ),
                      )
                    : Image.network(
                        imgUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: tokens.cardSubtle,
                          child: Icon(
                            Icons.inventory_2_outlined,
                            color: tokens.inkMuted,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${product['name']}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${product['sku']} · ${_vnd(product['price'])} · Còn $stock · ${published ? 'Đang bán' : 'Đã ẩn'}',
                    style: TextStyle(fontSize: 12.5, color: tokens.inkSecondary),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _toneBadge(
                        stock <= 0 ? 'Hết hàng' : 'Tồn kho: $stock',
                        stockTone,
                      ),
                      _toneBadge(
                        published ? 'Đang bán' : 'Đã ẩn',
                        published ? tokens.sapphire : tokens.neutral,
                      ),
                      if ('${product['category'] ?? ''}'.trim().isNotEmpty)
                        _toneBadge('${product['category']}', tokens.neutral),
                      if (variants.isNotEmpty)
                        _toneBadge('${variants.length} SKU', tokens.violet),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (canManage)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch.adaptive(
                    key: ValueKey('merchant-product-publish-${product['id']}'),
                    value: published,
                    onChanged: _actionBusy
                        ? null
                        : (val) => _runQuick(
                            () => widget.session.service.merchant(
                              'product_quick_update',
                              {
                                'product_id': product['id'],
                                'version': product['version'] ?? 1,
                                'published': val,
                              },
                            ),
                          ),
                  ),
                  Text(
                    published ? 'Mở bán' : 'Ẩn',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            if (canManage)
              ActionChip(
                key: ValueKey('merchant-product-stock-${product['id']}'),
                avatar: const Icon(Icons.exposure_outlined, size: 16),
                label: const Text('Chỉnh tồn kho'),
                onPressed: _actionBusy
                    ? null
                    : () async {
                        final ok = await showMerchantQuickStockDialog(
                          context,
                          session: widget.session,
                          product: product,
                        );
                        if (ok == true && widget.lease.valid) {
                          await widget.onReload();
                        }
                      },
              ),
            IconButton(
              tooltip: 'Biến thể SKU',
              onPressed: _actionBusy || !canManage
                  ? null
                  : () async {
                      await showMarketVariantsDialog(
                        context,
                        session: widget.session,
                        product: product,
                      );
                      if (widget.lease.valid) await widget.onReload();
                    },
              icon: const Icon(Icons.layers_outlined),
            ),
            if (canManage)
              IconButton(
                tooltip: 'Sổ kho món này',
                onPressed: _actionBusy
                    ? null
                    : () => showMerchantStockLedgerDialog(
                        context,
                        session: widget.session,
                        shop: shop,
                        productId: '${product['id']}',
                        productName: '${product['name']}',
                      ),
                icon: const Icon(Icons.history_outlined),
              ),
            IconButton(
              tooltip: 'Sửa sản phẩm',
              onPressed: _actionBusy || !canManage
                  ? null
                  : () => widget.onEdit(shop: shop, product: product),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        if (variants.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in variants)
                ActionChip(
                  label: Text(
                    '${v['title']} (${v['sku']}): ${_vnd(v['price'])} · Tồn ${v['stock']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: _actionBusy || !canManage
                      ? null
                      : () async {
                          final ok = await showMerchantQuickStockDialog(
                            context,
                            session: widget.session,
                            product: product,
                            variant: v,
                          );
                          if (ok == true && widget.lease.valid) {
                            await widget.onReload();
                          }
                        },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class MerchantOrdersPanel extends StatefulWidget {
  const MerchantOrdersPanel({
    super.key,
    required this.session,
    required this.orders,
    required this.loading,
    required this.loaded,
    required this.busy,
    required this.activeFilter,
    required this.activeSearch,
    this.shops = const [],
    this.selectedShopId,
    required this.onQueryChanged,
    required this.onOrderAction,
    required this.onOpenConversation,
    required this.onReload,
    this.onOpenDeliveryJourney,
  });

  final CloudAccountSession session;
  final List<Map<String, dynamic>> orders;
  final bool loading;
  final bool loaded;
  final bool busy;
  final String activeFilter;
  final String activeSearch;
  final List<Map<String, dynamic>> shops;
  final String? selectedShopId;
  final void Function({String? filter, String? search, String? shopId})
  onQueryChanged;
  final Future<void> Function(Map<String, dynamic> order, String action)
  onOrderAction;
  final Future<void> Function(String orderId) onOpenConversation;
  final Future<void> Function() onReload;
  final ValueChanged<Map<String, dynamic>>? onOpenDeliveryJourney;

  @override
  State<MerchantOrdersPanel> createState() => _MerchantOrdersPanelState();
}

class _MerchantOrdersPanelState extends State<MerchantOrdersPanel> {
  late final TextEditingController _search = TextEditingController(
    text: widget.activeSearch,
  );

  @override
  void didUpdateWidget(covariant MerchantOrdersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeSearch != widget.activeSearch &&
        _search.text != widget.activeSearch) {
      _search.text = widget.activeSearch;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<(String label, Map<String, dynamic> order)> _journeyTargets(
    Map<String, dynamic> o,
  ) {
    final targets = <(String, Map<String, dynamic>)>[];
    for (final s in _rows(o['shipments'])) {
      if (s['delivery_order'] is Map) {
        final idx = s['parcel_index'] ?? s['parcel_no'] ?? (targets.length + 1);
        final status = cloudStatuses[s['status']] ?? '${s['status'] ?? ''}';
        targets.add((
          'Kiện #$idx · ${s['tracking_code'] ?? ''} ($status)',
          Map<String, dynamic>.from(s['delivery_order'] as Map),
        ));
      }
    }
    if (targets.isEmpty && o['delivery_order'] is Map) {
      targets.add((
        'Vận đơn ${o['tracking_code'] ?? ''}',
        Map<String, dynamic>.from(o['delivery_order'] as Map),
      ));
    }
    return targets;
  }

  Future<void> _openJourneyPicker(
    BuildContext context,
    List<(String, Map<String, dynamic>)> targets,
  ) async {
    if (widget.onOpenDeliveryJourney == null || targets.isEmpty) return;
    if (targets.length == 1) {
      widget.onOpenDeliveryJourney!(targets.single.$2);
      return;
    }
    final chosen = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Chọn kiện vận chuyển cần theo dõi'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final t in targets)
                  ListTile(
                    leading: const Icon(Icons.local_shipping_outlined),
                    title: Text(t.$1),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(dialog, t.$2),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
    if (chosen != null) widget.onOpenDeliveryJourney!(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    const states = {
      'pending': 'Chờ cửa hàng xác nhận',
      'accepted': 'Đang chuẩn bị',
      'ready': 'Đã bàn giao vận chuyển',
      'cancelled': 'Đã hủy',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.shops.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Tất cả cửa hàng'),
                selected: widget.selectedShopId == null,
                onSelected: widget.busy
                    ? null
                    : (_) => widget.onQueryChanged(shopId: ''),
              ),
              for (final sh in widget.shops)
                ChoiceChip(
                  label: Text('${sh['name']}'),
                  selected: widget.selectedShopId == '${sh['id']}',
                  onSelected: widget.busy
                      ? null
                      : (_) => widget.onQueryChanged(shopId: '${sh['id']}'),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('merchant-orders-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => widget.onQueryChanged(search: v.trim()),
                decoration: InputDecoration(
                  hintText: 'Tìm mã đơn, mã vận đơn, tên hoặc SĐT người nhận...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty && widget.activeSearch.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Xóa lọc từ khóa',
                          onPressed: () {
                            _search.clear();
                            widget.onQueryChanged(search: '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: widget.busy
                  ? null
                  : () => widget.onQueryChanged(search: _search.text.trim()),
              child: const Text('Tìm'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in const [
              ('all', 'Tất cả'),
              ('pending', 'Chờ xác nhận'),
              ('accepted', 'Đang chuẩn bị'),
              ('ready', 'Chờ tài xế lấy'),
              ('in_transit', 'Đang giao'),
              ('delivered', 'Đã giao'),
              ('returns', 'Đổi trả mở'),
              ('cancelled', 'Đã hủy'),
            ])
              ChoiceChip(
                key: ValueKey('merchant-order-filter-${f.$1}'),
                label: Text(f.$2),
                selected: widget.activeFilter == f.$1,
                onSelected: widget.busy
                    ? null
                    : (_) => widget.onQueryChanged(filter: f.$1),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (widget.orders.isEmpty && !widget.loading && widget.loaded)
          GhstLuminousCard(
            padding: const EdgeInsets.all(20),
            child: const Text('Chưa có đơn mua hàng.'),
          ),
        for (final o in widget.orders)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Builder(
              builder: (context) {
                final snapshot = o['snapshot'] is Map
                    ? Map<String, dynamic>.from(o['snapshot'] as Map)
                    : const <String, dynamic>{};
                final details = snapshot['details'] is Map
                    ? Map<String, dynamic>.from(snapshot['details'] as Map)
                    : const <String, dynamic>{};
                final buyer = o['buyer_profile'] is Map
                    ? Map<String, dynamic>.from(o['buyer_profile'] as Map)
                    : const <String, dynamic>{};
                final state = '${o['state'] ?? ''}';
                final statusText = state == 'ready'
                    ? cloudStatuses[o['delivery_status']] ??
                          (o['delivered_at'] != null
                              ? 'Đã giao'
                              : states['ready']!)
                    : states[state] ?? state;
                final statusTone = switch (state) {
                  'pending' => tokens.amber,
                  'accepted' => tokens.sapphire,
                  'cancelled' => tokens.rose,
                  _ =>
                    o['delivered_at'] != null ? tokens.emerald : tokens.cyan,
                };
                final acceptBy = DateTime.tryParse('${o['accept_by'] ?? ''}');
                final shipments = _rows(o['shipments']);
                final journeyTargets = _journeyTargets(o);
                final openReturns =
                    (o['open_returns_count'] as num? ?? 0).toInt();
                final messageCount = (o['message_count'] as num? ?? 0).toInt();
                final buyerName = '${buyer['full_name'] ?? ''}'.trim();
                final buyerPhone = '${buyer['phone'] ?? ''}'.trim();
                final dropoff = '${details['dropoff_address'] ?? ''}'.trim();
                final buyerNote =
                    '${snapshot['buyer_note'] ?? details['buyer_note'] ?? ''}'
                        .trim();

                return GhstLuminousCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${o['shop_name'] ?? snapshot['shop_name'] ?? 'Cửa hàng'}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          _toneBadge(statusText, statusTone),
                          if (state == 'pending' && acceptBy != null)
                            Builder(
                              builder: (_) {
                                final diff = acceptBy.difference(
                                  DateTime.now(),
                                );
                                final overdue = diff.isNegative;
                                return _toneBadge(
                                  overdue
                                      ? 'Quá hạn xác nhận'
                                      : 'Còn ${(diff.inMinutes + 1).clamp(1, 999)} phút xác nhận',
                                  overdue ? tokens.rose : tokens.amber,
                                  icon: Icons.timer_outlined,
                                );
                              },
                            ),
                          if (openReturns > 0)
                            _toneBadge(
                              '$openReturns đổi trả mở',
                              tokens.rose,
                              icon: Icons.assignment_return_outlined,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        'Đơn ${o['id']}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: tokens.inkSecondary,
                        ),
                      ),
                      if (buyerName.isNotEmpty || buyerPhone.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Người nhận: ${[if (buyerName.isNotEmpty) buyerName, if (buyerPhone.isNotEmpty) buyerPhone].join(' · ')}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                      if (dropoff.isNotEmpty)
                        Text(
                          'Giao đến: $dropoff',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: tokens.inkSecondary,
                          ),
                        ),
                      if (buyerNote.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Ghi chú khách: $buyerNote',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: tokens.amber.foreground,
                          ),
                        ),
                      ],
                      const Divider(height: 18),
                      for (final item in _rows(snapshot['items']))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${item['quantity']} × ${item['name']} · ${_vnd(item['unit_price'])}'
                            '${marketOptionNames(item['options']).isEmpty ? '' : '\n${marketOptionNames(item['options'])}'}',
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        'Tiền hàng: ${_vnd(snapshot['subtotal'])} · Phí giao: ${_vnd(snapshot['shipping_fee'])}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${o['payment_method'] == 'prepaid' ? 'Trả trước' : 'Thu hộ COD'} · '
                        '${o['payment_status'] == 'PAID'
                            ? 'Đã ghi nhận thanh toán'
                            : o['payment_status'] == 'REVIEW'
                            ? 'Cần đối soát thanh toán'
                            : 'Chưa ghi nhận thanh toán'}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: tokens.inkSecondary,
                        ),
                      ),
                      if (o['tracking_code'] != null) ...[
                        const SizedBox(height: 4),
                        SelectableText('Vận đơn: ${o['tracking_code']}'),
                      ],
                      if (shipments.length > 1)
                        for (final s in shipments)
                          SelectableText(
                            'Kiện #${s['parcel_index'] ?? s['parcel_no']}: ${s['tracking_code']} · ${cloudStatuses[s['status']] ?? s['status']}',
                          ),
                      if ('${o['reason'] ?? ''}'.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Lý do: ${o['reason']}'),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (state == 'pending')
                            FilledButton.icon(
                              onPressed: widget.busy
                                  ? null
                                  : () => widget.onOrderAction(o, 'accept'),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Xác nhận đơn'),
                            ),
                          if (state == 'accepted') ...[
                            FilledButton.icon(
                              onPressed: widget.busy
                                  ? null
                                  : () => widget.onOrderAction(o, 'ready'),
                              icon: const Icon(Icons.local_shipping_outlined),
                              label: const Text('Sẵn sàng giao'),
                            ),
                            if (widget.session.canManageShop(
                              o['shop_id'] as String?,
                            ))
                              OutlinedButton.icon(
                                onPressed: widget.busy
                                    ? null
                                    : () async {
                                        final split =
                                            await showOrderShipmentSplitDialog(
                                              context,
                                              session: widget.session,
                                              order: o,
                                            );
                                        if (split == true) {
                                          await widget.onReload();
                                        }
                                      },
                                icon: const Icon(Icons.call_split),
                                label: const Text('Tách kiện giao'),
                              ),
                          ],
                          if (journeyTargets.isNotEmpty &&
                              widget.onOpenDeliveryJourney != null)
                            FilledButton.tonalIcon(
                              key: ValueKey(
                                'merchant-track-journey-${o['id']}',
                              ),
                              onPressed: widget.busy
                                  ? null
                                  : () => _openJourneyPicker(
                                      context,
                                      journeyTargets,
                                    ),
                              icon: const Icon(Icons.route_outlined),
                              label: Text(
                                journeyTargets.length > 1
                                    ? 'Theo dõi hành trình (${journeyTargets.length} kiện)'
                                    : 'Theo dõi hành trình giao',
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: widget.busy
                                ? null
                                : () => widget.onOpenConversation(
                                    '${o['id']}',
                                  ),
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: Text(
                              messageCount > 0
                                  ? 'Trao đổi ($messageCount)'
                                  : 'Trao đổi',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: widget.busy
                                ? null
                                : () async {
                                    await openMarketOrderServices(
                                      context,
                                      widget.session,
                                      orderId: '${o['id']}',
                                    );
                                    await widget.onReload();
                                  },
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('Chi tiết và hậu mãi'),
                          ),
                          if (state == 'pending' || state == 'accepted')
                            OutlinedButton(
                              onPressed: widget.busy
                                  ? null
                                  : () => widget.onOrderAction(o, 'cancel'),
                              child: const Text('Hủy đơn'),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class MerchantOperationsCenter extends StatefulWidget {
  const MerchantOperationsCenter({
    super.key,
    required this.session,
    required this.lease,
    this.onOpenDeliveryJourney,
  });

  final CloudAccountSession session;
  final CloudSessionLease lease;
  final ValueChanged<Map<String, dynamic>>? onOpenDeliveryJourney;

  @override
  State<MerchantOperationsCenter> createState() =>
      _MerchantOperationsCenterState();
}

class _MerchantOperationsCenterState extends State<MerchantOperationsCenter> {
  Map<String, dynamic>? _dashboard;
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _vouchers = const [];
  List<Map<String, dynamic>> _flashSales = const [];
  List<Map<String, dynamic>> _financeRows = const [];
  List<Map<String, dynamic>> _returnRows = const [];
  List<Map<String, dynamic>> _reviewRows = const [];
  Map<String, dynamic> _reviewSummary = const {};
  String? _selectedShopId;
  String _tab = 'returns';
  String _financeFilter = 'all';
  String _returnFilter = 'all';
  String _reviewFilter = 'all';
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  bool get _valid => mounted && widget.lease.valid;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  bool _canManageSelected(String? shopId) {
    if (widget.session.isOperator) return true;
    final role = '${_dashboard?['my_role'] ?? ''}'.trim();
    if (role == 'owner' || role == 'manager' || role == 'operator') {
      return true;
    }
    return widget.session.canManageShop(shopId);
  }

  Future<void> _load({bool initial = false}) async {
    if (!_valid) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dash = await widget.session.service.merchant('dashboard', {
        if (_selectedShopId != null) 'shop_id': _selectedShopId,
      });
      if (!_valid) return;
      final shops = _rows(dash['shops']);
      final resolvedShopId =
          '${dash['selected_shop_id'] ?? shops.firstOrNull?['id'] ?? ''}'
              .trim();
      final canManage =
          widget.session.isOperator ||
          const {'owner', 'manager', 'operator'}.contains(dash['my_role']) ||
          (resolvedShopId.isNotEmpty &&
              widget.session.canManageShop(resolvedShopId));
      var effectiveTab = _tab;
      if (initial && canManage) {
        effectiveTab = 'finance';
      } else if (!canManage &&
          (effectiveTab == 'finance' || effectiveTab == 'promotions')) {
        effectiveTab = 'returns';
      }

      List<Map<String, dynamic>> shopProducts = _products;
      if (resolvedShopId.isNotEmpty && canManage) {
        try {
          final ws = await widget.session.service.market('workspace');
          shopProducts = _rows(
            ws['products'],
          ).where((p) => '${p['shop_id']}' == resolvedShopId).toList();
        } catch (_) {}
      }

      List<Map<String, dynamic>> vouchers = _vouchers;
      List<Map<String, dynamic>> flashSales = _flashSales;
      List<Map<String, dynamic>> financeRows = _financeRows;
      List<Map<String, dynamic>> returnRows = _returnRows;
      List<Map<String, dynamic>> reviewRows = _reviewRows;
      Map<String, dynamic> reviewSummary = _reviewSummary;

      if (resolvedShopId.isNotEmpty) {
        if (effectiveTab == 'promotions' && canManage) {
          final promo = await widget.session.service.merchant('promotions', {
            'shop_id': resolvedShopId,
          });
          vouchers = _rows(promo['vouchers']);
          flashSales = _rows(promo['flash_sales']);
        } else if (effectiveTab == 'finance' && canManage) {
          final fin = await widget.session.service.merchant(
            'aftersales_inbox',
            {
              'shop_id': resolvedShopId,
              'tab': 'finance',
              'filter': _financeFilter,
            },
          );
          financeRows = _rows(fin['finance']);
        } else if (effectiveTab == 'returns') {
          final ret = await widget.session.service.merchant(
            'aftersales_inbox',
            {
              'shop_id': resolvedShopId,
              'tab': 'returns',
              'filter': _returnFilter,
            },
          );
          returnRows = _rows(ret['returns']);
        } else if (effectiveTab == 'reviews') {
          final rev = await widget.session.service.merchant(
            'aftersales_inbox',
            {
              'shop_id': resolvedShopId,
              'tab': 'reviews',
              'filter': _reviewFilter,
            },
          );
          reviewRows = _rows(rev['reviews']);
          reviewSummary = rev['summary'] is Map
              ? Map<String, dynamic>.from(rev['summary'] as Map)
              : const {};
        }
      }

      if (!_valid) return;
      setState(() {
        _dashboard = dash;
        _selectedShopId = resolvedShopId.isEmpty ? null : resolvedShopId;
        _tab = effectiveTab;
        _products = shopProducts;
        _vouchers = vouchers;
        _flashSales = flashSales;
        _financeRows = financeRows;
        _returnRows = returnRows;
        _reviewRows = reviewRows;
        _reviewSummary = reviewSummary;
        _loading = false;
      });
    } catch (e) {
      if (_valid && !widget.lease.handleAccessFailure(e)) {
        setState(() {
          _error = _errText(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _mutate(
    Future<void> Function() action, {
    String? successNotice,
  }) async {
    if (_busy || !_valid) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      if (!_valid) return;
      if (successNotice != null) _notice = successNotice;
      await _load();
    } catch (e) {
      if (_valid && !widget.lease.handleAccessFailure(e)) {
        setState(() => _error = _errText(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestSettlement(Map<String, dynamic> eligible) async {
    final maxAmount = (eligible['eligible_amount'] as num? ?? 0).toInt();
    final amountCtrl = TextEditingController(text: '$maxAmount');
    final reasonCtrl = TextEditingController(
      text: 'Đề nghị quyết toán doanh thu đơn đã giao hoàn tất',
    );
    final evidenceCtrl = TextEditingController(
      text: '${eligible['tracking_code'] ?? eligible['order_id']}',
    );
    final form = GlobalKey<FormState>();
    Map<String, dynamic>? submitted;
    try {
      submitted = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: widget.session,
          roles: const {'merchant'},
          dialog: true,
          builder: (dialog, lease) => AlertDialog(
            title: const Text('Đề nghị quyết toán đơn hàng'),
            content: SizedBox(
              width: 440,
              child: Form(
                key: form,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Đơn mua: ${eligible['order_id']}'),
                      Text('Tối đa đủ điều kiện: ${_vnd(maxAmount)}'),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('merchant-settlement-amount'),
                        controller: amountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Số tiền đề nghị quyết toán',
                          suffixText: 'đ',
                        ),
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          if (n == null || n <= 0 || n > maxAmount) {
                            return 'Nhập từ 1 đến ${_vnd(maxAmount)}.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: reasonCtrl,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'Nội dung đối soát',
                        ),
                        validator: (v) => (v?.trim().length ?? 0) >= 3
                            ? null
                            : 'Nhập ít nhất 3 ký tự.',
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: evidenceCtrl,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'Mã tham chiếu / chứng từ',
                        ),
                        validator: (v) => (v?.trim().length ?? 0) >= 3
                            ? null
                            : 'Nhập ít nhất 3 ký tự.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Hủy'),
              ),
              FilledButton(
                key: const ValueKey('merchant-settlement-submit'),
                onPressed: () {
                  if (lease.valid && form.currentState!.validate()) {
                    Navigator.pop(dialog, {
                      'amount': int.parse(amountCtrl.text.trim()),
                      'reason': reasonCtrl.text.trim(),
                      'evidence': evidenceCtrl.text.trim(),
                    });
                  }
                },
                child: const Text('Gửi đề nghị'),
              ),
            ],
          ),
        ),
      );
    } finally {
      Future<void>.delayed(const Duration(seconds: 1), () {
        amountCtrl.dispose();
        reasonCtrl.dispose();
        evidenceCtrl.dispose();
      });
    }
    if (submitted == null || !_valid) return;
    await _mutate(
      () => widget.session.service.command('marketplace/finance_request', {
        'order_id': eligible['order_id'],
        'kind': 'settlement',
        'amount': submitted!['amount'],
        'reason': submitted['reason'],
        'evidence': submitted['evidence'],
      }),
      successNotice: 'Đã gửi đề nghị quyết toán thành công.',
    );
  }

  Future<void> _handleReturn(Map<String, dynamic> ret, String action) async {
    final responseCtrl = TextEditingController();
    var createReturnShipment = action == 'approve';
    var disposition = 'restock';
    final form = GlobalKey<FormState>();
    Map<String, dynamic>? payloadExtra;
    try {
      payloadExtra = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: widget.session,
          roles: const {'merchant'},
          dialog: true,
          builder: (dialog, lease) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: Text(
                switch (action) {
                  'approve' => 'Duyệt yêu cầu trả hàng',
                  'reject' => 'Từ chối yêu cầu trả hàng',
                  _ => 'Xác nhận nhận hàng hoàn',
                },
              ),
              content: SizedBox(
                width: 440,
                child: Form(
                  key: form,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: const ValueKey('merchant-return-response'),
                          controller: responseCtrl,
                          maxLength: 1000,
                          decoration: const InputDecoration(
                            labelText: 'Phản hồi gửi khách hàng',
                          ),
                          validator: (v) => (v?.trim().length ?? 0) >= 3
                              ? null
                              : 'Nhập ít nhất 3 ký tự.',
                        ),
                        if (action == 'approve')
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Tạo vận đơn chiều hoàn cho tài xế thu hồi',
                            ),
                            value: createReturnShipment,
                            onChanged: (v) => update(
                              () => createReturnShipment = v == true,
                            ),
                          ),
                        if (action == 'receive') ...[
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: disposition,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Kiểm định hàng hoàn về kho',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'restock',
                                child: Text('Nhập lại tồn kho bán tiếp'),
                              ),
                              DropdownMenuItem(
                                value: 'writeoff',
                                child: Text('Hàng hỏng / Không nhập kho'),
                              ),
                            ],
                            onChanged: (v) =>
                                update(() => disposition = v ?? 'restock'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog),
                  child: const Text('Quay lại'),
                ),
                FilledButton(
                  key: const ValueKey('merchant-return-confirm'),
                  onPressed: () {
                    if (lease.valid && form.currentState!.validate()) {
                      Navigator.pop(dialog, {
                        'response': responseCtrl.text.trim(),
                        if (action == 'approve' && createReturnShipment)
                          'create_return_shipment': true,
                        if (action == 'receive') 'disposition': disposition,
                      });
                    }
                  },
                  child: const Text('Xác nhận'),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      Future<void>.delayed(const Duration(seconds: 1), responseCtrl.dispose);
    }
    if (payloadExtra == null || !_valid) return;
    await _mutate(
      () => widget.session.service.market('return_action', {
        'order_id': ret['order_id'],
        'id': ret['id'],
        'version': ret['version'],
        'action': action,
        ...payloadExtra!,
      }),
      successNotice: 'Đã cập nhật yêu cầu đổi trả.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final shops = _rows(_dashboard?['shops']);
    final canManage = _canManageSelected(_selectedShopId);
    final tabs = <(String, String, IconData)>[
      if (canManage) ...const [
        ('finance', 'Đối soát & Doanh thu', Icons.account_balance_wallet_outlined),
        ('promotions', 'Khuyến mãi Shop', Icons.local_offer_outlined),
      ],
      const ('returns', 'Đổi trả & Khiếu nại', Icons.assignment_return_outlined),
      const ('reviews', 'Đánh giá & Phản hồi', Icons.reviews_outlined),
    ];

    return RefreshIndicator(
      onRefresh: () => _busy ? Future<void>.value() : _load(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        canManage
                            ? 'Kinh doanh, Khuyến mãi & Đối soát'
                            : 'Hậu mãi & Đánh giá cửa hàng',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tải lại',
                      onPressed: _busy || _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (_loading || _busy) const LinearProgressIndicator(),
                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _toneBadge(
                      _notice!,
                      tokens.emerald,
                      icon: Icons.check_circle_outline,
                    ),
                  ),
                if (!_loading && shops.isEmpty && _error == null)
                  GhstLuminousCard(
                    padding: const EdgeInsets.all(20),
                    child: const Text(
                      'Chưa có cửa hàng hoạt động. Hãy tạo cửa hàng trong mục Cửa hàng của tôi trước.',
                    ),
                  )
                else if (shops.isNotEmpty) ...[
                  if (shops.length > 1) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final sh in shops)
                          ChoiceChip(
                            label: Text('${sh['name']}'),
                            selected: '${sh['id']}' == _selectedShopId,
                            onSelected: _busy
                                ? null
                                : (sel) {
                                    if (sel) {
                                      setState(
                                        () => _selectedShopId = '${sh['id']}',
                                      );
                                      _load();
                                    }
                                  },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in tabs)
                        ChoiceChip(
                          key: ValueKey('merchant-ops-tab-${t.$1}'),
                          avatar: Icon(t.$3, size: 16),
                          label: Text(t.$2),
                          selected: _tab == t.$1,
                          onSelected: _busy
                              ? null
                              : (sel) {
                                  if (sel && _tab != t.$1) {
                                    setState(() => _tab = t.$1);
                                    _load();
                                  }
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  switch (_tab) {
                    'finance' when canManage => _buildFinanceTab(tokens),
                    'promotions' when canManage => _buildPromotionsTab(tokens),
                    'reviews' => _buildReviewsTab(tokens),
                    _ => _buildReturnsTab(tokens),
                  },
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFinanceTab(GhstThemeTokens tokens) {
    final kpis = _dashboard?['kpis'] is Map
        ? Map<String, dynamic>.from(_dashboard!['kpis'] as Map)
        : const <String, dynamic>{};
    final finance = kpis['finance'] is Map
        ? Map<String, dynamic>.from(kpis['finance'] as Map)
        : const <String, dynamic>{};
    final eligibleOrders = _rows(finance['eligible_orders']);
    const finKinds = {
      'collection': 'Thu COD',
      'refund': 'Hoàn tiền khách',
      'settlement': 'Quyết toán về shop',
    };
    const finStates = {
      'requested': 'Chờ duyệt',
      'approved': 'Đã duyệt',
      'rejected': 'Từ chối',
      'completed': 'Đã tất toán',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 720 ? 3 : 2;
            final spacing = 10.0;
            final w = (constraints.maxWidth - spacing * (cols - 1)) / cols;
            Widget metric(String label, dynamic val, TonePair tone) => SizedBox(
              width: w,
              child: GhstLuminousCard(
                padding: const EdgeInsets.all(14),
                accentGlow: tone.glow,
                borderColor: tone.border,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tokens.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _vnd(val),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: tone.foreground,
                      ),
                    ),
                  ],
                ),
              ),
            );
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                metric(
                  'Doanh thu hàng ròng',
                  finance['gross_subtotal'],
                  tokens.sapphire,
                ),
                metric(
                  'Đã thu tiền đơn',
                  finance['collected_total'],
                  tokens.cyan,
                ),
                metric(
                  'Đã hoàn tiền khách',
                  finance['refunded_total'],
                  tokens.rose,
                ),
                metric(
                  'Đã quyết toán về shop',
                  finance['settled_total'],
                  tokens.emerald,
                ),
                metric(
                  'Đang chờ duyệt chi',
                  finance['pending_settlement_total'],
                  tokens.amber,
                ),
                metric(
                  'Đủ điều kiện quyết toán',
                  finance['eligible_settlement_total'],
                  tokens.emerald,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        GhstLuminousCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Đơn đủ điều kiện quyết toán (${eligibleOrders.length})',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Áp dụng cho đơn đã giao hoàn tất sau thời gian bảo vệ đổi trả 7 ngày và không còn khiếu nại mở.',
                style: TextStyle(fontSize: 12.5, color: tokens.inkSecondary),
              ),
              const SizedBox(height: 10),
              if (eligibleOrders.isEmpty)
                const Text('Hiện chưa có đơn mới đủ điều kiện đề nghị quyết toán.'),
              for (final el in eligibleOrders)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.cardSubtle,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Đơn ${el['order_id']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Giao lúc ${cloudDate(el['delivered_at'])} · Khả dụng: ${_vnd(el['eligible_amount'])}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: tokens.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                        FilledButton.icon(
                          key: ValueKey(
                            'merchant-propose-settlement-${el['order_id']}',
                          ),
                          onPressed: _busy ? null : () => _requestSettlement(el),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Đề nghị quyết toán'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GhstLuminousCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Lịch sử bút toán đối soát',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in const [
                    ('all', 'Tất cả'),
                    ('settlement', 'Quyết toán shop'),
                    ('collection', 'Thu COD'),
                    ('refund', 'Hoàn tiền'),
                    ('pending', 'Chờ duyệt'),
                  ])
                    ChoiceChip(
                      label: Text(f.$2),
                      selected: _financeFilter == f.$1,
                      onSelected: _busy
                          ? null
                          : (_) {
                              setState(() => _financeFilter = f.$1);
                              _load();
                            },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_financeRows.isEmpty)
                const Text('Chưa có bút toán tài chính khớp bộ lọc.'),
              for (final row in _financeRows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${finKinds[row['kind']] ?? row['kind']} · ${_vnd(row['amount'])}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Đơn ${row['order_id']} · ${finStates[row['state']] ?? row['state']} · ${cloudDate(row['created_at'])}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Mở chi tiết đơn',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () async {
                      await openMarketOrderServices(
                        context,
                        widget.session,
                        orderId: '${row['order_id']}',
                      );
                      if (_valid) await _load();
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPromotionsTab(GhstThemeTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _busy || _selectedShopId == null
                ? null
                : () async {
                    final ok = await showVoucherEditorDialog(
                      context,
                      session: widget.session,
                      shopId: _selectedShopId,
                    );
                    if (ok == true && _valid) await _load();
                  },
            icon: const Icon(Icons.confirmation_num_outlined),
            label: const Text('Tạo Voucher shop'),
          ),
          OutlinedButton.icon(
            onPressed: _busy || _products.isEmpty
                ? null
                : () async {
                    final ok = await showFlashSaleEditorDialog(
                      context,
                      session: widget.session,
                      products: _products,
                    );
                    if (ok == true && _valid) await _load();
                  },
            icon: const Icon(Icons.flash_on_outlined),
            label: const Text('Tạo Flash Sale'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      GhstLuminousCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Mã giảm giá của cửa hàng (${_vouchers.length})',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (_vouchers.isEmpty)
              const Text('Chưa có mã giảm giá nào cho cửa hàng này.'),
            for (final v in _vouchers)
              Builder(
                builder: (_) {
                  final used = (v['budget_used'] as num? ?? 0).toDouble();
                  final total = (v['budget_total'] as num? ?? 1).toDouble();
                  final ratio = total <= 0 ? 0.0 : (used / total).clamp(0.0, 1.0);
                  final active = v['active'] == true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tokens.cardSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: tokens.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${v['code']} · ${v['title']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Switch.adaptive(
                                key: ValueKey(
                                  'merchant-voucher-toggle-${v['id']}',
                                ),
                                value: active,
                                onChanged: _busy
                                    ? null
                                    : (nextActive) => _mutate(
                                        () => widget.session.service.market(
                                          'voucher_save',
                                          {
                                            'id': v['id'],
                                            'version': v['version'],
                                            'shop_id': v['shop_id'],
                                            'code': v['code'],
                                            'title': v['title'],
                                            'discount_kind': v['discount_kind'],
                                            'discount_value':
                                                v['discount_value'],
                                            'max_discount': v['max_discount'],
                                            'min_subtotal': v['min_subtotal'],
                                            'budget_total': v['budget_total'],
                                            'per_user_limit':
                                                v['per_user_limit'],
                                            'starts_at': v['starts_at'],
                                            'ends_at': v['ends_at'],
                                            'active': nextActive,
                                          },
                                        ),
                                      ),
                              ),
                              IconButton(
                                tooltip: 'Sửa voucher',
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        final ok =
                                            await showVoucherEditorDialog(
                                              context,
                                              session: widget.session,
                                              shopId: _selectedShopId,
                                              voucher: v,
                                            );
                                        if (ok == true && _valid) await _load();
                                      },
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ],
                          ),
                          Text(
                            '${v['discount_kind'] == 'percent' ? 'Giảm ${v['discount_value']}% tối đa ${_vnd(v['max_discount'])}' : 'Giảm ${_vnd(v['discount_value'])}'}'
                            ' · Đơn từ ${_vnd(v['min_subtotal'])} · Đã dùng ${v['usage_count'] ?? 0} lượt',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: tokens.inkSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: ratio),
                          const SizedBox(height: 4),
                          Text(
                            'Ngân sách đã dùng: ${_vnd(used)} / ${_vnd(total)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      GhstLuminousCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Chương trình Flash Sale (${_flashSales.length})',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (_flashSales.isEmpty)
              const Text('Chưa có chương trình Flash Sale nào.'),
            for (final fs in _flashSales)
              Builder(
                builder: (_) {
                  final sold = (fs['sold_stock'] as num? ?? 0).toInt();
                  final alloc = (fs['allocated_stock'] as num? ?? 1).toInt();
                  final active = fs['active'] == true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tokens.cardSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: tokens.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${fs['product_name'] ?? 'Sản phẩm'} (${fs['product_sku'] ?? ''})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Giá Flash Sale: ${_vnd(fs['sale_price'])} (Gốc ${_vnd(fs['original_price'])}) · Đã bán $sold/$alloc suất',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: tokens.inkSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            key: ValueKey('merchant-flash-toggle-${fs['id']}'),
                            value: active,
                            onChanged: _busy
                                ? null
                                : (nextActive) => _mutate(
                                    () => widget.session.service.market(
                                      'flash_sale_save',
                                      {
                                        'id': fs['id'],
                                        'version': fs['version'],
                                        'product_id': fs['product_id'],
                                        'sale_price': fs['sale_price'],
                                        'allocated_stock':
                                            fs['allocated_stock'],
                                        'per_user_limit': fs['per_user_limit'],
                                        'starts_at': fs['starts_at'],
                                        'ends_at': fs['ends_at'],
                                        'active': nextActive,
                                      },
                                    ),
                                  ),
                          ),
                          IconButton(
                            tooltip: 'Sửa Flash Sale',
                            onPressed: _busy
                                ? null
                                : () async {
                                    final ok = await showFlashSaleEditorDialog(
                                      context,
                                      session: widget.session,
                                      products: _products,
                                      flashSale: fs,
                                    );
                                    if (ok == true && _valid) await _load();
                                  },
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    ],
  );

  Widget _buildReturnsTab(GhstThemeTokens tokens) {
    const retStates = {
      'requested': 'Chờ cửa hàng duyệt',
      'approved': 'Đã duyệt nhận hoàn',
      'rejected': 'Đã từ chối',
      'escalated': 'Khiếu nại lên sàn',
      'received': 'Đã nhận hàng hoàn',
    };

    return GhstLuminousCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in const [
                ('all', 'Tất cả'),
                ('open', 'Cần xử lý'),
                ('requested', 'Chờ duyệt'),
                ('approved', 'Đang hoàn về'),
                ('received', 'Đã nhận hoàn'),
              ])
                ChoiceChip(
                  label: Text(f.$2),
                  selected: _returnFilter == f.$1,
                  onSelected: _busy
                      ? null
                      : (_) {
                          setState(() => _returnFilter = f.$1);
                          _load();
                        },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_returnRows.isEmpty)
            const Text('Chưa có yêu cầu trả hàng hoặc khiếu nại nào.'),
          for (final ret in _returnRows)
            Builder(
              builder: (context) {
                final state = '${ret['state'] ?? ''}';
                final attachments = (ret['attachments'] as List? ?? const [])
                    .map((e) => '$e')
                    .where((e) => e.isNotEmpty)
                    .toList();
                final returnDelivery = ret['return_delivery_order'] is Map
                    ? Map<String, dynamic>.from(
                        ret['return_delivery_order'] as Map,
                      )
                    : null;
                final tone = switch (state) {
                  'requested' || 'escalated' => tokens.rose,
                  'approved' => tokens.amber,
                  'received' => tokens.emerald,
                  _ => tokens.neutral,
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: tokens.cardSubtle,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${ret['quantity']} × ${ret['item_name']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            _toneBadge(retStates[state] ?? state, tone),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Khách: ${ret['buyer_name']} · ${ret['buyer_phone']} · Đơn ${ret['order_id']}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: tokens.inkSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('Lý do khách báo: ${ret['reason']}'),
                        if ('${ret['response'] ?? ''}'.trim().isNotEmpty)
                          Text(
                            'Phản hồi của shop: ${ret['response']}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: tokens.inkSecondary,
                            ),
                          ),
                        if (attachments.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (var i = 0; i < attachments.length; i++)
                                ActionChip(
                                  avatar: const Icon(
                                    Icons.image_outlined,
                                    size: 16,
                                  ),
                                  label: Text('Minh chứng #${i + 1}'),
                                  onPressed: () => openSignedPrivateAttachment(
                                    context,
                                    session: widget.session,
                                    name: attachments[i],
                                  ),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (state == 'requested') ...[
                              FilledButton(
                                key: ValueKey(
                                  'merchant-return-approve-${ret['id']}',
                                ),
                                onPressed: _busy
                                    ? null
                                    : () => _handleReturn(ret, 'approve'),
                                child: const Text('Duyệt trả hàng'),
                              ),
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _handleReturn(ret, 'reject'),
                                child: const Text('Từ chối'),
                              ),
                            ],
                            if (state == 'approved')
                              FilledButton.icon(
                                key: ValueKey(
                                  'merchant-return-receive-${ret['id']}',
                                ),
                                onPressed: _busy
                                    ? null
                                    : () => _handleReturn(ret, 'receive'),
                                icon: const Icon(Icons.inventory_outlined),
                                label: const Text('Đã nhận hàng trả'),
                              ),
                            if (returnDelivery != null &&
                                widget.onOpenDeliveryJourney != null)
                              FilledButton.tonalIcon(
                                onPressed: _busy
                                    ? null
                                    : () => widget.onOpenDeliveryJourney!(
                                        returnDelivery,
                                      ),
                                icon: const Icon(Icons.route_outlined),
                                label: const Text('Theo dõi vận đơn hoàn'),
                              ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await openMarketOrderServices(
                                  context,
                                  widget.session,
                                  orderId: '${ret['order_id']}',
                                );
                                if (_valid) await _load();
                              },
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Mở đơn gốc'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildReviewsTab(GhstThemeTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GhstLuminousCard(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _toneBadge(
              'Shop ★ ${_reviewSummary['shop_rating_avg'] ?? 0} (${_reviewSummary['shop_rating_count'] ?? 0})',
              tokens.amber,
            ),
            _toneBadge(
              'Sản phẩm ★ ${_reviewSummary['product_rating_avg'] ?? 0} (${_reviewSummary['product_rating_count'] ?? 0})',
              tokens.sapphire,
            ),
            _toneBadge(
              'Chưa phản hồi: ${_reviewSummary['unreplied_count'] ?? 0}',
              tokens.violet,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      GhstLuminousCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in const [
                  ('all', 'Tất cả'),
                  ('unreplied', 'Chưa phản hồi'),
                  ('replied', 'Đã phản hồi'),
                  ('shop', 'Đánh giá shop'),
                  ('product', 'Đánh giá món'),
                ])
                  ChoiceChip(
                    label: Text(f.$2),
                    selected: _reviewFilter == f.$1,
                    onSelected: _busy
                        ? null
                        : (_) {
                            setState(() => _reviewFilter = f.$1);
                            _load();
                          },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_reviewRows.isEmpty)
              const Text('Chưa có đánh giá nào khớp bộ lọc.'),
            for (final r in _reviewRows)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tokens.cardSubtle,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _toneBadge(
                            '★ ${r['rating']}/5',
                            tokens.amber,
                          ),
                          Text(
                            '${r['target_title']} · ${r['reviewer_name']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            cloudDate(r['created_at']),
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.inkMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('${r['body']}'),
                      if ('${r['reply'] ?? ''}'.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: tokens.cardSurface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: tokens.border),
                          ),
                          child: Text(
                            'Phản hồi của cửa hàng: ${r['reply']}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: tokens.inkSecondary,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          FilledButton.tonalIcon(
                            key: ValueKey('merchant-review-reply-${r['id']}'),
                            onPressed: _busy
                                ? null
                                : () async {
                                    final ok =
                                        await showReviewReplyOrReportDialog(
                                          context,
                                          session: widget.session,
                                          reviewKind: '${r['review_kind']}',
                                          reviewId: '${r['id']}',
                                          reply: true,
                                        );
                                    if (ok == true && _valid) await _load();
                                  },
                            icon: const Icon(Icons.reply_outlined, size: 18),
                            label: Text(
                              '${r['reply'] ?? ''}'.trim().isEmpty
                                  ? 'Phản hồi'
                                  : 'Sửa phản hồi',
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () async {
                                    final ok =
                                        await showReviewReplyOrReportDialog(
                                          context,
                                          session: widget.session,
                                          reviewKind: '${r['review_kind']}',
                                          reviewId: '${r['id']}',
                                          reply: false,
                                        );
                                    if (ok == true && _valid) await _load();
                                  },
                            icon: const Icon(Icons.flag_outlined, size: 18),
                            label: const Text('Báo cáo'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
