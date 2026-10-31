import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/integrations/cloud_orders_service.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../widgets/photon_address_lookup.dart';

class CloudAddressBookScreen extends StatefulWidget {
  const CloudAddressBookScreen({
    super.key,
    required this.service,
    this.selectAddress = false,
    this.lease,
  });
  final CloudOrdersService service;
  final bool selectAddress;
  final CloudSessionLease? lease;

  @override
  State<CloudAddressBookScreen> createState() => _CloudAddressBookScreenState();
}

class _CloudAddressBookScreenState extends State<CloudAddressBookScreen> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final key in [
      'label',
      'recipient_name',
      'recipient_phone',
      'full_address',
      'latitude',
      'longitude',
    ])
      key: TextEditingController(),
  };
  late final _identity = widget.service.identityScope;
  StreamSubscription<dynamic>? _auth;
  List<Map<String, dynamic>> _addresses = [];
  Map<String, dynamic>? _editing;
  String? _draftId, _error;
  bool _busy = false, _showEditor = false, _default = false;
  bool _invalidated = false;

  bool get _sameAccount =>
      !_invalidated &&
      widget.service.signedIn &&
      _identity == widget.service.identityScope &&
      (widget.lease?.valid ?? true);

  @override
  void initState() {
    super.initState();
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
    unawaited(_load());
  }

  void _invalidate() {
    if (!mounted || _invalidated) return;
    _invalidated = true;
    setState(() {
      _addresses = [];
      _editing = null;
      _draftId = null;
      _showEditor = false;
      for (final field in _fields.values) {
        field.clear();
      }
      _error = 'Tài khoản đã thay đổi. Mở lại sổ địa chỉ.';
    });
  }

  @override
  void dispose() {
    _auth?.cancel();
    widget.lease?.removeListener(_invalidate);
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  String _message(Object error) => error is PublicApiException
      ? (error.statusCode == 503
            ? 'Sổ địa chỉ tạm thời chưa khả dụng.'
            : error.message)
      : 'Không hoàn tất được yêu cầu. Vui lòng thử lại.';

  Future<void> _run(Future<Map<String, dynamic>> Function() operation) async {
    if (_busy || !_sameAccount) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await operation();
      if (!mounted || !_sameAccount) return;
      setState(() {
        _addresses = (response['addresses'] as List? ?? [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
      });
    } catch (error) {
      if (mounted &&
          _sameAccount &&
          error is PublicApiException &&
          [401, 403].contains(error.statusCode)) {
        _invalidate();
        widget.lease?.session.invalidateVerification();
      }
      if (mounted && _sameAccount) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() => widget.service.request('addresses'));

  void _edit([Map<String, dynamic>? address]) {
    if (!_sameAccount) return;
    setState(() {
      _editing = address;
      _draftId = address?['id'] as String? ?? const Uuid().v4();
      _showEditor = true;
      _default = address?['is_default'] == true || _addresses.isEmpty;
      _error = null;
      for (final field in _fields.entries) {
        field.value.text = '${address?[field.key] ?? ''}';
      }
    });
  }

  Future<void> _save() async {
    if (!_sameAccount || !_form.currentState!.validate()) return;
    final details = <String, dynamic>{
      for (final key in [
        'label',
        'recipient_name',
        'recipient_phone',
        'full_address',
      ])
        key: _fields[key]!.text.trim(),
      'latitude': double.parse(_fields['latitude']!.text.trim()),
      'longitude': double.parse(_fields['longitude']!.text.trim()),
      'is_default': _default,
    };
    await _run(
      () => widget.service.request(
        'addresses/$_draftId',
        body: {
          'details': details,
          if (_editing != null) 'version': _editing!['version'],
        },
      ),
    );
    if (mounted && _sameAccount && _error == null) {
      setState(() => _showEditor = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> address) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa địa chỉ?'),
        content: Text('${address['label']}\n${address['full_address']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && _sameAccount) {
      await _run(
        () => widget.service.request(
          'addresses/${address['id']}',
          body: {'delete': true, 'version': address['version']},
        ),
      );
    }
  }

  Widget _field(String key, String label, {int max = 120}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: _fields[key],
      enabled: !_busy && _sameAccount,
      maxLength: max,
      keyboardType: ['latitude', 'longitude'].contains(key)
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : key == 'recipient_phone'
          ? TextInputType.phone
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
      validator: (text) {
        final value = text?.trim() ?? '';
        if (value.isEmpty) return 'Vui lòng nhập $label.';
        if (key == 'recipient_phone' &&
            !RegExp(r'^0[35789][0-9]{8}$').hasMatch(value)) {
          return 'Số điện thoại Việt Nam không hợp lệ.';
        }
        if (key == 'full_address' && value.length < 5) {
          return 'Địa chỉ quá ngắn.';
        }
        if (['latitude', 'longitude'].contains(key)) {
          final number = double.tryParse(value);
          if (number == null ||
              !number.isFinite ||
              number.abs() > (key == 'latitude' ? 90 : 180)) {
            return 'Tọa độ không hợp lệ.';
          }
        }
        return null;
      },
    ),
  );

  Widget _editor() => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field('label', 'Tên gợi nhớ', max: 60),
        _field('recipient_name', 'Tên người nhận'),
        _field('recipient_phone', 'Số điện thoại', max: 10),
        _field('full_address', 'Địa chỉ', max: 500),
        if (!_busy && _sameAccount)
          PhotonAddressLookup(
            controller: _fields['full_address']!,
            onSelected: (place) {
              if (!_sameAccount) return;
              _fields['full_address']!.text = place.address;
              _fields['latitude']!.text = '${place.point.latitude}';
              _fields['longitude']!.text = '${place.point.longitude}';
            },
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _field('latitude', 'Vĩ độ')),
            const SizedBox(width: 12),
            Expanded(child: _field('longitude', 'Kinh độ')),
          ],
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Địa chỉ mặc định'),
          value: _default,
          onChanged:
              _busy || _editing?['is_default'] == true || _addresses.isEmpty
              ? null
              : (value) => setState(() => _default = value!),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy || !_sameAccount ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Lưu địa chỉ'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _showEditor = false),
              child: const Text('Quay lại'),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.selectAddress ? 'Chọn địa chỉ' : 'Sổ địa chỉ'),
      actions: [
        IconButton(
          tooltip: 'Tải lại địa chỉ',
          onPressed: _busy || !_sameAccount ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Thêm địa chỉ',
          onPressed: _busy || !_sameAccount || _addresses.length >= 25
              ? null
              : _edit,
          icon: const Icon(Icons.add_location_alt_outlined),
        ),
      ],
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy) const LinearProgressIndicator(),
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
                if (_showEditor && _sameAccount)
                  _editor()
                else if (_sameAccount) ...[
                  if (!_busy && _addresses.isEmpty && _error == null)
                    const Text('Chưa có địa chỉ đã lưu.'),
                  for (final address in _addresses) ...[
                    Text(
                      '${address['label']}${address['is_default'] == true ? ' · Mặc định' : ''}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${address['recipient_name']} · ${address['recipient_phone']}',
                    ),
                    Text('${address['full_address']}'),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (widget.selectAddress)
                          FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () {
                                    if (_sameAccount) {
                                      Navigator.pop(context, address);
                                    }
                                  },
                            icon: const Icon(Icons.check),
                            label: const Text('Chọn địa chỉ'),
                          ),
                        IconButton(
                          tooltip: 'Sửa địa chỉ',
                          onPressed: _busy ? null : () => _edit(address),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Xóa địa chỉ',
                          onPressed: _busy ? null : () => _delete(address),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    const Divider(),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
