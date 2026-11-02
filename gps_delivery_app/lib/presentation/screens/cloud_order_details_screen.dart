import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/utils/currency_formatter.dart';
import '../widgets/cloud_order_form.dart';
import '../widgets/cloud_order_labels.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/market_commercial_sheets.dart';

class CloudOrderDetailsScreen extends StatefulWidget {
  const CloudOrderDetailsScreen({
    super.key,
    required this.lease,
    required this.order,
    this.merchants = const [],
  });

  final CloudSessionLease lease;
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> merchants;

  @override
  State<CloudOrderDetailsScreen> createState() =>
      _CloudOrderDetailsScreenState();
}

class _CloudOrderDetailsScreenState extends State<CloudOrderDetailsScreen> {
  List<Map<String, dynamic>>? _history;
  bool _busy = false;
  int _generation = 0;
  String? _error;
  bool get _allowed => widget.lease.valid;
  Map<String, dynamic> get _order => widget.order;
  Map get _details => _order['details'] as Map? ?? const {};
  bool get _isOwner => _order['owner_id'] == widget.lease.session.service.userId;
  bool get _isMerchantOrOperator =>
      widget.lease.session.isOperator ||
      _order['merchant_id'] == widget.lease.session.service.userId;
  String get _effectiveStatus {
    final history = _history;
    final latest = history != null && history.isNotEmpty ? history.last : null;
    return '${latest != null && latest['version'] >= (_order['version'] as int? ?? 0) ? latest['status'] : _order['status']}';
  }

  bool get _canRepeat =>
      _allowed &&
      _history != null &&
      widget.lease.session.canCreateShippingOrder &&
      _isOwner;

  @override
  void initState() {
    super.initState();
    widget.lease.addListener(_invalidate);
    _load();
  }

  void _invalidate() {
    if (!mounted) return;
    _generation++;
    setState(() {
      _history = null;
      _error = null;
    });
  }

