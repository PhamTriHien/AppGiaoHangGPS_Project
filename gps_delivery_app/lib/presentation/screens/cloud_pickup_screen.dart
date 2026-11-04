import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/cloud_logistics_panels.dart';
import '../widgets/cloud_order_labels.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/ghst_button_icon.dart';

Future<void> openCloudPickups(
  BuildContext context,
  CloudAccountSession session, {
  bool operator = false,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CloudSessionBoundary(
      session: session,
      operator: operator,
      builder: (_, lease) => Scaffold(
        appBar: AppBar(title: const Text('Lịch xe thu gom')),
        body: SafeArea(
          child: CloudPickupScreen(
            session: session,
            lease: lease,
            operator: operator,
          ),
        ),
      ),
    ),
  ),
);

/// Bulk pickups: merchants request a vehicle at an address-book warehouse,
/// operators dispatch an approved driver and the driver sees the assignment.
class CloudPickupScreen extends StatefulWidget {
  const CloudPickupScreen({
    super.key,
    required this.session,
    required this.lease,
    this.operator = false,
  });

  final CloudAccountSession session;
  final CloudSessionLease lease;
  final bool operator;

  @override
  State<CloudPickupScreen> createState() => _CloudPickupScreenState();
}

class _CloudPickupScreenState extends State<CloudPickupScreen> {
  final _form = GlobalKey<FormState>();
  final _count = TextEditingController();
  final _weight = TextEditingController();
  final _note = TextEditingController();
  List<Map<String, dynamic>> _pickups = [], _drivers = [], _addresses = [];
  final _selectedDriver = <String, String>{};
  String? _addressId;
  String _vehicle = 'van_500kg', _slot = 'afternoon';
  DateTime? _date;
  bool _busy = false, _loaded = false;
  String? _error, _notice;
  int _generation = 0;

  bool get _allowed => mounted && widget.lease.valid;
  bool get _merchant => !widget.operator && widget.session.hasRole('merchant');

  @override
  void initState() {
    super.initState();
    widget.lease.addListener(_invalidated);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    widget.lease.removeListener(_invalidated);
    _count.dispose();
    _weight.dispose();
    _note.dispose();
    super.dispose();
  }

  void _invalidated() {
    if (widget.lease.valid || !mounted) return;
    _generation++;
    setState(() {
      _pickups = [];
      _drivers = [];
      _addresses = [];
      _loaded = false;
    });
  }

