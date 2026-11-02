import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/integrations/photon_address_service.dart';
import '../../core/network/public_json_api.dart';
import '../../core/utils/cloud_order_csv.dart';
import '../../core/utils/currency_formatter.dart';
import '../../domain/entities/geo_point.dart';
import '../widgets/cloud_logistics_panels.dart';
import '../widgets/cloud_order_labels.dart';
import '../widgets/cloud_session_boundary.dart';

Future<void> openCloudOrderImport(
  BuildContext context,
  CloudAccountSession session,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CloudSessionBoundary(
      session: session,
      builder: (_, lease) => Scaffold(
        appBar: AppBar(title: const Text('Nhập đơn giao hàng từ CSV')),
        body: SafeArea(
          child: CloudOrderImportScreen(session: session, lease: lease),
        ),
      ),
    ),
  ),
);

class _ImportRow {
  _ImportRow(this.source) : error = source.error;
  final CloudCsvRow source;
  Map<String, dynamic>? details, quote;
  String? error, trackingCode;
}

/// Creates real cloud shipping orders from a CSV exported by a sales channel.
/// Every row is geocoded, quoted and created through the same server checks
/// as the manual form; nothing is created before the batch is confirmed.
class CloudOrderImportScreen extends StatefulWidget {
  const CloudOrderImportScreen({
    super.key,
    required this.session,
    required this.lease,
    this.addressService,
  });

  final CloudAccountSession session;
  final CloudSessionLease lease;
  final PhotonAddressService? addressService;

  @override
  State<CloudOrderImportScreen> createState() => _CloudOrderImportScreenState();
}

class _CloudOrderImportScreenState extends State<CloudOrderImportScreen> {
  late final _places = widget.addressService ?? PhotonAddressService();
  List<Map<String, dynamic>> _addresses = [];
  List<_ImportRow> _rows = [];
  String? _pickupId, _fileName, _error, _notice;
  String _payment = 'sender_cash';
  bool _busy = false, _loaded = false;

  bool get _allowed => mounted && widget.lease.valid;
  Map<String, dynamic>? get _pickup =>
      _addresses.where((a) => a['id'] == _pickupId).firstOrNull;
  Iterable<_ImportRow> get _quoted =>
      _rows.where((r) => r.quote != null && r.trackingCode == null);

  @override
  void initState() {
    super.initState();
    widget.lease.addListener(_invalidated);
    _loadAddresses();
  }

  @override
  void dispose() {
    widget.lease.removeListener(_invalidated);
    super.dispose();
  }

