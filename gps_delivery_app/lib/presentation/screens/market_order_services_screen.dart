import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/market_options.dart';
import '../widgets/cloud_order_labels.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/market_commercial_sheets.dart';

List<Map<String, dynamic>> _rows(dynamic value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
String _money(dynamic value) =>
    CurrencyFormatter.formatVnd((value as num? ?? 0).toDouble());
const _states = {
  'requested': 'Chờ duyệt',
  'approved': 'Đã duyệt',
  'rejected': 'Từ chối',
  'escalated': 'Chờ giải quyết tranh chấp',
  'received': 'Đã nhận hàng trả',
  'completed': 'Đã xác nhận thu/chi',
};
const _kinds = {
  'collection': 'Thu COD',
  'refund': 'Hoàn tiền',
  'settlement': 'Trả tiền shop',
};

Future<void> openMarketOrderServices(
  BuildContext context,
  CloudAccountSession session, {
  String? orderId,
  bool operator = false,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CloudSessionBoundary(
      session: session,
      operator: operator,
      builder: (_, lease) => MarketOrderServicesScreen(
        session: session,
        lease: lease,
        orderId: orderId,
        operator: operator,
      ),
    ),
  ),
);

class MarketOrderServicesScreen extends StatefulWidget {
  const MarketOrderServicesScreen({
    super.key,
    required this.session,
    required this.lease,
    this.orderId,
    this.operator = false,
  });
  final CloudAccountSession session;
  final CloudSessionLease lease;
  final String? orderId;
  final bool operator;
  @override
  State<MarketOrderServicesScreen> createState() =>
      _MarketOrderServicesScreenState();
}

class _MarketOrderServicesScreenState extends State<MarketOrderServicesScreen> {
  final _lookup = TextEditingController();
  Map<String, dynamic> _data = {};
  bool _busy = false;
  String? _error, _notice;
  String? get _orderId => widget.orderId;
  bool get _valid => mounted && widget.lease.valid;
  bool get _buyer =>
      (_data['order'] as Map?)?['owner_id'] == widget.session.service.userId;
  bool get _merchant {
    final order = _data['order'] as Map?;
    if (order == null) return false;
    return (order['merchant_id'] == widget.session.service.userId &&
            widget.session.hasRole('merchant')) ||
        widget.session.isStaffOfShop(order['shop_id'] as String?);
  }

  @override
  void initState() {
    super.initState();
    widget.lease.addListener(_invalidated);
    _reload();
  }

  void _invalidated() {
    if (mounted && !widget.lease.valid) {
      setState(() {
        _data = {};
        _error = _notice = null;
        _lookup.clear();
      });
    }
  }

  @override
  void dispose() {
    widget.lease.removeListener(_invalidated);
    _lookup.dispose();
    super.dispose();
  }

  Future<void> _load({String? more}) async {
    if (!_valid) return;
    final data = await widget.session.service.market(
      _orderId == null ? 'operations' : 'order_services',
      {
        if (_orderId != null) 'order_id': _orderId,
        if (more != null &&
            _data[more == 'finance' ? 'next' : 'returns_next'] is Map)
          ...Map<String, dynamic>.from(
            _data[more == 'finance' ? 'next' : 'returns_next'] as Map,
          ),
      },
    );
    if (_valid) {
      setState(() {
        if (more == null) {
          _data = data;
        } else {
          _data[more] = [..._rows(_data[more]), ..._rows(data[more])];
          final cursor = more == 'finance' ? 'next' : 'returns_next';
          _data[cursor] = data[cursor];
        }
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !_valid) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (e) {
      if (_valid) {
        Object shown = e;
        if (e is PublicApiException && e.statusCode == 409) {
          try {
            await _load();
          } catch (refreshError) {
            shown = refreshError;
          }
        }
        if (!_valid || widget.lease.handleAccessFailure(shown)) return;
        if (shown is PublicApiException && shown.statusCode == 404) _data = {};
        setState(
          () => _error = shown is PublicApiException && shown.statusCode != 503
              ? shown.message
              : 'Chưa xử lý được yêu cầu. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() => _run(_load);

  Future<Map<String, String>?> _form(
    String title,
    Map<String, String> fields, {
    Map<String, String> initial = const {},
  }) async {
    final controllers = {
      for (final key in fields.keys)
        key: TextEditingController(text: initial[key] ?? ''),
    };
    final form = GlobalKey<FormState>();
    try {
      return await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: widget.session,
          dialog: true,
          operator: widget.operator,
          builder: (dialog, lease) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 440,
              child: Form(
                key: form,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in fields.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: TextFormField(
                            controller: controllers[entry.key],
                            decoration: InputDecoration(labelText: entry.value),
                            keyboardType:
                                ['quantity', 'amount'].contains(entry.key)
                                ? TextInputType.number
                                : TextInputType.text,
                            maxLength: entry.key == 'evidence' ? 500 : 1000,
                            validator: (value) {
                              final v = value?.trim() ?? '';
                              if (['quantity', 'amount'].contains(entry.key)) {
                                return (int.tryParse(v) ?? 0) > 0
                                    ? null
                                    : 'Nhập số nguyên lớn hơn 0';
                              }
                              return v.length >= 3
                                  ? null
                                  : 'Nhập ít nhất 3 ký tự';
                            },
                          ),
                        ),
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
                onPressed: () {
                  if (lease.valid && form.currentState!.validate()) {
                    Navigator.pop(dialog, {
                      for (final e in controllers.entries)
                        e.key: e.value.text.trim(),
                    });
                  }
                },
                child: const Text('Xác nhận'),
              ),
            ],
          ),
        ),
      );
    } finally {
      Future<void>.delayed(const Duration(seconds: 1), () {
        for (final c in controllers.values) {
          c.dispose();
        }
      });
    }
  }

  Future<void> _return(Map<String, dynamic> item) async {
    final qtyCtrl = TextEditingController(text: '1');
    final reasonCtrl = TextEditingController();
    final attachments = <String>[];
    var uploading = false;
    String? uploadError;
    final form = GlobalKey<FormState>();
    Map<String, String>? response;
    try {
      response = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: widget.session,
          dialog: true,
          builder: (dialog, lease) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: const Text('Yêu cầu trả hàng'),
              content: SizedBox(
                width: 440,
                child: Form(
                  key: form,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (uploading) const LinearProgressIndicator(),
                        if (uploadError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              uploadError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: TextFormField(
                            controller: qtyCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Số lượng trả',
                            ),
                            keyboardType: TextInputType.number,
                            maxLength: 1000,
                            validator: (v) =>
                                (int.tryParse(v?.trim() ?? '') ?? 0) > 0
                                ? null
                                : 'Nhập số nguyên lớn hơn 0',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: TextFormField(
                            controller: reasonCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Lý do',
                            ),
                            maxLength: 1000,
                            validator: (v) => (v?.trim().length ?? 0) >= 3
                                ? null
                                : 'Nhập ít nhất 3 ký tự',
                          ),
                        ),
                        if (_orderId != null)
                          OutlinedButton.icon(
                            onPressed: uploading || attachments.length >= 4
                                ? null
                                : () async {
                                    update(() {
                                      uploading = true;
                                      uploadError = null;
                                    });
                                    try {
                                      final name =
                                          await pickAndUploadPrivateAttachment(
                                            session: widget.session,
                                            orderId: _orderId!,
                                            scope: 'return',
                                          );
                                      if (dialog.mounted) {
                                        update(() {
                                          uploading = false;
                                          if (name != null) {
                                            attachments.add(name);
                                          }
                                        });
                                      }
                                    } catch (e) {
                                      if (dialog.mounted) {
                                        update(() {
                                          uploading = false;
                                          uploadError = e is PublicApiException
                                              ? e.message
                                              : 'Chưa tải được ảnh minh chứng.';
                                        });
                                      }
                                    }
                                  },
                            icon: const Icon(Icons.attach_file),
                            label: Text(
                              attachments.isEmpty
                                  ? 'Đính kèm ảnh minh chứng trả hàng'
                                  : 'Đã đính kèm ${attachments.length} ảnh minh chứng',
                            ),
                          ),
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
                  onPressed: uploading
                      ? null
                      : () {
                          if (lease.valid && form.currentState!.validate()) {
                            Navigator.pop(dialog, {
                              'quantity': qtyCtrl.text.trim(),
                              'reason': reasonCtrl.text.trim(),
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
      Future<void>.delayed(const Duration(seconds: 1), () {
        qtyCtrl.dispose();
        reasonCtrl.dispose();
      });
    }
    if (response == null || !_valid) return;
    await _run(() async {
      await widget.session.service.command('marketplace/return_request', {
        'order_id': _orderId,
        'product_id': item['product_id'],
        'line_id': item['line_id'] ?? item['product_id'],
        'quantity': int.parse(response!['quantity']!),
        'reason': response['reason'],
        if (attachments.isNotEmpty) 'attachments': attachments,
      });
      await _load();
    });
  }

  Future<void> _review(Map<String, dynamic> item) async {
    int rating = 5;
    final body = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: widget.session,
        dialog: true,
        builder: (dialog, lease) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Đánh giá sản phẩm'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 1; i <= 5; i++)
                          Expanded(
                            child: IconButton(
                              tooltip: '$i sao',
                              constraints: const BoxConstraints.tightFor(
                                width: 40,
                                height: 44,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: () => update(() => rating = i),
                              icon: Icon(
                                i <= rating ? Icons.star : Icons.star_border,
                              ),
                            ),
                          ),
                      ],
                    ),
                    TextField(
                      controller: body,
                      maxLength: 2000,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Nhận xét'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Quay lại'),
              ),
              FilledButton(
                onPressed: () {
                  if (lease.valid && body.text.trim().length >= 3) {
                    Navigator.pop(dialog, true);
                  }
                },
                child: const Text('Gửi đánh giá'),
              ),
            ],
          ),
        ),
      ),
    );
    final text = body.text.trim();
    Future<void>.delayed(const Duration(seconds: 1), body.dispose);
    if (accepted != true || !_valid) return;
    await _run(() async {
      await widget.session.service.market('review_save', {
        'order_id': _orderId,
        'product_id': item['product_id'],
        'rating': rating,
        'body': text,
      });
      await _load();
    });
  }

  Future<void> _returnAction(Map<String, dynamic> ret, String action) async {
    final responseCtrl = TextEditingController();
    var createReturnShipment = false;
    var disposition = 'restock';
    final form = GlobalKey<FormState>();
    Map<String, dynamic>? payloadExtra;
    try {
      payloadExtra = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: widget.session,
          dialog: true,
          operator: widget.operator,
          builder: (dialog, lease) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: const Text('Xử lý trả hàng'),
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
                          controller: responseCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Phản hồi / lý do',
                          ),
                          maxLength: 1000,
                          validator: (v) => (v?.trim().length ?? 0) >= 3
                              ? null
                              : 'Nhập ít nhất 3 ký tự',
                        ),
                        if (action == 'approve')
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Tạo vận đơn thu hồi hàng trả (reverse logistics)',
                            ),
                            value: createReturnShipment,
                            onChanged: (v) => update(
                              () => createReturnShipment = v == true,
                            ),
                          ),
                        if (action == 'receive') ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: disposition,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Xử lý tồn kho hàng trả',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'restock',
                                child: Text('Nhập lại tồn kho bán tiếp'),
                              ),
                              DropdownMenuItem(
                                value: 'writeoff',
                                child: Text('Hàng hỏng / Không nhập lại kho'),
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
    await _run(() async {
      await widget.session.service.market('return_action', {
        'order_id': ret['order_id'],
        'id': ret['id'],
        'version': ret['version'],
        'action': action,
        ...payloadExtra!,
      });
      await _load();
    });
  }

  Future<void> _finance(String kind, {Map<String, dynamic>? ret}) async {
    final response = await _form(
      _kinds[kind]!,
      {
        'amount': 'Số tiền (VND)',
        'reason': 'Lý do',
        'evidence': 'Mã chứng từ / tham chiếu',
      },
      initial: {
        if (kind == 'collection')
          'amount':
              '${((_data['order']['snapshot']['payable_subtotal'] ?? _data['order']['snapshot']['subtotal']) as num) + (_data['order']['snapshot']['shipping_fee'] as num)}',
      },
    );
    if (response == null || !_valid) return;
    await _run(() async {
      await widget.session.service.command('marketplace/finance_request', {
        'order_id': _orderId,
        'kind': kind,
        'amount': int.parse(response['amount']!),
        'reason': response['reason'],
        'evidence': response['evidence'],
        if (ret != null) 'return_id': ret['id'],
      });
      await _load();
    });
  }

  Future<void> _financeAction(Map<String, dynamic> f, String action) async {
    final response = await _form(
      action == 'complete'
          ? 'Xác nhận thu/chi thực tế'
          : 'Duyệt yêu cầu tài chính',
      action == 'complete'
          ? {'evidence': 'Chứng từ giao dịch đã thực hiện'}
          : {'reason': 'Lý do quyết định'},
    );
    if (response == null || !_valid) return;
    await _run(() async {
      await widget.session.service.market('finance_action', {
        'id': f['id'],
        'version': f['version'],
        'action': action,
        ...response,
      });
      await _load();
    });
  }

  Future<void> _share() => _run(() async {
    final share = await widget.session.service.market('tracking_share', {
      'order_id': _orderId,
    });
    if (!_valid) return;
    await _load();
    if (!mounted || !widget.lease.valid) return;
    await showDialog<void>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: widget.session,
        dialog: true,
        builder: (dialog, lease) => AlertDialog(
          title: const Text('Chia sẻ theo dõi'),
          content: SizedBox(
            width: 440,
            child: SelectableText(
              share['share_url'] as String? ?? '${share['token']}',
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                if (!lease.valid) return;
                try {
                  await Clipboard.setData(
                    ClipboardData(
                      text:
                          share['share_url'] as String? ?? '${share['token']}',
                    ),
                  );
                } catch (_) {}
                if (dialog.mounted && lease.valid) Navigator.pop(dialog);
              },
              icon: const Icon(Icons.copy),
              label: const Text('Sao chép'),
            ),
          ],
        ),
      ),
    );
  });
  Future<void> _reorder() => _run(() async {
    final cart = await widget.session.service.market('cart');
    if (!_valid) return;
    await widget.session.service.command('marketplace/reorder', {
      'order_id': _orderId,
      'version': cart['version'],
    });
    if (_valid) {
      setState(() => _notice = 'Đã thêm sản phẩm vào giỏ theo giá hiện tại.');
    }
  });

  Widget _financeList() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final f in _rows(_data['finance']))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_kinds[f['kind']]} · ${_money(f['amount'])}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(_states[f['state']] ?? ''),
              if (widget.operator) ...[
                SelectableText('Đơn ${f['order_id']}'),
                Text('${f['reason']}'),
                if (f['evidence'] != null)
                  SelectableText('Tham chiếu đề nghị: ${f['evidence']}'),
                if (f['completion_evidence'] != null)
                  SelectableText(
                    'Chứng từ thực hiện: ${f['completion_evidence']}',
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => openMarketOrderServices(
                              context,
                              widget.session,
                              orderId: f['order_id'] as String,
                              operator: true,
                            ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Xem đơn'),
                    ),
                    if (f['proposer'] != widget.session.service.userId) ...[
                      if (f['state'] == 'requested')
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _financeAction(f, 'approve'),
                          child: const Text('Duyệt'),
                        ),
                      if (f['state'] == 'approved')
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _financeAction(f, 'complete'),
                          child: const Text('Xác nhận thu/chi'),
                        ),
                      if (['requested', 'approved'].contains(f['state']))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _financeAction(f, 'reject'),
                          child: const Text('Từ chối'),
                        ),
                    ],
                  ],
                ),
              ],
              const Divider(),
            ],
          ),
        ),
      if (_rows(_data['finance']).isEmpty)
        const Text('Chưa có yêu cầu thu/chi.'),
    ],
  );
  Widget _returnList() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final r in _rows(_data['returns']))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trả ${r['quantity']} sản phẩm · ${_states[r['state']] ?? ''}'
                '${r['disposition'] == 'restock' ? ' · Đã nhập lại kho' : r['disposition'] == 'writeoff' ? ' · Hủy hàng hỏng' : ''}',
              ),
              Text('${r['reason']}'),
              if ((r['response'] as String? ?? '').isNotEmpty)
                Text('${r['response']}'),
              if (r['return_delivery_id'] != null)
                SelectableText('Vận đơn thu hồi: ${r['return_delivery_id']}'),
              if (r['attachments'] is List &&
                  (r['attachments'] as List).isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final att in (r['attachments'] as List))
                      ActionChip(
                        avatar: const Icon(Icons.image_outlined, size: 16),
                        label: const Text('Xem ảnh minh chứng'),
                        onPressed: _busy
                            ? null
                            : () => openSignedPrivateAttachment(
                                context,
                                session: widget.session,
                                name: att is Map ? '${att['name']}' : '$att',
                                operator: widget.operator,
                              ),
                      ),
                  ],
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_buyer && r['state'] == 'rejected')
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _returnAction(r, 'escalate'),
                      child: const Text('Yêu cầu giải quyết'),
                    ),
                  if ((_merchant && r['state'] == 'requested') ||
                      widget.operator &&
                          ['requested', 'escalated'].contains(r['state'])) ...[
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _returnAction(r, 'approve'),
                      child: const Text('Chấp nhận trả'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _returnAction(r, 'reject'),
                      child: const Text('Từ chối'),
                    ),
                  ],
                  if ((_merchant || widget.operator) &&
                      r['state'] == 'approved')
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _returnAction(r, 'receive'),
                      child: const Text('Đã nhận hàng trả'),
                    ),
                  if ((_buyer || widget.operator) &&
                      r['state'] == 'received' &&
                      _orderId != null)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _finance('refund', ret: r),
                      child: const Text('Đề nghị hoàn tiền'),
                    ),
                  if (widget.operator && _orderId == null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => openMarketOrderServices(
                              context,
                              widget.session,
                              orderId: r['order_id'] as String,
                              operator: true,
                            ),
                      child: const Text('Xem đơn'),
                    ),
                ],
              ),
              const Divider(),
            ],
          ),
        ),
      if (_rows(_data['returns']).isEmpty)
        const Text('Chưa có yêu cầu trả hàng.'),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final order = _data['order'] as Map?;
    final delivered = order?['delivered_at'] != null;
    final shipments = _rows(_data['shipments']);
    final partnerReviews = _rows(_data['partner_reviews']);
    final attachments = _rows(_data['attachments']);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.operator ? 'Đối soát và hậu mãi' : 'Dịch vụ đơn mua',
        ),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !_valid
          ? const SizedBox.shrink()
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_busy) const LinearProgressIndicator(),
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
                          if (_notice != null) Text(_notice!),
                          if (_orderId == null && widget.operator) ...[
                            TextField(
                              controller: _lookup,
                              decoration: InputDecoration(
                                labelText: 'Mã đơn mua',
                                suffixIcon: IconButton(
                                  tooltip: 'Mở đơn',
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          final id = _lookup.text.trim();
                                          if (RegExp(
                                            r'^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$',
                                          ).hasMatch(id)) {
                                            openMarketOrderServices(
                                              context,
                                              widget.session,
                                              orderId: id,
                                              operator: true,
                                            );
                                          } else {
                                            setState(
                                              () => _error =
                                                  'Mã đơn không hợp lệ.',
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.search),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_data['jobs'] is Map)
                              Text(
                                'Đơn chờ xử lý: ${_data['jobs']['pending']} · Quá hạn: ${_data['jobs']['overdue']} · Tác vụ lỗi: ${_data['jobs']['failed']}',
                              ),
                            TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() async {
                                      await widget.session.service.market(
                                        'jobs_run',
                                      );
                                      await _load();
                                    }),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Xử lý đơn quá hạn'),
                            ),
                            for (final j in _rows(_data['failed_jobs']))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Tác vụ lỗi sau ${j['attempts']} lần',
                                ),
                                subtitle: SelectableText(
                                  'Đơn ${j['order_id']}',
                                ),
                                trailing: IconButton(
                                  tooltip: 'Thử lại tác vụ',
                                  icon: const Icon(Icons.replay),
                                  onPressed: _busy
                                      ? null
                                      : () => _run(() async {
                                          await widget.session.service.market(
                                            'job_retry',
                                            {'id': j['id']},
                                          );
                                          await _load();
                                        }),
                                ),
                              ),
                          ],
                          if (order != null) ...[
                            SelectableText('Đơn ${order['id']}'),
                            Text(
                              '${order['snapshot']['shop_name']}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            Text('Đã thu: ${_money(_data['collected'])}'),
                            Text('Đã hoàn: ${_money(_data['refunded'])}'),
                            if (_merchant || widget.operator)
                              Text('Đã trả shop: ${_money(_data['settled'])}'),
                            if (shipments.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Kiện vận chuyển (${shipments.length})',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              for (final s in shipments)
                                SelectableText(
                                  'Kiện #${s['parcel_no']} · ${s['tracking_code']} · ${cloudStatuses[s['status']] ?? s['status']}',
                                ),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (_buyer)
                                  OutlinedButton.icon(
                                    onPressed: _busy ? null : _reorder,
                                    icon: const Icon(Icons.add_shopping_cart),
                                    label: const Text('Mua lại'),
                                  ),
                                if (_buyer)
                                  OutlinedButton.icon(
                                    onPressed: _busy ? null : _share,
                                    icon: const Icon(Icons.share_outlined),
                                    label: const Text('Chia sẻ theo dõi'),
                                  ),
                                if (_buyer && delivered)
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            final ok =
                                                await showPartnerReviewDialog(
                                                  context,
                                                  session: widget.session,
                                                  targetKind: 'shop',
                                                  orderId: _orderId,
                                                );
                                            if (ok == true && _valid) {
                                              await _reload();
                                            }
                                          },
                                    icon: const Icon(Icons.storefront_outlined),
                                    label: const Text('Đánh giá cửa hàng'),
                                  ),
                                if (_buyer &&
                                    delivered &&
                                    order['delivery_id'] != null)
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            final ok =
                                                await showPartnerReviewDialog(
                                                  context,
                                                  session: widget.session,
                                                  targetKind: 'driver',
                                                  orderId: _orderId,
                                                );
                                            if (ok == true && _valid) {
                                              await _reload();
                                            }
                                          },
                                    icon: const Icon(
                                      Icons.delivery_dining_outlined,
                                    ),
                                    label: const Text('Đánh giá tài xế'),
                                  ),
                                if (widget.operator && delivered)
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _finance('collection'),
                                    child: const Text('Đề nghị thu COD'),
                                  ),
                                if ((_merchant || widget.operator) && delivered)
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _finance('settlement'),
                                    child: const Text('Đề nghị trả tiền shop'),
                                  ),
                              ],
                            ),
                            if (_buyer)
                              for (final s in _rows(_data['shares']).where(
                                (s) =>
                                    s['revoked_at'] == null &&
                                    (DateTime.tryParse('${s['expires_at']}')
                                            ?.isAfter(DateTime.now()) ??
                                        false),
                              ))
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    'Liên kết đến ${s['expires_at']}',
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Thu hồi liên kết',
                                    icon: const Icon(Icons.link_off),
                                    onPressed: _busy
                                        ? null
                                        : () => _run(() async {
                                            await widget.session.service.market(
                                              'tracking_revoke',
                                              {
                                                'order_id': _orderId,
                                                'id': s['id'],
                                              },
                                            );
                                            await _load();
                                          }),
                                  ),
                                ),
                            const Divider(),
                            for (final item in _rows(
                              order['snapshot']['items'],
                            ))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('${item['name']}'),
                                subtitle: Text(
                                  '${item['quantity']} × ${_money(item['unit_price'])}'
                                  '${marketOptionNames(item['options']).isEmpty ? '' : '\n${marketOptionNames(item['options'])}'}',
                                ),
                                trailing: _buyer && delivered
                                    ? Wrap(
                                        children: [
                                          IconButton(
                                            tooltip: 'Đánh giá',
                                            onPressed: _busy
                                                ? null
                                                : () => _review(item),
                                            icon: const Icon(
                                              Icons.star_outline,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Trả hàng',
                                            onPressed: _busy
                                                ? null
                                                : () => _return(item),
                                            icon: const Icon(
                                              Icons.assignment_return_outlined,
                                            ),
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                            if (partnerReviews.isNotEmpty) ...[
                              const Divider(),
                              Text(
                                'Đánh giá cửa hàng & tài xế',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              for (final pr in partnerReviews)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${pr['target_kind'] == 'shop' ? 'Cửa hàng' : 'Tài xế'} · ${pr['rating']}/5 sao',
                                  ),
                                  subtitle: Text(
                                    '${pr['body']}'
                                    '${(pr['reply'] as String? ?? '').isEmpty ? '' : '\nPhản hồi: ${pr['reply']}'}',
                                  ),
                                  trailing: Wrap(
                                    children: [
                                      if (_merchant &&
                                          pr['target_kind'] == 'shop')
                                        IconButton(
                                          tooltip: 'Phản hồi đánh giá shop',
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
                                                        reviewKind: 'partner',
                                                        reviewId: '${pr['id']}',
                                                        reply: true,
                                                      );
                                                  if (ok == true && _valid) {
                                                    await _reload();
                                                  }
                                                },
                                        ),
                                      IconButton(
                                        tooltip: 'Báo cáo đánh giá đối tác',
                                        icon: const Icon(
                                          Icons.flag_outlined,
                                          size: 18,
                                        ),
                                        onPressed: _busy
                                            ? null
                                            : () =>
                                                  showReviewReplyOrReportDialog(
                                                    context,
                                                    session: widget.session,
                                                    reviewKind: 'partner',
                                                    reviewId: '${pr['id']}',
                                                    reply: false,
                                                  ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            if (attachments.isNotEmpty) ...[
                              const Divider(),
                              Text(
                                'Tệp đính kèm bảo mật',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final att in attachments)
                                    ActionChip(
                                      avatar: const Icon(
                                        Icons.lock_outline,
                                        size: 16,
                                      ),
                                      label: Text(
                                        '${att['scope']} · ${att['name']}',
                                      ),
                                      onPressed: _busy
                                          ? null
                                          : () => openSignedPrivateAttachment(
                                              context,
                                              session: widget.session,
                                              name: '${att['name']}',
                                              operator: widget.operator,
                                            ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                          const SizedBox(height: 20),
                          Text(
                            'Trả hàng và tranh chấp',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          _returnList(),
                          if (_data['returns_next'] is Map)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() => _load(more: 'returns')),
                              child: const Text('Yêu cầu trả hàng cũ hơn'),
                            ),
                          const SizedBox(height: 20),
                          Text(
                            'Lịch sử thu/chi',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          _financeList(),
                          if (_data['next'] is Map)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() => _load(more: 'finance')),
                              child: const Text('Giao dịch cũ hơn'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
