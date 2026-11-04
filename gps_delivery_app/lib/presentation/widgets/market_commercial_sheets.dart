import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../../core/utils/currency_formatter.dart';
import 'cloud_order_labels.dart';
import 'cloud_session_boundary.dart';
import 'ghst_button_icon.dart';

String _vnd(dynamic v) =>
    CurrencyFormatter.formatVnd((v as num? ?? 0).toDouble());

List<Map<String, dynamic>> _mapRows(dynamic raw) => (raw as List? ?? const [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();

String _errText(Object e) => e is PublicApiException
    ? e.message
    : 'Không thực hiện được yêu cầu. Vui lòng thử lại.';

Future<String?> pickAndUploadPrivateAttachment({
  required CloudAccountSession session,
  required String orderId,
  required String scope,
}) async {
  final selected = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Ảnh đính kèm',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
        mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
      ),
    ],
  );
  if (selected == null) return null;
  if (await selected.length() > 5000000) {
    throw const PublicApiException('Chọn ảnh tối đa 5 MB.');
  }
  final bytes = await selected.readAsBytes();
  final res = await session.service.uploadAttachment(
    orderId: orderId,
    scope: scope,
    bytes: bytes,
  );
  final att = res['attachment'] as Map?;
  final name = att?['name'];
  if (name is! String || name.isEmpty) {
    throw const PublicApiException('Chưa nhận được mã tệp đính kèm.');
  }
  return name;
}

