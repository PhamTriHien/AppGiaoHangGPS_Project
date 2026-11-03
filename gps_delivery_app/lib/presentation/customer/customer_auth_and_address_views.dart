part of 'customer_subsystem_views.dart';

extension _CustomerAuthAndAddressViews on _CustomerSubsystemEntryState {
  /// Quản lý sổ địa chỉ nhận hàng
  Widget _buildSavedAddressesView() {
    final mySavedAddresses = _store.customerSavedAddresses;
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF1E56C5),
            child: const Row(
              children: [
                Icon(
                  Icons.bookmarks_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Quản lý sổ địa chỉ thường dùng',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Bản đồ Google Maps ghim vị trí địa chỉ đã lưu
                Builder(
                  builder: (context) {
                    final safeAddrIdx = mySavedAddresses.isEmpty
                        ? 0
                        : _selectedSavedAddressIndex.clamp(
                            0,
                            mySavedAddresses.length - 1,
                          );
                    final focusedSaved = mySavedAddresses.isNotEmpty
                        ? mySavedAddresses[safeAddrIdx]
                        : null;
                    final pinPos = _pinnedSavedAddressLocation ??
                        (_store.liveDeviceLocation ??
                            (focusedSaved != null
                                ? focusedSaved.location
                                : (_store.activeAuthenticatedUser
                                        ?.defaultLocation ??
                                    const GeoPoint(
                                      latitude: 10.7769,
                                      longitude: 106.6953,
                                    ))));
                    final pinAddress = _newAddressCtrl.text.trim().isNotEmpty &&
                            _pinnedSavedAddressLocation != null
                        ? _newAddressCtrl.text.trim()
                        : (_store.liveDeviceLocation != null &&
                                _store.liveDeviceAddress.trim().isNotEmpty
                            ? 'GPS Thiết bị: ${_store.liveDeviceAddress.trim()}'
                            : (focusedSaved != null
                                ? focusedSaved.fullAddress
                                : (_store.customerDefaultAddress.isNotEmpty
                                    ? _store.customerDefaultAddress
                                    : 'Chạm trực tiếp lên bản đồ để ghim địa chỉ mới')));
                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF122033)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Map3dPerspectiveWidget(
                        height: 440,
                        mode: MapViewMode.customerPreview,
                        is3dMode: _store.isMap3dEnabled,
                        speedKmh: 0,
                        onToggle3d: _store.toggleMap3d,
                        singlePinPoint: _pinnedSavedAddressLocation != null ||
                                focusedSaved != null || _store.liveDeviceLocation != null
                            ? pinPos : null,
                        singlePinLabel: _pinnedSavedAddressLocation != null
                            ? 'Vị trí vừa ghim'
                            : (focusedSaved != null
                                ? focusedSaved.label
                                : 'Vị trí lưu'),
                        nextTurnInstruction: _pinnedSavedAddressLocation != null
                            ? 'Đã ghim tọa độ (${pinPos.latitude.toStringAsFixed(5)}, ${pinPos.longitude.toStringAsFixed(5)})'
                            : (focusedSaved != null &&
                                    focusedSaved.fullAddress ==
                                        _store.customerDefaultAddress
                                ? 'Địa chỉ mặc định của bạn • Chạm bản đồ để đổi điểm ghim'
                                : 'Chạm vào bản đồ để ghim tọa độ chính xác'),
                        roadName: pinAddress,
                        onTapGeoPoint: (pt) async {
                          _rebuildCustomerUi(() {
                            _pinnedSavedAddressLocation = pt;
                          });
                          final resolvedAddr = await SmartDispatchEngine
                              .reverseGeocodeCoordinate(pt);
                          if (!mounted) return;
                          _rebuildCustomerUi(() {
                            _newAddressCtrl.text = resolvedAddr;
                          });
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC85A17),
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.zero),
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
                      final resolvedText = await SmartDispatchEngine
                          .reverseGeocodeCoordinate(pos);
                      if (!mounted) return;
                      _rebuildCustomerUi(() {
                        _pinnedSavedAddressLocation = pos;
                        _pinnedPickupLocation = pos;
                        _pickupCtrl.text = resolvedText;
                        _newAddressCtrl.text = resolvedText;
                        _osrmPreviewPoints = null;
                        _osrmDistMeters = null;
                        _osrmDurationSec = null;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã định vị GPS thiết bị: $resolvedText',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.my_location_rounded, size: 18),
                    label: const Text(
                      'Dùng vị trí hiện tại (GPS)',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Sổ địa chỉ đã lưu',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: Color(0xFF122033),
                  ),
                ),
                const SizedBox(height: 8),
                if (mySavedAddresses.isEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF3F8),
                      border: Border.all(color: const Color(0xFF122033)),
                    ),
                    child: const Text(
                      'Bạn chưa lưu địa chỉ nào. Hãy nhập địa chỉ thường dùng bên dưới và nhấn "Thêm địa chỉ".',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF4A4754),
                      ),
                    ),
                  )
                else
                  ...mySavedAddresses.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final addr = entry.value;
                    final isDefault =
                        addr.fullAddress == _store.customerDefaultAddress;
                    final isFocused = idx ==
                        _selectedSavedAddressIndex.clamp(
                          0,
                          mySavedAddresses.length - 1,
                        );
                    return InkWell(
                      onTap: () => _rebuildCustomerUi(() {
                        _selectedSavedAddressIndex = idx;
                        _pinnedSavedAddressLocation = null;
                      }),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isFocused
                              ? const Color(0xFFEEF3F8)
                              : Colors.white,
                          borderRadius: BorderRadius.all(Radius.zero),
                          border: Border.all(
                            color: isFocused
                                ? const Color(0xFF1E56C5)
                                : const Color(0xFF122033),
                            width: isFocused ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE9E9E4),
                                    borderRadius: BorderRadius.all(Radius.zero),
                                  ),
                                  child: Icon(
                                    addr.label.contains('Nhà')
                                        ? Icons.home_rounded
                                        : addr.label.contains('Cơ quan') ||
                                                addr.label.contains('Công ty')
                                            ? Icons.business_rounded
                                            : Icons.location_on_rounded,
                                    color: const Color(0xFF1E56C5),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            addr.label,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                          if (isDefault)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              color: const Color(0xFF1E56C5),
                                              child: const Text(
                                                'Mặc định',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        addr.fullAddress,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF4A4754),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Color(0xFFDC2626),
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _store.removeCustomerAddress(addr.id),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                  ),
                                  onPressed: () {
                                    _pickupCtrl.text = addr.fullAddress;
                                    _pinnedPickupLocation = addr.location;
                                    _rebuildCustomerUi(() {
                                      _osrmPreviewPoints = null;
                                      _osrmDistMeters = null;
                                      _osrmDurationSec = null;
                                      _selectedScreenIndex = 2;
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.trip_origin_rounded,
                                    size: 14,
                                  ),
                                  label: const Text(
                                    'Chọn lấy',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                  ),
                                  onPressed: () {
                                    _dropoffCtrl.text = addr.fullAddress;
                                    _pinnedDropoffLocation = addr.location;
                                    _rebuildCustomerUi(() {
                                      _osrmPreviewPoints = null;
                                      _osrmDistMeters = null;
                                      _osrmDurationSec = null;
                                      _selectedScreenIndex = 2;
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.location_on_outlined,
                                    size: 14,
                                  ),
                                  label: const Text(
                                    'Chọn giao',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                if (!isDefault)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                    ),
                                    onPressed: () {
                                      _store.setDefaultCustomerAddress(
                                        addr.fullAddress,
                                      );
                                      _rebuildCustomerUi(() {
                                        _selectedSavedAddressIndex = idx;
                                        _profileAddressCtrl.text =
                                            addr.fullAddress;
                                      });
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Đã đặt "${addr.label}" làm địa chỉ mặc định!',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.star_outline_rounded,
                                      size: 14,
                                      color: Color(0xFF1E56C5),
                                    ),
                                    label: const Text(
                                      'Đặt mặc định',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: ['Nhà riêng', 'Công ty', 'Khác'].map((tag) {
                    return ChoiceChip(
                      label: Text(tag),
                      selected: _selectedAddressTag == tag,
                      onSelected: (_) =>
                          _rebuildCustomerUi(() => _selectedAddressTag = tag),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (layoutCtx, constraints) {
                    final addressField = TextField(
                      controller: _newAddressCtrl,
                      onChanged: (_) => _rebuildCustomerUi(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Nhập địa chỉ mới để lưu vào sổ...',
                        prefixIcon: const Icon(Icons.place_outlined),
                        suffixIcon: IconButton(
                          tooltip: 'Tra cứu địa chỉ thực tế từ OpenStreetMap',
                          onPressed: () async {
                            final q = _newAddressCtrl.text.trim();
                            if (q.isEmpty) return;
                            final results = await SmartDispatchEngine
                                .fetchLiveNominatimSuggestions(q);
                            if (!mounted) return;
                            _rebuildCustomerUi(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Đã tìm thấy ${results.length} địa chỉ thực tế cho "$q"',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.travel_explore_rounded,
                            color: Color(0xFF1E56C5),
                            size: 18,
                          ),
                        ),
                      ),
                    );
                    final addBtn = ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC85A17),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.zero),
                        ),
                      ),
                      onPressed: () {
                        if (_newAddressCtrl.text.trim().isEmpty) return;
                        _store.addCustomerAddress(
                          _selectedAddressTag,
                          _newAddressCtrl.text.trim(),
                          customLocation: _pinnedSavedAddressLocation,
                        );
                        _pinnedSavedAddressLocation = null;
                        _newAddressCtrl.clear();
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text(
                        'Thêm địa chỉ',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    );
                    if (constraints.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          addressField,
                          const SizedBox(height: 8),
                          addBtn,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: addressField),
                        const SizedBox(width: 10),
                        addBtn,
                      ],
                    );
                  },
                ),
                if (_newAddressCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: SmartDispatchEngine.searchAddressSuggestions(
                      _newAddressCtrl.text,
                    ).take(3).map((place) {
                      return ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(
                          Icons.location_searching_rounded,
                          size: 13,
                          color: Color(0xFF1E56C5),
                        ),
                        label: Text(
                          place.title,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () => _rebuildCustomerUi(() {
                          _newAddressCtrl.text = place.fullAddress;
                          _pinnedSavedAddressLocation = place.location;
                        }),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _applyVoucherAndProceed(BuildContext context, String code) {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) return;
    final matched =
        _store.vouchers.where((v) => v.code == cleanCode).firstOrNull;
    if (matched == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'Mã khuyến mãi "$cleanCode" không tồn tại trong hệ thống.',
          ),
        ),
      );
      return;
    }
    if (!matched.isUsable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            matched.isExpired
                ? 'Mã "$cleanCode" đã hết hạn sử dụng (${matched.expiryDate}).'
                : 'Mã "$cleanCode" hiện đang tạm ngưng áp dụng.',
          ),
        ),
      );
      return;
    }
    final hasCompleteOrderForm = _pickupCtrl.text.trim().isNotEmpty &&
        _dropoffCtrl.text.trim().isNotEmpty &&
        _recipientNameCtrl.text.trim().isNotEmpty &&
        _recipientPhoneCtrl.text.trim().isNotEmpty;
    _rebuildCustomerUi(() {
      _voucherCtrl.text = cleanCode;
      _selectedScreenIndex = hasCompleteOrderForm ? 3 : 2;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          hasCompleteOrderForm
              ? 'Đã chọn mã khuyến mãi $cleanCode (Đơn tối thiểu ${CurrencyFormatter.formatVnd(matched.minOrderValue)})!'
              : 'Đã chọn mã $cleanCode. Vui lòng nhập địa chỉ lấy/giao và người nhận để tính cước!',
        ),
      ),
    );
  }

