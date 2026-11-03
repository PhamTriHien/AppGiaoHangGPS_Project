import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/integrations/push_notification_service.dart';
import '../../core/network/public_json_api.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/market_options.dart';
import '../widgets/cloud_commerce_dialog.dart';
import '../widgets/cloud_logistics_panels.dart';
import '../widgets/cloud_notification_center.dart';
import '../widgets/cloud_profile_form.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/market_catalog_fields.dart';
import '../widgets/market_commercial_sheets.dart';
import '../widgets/market_product_details.dart';
import '../widgets/marketplace_editor.dart';
import 'cloud_address_book_screen.dart';
import 'cloud_local_import_screen.dart';
import 'cloud_order_import_screen.dart';
import 'cloud_orders_screen.dart';
import 'cloud_pickup_screen.dart';
import 'cloud_promo_events_screen.dart';
import 'market_order_services_screen.dart';

enum MarketView {
  catalog,
  cart,
  orders,
  notifications,
  account,
  workspace,
  merchantOrders,
  moderation,
  favorites,
}

String _title(MarketView view) => switch (view) {
  MarketView.catalog => 'Khám phá',
  MarketView.cart => 'Giỏ hàng',
  MarketView.orders => 'Đơn mua',
  MarketView.notifications => 'Thông báo',
  MarketView.account => 'Tài khoản',
  MarketView.workspace => 'Cửa hàng của tôi',
  MarketView.merchantOrders => 'Đơn của cửa hàng',
  MarketView.moderation => 'Duyệt cửa hàng',
  MarketView.favorites => 'Sản phẩm yêu thích',
};
String _money(dynamic value) =>
    CurrencyFormatter.formatVnd((value as num? ?? 0).toDouble());
List<Map<String, dynamic>> _rows(dynamic raw) => (raw as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();

Future<void> openMarketOrderConversation(
  BuildContext context,
  CloudAccountSession session,
  String orderId,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CloudSessionBoundary(
      session: session,
      builder: (_, lease) => _OrderConversation(
        session: session,
        lease: lease,
        orderId: orderId,
      ),
    ),
  ),
);

Future<void> openMarketplaceView(
  BuildContext context,
  CloudAccountSession session,
  MarketView view,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CloudSessionBoundary(
      session: session,
      operator: view == MarketView.moderation,
      roles: {
        if ([MarketView.workspace, MarketView.merchantOrders].contains(view))
          'merchant',
      },
      builder: (_, lease) => Scaffold(
        appBar: AppBar(title: Text(_title(view))),
        body: MarketplaceView(
          session: session,
          view: view,
          lease: lease,
          showHeading: false,
        ),
      ),
    ),
  ),
);

class MarketplaceView extends StatefulWidget {
  const MarketplaceView({
    super.key,
    required this.session,
    required this.view,
    this.lease,
    this.showHeading = true,
    this.shopId,
    this.onNavigate,
    this.onOpenShipping,
    this.onOpenOperator,
  });
  final CloudAccountSession session;
  final MarketView view;
  final CloudSessionLease? lease;
  final bool showHeading;
  final String? shopId;
  final ValueChanged<MarketView>? onNavigate;
  final VoidCallback? onOpenShipping;
  final VoidCallback? onOpenOperator;
  @override
  State<MarketplaceView> createState() => _MarketplaceViewState();
}