  List<Map<String, dynamic>> _rows(dynamic raw) => (raw as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  Future<void> _load() async {
    if (!_allowed) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = widget.session.service;
      final list = await service.logistics('pickup_list');
      final addresses = _merchant
          ? _rows((await service.request('addresses'))['addresses'])
          : <Map<String, dynamic>>[];
      if (!_allowed || generation != _generation) return;
      setState(() {
        _pickups = _rows(list['pickups']);
        _drivers = _rows(list['drivers']);
        _addresses = addresses;
        if (!_addresses.any((a) => a['id'] == _addressId)) {
          _addressId =
              (_addresses.where((a) => a['is_default'] == true).firstOrNull ??
                      _addresses.firstOrNull)?['id']
                  as String?;
        }
        _loaded = true;
      });
    } catch (error) {
      if (!_allowed || generation != _generation) return;
      if (widget.lease.handleAccessFailure(error)) return;
      setState(
        () => _error = cloudLogisticsMessage(
          error,
          'Chưa tải được lịch xe thu gom.',
        ),
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy || !_allowed) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      if (!_allowed) return;
      setState(() => _notice = success);
    } catch (error) {
      if (!_allowed || widget.lease.handleAccessFailure(error)) return;
      setState(
        () => _error = cloudLogisticsMessage(
          error,
          'Chưa xử lý được phiếu thu gom. Vui lòng thử lại.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (_allowed && _error == null) await _load();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 14)),
    );
    if (chosen != null && _allowed) setState(() => _date = chosen);
  }

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    if (_addressId == null || _date == null) {
      setState(() => _error = 'Chọn kho lấy hàng và ngày thu gom.');
      return;
    }
    final payload = {
      'address_id': _addressId,
      'vehicle_type': _vehicle,
      'pickup_date': _isoDate(_date!),
      'time_slot': _slot,
      'package_count': int.parse(_count.text.trim()),
      'total_weight_kg': double.parse(_weight.text.trim()),
      'note': _note.text.trim(),
    };
    await _run(() async {
      await widget.session.service.command('logistics/pickup_create', payload);
      if (!_allowed) return;
      _count.clear();
      _weight.clear();
      _note.clear();
    }, 'Đã tạo phiếu hẹn xe thu gom.');
  }

  Widget _requestForm() => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GhstAiIcon(
              style: Icon3dStyle.cargoTruck,
              size: 42,
              borderRadius: 12,
              selected: true,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đặt lịch xe thu gom số lượng lớn',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Hẹn xe đến kho trong sổ địa chỉ để lấy nhiều kiện cùng lúc theo khung giờ.',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loaded && _addresses.isEmpty)
          const Text('Thêm địa chỉ kho vào sổ địa chỉ trước khi đặt lịch.')
        else
          DropdownButtonFormField<String>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), initialValue: _addressId, isExpanded: true, decoration: const InputDecoration(
              labelText: 'Kho lấy hàng',
              border: OutlineInputBorder(),
            ), items: [
              for (final a in _addresses)
                DropdownMenuItem(
                  value: '${a['id']}',
                  child: Text(
                    '${a['label']} · ${a['full_address']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ], onChanged: _busy ? null : (v) => setState(() => _addressId = v),),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), initialValue: _vehicle, isExpanded: true, decoration: const InputDecoration(
            labelText: 'Loại xe thu gom',
            border: OutlineInputBorder(),
          ), items: [
            for (final v in cloudPickupVehicles.entries)
              DropdownMenuItem(value: v.key, child: Text(v.value)),
          ], onChanged: _busy
              ? null
              : (v) => setState(() {
                  _vehicle = v!;
                  _form.currentState?.validate();
                }),),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), initialValue: _slot, isExpanded: true, decoration: const InputDecoration(
            labelText: 'Khung giờ hẹn lấy',
            border: OutlineInputBorder(),
          ), items: [
            for (final s in cloudPickupSlots.entries)
              DropdownMenuItem(value: s.key, child: Text(s.value)),
          ], onChanged: _busy ? null : (v) => setState(() => _slot = v!),),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickDate,
          icon: const GhstButtonIcon(Icons.event_outlined),
          label: Text(
            _date == null
                ? 'Chọn ngày thu gom'
                : 'Ngày thu gom: ${_date!.day}/${_date!.month}/${_date!.year}',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _count,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số lượng kiện',
                  border: OutlineInputBorder(),
                ),
                validator: (raw) {
                  final value = int.tryParse(raw?.trim() ?? '');
                  return value == null || value < 1 || value > 1000
                      ? 'Từ 1 đến 1.000 kiện'
                      : null;
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _weight,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Tổng khối lượng', suffixText: 'kg',
                  border: OutlineInputBorder(),
                ),
                validator: (raw) {
                  final value = double.tryParse(raw?.trim() ?? '');
                  final capacity = cloudPickupVehicleCapacityKg[_vehicle]!;
                  if (value == null ||
                      !value.isFinite ||
                      value <= 0 ||
                      value > capacity) {
                    return 'Lớn hơn 0 và tối đa $capacity kg';
                  }
                  return (value * 10).roundToDouble() != value * 10
                      ? 'Tối đa 1 chữ số thập phân'
                      : null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _note,
          enabled: !_busy,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Ghi chú kho',
            border: OutlineInputBorder(),
          ),
        ),
        FilledButton.icon(
          onPressed: _busy || _addresses.isEmpty ? null : _create,
          icon: const GhstButtonIcon(Icons.local_shipping_outlined),
          label: const Text('Đặt lịch xe thu gom'),
        ),
      ],
    ),
  );

  Widget _pickup(Map<String, dynamic> p) {
    final id = '${p['id']}';
    final date = DateTime.tryParse('${p['pickup_date']}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${cloudPickupVehicles[p['vehicle_type']] ?? p['vehicle_type']} · '
            '${cloudPickupSlots[p['time_slot']] ?? p['time_slot']}'
            '${date == null ? '' : ' · ${date.day}/${date.month}/${date.year}'}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (widget.operator ||
              p['merchant_id'] != widget.session.service.userId)
            Text('Cửa hàng: ${p['merchant_name']}'),
          Text('Kho: ${p['pickup_address']}'),
          Text('Liên hệ: ${p['contact_name']} · ${p['contact_phone']}'),
          Text('${p['package_count']} kiện · ${p['total_weight_kg']} kg'),
          if ('${p['note'] ?? ''}'.isNotEmpty) Text('Ghi chú: ${p['note']}'),
          Text(
            p['status'] == 'assigned'
                ? 'Đã điều xe: ${p['driver_name'] ?? ''}'
                : cloudPickupStatuses[p['status']] ?? '${p['status']}',
            style: TextStyle(
              color: p['status'] == 'assigned'
                  ? GhstThemeTokens.of(context).emerald.foreground
                  : GhstThemeTokens.of(context).amber.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'Tạo lúc ${cloudDate(p['created_at'])}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (widget.operator && p['status'] == 'requested') ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: DropdownButtonFormField<String>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), initialValue: _selectedDriver[id], isExpanded: true, decoration: const InputDecoration(
                      labelText: 'Tài xế đã duyệt',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ), items: [
                      for (final d in _drivers)
                        DropdownMenuItem(
                          value: '${d['user_id']}',
                          child: Text(
                            '${d['full_name']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ], onChanged: _busy
                        ? null
                        : (v) => setState(() => _selectedDriver[id] = v!),),
                ),
                FilledButton.icon(
                  onPressed: _busy || _selectedDriver[id] == null
                      ? null
                      : () => _run(
                          () => widget.session.service.logistics(
                            'pickup_assign',
                            {
                              'id': id,
                              'version': p['version'],
                              'driver_id': _selectedDriver[id],
                            },
                          ),
                          'Đã điều tài xế nhận phiếu thu gom.',
                        ),
                  icon: const GhstButtonIcon(Icons.local_shipping_outlined),
                  label: const Text('Điều xe thu gom'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_merchant) ...[_requestForm(), const Divider(height: 32)],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.operator
                            ? 'Phiếu thu gom toàn mạng'
                            : 'Phiếu thu gom của bạn',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tải lại',
                      onPressed: _busy ? null : _load,
                      icon: const GhstButtonIcon(Icons.refresh),
                    ),
                  ],
                ),
                if (_busy) const LinearProgressIndicator(),
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
                if (_loaded && _pickups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Chưa có phiếu thu gom.'),
                  ),
                for (final p in _pickups) ...[
                  _pickup(p),
                  const Divider(height: 1),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