Future<void> openSignedPrivateAttachment(
  BuildContext context, {
  required CloudAccountSession session,
  required String name,
  bool operator = false,
}) async {
  final url = await session.service.signAttachment(name);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => CloudSessionBoundary(
      session: session,
      operator: operator,
      dialog: true,
      builder: (dialog, _) => AlertDialog(
        title: const Text('Tệp đính kèm bảo mật'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Center(child: Text('Không hiển thị được ảnh.')),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(dialog),
            icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

            label: const Text('Đóng'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showMarketVariantsDialog(
  BuildContext context, {
  required CloudAccountSession session,
  required Map<String, dynamic> product,
}) => showDialog<void>(
  context: context,
  builder: (_) => CloudSessionBoundary(
    session: session,
    roles: const {'merchant'},
    dialog: true,
    builder: (dialog, lease) => _VariantsDialog(
      session: session,
      lease: lease,
      product: product,
    ),
  ),
);

class _VariantsDialog extends StatefulWidget {
  const _VariantsDialog({
    required this.session,
    required this.lease,
    required this.product,
  });
  final CloudAccountSession session;
  final CloudSessionLease lease;
  final Map<String, dynamic> product;

  @override
  State<_VariantsDialog> createState() => _VariantsDialogState();
}

class _VariantsDialogState extends State<_VariantsDialog> {
  late List<Map<String, dynamic>> _variants = _mapRows(
    widget.product['variants'],
  );
  final _sku = TextEditingController();
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  final _weight = TextEditingController(text: '0.5');
  final _l = TextEditingController(text: '0');
  final _w = TextEditingController(text: '0');
  final _h = TextEditingController(text: '0');
  Map<String, dynamic>? _editing;
  bool _published = true, _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_sku, _title, _price, _stock, _weight, _l, _w, _h]) {
      c.dispose();
    }
    super.dispose();
  }

  void _selectForEdit(Map<String, dynamic>? v) {
    setState(() {
      _editing = v;
      _sku.text = '${v?['sku'] ?? ''}';
      _title.text = '${v?['title'] ?? ''}';
      _price.text = v == null ? '' : '${v['price']}';
      _stock.text = v == null ? '' : '${v['stock']}';
      _weight.text = '${v?['weight_kg'] ?? widget.product['weight_kg'] ?? 0.5}';
      _l.text = '${v?['length_cm'] ?? 0}';
      _w.text = '${v?['width_cm'] ?? 0}';
      _h.text = '${v?['height_cm'] ?? 0}';
      _published = v == null ? true : v['published'] == true;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_busy || !widget.lease.valid) return;
    final price = int.tryParse(_price.text.trim());
    final stock = int.tryParse(_stock.text.trim());
    final weight = double.tryParse(_weight.text.trim());
    final l = double.tryParse(_l.text.trim()) ?? 0;
    final w = double.tryParse(_w.text.trim()) ?? 0;
    final h = double.tryParse(_h.text.trim()) ?? 0;
    if (_sku.text.trim().isEmpty ||
        _title.text.trim().isEmpty ||
        price == null ||
        price < 1 ||
        stock == null ||
        stock < 0 ||
        weight == null ||
        weight <= 0 ||
        weight > 30) {
      setState(
        () => _error = 'Nhập đủ mã SKU, tên phân loại, giá, tồn và khối lượng.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.session.service.market('variant_save', {
        if (_editing != null) 'id': _editing!['id'],
        if (_editing != null) 'version': _editing!['version'],
        'product_id': widget.product['id'],
        'sku': _sku.text.trim(),
        'title': _title.text.trim(),
        'price': price,
        'stock': stock,
        'weight_kg': weight,
        'length_cm': l,
        'width_cm': w,
        'height_cm': h,
        'published': _published,
      });
      if (!mounted || !widget.lease.valid) return;
      final saved = Map<String, dynamic>.from(res['variant'] as Map);
      setState(() {
        final idx = _variants.indexWhere((e) => e['id'] == saved['id']);
        if (idx >= 0) {
          _variants[idx] = saved;
        } else {
          _variants = [..._variants, saved];
        }
      });
      _selectForEdit(null);
    } catch (e) {
      if (mounted && !widget.lease.handleAccessFailure(e)) {
        setState(() => _error = _errText(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Biến thể SKU · ${widget.product['name']}'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            for (final v in _variants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${v['title']} · ${v['sku']}'),
                subtitle: Text(
                  '${_vnd(v['price'])} · Tồn ${v['stock']} · ${v['weight_kg']} kg · ${v['published'] == true ? 'Đang bán' : 'Ẩn'}',
                ),
                trailing: IconButton(
                  tooltip: 'Sửa biến thể',
                  icon: const GhstButtonIcon(Icons.edit_outlined),
                  onPressed: _busy ? null : () => _selectForEdit(v),
                ),
              ),
            const Divider(),
            Text(
              _editing == null ? 'Thêm biến thể mới' : 'Cập nhật biến thể',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sku,
                    decoration: const InputDecoration(labelText: 'Mã SKU'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Tên biến thể', hintText: 'Size L',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Giá', suffixText: 'đ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _stock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Tồn kho'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _weight,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Khối lượng', suffixText: 'kg'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _l,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Dài', suffixText: 'cm'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _w,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Rộng', suffixText: 'cm'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _h,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cao', suffixText: 'cm'),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mở bán biến thể'),
              value: _published,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _published = v),
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const GhstButtonIcon(Icons.save_outlined),
                  label: Text(_editing == null ? 'Thêm SKU' : 'Lưu SKU'),
                ),
                if (_editing != null)
                  TextButton.icon(
                    onPressed: _busy ? null : () => _selectForEdit(null),
                    icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

                    label: const Text('Hủy sửa'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

        label: const Text('Đóng'),
      ),
    ],
  );
}

Future<void> showShopStaffDialog(
  BuildContext context, {
  required CloudAccountSession session,
  required Map<String, dynamic> shop,
  required List<Map<String, dynamic>> initialStaff,
}) => showDialog<void>(
  context: context,
  builder: (_) => CloudSessionBoundary(
    session: session,
    roles: const {'merchant'},
    dialog: true,
    builder: (_, lease) => _ShopStaffDialog(
      session: session,
      lease: lease,
      shop: shop,
      initialStaff: initialStaff,
    ),
  ),
);

class _ShopStaffDialog extends StatefulWidget {
  const _ShopStaffDialog({
    required this.session,
    required this.lease,
    required this.shop,
    required this.initialStaff,
  });
  final CloudAccountSession session;
  final CloudSessionLease lease;
  final Map<String, dynamic> shop;
  final List<Map<String, dynamic>> initialStaff;

  @override
  State<_ShopStaffDialog> createState() => _ShopStaffDialogState();
}

class _ShopStaffDialogState extends State<_ShopStaffDialog> {
  late List<Map<String, dynamic>> _staff = widget.initialStaff
      .where((s) => s['shop_id'] == widget.shop['id'])
      .toList();
  final _phoneOrId = TextEditingController();
  String _role = 'staff';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneOrId.dispose();
    super.dispose();
  }

  Future<void> _save({String? userId, String? role, bool active = true}) async {
    if (_busy || !widget.lease.valid) return;
    final raw = _phoneOrId.text.trim();
    final isUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(raw);
    if (userId == null &&
        !isUuid &&
        !RegExp(r'^0[35789][0-9]{8}$').hasMatch(raw)) {
      setState(() => _error = 'Nhập SĐT Việt Nam hoặc UUID nhân viên hợp lệ.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.session.service.market('staff_save', {
        'shop_id': widget.shop['id'],
        if (userId != null)
          'user_id': userId
        else if (isUuid)
          'user_id': raw
        else
          'phone': raw,
        'role': role ?? _role,
        'active': active,
      });
      if (!mounted || !widget.lease.valid) return;
      setState(() {
        _staff = _mapRows(res['staff']);
        if (userId == null) _phoneOrId.clear();
      });
    } catch (e) {
      if (mounted && !widget.lease.handleAccessFailure(e)) {
        setState(() => _error = _errText(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Nhân sự cửa hàng · ${widget.shop['name']}'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_staff.isEmpty)
              const Text('Chưa có nhân viên được phân quyền.'),
            for (final s in _staff)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${s['full_name']} · ${s['phone']}'),
                subtitle: Text(
                  s['role'] == 'manager'
                      ? 'Quản lý sản phẩm, kho & đơn hàng'
                      : 'Nhân viên xử lý đơn & tin nhắn',
                ),
                trailing: IconButton(
                  tooltip: 'Thu hồi quyền',
                  icon: const GhstButtonIcon(Icons.person_remove_outlined),
                  onPressed: _busy
                      ? null
                      : () => _save(
                          userId: '${s['user_id']}',
                          role: '${s['role']}',
                          active: false,
                        ),
                ),
              ),
            const Divider(),
            TextField(
              controller: _phoneOrId,
              decoration: const InputDecoration(
                labelText: 'Số điện thoại hoặc UUID tài khoản',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), initialValue: _role, isExpanded: true, decoration: const InputDecoration(labelText: 'Vai trò cửa hàng'), items: const [
                DropdownMenuItem(
                  value: 'staff',
                  child: Text('Nhân viên xử lý đơn'),
                ),
                DropdownMenuItem(
                  value: 'manager',
                  child: Text('Quản lý cửa hàng'),
                ),
              ], onChanged: _busy ? null : (v) => setState(() => _role = v!),),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : () => _save(),
              icon: const GhstButtonIcon(Icons.person_add_outlined),
              label: const Text('Cấp quyền nhân sự'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

        label: const Text('Đóng'),
      ),
    ],
  );
}

Future<bool?> showVoucherEditorDialog(
  BuildContext context, {
  required CloudAccountSession session,
  String? shopId,
  Map<String, dynamic>? voucher,
  bool operator = false,
}) => showDialog<bool>(
  context: context,
  builder: (_) => CloudSessionBoundary(
    session: session,
    operator: operator,
    roles: operator ? const {} : const {'merchant'},
    dialog: true,
    builder: (_, lease) => _VoucherEditorDialog(
      session: session,
      lease: lease,
      shopId: shopId,
      voucher: voucher,
    ),
  ),
);

class _VoucherEditorDialog extends StatefulWidget {
  const _VoucherEditorDialog({
    required this.session,
    required this.lease,
    this.shopId,
    this.voucher,
  });
  final CloudAccountSession session;
  final CloudSessionLease lease;
  final String? shopId;
  final Map<String, dynamic>? voucher;

  @override
  State<_VoucherEditorDialog> createState() => _VoucherEditorDialogState();
}

class _VoucherEditorDialogState extends State<_VoucherEditorDialog> {
  late final _code = TextEditingController(
    text: '${widget.voucher?['code'] ?? ''}',
  );
  late final _title = TextEditingController(
    text: '${widget.voucher?['title'] ?? ''}',
  );
  late final _val = TextEditingController(
    text: '${widget.voucher?['discount_value'] ?? 15000}',
  );
  late final _max = TextEditingController(
    text: '${widget.voucher?['max_discount'] ?? 15000}',
  );
  late final _min = TextEditingController(
    text: '${widget.voucher?['min_subtotal'] ?? 50000}',
  );
  late final _budget = TextEditingController(
    text: '${widget.voucher?['budget_total'] ?? 500000}',
  );
  late final _limit = TextEditingController(
    text: '${widget.voucher?['per_user_limit'] ?? 1}',
  );
  late final _hours = TextEditingController(text: '72');
  late String _kind = '${widget.voucher?['discount_kind'] ?? 'fixed'}';
  late bool _active = widget.voucher == null
      ? true
      : widget.voucher!['active'] == true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _title, _val, _max, _min, _budget, _limit, _hours]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !widget.lease.valid) return;
    final val = int.tryParse(_val.text.trim());
    final max = int.tryParse(_max.text.trim());
    final min = int.tryParse(_min.text.trim()) ?? 0;
    final budget = int.tryParse(_budget.text.trim());
    final limit = int.tryParse(_limit.text.trim()) ?? 1;
    final hours = int.tryParse(_hours.text.trim()) ?? 72;
    if (!RegExp(r'^[A-Za-z0-9_-]{3,32}$').hasMatch(_code.text.trim()) ||
        _title.text.trim().isEmpty ||
        val == null ||
        val < 1 ||
        max == null ||
        max < 1 ||
        budget == null ||
        budget < max ||
        hours < 1) {
      setState(
        () => _error =
            'Kiểm tra mã 3-32 ký tự chữ/số, mức giảm và tổng ngân sách.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final now = DateTime.now().toUtc();
      await widget.session.service.market('voucher_save', {
        if (widget.voucher != null) 'id': widget.voucher!['id'],
        if (widget.voucher != null) 'version': widget.voucher!['version'],
        if (widget.shopId != null) 'shop_id': widget.shopId,
        'code': _code.text.trim().toUpperCase(),
        'title': _title.text.trim(),
        'discount_kind': _kind,
        'discount_value': val,
        'max_discount': max,
        'min_subtotal': min,
        'budget_total': budget,
        'per_user_limit': limit,
        'starts_at':
            widget.voucher?['starts_at'] ??
            now.subtract(const Duration(minutes: 1)).toIso8601String(),
        'ends_at':
            widget.voucher?['ends_at'] ??
            now.add(Duration(hours: hours)).toIso8601String(),
        'active': _active,
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.shopId == null ? 'Voucher toàn sàn' : 'Voucher cửa hàng',
    ),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            TextField(
              controller: _code,
              enabled: widget.voucher == null && !_busy,
              decoration: const InputDecoration(labelText: 'Mã voucher'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Tên chương trình'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), initialValue: _kind, isExpanded: true, decoration: const InputDecoration(labelText: 'Loại giảm giá'), items: const [
                DropdownMenuItem(value: 'fixed', child: Text('Số tiền cố định')),
                DropdownMenuItem(value: 'percent', child: Text('Theo %')),
              ], onChanged: _busy ? null : (v) => setState(() => _kind = v!),),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _val,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _kind == 'percent' ? 'Mức giảm' : 'Số tiền giảm', suffixText: _kind == 'percent' ? '%' : 'đ',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _max,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Giảm tối đa', suffixText: 'đ',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _min,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Đơn tối thiểu', suffixText: 'đ',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _budget,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Ngân sách', suffixText: 'đ',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _limit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Lượt / khách',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.voucher == null)
                  Expanded(
                    child: TextField(
                      controller: _hours,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Hiệu lực', suffixText: 'giờ',
                      ),
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Đang kích hoạt'),
              value: _active,
              onChanged: _busy ? null : (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

        label: const Text('Hủy'),
      ),
      FilledButton.icon(
        onPressed: _busy ? null : _save,
        icon: const GhstButtonIcon.glyph(GhstActionKind.save, size: 16),

        label: const Text('Lưu voucher'),
      ),
    ],
  );
}

Future<bool?> showFlashSaleEditorDialog(
  BuildContext context, {
  required CloudAccountSession session,
  required List<Map<String, dynamic>> products,
  Map<String, dynamic>? flashSale,
  bool operator = false,
}) => showDialog<bool>(
  context: context,
  builder: (_) => CloudSessionBoundary(
    session: session,
    operator: operator,
    roles: operator ? const {} : const {'merchant'},
    dialog: true,
    builder: (_, lease) => _FlashSaleDialog(
      session: session,
      lease: lease,
      products: products,
      flashSale: flashSale,
    ),
  ),
);

class _FlashSaleDialog extends StatefulWidget {
  const _FlashSaleDialog({
    required this.session,
    required this.lease,
    required this.products,
    this.flashSale,
  });
  final CloudAccountSession session;
  final CloudSessionLease lease;
  final List<Map<String, dynamic>> products;
  final Map<String, dynamic>? flashSale;

  @override
  State<_FlashSaleDialog> createState() => _FlashSaleDialogState();
}

class _FlashSaleDialogState extends State<_FlashSaleDialog> {
  late String? _productId =
      widget.flashSale?['product_id'] as String? ??
      widget.products.firstOrNull?['id'] as String?;
  late final _price = TextEditingController(
    text: '${widget.flashSale?['sale_price'] ?? ''}',
  );
  late final _stock = TextEditingController(
    text: '${widget.flashSale?['allocated_stock'] ?? 10}',
  );
  late final _limit = TextEditingController(
    text: '${widget.flashSale?['per_user_limit'] ?? 2}',
  );
  late final _hours = TextEditingController(text: '24');
  late bool _active = widget.flashSale == null
      ? true
      : widget.flashSale!['active'] == true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_price, _stock, _limit, _hours]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !widget.lease.valid || _productId == null) return;
    final price = int.tryParse(_price.text.trim());
    final stock = int.tryParse(_stock.text.trim());
    final limit = int.tryParse(_limit.text.trim()) ?? 2;
    final hours = int.tryParse(_hours.text.trim()) ?? 24;
    if (price == null || price < 1 || stock == null || stock < 1 || hours < 1) {
      setState(() => _error = 'Nhập giá Flash Sale và số suất hợp lệ.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final now = DateTime.now().toUtc();
      await widget.session.service.market('flash_sale_save', {
        if (widget.flashSale != null) 'id': widget.flashSale!['id'],
        if (widget.flashSale != null) 'version': widget.flashSale!['version'],
        'product_id': _productId,
        'sale_price': price,
        'allocated_stock': stock,
        'per_user_limit': limit,
        'starts_at':
            widget.flashSale?['starts_at'] ??
            now.subtract(const Duration(minutes: 1)).toIso8601String(),
        'ends_at':
            widget.flashSale?['ends_at'] ??
            now.add(Duration(hours: hours)).toIso8601String(),
        'active': _active,
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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Chương trình Flash Sale'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (widget.products.isNotEmpty)
              DropdownButtonFormField<String>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), initialValue: _productId, isExpanded: true, decoration: const InputDecoration(labelText: 'Sản phẩm'), items: widget.products
                    .map(
                      (p) => DropdownMenuItem(
                        value: '${p['id']}',
                        child: Text(
                          '${p['name']} · ${_vnd(p['price'])}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(), onChanged: _busy || widget.flashSale != null
                    ? null
                    : (v) => setState(() => _productId = v),),
            const SizedBox(height: 8),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Giá Flash Sale', suffixText: 'đ',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _stock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Số suất bán'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _limit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Giới hạn / khách',
                    ),
                  ),
                ),
              ],
            ),
            if (widget.flashSale == null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _hours,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Thời lượng', suffixText: 'giờ',
                ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Đang mở Flash Sale'),
              value: _active,
              onChanged: _busy ? null : (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

        label: const Text('Hủy'),
      ),
      FilledButton.icon(
        onPressed: _busy || _productId == null ? null : _save,
        icon: const GhstButtonIcon.glyph(GhstActionKind.save, size: 16),

        label: const Text('Lưu Flash Sale'),
      ),
    ],
  );
}

