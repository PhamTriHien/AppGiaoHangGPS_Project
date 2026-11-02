import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env_config.dart';
import '../../core/gps/stop_order_optimizer.dart';
import '../../core/integrations/cloud_orders_service.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/integrations/photon_address_service.dart';
import '../../core/network/public_json_api.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import '../screens/cloud_address_book_screen.dart';
import 'cloud_logistics_panels.dart';
import 'cloud_order_labels.dart';
import 'cloud_session_boundary.dart';
import 'photon_address_lookup.dart';
import 'system_state_screens.dart';

class _ExtraStopField {
  _ExtraStopField({required this.address, this.point});
  final TextEditingController address;
  GeoPoint? point;
}

class CloudOrderForm extends StatefulWidget {
  const CloudOrderForm({
    super.key,
    required this.service,
    required this.merchants,
    this.lease,
    this.initialDetails,
    this.embedded = false,
    this.onCreated,
    this.addressService,
  });
  final CloudOrdersService service;
  final List<Map<String, dynamic>> merchants;
  final CloudSessionLease? lease;
  final Map<String, dynamic>? initialDetails;
  final bool embedded;
  final VoidCallback? onCreated;
  final PhotonAddressService? addressService;

  @override
  State<CloudOrderForm> createState() => _CloudOrderFormState();
}