  @override
  void dispose() {
    _generation++;
    widget.lease.removeListener(_invalidate);
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy || !_allowed) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _history = null;
      _error = null;
    });
    try {
      final result = await widget.lease.session.service.request(
        'orders/${_order['id']}/history',
      );
      if (!mounted || !_allowed || generation != _generation) return;
      final raw = result['history'];
      if (raw is! List) throw const FormatException('Invalid order history');
      final versions = <int>{};
      final history =
          raw.map((row) {
            if (row is! Map ||
                row['order_id'] != _order['id'] ||
                row['version'] is! int ||
                row['version'] < 1 ||
                !versions.add(row['version'] as int) ||
                !cloudActions.containsKey(row['action']) ||
                !cloudStatuses.containsKey(row['status']) ||
                DateTime.tryParse('${row['created_at']}') == null ||
                row['reason'] != null && row['reason'] is! String) {
              throw const FormatException('Invalid order history entry');
            }
            return Map<String, dynamic>.unmodifiable(
              Map<String, dynamic>.from(row),
            );
          }).toList()..sort(
            (a, b) => (a['version'] as int).compareTo(b['version'] as int),
          );
      setState(() => _history = List.unmodifiable(history));
    } catch (error) {
      if (!mounted || !_allowed || generation != _generation) return;
      if (error is PublicApiException &&
          [401, 403].contains(error.statusCode)) {
        widget.lease.session.invalidateVerification();
        return;
      }
      setState(
        () => _error = error is PublicApiException && error.statusCode == 404
            ? 'Đơn hàng không còn khả dụng với tài khoản này.'
            : 'Không tải được chi tiết đơn hàng. Vui lòng thử lại.',
      );
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  String _text(dynamic value) =>
      value == null || '$value'.trim().isEmpty ? 'Chưa có thông tin' : '$value';
  String _money(dynamic value) => value is num && value.isFinite && value >= 0
      ? CurrencyFormatter.formatVnd(value.toDouble())
      : 'Chưa có thông tin';
  String get _status => cloudStatuses[_effectiveStatus] ?? 'Đang cập nhật';

  String get _payment => switch (_order['payment_status']) {
    'PAID' => 'Đã thanh toán cước',
    'REVIEW' => 'Cần đối soát cước',
    _ => 'Chưa ghi nhận thanh toán cước',
  };
  String get _payer => switch (_details['payment_method']) {
    'sender_cash' => 'Người gửi trả phí',
    'recipient_cash' => 'Người nhận trả phí',
    _ => 'Chưa có thông tin',
  };

  Map<String, String> get _summary => {
    'Trạng thái': _status,
    'Ngày tạo': cloudDate(_order['created_at']),
    'Điểm lấy': _text(_details['pickup_address']),
    'Điểm giao': _text(_details['dropoff_address']),
    'Người nhận': _text(_details['recipient_name']),
    'Điện thoại': _text(_details['recipient_phone']),
    'Hàng hóa': _text(_details['package_description']),
    'Khối lượng (kg)': _text(_details['weight_kg']),
    'Cước vận chuyển': _money(_order['shipping_fee']),
    'Tiền thu hộ COD': _money(_order['cod_amount']),
    'Trả phí': _payer,
    'Thanh toán': _payment,
  };

  Future<void> _copy({bool receipt = false}) async {
    if (!_allowed || _history == null) return;
    final text = receipt
        ? [
            'THÔNG TIN ĐƠN GIAO HÀNG',
            'Mã vận đơn: ${_order['tracking_code']}',
            ..._summary.entries.map((e) => '${e.key}: ${e.value}'),
          ].join('\n')
        : '${_order['tracking_code']}';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted && _allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            receipt ? 'Đã sao chép thông tin đơn.' : 'Đã sao chép mã vận đơn.',
          ),
        ),
      );
    }
  }

  Future<void> _showOtp() async {
    if (_busy || !_allowed) return;
    setState(() => _busy = true);
    try {
      final res = await widget.lease.session.service.orderOtp(
        '${_order['id']}',
      );
      if (!mounted || !_allowed) return;
      final otp = '${res['otp_code'] ?? res['recipient_otp'] ?? ''}'.trim();
      await showDialog<void>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: widget.lease.session,
          dialog: true,
          builder: (dialog, _) => AlertDialog(
            title: const Text('Mã OTP giao hàng người nhận'),
            content: SelectableText(
              otp.isEmpty ? 'Đơn hàng này không yêu cầu OTP.' : otp,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            actions: [
              if (otp.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: otp)).ignore();
                    Navigator.pop(dialog);
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Sao chép'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Đóng'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted && !_leaseHandled(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa tải được mã OTP.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _viewPod() async {
    if (_busy || !_allowed) return;
    setState(() => _busy = true);
    try {
      final url = await widget.lease.session.service.signPod(
        '${_order['tracking_code']}',
      );
      if (!mounted || !_allowed) return;
      await showDialog<void>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: widget.lease.session,
          dialog: true,
          builder: (dialog, _) => AlertDialog(
            title: const Text('Ảnh bằng chứng giao hàng (POD)'),
            content: SizedBox(
              width: 480,
              height: 360,
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Text('Không hiển thị được ảnh POD.')),
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
    } catch (e) {
      if (mounted && !_leaseHandled(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa mở được ảnh POD.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manageShares() async {
    if (_busy || !_allowed) return;
    setState(() => _busy = true);
    List<Map<String, dynamic>> shares = [];
    try {
      final res = await widget.lease.session.service.orderShares(
        '${_order['id']}',
      );
      shares = (res['shares'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      if (mounted && !_leaseHandled(e)) {
        setState(() {
          _busy = false;
          _error = e is PublicApiException
              ? e.message
              : 'Chưa tải được danh sách liên kết chia sẻ.';
        });
      }
      return;
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted || !_allowed) return;
    await showDialog<void>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: widget.lease.session,
        dialog: true,
        builder: (dialog, lease) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Chia sẻ hành trình đơn hàng'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: () async {
                        final created = await widget.lease.session.service
                            .orderShares('${_order['id']}', create: true);
                        final url =
                            created['share_url'] as String? ??
                            '${created['token']}';
                        try {
                          await Clipboard.setData(ClipboardData(text: url));
                        } catch (_) {}
                        final refreshed = await widget.lease.session.service
                            .orderShares('${_order['id']}');
                        if (dialog.mounted && lease.valid) {
                          update(() {
                            shares = (refreshed['shares'] as List? ?? const [])
                                .map((e) => Map<String, dynamic>.from(e as Map))
                                .toList();
                          });
                        }
                      },
                      icon: const Icon(Icons.add_link),
                      label: const Text('Tạo & sao chép liên kết mới'),
                    ),
                    const SizedBox(height: 12),
                    if (shares.isEmpty)
                      const Text('Chưa có liên kết chia sẻ đang mở.'),
                    for (final s in shares)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: SelectableText('Mã liên kết · ${s['id']}'),
                        subtitle: Text(
                          s['revoked_at'] != null
                              ? 'Đã thu hồi'
                              : 'Hiệu lực đến: ${cloudDate(s['expires_at'])}',
                        ),
                        trailing: s['revoked_at'] != null
                            ? null
                            : IconButton(
                                tooltip: 'Thu hồi liên kết',
                                icon: const Icon(Icons.link_off),
                                onPressed: () async {
                                  await widget.lease.session.service
                                      .orderShares(
                                        '${_order['id']}',
                                        revokeId: '${s['id']}',
                                      );
                                  final refreshed = await widget
                                      .lease
                                      .session
                                      .service
                                      .orderShares('${_order['id']}');
                                  if (dialog.mounted && lease.valid) {
                                    update(() {
                                      shares =
                                          (refreshed['shares'] as List? ??
                                                  const [])
                                              .map(
                                                (e) =>
                                                    Map<String, dynamic>.from(
                                                      e as Map,
                                                    ),
                                              )
                                              .toList();
                                    });
                                  }
                                },
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
      ),
    );
  }

  bool _leaseHandled(Object error) {
    if (error is PublicApiException && [401, 403].contains(error.statusCode)) {
      widget.lease.session.invalidateVerification();
      return true;
    }
    return false;
  }

  Future<void> _repeat() async {
    if (!_canRepeat) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CloudSessionBoundary(
          session: widget.lease.session,
          roles: const {'customer', 'merchant'},
          builder: (_, lease) => CloudOrderForm(
            service: widget.lease.session.service,
            lease: lease,
            merchants: widget.merchants,
            initialDetails: {
              ..._details,
              'cod_amount': _order['cod_amount'],
              'merchant_id': _order['merchant_id'],
            },
          ),
        ),
      ),
    );
    if (mounted && _allowed && result == true) Navigator.of(context).pop(true);
  }

  Widget _section(String title, Map<String, String> values) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      for (final entry in values.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.key, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 3),
              SelectableText(entry.value),
            ],
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final visible = _allowed && _history != null;
    final summary = visible ? _summary : const <String, String>{};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết đơn hàng'),
        actions: [
          IconButton(
            tooltip: 'Tải lại lịch sử',
            onPressed: _busy || !_allowed ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sao chép thông tin đơn',
            onPressed: visible ? () => _copy(receipt: true) : null,
            icon: const Icon(Icons.content_copy_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (!_allowed)
                    const Text(
                      'Phiên làm việc đã thay đổi. Vui lòng mở lại đơn hàng.',
                    ),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Thử lại'),
                      ),
                    ),
                  ],
                  if (visible) ...[
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SelectableText(
                          _text(_order['tracking_code']),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        IconButton(
                          tooltip: 'Sao chép mã vận đơn',
                          onPressed: _copy,
                          icon: const Icon(Icons.copy_outlined, size: 20),
                        ),
                      ],
                    ),
                    Text(
                      _status,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(cloudDate(_order['created_at'])),
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_canRepeat)
                            FilledButton.icon(
                              onPressed: _repeat,
                              icon: const Icon(Icons.replay),
                              label: const Text('Gửi lại đơn'),
                            ),
                          if ((_isOwner || _isMerchantOrOperator) &&
                              _details['require_otp'] == true)
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _showOtp,
                              icon: const Icon(Icons.pin_outlined),
                              label: const Text('Mã OTP người nhận'),
                            ),
                          if (_isOwner || _isMerchantOrOperator)
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _manageShares,
                              icon: const Icon(Icons.share_outlined),
                              label: const Text('Chia sẻ hành trình'),
                            ),
                          if ((_order['pod_photo_path'] as String? ?? '')
                              .isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _viewPod,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Xem ảnh POD'),
                            ),
                          if (_isOwner &&
                              _effectiveStatus == 'delivered' &&
                              _order['driver_id'] != null)
                            OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => showPartnerReviewDialog(
                                      context,
                                      session: widget.lease.session,
                                      targetKind: 'driver',
                                      cloudOrderId: '${_order['id']}',
                                    ),
                              icon: const Icon(Icons.star_outline),
                              label: const Text('Đánh giá tài xế'),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 32),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final pickup = _section('Lấy hàng', {
                          'Địa chỉ': summary['Điểm lấy']!,
                          if ((_details['scheduled_at'] as String? ?? '')
                              .isNotEmpty)
                            'Hẹn lấy hàng': cloudDate(_details['scheduled_at']),
                        });
                        final dropoff = _section('Giao hàng', {
                          'Địa chỉ': summary['Điểm giao']!,
                          'Người nhận': summary['Người nhận']!,
                          'Điện thoại': summary['Điện thoại']!,
                          if (_details['extra_stops'] is List &&
                              (_details['extra_stops'] as List).isNotEmpty)
                            'Điểm dừng trung gian': (_details['extra_stops']
                                    as List)
                                .map((s) => '${(s as Map)['address'] ?? ''}')
                                .join(' -> '),
                        });
                        return constraints.maxWidth < 680
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  pickup,
                                  const SizedBox(height: 12),
                                  dropoff,
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: pickup),
                                  const SizedBox(width: 32),
                                  Expanded(child: dropoff),
                                ],
                              );
                      },
                    ),
                    const Divider(height: 32),
                    _section('Kiện hàng', {
                      'Hàng hóa': summary['Hàng hóa']!,
                      'Khối lượng (kg)': summary['Khối lượng (kg)']!,
                      'Dịch vụ':
                          cloudServiceTypes[_details['service_type']] ??
                          'Chưa có thông tin',
                      if ((_details['length_cm'] as num? ?? 0) > 0 &&
                          (_details['width_cm'] as num? ?? 0) > 0 &&
                          (_details['height_cm'] as num? ?? 0) > 0)
                        'Kích thước (cm)':
                            '${_details['length_cm']} × ${_details['width_cm']} × ${_details['height_cm']}',
                      if ((_details['declared_value'] as num? ?? 0) > 0)
                        'Khai giá bảo hiểm': _money(_details['declared_value']),
                      if ((_details['buyer_note'] as String? ?? '').isNotEmpty)
                        'Ghi chú': '${_details['buyer_note']}',
                      if ((_order['delivery_instruction'] as String? ?? '')
                          .isNotEmpty)
                        'Chỉ dẫn giao hàng':
                            '${_order['delivery_instruction']}',
                    }),
                    const Divider(height: 32),
                    _section('Cước và thu hộ', {
                      'Cước vận chuyển': summary['Cước vận chuyển']!,
                      'Tiền thu hộ COD': summary['Tiền thu hộ COD']!,
                      'Trả phí': _payer,
                      'Thanh toán cước': _payment,
                    }),
                    if (_order['fulfillment_provider'] == 'ghn')
                      _section('Vận chuyển GHN', {
                        'Mã vận đơn hãng': _text(_order['carrier_code']),
                      }),
                    const Divider(height: 32),
                    Text(
                      'Lịch sử đơn hàng',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (_history!.isEmpty)
                      const Text('Chưa có lịch sử cập nhật.'),
                    for (final event in _history!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 3),
                              child: Icon(Icons.check_circle_outline, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cloudActions[event['action']]!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(cloudStatuses[event['status']]!),
                                  Text(
                                    cloudDate(event['created_at']),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                  if ((event['reason'] as String? ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    SelectableText('Lý do: ${event['reason']}'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