class _MarketplaceViewState extends State<MarketplaceView> {
  late final _lease =
      widget.lease ?? CloudSessionLease(session: widget.session);
  final _search = TextEditingController();
  final _voucher = TextEditingController();
  final _buyerNote = TextEditingController();
  String _category = '', _sort = 'default';
  String _shippingMode = 'standard', _paymentMethod = 'cod';
  bool _inStock = false;
  bool _useCoins = false,
      _preferEv = false,
      _requirePod = false,
      _requireOtp = false;
  int? _minPrice, _maxPrice;
  Map<String, dynamic> _data = {}, _cart = {};
  Map<String, dynamic>? _quote;
  List<Map<String, dynamic>> _addresses = [];
  String? _addressId, _error, _notice;
  Map<String, dynamic>? _next;
  bool _expanded = false;
  bool _loading = true, _busy = false, _loaded = false;
  String? _addressError;
  int _generation = 0;
  Timer? _poll;
  bool get _allowed => mounted && _lease.valid;
  CloudAccountSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _lease.addListener(_invalidated);
    if ([MarketView.account, MarketView.notifications].contains(widget.view)) {
      _loading = false;
    } else {
      _load();
    }
    if ([
      MarketView.orders,
      MarketView.merchantOrders,
    ].contains(widget.view)) {
      _poll = Timer.periodic(const Duration(seconds: 20), (_) {
        if (!_busy &&
            !_loading &&
            ModalRoute.of(context)?.isCurrent != false &&
            !_expanded) {
          _load(silent: true);
        }
      });
    }
  }

  void _invalidated() {
    if (!_lease.valid && mounted) {
      _generation++;
      setState(() {
        _loaded = false;
        _data = {};
        _cart = {};
        _quote = null;
        _addresses = [];
        _notice = _error = null;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _poll?.cancel();
    _lease.removeListener(_invalidated);
    if (widget.lease == null) _lease.dispose();
    _search.dispose();
    _voucher.dispose();
    _buyerNote.dispose();
    super.dispose();
  }

  String _message(Object e) => e is PublicApiException && e.statusCode != 503
      ? e.message
      : 'Dịch vụ tạm thời chưa khả dụng. Vui lòng thử lại sau.';

  Future<void> _load({bool silent = false, bool more = false}) async {
    if (!_allowed) return;
    final generation = ++_generation;
    setState(() {
      if (!silent) _loading = true;
      _error = null;
      if (widget.view == MarketView.cart) _quote = null;
      if (!more &&
          [MarketView.catalog, MarketView.favorites].contains(widget.view)) {
        _data = {};
        _loaded = false;
        _next = null;
      }
    });
    try {
      final action = switch (widget.view) {
        MarketView.catalog => 'catalog',
        MarketView.favorites => 'favorites',
        MarketView.cart => 'cart',
        MarketView.orders || MarketView.merchantOrders => 'orders',
        MarketView.notifications => 'notifications',
        MarketView.workspace || MarketView.moderation => 'workspace',
        MarketView.account => 'profile',
      };
      final response = await _session.service.market(action, {
        if (widget.view == MarketView.catalog && _search.text.trim().isNotEmpty)
          'search': _search.text.trim(),
        if (widget.view == MarketView.catalog) ...{
          if (widget.shopId != null) 'shop_id': widget.shopId,
          if (_category.isNotEmpty) 'category': _category,
          if (_sort != 'default') 'sort': _sort,
          if (_inStock) 'in_stock': true,
          if (_minPrice != null) 'min_price': _minPrice,
          if (_maxPrice != null) 'max_price': _maxPrice,
        },
        if (widget.view == MarketView.merchantOrders) 'workspace': 'merchant',
        if (widget.view == MarketView.moderation) 'moderation': true,
        if (more && _next != null) ..._next!,
      });
      List<Map<String, dynamic>> addresses = _addresses;
      String? addressError;
      if (widget.view == MarketView.cart) {
        try {
          addresses = _rows(
            (await _session.service.request('addresses'))['addresses'],
          );
        } catch (error) {
          if (!_allowed || generation != _generation) return;
          if (_lease.handleAccessFailure(error)) return;
          addresses = [];
          addressError = 'Chưa tải được sổ địa chỉ. Vui lòng tải lại.';
        }
      }
      if (!_allowed || generation != _generation) return;
      final key = switch (widget.view) {
        MarketView.catalog ||
        MarketView.workspace ||
        MarketView.favorites => 'products',
        MarketView.orders || MarketView.merchantOrders => 'orders',
        MarketView.notifications => 'notifications',
        MarketView.moderation => 'shops',
        _ => '',
      };
      setState(() {
        if (more && key.isNotEmpty) {
          response[key] = {
            for (final row in [..._rows(_data[key]), ..._rows(response[key])])
              row['id']: row,
          }.values.toList();
        }
        _data = response;
        _loaded = true;
        _expanded = more;
        _next = response['next'] == null
            ? null
            : Map<String, dynamic>.from(response['next'] as Map);
        if (widget.view == MarketView.cart) {
          _cart = response;
          _addresses = addresses;
          _addressError = addressError;
          _quote = null;
          if (!_addresses.any((a) => a['id'] == _addressId)) {
            _addressId = _addresses.isEmpty
                ? null
                : (_addresses.firstWhere(
                        (a) => a['is_default'] == true,
                        orElse: () => _addresses.first,
                      )['id']
                      as String);
          }
        }
      });
    } catch (e) {
      if (_allowed && generation == _generation) {
        if (_lease.handleAccessFailure(e)) return;
        setState(() {
          if (e is PublicApiException && e.statusCode == 404) {
            _data = {};
            _cart = {};
            _quote = null;
            _addresses = [];
            _loaded = false;
            _next = null;
          }
          _error = _message(e);
        });
      }
    } finally {
      if (_allowed && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _loading || !_allowed) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = _notice = null;
    });
    try {
      await action();
    } catch (e) {
      if (_allowed && generation == _generation) {
        if (_lease.handleAccessFailure(e)) return;
        if (e is PublicApiException &&
            e.statusCode == 409 &&
            [
              MarketView.cart,
              MarketView.orders,
              MarketView.merchantOrders,
            ].contains(widget.view)) {
          await _load(silent: true);
          if (!_allowed) return;
        }
        setState(() {
          if (e is PublicApiException && e.statusCode == 404) {
            _data = {};
            _cart = {};
            _quote = null;
            _addresses = [];
            _loaded = false;
            _next = null;
          }
          _error = _message(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(Map<String, dynamic> product) => _run(() async {
    final cart = await _session.service.market('cart');
    if (!_allowed) return;
    final items = _rows(cart['items']);
    final selection = product['selected_options'] ?? <dynamic>[];
    final variantId = product['variant_id'];
    final existing = items
        .where(
          (p) =>
              p['id'] == product['id'] &&
              '${p['variant_id'] ?? ''}' == '${variantId ?? ''}' &&
              marketSelectionKey(p['selected_options']) ==
                  marketSelectionKey(selection),
        )
        .firstOrNull;
    await _session.service.market('cart_set', {
      'product_id': product['id'],
      'variant_id': ?variantId,
      'selected_options': selection,
      'quantity': (existing?['quantity'] as int? ?? 0) + 1,
      'version': cart['version'],
    });
    if (_allowed) setState(() => _notice = 'Đã thêm vào giỏ hàng.');
  });

  Future<void> _quantity(Map<String, dynamic> product, int qty) =>
      _run(() async {
        final cart = await _session.service.market('cart_set', {
          'product_id': product['id'],
          if (product['line_id'] != null) 'line_id': product['line_id'],
          if (product['variant_id'] != null) 'variant_id': product['variant_id'],
          'quantity': qty,
          'version': _cart['version'],
        });
        if (_allowed) {
          setState(() {
            _cart = cart;
            _quote = null;
          });
        }
      });

  Future<void> _getQuote() => _run(() async {
    setState(() => _quote = null);
    final voucher = _voucher.text.trim().toUpperCase();
    final note = _buyerNote.text.trim();
    final response = await _session.service.market('quote', {
      'address_id': _addressId,
      'cart_version': _cart['version'],
      if (_addresses
              .where((a) => a['id'] == _addressId)
              .firstOrNull?['version'] !=
          null)
        'address_version': _addresses.firstWhere(
          (a) => a['id'] == _addressId,
        )['version'],
      if (_shippingMode != 'standard') 'service_type': _shippingMode,
      if (_paymentMethod != 'cod') 'payment_method': _paymentMethod,
      if (voucher.isNotEmpty) 'voucher_code': voucher,
      if (_useCoins) 'use_coins': true,
      if (note.isNotEmpty) 'buyer_note': note,
      if (_preferEv) 'prefer_ev': true,
      if (_requirePod) 'require_pod': true,
      if (_requireOtp) 'require_otp': true,
    });
    if (_allowed) {
      setState(
        () => _quote = Map<String, dynamic>.from(response['quote'] as Map),
      );
    }
  });

  Future<void> _conversation(String orderId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudSessionBoundary(
          session: _session,
          builder: (_, lease) => _OrderConversation(
            session: _session,
            lease: lease,
            orderId: orderId,
          ),
        ),
      ),
    );
  }

  Future<void> _checkout() => _run(() async {
    final quote = _quote;
    if (quote == null) return;
    final response = await _session.service.command('marketplace/checkout', {
      'quote_id': quote['id'],
    });
    if (!_allowed) return;
    final purchase = Map<String, dynamic>.from(response['purchase'] as Map);
    final id = purchase['id'];
    setState(() {
      _quote = null;
      _cart = {};
      _notice = 'Đã đặt mua. Mã đơn: $id';
    });
    unawaited(_session.refresh().catchError((Object _) {}));
    await _load();
    if (_allowed && purchase['payment_method'] == 'prepaid' && mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: _session,
          dialog: true,
          builder: (_, lease) => CloudCommerceDialog(
            service: _session.service,
            order: {
              ...purchase,
              'owner_id': _session.service.userId,
              'tracking_code': id,
            },
            purchase: true,
            lease: lease,
          ),
        ),
      );
    }
  });

  Future<void> _addressesPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudSessionBoundary(
          session: _session,
          builder: (_, lease) =>
              CloudAddressBookScreen(service: _session.service, lease: lease),
        ),
      ),
    );
    if (_allowed && widget.view == MarketView.cart) await _load();
  }

  Future<void> _edit({
    Map<String, dynamic>? shop,
    Map<String, dynamic>? product,
    bool editShop = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => CloudSessionBoundary(
          session: _session,
          roles: const {'merchant'},
          builder: (_, lease) => MarketplaceEditor(
            service: _session.service,
            lease: lease,
            shop: shop ?? {},
            product: product,
            editShop: editShop,
          ),
        ),
      ),
    );
    if (_allowed) await _load();
  }

  Future<void> _showShopDetails(String shopId) => _run(() async {
    final res = await _session.service.market('shop_details', {
      'shop_id': shopId,
    });
    if (!_allowed || !mounted) return;
    final shop = Map<String, dynamic>.from(res['shop'] as Map? ?? const {});
    final reviews = _rows(res['reviews']);
    await showDialog<void>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: _session,
        dialog: true,
        builder: (dialog, _) => AlertDialog(
          title: Text('${shop['name'] ?? 'Thông tin cửa hàng'}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đánh giá: ${res['rating_avg'] ?? 0} sao · ${res['rating_count'] ?? 0} lượt · Theo dõi: ${res['followers'] ?? 0}',
                  ),
                  const Divider(),
                  if (reviews.isEmpty)
                    const Text('Chưa có đánh giá cửa hàng.'),
                  for (final r in reviews)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${r['rating']}/5 sao'),
                      subtitle: Text(
                        '${r['body']}'
                        '${(r['reply'] as String? ?? '').isEmpty ? '' : '\nPhản hồi: ${r['reply']}'}',
                      ),
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
      ),
    );
  });

  Future<void> _action(Map<String, dynamic> order, String action) async {
    String reason = '';
    if (action == 'cancel') {
      final controller = TextEditingController();
      final response = await showDialog<String>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: _session,
          dialog: true,
          builder: (dialog, _) => AlertDialog(
            title: const Text('Hủy đơn mua'),
            content: TextField(
              controller: controller,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Lý do'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Quay lại'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, controller.text.trim()),
                child: const Text('Hủy đơn'),
              ),
            ],
          ),
        ),
      );
      Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
      if (response == null || !_allowed) return;
      if (response.length < 3) {
        setState(() => _error = 'Vui lòng nhập lý do ít nhất 3 ký tự.');
        return;
      }
      reason = response;
    }
    await _run(() async {
      await _session.service.market('order_action', {
        'order_id': order['id'],
        'version': order['version'],
        'action': action,
        'reason': reason,
      });
      if (_allowed) await _load();
    });
  }

  Widget _picture(Map<String, dynamic> product, {double height = 140}) {
    final url = product['image_url'] as String? ?? '';
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: const Center(child: Icon(Icons.inventory_2_outlined, size: 40)),
    );
    return SizedBox(
      height: height,
      width: double.infinity,
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }

  Future<void> _details(Map<String, dynamic> product) async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: _session,
        dialog: true,
        builder: (_, lease) => MarketProductDetails(
          session: _session,
          lease: lease,
          productId: product['id'] as String,
        ),
      ),
    );
    if (selected != null && _allowed) await _add(selected);
    if (_allowed && widget.view == MarketView.favorites) await _load();
  }

  Future<void> _openShop(Map<String, dynamic> product) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CloudSessionBoundary(
            session: _session,
            builder: (_, lease) => Scaffold(
              appBar: AppBar(
                title: Text(
                  '${product['shop_name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              body: MarketplaceView(
                session: _session,
                view: MarketView.catalog,
                lease: lease,
                shopId: product['shop_id'] as String,
                showHeading: false,
              ),
            ),
          ),
        ),
      );

  Future<void> _priceFilter() async {
    final low = TextEditingController(text: _minPrice?.toString() ?? ''),
        high = TextEditingController(text: _maxPrice?.toString() ?? '');
    final form = GlobalKey<FormState>();
    try {
      final values = await showDialog<List<int?>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Khoảng giá'),
          content: SizedBox(
            width: 320,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in [(low, 'Giá từ'), (high, 'Giá đến')])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextFormField(
                        controller: entry.$1,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: entry.$2, suffixText: 'đ'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final parsed = int.tryParse(value.trim());
                          if (parsed == null ||
                              parsed < 0 ||
                              parsed > 10000000) {
                            return 'Nhập giá từ 0 đến 10.000.000 đ.';
                          }
                          if (entry.$1 == high &&
                              parsed < (int.tryParse(low.text.trim()) ?? 0)) {
                            return 'Giá tối đa phải từ giá tối thiểu.';
                          }
                          return null;
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, <int?>[null, null]),
              child: const Text('Xóa lọc'),
            ),
            FilledButton(
              onPressed: () {
                if (_allowed && form.currentState!.validate()) {
                  Navigator.pop(dialogContext, [
                    int.tryParse(low.text.trim()),
                    int.tryParse(high.text.trim()),
                  ]);
                }
              },
              child: const Text('Áp dụng'),
            ),
          ],
        ),
      );
      if (values != null && _allowed) {
        setState(() {
          _minPrice = values[0];
          _maxPrice = values[1];
        });
        await _load();
      }
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      low.dispose();
      high.dispose();
    }
  }

  Widget _catalog() {
    final products = _rows(_data['products']);
    final shop = _data['shop'] as Map?;
    final categories = <String>{
      '',
      _category,
      ...(_data['categories'] as List? ?? []).cast<String>(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shop != null) ...[
          if ((shop['banner_url'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                height: 140,
                child: Image.network(
                  '${shop['banner_url']}',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          if ((shop['description'] as String? ?? '').isNotEmpty)
            Text('${shop['description']}'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_on_outlined),
            title: Text('${shop['address']}'),
            subtitle: (shop['service_radius_km'] as num? ?? 0) > 0
                ? Text('Phạm vi giao hàng: ${shop['service_radius_km']} km')
                : null,
          ),
          if (shop['paused'] == true) const Text('Cửa hàng đang tạm nghỉ.'),
          if (shop['paused'] != true && shop['open'] == false)
            const Text('Cửa hàng ngoài giờ hoạt động.'),
          for (final slot in marketRows(shop['opening_schedule']))
            Text(
              '${MarketScheduleEditor.days[(slot['day'] as int) - 1]}: '
              '${MarketScheduleEditor.time(slot['open'] as int)}–${MarketScheduleEditor.time(slot['close'] as int)}',
            ),
          if (shop['id'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: Icon(
                      shop['following'] == true
                          ? Icons.bookmark_added
                          : Icons.bookmark_add_outlined,
                      size: 16,
                    ),
                    label: Text(
                      shop['following'] == true
                          ? 'Đang theo dõi'
                          : 'Theo dõi cửa hàng',
                    ),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _session.service.market('shop_follow_set', {
                              'shop_id': shop['id'],
                              'enabled': shop['following'] != true,
                            });
                            if (_allowed) await _load(silent: true);
                          }),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.star_outline, size: 16),
                    label: const Text('Đánh giá cửa hàng'),
                    onPressed: _busy
                        ? null
                        : () => _showShopDetails('${shop['id']}'),
                  ),
                ],
              ),
            ),
          const Divider(),
        ],
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
          decoration: InputDecoration(
            labelText: 'Tìm sản phẩm, cửa hàng',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Tìm kiếm',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
        ),
        if (widget.view == MarketView.catalog) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('category-$_category'),
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Danh mục'),
                  items: categories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(
                            c.isEmpty ? 'Tất cả' : c,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (v) {
                          setState(() => _category = v ?? '');
                          _load();
                        },
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _sort,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sắp xếp'),
                  items: const [
                    DropdownMenuItem(value: 'default', child: Text('Mặc định')),
                    DropdownMenuItem(
                      value: 'price_asc',
                      child: Text('Giá tăng dần'),
                    ),
                    DropdownMenuItem(
                      value: 'price_desc',
                      child: Text('Giá giảm dần'),
                    ),
                    DropdownMenuItem(
                      value: 'newest',
                      child: Text('Mới cập nhật'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) {
                          setState(() => _sort = v ?? 'default');
                          _load();
                        },
                ),
              ),
              FilterChip(
                label: const Text('Còn hàng'),
                selected: _inStock,
                onSelected: _busy
                    ? null
                    : (v) {
                        setState(() => _inStock = v);
                        _load();
                      },
              ),
              IconButton(
                tooltip: 'Khoảng giá',
                onPressed: _busy ? null : _priceFilter,
                color: _minPrice != null || _maxPrice != null
                    ? Theme.of(context).colorScheme.primary
                    : null,
                icon: const Icon(Icons.price_change_outlined),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        if (products.isEmpty && !_loading && _loaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('Chưa có sản phẩm phù hợp.'),
          ),
        LayoutBuilder(
          builder: (context, c) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: products.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: c.maxWidth < 500
                  ? 1
                  : c.maxWidth < 850
                  ? 2
                  : 3,
              mainAxisExtent: 380,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemBuilder: (context, index) {
              final p = products[index];
              final flashPrice = p['flash_sale_price'] as num?;
              final hasVariants = (p['variants_count'] as num? ?? 0) > 0;
              return Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  onTap: () => _details(p),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _picture(p),
                        const SizedBox(height: 12),
                        Text(
                          '${p['name']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              alignment: Alignment.centerLeft,
                            ),
                            onPressed: p['shop_id'] == null
                                ? null
                                : () => _openShop(p),
                            icon: const Icon(
                              Icons.storefront_outlined,
                              size: 16,
                            ),
                            label: Text(
                              '${p['shop_name']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          flashPrice != null
                              ? '${_money(flashPrice)} · Flash Sale'
                              : _money(p['price']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                p['available'] == false
                                    ? 'Chưa nhận đặt'
                                    : p['stock'] == 0
                                    ? 'Hết hàng'
                                    : 'Còn ${p['stock']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Thêm vào giỏ',
                              onPressed:
                                  _busy ||
                                      p['stock'] == 0 ||
                                      p['available'] == false
                                  ? null
                                  : () =>
                                        marketRows(p['option_groups']).isEmpty &&
                                            !hasVariants
                                        ? _add(p)
                                        : _details(p),
                              icon: const Icon(Icons.add_shopping_cart),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _cartView() {
    final items = _rows(_cart['items']);
    final quoteSnapshot = _quote?['snapshot'] as Map?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p['shop_name']}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Text(
                  '${p['name']} · ${p['sku']}'
                  '${(p['variant_title'] as String? ?? '').isEmpty ? '' : ' · ${p['variant_title']}'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (marketOptionNames(p['options']).isNotEmpty)
                  Text(marketOptionNames(p['options'])),
                Text(
                  p['unit_price'] == null && p['available'] == false
                      ? 'Lựa chọn đã thay đổi'
                      : _money(p['unit_price'] ?? p['price']),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Giảm số lượng',
                      onPressed: _busy || _loading
                          ? null
                          : () => _quantity(p, (p['quantity'] as int) - 1),
                      icon: const Icon(Icons.remove),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${p['quantity']}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tăng số lượng',
                      onPressed: _busy || _loading || p['quantity'] == 99
                          ? null
                          : () => _quantity(p, (p['quantity'] as int) + 1),
                      icon: const Icon(Icons.add),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Xóa sản phẩm',
                      onPressed: _busy || _loading
                          ? null
                          : () => _quantity(p, 0),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                if (p['stock'] < p['quantity'] ||
                    p['published'] != true ||
                    p['shop_status'] != 'active' ||
                    p['paused'] == true ||
                    p['available'] == false)
                  const Text('Sản phẩm hiện không thể đặt mua.'),
                const Divider(),
              ],
            ),
          ),
        if (items.isEmpty && !_loading && _loaded)
          const Text('Giỏ hàng đang trống.'),
        if (items.isNotEmpty) ...[
          if (_addressError != null) Text(_addressError!),
          if (_addresses.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey(_addressId),
              initialValue: _addressId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Địa chỉ nhận hàng'),
              items: _addresses
                  .map(
                    (a) => DropdownMenuItem(
                      value: a['id'] as String,
                      child: Text(
                        '${a['label']} · ${a['full_address']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busy || _loading
                  ? null
                  : (value) => setState(() {
                      _addressId = value;
                      _quote = null;
                    }),
            ),
          TextButton.icon(
            onPressed: _busy ? null : _addressesPage,
            icon: const Icon(Icons.location_on_outlined),
            label: Text(
              _addresses.isEmpty ? 'Thêm địa chỉ nhận hàng' : 'Sổ địa chỉ',
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Thanh toán khi nhận hàng'),
                selected: _paymentMethod == 'cod',
                onSelected: _busy || _loading
                    ? null
                    : (_) => setState(() {
                        _paymentMethod = 'cod';
                        _quote = null;
                      }),
              ),
              ChoiceChip(
                label: const Text('Trả trước trực tuyến payOS'),
                selected: _paymentMethod == 'prepaid',
                onSelected: _busy || _loading
                    ? null
                    : (_) => setState(() {
                        _paymentMethod = 'prepaid';
                        _quote = null;
                      }),
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Vận chuyển, Voucher & Xu thưởng'),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _shippingMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Phương thức giao hàng',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'standard',
                    child: Text('Tiêu chuẩn'),
                  ),
                  DropdownMenuItem(value: 'express', child: Text('Giao nhanh')),
                  DropdownMenuItem(
                    value: 'saving',
                    child: Text('Tiết kiệm 4h'),
                  ),
                  DropdownMenuItem(
                    value: 'same_day_2h',
                    child: Text('Ghép đơn 2H'),
                  ),
                ],
                onChanged: _busy || _loading
                    ? null
                    : (v) => setState(() {
                        _shippingMode = v ?? 'standard';
                        _quote = null;
                      }),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _voucher,
                      enabled: !_busy && !_loading,
                      decoration: const InputDecoration(
                        labelText: 'Mã giảm giá',
                      ),
                      onChanged: (_) => setState(() => _quote = null),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _busy || _loading
                        ? null
                        : () async {
                            final code = await showVoucherBrowserDialog(
                              context,
                              session: _session,
                            );
                            if (code != null && _allowed) {
                              setState(() {
                                _voucher.text = code;
                                _quote = null;
                              });
                            }
                          },
                    icon: const Icon(Icons.confirmation_num_outlined),
                    label: const Text('Chọn mã'),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Đổi Xu thưởng · ${_session.coinBalance} Xu khả dụng',
                ),
                value: _useCoins,
                onChanged: _busy || _loading || _session.coinBalance <= 0
                    ? null
                    : (v) => setState(() {
                        _useCoins = v;
                        _quote = null;
                      }),
              ),
              TextField(
                controller: _buyerNote,
                enabled: !_busy && !_loading,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú đơn hàng',
                ),
                onChanged: (_) => setState(() => _quote = null),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ưu tiên xe điện'),
                value: _preferEv,
                onChanged: _busy || _loading
                    ? null
                    : (v) => setState(() {
                        _preferEv = v;
                        _quote = null;
                      }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Yêu cầu ảnh bằng chứng giao hàng'),
                value: _requirePod,
                onChanged: _busy || _loading
                    ? null
                    : (v) => setState(() {
                        _requirePod = v;
                        _quote = null;
                      }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Yêu cầu mã OTP 6 số khi nhận'),
                value: _requireOtp,
                onChanged: _busy || _loading
                    ? null
                    : (v) => setState(() {
                        _requireOtp = v;
                        _quote = null;
                      }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || _loading || _addressId == null
                ? null
                : _getQuote,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Cập nhật báo giá'),
          ),
          if (quoteSnapshot != null) ...[
            for (final s in _rows(quoteSnapshot['shops']))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${s['shop_name']}'),
                    for (final item in _rows(s['items'])) ...[
                      Text(
                        '${item['quantity']} × ${item['name']} · ${_money(item['unit_price'])}',
                      ),
                      if (marketOptionNames(item['options']).isNotEmpty)
                        Text(marketOptionNames(item['options'])),
                    ],
                    if ((s['details'] as Map?)?['dropoff_address'] != null)
                      Text('Giao đến: ${s['details']['dropoff_address']}'),
                    Text('Tiền hàng: ${_money(s['subtotal'])}'),
                    if ((s['voucher_discount'] as num? ?? 0) > 0)
                      Text('Giảm voucher: -${_money(s['voucher_discount'])}'),
                    if ((s['coin_discount'] as num? ?? 0) > 0)
                      Text('Đổi Xu: -${_money(s['coin_discount'])}'),
                    Text('Phí giao hàng: ${_money(s['shipping_fee'])}'),
                  ],
                ),
              ),
            if ((quoteSnapshot['voucher_discount'] as num? ?? 0) > 0)
              Text(
                'Tổng giảm voucher: -${_money(quoteSnapshot['voucher_discount'])}',
              ),
            if ((quoteSnapshot['coin_discount'] as num? ?? 0) > 0)
              Text('Tổng đổi Xu: -${_money(quoteSnapshot['coin_discount'])}'),
            Text(
              'Tổng thanh toán: ${_money(quoteSnapshot['total'])}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || _loading ? null : _checkout,
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text('Đặt mua'),
            ),
          ],
        ],
      ],
    );
  }

  Widget _orders() {
    final orders = _rows(_data['orders']);
    final merchant = widget.view == MarketView.merchantOrders;
    const states = {
      'pending': 'Chờ cửa hàng xác nhận',
      'accepted': 'Đang chuẩn bị',
      'ready': 'Đã bàn giao vận chuyển',
      'cancelled': 'Đã hủy',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (orders.isEmpty && !_loading && _loaded)
          const Text('Chưa có đơn mua hàng.'),
        for (final o in orders)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${o['snapshot']['shop_name']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SelectableText('Đơn ${o['id']}'),
                Text(
                  o['state'] == 'ready'
                      ? cloudStatuses[o['delivery_status']] ??
                            (o['delivered_at'] != null
                                ? 'Đã giao'
                                : states['ready']!)
                      : states[o['state']] ?? '',
                ),
                for (final item in _rows(o['snapshot']['items']))
                  Text(
                    '${item['quantity']} × ${item['name']} · ${_money(item['unit_price'])}'
                    '${marketOptionNames(item['options']).isEmpty ? '' : '\n${marketOptionNames(item['options'])}'}',
                  ),
                Text(
                  'Tiền hàng: ${_money(o['snapshot']['subtotal'])} · Phí giao: ${_money(o['snapshot']['shipping_fee'])}',
                ),
                Text(
                  o['payment_status'] == 'PAID'
                      ? 'Đã ghi nhận thanh toán'
                      : o['payment_status'] == 'REVIEW'
                      ? 'Cần đối soát thanh toán'
                      : 'Chưa ghi nhận thanh toán',
                ),
                if (o['tracking_code'] != null)
                  SelectableText('Vận đơn: ${o['tracking_code']}'),
                if (_rows(o['shipments']).length > 1)
                  for (final s in _rows(o['shipments']))
                    SelectableText(
                      'Kiện #${s['parcel_no']}: ${s['tracking_code']} · ${cloudStatuses[s['status']] ?? s['status']}',
                    ),
                if ((o['reason'] as String? ?? '').isNotEmpty)
                  Text('Lý do: ${o['reason']}'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              await openMarketOrderServices(
                                context,
                                _session,
                                orderId: o['id'] as String,
                              );
                              if (_allowed) await _load();
                            },
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Chi tiết và hậu mãi'),
                    ),
                    if (!merchant &&
                        o['payment_method'] == 'prepaid' &&
                        o['payment_status'] != 'PAID' &&
                        o['purchase_id'] != null)
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                await showDialog<void>(
                                  context: context,
                                  builder: (_) => CloudSessionBoundary(
                                    session: _session,
                                    dialog: true,
                                    builder: (_, lease) => CloudCommerceDialog(
                                      service: _session.service,
                                      purchase: true,
                                      lease: lease,
                                      order: {
                                        'id': o['purchase_id'],
                                        'owner_id': o['owner_id'],
                                        'payment_method': 'prepaid',
                                        'payment_status': o['payment_status'],
                                        'total':
                                            ((o['snapshot']['payable_subtotal'] ??
                                                        o['snapshot']['subtotal'])
                                                    as num) +
                                            (o['snapshot']['shipping_fee']
                                                as num),
                                        'tracking_code': o['id'],
                                      },
                                    ),
                                  ),
                                );
                                if (_allowed) await _load();
                              },
                        icon: const Icon(Icons.payment),
                        label: const Text('Thanh toán trả trước'),
                      ),
                    if (merchant && o['state'] == 'pending')
                      FilledButton(
                        onPressed: _busy ? null : () => _action(o, 'accept'),
                        child: const Text('Xác nhận đơn'),
                      ),
                    if (merchant && o['state'] == 'accepted') ...[
                      FilledButton(
                        onPressed: _busy ? null : () => _action(o, 'ready'),
                        child: const Text('Sẵn sàng giao'),
                      ),
                      if (_session.canManageShop(o['shop_id'] as String?))
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final split =
                                      await showOrderShipmentSplitDialog(
                                        context,
                                        session: _session,
                                        order: o,
                                      );
                                  if (split == true && _allowed) {
                                    await _load();
                                  }
                                },
                          icon: const Icon(Icons.call_split),
                          label: const Text('Tách kiện giao'),
                        ),
                    ],
                    if (o['state'] == 'pending' ||
                        merchant && o['state'] == 'accepted')
                      OutlinedButton(
                        onPressed: _busy ? null : () => _action(o, 'cancel'),
                        child: const Text('Hủy đơn'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _conversation(o['id'] as String),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Trao đổi'),
                    ),
                  ],
                ),
                const Divider(),
              ],
            ),
          ),
      ],
    );
  }

  Widget _workspace() {
    final shops = _rows(_data['shops']), products = _rows(_data['products']);
    final moderation = widget.view == MarketView.moderation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shops.isEmpty && !_loading && _loaded)
          moderation
              ? const Text('Chưa có cửa hàng.')
              : _session.hasRole('merchant')
              ? FilledButton.icon(
                  onPressed: _busy ? null : () => _edit(editShop: true),
                  icon: const Icon(Icons.add_business),
                  label: const Text('Tạo cửa hàng'),
                )
              : const Text('Chưa có cửa hàng được phân quyền.'),
        for (final sh in shops) ...[
          Text('${sh['name']}', style: Theme.of(context).textTheme.titleLarge),
          Text('${sh['address']}'),
          Text(
            sh['status'] == 'pending'
                ? 'Chờ duyệt'
                : sh['status'] == 'suspended'
                ? 'Tạm khóa'
                : sh['paused'] == true
                ? 'Tạm nghỉ'
                : 'Đang hoạt động',
          ),
          Builder(
            builder: (context) {
              final canManage = _session.canManageShop(sh['id'] as String?);
              final isDirectOwner =
                  _session.hasRole('merchant') &&
                  (sh['owner_id'] == null ||
                      sh['owner_id'] == _session.service.userId);
              final shopProducts = products
                  .where((p) => p['shop_id'] == sh['id'])
                  .toList();
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (moderation)
                    for (final status in ['active', 'suspended'])
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await _session.service.market('shop_moderate', {
                                  'id': sh['id'],
                                  'version': sh['version'],
                                  'status': status,
                                });
                                if (_allowed) await _load();
                              }),
                        child: Text(
                          status == 'active' ? 'Duyệt hoạt động' : 'Tạm khóa',
                        ),
                      )
                  else ...[
                    OutlinedButton.icon(
                      onPressed: _busy || !canManage
                          ? null
                          : () => _edit(shop: sh, editShop: true),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Sửa cửa hàng'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          _busy || !canManage || sh['status'] == 'suspended'
                          ? null
                          : () => _edit(shop: sh),
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm sản phẩm'),
                    ),
                    if (canManage)
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final ok = await showVoucherEditorDialog(
                                  context,
                                  session: _session,
                                  shopId: '${sh['id']}',
                                );
                                if (ok == true && _allowed) await _load();
                              },
                        icon: const Icon(Icons.confirmation_num_outlined),
                        label: const Text('Voucher shop'),
                      ),
                    if (canManage && shopProducts.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final ok = await showFlashSaleEditorDialog(
                                  context,
                                  session: _session,
                                  products: shopProducts,
                                );
                                if (ok == true && _allowed) await _load();
                              },
                        icon: const Icon(Icons.flash_on_outlined),
                        label: const Text('Flash Sale'),
                      ),
                    if (isDirectOwner)
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                await showShopStaffDialog(
                                  context,
                                  session: _session,
                                  shop: sh,
                                  initialStaff: _rows(_data['staff']),
                                );
                                if (_allowed) await _load();
                              },
                        icon: const Icon(Icons.group_outlined),
                        label: const Text('Nhân sự'),
                      ),
                  ],
                ],
              );
            },
          ),
          const Divider(),
          if (!moderation)
            for (final p in products.where((p) => p['shop_id'] == sh['id']))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${p['name']}'),
                subtitle: Text(
                  '${p['sku']} · ${_money(p['price'])} · Còn ${p['stock']} · ${p['published'] == true ? 'Đang bán' : 'Đã ẩn'}',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Biến thể SKU',
                      onPressed:
                          _busy || !_session.canManageShop(sh['id'] as String?)
                          ? null
                          : () async {
                              await showMarketVariantsDialog(
                                context,
                                session: _session,
                                product: p,
                              );
                              if (_allowed) await _load();
                            },
                      icon: const Icon(Icons.layers_outlined),
                    ),
                    IconButton(
                      tooltip: 'Sửa sản phẩm',
                      onPressed:
                          _busy || !_session.canManageShop(sh['id'] as String?)
                          ? null
                          : () => _edit(shop: sh, product: p),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
              ),
        ],
        if (!moderation && _session.hasRole('merchant')) ...[
          const Divider(height: 32),
          Text(
            'Vận hành giao hàng',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => openCloudPickups(context, _session),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Lịch xe thu gom'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => openCloudOrderImport(context, _session),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Nhập đơn từ CSV'),
              ),
            ],
          ),
          CloudDeliveryStatsCard(service: _session.service, lease: _lease),
        ],
      ],
    );
  }

  Widget _notifications() {
    const kinds = {
      'new_order': 'Đơn mua mới',
      'accept': 'Cửa hàng đã xác nhận đơn',
      'ready': 'Đơn hàng đã sẵn sàng giao',
      'cancel': 'Đơn mua đã hủy',
      'message': 'Tin nhắn mới',
      'shop_reviewed': 'Đánh giá cửa hàng mới',
      'review_replied': 'Cửa hàng đã phản hồi đánh giá',
    };
    final notices = _rows(_data['notifications']);
    return Column(
      children: [
        if (notices.isEmpty && !_loading && _loaded)
          const Text('Chưa có thông báo.'),
        for (final n in notices)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              n['read_at'] == null
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_none,
            ),
            title: Text(kinds[n['kind']] ?? 'Cập nhật đơn hàng'),
            subtitle: Text('Đơn ${n['order_id']}'),
            onTap: _busy
                ? null
                : () => _run(() async {
                    final r = await _session.service.market(
                      'notification_read',
                      {'id': n['id']},
                    );
                    if (_allowed) {
                      setState(() {
                        final updated = _rows(r['notifications']);
                        _data = {
                          ..._data,
                          'notifications': [
                            for (final item in _rows(_data['notifications']))
                              updated
                                      .where((row) => row['id'] == item['id'])
                                      .firstOrNull ??
                                  item,
                          ],
                        };
                      });
                      final orderId = n['order_id'] as String?;
                      if (orderId != null) {
                        if (n['kind'] == 'message') {
                          await _conversation(orderId);
                        } else {
                          if (!mounted) return;
                          await openMarketOrderServices(
                            context,
                            _session,
                            orderId: orderId,
                          );
                        }
                        if (_allowed) await _load();
                      }
                    }
                  }),
          ),
      ],
    );
  }

  String _verifiedRoleSummary() {
    final labels = <String>[
      if (_session.isOperator) 'Quản trị viên',
      if (_session.hasRole('merchant'))
        'Đối tác Cửa hàng'
      else if (_session.hasStaffShop)
        'Nhân sự cửa hàng',
      if (_session.hasRole('driver')) 'Đối tác Tài xế',
      'Khách hàng',
    ];
    return 'Vai trò đã xác thực: ${labels.join(' · ')}';
  }

  Widget _account() {
    final phone = '${_session.account?['phone'] ?? ''}'.trim();
    final birthDate = formatIsoBirthDate(_session.birthDate);
    final citizenMasked = maskCitizenId(_session.citizenId);
    final verifiedKyc = _session.identityVerified;
    final identitySummary = <String>[
      if (phone.isNotEmpty) 'SĐT: $phone',
      'Ngày sinh: ${birthDate.isNotEmpty ? birthDate : 'Chưa cập nhật'}',
      'CCCD: ${citizenMasked.isNotEmpty ? citizenMasked : 'Chưa cập nhật'}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_session.account?['full_name']}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(_session.service.email),
        Text(
          identitySummary,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 2),
        Text(
          _verifiedRoleSummary(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_session.account?['requested_role'] != null)
          Text(
            'Chờ duyệt: ${cloudAccountRoles[_session.account!['requested_role']]}',
          ),
        const SizedBox(height: 8),
        if (_session.isOperator && widget.onOpenOperator != null)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('Cổng Quản trị'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onOpenOperator,
          ),
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            verifiedKyc ? Icons.verified_user_outlined : Icons.person_outline,
          ),
          title: const Text('Hồ sơ cá nhân'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CloudSessionBoundary(
                session: _session,
                profile: true,
                builder: (page, lease) => Scaffold(
                  appBar: AppBar(title: const Text('Hồ sơ cá nhân')),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: CloudProfileForm(
                        session: _session,
                        lease: lease,
                        onSaved: () => Navigator.pop(page),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: PushNotificationService.instance,
          builder: (context, _) {
            final unread = PushNotificationService.instance.unreadCount;
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              leading: Badge.count(
                count: unread,
                isLabelVisible: unread > 0,
                child: const Icon(Icons.notifications_none_rounded),
              ),
              title: const Text('Trung tâm thông báo'),
              subtitle: Text(
                unread > 0
                    ? '$unread thông báo chưa đọc'
                    : 'Lịch sử & tùy chỉnh cảnh báo',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => widget.onNavigate != null
                  ? widget.onNavigate!(MarketView.notifications)
                  : openCloudNotificationCenter(context, _session),
            );
          },
        ),
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.contact_mail_outlined),
          title: const Text('Sổ địa chỉ'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _addressesPage,
        ),
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.favorite_outline),
          title: const Text('Sản phẩm yêu thích'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              openMarketplaceView(context, _session, MarketView.favorites),
        ),
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.casino_outlined),
          title: const Text('Sự kiện & Vòng xoay may mắn'),
          subtitle: const Text('Điểm danh, Vòng xoay, Hộp mù & Đổi Xu'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => openCloudPromoEvents(
            context,
            _session,
            onOpenCatalog: () => widget.onNavigate != null
                ? widget.onNavigate!(MarketView.catalog)
                : openMarketplaceView(context, _session, MarketView.catalog),
          ),
        ),
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.monetization_on_outlined),
          title: const Text('Ví Xu thưởng'),
          subtitle: Text('${_session.coinBalance} Xu khả dụng'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showCoinWalletDialog(context, session: _session),
        ),
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.confirmation_num_outlined),
          title: const Text('Kho mã giảm giá'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showVoucherBrowserDialog(context, session: _session),
        ),
        if (PushNotificationService.supported)
          ListenableBuilder(
            listenable: PushNotificationService.instance,
            builder: (context, _) => SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('Thông báo đẩy thời gian thực'),
              value: PushNotificationService.instance.enabled,
              onChanged: _busy
                  ? null
                  : (enabled) => _run(() async {
                      if (enabled) {
                        await PushNotificationService.instance.enable((msg) {
                          if (mounted && _allowed) setState(() => _notice = msg);
                        });
                      } else {
                        await PushNotificationService.instance.disable(
                          clearRemotePreference: true,
                        );
                      }
                      if (mounted) setState(() {});
                    }),
            ),
          ),
      if (_session.schemaVersion >= 3)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.move_to_inbox_outlined),
          title: const Text('Nhập địa chỉ từ thiết bị'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CloudSessionBoundary(
                session: _session,
                builder: (_, lease) =>
                    CloudLocalImportScreen(session: _session, lease: lease),
              ),
            ),
          ),
        ),
      if (_session.hasMerchantAccess) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.storefront_outlined),
          title: const Text('Cửa hàng của tôi'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => widget.onNavigate != null
              ? widget.onNavigate!(MarketView.workspace)
              : openMarketplaceView(context, _session, MarketView.workspace),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.receipt_long_outlined),
          title: const Text('Đơn của cửa hàng'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => widget.onNavigate != null
              ? widget.onNavigate!(MarketView.merchantOrders)
              : openMarketplaceView(
                  context,
                  _session,
                  MarketView.merchantOrders,
                ),
        ),
      ],
      if (_session.hasRole('driver'))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delivery_dining),
          title: const Text('Chuyến giao của tôi'),
          trailing: const Icon(Icons.chevron_right),
          onTap:
              widget.onOpenShipping ??
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CloudSessionBoundary(
                    session: _session,
                    roles: const {'driver'},
                    builder: (_, lease) => CloudOrdersScreen(session: _session),
                  ),
                ),
              ),
        ),
      const Divider(),
      TextButton.icon(
        onPressed: () => _run(_session.service.signOut),
        icon: const Icon(Icons.logout),
        label: const Text('Đăng xuất'),
      ),
    ],
  );
  }

  @override
  Widget build(BuildContext context) {
    if (!_lease.valid) {
      return const Center(child: Text('Phiên làm việc đã thay đổi.'));
    }
    if (widget.view == MarketView.notifications) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: CloudNotificationCenter(
            session: _session,
            lease: _lease,
            embedded: true,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _busy
          ? Future<void>.value()
          : widget.view == MarketView.account
          ? _session.refresh()
          : _load(),
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
                    if (widget.showHeading)
                      Expanded(
                        child: Text(
                          _title(widget.view),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      )
                    else
                      const Spacer(),
                    if (widget.view != MarketView.account)
                      IconButton(
                        tooltip: 'Tải lại',
                        onPressed: _busy || _loading ? null : _load,
                        icon: const Icon(Icons.refresh),
                      ),
                  ],
                ),
                if (_loading || _busy) const LinearProgressIndicator(),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_notice!),
                  ),
                switch (widget.view) {
                  MarketView.catalog || MarketView.favorites => _catalog(),
                  MarketView.cart => _cartView(),
                  MarketView.orders || MarketView.merchantOrders => _orders(),
                  MarketView.notifications => _notifications(),
                  MarketView.account => _account(),
                  MarketView.workspace || MarketView.moderation => _workspace(),
                },
                if (_next != null)
                  TextButton(
                    onPressed: _busy || _loading
                        ? null
                        : () => _load(more: true),
                    child: const Text('Tải thêm'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderConversation extends StatefulWidget {
  const _OrderConversation({
    required this.session,
    required this.lease,
    required this.orderId,
  });
  final CloudAccountSession session;
  final CloudSessionLease lease;
  final String orderId;
  @override
  State<_OrderConversation> createState() => _OrderConversationState();
}

class _OrderConversationState extends State<_OrderConversation> {
  final _text = TextEditingController();
  final _attachments = <String>[];
  String _draft = const Uuid().v4();
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _next;
  bool _expanded = false;
  bool _busy = false;
  bool _loaded = false;
  String? _error;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    widget.lease.addListener(_invalidated);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_busy && !_expanded && ModalRoute.of(context)?.isCurrent != false) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    widget.lease.removeListener(_invalidated);
    _poll?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _invalidated() {
    if (mounted && !widget.lease.valid) {
      setState(() {
        _messages = [];
        _attachments.clear();
        _next = null;
        _loaded = false;
        _text.clear();
      });
    }
  }

  Future<void> _attach() async {
    if (_busy || !widget.lease.valid || _attachments.length >= 4) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = await pickAndUploadPrivateAttachment(
        session: widget.session,
        orderId: widget.orderId,
        scope: 'chat',
      );
      if (mounted && widget.lease.valid && name != null) {
        setState(() => _attachments.add(name));
      }
    } catch (e) {
      if (mounted && !widget.lease.handleAccessFailure(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa đính kèm được ảnh.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load({bool send = false, bool more = false}) async {
    if (_busy || !widget.lease.valid) return;
    setState(() => _busy = true);
    try {
      final bodyText = _text.text.trim();
      final response = send
          ? await widget.session.service.command('marketplace/message_send', {
              'order_id': widget.orderId,
              'body': bodyText.isEmpty && _attachments.isNotEmpty
                  ? 'Đã gửi ảnh đính kèm'
                  : bodyText,
              'draft_id': _draft,
              if (_attachments.isNotEmpty)
                'attachments': List<String>.from(_attachments),
            })
          : await widget.session.service.market('messages', {
              'order_id': widget.orderId,
              if (more && _next != null) ..._next!,
            });
      if (!mounted || !widget.lease.valid) return;
      setState(() {
        _loaded = true;
        _messages = more
            ? [..._rows(response['messages']), ..._messages]
            : _rows(response['messages']);
        _next = response['next'] == null
            ? null
            : Map<String, dynamic>.from(response['next'] as Map);
        _expanded = more;
        _error = null;
        if (send) {
          _text.clear();
          _attachments.clear();
          _draft = const Uuid().v4();
        }
      });
    } catch (e) {
      if (mounted && widget.lease.valid) {
        if (widget.lease.handleAccessFailure(e)) return;
        if (e is PublicApiException && e.statusCode == 404) {
          _messages = [];
          _next = null;
          _loaded = false;
          _text.clear();
        }
        setState(
          () => _error = e is PublicApiException && e.statusCode != 503
              ? e.message
              : 'Chưa tải được tin nhắn.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Trao đổi đơn hàng'),
      actions: [
        IconButton(
          tooltip: 'Tải lại tin nhắn',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_next != null)
                  TextButton(
                    onPressed: _busy ? null : () => _load(more: true),
                    child: const Text('Tin nhắn cũ hơn'),
                  ),
                if (_messages.isEmpty && !_busy && _loaded)
                  const Text('Chưa có tin nhắn.'),
                for (final msg in _messages)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${msg['body']}'),
                        subtitle: Text(
                          msg['actor_id'] == widget.session.service.userId
                              ? 'Bạn'
                              : 'Đối tác',
                        ),
                      ),
                      if (msg['attachments'] is List &&
                          (msg['attachments'] as List).isNotEmpty)
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final att in (msg['attachments'] as List))
                              ActionChip(
                                avatar: const Icon(
                                  Icons.image_outlined,
                                  size: 16,
                                ),
                                label: const Text('Xem ảnh đính kèm'),
                                onPressed: _busy
                                    ? null
                                    : () => openSignedPrivateAttachment(
                                        context,
                                        session: widget.session,
                                        name: '$att',
                                      ),
                              ),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
          if (_attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Đã chọn ${_attachments.length} ảnh đính kèm',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Đính kèm ảnh',
                  onPressed: _busy || _attachments.length >= 4 ? null : _attach,
                  icon: const Icon(Icons.attach_file),
                ),
                Expanded(
                  child: TextField(
                    controller: _text,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Tin nhắn'),
                  ),
                ),
                IconButton(
                  tooltip: 'Gửi tin nhắn',
                  onPressed: _busy
                      ? null
                      : () {
                          if (_text.text.trim().isNotEmpty ||
                              _attachments.isNotEmpty) {
                            _load(send: true);
                          }
                        },
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