  Widget _buildVoucherChoices({required ValueChanged<String> onSelected}) {
    final available = _store.vouchers.where((v) => v.isUsable).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _voucherCtrl,
          decoration: InputDecoration(
            labelText: 'Mã ưu đãi',
            prefixIcon: const Icon(Icons.local_offer_outlined),
            suffixIcon: IconButton(
              tooltip: 'Áp dụng',
              icon: const Icon(Icons.check),
              onPressed: () => onSelected(_voucherCtrl.text),
            ),
          ),
          onSubmitted: onSelected,
        ),
        const SizedBox(height: 12),
        if (available.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('Chưa có ưu đãi khả dụng.'),
          ),
        ...available.map((voucher) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.confirmation_number_outlined),
          title: Text(voucher.code),
          subtitle: Text('${voucher.title}\nĐơn tối thiểu: ${CurrencyFormatter.formatVnd(voucher.minOrderValue)} • HSD: ${voucher.expiryDate}'),
          trailing: IconButton(
            tooltip: 'Chọn ưu đãi',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => onSelected(voucher.code),
          ),
          onTap: () => onSelected(voucher.code),
        )),
      ],
    );
  }

  Future<void> _showVoucherPicker() async {
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Chọn ưu đãi'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: _buildVoucherChoices(
              onSelected: (code) => Navigator.of(dialogContext).pop(code),
            ),
          ),
        ),
        actions: [TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Đóng'),
        )],
      ),
    );
    if (mounted && code != null) _applyVoucherAndProceed(context, code);
  }

  Widget _buildDedicatedVoucherUc11View() {
    return _buildPromoEventsAndVoucherHubView(context);
  }
}