Future<String?> showVoucherBrowserDialog(
  BuildContext context, {
  required CloudAccountSession session,
  String? shopId,
}) => showDialog<String>(
  context: context,
  builder: (_) => CloudSessionBoundary(
    session: session,
    dialog: true,
    builder: (_, lease) =>
        _VoucherBrowserDialog(session: session, lease: lease, shopId: shopId),
  ),
);

class _VoucherBrowserDialog extends StatefulWidget {
  const _VoucherBrowserDialog({
    required this.session,
    required this.lease,
    this.shopId,
  });
  final CloudAccountSession session;
  final CloudSessionLease lease;
  final String? shopId;

  @override
  State<_VoucherBrowserDialog> createState() => _VoucherBrowserDialogState();
}

class _VoucherBrowserDialogState extends State<_VoucherBrowserDialog> {
  List<Map<String, dynamic>> _vouchers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.session.service.market('vouchers', {
        if (widget.shopId != null) 'shop_id': widget.shopId,
      });
      if (mounted && widget.lease.valid) {
        setState(() {
          _vouchers = _mapRows(res['vouchers']);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && !widget.lease.handleAccessFailure(e)) {
        setState(() {
          _error = _errText(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Kho mã giảm giá khả dụng'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (!_loading && _vouchers.isEmpty && _error == null)
              const Text('Hiện chưa có mã giảm giá đang mở.'),
            for (final v in _vouchers)
              Card(
                child: ListTile(
                  title: Text('${v['code']}${v['personal'] == true ? ' [Cá nhân]' : ''} · ${v['title']}'),
                  subtitle: Text(
                    '${v['discount_kind'] == 'percent' ? 'Giảm ${v['discount_value']}% tối đa ${_vnd(v['max_discount'])}' : 'Giảm ${_vnd(v['discount_value'])}'
                    } · Đơn từ ${_vnd(v['min_subtotal'])} · Ngân sách còn ${_vnd(v['remaining_budget'])}',
                  ),
                  trailing: FilledButton.tonalIcon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: '${v['code']}'),
                      ).ignore();
                      Navigator.pop(context, '${v['code']}');
                    },
                    icon: const GhstButtonIcon.glyph(GhstActionKind.voucher, size: 16),

                    label: const Text('Dùng'),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

        label: const Text('Đóng'),
      ),
    ],
  );
}

Future<void> showCoinWalletDialog(
  BuildContext context, {
  required CloudAccountSession session,
}) => showDialog<void>(
  context: context,
  builder: (_) => CloudSessionBoundary(
    session: session,
    dialog: true,
    builder: (_, lease) => _CoinWalletDialog(session: session, lease: lease),
  ),
);

class _CoinWalletDialog extends StatefulWidget {
  const _CoinWalletDialog({required this.session, required this.lease});
  final CloudAccountSession session;
  final CloudSessionLease lease;

