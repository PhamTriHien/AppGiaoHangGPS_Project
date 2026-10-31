import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/integrations/cloud_orders_service.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/utils/currency_formatter.dart';
import '../screens/cloud_address_book_screen.dart';
import 'cloud_order_labels.dart';
import 'cloud_session_boundary.dart';
import 'photon_address_lookup.dart';

class CloudOrderForm extends StatefulWidget {
  const CloudOrderForm({
    super.key,
    required this.service,
    required this.merchants,
    this.lease,
    this.initialDetails,
    this.embedded = false,
    this.onCreated,
  });
  final CloudOrdersService service;
  final List<Map<String, dynamic>> merchants;
  final CloudSessionLease? lease;
  final Map<String, dynamic>? initialDetails;
  final bool embedded;
  final VoidCallback? onCreated;
  @override
  State<CloudOrderForm> createState() => _CloudOrderFormState();
}

class _CloudOrderFormState extends State<CloudOrderForm> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final key in [
      'pickup_address',
      'dropoff_address',
      'pickup_lat',
      'pickup_lng',
      'dropoff_lat',
      'dropoff_lng',
      'recipient_name',
      'recipient_phone',
      'package_description',
      'weight_kg',
      'cod_amount',
      'length_cm',
      'width_cm',
      'height_cm',
      'declared_value',
      'buyer_note',
      'scheduled_at',
    ])
      key: TextEditingController(),
  };
  final _extraStops =
      <
        ({
          TextEditingController address,
          TextEditingController lat,
          TextEditingController lng,
        })
      >[];
  final _fieldValues = <String, String>{};
  late final _identity = widget.service.identityScope;
  StreamSubscription<AuthState>? _auth;
  bool _invalidated = false;
  late final Future<String> _draft = widget.service.startDraft();
  String _serviceType = 'standard', _payment = 'sender_cash', _merchant = '';
  bool _isRoundTrip = false,
      _preferEv = false,
      _greenFund = false,
      _requirePod = false,
      _requireOtp = false;
  Map<String, dynamic>? _quote;
  bool _busy = false;
  String? _error;

  bool get _sameAccount =>
      !_invalidated &&
      widget.service.signedIn &&
      _identity == widget.service.identityScope &&
      (widget.lease?.valid ?? true);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDetails;
    if (initial != null && _sameAccount) {
      for (final entry in _fields.entries) {
        final value = initial[entry.key];
        if (value is String || value is num && value.isFinite) {
          if (['length_cm', 'width_cm', 'height_cm', 'declared_value'].contains(
                entry.key,
              ) &&
              value is num &&
              value <= 0) {
            continue;
          }
          entry.value.text = '$value';
        }
      }
      if (cloudServiceTypes.containsKey(initial['service_type'])) {
        _serviceType = initial['service_type'] as String;
      }
      if ([
        'sender_cash',
        'recipient_cash',
      ].contains(initial['payment_method'])) {
        _payment = initial['payment_method'] as String;
      }
      _isRoundTrip = initial['is_round_trip'] == true;
      _preferEv = initial['prefer_ev'] == true;
      _greenFund = initial['green_fund'] == true;
      _requirePod = initial['require_pod'] == true;
      _requireOtp = initial['require_otp'] == true;
      if (initial['extra_stops'] is List) {
        for (final raw in (initial['extra_stops'] as List).take(5)) {
          if (raw is Map) {
            _addStop(
              address: '${raw['address'] ?? ''}',
              lat: '${raw['lat'] ?? ''}',
              lng: '${raw['lng'] ?? ''}',
            );
          }
        }
      }
      final merchant = initial['merchant_id'];
      if (merchant is String &&
          widget.merchants.any((row) => row['user_id'] == merchant)) {
        _merchant = merchant;
      }
    }
    for (final controller in _fields.values) {
      controller.addListener(_changed);
    }
    _fieldValues.addAll({
      for (final entry in _fields.entries) entry.key: entry.value.text,
    });
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
  }

  void _addStop({String address = '', String lat = '', String lng = ''}) {
    if (_extraStops.length >= 5) return;
    final stop = (
      address: TextEditingController(text: address)..addListener(_resetQuote),
      lat: TextEditingController(text: lat)..addListener(_resetQuote),
      lng: TextEditingController(text: lng)..addListener(_resetQuote),
    );
    _extraStops.add(stop);
  }

  void _removeStop(int index) {
    final removed = _extraStops.removeAt(index);
    removed.address.removeListener(_resetQuote);
    removed.lat.removeListener(_resetQuote);
    removed.lng.removeListener(_resetQuote);
    removed.address.dispose();
    removed.lat.dispose();
    removed.lng.dispose();
    setState(() => _quote = null);
  }

  void _resetQuote() {
    if (mounted && _quote != null) setState(() => _quote = null);
  }

  void _invalidate() {
    if (!mounted || _invalidated) return;
    _invalidated = true;
    _quote = null;
    for (final controller in _fields.values) {
      controller.clear();
    }
    for (final stop in _extraStops) {
      stop.address.clear();
      stop.lat.clear();
      stop.lng.clear();
    }
    setState(() => _error = 'Tài khoản đã thay đổi. Mở lại form tạo đơn.');
  }

  void _changed() {
    var changed = false;
    for (final entry in _fields.entries) {
      if (_fieldValues[entry.key] != entry.value.text) {
        changed = true;
        _fieldValues[entry.key] = entry.value.text;
      }
    }
    if (changed && mounted && _quote != null) setState(() => _quote = null);
  }

  @override
  void dispose() {
    _auth?.cancel();
    widget.lease?.removeListener(_invalidate);
    for (final controller in _fields.values) {
      controller.removeListener(_changed);
      controller.dispose();
    }
    for (final stop in _extraStops) {
      stop.address.removeListener(_resetQuote);
      stop.lat.removeListener(_resetQuote);
      stop.lng.removeListener(_resetQuote);
      stop.address.dispose();
      stop.lat.dispose();
      stop.lng.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _details() {
    final result = <String, dynamic>{
      for (final key in [
        'pickup_address',
        'dropoff_address',
        'recipient_name',
        'recipient_phone',
        'package_description',
      ])
        key: _fields[key]!.text.trim(),
      for (final key in [
        'pickup_lat',
        'pickup_lng',
        'dropoff_lat',
        'dropoff_lng',
        'weight_kg',
      ])
        key: double.parse(_fields[key]!.text.trim()),
      'cod_amount': int.parse(
        _fields['cod_amount']!.text.trim().isEmpty
            ? '0'
            : _fields['cod_amount']!.text.trim(),
      ),
      'service_type': _serviceType,
      'payment_method': _payment,
      if (_merchant.isNotEmpty) 'merchant_id': _merchant,
    };
    for (final dim in ['length_cm', 'width_cm', 'height_cm']) {
      final raw = _fields[dim]!.text.trim();
      final parsed = double.tryParse(raw);
      if (parsed != null && parsed > 0) result[dim] = parsed;
    }
    final declared = int.tryParse(_fields['declared_value']!.text.trim());
    if (declared != null && declared > 0) result['declared_value'] = declared;
    final note = _fields['buyer_note']!.text.trim();
    if (note.isNotEmpty) result['buyer_note'] = note;
    final scheduled = _fields['scheduled_at']!.text.trim();
    if (scheduled.isNotEmpty) result['scheduled_at'] = scheduled;
    if (_isRoundTrip) result['is_round_trip'] = true;
    if (_preferEv) result['prefer_ev'] = true;
    if (_greenFund) result['green_fund'] = true;
    if (_requirePod) result['require_pod'] = true;
    if (_requireOtp) result['require_otp'] = true;
    if (_extraStops.isNotEmpty) {
      result['extra_stops'] = [
        for (final s in _extraStops)
          {
            'address': s.address.text.trim(),
            'lat': double.parse(s.lat.text.trim()),
            'lng': double.parse(s.lng.text.trim()),
          },
      ];
    }
    return result;
  }

  Future<void> _submit({bool create = false}) async {
    if (_busy || !_form.currentState!.validate()) return;
    if (!_sameAccount) {
      setState(() => _error = 'Tài khoản đã thay đổi. Mở lại form tạo đơn.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final details = _details();
      if (create && _quote != null) {
        final draft = await _draft;
        if (!_sameAccount) {
          throw StateError('Identity changed');
        }
        await widget.service.command('orders', {
          'details': details,
          'pricing_version': _quote!['pricing_version'],
          'expected_fee': _quote!['shipping_fee'],
          'draft_id': draft,
        });
        if (!mounted || !_sameAccount) return;
        await widget.service.completeDraft(draft);
        if (mounted && _sameAccount) {
          if (widget.embedded) {
            widget.onCreated?.call();
          } else {
            Navigator.pop(context, true);
          }
        }
      } else {
        final quote = await widget.service.request('quote', body: details);
        if (mounted && _sameAccount) setState(() => _quote = quote);
      }
    } catch (error) {
      if (mounted && _sameAccount) {
        setState(() {
          _error = error is PublicApiException
              ? error.message
              : 'Không tạo được đơn. Kiểm tra kết nối và thử lại.';
          if (error is PublicApiException && error.statusCode == 409) {
            _quote = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickSchedule() async {
    if (_busy || !_sameAccount) return;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (date == null || !mounted || !_sameAccount) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted || !_sameAccount) return;
    final chosen = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc();
    _fields['scheduled_at']!.text = chosen.toIso8601String();
    setState(() => _quote = null);
  }

  Widget _text(
    String key,
    String label, {
    bool numeric = false,
    bool optional = false,
    int max = 500,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: _fields[key],
      enabled: !_busy && _sameAccount,
      maxLength: max,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      validator: (raw) {
        final value = raw?.trim() ?? '';
        if (key == 'cod_amount') {
          if (value.isEmpty) return null;
          final number = int.tryParse(value);
          return number == null || number < 0 || number > 20000000
              ? 'COD từ 0 đến 20.000.000 đồng'
              : null;
        }
        if (key == 'declared_value') {
          if (value.isEmpty) return null;
          final number = int.tryParse(value);
          return number == null || number < 0 || number > 30000000
              ? 'Khai giá từ 0 đến 30.000.000 đồng'
              : null;
        }
        if (['length_cm', 'width_cm', 'height_cm'].contains(key)) {
          if (value.isEmpty) return null;
          final number = double.tryParse(value);
          return number == null ||
                  !number.isFinite ||
                  number < 0 ||
                  number > 300
              ? 'Kích thước 0–300 cm'
              : null;
        }
        if (key == 'scheduled_at') {
          if (value.isEmpty) return null;
          return DateTime.tryParse(value) == null
              ? 'Thời gian ISO-8601 không hợp lệ'
              : null;
        }
        if (optional && value.isEmpty) return null;
        if (value.isEmpty) return 'Nhập $label';
        if (key == 'recipient_phone' &&
            !RegExp(r'^0[35789][0-9]{8}$').hasMatch(value)) {
          return 'Số điện thoại Việt Nam không hợp lệ';
        }
        if (numeric) {
          final number = double.tryParse(value);
          final maxWeight = _serviceType == 'truck' ? 500 : 30;
          final limit = key.endsWith('_lat')
              ? 90
              : key.endsWith('_lng')
              ? 180
              : maxWeight;
          if (number == null ||
              !number.isFinite ||
              number.abs() > limit ||
              key == 'weight_kg' && number <= 0) {
            return 'Giá trị không hợp lệ';
          }
        }
        return null;
      },
    ),
  );

  Future<void> _chooseAddress(String prefix) async {
    if (!_sameAccount) return;
    final address = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => widget.lease == null
            ? CloudAddressBookScreen(
                service: widget.service,
                selectAddress: true,
              )
            : CloudSessionBoundary(
                session: widget.lease!.session,
                builder: (_, lease) => CloudAddressBookScreen(
                  service: widget.service,
                  selectAddress: true,
                  lease: lease,
                ),
              ),
      ),
    );
    if (!mounted || address == null || !_sameAccount) {
      return;
    }
    _fields['${prefix}_address']!.text = '${address['full_address']}';
    _fields['${prefix}_lat']!.text = '${address['latitude']}';
    _fields['${prefix}_lng']!.text = '${address['longitude']}';
    if (prefix == 'dropoff') {
      _fields['recipient_name']!.text = '${address['recipient_name']}';
      _fields['recipient_phone']!.text = '${address['recipient_phone']}';
    }
    setState(() => _quote = null);
  }

  Widget _address(String prefix, String title) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          tooltip: prefix == 'pickup'
              ? 'Chọn địa chỉ lấy đã lưu'
              : 'Chọn địa chỉ giao đã lưu',
          onPressed: _busy || !_sameAccount
              ? null
              : () => _chooseAddress(prefix),
          icon: const Icon(Icons.contact_mail_outlined),
        ),
      ),
      _text('${prefix}_address', title),
      if (!_busy && _sameAccount)
        PhotonAddressLookup(
          controller: _fields['${prefix}_address']!,
          onSelected: (place) {
            if (!_sameAccount) return;
            _fields['${prefix}_address']!.text = place.address;
            _fields['${prefix}_lat']!.text = '${place.point.latitude}';
            _fields['${prefix}_lng']!.text = '${place.point.longitude}';
          },
        ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: _text('${prefix}_lat', 'Vĩ độ', numeric: true)),
          const SizedBox(width: 12),
          Expanded(child: _text('${prefix}_lng', 'Kinh độ', numeric: true)),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: widget.embedded ? Colors.transparent : null,
    appBar: widget.embedded ? null : AppBar(title: const Text('Tạo đơn hàng')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _address('pickup', 'Địa chỉ lấy hàng'),
                  _address('dropoff', 'Địa chỉ giao hàng'),
                  const Divider(height: 24),
                  _text('recipient_name', 'Tên người nhận', max: 120),
                  _text('recipient_phone', 'Số điện thoại người nhận', max: 10),
                  _text('package_description', 'Hàng hóa', max: 1000),
                  _text('weight_kg', 'Khối lượng (kg)', numeric: true),
                  _text('cod_amount', 'Tiền thu hộ (đồng)', numeric: true),
                  DropdownButtonFormField<String>(
                    initialValue: _serviceType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Dịch vụ',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final entry in cloudServiceTypes.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: _busy || !_sameAccount
                        ? null
                        : (value) => setState(() {
                            _serviceType = value!;
                            _quote = null;
                          }),
                  ),
                  const SizedBox(height: 16),
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
                    onChanged: _busy || !_sameAccount
                        ? null
                        : (value) => setState(() {
                            _payment = value!;
                            _quote = null;
                          }),
                  ),
                  if (widget.merchants.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _merchant,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Cửa hàng xử lý',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Gửi trực tiếp'),
                        ),
                        ...widget.merchants.map(
                          (m) => DropdownMenuItem(
                            value: '${m['user_id']}',
                            child: Text(
                              '${m['full_name']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: _busy || !_sameAccount
                          ? null
                          : (value) => setState(() {
                              _merchant = value!;
                              _quote = null;
                            }),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Tùy chọn nâng cao (Kích thước, Bảo hiểm, Đa điểm dừng, POD/OTP)',
                    ),
                    children: [
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _text(
                              'length_cm',
                              'Dài (cm)',
                              numeric: true,
                              optional: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _text(
                              'width_cm',
                              'Rộng (cm)',
                              numeric: true,
                              optional: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _text(
                              'height_cm',
                              'Cao (cm)',
                              numeric: true,
                              optional: true,
                            ),
                          ),
                        ],
                      ),
                      _text(
                        'declared_value',
                        'Khai giá bảo hiểm (đồng)',
                        numeric: true,
                        optional: true,
                      ),
                      _text(
                        'buyer_note',
                        'Ghi chú giao hàng',
                        optional: true,
                        max: 500,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _text(
                              'scheduled_at',
                              'Hẹn giờ lấy hàng (ISO-8601)',
                              optional: true,
                              max: 64,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Chọn lịch lấy hàng',
                            onPressed: _busy || !_sameAccount
                                ? null
                                : _pickSchedule,
                            icon: const Icon(Icons.schedule),
                          ),
                          if (_fields['scheduled_at']!.text.isNotEmpty)
                            IconButton(
                              tooltip: 'Xóa lịch hẹn',
                              onPressed: _busy || !_sameAccount
                                  ? null
                                  : () {
                                      _fields['scheduled_at']!.clear();
                                      setState(() => _quote = null);
                                    },
                              icon: const Icon(Icons.clear),
                            ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Giao khứ hồi (+60% cước)'),
                        value: _isRoundTrip,
                        onChanged: _busy || !_sameAccount
                            ? null
                            : (v) => setState(() {
                                _isRoundTrip = v;
                                _quote = null;
                              }),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Ưu tiên tài xế xe điện (EV)'),
                        value: _preferEv,
                        onChanged: _busy || !_sameAccount
                            ? null
                            : (v) => setState(() {
                                _preferEv = v;
                                _quote = null;
                              }),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Đóng góp Quỹ Xanh (+1.000 đ)'),
                        value: _greenFund,
                        onChanged: _busy || !_sameAccount
                            ? null
                            : (v) => setState(() {
                                _greenFund = v;
                                _quote = null;
                              }),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Yêu cầu ảnh bằng chứng giao hàng (POD)',
                        ),
                        value: _requirePod,
                        onChanged: _busy || !_sameAccount
                            ? null
                            : (v) => setState(() {
                                _requirePod = v;
                                _quote = null;
                              }),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Yêu cầu mã OTP 6 số người nhận'),
                        value: _requireOtp,
                        onChanged: _busy || !_sameAccount
                            ? null
                            : (v) => setState(() {
                                _requireOtp = v;
                                _quote = null;
                              }),
                      ),
                      for (var i = 0; i < _extraStops.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Điểm dừng trung gian #${i + 1}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Xóa điểm dừng',
                                    onPressed: _busy || !_sameAccount
                                        ? null
                                        : () => _removeStop(i),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                ],
                              ),
                              TextFormField(
                                controller: _extraStops[i].address,
                                enabled: !_busy && _sameAccount,
                                decoration: InputDecoration(
                                  labelText: 'Địa chỉ điểm dừng #${i + 1}',
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (v) =>
                                    (v?.trim().length ?? 0) < 3
                                        ? 'Nhập địa chỉ điểm dừng'
                                        : null,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _extraStops[i].lat,
                                      enabled: !_busy && _sameAccount,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                            signed: true,
                                          ),
                                      decoration: InputDecoration(
                                        labelText: 'Vĩ độ dừng #${i + 1}',
                                        border: const OutlineInputBorder(),
                                      ),
                                      validator: (v) {
                                        final n = double.tryParse(
                                          v?.trim() ?? '',
                                        );
                                        return n == null || n.abs() > 90
                                            ? 'Vĩ độ không hợp lệ'
                                            : null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _extraStops[i].lng,
                                      enabled: !_busy && _sameAccount,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                            signed: true,
                                          ),
                                      decoration: InputDecoration(
                                        labelText: 'Kinh độ dừng #${i + 1}',
                                        border: const OutlineInputBorder(),
                                      ),
                                      validator: (v) {
                                        final n = double.tryParse(
                                          v?.trim() ?? '',
                                        );
                                        return n == null || n.abs() > 180
                                            ? 'Kinh độ không hợp lệ'
                                            : null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      if (_extraStops.length < 5)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _busy || !_sameAccount
                                ? null
                                : () => setState(() {
                                    _addStop();
                                    _quote = null;
                                  }),
                            icon: const Icon(Icons.add_location_alt_outlined),
                            label: const Text(
                              'Thêm điểm dừng trung gian (+5.000 đ)',
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_quote != null) ...[
                    Text(
                      'Phí vận chuyển: ${CurrencyFormatter.formatVnd((_quote!['shipping_fee'] as num).toDouble())}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Cự ly ước tính: ${((_quote!['distance_meters'] as num) / 1000).toStringAsFixed(1)} km',
                    ),
                    if ((_quote!['volumetric_weight_kg'] as num? ?? 0) > 0)
                      Text(
                        'Khối lượng quy đổi thể tích: ${_quote!['volumetric_weight_kg']} kg',
                      ),
                    if ((_quote!['estimated_co2_saved_grams'] as num? ?? 0) > 0)
                      Text(
                        'Ước tính giảm phát thải EV: ${_quote!['estimated_co2_saved_grams']} g CO2',
                      ),
                    if (_quote!['breakdown'] is Map) ...[
                      for (final entry in const {
                        'base_fee': 'Phí 2 km đầu',
                        'distance_fee': 'Phí quãng đường bổ sung',
                        'weight_fee': 'Phụ phí vượt khối lượng',
                        'express_fee': 'Điều chỉnh gói dịch vụ',
                      }.entries)
                        if ((_quote!['breakdown'] as Map)[entry.key] is num)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${entry.value}: ${CurrencyFormatter.formatVnd(((_quote!['breakdown'] as Map)[entry.key] as num).toDouble())}',
                            ),
                          ),
                      for (final entry in const {
                        'stop_fee': 'Phụ phí đa điểm dừng',
                        'round_trip_fee': 'Phụ phí khứ hồi',
                        'insurance_fee': 'Phí bảo hiểm khai giá',
                        'green_fee': 'Đóng góp Quỹ Xanh',
                      }.entries)
                        if (((_quote!['breakdown'] as Map)[entry.key] as num? ??
                                0) >
                            0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${entry.value}: ${CurrencyFormatter.formatVnd(((_quote!['breakdown'] as Map)[entry.key] as num).toDouble())}',
                            ),
                          ),
                    ],
                    const SizedBox(height: 16),
                  ],
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
                  if (_busy) const LinearProgressIndicator(),
                  FilledButton.icon(
                    onPressed: _busy || !_sameAccount
                        ? null
                        : () => _submit(create: _quote != null),
                    icon: Icon(
                      _quote == null ? Icons.calculate_outlined : Icons.add,
                    ),
                    label: Text(
                      _quote == null ? 'Lấy báo giá' : 'Xác nhận tạo đơn',
                    ),
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
