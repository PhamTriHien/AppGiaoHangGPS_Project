import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/market_options.dart';
import 'market_commercial_sheets.dart';

class MarketProductDetails extends StatefulWidget {
  const MarketProductDetails({
    super.key,
    required this.session,
    required this.lease,
    required this.productId,
  });
  final CloudAccountSession session;
  final CloudSessionLease lease;
  final String productId;
  @override
  State<MarketProductDetails> createState() => _MarketProductDetailsState();
}

class _MarketProductDetailsState extends State<MarketProductDetails> {
  Map<String, dynamic> _data = {};
  bool _busy = false;
  String? _error;
  String? _variantId;
  final _selected = <String, Set<String>>{};
  int _imageIndex = 0;
  bool get _valid => mounted && widget.lease.valid;
  @override
  void initState() {
    super.initState();
    widget.lease.addListener(_changed);
    _load();
  }

  void _changed() {
    if (!_valid && mounted) setState(() => _data = {});
  }

  @override
  void dispose() {
    widget.lease.removeListener(_changed);
    super.dispose();
  }

  Future<void> _load({bool favorite = false, bool followShop = false}) async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (favorite) {
        await widget.session.service.market('favorite_set', {
          'product_id': widget.productId,
          'enabled': _data['favorite'] != true,
        });
      }
      if (followShop && (_data['product'] as Map?)?['shop_id'] != null) {
        await widget.session.service.market('shop_follow_set', {
          'shop_id': (_data['product'] as Map)['shop_id'],
          'enabled': _data['shop_following'] != true,
        });
      }
      if (!_valid) return;
      final data = await widget.session.service.market('product_details', {
        'product_id': widget.productId,
      });
      if (_valid) {
        final variants = marketRows(data['variants']);
        setState(() {
          _data = data;
          if (variants.isNotEmpty &&
              !variants.any((v) => v['id'] == _variantId)) {
            _variantId = '${variants.first['id']}';
          }
        });
      }
    } catch (e) {
      if (_valid) {
        if (widget.lease.handleAccessFailure(e)) return;
        if (e is PublicApiException && e.statusCode == 404) {
          _data = {};
          _selected.clear();
        }
        setState(
          () => _error = e is PublicApiException && e.statusCode != 503
              ? e.message
              : 'Chưa tải được sản phẩm.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _data['product'] as Map?;
    final images = <String>{
      if (p?['image_url'] is String && (p!['image_url'] as String).isNotEmpty)
        p['image_url'] as String,
      ...((p?['images'] as List?) ?? []).whereType<String>(),
    }.toList();
    final variants = marketRows(_data['variants']);
    final selectedVariant = variants.isEmpty
        ? null
        : (variants.where((v) => '${v['id']}' == _variantId).firstOrNull ??
              variants.first);
    final flash = _data['flash_sale'] as Map?;
    final groups = marketRows(p?['option_groups']);
    final selection = <Map<String, String>>[];
    final basePrice =
        ((selectedVariant?['price'] ?? p?['price']) as num? ?? 0).toDouble();
    final flashPrice = (flash?['sale_price'] as num?)?.toDouble();
    final flashRemaining = flash == null
        ? 0
        : ((flash['allocated_stock'] as num? ?? 0) -
                  (flash['sold_stock'] as num? ?? 0))
              .toInt();
    var amount =
        flashPrice != null && flashRemaining > 0 && flashPrice < basePrice
        ? flashPrice
        : basePrice;
    final stock = ((selectedVariant?['stock'] ?? p?['stock']) as num? ?? 0)
        .toInt();
    var valid = true;
    for (final g in groups) {
      final choices = marketRows(g['options']);
      final chosen = (_selected[g['id']] ?? <String>{})
          .where((id) => choices.any((o) => o['id'] == id))
          .toSet();
      if (chosen.length < (g['min'] as int) ||
          chosen.length > (g['max'] as int)) {
        valid = false;
      }
      for (final option in choices) {
        if (chosen.contains(option['id'])) {
          amount += (option['price'] as num).toDouble();
          selection.add({
            'group_id': g['id'] as String,
            'option_id': option['id'] as String,
          });
        }
      }
    }
    return AlertDialog(
      title: Text(p?['name'] as String? ?? 'Sản phẩm'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) Text(_error!),
              if (p != null) ...[
                if (images.isNotEmpty)
                  SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: Image.network(
                      images[_imageIndex.clamp(0, images.length - 1)],
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                if (images.length > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Ảnh trước',
                        onPressed: _imageIndex > 0
                            ? () => setState(() => _imageIndex--)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text('${_imageIndex + 1} / ${images.length}'),
                      IconButton(
                        tooltip: 'Ảnh tiếp',
                        onPressed: _imageIndex + 1 < images.length
                            ? () => setState(() => _imageIndex++)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                if (flashPrice != null && flashRemaining > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    color: Colors.deepOrange.shade50,
                    child: Text(
                      'FLASH SALE: ${CurrencyFormatter.formatVnd(flashPrice)} · Còn $flashRemaining suất',
                      style: TextStyle(
                        color: Colors.deepOrange.shade800,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                Text('${p['description']}'),
                Text('Phân loại: ${selectedVariant?['sku'] ?? p['sku']}'),
                Text(
                  CurrencyFormatter.formatVnd(amount),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('Còn $stock'),
                if ((p['preparation_minutes'] as num? ?? 0) > 0)
                  Text('Chuẩn bị: ${p['preparation_minutes']} phút'),
                if (p['available'] == false)
                  const Text('Hiện chưa nhận đặt sản phẩm này.'),
                if (p['shop_id'] != null && _data.containsKey('shop_following'))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ActionChip(
                      avatar: Icon(
                        _data['shop_following'] == true
                            ? Icons.bookmark_added
                            : Icons.bookmark_add_outlined,
                        size: 18,
                      ),
                      label: Text(
                        '${_data['shop_following'] == true ? 'Đang theo dõi shop' : 'Theo dõi shop'}'
                        '${_data['shop_followers'] != null ? ' (${_data['shop_followers']})' : ''}',
                      ),
                      onPressed: _busy
                          ? null
                          : () => _load(followShop: true),
                    ),
                  ),
                if (variants.isNotEmpty) ...[
                  const Divider(),
                  Text(
                    'Chọn phân loại SKU',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in variants)
                        ChoiceChip(
                          label: Text(
                            '${v['title']} (${CurrencyFormatter.formatVnd((v['price'] as num).toDouble())})',
                          ),
                          selected: selectedVariant?['id'] == v['id'],
                          onSelected: _busy || (v['stock'] as num? ?? 0) <= 0
                              ? null
                              : (_) =>
                                    setState(() => _variantId = '${v['id']}'),
                        ),
                    ],
                  ),
                ],
                if (marketRows(_data['vouchers']).isNotEmpty) ...[
                  const Divider(),
                  Text(
                    'Mã giảm giá áp dụng',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final v in marketRows(_data['vouchers']))
                        Chip(
                          label: Text('${v['code']} · ${v['title']}'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
                for (final g in groups) ...[
                  const Divider(),
                  Text(
                    '${g['name']} (${g['min']}–${g['max']})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final option in marketRows(g['options']))
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text('${option['name']}'),
                      subtitle: Text(
                        '+${CurrencyFormatter.formatVnd((option['price'] as num).toDouble())}',
                      ),
                      value:
                          _selected[g['id']]?.contains(option['id']) ?? false,
                      onChanged: _busy
                          ? null
                          : (enabled) => setState(() {
                              final chosen = _selected.putIfAbsent(
                                g['id'] as String,
                                () => <String>{},
                              );
                              if (enabled != true) {
                                chosen.remove(option['id']);
                              } else if (g['max'] == 1) {
                                chosen
                                  ..clear()
                                  ..add(option['id'] as String);
                              } else if (chosen.length < (g['max'] as int)) {
                                chosen.add(option['id'] as String);
                              }
                            }),
                    ),
                ],
                const Divider(),
                Text(
                  'Đánh giá đã mua hàng',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if ((_data['reviews'] as List? ?? []).isEmpty)
                  const Text('Chưa có đánh giá.'),
                for (final rawRev in _data['reviews'] as List? ?? [])
                  Builder(
                    builder: (context) {
                      final r = Map<String, dynamic>.from(rawRev as Map);
                      final replyText = '${r['reply'] ?? ''}'.trim();
                      final reviewId = r['id'] as String?;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${r['rating']} / 5'),
                        subtitle: Text(
                          replyText.isEmpty
                              ? '${r['body']}'
                              : '${r['body']}\nPhản hồi từ cửa hàng: $replyText',
                        ),
                        trailing: reviewId == null
                            ? null
                            : Wrap(
                                children: [
                                  if (widget.session.canManageShop(
                                    p['shop_id'] as String?,
                                  ))
                                    IconButton(
                                      tooltip: 'Phản hồi đánh giá',
                                      icon: const Icon(
                                        Icons.reply_outlined,
                                        size: 18,
                                      ),
                                      onPressed: _busy
                                          ? null
                                          : () async {
                                              final ok =
                                                  await showReviewReplyOrReportDialog(
                                                    context,
                                                    session: widget.session,
                                                    reviewKind: 'product',
                                                    reviewId: reviewId,
                                                    reply: true,
                                                  );
                                              if (ok == true && _valid) {
                                                await _load();
                                              }
                                            },
                                    ),
                                  IconButton(
                                    tooltip: 'Báo cáo đánh giá',
                                    icon: const Icon(
                                      Icons.flag_outlined,
                                      size: 18,
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            await showReviewReplyOrReportDialog(
                                              context,
                                              session: widget.session,
                                              reviewKind: 'product',
                                              reviewId: reviewId,
                                              reply: false,
                                            );
                                          },
                                  ),
                                ],
                              ),
                      );
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
        if (p != null)
          IconButton(
            tooltip: _data['favorite'] == true ? 'Bỏ yêu thích' : 'Yêu thích',
            onPressed: _busy ? null : () => _load(favorite: true),
            icon: Icon(
              _data['favorite'] == true
                  ? Icons.favorite
                  : Icons.favorite_outline,
            ),
          ),
        if (p != null)
          FilledButton.icon(
            onPressed:
                _busy || stock <= 0 || p['available'] == false || !valid
                ? null
                : () {
                    if (_valid) {
                      Navigator.pop(context, {
                        ...Map<String, dynamic>.from(p),
                        'selected_options': selection,
                        if (selectedVariant != null)
                          'variant_id': selectedVariant['id'],
                      });
                    }
                  },
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Thêm vào giỏ'),
          ),
      ],
    );
  }
}