  @override
  State<_CoinWalletDialog> createState() => _CoinWalletDialogState();
}

class _CoinWalletDialogState extends State<_CoinWalletDialog> {
  int _balance = 0;
  List<Map<String, dynamic>> _ledger = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.session.service.market('coins');
      if (mounted && widget.lease.valid) {
        setState(() {
          _balance = (res['balance'] as num? ?? 0).toInt();
          _ledger = _mapRows(res['ledger']);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && !widget.lease.handleAccessFailure(e)) {
        setState(() {
          _error = _errText(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const kinds = {
      'earn_settlement': 'Tích xu 1% sau đối soát',
      'earn_shipping': 'Tích Xu 1% đơn giao hoàn tất',
      'redeem_checkout': 'Đổi xu thanh toán đơn hàng',
      'redeem_shipping': 'Đổi Xu giảm cước giao hàng',
      'release_cancel': 'Hoàn xu do hủy đơn',
      'release_shipping_cancel': 'Hoàn Xu do hủy đơn giao hàng',
      'reverse_cancel': 'Hoàn xu do hủy đơn',
      'reverse_refund': 'Thu hồi xu khi hoàn tiền',
      'promo_checkin': 'Thưởng điểm danh sự kiện hàng ngày',
      'promo_spin': 'Trúng thưởng Vòng xoay may mắn',
      'promo_blind_box': 'Khui thưởng Hộp mù bí ẩn',
      'promo_mission': 'Thưởng nhiệm vụ đơn hàng',
      'promo_exchange': 'Đổi Xu lấy vé / Voucher sự kiện',
    };
    return AlertDialog(
      title: const Text('Ví Xu thưởng GHST'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) Text(_error!),
              Text(
                'Số dư hiện tại: $_balance Xu · Tương đương ${_vnd(_balance)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Tích 1% khi đơn hoàn tất, đổi tối đa 20% cước phí giao hàng hoặc đơn mua sắm.',
              ),
              const Divider(height: 24),
              if (!_loading && _ledger.isEmpty)
                const Text('Chưa có biến động xu.'),
              for (final row in _ledger)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(kinds[row['kind']] ?? '${row['kind']}'),
                  subtitle: Text(cloudDate(row['created_at'])),
                  trailing: Text(
                    '${(row['delta'] as num) > 0 ? '+' : ''}${row['delta']} Xu',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: (row['delta'] as num) > 0
                          ? GhstThemeTokens.of(context).emerald.foreground
                          : GhstThemeTokens.of(context).rose.foreground,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

          label: const Text('Đóng'),
        ),
      ],
    );
  }
}

Future<bool?> showOrderShipmentSplitDialog(
  BuildContext context, {
  required CloudAccountSession session,
  required Map<String, dynamic> order,
}) => showDialog<bool>(
  context: context,
  builder: (_) => CloudSessionBoundary(
    session: session,
    roles: const {'merchant'},
    dialog: true,
    builder: (_, lease) =>
        _SplitShipmentDialog(session: session, lease: lease, order: order),
  ),
);

class _SplitShipmentDialog extends StatefulWidget {
  const _SplitShipmentDialog({
    required this.session,
    required this.lease,
    required this.order,
  });
  final CloudAccountSession session;
  final CloudSessionLease lease;
  final Map<String, dynamic> order;

  @override
  State<_SplitShipmentDialog> createState() => _SplitShipmentDialogState();
}

class _SplitShipmentDialogState extends State<_SplitShipmentDialog> {
  late final int _expectedCod = widget.order['payment_method'] == 'prepaid'
      ? 0
      : ((widget.order['snapshot']['payable_subtotal'] ??
                    widget.order['snapshot']['subtotal'])
                as num)
            .toInt();
  late final List<(TextEditingController, TextEditingController)> _rows = [
    (
      TextEditingController(text: '0.5'),
      TextEditingController(text: '$_expectedCod'),
    ),
    (TextEditingController(text: '0.5'), TextEditingController(text: '0')),
  ];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final r in _rows) {
      r.$1.dispose();
      r.$2.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !widget.lease.valid) return;
    final parcels = <Map<String, dynamic>>[];
    var sumCod = 0;
    for (final r in _rows) {
      final w = double.tryParse(r.$1.text.trim());
      final cod = int.tryParse(r.$2.text.trim());
      if (w == null || w <= 0 || w > 500 || cod == null || cod < 0) {
        setState(() => _error = 'Khối lượng và COD mỗi kiện phải hợp lệ.');
        return;
      }
      sumCod += cod;
      parcels.add({'weight_kg': w, 'cod_amount': cod});
    }
    if (sumCod != _expectedCod) {
      setState(
        () => _error =
            'Tổng COD các kiện ${_vnd(sumCod)} phải khớp ${_vnd(_expectedCod)}.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.service.market('order_shipment_split', {
        'order_id': widget.order['id'],
        'version': widget.order['version'],
        'parcels': parcels,
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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tách kiện vận chuyển'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            Text('Tổng COD cần phân bổ: ${_vnd(_expectedCod)}'),
            const SizedBox(height: 10),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            for (var i = 0; i < _rows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Text('Kiện ${i + 1}: '),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _rows[i].$1,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Kg'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _rows[i].$2,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'COD', suffixText: 'đ'),
                      ),
                    ),
                    if (_rows.length > 2)
                      IconButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                final removed = _rows.removeAt(i);
                                removed.$1.dispose();
                                removed.$2.dispose();
                              }),
                        icon: const GhstButtonIcon(Icons.remove_circle_outline),
                      ),
                  ],
                ),
              ),
            if (_rows.length < 10)
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(
                        () => _rows.add((
                          TextEditingController(text: '0.5'),
                          TextEditingController(text: '0'),
                        )),
                      ),
                icon: const GhstButtonIcon(Icons.add),
                label: const Text('Thêm kiện'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

        label: const Text('Hủy'),
      ),
      FilledButton.icon(
        onPressed: _busy ? null : _submit,
        icon: const GhstButtonIcon.glyph(GhstActionKind.plus, size: 16),

        label: const Text('Tạo vận đơn tách kiện'),
      ),
    ],
  );
}

