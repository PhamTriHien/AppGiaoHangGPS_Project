import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/integrations/cloud_orders_service.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/utils/market_options.dart';
import 'market_catalog_fields.dart';

class MarketplaceEditor extends StatefulWidget {
  const MarketplaceEditor({
    super.key,
    required this.service,
    required this.lease,
    required this.shop,
    this.product,
    this.editShop = false,
  });
  final CloudOrdersService service;
  final CloudSessionLease lease;
  final Map<String, dynamic> shop;
  final Map<String, dynamic>? product;
  final bool editShop;
  @override
  State<MarketplaceEditor> createState() => _MarketplaceEditorState();
}

class _MarketplaceEditorState extends State<MarketplaceEditor> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  late final String _id = widget.product?['id'] as String? ?? const Uuid().v4();
  late bool _toggle = widget.editShop
      ? widget.shop['paused'] == true
      : widget.product?['published'] == true;
  bool _busy = false;
  String? _error;
  late final List<Map<String, dynamic>> _groups = marketRows(
    jsonDecode(jsonEncode(_original['option_groups'] ?? [])),
  );
  late final List<Map<String, dynamic>> _schedule = marketRows(
    jsonDecode(
      jsonEncode(
        _original[widget.editShop ? 'opening_schedule' : 'sale_schedule'] ?? [],
      ),
    ),
  );
  late final List<String> _images = <String>{
    if ((_original['image_url'] as String? ?? '').isNotEmpty)
      _original['image_url'] as String,
    ...((_original['images'] as List?) ?? []).whereType<String>(),
  }.toList();
  Map<String, dynamic> get _original =>
      widget.editShop ? widget.shop : widget.product ?? {};
  TextEditingController _field(String key) => _fields.putIfAbsent(
    key,
    () {
      if (key == 'image_url' && _images.isNotEmpty) {
        return TextEditingController(text: _images.first);
      }
      final raw = _original[key];
      if ([
            'service_radius_km',
            'length_cm',
            'width_cm',
            'height_cm',
          ].contains(key) &&
          raw is num &&
          raw <= 0) {
        return TextEditingController();
      }
      return TextEditingController(
        text: '${raw ?? (key == 'preparation_minutes' ? 0 : '')}',
      );
    },
  );
  String _text(String key) => _field(key).text.trim();

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _input(
    String key,
    String label, {
    int max = 160,
    bool number = false,
    bool optional = false, String? suffixText, String? helperText,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: _field(key),
      enabled: !_busy,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      maxLines: key == 'description' ? 3 : 1,
      decoration: InputDecoration(labelText: label, suffixText: suffixText, helperText: helperText),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (optional && text.isEmpty) return null;
        if (!optional && text.isEmpty) return 'Vui lòng nhập $label.';
        if (text.length > max) return 'Tối đa $max ký tự.';
        if (number && (num.tryParse(text)?.isFinite != true)) {
          return 'Nhập số hợp lệ.';
        }
        if (key == 'service_radius_km' && text.isNotEmpty) {
          final r = double.tryParse(text);
          if (r == null || r < 0 || r > 200) {
            return 'Bán kính phục vụ từ 0 đến 200 km.';
          }
        }
        if (['length_cm', 'width_cm', 'height_cm'].contains(key) &&
            text.isNotEmpty) {
          final d = double.tryParse(text);
          if (d == null || d < 0 || d > 300) {
            return 'Kích thước kiện từ 0 đến 300 cm.';
          }
        }
        if (['image_url', 'banner_url'].contains(key) &&
            text.isNotEmpty &&
            (Uri.tryParse(text)?.scheme != 'https' ||
                Uri.tryParse(text)?.host.isNotEmpty != true)) {
          return 'Nhập đường dẫn ảnh HTTPS.';
        }
        return null;
      },
    ),
  );

  Future<void> _save() async {
    if (_busy || !widget.lease.valid || !_form.currentState!.validate()) return;
    final Map<String, dynamic> payload;
    if (widget.editShop) {
      final lat = double.parse(_text('latitude')),
          lng = double.parse(_text('longitude'));
      if (lat < -90 ||
          lat > 90 ||
          lng < -180 ||
          lng > 180 ||
          _text('address').length < 5) {
        setState(() => _error = 'Địa chỉ hoặc tọa độ cửa hàng không hợp lệ.');
        return;
      }
      final banner = _text('banner_url');
      final radius = double.tryParse(_text('service_radius_km'));
      payload = {
        'name': _text('name'),
        'description': _text('description'),
        'address': _text('address'),
        'latitude': lat,
        'longitude': lng,
        'paused': _toggle,
        'opening_schedule': _schedule,
        if (banner.isNotEmpty) 'banner_url': banner,
        if (radius != null && radius > 0) 'service_radius_km': radius,
        if (widget.shop['version'] != null) 'version': widget.shop['version'],
      };
    } else {
      if (_groups.any(
        (g) =>
            (g['max'] as int) < 1 ||
            (g['min'] as int) > (g['max'] as int) ||
            (g['max'] as int) > (g['options'] as List).length,
      )) {
        setState(
          () =>
              _error = 'Kiểm tra số lựa chọn tối thiểu, tối đa của từng nhóm.',
        );
        return;
      }
      final preparation = int.tryParse(_text('preparation_minutes'));
      if (preparation == null || preparation < 0 || preparation > 1440) {
        setState(() => _error = 'Thời gian chuẩn bị từ 0 đến 1440 phút.');
        return;
      }
      final price = int.tryParse(_text('price')),
          stock = int.tryParse(_text('stock')),
          weight = double.tryParse(_text('weight_kg'));
      if (price == null ||
          price < 1 ||
          price > 10000000 ||
          stock == null ||
          stock < 0 ||
          stock > 1000000 ||
          weight == null ||
          weight < .01 ||
          weight > 30) {
        setState(
          () =>
              _error = 'Kiểm tra giá, tồn kho nguyên và khối lượng 0,01–30 kg.',
        );
        return;
      }
      final lengthCm = double.tryParse(_text('length_cm'));
      final widthCm = double.tryParse(_text('width_cm'));
      final heightCm = double.tryParse(_text('height_cm'));
      payload = {
        'id': _id,
        'shop_id': widget.shop['id'],
        'name': _text('name'),
        'description': _text('description'),
        'category': _text('category'),
        'sku': _text('sku'),
        'image_url': _text('image_url'),
        'images': _images,
        'option_groups': _groups,
        'sale_schedule': _schedule,
        'preparation_minutes': preparation,
        'price': price,
        'stock': stock,
        'weight_kg': weight,
        'published': _toggle,
        if (lengthCm != null && lengthCm > 0) 'length_cm': lengthCm,
        if (widthCm != null && widthCm > 0) 'width_cm': widthCm,
        if (heightCm != null && heightCm > 0) 'height_cm': heightCm,
        if (widget.product != null) 'version': widget.product!['version'],
      };
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.market(
        widget.editShop ? 'shop_save' : 'product_save',
        payload,
      );
      if (mounted && widget.lease.valid) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted && widget.lease.valid) {
        if (widget.lease.handleAccessFailure(e)) return;
        setState(
          () => _error = e is PublicApiException && e.statusCode != 503
              ? e.message
              : 'Chưa lưu được thay đổi. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload({bool banner = false}) async {
    if (_busy || !widget.lease.valid || (!banner && _images.length >= 8)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selected = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Ảnh cửa hàng / sản phẩm',
            extensions: ['jpg', 'jpeg', 'png', 'webp'],
            mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
          ),
        ],
      );
      if (!mounted || !widget.lease.valid || selected == null) return;
      if (await selected.length() > 5000000) {
        throw const PublicApiException('Chọn ảnh tối đa 5 MB.');
      }
      final bytes = await selected.readAsBytes();
      if (!mounted || !widget.lease.valid) return;
      final result = await widget.service.request(
        'media',
        body: {'shop_id': widget.shop['id'], 'image': base64Encode(bytes)},
      );
      if (!mounted || !widget.lease.valid) return;
      final url = result['image_url'];
      if (url is! String || Uri.tryParse(url)?.scheme != 'https') {
        throw const PublicApiException('Chưa nhận được ảnh đã lưu.');
      }
      setState(() {
        if (banner) {
          _field('banner_url').text = url;
        } else {
          if (!_images.contains(url)) _images.add(url);
          _field('image_url').text = _images.first;
        }
      });
    } catch (e) {
      if (mounted && widget.lease.valid) {
        if (widget.lease.handleAccessFailure(e)) return;
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa tải được ảnh. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.editShop
            ? 'Thông tin cửa hàng'
            : widget.product == null
            ? 'Thêm sản phẩm'
            : 'Sửa sản phẩm',
      ),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _input(
                    'name',
                    widget.editShop ? 'Tên cửa hàng' : 'Tên sản phẩm',
                    max: widget.editShop ? 120 : 160,
                  ),
                  _input(
                    'description',
                    'Mô tả',
                    max: widget.editShop ? 2000 : 4000,
                    optional: true,
                  ),
                  if (widget.editShop) ...[
                    _input('address', 'Địa chỉ lấy hàng', max: 500),
                    _input('latitude', 'Vĩ độ', number: true),
                    _input('longitude', 'Kinh độ', number: true),
                    _input(
                      'service_radius_km',
                      'Bán kính phục vụ tối đa', suffixText: 'km', helperText: 'Nhập 0 nếu không giới hạn',
                      number: true,
                      optional: true,
                    ),
                    _input(
                      'banner_url',
                      'Ảnh bìa cửa hàng',
                      max: 500,
                      optional: true,
                    ),
                    if (widget.shop['id'] != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _upload(banner: true),
                            icon: const Icon(Icons.panorama_outlined),
                            label: const Text('Tải ảnh bìa cửa hàng'),
                          ),
                        ),
                      ),
                  ] else ...[
                    _input('category', 'Danh mục', max: 80),
                    _input('sku', 'Mã SKU / phân loại', max: 80),
                    if (_text('image_url').isNotEmpty)
                      SizedBox(
                        height: 180,
                        child: Image.network(
                          _text('image_url'),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy || _images.length >= 8
                              ? null
                              : _upload,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Chọn ảnh'),
                        ),
                        if (_text('image_url').isNotEmpty)
                          IconButton(
                            tooltip: 'Bỏ ảnh',
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _images.remove(_text('image_url'));
                                    _field('image_url').text = _images.isEmpty
                                        ? ''
                                        : _images.first;
                                  }),
                            icon: const Icon(Icons.delete_outline),
                          ),
                      ],
                    ),
                    if (_images.length > 1)
                      SizedBox(
                        height: 80,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _images.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) => Tooltip(
                            message: 'Đặt ảnh chính',
                            child: InkWell(
                              onTap: _busy
                                  ? null
                                  : () => setState(() {
                                      final image = _images.removeAt(index);
                                      _images.insert(0, image);
                                      _field('image_url').text = image;
                                    }),
                              child: SizedBox(
                                width: 80,
                                child: Image.network(
                                  _images[index],
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    _input('price', 'Giá bán', number: true, suffixText: 'đ'),
                    _input('stock', 'Tồn khả dụng', number: true),
                    _input('weight_kg', 'Khối lượng', number: true, suffixText: 'kg'),
                    Row(
                      children: [
                        Expanded(
                          child: _input(
                            'length_cm',
                            'Dài', suffixText: 'cm',
                            number: true,
                            optional: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _input(
                            'width_cm',
                            'Rộng', suffixText: 'cm',
                            number: true,
                            optional: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _input(
                            'height_cm',
                            'Cao', suffixText: 'cm',
                            number: true,
                            optional: true,
                          ),
                        ),
                      ],
                    ),
                    _input(
                      'preparation_minutes',
                      'Thời gian chuẩn bị', suffixText: 'phút',
                      number: true,
                    ),
                    MarketOptionEditor(
                      groups: _groups,
                      enabled: !_busy,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 20),
                  ],
                  MarketScheduleEditor(
                    title: widget.editShop ? 'Giờ hoạt động' : 'Lịch bán',
                    slots: _schedule,
                    enabled: !_busy,
                    lease: widget.lease,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.editShop ? 'Tạm nghỉ' : 'Đang bán'),
                    value: _toggle,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _toggle = value),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_busy) const LinearProgressIndicator(),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Lưu'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
