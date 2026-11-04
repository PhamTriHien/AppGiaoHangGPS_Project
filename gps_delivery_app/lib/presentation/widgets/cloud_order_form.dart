import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env_config.dart';
import '../../core/gps/stop_order_optimizer.dart';
import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_orders_service.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/integrations/photon_address_service.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import '../screens/cloud_address_book_screen.dart';
import 'animated_3d_ui_icons.dart';
import 'cloud_commerce_dialog.dart';
import 'cloud_logistics_panels.dart';
import 'cloud_order_labels.dart';
import 'cloud_session_boundary.dart';
import 'motion_3d_effects.dart';
import 'photon_address_lookup.dart';
import 'system_state_screens.dart';
import 'vietqr_bank_payment_panel.dart';
import 'ghst_button_icon.dart';

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
    this.session,
    this.lease,
    this.initialDetails,
    this.embedded = false,
    this.onCreated,
    this.onOrderCreated,
    this.addressService,
  });
  final CloudOrdersService service;
  final List<Map<String, dynamic>> merchants;
  final CloudAccountSession? session;
  final CloudSessionLease? lease;
  final Map<String, dynamic>? initialDetails;
  final bool embedded;
  final VoidCallback? onCreated;
  final ValueChanged<Map<String, dynamic>>? onOrderCreated;
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
      _requireOtp = false,
      _useCoins = false;
  Map<String, dynamic>? _quote;
  Map<String, Map<String, dynamic>>? _serviceEta;
  bool _busy = false;
  String? _error, _routeNotice;
  Timer? _draftSaveTimer;
  bool _restoredFromCloudDraft = false;
  bool _suppressDraftSync = false;

  CloudAccountSession? get _accountSession =>
      widget.session ?? widget.lease?.session;

  bool get _draftSyncEnabled =>
      _accountSession != null &&
      (widget.initialDetails == null || widget.initialDetails!.isEmpty);

  int get _availableCoins => _accountSession?.coinBalance ?? 0;

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

  void _applyInitialSource(Map<String, dynamic> source, {bool isDraft = false}) {
    _suppressDraftSync = true;
    try {
      for (final entry in _fields.entries) {
        final value = source[entry.key];
        if (value is String || value is num && value.isFinite) {
          if (['length_cm', 'width_cm', 'height_cm', 'declared_value'].contains(
                entry.key,
              ) &&
              value is num &&
              value <= 0) {
            continue;
          }
          if (entry.key == 'scheduled_at' && !isDraft) {
            final parsedSchedule = DateTime.tryParse('$value');
            if (parsedSchedule != null &&
                parsedSchedule.isBefore(DateTime.now())) {
              continue;
            }
          }
          entry.value.text = '$value';
        }
      }
      _pickupPoint = _parsePoint(source['pickup_lat'], source['pickup_lng']);
      _dropoffPoint = _parsePoint(source['dropoff_lat'], source['dropoff_lng']);
      _focusedMapPoint = _dropoffPoint ?? _pickupPoint;
      if (_pickupPoint != null && _dropoffPoint == null) {
        _activeMapTarget = 'dropoff';
      }
      if (cloudServiceTypes.containsKey(source['service_type'])) {
        _serviceType = source['service_type'] as String;
      }
      if ([
        'sender_cash',
        'sender_bank_qr',
        'recipient_cash',
      ].contains(source['payment_method'])) {
        _payment = source['payment_method'] as String;
      }
      _isRoundTrip = source['is_round_trip'] == true;
      _preferEv = source['prefer_ev'] == true;
      _greenFund = source['green_fund'] == true;
      _requirePod = source['require_pod'] == true;
      _requireOtp = source['require_otp'] == true;
      _useCoins = source['use_coins'] == true;
      if (source['extra_stops'] is List) {
        for (final raw in (source['extra_stops'] as List).take(5)) {
          if (raw is Map) {
            _addStop(
              address: '${raw['address'] ?? ''}',
              point: _parsePoint(raw['lat'], raw['lng']),
            );
          }
        }
      }
      final merchant = source['merchant_id'];
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
    } finally {
      _suppressDraftSync = false;
    }
  }

  Map<String, dynamic> _buildDraftSnapshot() {
    final map = <String, dynamic>{
      'service_type': _serviceType,
      'payment_method': _payment,
      if (_merchant.isNotEmpty) 'merchant_id': _merchant,
      if (_isRoundTrip) 'is_round_trip': true,
      if (_preferEv) 'prefer_ev': true,
      if (_greenFund) 'green_fund': true,
      if (_requirePod) 'require_pod': true,
      if (_requireOtp) 'require_otp': true,
      if (_useCoins) 'use_coins': true,
    };
    for (final entry in _fields.entries) {
      final text = entry.value.text.trim();
      if (text.isNotEmpty) map[entry.key] = text;
    }
    if (_pickupPoint != null) {
      map['pickup_lat'] = _pickupPoint!.latitude;
      map['pickup_lng'] = _pickupPoint!.longitude;
    }
    if (_dropoffPoint != null) {
      map['dropoff_lat'] = _dropoffPoint!.latitude;
      map['dropoff_lng'] = _dropoffPoint!.longitude;
    }
    if (_extraStops.isNotEmpty) {
      map['extra_stops'] = [
        for (final s in _extraStops)
          {
            'address': s.address.text.trim(),
            if (s.point != null) 'lat': s.point!.latitude,
            if (s.point != null) 'lng': s.point!.longitude,
          },
      ];
    }
    return map;
  }

  bool get _hasMeaningfulDraftContent {
    for (final entry in _fields.entries) {
      if (entry.value.text.trim().isNotEmpty) return true;
    }
    return _pickupPoint != null ||
        _dropoffPoint != null ||
        _extraStops.isNotEmpty;
  }

  void _scheduleDraftSync() {
    if (!_draftSyncEnabled || _suppressDraftSync || !_sameAccount) return;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(
      const Duration(milliseconds: 550),
      _flushDraftToCloud,
    );
  }

  Future<void> _flushDraftToCloud() async {
    if (!mounted || !_draftSyncEnabled || !_sameAccount) return;
    if (!_hasMeaningfulDraftContent) {
      _accountSession?.updateCachedShippingDraft(const {});
      try {
        await widget.service.accountPreferences('clear_draft');
      } catch (_) {}
      return;
    }
    final snap = _buildDraftSnapshot();
    _accountSession?.updateCachedShippingDraft(snap);
    try {
      await widget.service.accountPreferences('save_draft', {'draft': snap});
    } catch (_) {}
  }

  Future<void> _clearCloudDraft() async {
    if (_busy || !_sameAccount) return;
    _draftSaveTimer?.cancel();
    _suppressDraftSync = true;
    try {
      for (final c in _fields.values) {
        c.clear();
      }
      for (final s in _extraStops) {
        s.address.removeListener(_resetQuote);
        s.address.dispose();
      }
      _extraStops.clear();
      _pickupPoint = null;
      _dropoffPoint = null;
      _focusedMapPoint = null;
      _activeMapTarget = 'pickup';
      _serviceType = 'standard';
      _payment = 'sender_cash';
      _merchant = '';
      _isRoundTrip = false;
      _preferEv = false;
      _greenFund = false;
      _requirePod = false;
      _requireOtp = false;
      _useCoins = false;
      _quote = null;
      _error = null;
      _routeNotice = null;
      _restoredFromCloudDraft = false;
      _fieldValues
        ..clear()
        ..addAll({
          for (final entry in _fields.entries) entry.key: entry.value.text,
        });
    } finally {
      _suppressDraftSync = false;
    }
    if (mounted) setState(() {});
    _accountSession?.updateCachedShippingDraft(const {});
    try {
      await widget.service.accountPreferences('clear_draft');
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDetails;
    final savedDraft = _accountSession?.shippingDraft;
    if (initial != null && initial.isNotEmpty && _sameAccount) {
      _applyInitialSource(initial, isDraft: false);
    } else if (_draftSyncEnabled &&
        _sameAccount &&
        savedDraft != null &&
        savedDraft.isNotEmpty) {
      _applyInitialSource(savedDraft, isDraft: true);
      _restoredFromCloudDraft = true;
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
    _scheduleDraftSync();
  }

  void _resetQuote() {
    if (mounted && _quote != null) setState(() => _quote = null);
    _scheduleDraftSync();
  }

  void _invalidate() {
    if (!mounted || _invalidated) return;
    _invalidated = true;
    _draftSaveTimer?.cancel();
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
    if (changed) {
      if (mounted && _quote != null) setState(() => _quote = null);
      _scheduleDraftSync();
    }
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
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
    final pts = <GeoPoint>[
      _pickupPoint!,
      for (final stop in _extraStops)
        if (stop.point != null) stop.point!,
      _dropoffPoint!,
    ];
    if (_isRoundTrip && pts.length < 7) {
      pts.add(_pickupPoint!);
    }
    return pts;
  }

  List<GeoPoint> get _mapExtraStopPoints => [
    for (final stop in _extraStops)
      if (stop.point != null) stop.point!,
  ];

  List<String> get _mapExtraStopLabels => [
    for (var i = 0; i < _extraStops.length; i++)
      if (_extraStops[i].point != null) 'Điểm #${i + 1}',
  ];

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
    _scheduleDraftSync();
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
      'payment_method': _payment == 'sender_bank_qr' ? 'sender_cash' : _payment,
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
    if (_useCoins) result['use_coins'] = true;
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
        final createdResponse = await widget.service.command('orders', {
          'details': details,
          'pricing_version': _quote!['pricing_version'],
          'expected_fee': _quote!['payable_fee'] ?? _quote!['shipping_fee'],
          'draft_id': draft,
        });
        if (!mounted || !_sameAccount) return;
        _draftSaveTimer?.cancel();
        _accountSession?.updateCachedShippingDraft(const {});
        _restoredFromCloudDraft = false;
        await widget.service.completeDraft(draft);
        unawaited(_accountSession?.refresh().catchError((Object _) {}));
        final createdOrder = createdResponse['order'] is Map
            ? Map<String, dynamic>.from(createdResponse['order'] as Map)
            : null;
        if (mounted &&
            _sameAccount &&
            _payment == 'sender_bank_qr' &&
            createdOrder != null &&
            createdOrder['id'] != null) {
          setState(() => _busy = false);
          await showDialog<void>(
            context: context,
            builder: (_) => widget.lease != null
                ? CloudSessionBoundary(
                    session: widget.lease!.session,
                    operator: widget.lease!.session.isOperator,
                    dialog: true,
                    builder: (_, lease) => CloudCommerceDialog(
                      service: widget.service,
                      order: createdOrder,
                      operator: lease.session.isOperator,
                      lease: lease,
                    ),
                  )
                : CloudCommerceDialog(
                    service: widget.service,
                    order: createdOrder,
                  ),
          );
        }
        if (mounted && _sameAccount) {
          if (widget.embedded) {
            if (createdOrder != null && widget.onOrderCreated != null) {
              widget.onOrderCreated!(createdOrder);
            } else {
              widget.onCreated?.call();
            }
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
            : 'Thứ tự hiện tại đã ngắn nhất: ${km(plan.currentMeters)} km đường bộ.';
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
    int max = 500, String? suffixText,
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
        labelText: label, suffixText: suffixText,
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
              ? 'Thời gian hẹn lấy không hợp lệ'
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
    _scheduleDraftSync();
  }

  Widget _buildDraftBanner(BuildContext context) {
    if (!_draftSyncEnabled ||
        (!_restoredFromCloudDraft && !_hasMeaningfulDraftContent)) {
      return const SizedBox.shrink();
    }
    final tokens = GhstThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GhstLuminousCard(
        accentGlow: tokens.sapphire.glow,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        borderRadius: 14,
        child: Row(
          children: [
            GhstButtonIcon(
              Icons.cloud_done_outlined,
              size: 18,
              color: tokens.sapphire.foreground,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _restoredFromCloudDraft
                    ? 'Đã khôi phục bản nháp đơn giao chưa hoàn tất'
                    : 'Bản nháp đơn giao đang được tự động lưu',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: tokens.ink,
                ),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('clear-shipping-draft'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _busy || !_sameAccount ? null : _clearCloudDraft,
              icon: const GhstButtonIcon(Icons.delete_sweep_outlined, size: 16),
              label: const Text('Xóa bản nháp'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceTierSelector(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    const tierMeta =
        <
          String,
          ({
            Icon3dStyle style,
            String subtitle,
            String badge,
          })
        >{
          'standard': (
            style: Icon3dStyle.parcelBox,
            subtitle: 'Xe máy nội thành · Cân bằng cước phí',
            badge: 'Phổ biến',
          ),
          'express': (
            style: Icon3dStyle.scooterExpress,
            subtitle: 'Ưu tiên điều phối · Giao thẳng siêu tốc',
            badge: 'Ưu tiên',
          ),
          'saving': (
            style: Icon3dStyle.walletVault,
            subtitle: 'Linh hoạt lộ trình · Tiết kiệm tối đa',
            badge: 'Tiết kiệm',
          ),
          'same_day_2h': (
            style: Icon3dStyle.hub2hBatch,
            subtitle: 'Ghép đơn cùng hướng · Cam kết 2 giờ',
            badge: '2 Giờ',
          ),
          'truck': (
            style: Icon3dStyle.cargoTruck,
            subtitle: 'Hàng lớn cồng kềnh đến 500 kg',
            badge: '500 kg',
          ),
        };
    TonePair toneForTier(String key) => switch (key) {
      'express' => tokens.amber,
      'saving' => tokens.emerald,
      'same_day_2h' => tokens.violet,
      'truck' => tokens.amber,
      _ => tokens.sapphire,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              GhstButtonIcon(
                Icons.layers_outlined,
                size: 17,
                color: tokens.sapphire.foreground,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Chọn gói dịch vụ vận chuyển',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: tokens.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 460;
            final cardWidth = twoColumns
                ? (constraints.maxWidth - 10) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final entry in cloudServiceTypes.entries)
                  SizedBox(
                    width: cardWidth,
                    child: Builder(
                      builder: (context) {
                        final selected = _serviceType == entry.key;
                        final meta = tierMeta[entry.key]!;
                        final tone = toneForTier(entry.key);
                        final eta = _serviceEta?[entry.key];
                        return Motion3dInteractiveSurface(
                          enabled: !_busy && _sameAccount,
                          maxTilt: 0.032,
                          enablePressScale: true,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            key: ValueKey('service-tier-${entry.key}'),
                            borderRadius: BorderRadius.circular(14),
                            onTap: _busy || !_sameAccount
                                ? null
                                : () {
                                    setState(() {
                                      _serviceType = entry.key;
                                      _quote = null;
                                    });
                                    _scheduleDraftSync();
                                  },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: selected
                                    ? tone.fill
                                    : tokens.cardSurface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? tone.foreground
                                      : tokens.border,
                                  width: selected ? 1.7 : 1.0,
                                ),
                                boxShadow: selected
                                    ? tokens.cardShadow
                                    : const [],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GhstAiIcon(
                                    style: meta.style,
                                    size: 40,
                                    borderRadius: 11,
                                    selected: selected,
                                    borderColor: selected
                                        ? tone.foreground
                                        : tokens.border,
                                    glowColor: tone.icon,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                entry.value,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 13.5,
                                                  color: selected
                                                      ? tone.foreground
                                                      : tokens.ink,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: selected
                                                    ? tone.foreground
                                                          .withValues(
                                                            alpha: 0.16,
                                                          )
                                                    : tokens.cardSubtle,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                eta != null
                                                    ? cloudMinutes(
                                                        eta['avg_delivery_minutes'],
                                                      )
                                                    : meta.badge,
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: selected
                                                      ? tone.foreground
                                                      : tokens.inkSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          meta.subtitle,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            height: 1.25,
                                            color: tokens.inkSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _googleMapPicker() => GhstLuminousCard(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    borderRadius: 16,
    accentGlow: GhstThemeTokens.of(context).sapphire.glow,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            GhstButtonIcon(Icons.map_outlined, size: 19),
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
            ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel('Ghim điểm lấy [A]', size: 15), label: const Text('Ghim điểm lấy [A]'), selected: _activeMapTarget == 'pickup', onSelected: _busy || !_sameAccount
                  ? null
                  : (_) => setState(() {
                      _activeMapTarget = 'pickup';
                      if (_pickupPoint != null) _focusedMapPoint = _pickupPoint;
                    }),),
            ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel('Ghim điểm giao [B]', size: 15), label: const Text('Ghim điểm giao [B]'), selected: _activeMapTarget == 'dropoff', onSelected: _busy || !_sameAccount
                  ? null
                  : (_) => setState(() {
                      _activeMapTarget = 'dropoff';
                      if (_dropoffPoint != null) {
                        _focusedMapPoint = _dropoffPoint;
                      }
                    }),),
            for (var i = 0; i < _extraStops.length; i++)
              ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel('Ghim điểm dừng #${i + 1}', size: 15), label: Text('Ghim điểm dừng #${i + 1}'), selected: _activeMapTarget == 'stop:$i', onSelected: _busy || !_sameAccount
                    ? null
                    : (_) => setState(() {
                        _activeMapTarget = 'stop:$i';
                        if (_extraStops[i].point != null) {
                          _focusedMapPoint = _extraStops[i].point;
                        }
                      }),),
            ActionChip(
              avatar: const GhstButtonIcon(Icons.my_location_outlined, size: 16),
              label: const Text('Vị trí hiện tại'),
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
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Map3dPerspectiveWidget(
            key: const ValueKey('cloud-order-google-map'),
            height: 390,
            showTopBanner: false,
            mode: MapViewMode.customerPreview,
            customFleetDrivers: const [],
            useGlobalFallbackRoute: false,
            routePoints: _mapRoutePoints,
            explicitDropoffPoint: _dropoffPoint,
            extraStopPoints: _mapExtraStopPoints,
            extraStopLabels: _mapExtraStopLabels,
            singlePinPoint: _mapRoutePoints.length >= 2
                ? null
                : _singlePinnedPoint,
            singlePinLabel: _singlePinnedLabel,
            focusedCenterPoint: _focusedMapPoint,
            pickupLabel: 'Điểm lấy [A]',
            dropoffLabel: 'Điểm giao [B]',
            onTapGeoPoint: _busy || !_sameAccount ? null : _handleMapTap,
          ),
        ),
        if (_pickupPoint != null && _dropoffPoint != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _routeInfoChip(
                context,
                Icons.route_rounded,
                _extraStops.isEmpty
                    ? 'Hành trình 2 điểm A → B'
                    : 'Đa điểm: ${_extraStops.length + 2} chặng dừng',
              ),
              if (_isRoundTrip)
                _routeInfoChip(
                  context,
                  Icons.sync_alt_rounded,
                  'Khứ hồi quay lại [A]',
                ),
              if (_preferEv)
                _routeInfoChip(
                  context,
                  Icons.electric_moped_rounded,
                  'Ưu tiên xe điện',
                ),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _routeInfoChip(BuildContext context, IconData icon, String label) {
    final tokens = GhstThemeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.sapphire.fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.sapphire.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GhstButtonIcon(icon, size: 14, color: tokens.sapphire.foreground),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: tokens.sapphire.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _address(String prefix, String title) {
    final tokens = GhstThemeTokens.of(context);
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
              GhstButtonIcon(
                pinned ? Icons.where_to_vote_rounded : Icons.touch_app_outlined,
                size: 17,
                color: pinned
                    ? tokens.emerald.foreground
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
                        ? tokens.emerald.foreground
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
                icon: GhstButtonIcon(
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
                icon: const GhstButtonIcon(Icons.contact_mail_outlined, size: 20),
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
                _scheduleDraftSync();
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : null,
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('Tạo đơn hàng')),
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
                    _buildDraftBanner(context),
                    _googleMapPicker(),
                    _address('pickup', 'Địa chỉ lấy hàng'),
                    _address('dropoff', 'Địa chỉ giao hàng'),
                    const Divider(height: 24),
                    _text('recipient_name', 'Tên người nhận', max: 120),
                    _text(
                      'recipient_phone',
                      'Số điện thoại người nhận',
                      max: 10,
                    ),
                    CloudRecipientTrust(
                      service: widget.service,
                      phone: _fields['recipient_phone']!,
                      lease: widget.lease,
                      enabled: !_busy && _sameAccount,
                    ),
                    _text('package_description', 'Hàng hóa', max: 1000),
                    _text(
                      'weight_kg',
                      'Khối lượng',
                      numeric: true,
                      suffixText: 'kg',
                    ),
                    _text(
                      'cod_amount',
                      'Tiền thu hộ',
                      numeric: true,
                      suffixText: 'đ',
                    ),
                    const SizedBox(height: 4),
                    _buildServiceTierSelector(context),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), initialValue: _payment, isExpanded: true, decoration: const InputDecoration(
                        labelText: 'Trả phí vận chuyển',
                        border: OutlineInputBorder(),
                      ), items: const [
                        DropdownMenuItem(
                          value: 'sender_cash',
                          child: Text('Người gửi trả tiền mặt'),
                        ),
                        DropdownMenuItem(
                          value: 'sender_bank_qr',
                          child: Text('Chuyển khoản ngân hàng · Mã QR'),
                        ),
                        DropdownMenuItem(
                          value: 'recipient_cash',
                          child: Text('Người nhận trả tiền mặt'),
                        ),
                      ], onChanged: _busy || !_sameAccount
                          ? null
                          : (value) {
                              setState(() {
                                _payment = value!;
                                _quote = null;
                              });
                              _scheduleDraftSync();
                            },),
                    if (widget.merchants.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), initialValue: _merchant, isExpanded: true, decoration: const InputDecoration(
                          labelText: 'Cửa hàng xử lý',
                          border: OutlineInputBorder(),
                        ), items: [
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
                        ], onChanged: _busy || !_sameAccount
                            ? null
                            : (value) {
                                setState(() {
                                  _merchant = value!;
                                  _quote = null;
                                });
                                _scheduleDraftSync();
                              },),
                    ],
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const GhstButtonIcon(Icons.monetization_on_outlined),
                      title: const Text('Dùng Xu giảm cước phí đơn hàng'),
                      subtitle: Text(
                        _availableCoins > 0
                            ? '$_availableCoins Xu khả dụng · Giảm tối đa 20% cước phí'
                            : 'Hiện có 0 Xu · Hoàn tất đơn hoặc tham gia sự kiện để tích Xu',
                      ),
                      value:
                          _useCoins &&
                          (_availableCoins > 0 ||
                              (_quote?['coin_discount'] as num? ?? 0) > 0),
                      onChanged:
                          _busy ||
                              !_sameAccount ||
                              (_availableCoins <= 0 && !_useCoins)
                          ? null
                          : (v) {
                              setState(() {
                                _useCoins = v;
                                _quote = null;
                              });
                              _scheduleDraftSync();
                            },
                    ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Tùy chọn nâng cao: Kích thước, Bảo hiểm & Điểm dừng',
                    ),
                    children: [
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _text(
                              'length_cm',
                              'Dài', suffixText: 'cm',
                              numeric: true,
                              optional: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _text(
                              'width_cm',
                              'Rộng', suffixText: 'cm',
                              numeric: true,
                              optional: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _text(
                              'height_cm',
                              'Cao', suffixText: 'cm',
                              numeric: true,
                              optional: true,
                            ),
                          ),
                        ],
                      ),
                      _text(
                        'declared_value',
                        'Khai giá bảo hiểm', suffixText: 'đ',
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
                              'Hẹn giờ lấy hàng',
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
                            icon: const GhstButtonIcon(Icons.schedule),
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
                              icon: const GhstButtonIcon(Icons.clear),
                            ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Giao khứ hồi · Phụ thu 60% cước'),
                        value: _isRoundTrip,
                        onChanged: _busy || !_sameAccount
                            ? null
                            : (v) {
                                setState(() {
                                  _isRoundTrip = v;
                                  _quote = null;
                                });
                                _scheduleDraftSync();
                              },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Ưu tiên tài xế xe điện'),
                        value: _preferEv,
                        onChanged: _busy || !_sameAccount
                            ? null
                            : (v) {
                                setState(() {
                                  _preferEv = v;
                                  _quote = null;
                                });
                                _scheduleDraftSync();
                              },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Đóng góp Quỹ Xanh · 1.000 đ'),
                        value: _greenFund,
                        onChanged: _busy || !_sameAccount
                            ? null
                            : (v) {
                                setState(() {
                                  _greenFund = v;
                                  _quote = null;
                                });
                                _scheduleDraftSync();
                              },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Yêu cầu ảnh bằng chứng giao hàng',
                        ),
                        value: _requirePod,
                        onChanged: _busy || !_sameAccount
                            ? null
                            : (v) {
                                setState(() {
                                  _requirePod = v;
                                  _quote = null;
                                });
                                _scheduleDraftSync();
                              },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Yêu cầu mã OTP 6 số người nhận'),
                        value: _requireOtp,
                        onChanged: _busy || !_sameAccount
                            ? null
                            : (v) {
                                setState(() {
                                  _requireOtp = v;
                                  _quote = null;
                                });
                                _scheduleDraftSync();
                              },
                      ),
                      for (var i = 0; i < _extraStops.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  GhstButtonIcon(
                                    _extraStops[i].point != null
                                        ? Icons.where_to_vote_rounded
                                        : Icons.pin_drop_outlined,
                                    size: 16,
                                    color: _extraStops[i].point != null
                                        ? tokens.emerald.foreground
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
                                    icon: const GhstButtonIcon(
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
                                    icon: const GhstButtonIcon(
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
                                      _scheduleDraftSync();
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
                              icon: const GhstButtonIcon(Icons.alt_route_outlined),
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
                                  : () {
                                      setState(() {
                                        _addStop();
                                        _quote = null;
                                      });
                                      _scheduleDraftSync();
                                    },
                              icon: const GhstButtonIcon(Icons.add_location_alt_outlined),
                              label: const Text(
                                'Thêm điểm dừng trung gian · 5.000 đ',
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_quote != null) ...[
                      GhstLuminousCard(
                        accentGlow: tokens.emerald.glow,
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        borderRadius: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Phí vận chuyển: ${CurrencyFormatter.formatVnd((_quote!['shipping_fee'] as num).toDouble())}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if ((_quote!['coin_discount'] as num? ?? 0) >
                                0) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Đổi Xu giảm cước: -${CurrencyFormatter.formatVnd((_quote!['coin_discount'] as num).toDouble())}',
                                  style: TextStyle(
                                    color: tokens.emerald.foreground,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 2,
                                  bottom: 4,
                                ),
                                child: Text(
                                  'Cước cần thanh toán: ${CurrencyFormatter.formatVnd(((_quote!['payable_fee'] ?? _quote!['shipping_fee']) as num).toDouble())}',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ] else if (!_useCoins &&
                                (_quote!['max_coin_discount'] as num? ?? 0) > 0)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  bottom: 4,
                                ),
                                child: Text(
                                  'Có thể bật Dùng Xu để giảm ngay ${CurrencyFormatter.formatVnd((_quote!['max_coin_discount'] as num).toDouble())} cước phí',
                                  style: TextStyle(
                                    color: tokens.amber.foreground,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            Text(
                              'Cự ly ước tính: ${((_quote!['distance_meters'] as num) / 1000).toStringAsFixed(1)} km',
                            ),
                            if ((_quote!['volumetric_weight_kg'] as num? ?? 0) >
                                0)
                              Text(
                                'Khối lượng quy đổi thể tích: ${_quote!['volumetric_weight_kg']} kg',
                              ),
                            if ((_quote!['estimated_co2_saved_grams'] as num? ??
                                    0) >
                                0)
                              Text(
                                'Ước tính giảm phát thải EV: ${_quote!['estimated_co2_saved_grams']} g CO2',
                              ),
                            if (_serviceEta?[_serviceType] case final eta?)
                              Text(
                                'Thời gian giao thực tế trung bình 30 ngày · ${cloudServiceTypes[_serviceType]}: '
                                '${cloudMinutes(eta['avg_delivery_minutes'])} · ${eta['samples']} đơn',
                              ),
                            if (_quote!['breakdown'] is Map) ...[
                              for (final entry in const {
                                'base_fee': 'Phí 2 km đầu',
                                'distance_fee': 'Phí quãng đường bổ sung',
                                'weight_fee': 'Phụ phí vượt khối lượng',
                                'express_fee': 'Điều chỉnh gói dịch vụ',
                              }.entries)
                                if ((_quote!['breakdown'] as Map)[entry.key]
                                    is num)
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
                                if (((_quote!['breakdown'] as Map)[entry.key]
                                            as num? ??
                                        0) >
                                    0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      '${entry.value}: ${CurrencyFormatter.formatVnd(((_quote!['breakdown'] as Map)[entry.key] as num).toDouble())}',
                                    ),
                                  ),
                            ],
                          ],
                        ),
                      ),
                      if (_payment == 'sender_bank_qr') ...[
                        VietQrBankPaymentPanel(
                          amountVnd:
                              ((_quote!['payable_fee'] ??
                                          _quote!['shipping_fee'])
                                      as num)
                                  .toDouble(),
                          orderReference: 'CUOC VAN CHUYEN',
                          compact: true,
                          reconciliationNote:
                              'Sau khi bấm Xác nhận tạo đơn, hệ thống sẽ tạo mã vận đơn riêng để đối soát chuyển khoản.',
                        ),
                        const SizedBox(height: 16),
                      ],
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
                      icon: GhstButtonIcon(
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
}