Future<bool?> showPartnerReviewDialog(
  BuildContext context, {
  required CloudAccountSession session,
  required String targetKind,
  String? orderId,
  String? cloudOrderId,
}) async {
  var rating = 5;
  final body = TextEditingController();
  String? error;
  var busy = false;
  try {
    return await showDialog<bool>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: session,
        dialog: true,
        builder: (dialog, lease) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              targetKind == 'shop' ? 'Đánh giá cửa hàng' : 'Đánh giá tài xế',
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy) const LinearProgressIndicator(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 1; i <= 5; i++)
                        IconButton(
                          tooltip: '$i sao',
                          onPressed: busy
                              ? null
                              : () => update(() => rating = i),
                          icon: GhstButtonIcon(
                            i <= rating ? Icons.star : Icons.star_border,
                          ),
                        ),
                    ],
                  ),
                  TextField(
                    controller: body,
                    maxLength: 2000,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Nhận xét chất lượng phục vụ',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(dialog),
                icon: const GhstButtonIcon.glyph(GhstActionKind.back, size: 16),

                label: const Text('Quay lại'),
              ),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        if (body.text.trim().length < 3) {
                          update(() => error = 'Nhập ít nhất 3 ký tự.');
                          return;
                        }
                        update(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await session.service.market('partner_review_save', {
                            'target_kind': targetKind,
                            'order_id': ?orderId,
                            'cloud_order_id': ?cloudOrderId,
                            'rating': rating,
                            'body': body.text.trim(),
                          });
                          if (dialog.mounted && lease.valid) {
                            Navigator.pop(dialog, true);
                          }
                        } catch (e) {
                          if (dialog.mounted && !lease.handleAccessFailure(e)) {
                            update(() {
                              busy = false;
                              error = _errText(e);
                            });
                          }
                        }
                      },
                icon: const GhstButtonIcon.glyph(GhstActionKind.send, size: 16),

                label: const Text('Gửi đánh giá'),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    Future<void>.delayed(const Duration(seconds: 1), body.dispose);
  }
}