class _CloudOrderFormState extends State<CloudOrderForm> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final key in [
      'pickup_address',
      'dropoff_address',
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
  final _extraStops = <_ExtraStopField>[];
  final _fieldValues = <String, String>{};
  final _reverseGeneration = <String, int>{};
  late final _identity = widget.service.identityScope;
  StreamSubscription<AuthState>? _auth;
  bool _invalidated = false;
  late final Future<String> _draft = widget.service.startDraft();
  GeoPoint? _pickupPoint;
  GeoPoint? _dropoffPoint;
  GeoPoint? _focusedMapPoint;
  String _activeMapTarget = 'pickup';
  bool _reverseBusy = false;
  String _serviceType = 'standard', _payment = 'sender_cash', _merchant = '';
  bool _isRoundTrip = false,
      _preferEv = false,
      _greenFund = false,
      _requirePod = false,
      _requireOtp = false;
  Map<String, dynamic>? _quote;
  Map<String, Map<String, dynamic>>? _serviceEta;
  bool _busy = false;
  String? _error, _routeNotice;

  bool get _sameAccount =>
      !_invalidated &&
      widget.service.signedIn &&
      _identity == widget.service.identityScope &&
      (widget.lease?.valid ?? true);

  bool get _canCallAddressApi =>
      widget.addressService != null || EnvConfig.deliveryApiBaseUrl.isNotEmpty;

  PhotonAddressService get _effectiveAddressService =>
      widget.addressService ?? PhotonAddressService();

  static GeoPoint? _parsePoint(Object? rawLat, Object? rawLng) {
    final lat = rawLat is num
        ? rawLat.toDouble()
        : double.tryParse('${rawLat ?? ''}'.trim());
    final lng = rawLng is num
        ? rawLng.toDouble()
        : double.tryParse('${rawLng ?? ''}'.trim());
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return null;
    }
    return GeoPoint(latitude: lat, longitude: lng);
  }

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
      _pickupPoint = _parsePoint(initial['pickup_lat'], initial['pickup_lng']);
      _dropoffPoint = _parsePoint(
        initial['dropoff_lat'],
        initial['dropoff_lng'],
      );
      _focusedMapPoint = _dropoffPoint ?? _pickupPoint;
      if (_pickupPoint != null && _dropoffPoint == null) {
        _activeMapTarget = 'dropoff';
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
              point: _parsePoint(raw['lat'], raw['lng']),
            );
          }
        }
      }
      final merchant = initial['merchant_id'];
      if (merchant is String &&
          widget.merchants.any((row) => row['user_id'] == merchant)) {
        _merchant = merchant;
      }
      if (_dropoffPoint != null &&
          _fields['dropoff_address']!.text.trim().isEmpty &&
          _canCallAddressApi) {
        unawaited(_reverseTarget('dropoff', _dropoffPoint!));
      }
      if (_pickupPoint != null &&
          _fields['pickup_address']!.text.trim().isEmpty &&
          _canCallAddressApi) {
        unawaited(_reverseTarget('pickup', _pickupPoint!));
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

  void _addStop({String address = '', GeoPoint? point}) {
    if (_extraStops.length >= 5) return;
    final index = _extraStops.length;
    final stop = _ExtraStopField(
      address: TextEditingController(text: address)..addListener(_resetQuote),
      point: point,
    );
    _extraStops.add(stop);
    if (point == null && address.isEmpty) {
      _activeMapTarget = 'stop:$index';
    }
  }

  void _removeStop(int index) {
    final removed = _extraStops.removeAt(index);
    removed.address.removeListener(_resetQuote);
    removed.address.dispose();
    if (_activeMapTarget.startsWith('stop:')) {
      _activeMapTarget = _pickupPoint == null ? 'pickup' : 'dropoff';
    }
    setState(() => _quote = null);
  }

  void _resetQuote() {
    if (mounted && _quote != null) setState(() => _quote = null);
  }

  void _invalidate() {
    if (!mounted || _invalidated) return;
    _invalidated = true;
    _quote = null;
    _pickupPoint = null;
    _dropoffPoint = null;
    _focusedMapPoint = null;
    _reverseGeneration.clear();
    for (final controller in _fields.values) {
      controller.clear();
    }
    for (final stop in _extraStops) {
      stop.address.clear();
      stop.point = null;
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
      stop.address.dispose();
    }
    super.dispose();
  }

  List<GeoPoint> get _mapRoutePoints {
    if (_pickupPoint == null || _dropoffPoint == null) return const [];
    return [
      _pickupPoint!,
      for (final stop in _extraStops)
        if (stop.point != null) stop.point!,
      _dropoffPoint!,
    ];
  }

  GeoPoint? get _singlePinnedPoint {
    if (_pickupPoint != null) return _pickupPoint;
    if (_dropoffPoint != null) return _dropoffPoint;
    for (final stop in _extraStops) {
      if (stop.point != null) return stop.point;
    }
    return null;
  }

  String get _singlePinnedLabel {
    if (_pickupPoint != null) return 'Điểm lấy [A]';
    if (_dropoffPoint != null) return 'Điểm giao [B]';
    return 'Điểm dừng';
  }

  String get _activeTargetDescription {
    if (_activeMapTarget == 'pickup') return 'Điểm lấy hàng [A]';
    if (_activeMapTarget == 'dropoff') return 'Điểm giao hàng [B]';
    if (_activeMapTarget.startsWith('stop:')) {
      final idx = int.tryParse(_activeMapTarget.substring(5)) ?? 0;
      return 'Điểm dừng trung gian #${idx + 1}';
    }
    return 'Điểm lấy hàng [A]';
  }

  TextEditingController? _controllerForTarget(String target) {
    if (target == 'pickup') return _fields['pickup_address'];
    if (target == 'dropoff') return _fields['dropoff_address'];
    if (target.startsWith('stop:')) {
      final idx = int.tryParse(target.substring(5));
      if (idx != null && idx >= 0 && idx < _extraStops.length) {
        return _extraStops[idx].address;
      }
    }
    return null;
  }

  void _assignTargetPoint(String target, GeoPoint point) {
    if (target == 'pickup') {
      _pickupPoint = point;
    } else if (target == 'dropoff') {
      _dropoffPoint = point;
    } else if (target.startsWith('stop:')) {
      final idx = int.tryParse(target.substring(5));
      if (idx != null && idx >= 0 && idx < _extraStops.length) {
        _extraStops[idx].point = point;
      }
    }
  }

  Future<void> _reverseTarget(String target, GeoPoint point) async {
    if (!_canCallAddressApi || !_sameAccount) return;
    final gen = (_reverseGeneration[target] ?? 0) + 1;
    _reverseGeneration[target] = gen;
    if (mounted) setState(() => _reverseBusy = true);
    try {
      final address = await _effectiveAddressService.reverseGeocode(point);
      if (!mounted || !_sameAccount || _reverseGeneration[target] != gen) {
        return;
      }
      final controller = _controllerForTarget(target);
      if (controller != null && address.isNotEmpty) {
        controller.text = address;
      }
    } catch (_) {
    } finally {
      if (mounted && _reverseGeneration[target] == gen) {
        setState(() => _reverseBusy = false);
      }
    }
  }

  void _handleMapTap(GeoPoint point) {
    if (_busy || !_sameAccount) return;
    final target = _activeMapTarget;
    setState(() {
      _assignTargetPoint(target, point);
      _focusedMapPoint = point;
      _quote = null;
      _error = null;
      if (target == 'pickup' && _dropoffPoint == null) {
        _activeMapTarget = 'dropoff';
      }
    });
    unawaited(_reverseTarget(target, point));
  }

  Future<void> _useCurrentGpsForActiveTarget() async {
    if (_busy || !_sameAccount) return;
    final target = _activeMapTarget;
    final pos = await AppStateStore.instance.acquireCustomerDeviceGps();
    if (!mounted || !_sameAccount) return;
    if (pos == null) {
      setState(() => _error = AppStateStore.instance.liveGpsStatusMessage);
      return;
    }
    final liveAddr = AppStateStore.instance.liveDeviceAddress.trim();
    final controller = _controllerForTarget(target);
    setState(() {
      _assignTargetPoint(target, pos);
      _focusedMapPoint = pos;
      _quote = null;
      _error = null;
      if (controller != null && liveAddr.isNotEmpty) {
        controller.text = liveAddr;
      }
      if (target == 'pickup' && _dropoffPoint == null) {
        _activeMapTarget = 'dropoff';
      }
    });
    if (liveAddr.isEmpty) {
      unawaited(_reverseTarget(target, pos));
    }
  }

  Future<String?> _ensureCoordinatesResolved() async {
    Future<GeoPoint?> resolveOne(String text) async {
      if (!_canCallAddressApi) return null;
      final places = await _effectiveAddressService.search(
        text,
        bias: _focusedMapPoint ?? _pickupPoint ?? _dropoffPoint,
      );
      return places.isEmpty ? null : places.first.point;
    }

    if (_pickupPoint == null) {
      final resolved = await resolveOne(_fields['pickup_address']!.text);
      if (!_sameAccount) return 'Tài khoản đã thay đổi. Mở lại form tạo đơn.';
      if (resolved == null) {
        return 'Chưa ghim được Địa chỉ lấy hàng trên Google Map. Vui lòng chọn gợi ý tìm kiếm hoặc chạm trực tiếp lên bản đồ.';
      }
      _pickupPoint = resolved;
      _focusedMapPoint = resolved;
    }
    if (_dropoffPoint == null) {
      final resolved = await resolveOne(_fields['dropoff_address']!.text);
      if (!_sameAccount) return 'Tài khoản đã thay đổi. Mở lại form tạo đơn.';
      if (resolved == null) {
        return 'Chưa ghim được Địa chỉ giao hàng trên Google Map. Vui lòng chọn gợi ý tìm kiếm hoặc chạm trực tiếp lên bản đồ.';
      }
      _dropoffPoint = resolved;
      _focusedMapPoint = resolved;
    }
    for (var i = 0; i < _extraStops.length; i++) {
      if (_extraStops[i].point == null) {
        final resolved = await resolveOne(_extraStops[i].address.text);
        if (!_sameAccount) return 'Tài khoản đã thay đổi. Mở lại form tạo đơn.';
        if (resolved == null) {
          return 'Chưa ghim được Điểm dừng #${i + 1} trên Google Map. Vui lòng chọn gợi ý tìm kiếm hoặc chạm trực tiếp lên bản đồ.';
        }
        _extraStops[i].point = resolved;
      }
    }
    return null;
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
      'pickup_lat': _pickupPoint!.latitude,
      'pickup_lng': _pickupPoint!.longitude,
      'dropoff_lat': _dropoffPoint!.latitude,
      'dropoff_lng': _dropoffPoint!.longitude,
      'weight_kg': double.parse(_fields['weight_kg']!.text.trim()),
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
            'lat': s.point!.latitude,
            'lng': s.point!.longitude,
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
      final missingError = await _ensureCoordinatesResolved();
      if (!mounted || !_sameAccount) return;
      if (missingError != null) {
        setState(() {
          _error = missingError;
          _quote = null;
        });
        return;
      }
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
        unawaited(_loadServiceEta());
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

  Future<void> _loadServiceEta() async {
    if (_serviceEta != null) return;
    try {
      final result = await widget.service.logistics('service_eta');
      if (!mounted || !_sameAccount) return;
      setState(
        () => _serviceEta = {
          for (final row
              in (result['services'] as List? ?? const []).whereType<Map>())
            '${row['service_type']}': Map<String, dynamic>.from(row),
        },
      );
    } catch (_) {}
  }

  Future<void> _optimizeStops() async {
    if (_busy || !_sameAccount) return;
    setState(() {
      _busy = true;
      _error = null;
      _routeNotice = null;
    });
    try {
      final missing = await _ensureCoordinatesResolved();
      if (!mounted || !_sameAccount) return;
      if (missing != null) {
        setState(() => _error = missing);
        return;
      }
      final distances = await _effectiveAddressService.roadDistances([
        _pickupPoint!,
        for (final stop in _extraStops) stop.point!,
        _dropoffPoint!,
      ]);
      if (!mounted || !_sameAccount) return;
      final plan = bestStopOrder(distances);
      String km(double meters) => (meters / 1000).toStringAsFixed(1);
      setState(() {
        if (plan.improves) {
          final reordered = [for (final i in plan.order) _extraStops[i]];
          _extraStops
            ..clear()
            ..addAll(reordered);
          _quote = null;
          if (_activeMapTarget.startsWith('stop:')) {
            _activeMapTarget = 'dropoff';
          }
        }
        _routeNotice = plan.improves
            ? 'Đã sắp xếp lại điểm dừng: ${km(plan.currentMeters)} km → ${km(plan.optimizedMeters)} km đường bộ.'
            : 'Thứ tự hiện tại đã ngắn nhất (${km(plan.currentMeters)} km đường bộ).';
      });
    } catch (error) {
      if (mounted && _sameAccount) {
        setState(
          () => _error = error is PublicApiException
              ? error.message
              : 'Chưa tính được quãng đường thực tế giữa các điểm.',
        );
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
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: _fields[key],
      enabled: !_busy && _sameAccount,
      maxLength: max,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: false)
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
          if (number == null ||
              !number.isFinite ||
              number.abs() > maxWeight ||
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
    final point = _parsePoint(address['latitude'], address['longitude']);
    _fields['${prefix}_address']!.text = '${address['full_address']}';
    if (prefix == 'dropoff') {
      _fields['recipient_name']!.text = '${address['recipient_name']}';
      _fields['recipient_phone']!.text = '${address['recipient_phone']}';
    }
    setState(() {
      if (point != null) {
        if (prefix == 'pickup') {
          _pickupPoint = point;
        } else {
          _dropoffPoint = point;
        }
        _focusedMapPoint = point;
      }
      _quote = null;
      _error = null;
    });
  }

  Widget _googleMapPicker() => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.map_outlined, size: 19),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Chọn địa chỉ trực tiếp trên Google Map',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Ghim điểm lấy [A]'),
              selected: _activeMapTarget == 'pickup',
              onSelected: _busy || !_sameAccount
                  ? null
                  : (_) => setState(() {
                      _activeMapTarget = 'pickup';
                      if (_pickupPoint != null) _focusedMapPoint = _pickupPoint;
                    }),
            ),
            ChoiceChip(
              label: const Text('Ghim điểm giao [B]'),
              selected: _activeMapTarget == 'dropoff',
              onSelected: _busy || !_sameAccount
                  ? null
                  : (_) => setState(() {
                      _activeMapTarget = 'dropoff';
                      if (_dropoffPoint != null) {
                        _focusedMapPoint = _dropoffPoint;
                      }
                    }),
            ),
            for (var i = 0; i < _extraStops.length; i++)
              ChoiceChip(
                label: Text('Ghim điểm dừng #${i + 1}'),
                selected: _activeMapTarget == 'stop:$i',
                onSelected: _busy || !_sameAccount
                    ? null
                    : (_) => setState(() {
                        _activeMapTarget = 'stop:$i';
                        if (_extraStops[i].point != null) {
                          _focusedMapPoint = _extraStops[i].point;
                        }
                      }),
              ),
            ActionChip(
              avatar: const Icon(Icons.my_location_outlined, size: 16),
              label: const Text('Vị trí hiện tại (GPS)'),
              onPressed: _busy || !_sameAccount
                  ? null
                  : _useCurrentGpsForActiveTarget,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _reverseBusy
              ? 'Đang tự động nhận diện tên đường trên Google Map...'
              : 'Đang chọn: $_activeTargetDescription — Chạm lên bản đồ Google Map bên dưới để ghim vị trí.',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Map3dPerspectiveWidget(
          key: const ValueKey('cloud-order-google-map'),
          height: 270,
          showTopBanner: false,
          mode: MapViewMode.customerPreview,
          customFleetDrivers: const [],
          useGlobalFallbackRoute: false,
          routePoints: _mapRoutePoints,
          singlePinPoint: _mapRoutePoints.length >= 2
              ? null
              : _singlePinnedPoint,
          singlePinLabel: _singlePinnedLabel,
          focusedCenterPoint: _focusedMapPoint,
          pickupLabel: 'Điểm lấy [A]',
          dropoffLabel: 'Điểm giao [B]',
          onTapGeoPoint: _busy || !_sameAccount ? null : _handleMapTap,
        ),
      ],
    ),
  );

  Widget _address(String prefix, String title) {
    final pinned = prefix == 'pickup'
        ? _pickupPoint != null
        : _dropoffPoint != null;
    final active = _activeMapTarget == prefix;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                pinned ? Icons.where_to_vote_rounded : Icons.touch_app_outlined,
                size: 17,
                color: pinned
                    ? Colors.green.shade700
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  pinned
                      ? 'Đã ghim vị trí trên Google Map'
                      : 'Chạm lên Google Map hoặc nhập địa chỉ tìm kiếm',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: pinned ? FontWeight.w600 : FontWeight.w500,
                    color: pinned
                        ? Colors.green.shade700
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _busy || !_sameAccount
                    ? null
                    : () => setState(() {
                        _activeMapTarget = prefix;
                        final targetPt = prefix == 'pickup'
                            ? _pickupPoint
                            : _dropoffPoint;
                        if (targetPt != null) _focusedMapPoint = targetPt;
                      }),
                icon: Icon(
                  active ? Icons.gps_fixed : Icons.pin_drop_outlined,
                  size: 15,
                ),
                label: Text(prefix == 'pickup' ? 'Ghim [A]' : 'Ghim [B]'),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: prefix == 'pickup'
                    ? 'Chọn địa chỉ lấy đã lưu'
                    : 'Chọn địa chỉ giao đã lưu',
                onPressed: _busy || !_sameAccount
                    ? null
                    : () => _chooseAddress(prefix),
                icon: const Icon(Icons.contact_mail_outlined, size: 20),
              ),
            ],
          ),
          _text('${prefix}_address', title),
          if (!_busy && _sameAccount)
            PhotonAddressLookup(
              controller: _fields['${prefix}_address']!,
              service: widget.addressService,
              buttonLabel: prefix == 'pickup'
                  ? 'Tìm điểm lấy trên Google Map'
                  : 'Tìm điểm giao trên Google Map',
              autoSearch: true,
              biasPoint: _focusedMapPoint ?? _pickupPoint ?? _dropoffPoint,
              onSelected: (place) {
                if (!_sameAccount) return;
                _fields['${prefix}_address']!.text = place.address;
                setState(() {
                  if (prefix == 'pickup') {
                    _pickupPoint = place.point;
                    if (_dropoffPoint == null) _activeMapTarget = 'dropoff';
                  } else {
                    _dropoffPoint = place.point;
                  }
                  _focusedMapPoint = place.point;
                  _quote = null;
                  _error = null;
                });
              },
            ),
        ],
      ),
    );
  }

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
                  _googleMapPicker(),
                  _address('pickup', 'Địa chỉ lấy hàng'),
                  _address('dropoff', 'Địa chỉ giao hàng'),
                  const Divider(height: 24),
                  _text('recipient_name', 'Tên người nhận', max: 120),
                  _text('recipient_phone', 'Số điện thoại người nhận', max: 10),
                  CloudRecipientTrust(
                    service: widget.service,
                    phone: _fields['recipient_phone']!,
                    lease: widget.lease,
                    enabled: !_busy && _sameAccount,
                  ),
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
                                  Icon(
                                    _extraStops[i].point != null
                                        ? Icons.where_to_vote_rounded
                                        : Icons.pin_drop_outlined,
                                    size: 16,
                                    color: _extraStops[i].point != null
                                        ? Colors.green.shade700
                                        : null,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _extraStops[i].point != null
                                          ? 'Điểm dừng #${i + 1} · Đã ghim trên Google Map'
                                          : 'Điểm dừng trung gian #${i + 1}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: _busy || !_sameAccount
                                        ? null
                                        : () => setState(() {
                                            _activeMapTarget = 'stop:$i';
                                            if (_extraStops[i].point != null) {
                                              _focusedMapPoint =
                                                  _extraStops[i].point;
                                            }
                                          }),
                                    icon: const Icon(
                                      Icons.pin_drop_outlined,
                                      size: 15,
                                    ),
                                    label: const Text('Ghim Map'),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Xóa điểm dừng',
                                    onPressed: _busy || !_sameAccount
                                        ? null
                                        : () => _removeStop(i),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                      size: 20,
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
                                validator: (v) => (v?.trim().length ?? 0) < 3
                                    ? 'Nhập địa chỉ điểm dừng'
                                    : null,
                              ),
                              if (!_busy && _sameAccount)
                                PhotonAddressLookup(
                                  controller: _extraStops[i].address,
                                  service: widget.addressService,
                                  buttonLabel:
                                      'Tìm điểm dừng #${i + 1} trên Google Map',
                                  autoSearch: true,
                                  biasPoint:
                                      _focusedMapPoint ??
                                      _pickupPoint ??
                                      _dropoffPoint,
                                  onSelected: (place) {
                                    if (!_sameAccount) return;
                                    _extraStops[i].address.text = place.address;
                                    setState(() {
                                      _extraStops[i].point = place.point;
                                      _focusedMapPoint = place.point;
                                      _quote = null;
                                      _error = null;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                      if (_extraStops.length >= 2) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _busy || !_sameAccount
                                ? null
                                : _optimizeStops,
                            icon: const Icon(Icons.alt_route_outlined),
                            label: const Text(
                              'Tối ưu thứ tự điểm dừng theo đường bộ',
                            ),
                          ),
                        ),
                        if (_routeNotice != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_routeNotice!),
                          ),
                        const SizedBox(height: 8),
                      ],
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
                    if (_serviceEta?[_serviceType] case final eta?)
                      Text(
                        'Thời gian giao thực tế trung bình 30 ngày (${cloudServiceTypes[_serviceType]}): '
                        '${cloudMinutes(eta['avg_delivery_minutes'])} · ${eta['samples']} đơn',
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
