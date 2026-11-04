part of 'customer_subsystem_views.dart';

extension _CustomerOrderAndPricingViews on _CustomerSubsystemEntryState {
  /// UC03 & UC04: Tạo đơn hàng mới & Chọn dịch vụ 2x2 Grid (Khớp 100% uc03 & uc04)
  Widget _buildCreateOrderView() {
    final pickupSuggestions = SmartDispatchEngine.searchAddressSuggestions(
      _pickupCtrl.text,
    );
    final dropoffSuggestions = SmartDispatchEngine.searchAddressSuggestions(
      _dropoffCtrl.text,
    );
    final pPt =
        _pinnedPickupLocation ??
        (_pickupCtrl.text.trim().isEmpty && _store.liveDeviceLocation != null
            ? _store.liveDeviceLocation!
            : SmartDispatchEngine.resolveAddressToCoordinate(
                _pickupCtrl.text,
                fallback:
                    _store.liveDeviceLocation ??
                    const GeoPoint(latitude: 10.7769, longitude: 106.6953),
              ));
    final hasDropoffTarget =
        _dropoffCtrl.text.trim().isNotEmpty || _pinnedDropoffLocation != null;
    final dPt =
        _pinnedDropoffLocation ??
        SmartDispatchEngine.resolveAddressToCoordinate(
          _dropoffCtrl.text,
          fallback: const GeoPoint(latitude: 10.7688, longitude: 106.6820),
        );
    final rawAirMeters = GeoMath.distanceMeters(pPt, dPt);
    final resolvedDistMeters =
        _osrmDistMeters ?? (rawAirMeters * 1.28).round().clamp(1500, 45000);
    final resolvedDurSec =
        _osrmDurationSec ?? ((resolvedDistMeters / 1000.0) * 180).round();
    final estDistKm = (resolvedDistMeters / 1000.0).clamp(0.5, 65.0);
    final estDurationMin = (resolvedDurSec / 60.0).round().clamp(5, 240);
    final previewRoutePoints =
        (_osrmPreviewPoints != null && _osrmPreviewPoints!.length >= 2)
        ? _osrmPreviewPoints!
        : SmartDispatchEngine.generateRoutePolyline(pPt, dPt, segments: 10);

    Widget buildLeftFormColumn() {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.ink, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: AppColors.ink,
              offset: Offset(0, 4), blurRadius: 14,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tạo đơn hàng mới',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Nhập lộ trình lấy/giao và thông tin kiện hàng',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                  ),
                  onPressed: () =>
                      _rebuildCustomerUi(() => _selectedScreenIndex = 1),
                  icon: const GhstButtonIcon(Icons.bookmarks_outlined, size: 15),
                  label: const Text('Sổ địa chỉ'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _editingDraftId == null ? 'Đơn mới' : 'Đang sửa đơn nháp',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Soạn đơn mới',
                  onPressed: () async {
                    final ownerId = _store.activeAuthenticatedUser?.id;
                    if (!await _confirmReplaceCustomerForm() ||
                        !mounted ||
                        ownerId != _store.activeAuthenticatedUser?.id) {
                      return;
                    }
                    _rebuildCustomerUi(() {
                      _resetCustomerOrderForm();
                      _syncCustomerControllersFromDb();
                    });
                  },
                  icon: const GhstButtonIcon(Icons.note_add_outlined),
                ),
                IconButton(
                  tooltip: 'Lưu đơn nháp',
                  onPressed: _savingDraft ? null : _saveCustomerDraft,
                  icon: const GhstButtonIcon(Icons.save_outlined),
                ),
                IconButton(
                  tooltip: 'Mở đơn nháp',
                  onPressed: _openCustomerDrafts,
                  icon: const GhstButtonIcon(Icons.drafts_outlined),
                ),
              ],
            ),
            DeliveryWeatherStrip(
              point: _pinnedPickupLocation ?? _store.liveDeviceLocation,
            ),
            ShippingLabelScanner(
              onApply: (fields) => _rebuildCustomerUi(() {
                if (fields['recipientName']!.isNotEmpty) {
                  _recipientNameCtrl.text = fields['recipientName']!;
                }
                if (fields['recipientPhone']!.isNotEmpty) {
                  _recipientPhoneCtrl.text = fields['recipientPhone']!;
                }
                if (fields['dropoffAddress']!.isNotEmpty) {
                  _dropoffCtrl.text = fields['dropoffAddress']!;
                  _pinnedDropoffLocation = null;
                  _osrmPreviewPoints = null;
                  _osrmDistMeters = null;
                  _osrmDurationSec = null;
                }
              }),
            ),
            const Text(
              '1. Lộ trình lấy & giao hàng',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pickupCtrl,
              decoration: InputDecoration(
                labelText: 'Điểm lấy hàng (Người gửi)',
                prefixIcon: const GhstButtonIcon(
                  Icons.radio_button_checked_rounded,
                  color: AppColors.violet,
                  size: 18,
                ),
              ),
              onChanged: (_) => _rebuildCustomerUi(() {
                _userEditedPickupManually = true;
                _pinnedPickupLocation = null;
                _osrmPreviewPoints = null;
                _osrmDistMeters = null;
                _osrmDurationSec = null;
              }),
            ),
            const SizedBox(height: 6),
            PhotonAddressLookup(
              controller: _pickupCtrl,
              onSelected: (place) => _rebuildCustomerUi(() {
                _pickupCtrl.text = place.address;
                _pinnedPickupLocation = place.point;
                _userEditedPickupManually = true;
                _osrmPreviewPoints = null;
                _osrmDistMeters = null;
                _osrmDurationSec = null;
              }),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: _store.hasRealDeviceGpsFix
                      ? const Color(0xFFE0F2FE)
                      : null,
                  avatar: const GhstButtonIcon(
                    Icons.my_location_rounded,
                    size: 13,
                    color: Color(0xFF0284C7),
                  ),
                  label: Text(
                    _store.hasRealDeviceGpsFix
                        ? 'Vị trí GPS thật của tôi'
                        : 'Lấy vị trí hiện tại (GPS)',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0369A1),
                    ),
                  ),
                  onPressed: () async {
                    final pos = await _store.acquireCustomerDeviceGps();
                    if (!mounted) return;
                    if (pos == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppColors.danger,
                          content: Text(_store.liveGpsStatusMessage),
                          action: SnackBarAction(
                            label: 'Mở Cài đặt',
                            textColor: AppColors.acid,
                            onPressed: () {
                              unawaited(_store.openDeviceLocationSettings());
                            },
                          ),
                        ),
                      );
                      return;
                    }
                    final resolvedText =
                        _store.liveDeviceAddress.trim().isNotEmpty
                        ? _store.liveDeviceAddress.trim()
                        : await SmartDispatchEngine.reverseGeocodeCoordinate(
                            pos,
                          );
                    if (!mounted) return;
                    _rebuildCustomerUi(() {
                      _userEditedPickupManually = false;
                      _pinnedPickupLocation = pos;
                      _pickupCtrl.text = resolvedText;
                      _osrmPreviewPoints = null;
                      _osrmDistMeters = null;
                      _osrmDurationSec = null;
                    });
                    if (_dropoffCtrl.text.trim().isNotEmpty ||
                        _pinnedDropoffLocation != null) {
                      final nextDropoff =
                          _pinnedDropoffLocation ??
                          SmartDispatchEngine.resolveAddressToCoordinate(
                            _dropoffCtrl.text,
                            fallback: dPt,
                          );
                      final routeRes =
                          await SmartDispatchEngine.fetchLiveOsrmRoute(
                            pos,
                            nextDropoff,
                          );
                      if (!mounted) return;
                      _rebuildCustomerUi(() {
                        if (routeRes.polylinePoints.length >= 2) {
                          _osrmPreviewPoints = routeRes.polylinePoints;
                        }
                        _osrmDistMeters = routeRes.distanceMeters;
                        _osrmDurationSec = routeRes.durationSeconds;
                      });
                    }
                  },
                ),
                ..._store.customerSavedAddresses.map((addr) {
                  return ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: const GhstButtonIcon(
                      Icons.bookmark_rounded,
                      size: 13,
                      color: AppColors.violet,
                    ),
                    label: Text(
                      'Lấy tại: ${addr.label}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () => _rebuildCustomerUi(() {
                      _userEditedPickupManually = true;
                      _pickupCtrl.text = addr.fullAddress;
                      _pinnedPickupLocation = addr.location;
                      _osrmPreviewPoints = null;
                      _osrmDistMeters = null;
                      _osrmDurationSec = null;
                    }),
                  );
                }),
                ...pickupSuggestions.take(2).map((place) {
                  return ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: const GhstButtonIcon(
                      Icons.place_outlined,
                      size: 13,
                      color: AppColors.violet,
                    ),
                    label: Text(
                      place.title,
                      style: const TextStyle(fontSize: 11),
                    ),
                    onPressed: () => _rebuildCustomerUi(() {
                      _userEditedPickupManually = true;
                      _pickupCtrl.text = place.fullAddress;
                      _pinnedPickupLocation = place.location;
                      _osrmPreviewPoints = null;
                      _osrmDistMeters = null;
                      _osrmDurationSec = null;
                    }),
                  );
                }),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _dropoffCtrl,
              decoration: InputDecoration(
                labelText: 'Điểm giao hàng (Người nhận)',
                prefixIcon: const GhstButtonIcon(
                  Icons.location_on,
                  color: AppColors.pink,
                  size: 20,
                ),
              ),
              onChanged: (_) => _rebuildCustomerUi(() {
                _pinnedDropoffLocation = null;
                _osrmPreviewPoints = null;
                _osrmDistMeters = null;
                _osrmDurationSec = null;
              }),
            ),
            PhotonAddressLookup(
              controller: _dropoffCtrl,
              onSelected: (place) => _rebuildCustomerUi(() {
                _dropoffCtrl.text = place.address;
                _pinnedDropoffLocation = place.point;
                _osrmPreviewPoints = null;
                _osrmDistMeters = null;
                _osrmDurationSec = null;
              }),
            ),
            if (_store.customerSavedAddresses.isNotEmpty ||
                dropoffSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ..._store.customerSavedAddresses.map((addr) {
                    return ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const GhstButtonIcon(
                        Icons.bookmark_border_rounded,
                        size: 13,
                        color: AppColors.pink,
                      ),
                      label: Text(
                        'Giao tới: ${addr.label}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => _rebuildCustomerUi(() {
                        _dropoffCtrl.text = addr.fullAddress;
                        _pinnedDropoffLocation = addr.location;
                        _osrmPreviewPoints = null;
                        _osrmDistMeters = null;
                        _osrmDurationSec = null;
                      }),
                    );
                  }),
                  ...dropoffSuggestions.take(3).map((place) {
                    return ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const GhstButtonIcon(
                        Icons.place,
                        size: 13,
                        color: AppColors.pink,
                      ),
                      label: Text(
                        place.title,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onPressed: () => _rebuildCustomerUi(() {
                        _dropoffCtrl.text = place.fullAddress;
                        _pinnedDropoffLocation = place.location;
                        _osrmPreviewPoints = null;
                        _osrmDistMeters = null;
                        _osrmDurationSec = null;
                      }),
                    );
                  }),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final showMultiStopBody =
                    _expandMultiStopSection ||
                    _additionalStops.isNotEmpty ||
                    _isRoundTrip;
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    border: Border.all(color: AppColors.ink, width: 1.1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => _rebuildCustomerUi(
                          () => _expandMultiStopSection =
                              !_expandMultiStopSection,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              const GhstButtonIcon(
                                Icons.alt_route_rounded,
                                size: 18,
                                color: AppColors.violet,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Giao nhiều điểm (2-Opt TSP) & Khứ hồi 2 chiều',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    SizedBox(height: 1),
                                    Text(
                                      'Tùy chọn thêm tối đa 4 điểm giao phụ hoặc quay về điểm lấy',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (_additionalStops.isNotEmpty ||
                                          _isRoundTrip)
                                      ? AppColors.acid
                                      : Colors.white,
                                  border: Border.all(
                                    color: AppColors.ink,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  '${_additionalStops.length}/4${_isRoundTrip ? " • 2 chiều" : ""}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              GhstButtonIcon(
                                showMultiStopBody
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 20,
                                color: AppColors.ink,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (showMultiStopBody)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(height: 10),
                              if (_additionalStops.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                ..._additionalStops.asMap().entries.map((
                                  entry,
                                ) {
                                  final index = entry.key;
                                  final stop = entry.value;
                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      radius: 13,
                                      backgroundColor: AppColors.pink,
                                      child: Text(
                                        '${index + 2}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      stop['address'].toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${stop['recipientName'] ?? ''} • ${stop['recipientPhone'] ?? ''}',
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Xóa điểm giao',
                                      onPressed: () => _rebuildCustomerUi(
                                        () => _additionalStops.removeAt(index),
                                      ),
                                      icon: const GhstButtonIcon(
                                        Icons.close_rounded,
                                        size: 18,
                                      ),
                                    ),
                                  );
                                }),
                              ],
                              if (_additionalStops.length < 4) ...[
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _extraDropoffCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Địa chỉ điểm giao phụ',
                                    prefixIcon: GhstButtonIcon(
                                      Icons.add_location_alt_outlined,
                                      size: 18,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _extraRecipientNameCtrl,
                                        decoration: const InputDecoration(
                                          labelText: 'Người nhận',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: _extraRecipientPhoneCtrl,
                                        keyboardType: TextInputType.phone,
                                        decoration: const InputDecoration(
                                          labelText: 'SĐT',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  alignment: WrapAlignment.end,
                                  children: [
                                    if (_additionalStops.isNotEmpty)
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.ink,
                                          foregroundColor: AppColors.acid,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                        ),
                                        onPressed: () {
                                          if (_dropoffCtrl.text
                                              .trim()
                                              .isEmpty) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Vui lòng nhập Điểm giao chính trước khi tối ưu thứ tự đa điểm!',
                                                    ),
                                                  ),
                                                );
                                            return;
                                          }
                                          final allStops =
                                              <Map<String, dynamic>>[
                                                {
                                                  'address': _dropoffCtrl.text
                                                      .trim(),
                                                  'recipientName':
                                                      _recipientNameCtrl.text
                                                          .trim(),
                                                  'recipientPhone':
                                                      _recipientPhoneCtrl.text
                                                          .trim(),
                                                  if (_pinnedDropoffLocation !=
                                                      null) ...{
                                                    'latitude':
                                                        _pinnedDropoffLocation!
                                                            .latitude,
                                                    'longitude':
                                                        _pinnedDropoffLocation!
                                                            .longitude,
                                                  },
                                                },
                                                ..._additionalStops.map(
                                                  (s) =>
                                                      Map<String, dynamic>.from(
                                                        s,
                                                      ),
                                                ),
                                              ];
                                          final tspRes =
                                              SmartDispatchEngine.optimizeMultiStopRoute(
                                                pickup: pPt,
                                                stops: allStops,
                                                isRoundTrip: _isRoundTrip,
                                              );
                                          if (tspRes.optimizedStops.isEmpty) {
                                            return;
                                          }
                                          final outboundRes =
                                              SmartDispatchEngine.optimizeMultiStopRoute(
                                                pickup: pPt,
                                                stops: tspRes.optimizedStops,
                                                isRoundTrip: false,
                                              );
                                          final firstStop =
                                              tspRes.optimizedStops.first;
                                          _rebuildCustomerUi(() {
                                            _dropoffCtrl.text =
                                                (firstStop['address'] ?? '')
                                                    .toString();
                                            _recipientNameCtrl.text =
                                                (firstStop['recipientName'] ??
                                                        '')
                                                    .toString();
                                            _recipientPhoneCtrl.text =
                                                (firstStop['recipientPhone'] ??
                                                        '')
                                                    .toString();
                                            if (firstStop['latitude'] is num &&
                                                firstStop['longitude'] is num) {
                                              _pinnedDropoffLocation = GeoPoint(
                                                latitude:
                                                    (firstStop['latitude']
                                                            as num)
                                                        .toDouble(),
                                                longitude:
                                                    (firstStop['longitude']
                                                            as num)
                                                        .toDouble(),
                                              );
                                            }
                                            _additionalStops
                                              ..clear()
                                              ..addAll(
                                                tspRes.optimizedStops.skip(1),
                                              );
                                            _osrmPreviewPoints =
                                                tspRes.routePolyline;
                                            _osrmDistMeters = outboundRes
                                                .optimizedDistanceMeters;
                                            _osrmDurationSec = outboundRes
                                                .estimatedDurationSeconds;
                                            _lastTspSavedMeters =
                                                tspRes.savedDistanceMeters;
                                          });
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                tspRes.savedDistanceMeters > 0
                                                    ? 'Đã tối ưu 2-Opt TSP ${tspRes.optimizedStops.length} điểm giao • Tiết kiệm ${(tspRes.savedDistanceMeters / 1000.0).toStringAsFixed(2)} km!'
                                                    : 'Thứ tự ${tspRes.optimizedStops.length} điểm giao hiện tại đã là lộ trình ngắn nhất!',
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const GhstButtonIcon(
                                          Icons.route_rounded,
                                          size: 15,
                                        ),
                                        label: const Text(
                                          'Tối ưu đa điểm (2-Opt TSP)',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        final address = _extraDropoffCtrl.text
                                            .trim();
                                        if (address.isEmpty) return;
                                        _rebuildCustomerUi(() {
                                          _additionalStops.add({
                                            'address': address,
                                            'recipientName':
                                                _extraRecipientNameCtrl.text
                                                    .trim(),
                                            'recipientPhone':
                                                _extraRecipientPhoneCtrl.text
                                                    .trim(),
                                          });
                                          _extraDropoffCtrl.clear();
                                          _extraRecipientNameCtrl.clear();
                                          _extraRecipientPhoneCtrl.clear();
                                          _lastTspSavedMeters = null;
                                        });
                                      },
                                      icon: const GhstButtonIcon(Icons.add, size: 16),
                                      label: const Text('Thêm điểm giao'),
                                    ),
                                  ],
                                ),
                              ],
                              if (_lastTspSavedMeters != null) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    border: Border.all(
                                      color: AppColors.success,
                                    ),
                                  ),
                                  child: Text(
                                    _lastTspSavedMeters! > 0
                                        ? 'Lộ trình đa điểm đã sắp xếp tối ưu bằng Nearest-Neighbor + 2-Opt (rút ngắn ${(_lastTspSavedMeters! / 1000.0).toStringAsFixed(2)} km).'
                                        : 'Thứ tự các trạm giao đã tối ưu theo thuật toán 2-Opt TSP.',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ),
                              ],
                              const Divider(height: 16),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Giao hàng 2 chiều (Khứ hồi về điểm lấy)',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Tài xế mang chứng từ / hàng đổi trả quay lại điểm lấy (+60% cước cơ bản & km)',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Switch.adaptive(
                                    activeThumbColor: AppColors.violet,
                                    value: _isRoundTrip,
                                    onChanged: (val) => _rebuildCustomerUi(() {
                                      _isRoundTrip = val;
                                      _lastTspSavedMeters = null;
                                    }),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            const Text(
              '2. Thông tin người nhận',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _recipientNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Họ tên người nhận',
                      prefixIcon: GhstButtonIcon(Icons.person_outline, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _recipientPhoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại nhận',
                      prefixIcon: GhstButtonIcon(Icons.phone_outlined, size: 18),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '3. Đặc tính kiện hàng',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), isExpanded: true, initialValue: _pkgCategory, decoration: const InputDecoration(
                labelText: 'Phân loại hàng hóa',
                prefixIcon: GhstButtonIcon(Icons.inventory_2_outlined, size: 18),
              ), items:
                  <String>{
                        'Quần áo & Thời trang',
                        'Tài liệu & Hợp đồng',
                        'Thực phẩm & Đồ uống',
                        'Điện tử & Hàng dễ vỡ',
                        if (_pkgCategory.trim().isNotEmpty) _pkgCategory.trim(),
                      }
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(), onChanged: (v) {
                if (v != null) {
                  _rebuildCustomerUi(() {
                    _pkgCategory = v;
                  });
                }
              },),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _weightCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _rebuildCustomerUi(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Trọng lượng (kg)',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _dimCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kích thước (D x R x C)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final hasDeclaredVal = _declaredValueCtrl.text
                    .trim()
                    .isNotEmpty;
                final showInsuranceInput =
                    _expandInsuranceSection || hasDeclaredVal;
                final rawVal =
                    double.tryParse(_declaredValueCtrl.text.trim()) ?? 0.0;
                final fee = PricingEstimate.calculateInsuranceFee(rawVal);
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    border: Border.all(color: AppColors.ink, width: 1.1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: () => _rebuildCustomerUi(
                          () => _expandInsuranceSection =
                              !_expandInsuranceSection,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          child: Row(
                            children: [
                              const GhstButtonIcon(
                                Icons.verified_user_outlined,
                                size: 17,
                                color: AppColors.violet,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  rawVal > 0
                                      ? 'Khai giá bảo hiểm: +${CurrencyFormatter.formatVnd(fee)} (0.5%)'
                                      : 'Khai giá bảo hiểm hàng hóa (0.5% • Tùy chọn)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              GhstButtonIcon(
                                showInsuranceInput
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 19,
                                color: AppColors.ink,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (showInsuranceInput)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                          child: TextField(
                            controller: _declaredValueCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _rebuildCustomerUi(() {}),
                            decoration: InputDecoration(
                              labelText: 'Giá trị hàng hóa khai báo (VNĐ)',
                              hintText:
                                  'VD: 5000000 (Đền bù tối đa 30.000.000đ)',
                              helperText: rawVal <= 0
                                  ? 'Đơn >= 3.000.000đ tự lọc Tài xế >= 4.5★ & ký quỹ >= 500k'
                                  : 'Phí bảo hiểm khai giá (0.5%): ${CurrencyFormatter.formatVnd(fee)}',
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pkgDescCtrl,
              onChanged: (_) => _rebuildCustomerUi(() {}),
              decoration: const InputDecoration(
                labelText: 'Ghi chú cho tài xế khi lấy/giao',
                prefixIcon: GhstButtonIcon(Icons.notes_rounded, size: 18),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildRightMapAndServiceColumn() {
      final baseScale = (_store.baseFareConfig / 25000.0).clamp(0.4, 5.0);
      double scaledBase(DeliveryServiceType s) =>
          (s.defaultBaseFare * baseScale).roundToDouble();
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.ink, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: AppColors.ink,
              offset: Offset(0, 4), blurRadius: 14,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Bản đồ Lộ trình & Chấm điểm trực tiếp',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final res = await SmartDispatchEngine.fetchLiveOsrmRoute(
                      pPt,
                      dPt,
                    );
                    if (!mounted) return;
                    if (res.polylinePoints.length >= 2) {
                      _store.activeRoutePolyline = res.polylinePoints;
                    }
                    _rebuildCustomerUi(() {
                      if (res.polylinePoints.length >= 2) {
                        _osrmPreviewPoints = res.polylinePoints;
                      }
                      _osrmDistMeters = res.distanceMeters;
                      _osrmDurationSec = res.durationSeconds;
                    });
                    final km = (res.distanceMeters / 1000.0).toStringAsFixed(1);
                    final mins = (res.durationSeconds / 60).round().clamp(
                      5,
                      240,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã cập nhật lộ trình thực tế: $km km (~$mins phút)',
                        ),
                      ),
                    );
                  },
                  icon: const GhstButtonIcon(Icons.alt_route, size: 15),
                  label: const Text(
                    'Tính tuyến đường',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Chạm trên bản đồ để ghim:',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel('[A] Điểm lấy hàng', size: 15, color: (!_mapPinTargetsDropoff) ? Colors.white : null), visualDensity: VisualDensity.compact, label: Text(
                    '[A] Điểm lấy hàng',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: !_mapPinTargetsDropoff
                          ? Colors.white
                          : AppColors.ink,
                    ),
                  ), selected: !_mapPinTargetsDropoff, selectedColor: AppColors.violet, onSelected: (_) =>
                      _rebuildCustomerUi(() => _mapPinTargetsDropoff = false),),
                ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel('[B] Điểm giao hàng', size: 15, color: (_mapPinTargetsDropoff) ? Colors.white : null), visualDensity: VisualDensity.compact, label: Text(
                    '[B] Điểm giao hàng',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _mapPinTargetsDropoff
                          ? Colors.white
                          : AppColors.ink,
                    ),
                  ), selected: _mapPinTargetsDropoff, selectedColor: AppColors.pink, onSelected: (_) =>
                      _rebuildCustomerUi(() => _mapPinTargetsDropoff = true),),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.ink, width: 1.4),
              ),
              child: Map3dPerspectiveWidget(
                height: 300,
                mode: MapViewMode.customerPreview,
                is3dMode: _store.isMap3dEnabled,
                speedKmh: 0,
                onToggle3d: _store.toggleMap3d,
                progressFraction: 0.0,
                singlePinPoint:
                    hasDropoffTarget ||
                        (_pinnedPickupLocation == null &&
                            _pickupCtrl.text.trim().isEmpty)
                    ? null
                    : pPt,
                singlePinLabel: '[A] Điểm lấy',
                routePoints: hasDropoffTarget
                    ? previewRoutePoints
                    : const <GeoPoint>[],
                pickupLabel: '[A] Điểm lấy',
                dropoffLabel: '[B] Điểm giao',
                nextTurnInstruction: hasDropoffTarget
                    ? 'Quãng đường: ${estDistKm.toStringAsFixed(1)} km • Dự kiến ~$estDurationMin phút'
                    : 'Chạm lên bản đồ để ghim Điểm giao hàng [B]',
                roadName:
                    (_pickupCtrl.text.trim().isEmpty &&
                        _dropoffCtrl.text.trim().isEmpty)
                    ? 'Chưa chọn lộ trình lấy & giao hàng'
                    : '${_pickupCtrl.text.trim().isEmpty ? "Chưa chọn điểm lấy" : _pickupCtrl.text.trim()} → ${_dropoffCtrl.text.trim().isEmpty ? "Chưa chọn điểm giao" : _dropoffCtrl.text.trim()}',
                onTapGeoPoint: (pt) async {
                  final targetDropoff = _mapPinTargetsDropoff;
                  _rebuildCustomerUi(() {
                    if (targetDropoff) {
                      _pinnedDropoffLocation = pt;
                    } else {
                      _userEditedPickupManually = true;
                      _pinnedPickupLocation = pt;
                    }
                  });
                  final resolvedAddr =
                      await SmartDispatchEngine.reverseGeocodeCoordinate(pt);
                  if (!mounted) return;
                  final nextP = targetDropoff ? pPt : pt;
                  final nextD = targetDropoff ? pt : dPt;
                  _rebuildCustomerUi(() {
                    if (targetDropoff) {
                      _dropoffCtrl.text = resolvedAddr;
                    } else {
                      _pickupCtrl.text = resolvedAddr;
                    }
                  });
                  if (_pickupCtrl.text.trim().isNotEmpty &&
                      _dropoffCtrl.text.trim().isNotEmpty) {
                    final routeRes =
                        await SmartDispatchEngine.fetchLiveOsrmRoute(
                          nextP,
                          nextD,
                        );
                    if (!mounted) return;
                    _rebuildCustomerUi(() {
                      if (routeRes.polylinePoints.length >= 2) {
                        _osrmPreviewPoints = routeRes.polylinePoints;
                      }
                      _osrmDistMeters = routeRes.distanceMeters;
                      _osrmDurationSec = routeRes.durationSeconds;
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '4. Chọn gói dịch vụ giao hàng',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
                Animated3dIconBadge(
                  style: _selectedService == DeliveryServiceType.express30m
                      ? Icon3dStyle.scooterExpress
                      : _selectedService == DeliveryServiceType.standard
                      ? Icon3dStyle.parcelBox
                      : _selectedService == DeliveryServiceType.saving
                      ? Icon3dStyle.walletVault
                      : Icon3dStyle.gpsPinRadar,
                  size: 34,
                  showRadarPulse: false,
                  isSelected: true,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildUc04ServiceCard(
                    title: 'Giao nhanh (Express)',
                    eta: 'Siêu tốc 30 phút',
                    priceLabel:
                        'Từ ${CurrencyFormatter.formatVnd(scaledBase(DeliveryServiceType.express30m))}',
                    icon: Icons.bolt_rounded,
                    iconColor: AppColors.pink,
                    selected:
                        _selectedService == DeliveryServiceType.express30m,
                    onTap: () => _rebuildCustomerUi(() {
                      _selectedService = DeliveryServiceType.express30m;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildUc04ServiceCard(
                    title: 'Giao nhanh 2H (Ghép đơn)',
                    eta: 'Ghép đơn cùng hướng • 2H',
                    priceLabel:
                        'Từ ${CurrencyFormatter.formatVnd(scaledBase(DeliveryServiceType.sameDay2h))}',
                    icon: Icons.hub_rounded,
                    iconColor: const Color(0xFF0EA5E9),
                    selected: _selectedService == DeliveryServiceType.sameDay2h,
                    onTap: () => _rebuildCustomerUi(() {
                      _selectedService = DeliveryServiceType.sameDay2h;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildUc04ServiceCard(
                    title: 'Giao tiêu chuẩn',
                    eta: 'Trong 2 giờ',
                    priceLabel:
                        'Từ ${CurrencyFormatter.formatVnd(scaledBase(DeliveryServiceType.standard))}',
                    icon: Icons.local_shipping_rounded,
                    iconColor: AppColors.violet,
                    selected: _selectedService == DeliveryServiceType.standard,
                    onTap: () => _rebuildCustomerUi(() {
                      _selectedService = DeliveryServiceType.standard;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildUc04ServiceCard(
                    title: 'Giao tiết kiệm',
                    eta: 'Trong 4 giờ',
                    priceLabel:
                        'Từ ${CurrencyFormatter.formatVnd(scaledBase(DeliveryServiceType.saving))}',
                    icon: Icons.savings_rounded,
                    iconColor: AppColors.success,
                    selected: _selectedService == DeliveryServiceType.saving,
                    onTap: () => _rebuildCustomerUi(() {
                      _selectedService = DeliveryServiceType.saving;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildUc04ServiceCard(
              title: 'Giao hàng lớn',
              eta: 'Xe tải / Hàng cồng kềnh • Hỗ trợ bốc xếp',
              priceLabel:
                  'Từ ${CurrencyFormatter.formatVnd(scaledBase(DeliveryServiceType.truck))}',
              icon: Icons.fire_truck_rounded,
              iconColor: AppColors.ink,
              selected: _selectedService == DeliveryServiceType.truck,
              onTap: () => _rebuildCustomerUi(() {
                _selectedService = DeliveryServiceType.truck;
              }),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                border: Border.all(color: AppColors.ink, width: 1.1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tùy chọn Giao Xanh & Hẹn giờ lấy hàng',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(showCheckmark: false, visualDensity: VisualDensity.compact, avatar: GhstButtonIcon(
                          Icons.electric_moped_rounded,
                          size: 15,
                          color: _preferEcoEv
                              ? Colors.white
                              : AppColors.success,
                        ), label: Text(
                          _preferEcoEv
                              ? 'Xe điện Xanh (Eco EV • -48g CO₂/km)'
                              : 'Ưu tiên Xe điện Xanh (Eco EV)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _preferEcoEv ? Colors.white : AppColors.ink,
                          ),
                        ), selected: _preferEcoEv, selectedColor: AppColors.success, onSelected: (v) => _rebuildCustomerUi(() {
                          _preferEcoEv = v;
                        }),),
                      FilterChip(showCheckmark: false, visualDensity: VisualDensity.compact, avatar: GhstButtonIcon(
                          Icons.park_rounded,
                          size: 15,
                          color: _greenFundContributed
                              ? Colors.white
                              : AppColors.success,
                        ), label: Text(
                          'Góp 1.000đ Quỹ Xanh',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _greenFundContributed
                                ? Colors.white
                                : AppColors.ink,
                          ),
                        ), selected: _greenFundContributed, selectedColor: const Color(0xFF059669), onSelected: (v) => _rebuildCustomerUi(() {
                          _greenFundContributed = v;
                        }),),
                      FilterChip(showCheckmark: false, visualDensity: VisualDensity.compact, avatar: GhstButtonIcon(
                          Icons.event_available_rounded,
                          size: 15,
                          color: _isScheduledDelivery
                              ? Colors.white
                              : AppColors.violet,
                        ), label: Text(
                          _isScheduledDelivery
                              ? 'Hẹn khung giờ lấy: $_scheduledDeliverySlot'
                              : 'Đặt lịch hẹn giờ lấy hàng',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _isScheduledDelivery
                                ? Colors.white
                                : AppColors.ink,
                          ),
                        ), selected: _isScheduledDelivery, selectedColor: AppColors.violet, onSelected: (v) =>
                            _rebuildCustomerUi(() => _isScheduledDelivery = v),),
                    ],
                  ),
                  if (_isScheduledDelivery) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          const [
                            '09:00 - 11:00',
                            '13:00 - 15:00',
                            '15:00 - 17:00',
                            '18:00 - 20:00',
                          ].map((slot) {
                            final isSlotSelected =
                                _scheduledDeliverySlot == slot;
                            return ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel(slot, size: 15, color: (isSlotSelected) ? Colors.white : null), visualDensity: VisualDensity.compact, label: Text(
                                slot,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: isSlotSelected
                                      ? Colors.white
                                      : AppColors.ink,
                                ),
                              ), selected: isSlotSelected, selectedColor: AppColors.violet, onSelected: (_) => _rebuildCustomerUi(
                                () => _scheduledDeliverySlot = slot,
                              ),);
                          }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.violet,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (!_validateOrderFormInputs()) return;
                  _rebuildCustomerUi(() => _selectedScreenIndex = 3);
                },
                icon: const GhstButtonIcon(Icons.receipt_long_rounded, size: 18),
                label: const Text(
                  'XEM CHI TIẾT CƯỚC PHÍ & ĐẶT ĐƠN',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 740) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: buildLeftFormColumn()),
              const SizedBox(width: 20),
              Expanded(flex: 5, child: buildRightMapAndServiceColumn()),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildLeftFormColumn(),
            const SizedBox(height: 16),
            buildRightMapAndServiceColumn(),
          ],
        );
      },
    );
  }

  bool _validateOrderFormInputs() {
    if (_pickupCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập Địa chỉ lấy hàng (Điểm đi)!'),
        ),
      );
      return false;
    }
    if (_dropoffCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập Địa chỉ giao hàng (Điểm đến)!'),
        ),
      );
      return false;
    }
    if (_pickupCtrl.text.trim().toLowerCase() ==
        _dropoffCtrl.text.trim().toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'Địa chỉ lấy hàng và Địa chỉ giao hàng không được trùng nhau!',
          ),
        ),
      );
      return false;
    }
    if (_recipientNameCtrl.text.trim().isEmpty ||
        _recipientPhoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập đầy đủ Họ tên và SĐT người nhận!'),
        ),
      );
      return false;
    }
    final cleanPhone = _recipientPhoneCtrl.text.trim().replaceAll(' ', '');
    if (!RegExp(r'^(\+84|0)[0-9]{8,10}$').hasMatch(cleanPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'Số điện thoại người nhận không hợp lệ (10-11 số bắt đầu bằng 0 hoặc +84)!',
          ),
        ),
      );
      return false;
    }
    final weightVal = double.tryParse(_weightCtrl.text.trim());
    if (weightVal == null || weightVal <= 0 || weightVal > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'Khối lượng kiện hàng phải lớn hơn 0 và tối đa 500 kg!',
          ),
        ),
      );
      return false;
    }
    final codVal = double.tryParse(
      _codCtrl.text.trim().isEmpty ? '0' : _codCtrl.text.trim(),
    );
    if (codVal == null || codVal < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Số tiền thu hộ COD không được là số âm!'),
        ),
      );
      return false;
    }
    final pPt =
        _pinnedPickupLocation ??
        (_pickupCtrl.text.trim().isEmpty && _store.liveDeviceLocation != null
            ? _store.liveDeviceLocation!
            : SmartDispatchEngine.resolveAddressToCoordinate(
                _pickupCtrl.text,
                fallback:
                    _store.liveDeviceLocation ??
                    const GeoPoint(latitude: 10.7769, longitude: 106.6953),
              ));
    final dPt =
        _pinnedDropoffLocation ??
        SmartDispatchEngine.resolveAddressToCoordinate(
          _dropoffCtrl.text,
          fallback: const GeoPoint(latitude: 10.7688, longitude: 106.6820),
        );
    final restrictedZone = _store.findActiveRestrictedZoneForRoute(pPt, dPt);
    if (restrictedZone != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'Lộ trình nằm trong vùng hạn chế giao nhận "${restrictedZone.zoneName}". Vui lòng chọn địa điểm khác!',
          ),
        ),
      );
      return false;
    }
    return true;
  }

  Widget _buildUc04ServiceCard({
    required String title,
    required String eta,
    required String priceLabel,
    required IconData icon,
    required Color iconColor,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF4F7FA) : Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(12)),
          border: Border.all(
            color: selected ? const Color(0xFF2563EB) : const Color(0xFF0F172A),
            width: selected ? 2.0 : 1.0,
          ),
        ),
        child: Stack(
          children: [
            if (selected)
              const Positioned(
                top: 0,
                right: 0,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: Color(0xFFF43F5E),
                  child: GhstButtonIcon(Icons.check, size: 13, color: Colors.white),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  child: GhstButtonIcon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  eta,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF4A4754),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  priceLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: selected
                        ? const Color(0xFFF43F5E)
                        : const Color(0xFF2563EB),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// UC05, UC11 & UC07: Xem ước tính chi phí, Mã giảm giá & Thanh toán đơn hàng
  Widget _buildPricingAndVoucherView() {
    final pickupPt =
        _pinnedPickupLocation ??
        SmartDispatchEngine.resolveAddressToCoordinate(
          _pickupCtrl.text,
          fallback: const GeoPoint(latitude: 10.7769, longitude: 106.6953),
        );
    final dropoffPt =
        _pinnedDropoffLocation ??
        SmartDispatchEngine.resolveAddressToCoordinate(
          _dropoffCtrl.text,
          fallback: const GeoPoint(latitude: 10.7688, longitude: 106.6820),
        );
    var lastDropoffPt = dropoffPt;
    int distMeters;
    int durationSec;
    if (_additionalStops.isEmpty) {
      final rawAirMeters = GeoMath.distanceMeters(pickupPt, dropoffPt);
      distMeters =
          _osrmDistMeters ?? (rawAirMeters * 1.28).round().clamp(1500, 45000);
      durationSec = _osrmDurationSec ?? ((distMeters / 1000.0) * 180).round();
    } else {
      var routeMeters = GeoMath.distanceMeters(pickupPt, dropoffPt) * 1.28;
      var prevPt = dropoffPt;
      for (final stop in _additionalStops) {
        final addr = (stop['address'] ?? '').toString().trim();
        if (addr.isEmpty) continue;
        final sPt = (stop['latitude'] is num && stop['longitude'] is num)
            ? GeoPoint(
                latitude: (stop['latitude'] as num).toDouble(),
                longitude: (stop['longitude'] as num).toDouble(),
              )
            : SmartDispatchEngine.resolveAddressToCoordinate(
                addr,
                fallback: prevPt,
              );
        routeMeters += GeoMath.distanceMeters(prevPt, sPt) * 1.28;
        prevPt = sPt;
        lastDropoffPt = sPt;
      }
      distMeters = _osrmDistMeters ?? routeMeters.round().clamp(1500, 45000);
      durationSec =
          _osrmDurationSec ??
          (((distMeters / 1000.0) * 180).round() +
              _additionalStops.length * 180);
    }

    double geofenceFee = _store.computeGeofenceSurchargeForPoint(lastDropoffPt);
    if (_store.isWeatherSurchargeActive) {
      geofenceFee += _store.badWeatherSurchargeConfig;
    }
    final weightVal = double.tryParse(_weightCtrl.text.trim()) ?? 1.5;
    if (weightVal > 5.0) {
      geofenceFee += ((weightVal - 5.0) * 3000).roundToDouble();
    }
    final combinedDesc = '$_pkgCategory ${_pkgDescCtrl.text}'.toLowerCase();
    if (combinedDesc.contains('dễ vỡ')) {
      geofenceFee += 5000;
    }
    if (combinedDesc.contains('giữ lạnh')) {
      geofenceFee += 10000;
    }

    final baseScale = (_store.baseFareConfig / 25000.0).clamp(0.4, 5.0);
    final kmScale = (_store.pricePerKmConfig / 5000.0).clamp(0.4, 5.0);
    final rawDeclaredVal =
        double.tryParse(_declaredValueCtrl.text.trim()) ?? 0.0;
    final safeDeclaredValue = rawDeclaredVal.isFinite && rawDeclaredVal > 0
        ? rawDeclaredVal.clamp(0.0, PricingEstimate.maxInsuredDeclaredValueVnd)
        : 0.0;
    final extraStopCount = _additionalStops
        .where((s) => (s['address'] ?? '').toString().trim().isNotEmpty)
        .length;

    final preEst = PricingEstimate.calculate(
      serviceType: _selectedService,
      distanceMeters: distMeters,
      durationSeconds: durationSec,
      isPeakHour: _store.isPeakSurchargeActive,
      geofenceSurcharge: geofenceFee,
      voucherDiscount: 0,
      baseFareScale: baseScale,
      pricePerKmScale: kmScale,
      configuredStandardPeakSurcharge: _store.peakHourSurchargeConfig,
      declaredValueVnd: safeDeclaredValue,
      extraStopCount: extraStopCount,
      isRoundTrip: _isRoundTrip,
      greenFundContribution: _greenFundContributed,
      preferEcoEv: _preferEcoEv,
    );

    double discountVal = 0;
    final code = _voucherCtrl.text.trim().toUpperCase();
    final codVal = double.tryParse(_codCtrl.text) ?? 0.0;
    final matchedVoucher = _store.vouchers
        .where((v) => v.code == code)
        .firstOrNull;
    if (matchedVoucher != null &&
        matchedVoucher.isUsable &&
        (preEst.totalAmount + codVal) >= matchedVoucher.minOrderValue) {
      if (matchedVoucher.isPercentage) {
        discountVal =
            (preEst.totalAmount * (matchedVoucher.discountValue / 100.0)).clamp(
              0.0,
              matchedVoucher.maxDiscount,
            );
      } else {
        discountVal = matchedVoucher.discountValue;
      }
    }

    final estimate = PricingEstimate.calculate(
      serviceType: _selectedService,
      distanceMeters: distMeters,
      durationSeconds: durationSec,
      isPeakHour: _store.isPeakSurchargeActive,
      geofenceSurcharge: geofenceFee,
      voucherDiscount: discountVal,
      baseFareScale: baseScale,
      pricePerKmScale: kmScale,
      configuredStandardPeakSurcharge: _store.peakHourSurchargeConfig,
      declaredValueVnd: safeDeclaredValue,
      extraStopCount: extraStopCount,
      isRoundTrip: _isRoundTrip,
      greenFundContribution: _greenFundContributed,
      preferEcoEv: _preferEcoEv,
    );

    return Card(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.ink, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Animated3dIconBadge(
                      style: Icon3dStyle.walletVault,
                      size: 46,
                      showRadarPulse: false,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Xem ước tính chi phí',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                          Text(
                            'Xác nhận giá cước & Áp dụng Voucher (${estimate.distanceKm.toStringAsFixed(1)} km • ~${(durationSec / 60).round().clamp(5, 240)} phút)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4A4754),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _rebuildCustomerUi(() => _selectedScreenIndex = 2),
                  icon: const GhstButtonIcon(Icons.arrow_back_rounded, size: 15),
                  label: const Text(
                    'Quay lại sửa đơn',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Hộp Tóm tắt ước tính với Header xanh dương #1565C0 giống uc05_uoc_tinh_chi_phi.jpg
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.all(color: const Color(0xFF0F172A)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: const Color(0xFF2563EB),
                    child: const Text(
                      'Tóm tắt ước tính',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        _priceRow(
                          'Phí mở cửa cơ bản (${_selectedService.displayName})',
                          CurrencyFormatter.formatVnd(estimate.baseFare),
                        ),
                        _priceRow(
                          'Phí theo km (${estimate.distanceKm.toStringAsFixed(1)} km)',
                          CurrencyFormatter.formatVnd(estimate.distanceFare),
                        ),
                        _priceRow(
                          'Phụ phí giờ cao điểm & Geofence',
                          CurrencyFormatter.formatVnd(
                            estimate.surchargeFee -
                                estimate.multiStopFee -
                                estimate.roundTripFee -
                                estimate.insuranceFee -
                                estimate.greenContributionFee,
                          ),
                        ),
                        if (estimate.multiStopFee > 0)
                          _priceRow(
                            'Phụ phí đa điểm dừng (+$extraStopCount điểm)',
                            CurrencyFormatter.formatVnd(estimate.multiStopFee),
                          ),
                        if (estimate.roundTripFee > 0)
                          _priceRow(
                            'Phụ phí giao 2 chiều khứ hồi (+60%)',
                            CurrencyFormatter.formatVnd(estimate.roundTripFee),
                          ),
                        if (estimate.insuranceFee > 0)
                          _priceRow(
                            'Phí bảo hiểm khai giá (${CurrencyFormatter.formatVnd(safeDeclaredValue)})',
                            CurrencyFormatter.formatVnd(estimate.insuranceFee),
                          ),
                        if (estimate.greenContributionFee > 0)
                          _priceRow(
                            'Đóng góp Quỹ Xanh Vì Tương Lai',
                            CurrencyFormatter.formatVnd(
                              estimate.greenContributionFee,
                            ),
                            valueColor: AppColors.success,
                          ),
                        if (_preferEcoEv && estimate.estimatedCo2SavedGrams > 0)
                          _priceRow(
                            'Giảm phát thải Xe điện Xanh (Eco EV)',
                            '-${estimate.estimatedCo2SavedGrams.toStringAsFixed(0)}g CO₂',
                            valueColor: AppColors.success,
                          ),
                        _priceRow(
                          code.isEmpty
                              ? 'Giảm giá (Khuyến mãi)'
                              : 'Giảm giá (Mã khuyến mãi $code)',
                          '-${CurrencyFormatter.formatVnd(estimate.discountAmount)}',
                          valueColor: const Color(0xFF14B866),
                        ),
                        const Divider(height: 18),
                        _priceRow(
                          'Tổng cộng',
                          CurrencyFormatter.formatVnd(estimate.totalAmount),
                          isBold: true,
                          valueColor: const Color(0xFFF43F5E),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _showVoucherPicker,
              icon: const GhstButtonIcon(Icons.local_offer_outlined),
              label: Text(code.isEmpty ? 'Chọn ưu đãi' : 'Ưu đãi: $code'),
            ),
            if (code.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _rebuildCustomerUi(() {
                    _voucherCtrl.clear();
                  }),
                  icon: const GhstButtonIcon(Icons.close, size: 16),
                  label: const Text('Bỏ ưu đãi'),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Phương thức thanh toán',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final method in const [
                  'Tiền mặt (COD)',
                  'Chuyển khoản Ngân hàng',
                  'Quét mã VietQR',
                ])
                  ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel(method, size: 15, color: (_selectedPaymentMethod == method) ? Colors.white : null), label: Text(method), selected: _selectedPaymentMethod == method, selectedColor: const Color(0xFF2563EB), labelStyle: TextStyle(
                      color: _selectedPaymentMethod == method
                          ? Colors.white
                          : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w700,
                    ), onSelected: (_) => _rebuildCustomerUi(
                      () => _selectedPaymentMethod = method,
                    ),),
              ],
            ),
            if (_selectedPaymentMethod != 'Tiền mặt (COD)') ...[
              const SizedBox(height: 10),
              VietQrBankPaymentPanel(
                amountVnd: estimate.totalAmount,
                orderReference: 'DON GIAO HANG',
                selectedPayerBankBin: _selectedBankBin,
                compact: true,
                onPayerBankChanged: (bank) => _rebuildCustomerUi(() {
                  _selectedBankBin = bank.bin;
                  _selectedBankShortName = bank.shortName;
                }),
                reconciliationNote:
                    'Sau khi tạo đơn, hệ thống sẽ cấp mã vận đơn riêng để đối soát chuyển khoản.',
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final codField = TextField(
                    controller: _codCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _rebuildCustomerUi(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Tiền thu hộ COD (đ)',
                      hintText: '0',
                    ),
                  );
                  if (constraints.maxWidth < 480) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const GhstButtonIcon(
                              Icons.account_balance_wallet_rounded,
                              color: Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Phương thức đã chọn: $_selectedPaymentMethod',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        codField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      const GhstButtonIcon(
                        Icons.account_balance_wallet_rounded,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Phương thức đã chọn: $_selectedPaymentMethod',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ),
                      SizedBox(width: 170, child: codField),
                    ],
                  );
                },
              ),
            ),
            if (_selectedPaymentMethod == 'Tiền mặt (COD)') ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Người thanh toán cước ship:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  for (final payer in const [
                    'Người gửi trả phí',
                    'Người nhận trả phí',
                  ])
                    ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel(payer, size: 15, color: (_cashFeePayer == payer) ? Colors.white : null), visualDensity: VisualDensity.compact, label: Text(
                        payer,
                        style: const TextStyle(fontSize: 11.5),
                      ), selected: _cashFeePayer == payer, selectedColor: const Color(0xFF2563EB), labelStyle: TextStyle(
                        color: _cashFeePayer == payer
                            ? Colors.white
                            : const Color(0xFF0F172A),
                        fontWeight: FontWeight.w700,
                      ), onSelected: (_) =>
                          _rebuildCustomerUi(() => _cashFeePayer = payer),),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final ownerId = _store.activeAuthenticatedUser?.id;
                  if (!_validateOrderFormInputs()) {
                    _rebuildCustomerUi(() => _selectedScreenIndex = 2);
                    return;
                  }
                  final scheduleNote = _isScheduledDelivery
                      ? ' [Hẹn giờ: $_scheduledDeliverySlot]'
                      : '';
                  final descText = _pkgDescCtrl.text.trim().isEmpty
                      ? '$_pkgCategory$scheduleNote'
                      : '$_pkgCategory - ${_pkgDescCtrl.text.trim()}$scheduleNote';
                  final isBankQrSelected =
                      _selectedPaymentMethod != 'Tiền mặt (COD)';
                  final effectivePaymentMethod = isBankQrSelected
                      ? 'Ngân hàng · VietQR · $_selectedBankShortName'
                      : (_cashFeePayer == 'Người nhận trả phí'
                            ? 'Người nhận trả phí'
                            : _selectedPaymentMethod);
                  final created = _store.createNewOrder(
                    pickupAddress: _pickupCtrl.text.trim(),
                    dropoffAddress: _dropoffCtrl.text.trim(),
                    recipientName: _recipientNameCtrl.text.trim(),
                    recipientPhone: _recipientPhoneCtrl.text.trim(),
                    packageDescription: descText,
                    weightKg: double.tryParse(_weightCtrl.text) ?? 1.5,
                    dimensionsCm: _dimCtrl.text,
                    serviceType: _selectedService,
                    codAmount: double.tryParse(_codCtrl.text) ?? 0,
                    paymentMethod: effectivePaymentMethod,
                    voucherCode: _voucherCtrl.text,
                    customDistanceMeters: _additionalStops.isEmpty
                        ? distMeters
                        : null,
                    customDurationSeconds: _additionalStops.isEmpty
                        ? durationSec
                        : null,
                    isPrepaidConfirmed: false,
                    customPickupLocation: _pinnedPickupLocation,
                    customDropoffLocation: _pinnedDropoffLocation,
                    additionalStops: List<Map<String, dynamic>>.from(
                      _additionalStops,
                    ),
                    preferEcoEv: _preferEcoEv,
                    declaredValueVnd: safeDeclaredValue,
                    isRoundTrip: _isRoundTrip,
                    greenFundContributed: _greenFundContributed,
                  );
                  if (_isScheduledDelivery) {
                    await _store.scheduleOrder(
                      orderId: created.id,
                      scheduledAt: _nextScheduledDateTime(
                        _scheduledDeliverySlot,
                      ),
                    );
                  }
                  if (!context.mounted ||
                      ownerId != _store.activeAuthenticatedUser?.id) {
                    return;
                  }
                  final savedDraftId = _editingDraftId;
                  _editingDraftId = null;
                  if (savedDraftId != null) {
                    try {
                      await _store.deleteCustomerOrderDraft(savedDraftId);
                    } catch (_) {
                      // The order is committed even if draft cleanup fails.
                    }
                    _draftsFuture = null;
                    if (!context.mounted ||
                        ownerId != _store.activeAuthenticatedUser?.id) {
                      return;
                    }
                  }
                  final batchInfo = created.batchGroupId != null
                      ? ' • Đã ghép cặp đơn 2H (${created.batchGroupId})'
                      : '';
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã đặt đơn hàng ${created.trackingCode} thành công!$batchInfo',
                      ),
                    ),
                  );
                  if (isBankQrSelected && context.mounted) {
                    await _showLegacyBankQrPaymentDialog(created);
                  }
                  _rebuildCustomerUi(() {
                    _dropoffCtrl.clear();
                    _recipientNameCtrl.clear();
                    _recipientPhoneCtrl.clear();
                    _pkgDescCtrl.clear();
                    _voucherCtrl.clear();
                    _codCtrl.clear();
                    _declaredValueCtrl.clear();
                    _additionalStops.clear();
                    _isRoundTrip = false;
                    _lastTspSavedMeters = null;
                    _pinnedDropoffLocation = null;
                    _osrmPreviewPoints = null;
                    _osrmDistMeters = null;
                    _osrmDurationSec = null;
                    _resetCustomerOrderForm();
                    _syncCustomerControllersFromDb();
                    _selectedScreenIndex = 4;
                  });
                },
                icon: const GhstButtonIcon(Icons.local_shipping_outlined),
                label: const Text(
                  'Đặt đơn ngay',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _nextScheduledDateTime(String slot) {
    final match = RegExp(r'^(\d{2}):(\d{2})').firstMatch(slot);
    final hour = int.tryParse(match?.group(1) ?? '') ?? 13;
    final minute = int.tryParse(match?.group(2) ?? '') ?? 0;
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day + 1, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Widget _priceRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
                fontSize: isBold ? 15 : 13.5,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              fontSize: isBold ? 17 : 13.5,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// UC06: Theo dõi đơn hàng GPS Thời gian thực (Khớp 100% uc06_theo_doi_gps_1791014402627.jpg)
  Widget _buildLiveGpsTrackingView() {
    final activeOrder = _store.activeCustomerOrderRecord;
    if (activeOrder == null) {
      return Card(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: AppColors.ink, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Theo dõi đơn hàng',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                        Text(
                          'Theo dõi Tài xế GPS 3D Thời gian thực',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4A4754),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F7FA),
                      border: Border.all(color: const Color(0xFF0F172A)),
                    ),
                    child: const Text(
                      'Chưa có chuyến giao',
                      style: TextStyle(
                        color: Color(0xFF4A4754),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Map3dPerspectiveWidget(
                height: 420,
                mode: MapViewMode.customerPreview,
                is3dMode: _store.isMap3dEnabled,
                speedKmh: 0,
                onToggle3d: _store.toggleMap3d,
                progressFraction: 0.0,
                singlePinPoint: _store.liveDeviceLocation,
                singlePinLabel: _store.liveDeviceLocation != null
                    ? 'Vị trí GPS thật của bạn'
                    : 'Vị trí của bạn',
                nextTurnInstruction: 'Hệ thống định vị GPS sẵn sàng theo dõi lộ trình khi bạn tạo đơn',
                roadName: _store.liveDeviceAddress.trim().isNotEmpty
                    ? 'GPS Thiết bị: ${_store.liveDeviceAddress.trim()}'
                    : (_store.customerDefaultAddress.isNotEmpty
                          ? _store.customerDefaultAddress
                          : 'Chưa có vận đơn đang vận chuyển'),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FA),
                  border: Border.all(color: const Color(0xFF0F172A)),
                ),
                child: Row(
                  children: [
                    const Animated3dIconBadge(
                      style: Icon3dStyle.gpsPinRadar,
                      size: 52,
                      showRadarPulse: true,
                      isSelected: true,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Hiện chưa có đơn hàng nào đang vận chuyển',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Khi bạn đặt đơn hàng mới, lộ trình GPS 3D và thông tin tài xế nhận chuyến sẽ hiển thị trực tiếp tại đây.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4A4754),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.violet,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _rebuildCustomerUi(
                              () => _selectedScreenIndex = 2,
                            ),
                            icon: const GhstButtonIcon(Icons.add_box_rounded, size: 17),
                            label: const Text('Tạo đơn hàng mới'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final remMeters = _store.distanceFromDriverToOrderDropoffMeters(
      activeOrder,
    );
    final etaMinutes = (remMeters / 500.0).ceil().clamp(1, 45);
    final deliveryOtp4 = SecurityAndBarcodeUtils.generateOrderDeliveryOtp4(
      activeOrder.trackingCode,
    );
    final isSearching =
        activeOrder.status == OrderStatus.searching ||
        activeOrder.status == OrderStatus.draft;
    final isAccepted =
        activeOrder.status == OrderStatus.accepted ||
        activeOrder.status == OrderStatus.arrivingPickup;
    final isInTransit = activeOrder.status == OrderStatus.inTransit;
    final isDelivered = activeOrder.status == OrderStatus.delivered;
    final isCancelled = activeOrder.status == OrderStatus.cancelled;
    final isFailedOrReturning =
        activeOrder.status == OrderStatus.failed ||
        activeOrder.status == OrderStatus.returning;
    final assignedDriverRecord = activeOrder.assignedDriverName == null
        ? null
        : _store.drivers
              .where(
                (d) =>
                    d.fullName.trim().toLowerCase() ==
                    activeOrder.assignedDriverName!.trim().toLowerCase(),
              )
              .firstOrNull;
    final isLiveSyncedOrder =
        activeOrder.id == _store.activeOrderRecord?.id &&
        !isSearching &&
        !isDelivered &&
        !isCancelled &&
        !isFailedOrReturning;
    final mapSpeedKmh = isLiveSyncedOrder
        ? _store.currentSpeedKmh
        : ((assignedDriverRecord != null &&
                  assignedDriverRecord.isOnline &&
                  (isAccepted || isInTransit))
              ? _store.currentSpeedKmh
              : 0.0);
    final distRatio = activeOrder.distanceMeters > 0
        ? (1.0 - (remMeters / activeOrder.distanceMeters).clamp(0.0, 1.0))
        : 0.0;
    final mapProgress = isDelivered
        ? 1.0
        : (isSearching || isCancelled || isFailedOrReturning
              ? 0.0
              : (isLiveSyncedOrder
                    ? (_store.routeProgressStep > 0
                          ? (_store.routeProgressStep / 10.0).clamp(0.0, 1.0)
                          : distRatio.clamp(0.08, 0.96))
                    : distRatio.clamp(isInTransit ? 0.25 : 0.05, 0.95)));

    return Card(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.ink, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LiveOrderConnection(
              key: ValueKey('live-${activeOrder.trackingCode}'),
              room: activeOrder.trackingCode,
            ),
            Builder(
              builder: (context) {
                final currentNote = _store.quickDeliveryInstructionFor(
                  activeOrder.trackingCode,
                );
                const quickNotes = [
                  'Gọi trước 5 phút',
                  'Gửi lễ tân tầng trệt',
                  'Không bấm chuông',
                ];
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    border: Border.all(color: const Color(0xFF2563EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'Chỉ dẫn giao nhanh 1-chạm:',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          ...quickNotes.map((note) {
                            final selected = currentNote == note;
                            return ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel(note, size: 15, color: (selected) ? Colors.white : null), visualDensity: VisualDensity.compact, label: Text(
                                note,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ), selected: selected, selectedColor: const Color(0xFF2563EB), onSelected: (_) {
                                _store.setQuickDeliveryInstruction(
                                  activeOrder.trackingCode,
                                  selected ? '' : note,
                                );
                                _rebuildCustomerUi(() {});
                              },);
                          }),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Theo dõi đơn hàng',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    Text(
                      'Theo dõi Tài xế GPS 3D Thời gian thực',
                      style: TextStyle(fontSize: 12, color: Color(0xFF4A4754)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F7FA),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    border: Border.all(color: const Color(0xFF93C5FD)),
                  ),
                  child: Text(
                    isDelivered
                        ? 'Đã giao thành công • Hoàn tất 100%'
                        : isCancelled
                        ? 'Đã hủy đơn • ${activeOrder.cancelReason ?? "Khách hủy"}'
                        : isFailedOrReturning
                        ? '${activeOrder.status.displayName} • ${activeOrder.cancelReason ?? "Đang xử lý sự cố"}'
                        : isSearching
                        ? 'Trạng thái: ${activeOrder.status.displayName}'
                        : 'Dự kiến: ~$etaMinutes phút nữa (${(remMeters / 1000).toStringAsFixed(2)} km)',
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (!isDelivered && !isCancelled && !isFailedOrReturning)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      border: Border.all(color: const Color(0xFF14B866)),
                    ),
                    child: Text(
                      'OTP nhận hàng: $deliveryOtp4',
                      style: const TextStyle(
                        color: Color(0xFF14B866),
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                if (activeOrder.preferEcoEv || activeOrder.co2SavedGrams > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: Text(
                      'Xe điện Xanh • -${activeOrder.co2SavedGrams.toStringAsFixed(0)}g CO₂',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                if (activeOrder.batchGroupId != null &&
                    activeOrder.batchGroupId!.trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      border: Border.all(color: const Color(0xFF0EA5E9)),
                    ),
                    child: Text(
                      'Ghép đơn 2H: ${activeOrder.batchGroupId}',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                if (activeOrder.declaredValueVnd > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      border: Border.all(color: AppColors.ink),
                    ),
                    child: Text(
                      'Bảo hiểm: ${CurrencyFormatter.formatVnd(activeOrder.declaredValueVnd)}',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                if (activeOrder.isRoundTrip)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE9FE),
                      border: Border.all(color: AppColors.violet),
                    ),
                    child: const Text(
                      'Giao 2 chiều (Khứ hồi)',
                      style: TextStyle(
                        color: AppColors.violet,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
              ],
            ),
            if (_store.customerOrders.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _store.customerOrders.map((ordItem) {
                  final isCurrent =
                      ordItem.trackingCode == activeOrder.trackingCode;
                  return ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.glyph(GhstActionKind.receipt, size: 15, color: (isCurrent) ? Colors.white : null), visualDensity: VisualDensity.compact, label: Text(
                      '${ordItem.trackingCode} (${ordItem.status.displayName})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isCurrent ? Colors.white : AppColors.ink,
                      ),
                    ), selected: isCurrent, selectedColor: const Color(0xFF2563EB), onSelected: (_) => _rebuildCustomerUi(() {
                      _store.selectCustomerOrder(ordItem.trackingCode);
                    }),);
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            Map3dPerspectiveWidget(
              height: 520,
              mode: MapViewMode.customerLiveTracking,
              is3dMode: _store.isMap3dEnabled,
              speedKmh: mapSpeedKmh,
              onToggle3d: _store.toggleMap3d,
              driverLocation: _store.verifiedLocationForOrder(activeOrder),
              progressFraction: mapProgress,
              routePoints:
                  activeOrder.id == _store.activeOrderRecord?.id &&
                      _store.activeRoutePolyline.length >= 2
                  ? _store.activeRoutePolyline
                  : SmartDispatchEngine.generateRoutePolyline(
                      activeOrder.pickupLocation,
                      activeOrder.dropoffLocation,
                      segments: 10,
                    ),
              pickupLabel: '[A] Lấy hàng',
              dropoffLabel: '[B] Giao hàng',
              nextTurnInstruction: isDelivered
                  ? 'Đơn ${activeOrder.trackingCode} đã giao hoàn tất tại điểm nhận'
                  : isCancelled
                  ? 'Đơn ${activeOrder.trackingCode} đã hủy (${activeOrder.cancelReason ?? "Khách hủy"})'
                  : isFailedOrReturning
                  ? 'Đơn ${activeOrder.trackingCode}: ${activeOrder.status.displayName} (${activeOrder.cancelReason ?? "Đang xử lý"})'
                  : isSearching
                  ? 'Hệ thống đang định tuyến và điều phối tài xế cho mã ${activeOrder.trackingCode}'
                  : 'Tài xế cách điểm giao ${(remMeters / 1000).toStringAsFixed(2)} km (ETA: $etaMinutes phút)',
              roadName:
                  '${activeOrder.pickupAddress} → ${activeOrder.dropoffAddress}',
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  _buildUc06StepNode(
                    isCancelled
                        ? 'Đã hủy đơn'
                        : isFailedOrReturning
                        ? activeOrder.status.displayName
                        : 'Đã tạo đơn',
                    done: !isSearching && !isCancelled && !isFailedOrReturning,
                    active: isSearching || isCancelled || isFailedOrReturning,
                  ),
                  _buildUc06StepLine(
                    done: !isSearching && !isCancelled && !isFailedOrReturning,
                  ),
                  _buildUc06StepNode(
                    'Tài xế nhận',
                    done: isInTransit || isDelivered,
                    active: isAccepted,
                  ),
                  _buildUc06StepLine(done: isInTransit || isDelivered),
                  _buildUc06StepNode(
                    'Đang giao',
                    done: isDelivered,
                    active: isInTransit,
                  ),
                  _buildUc06StepLine(done: isDelivered),
                  _buildUc06StepNode(
                    'Hoàn thành',
                    done: isDelivered,
                    active: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.all(color: const Color(0xFF0F172A)),
              ),
              child: Row(
                children: [
                  const Animated3dIconBadge(
                    style: Icon3dStyle.scooterExpress,
                    size: 52,
                    showRadarPulse: true,
                    isSelected: true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeOrder.assignedDriverName != null
                              ? ((assignedDriverRecord?.rating ?? 0) > 0
                                    ? '${activeOrder.assignedDriverName} • ★ ${assignedDriverRecord!.rating.toStringAsFixed(1)}'
                                    : '${activeOrder.assignedDriverName} • Chưa có đánh giá')
                              : 'Đang tìm tài xế nhận chuyến...',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activeOrder.assignedDriverName != null
                              ? '${assignedDriverRecord?.vehicleType ?? "Xe máy"} • ${activeOrder.assignedDriverPlate ?? assignedDriverRecord?.licensePlate ?? "Chưa cập nhật biển số"} • Mã: ${activeOrder.trackingCode}'
                              : 'Mã vận đơn: ${activeOrder.trackingCode} • Dịch vụ: ${activeOrder.serviceType.displayName}',
                          style: const TextStyle(
                            color: Color(0xFF4A4754),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (activeOrder.assignedDriverName != null) ...[
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                      ),
                      onPressed: () {
                        final rawPhone = assignedDriverRecord?.phone ?? '';
                        final isClosed =
                            isDelivered ||
                            isCancelled ||
                            activeOrder.status == OrderStatus.failed ||
                            activeOrder.status == OrderStatus.returning ||
                            activeOrder.paymentStatus == 'RETURNED';
                        final maskedPhone = rawPhone.isNotEmpty
                            ? SecurityAndBarcodeUtils.maskPhoneNumber(
                                rawPhone,
                                shouldMask: isClosed,
                              )
                            : 'Chưa có SĐT';
                        if (rawPhone.isNotEmpty && !isClosed) {
                          Clipboard.setData(ClipboardData(text: rawPhone));
                          _store.sendChatMessage(
                            activeOrder.trackingCode,
                            '[Cuộc gọi] Khách hàng liên hệ tài xế ($maskedPhone)',
                            isCustomer: true,
                          );
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              rawPhone.isNotEmpty && !isClosed
                                  ? 'Đã sao chép SĐT tài xế ($rawPhone) và ghi nhận yêu cầu gọi điện!'
                                  : 'Thông tin liên hệ tài xế (đã ẩn bảo mật): $maskedPhone',
                            ),
                          ),
                        );
                      },
                      icon: const GhstButtonIcon(
                        Icons.phone,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                      ),
                      onPressed: () =>
                          _rebuildCustomerUi(() => _selectedScreenIndex = 5),
                      icon: const GhstButtonIcon(
                        Icons.chat_bubble_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFECFDF5),
                    side: const BorderSide(color: AppColors.ink, width: 1.2),
                  ),
                  onPressed: () {
                    final shareLink =
                        'https://ghst.vn/#/track?code=${Uri.encodeComponent(activeOrder.trackingCode)}';
                    Clipboard.setData(ClipboardData(text: shareLink));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã sao chép Link theo dõi công khai: $shareLink',
                        ),
                      ),
                    );
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PublicOrderTrackingScreen(
                          initialQuery: activeOrder.trackingCode,
                        ),
                      ),
                    );
                  },
                  icon: const GhstButtonIcon(
                    Icons.share_location_rounded,
                    size: 17,
                    color: AppColors.success,
                  ),
                  label: const Text('Chia sẻ hành trình (/track)'),
                ),
                if (activeOrder.assignedDriverName != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () =>
                        _rebuildCustomerUi(() => _selectedScreenIndex = 5),
                    icon: const GhstButtonIcon(Icons.chat_bubble_outline, size: 17),
                    label: const Text('Nhắn tin tài xế'),
                  ),
                if (isDelivered && activeOrder.paymentStatus != 'RETURNED')
                  OutlinedButton.icon(
                    onPressed: () =>
                        _rebuildCustomerUi(() => _selectedScreenIndex = 8),
                    icon: const GhstButtonIcon(Icons.star_outline_rounded, size: 17),
                    label: const Text('Đánh giá 5 sao'),
                  ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _rebuildCustomerUi(() => _selectedScreenIndex = 9),
                  icon: const GhstButtonIcon(Icons.report_problem_outlined, size: 17),
                  label: const Text('Khiếu nại'),
                ),
                if (activeOrder.status.canTransitionTo(OrderStatus.cancelled))
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                    ),
                    onPressed: () =>
                        _rebuildCustomerUi(() => _selectedScreenIndex = 6),
                    icon: const GhstButtonIcon(Icons.cancel_outlined, size: 17),
                    label: const Text('Hủy đơn'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUc06StepNode(
    String label, {
    required bool done,
    required bool active,
  }) {
    final color = done
        ? const Color(0xFF14B866)
        : active
        ? const Color(0xFFF43F5E)
        : const Color(0xFF0F172A);
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: GhstButtonIcon(
              done
                  ? Icons.check
                  : active
                  ? Icons.local_shipping_rounded
                  : Icons.circle,
              size: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: (done || active) ? FontWeight.w800 : FontWeight.w500,
              color: active
                  ? const Color(0xFFF43F5E)
                  : done
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF4A4754),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUc06StepLine({required bool done}) {
    return Container(
      width: 24,
      height: 2.5,
      margin: const EdgeInsets.only(bottom: 16),
      color: done ? const Color(0xFF14B866) : const Color(0xFF0F172A),
    );
  }
}
