import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/integrations/cloud_orders_service.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/utils/currency_formatter.dart';

class CloudCommerceDialog extends StatefulWidget {
  const CloudCommerceDialog({
    super.key,
    required this.service,
    required this.order,
    this.shipment = false,
    this.purchase = false,
    this.operator = false,
    this.lease,
  });
  final CloudOrdersService service;
  final Map<String, dynamic> order;
  final bool shipment, purchase, operator;
  final CloudSessionLease? lease;

  @override
  State<CloudCommerceDialog> createState() => _CloudCommerceDialogState();
}

class _CloudCommerceDialogState extends State<CloudCommerceDialog>
    with WidgetsBindingObserver {
  final _fields = <String, TextEditingController>{};
  late final String _identity = widget.service.userId;
  late final String _scope = widget.service.identityScope;
  bool _invalidated = false;
  StreamSubscription<dynamic>? _auth;
  Map<String, dynamic>? _record, _quote;
  String? _error;
  bool _busy = false, _configured = false;
  String _requiredNote = 'KHONGCHOXEMHANG';
  String get _path => widget.purchase
      ? 'purchases/${widget.order['id']}/payment'
      : 'orders/${widget.order['id']}/${widget.shipment ? 'shipment' : 'payment'}';
  bool get _sameAccount =>
      !_invalidated &&
      widget.service.identityScope == _scope &&
      widget.service.signedIn &&
      (widget.lease?.valid ?? true);
  String _money(dynamic value) =>
      CurrencyFormatter.formatVnd((value as num? ?? 0).toDouble());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final openingSession = widget.service.authSession;
    _auth = widget.service.authChanges.listen((event) {
      if (!_sameAccount ||
          event.event == AuthChangeEvent.signedOut ||
          event.event == AuthChangeEvent.signedIn &&
              (event.session == null ||
                  !identical(event.session, openingSession))) {
        _invalidate();
      }
    });
    widget.lease?.addListener(_invalidate);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        _sameAccount &&
        !_busy &&
        !widget.shipment &&
        _record?['status'] == 'PENDING') {
      unawaited(_refresh());
    }
  }

  void _invalidate() {
    if (!mounted || _invalidated) return;
    _invalidated = true;
    setState(() {
      _record = null;
      _quote = null;
      _configured = false;
      _error = 'Tài khoản đã thay đổi. Đóng cửa sổ và mở lại.';
      for (final controller in _fields.values) {
        controller.clear();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth?.cancel();
    widget.lease?.removeListener(_invalidate);
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _request(
    String path, {
    Map<String, dynamic>? body,
    bool quote = false,
  }) async {
    if (_busy || !_sameAccount) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.service.request(path, body: body);
      if (!mounted || !_sameAccount) return;
      setState(() {
        if (quote) {
          _quote = response;
        } else {
          if (response.containsKey('configured')) {
            _configured = response['configured'] == true;
          }
          _record = (response[widget.shipment ? 'shipment' : 'payment'] as Map?)
              ?.cast<String, dynamic>();
        }
      });
    } on PublicApiException catch (e) {
      if (mounted && _sameAccount) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && _sameAccount) {
        setState(() => _error = 'Không tải được dịch vụ. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _request(_path);
  Future<void> _refresh() =>
      _record == null ? _load() : _request('$_path/refresh', body: const {});
  Future<bool> _confirm(String title, String content) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Quay lại'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _preview() async {
    final values = <String, dynamic>{'required_note': _requiredNote};
    for (final key in [
      'from_province_name',
      'from_ward_name',
      'to_province_name',
      'to_ward_name',
    ]) {
      values[key] = _fields[key]?.text.trim() ?? '';
    }
    for (final key in ['length', 'width', 'height']) {
      values[key] = int.tryParse(_fields[key]?.text.trim() ?? '');
    }
    await _request('$_path/preview', body: values, quote: true);
  }

  Widget _field(String key, String label, {bool number = false, String? suffixText}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _fields.putIfAbsent(key, TextEditingController.new),
      enabled: !_busy && _sameAccount,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label, suffixText: suffixText,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() => _quote = null),
    ),
  );

  Widget _payment() {
    final status = _record?['status'];
    final cashCollectedFee =
        !widget.purchase &&
        ((widget.order['cash_collected_fee'] as num? ?? 0) > 0);
    final label =
        const {
          'CREATING': 'Đang xác minh liên kết',
          'PENDING': 'Chờ thanh toán',
          'PAID': 'Đã thanh toán',
          'REVIEW': 'Cần đối soát',
          'CANCELLED': 'Đã hủy liên kết',
          'EXPIRED': 'Đã hết hạn',
        }[status] ??
        (cashCollectedFee
            ? 'Đã thu tiền mặt cước'
            : 'Chưa có liên kết thanh toán');
    final canCreate = widget.purchase
        ? _sameAccount &&
              _configured &&
              (widget.operator || widget.order['owner_id'] == _identity) &&
              widget.order['payment_method'] == 'prepaid' &&
              (widget.order['payment_status'] ?? 'UNPAID') == 'UNPAID' &&
              !['PENDING', 'PAID', 'REVIEW'].contains(status)
        : _sameAccount &&
              _configured &&
              (widget.operator || widget.order['owner_id'] == _identity) &&
              widget.order['status'] == 'searching' &&
              widget.order['driver_id'] == null &&
              widget.order['fulfillment_provider'] == null &&
              (widget.order['details'] as Map?)?['payment_method'] ==
                  'sender_cash' &&
              (widget.order['payment_status'] ?? 'UNPAID') == 'UNPAID' &&
              !cashCollectedFee &&
              !['PENDING', 'PAID', 'REVIEW'].contains(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.purchase)
          Text(
            'Tổng thanh toán đơn mua: ${_money(_record?['amount'] ?? widget.order['total'])}',
          )
        else ...[
          if ((widget.order['coin_discount'] as num? ?? 0) > 0) ...[
            Text('Cước gốc: ${_money(widget.order['shipping_fee'])}'),
            Text(
              'Đổi Xu giảm cước: -${_money(widget.order['coin_discount'])}',
            ),
          ],
          Text(
            'Cước cần thanh toán: ${_money(_record?['amount'] ?? widget.order['payable_fee'] ?? widget.order['shipping_fee'])}',
          ),
          Text('Thu hộ COD riêng: ${_money(widget.order['cod_amount'])}'),
        ],
        const SizedBox(height: 12),
        Text(label),
        if (_record?['provider_order_code'] != null)
          Text('Mã giao dịch payOS: ${_record!['provider_order_code']}'),
        if (_record?['expires_at'] != null)
          Text(
            'Hết hạn: ${DateTime.tryParse('${_record!['expires_at']}')?.toLocal() ?? _record!['expires_at']}',
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (canCreate)
              FilledButton.icon(
                onPressed: _busy ? null : () => _request(_path, body: const {}),
                icon: const Icon(Icons.payment),
                label: Text(
                  status == 'CREATING'
                      ? 'Kiểm tra lại liên kết'
                      : 'Tạo liên kết payOS',
                ),
              ),
            if (_record?['checkout_url'] != null && status == 'PENDING') ...[
              FilledButton.icon(
                onPressed: _busy || !_sameAccount
                    ? null
                    : () async {
                        final url = Uri.tryParse('${_record!['checkout_url']}');
                        if (url == null ||
                            url.scheme != 'https' ||
                            url.host != 'pay.payos.vn') {
                          return;
                        }
                        try {
                          if (!await launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              ) &&
                              mounted) {
                            setState(
                              () => _error = 'Không mở được trang thanh toán.',
                            );
                          }
                        } catch (_) {
                          if (mounted) {
                            setState(
                              () => _error = 'Không mở được trang thanh toán.',
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Mở thanh toán'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || !_sameAccount ? null : _refresh,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Kiểm tra thanh toán'),
              ),
              IconButton(
                tooltip: 'Sao chép liên kết',
                onPressed: !_sameAccount
                    ? null
                    : () => Clipboard.setData(
                        ClipboardData(text: '${_record!['checkout_url']}'),
                      ),
                icon: const Icon(Icons.copy),
              ),
            ],
            if (['CREATING', 'PENDING'].contains(status) &&
                (widget.operator || widget.order['owner_id'] == _identity))
              TextButton.icon(
                onPressed: _busy || !_sameAccount
                    ? null
                    : () async {
                        if (!await _confirm(
                              'Hủy liên kết thanh toán?',
                              '${widget.order['tracking_code'] ?? widget.order['id']}',
                            ) ||
                            !mounted ||
                            !_sameAccount) {
                          return;
                        }
                        await _request('$_path/cancel', body: const {});
                      },
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Hủy liên kết'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _shipment() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_record != null) ...[
        SelectableText(
          'GHN: ${_record!['ghn_order_code'] ?? 'Chờ hãng xác nhận'}',
        ),
        Text('Trạng thái hãng: ${_record!['status']}'),
        if (_record!['total_fee'] != null)
          Text('Cước GHN shop trả: ${_money(_record!['total_fee'])}'),
        if (_record!['expected_delivery_time'] != null)
          Text(
            'Dự kiến: ${DateTime.tryParse('${_record!['expected_delivery_time']}')?.toLocal() ?? ''}',
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy || !_sameAccount
                  ? null
                  : () => _request('$_path/refresh', body: const {}),
              icon: const Icon(Icons.sync),
              label: const Text('Đồng bộ GHN'),
            ),
            if (widget.operator && _record!['ghn_order_code'] == null)
              FilledButton.icon(
                onPressed: _busy || !_sameAccount
                    ? null
                    : () => _request(_path, body: const {}),
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại vận đơn'),
              ),
            if (widget.operator &&
                _record!['ghn_order_code'] != null &&
                ![
                  'delivered',
                  'returned',
                  'cancel',
                ].contains(_record!['status']))
              TextButton.icon(
                onPressed: _busy || !_sameAccount
                    ? null
                    : () async {
                        if (!await _confirm(
                              'Yêu cầu GHN hủy vận đơn?',
                              '${_record!['ghn_order_code']}',
                            ) ||
                            !mounted ||
                            !_sameAccount) {
                          return;
                        }
                        await _request('$_path/cancel', body: const {});
                      },
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Yêu cầu hủy GHN'),
              ),
          ],
        ),
      ] else if (widget.operator && _configured) ...[
        Text('Lấy: ${(widget.order['details'] as Map)['pickup_address']}'),
        Text('Giao: ${(widget.order['details'] as Map)['dropoff_address']}'),
        const SizedBox(height: 16),
        _field('from_province_name', 'Tỉnh/thành điểm lấy'),
        _field('from_ward_name', 'Phường/xã điểm lấy'),
        _field('to_province_name', 'Tỉnh/thành điểm giao'),
        _field('to_ward_name', 'Phường/xã điểm giao'),
        _field('length', 'Chiều dài', number: true, suffixText: 'cm'),
        _field('width', 'Chiều rộng', number: true, suffixText: 'cm'),
        _field('height', 'Chiều cao', number: true, suffixText: 'cm'),
        DropdownButtonFormField<String>(
          initialValue: _requiredNote,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Quy định xem hàng'),
          items: const [
            DropdownMenuItem(
              value: 'KHONGCHOXEMHANG',
              child: Text('Không cho xem hàng'),
            ),
            DropdownMenuItem(
              value: 'CHOXEMHANGKHONGTHU',
              child: Text('Cho xem, không thử'),
            ),
            DropdownMenuItem(
              value: 'CHOTHUHANG',
              child: Text('Cho xem và thử'),
            ),
          ],
          onChanged: _busy || !_sameAccount
              ? null
              : (v) => setState(() {
                  _requiredNote = v!;
                  _quote = null;
                }),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy || !_sameAccount ? null : _preview,
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('Xem phí GHN'),
        ),
        if (_quote != null) ...[
          const SizedBox(height: 12),
          Text('Cước GHN shop trả: ${_money(_quote!['total_fee'])}'),
          FilledButton.icon(
            onPressed: _busy || !_sameAccount
                ? null
                : () async {
                    final quote = _quote!;
                    if (!await _confirm(
                          'Tạo vận đơn GHN?',
                          '${widget.order['tracking_code']}\nCước GHN shop trả: ${_money(quote['total_fee'])}',
                        ) ||
                        !mounted ||
                        !_sameAccount) {
                      return;
                    }
                    await _request(
                      _path,
                      body: {'quote_id': quote['quote_id']},
                    );
                  },
            icon: const Icon(Icons.local_shipping_outlined),
            label: const Text('Tạo vận đơn GHN'),
          ),
        ],
      ] else
        const Text('Chưa có vận đơn GHN.'),
    ],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.purchase
          ? 'Thanh toán đơn mua · ${widget.order['tracking_code'] ?? widget.order['id']}'
          : '${widget.shipment ? 'Vận chuyển GHN' : 'Thanh toán cước'} · ${widget.order['tracking_code']}',
    ),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!_busy && !_configured && _error == null)
              const Text('Dịch vụ chưa được bật hoặc chưa đủ cấu hình.'),
            if (_sameAccount) widget.shipment ? _shipment() : _payment(),
          ],
        ),
      ),
    ),
    actions: [
      IconButton(
        tooltip: 'Tải lại',
        onPressed: _busy || !_sameAccount ? null : _refresh,
        icon: const Icon(Icons.refresh),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Đóng'),
      ),
    ],
  );
}