  void _invalidated() {
    if (widget.lease.valid || !mounted) return;
    setState(() {
      _addresses = [];
      _rows = [];
      _loaded = false;
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy || !_allowed) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (error) {
      if (!_allowed || widget.lease.handleAccessFailure(error)) return;
      setState(
        () => _error = error is FormatException
            ? error.message
            : cloudLogisticsMessage(error, 'Chưa xử lý được tệp CSV.'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadAddresses() => _guard(() async {
    final result = await widget.session.service.request('addresses');
    if (!_allowed) return;
    setState(() {
      _addresses = (result['addresses'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _pickupId =
          (_addresses.where((a) => a['is_default'] == true).firstOrNull ??
                  _addresses.firstOrNull)?['id']
              as String?;
      _loaded = true;
    });
  });

  Future<void> _pickFile() => _guard(() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (file == null || !_allowed) return;
    if (await file.length() > 1000000) {
      throw const FormatException('Tệp CSV tối đa 1 MB.');
    }
    final String content;
    try {
      content = utf8.decode(await file.readAsBytes());
    } on FormatException {
      throw const FormatException('Tệp CSV cần mã hóa UTF-8.');
    }
    final parsed = parseCloudOrderCsv(content);
    if (!_allowed) return;
    setState(() {
      _fileName = file.name;
      _rows = [for (final row in parsed) _ImportRow(row)];
      if (parsed.isEmpty) _notice = 'Tệp không có dòng đơn hàng.';
    });
  });

  Future<void> _quoteAll() => _guard(() async {
    final pickup = _pickup;
    if (pickup == null) {
      throw const FormatException('Chọn địa chỉ lấy hàng trong sổ địa chỉ.');
    }
    final identity = widget.session.service.identityScope;
    final pickupPoint = GeoPoint(
      latitude: (pickup['latitude'] as num).toDouble(),
      longitude: (pickup['longitude'] as num).toDouble(),
    );
    for (final row in _rows.where(
      (r) => r.source.error == null && r.trackingCode == null,
    )) {
      if (!_allowed || identity != widget.session.service.identityScope) {
        return;
      }
      try {
        final point =
            row.source.point ??
            (await _places.search(
              '${row.source.details['dropoff_address']}',
              bias: pickupPoint,
            )).firstOrNull?.point;
        if (point == null) {
          setState(() {
            row.error = 'Không tìm thấy địa chỉ giao trên bản đồ';
            row.quote = null;
          });
          continue;
        }
        final details = {
          ...row.source.details,
          'pickup_address': pickup['full_address'],
          'pickup_lat': pickupPoint.latitude,
          'pickup_lng': pickupPoint.longitude,
          'dropoff_lat': point.latitude,
          'dropoff_lng': point.longitude,
          'payment_method': _payment,
        };
        final quote = await widget.session.service.request(
          'quote',
          body: details,
        );
        if (!_allowed) return;
        setState(() {
          row.details = details;
          row.quote = quote;
          row.error = null;
        });
      } on PublicApiException catch (error) {
        if (widget.lease.handleAccessFailure(error)) return;
        if (!_allowed) return;
        setState(() {
          row.quote = null;
          row.error = cloudLogisticsMessage(error, 'Chưa báo giá được.');
        });
      }
    }
  });

  Future<void> _createAll() async {
    final ready = _quoted.toList();
    if (ready.isEmpty || !_allowed) return;
    final total = ready.fold<num>(
      0,
      (sum, r) => sum + (r.quote!['shipping_fee'] as num),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Xác nhận tạo đơn'),
        content: Text(
          'Tạo ${ready.length} đơn giao hàng với tổng phí '
          '${CurrencyFormatter.formatVnd(total.toDouble())}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Tạo đơn'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    var created = 0;
    await _guard(() async {
      final identity = widget.session.service.identityScope;
      for (final row in ready) {
        if (!_allowed || identity != widget.session.service.identityScope) {
          return;
        }
        try {
          final result = await widget.session.service.command('orders', {
            'details': row.details,
            'pricing_version': row.quote!['pricing_version'],
            'expected_fee': row.quote!['shipping_fee'],
          });
          if (!_allowed) return;
          created++;
          setState(
            () => row.trackingCode =
                '${(result['order'] as Map)['tracking_code']}',
          );
        } on PublicApiException catch (error) {
          if (widget.lease.handleAccessFailure(error)) return;
          if (!_allowed) return;
          setState(() {
            if (error.statusCode == 409) row.quote = null;
            row.error = cloudLogisticsMessage(error, 'Chưa tạo được đơn.');
          });
        }
      }
    });
    if (_allowed) {
      setState(
        () => _notice = 'Đã tạo $created/${ready.length} đơn giao hàng.',
      );
    }
  }

  Widget _row(_ImportRow row) {
    final d = row.source.details;
    final quote = row.quote;
    final status = row.trackingCode != null
        ? 'Đã tạo đơn ${row.trackingCode}'
        : row.error != null
        ? row.error!
        : quote != null
        ? 'Phí ${CurrencyFormatter.formatVnd((quote['shipping_fee'] as num).toDouble())} · ${((quote['distance_meters'] as num) / 1000).toStringAsFixed(1)} km'
        : 'Hợp lệ, chờ báo giá';
    final color = row.trackingCode != null
        ? Colors.green.shade700
        : row.error != null
        ? Theme.of(context).colorScheme.error
        : null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        'Dòng ${row.source.line}: ${d['recipient_name']} · ${d['recipient_phone']}',
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${d['dropoff_address']}'),
          Text(
            '${d['package_description']} · ${d['weight_kg'] ?? '?'} kg · COD ${CurrencyFormatter.formatVnd(((d['cod_amount'] as num?) ?? 0).toDouble())} · '
            '${cloudServiceTypes[d['service_type']] ?? d['service_type']}',
          ),
          Text(status, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final valid = _rows.where((r) => r.source.error == null).length;
    final quoted = _quoted.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Xuất đơn từ sàn TMĐT/POS ra tệp CSV (UTF-8) theo thứ tự cột: '
                  'tên người nhận, số điện thoại, địa chỉ giao, hàng hóa, khối lượng (kg), '
                  'COD, dịch vụ (tùy chọn), vĩ độ và kinh độ giao (tùy chọn). '
                  'Tối đa $cloudCsvMaxRows đơn mỗi lần.',
                ),
                const SizedBox(height: 12),
                if (_loaded && _addresses.isEmpty)
                  const Text(
                    'Thêm địa chỉ lấy hàng vào sổ địa chỉ trước khi nhập đơn.',
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _pickupId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ lấy hàng',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final a in _addresses)
                        DropdownMenuItem(
                          value: '${a['id']}',
                          child: Text(
                            '${a['label']} · ${a['full_address']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            _pickupId = v;
                            for (final r in _rows) {
                              if (r.trackingCode == null) r.quote = null;
                            }
                          }),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _payment,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Trả phí vận chuyển',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'sender_cash',
                      child: Text('Người gửi trả tiền mặt'),
                    ),
                    DropdownMenuItem(
                      value: 'recipient_cash',
                      child: Text('Người nhận trả tiền mặt'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _payment = v!;
                          for (final r in _rows) {
                            if (r.trackingCode == null) r.quote = null;
                          }
                        }),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickFile,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(_fileName ?? 'Chọn tệp CSV'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy || valid == 0 || _pickup == null
                          ? null
                          : _quoteAll,
                      icon: const Icon(Icons.calculate_outlined),
                      label: const Text('Lấy báo giá'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy || quoted == 0 ? null : _createAll,
                      icon: const Icon(Icons.add),
                      label: Text('Tạo $quoted đơn'),
                    ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_notice!),
                  ),
                if (_rows.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_rows.length} dòng · $valid hợp lệ · $quoted đã báo giá',
                  ),
                  for (final row in _rows) ...[_row(row), const Divider()],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