Future<bool?> showReviewReplyOrReportDialog(
  BuildContext context, {
  required CloudAccountSession session,
  required String reviewKind,
  required String reviewId,
  required bool reply,
}) async {
  final ctrl = TextEditingController();
  String? error;
  var busy = false;
  try {
    return await showDialog<bool>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: session,
        dialog: true,
        builder: (dialog, lease) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(reply ? 'Phản hồi đánh giá' : 'Báo cáo đánh giá'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy) const LinearProgressIndicator(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  TextField(
                    controller: ctrl,
                    maxLength: reply ? 1000 : 500,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: reply ? 'Nội dung phản hồi' : 'Lý do báo cáo',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(dialog),
                icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

                label: const Text('Hủy'),
              ),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        if (ctrl.text.trim().length < 3) {
                          update(() => error = 'Nhập ít nhất 3 ký tự.');
                          return;
                        }
                        update(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await session.service.market(
                            reply ? 'review_reply' : 'review_report',
                            {
                              'review_kind': reviewKind,
                              'id': reviewId,
                              reply ? 'reply' : 'reason': ctrl.text.trim(),
                            },
                          );
                          if (dialog.mounted && lease.valid) {
                            Navigator.pop(dialog, true);
                          }
                        } catch (e) {
                          if (dialog.mounted && !lease.handleAccessFailure(e)) {
                            update(() {
                              busy = false;
                              error = _errText(e);
                            });
                          }
                        }
                      },
                icon: GhstButtonIcon.forLabel(reply ? 'Gửi phản hồi' : 'Gửi báo cáo', size: 16),

                label: Text(reply ? 'Gửi phản hồi' : 'Gửi báo cáo'),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    Future<void>.delayed(const Duration(seconds: 1), ctrl.dispose);
  }
}
