part of 'merchant_subsystem_views.dart';

extension _MerchantTrackingAndFinanceViews on _MerchantSubsystemEntryState {
  /// UC35: Theo dõi trạng thái nhiều đơn hàng cùng lúc (Chuẩn uc35_theo_doi_don_shop)
  Widget _buildMultiOrderTrackingView() {
    final shopOrders = _store.merchantPersonalOrders;
    if (shopOrders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.zero),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chưa có đơn hàng nào để theo dõi trạng thái',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              'Cửa hàng "${_store.merchantStoreName}" hiện chưa phát sinh vận đơn nào. Hãy khởi tạo đơn hàng mới để bắt đầu giám sát trực tiếp trên bản đồ.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5E83),
                foregroundColor: Colors.white,
              ),
              onPressed: () =>
                  _rebuildMerchantUi(() => _selectedScreenIndex = 2),
              icon: const Icon(Icons.add_box_outlined, size: 18),
              label: const Text('Tạo đơn gửi hàng'),
            ),
          ],
        ),
      );
    }
    final tabs = [
      'Tất cả',
      'Chờ lấy',
      'Đang giao',
      'Đã giao',
      'Giao thất bại',
      'Hoàn hàng',
    ];
    final filtered = shopOrders.where((o) {
      if (_shopOrderStatusTab == 'Tất cả') return true;
      if (_shopOrderStatusTab == 'Chờ lấy') {
        return o.status == OrderStatus.searching ||
            o.status == OrderStatus.accepted ||
            o.status == OrderStatus.arrivingPickup;
      }
      if (_shopOrderStatusTab == 'Đang giao') {
        return o.status == OrderStatus.inTransit;
      }
      if (_shopOrderStatusTab == 'Đã giao') {
        return o.status == OrderStatus.delivered &&
            o.paymentStatus != 'RETURNED';
      }
      if (_shopOrderStatusTab == 'Giao thất bại') {
        return o.status == OrderStatus.failed;
      }
      if (_shopOrderStatusTab == 'Hoàn hàng') {
        return o.status == OrderStatus.cancelled ||
            o.status == OrderStatus.returning ||
            o.paymentStatus == 'RETURNED';
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shopOrders.isNotEmpty)
          LiveOrderConnection(
            key: ValueKey(
              'merchant-live-${shopOrders[_selectedWaybillOrderIndex.clamp(0, shopOrders.length - 1)].trackingCode}',
            ),
            room:
                shopOrders[_selectedWaybillOrderIndex.clamp(
                      0,
                      shopOrders.length - 1,
                    )]
                    .trackingCode,
          ),
        Builder(
          builder: (context) {
            final multiPlan = _store.computeMultiStopPlanForWarehouse();
            if (multiPlan == null || multiPlan.orderedStops.length < 2) {
              return const SizedBox.shrink();
            }
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                border: Border.all(color: const Color(0xFF14B866)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ghép đơn Đa điểm thông minh 2-Opt TSP (${multiPlan.orderedStops.length} điểm giao)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Color(0xFF065F46),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Quãng đường tối ưu: ${(multiPlan.optimizedDistanceMeters / 1000).toStringAsFixed(1)} km (giảm ${multiPlan.savedPercent.toStringAsFixed(1)}% so với thứ tự hiện tại)',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF14B866),
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      final applied = _store.applyMultiStopRouteOptimization();
                      if (applied == null) return;
                      final seq = applied.orderedStops
                          .map((o) => o.trackingCode)
                          .join(' → ');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã kích hoạt lộ trình ghép tuyến 2-Opt: $seq',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.alt_route_rounded, size: 16),
                    label: Text(
                      _store.isMultiStopRouteActive
                          ? 'Đã bật lộ trình 2-Opt'
                          : 'Tối ưu ghép tuyến 2-Opt',
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tabs.map((t) {
            final selected = _shopOrderStatusTab == t;
            return ChoiceChip(
              label: Text(t),
              selected: selected,
              selectedColor: const Color(0xFFFF5E83),
              labelStyle: TextStyle(
                color: selected ? Colors.white : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              onSelected: (_) =>
                  _rebuildMerchantUi(() => _shopOrderStatusTab = t),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final colLeft = Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: AppColors.divider),
              ),
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Chưa có vận đơn nào thuộc trạng thái "$_shopOrderStatusTab".',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          const Color(0xFFF5F1E8),
                        ),
                        columns: const [
                          DataColumn(label: Text('Mã đơn')),
                          DataColumn(label: Text('Người nhận')),
                          DataColumn(label: Text('Tài xế')),
                          DataColumn(label: Text('COD')),
                          DataColumn(label: Text('Trạng thái')),
                          DataColumn(label: Text('Thao tác')),
                        ],
                        rows: filtered.map((o) {
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  o.trackingCode,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF5B33E6),
                                  ),
                                ),
                                onTap: () {
                                  final idx = shopOrders.indexOf(o);
                                  if (idx >= 0) {
                                    _rebuildMerchantUi(
                                      () => _selectedWaybillOrderIndex = idx,
                                    );
                                  }
                                },
                              ),
                              DataCell(Text(o.recipientName)),
                              DataCell(
                                Text(o.assignedDriverName ?? 'Đang tìm TX'),
                              ),
                              DataCell(
                                Text(CurrencyFormatter.formatVnd(o.codAmount)),
                              ),
                              DataCell(
                                Chip(
                                  label: Text(
                                    o.paymentStatus == 'RETURNED'
                                        ? 'Đã hoàn kho'
                                        : o.status.displayName,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        minimumSize: Size.zero,
                                      ),
                                      onPressed: () {
                                        final shareUrl =
                                            'https://ghst.vn/#/track?code=${Uri.encodeComponent(o.trackingCode)}';
                                        Clipboard.setData(
                                          ClipboardData(text: shareUrl),
                                        );
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                PublicOrderTrackingScreen(
                                                  initialQuery: o.trackingCode,
                                                ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.share_location_rounded,
                                        size: 14,
                                        color: AppColors.success,
                                      ),
                                      label: const Text(
                                        'Link Track',
                                        style: TextStyle(fontSize: 11.5),
                                      ),
                                    ),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        minimumSize: Size.zero,
                                      ),
                                      onPressed: () {
                                        final idx = shopOrders.indexOf(o);
                                        _rebuildMerchantUi(() {
                                          if (idx >= 0) {
                                            _selectedWaybillOrderIndex = idx;
                                          }
                                          _selectedScreenIndex = 4;
                                        });
                                      },
                                      icon: const Icon(
                                        Icons.print_outlined,
                                        size: 14,
                                      ),
                                      label: const Text(
                                        'In A6',
                                        style: TextStyle(fontSize: 11.5),
                                      ),
                                    ),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        minimumSize: Size.zero,
                                      ),
                                      onPressed: () {
                                        final idx = shopOrders.indexOf(o);
                                        _rebuildMerchantUi(() {
                                          if (idx >= 0) {
                                            _selectedWaybillOrderIndex = idx;
                                          }
                                          _editOrderNameCtrl.text =
                                              o.recipientName;
                                          _editOrderPhoneCtrl.text =
                                              o.recipientPhone;
                                          _editOrderAddrCtrl.text =
                                              o.dropoffAddress;
                                          _editOrderCodCtrl.text = o.codAmount
                                              .toStringAsFixed(0);
                                          _lastSyncedEditOrderCode =
                                              o.trackingCode;
                                          _selectedScreenIndex = 6;
                                        });
                                      },
                                      icon: const Icon(
                                        Icons.edit_note_outlined,
                                        size: 15,
                                      ),
                                      label: const Text(
                                        'Sửa/Hủy',
                                        style: TextStyle(fontSize: 11.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            );
            final safeFocusIdx = shopOrders.isEmpty
                ? 0
                : _selectedWaybillOrderIndex.clamp(0, shopOrders.length - 1);
            final ActiveOrderRecord? focusedOrd = filtered.isNotEmpty
                ? (filtered.contains(shopOrders[safeFocusIdx])
                      ? shopOrders[safeFocusIdx]
                      : filtered.first)
                : null;
            if (focusedOrd == null) {
              return colLeft;
            }
            final isFocusedActiveRoute =
                _store.activeOrderRecord?.trackingCode ==
                focusedOrd.trackingCode;
            final cachedPolyline =
                _merchantSyncedPolylines[focusedOrd.trackingCode];
            final focusedRoutePoints =
                cachedPolyline != null && cachedPolyline.length >= 2
                ? cachedPolyline
                : (isFocusedActiveRoute &&
                          _store.activeRoutePolyline.length >= 2
                      ? _store.activeRoutePolyline
                      : SmartDispatchEngine.generateRoutePolyline(
                          focusedOrd.pickupLocation,
                          focusedOrd.dropoffLocation,
                          segments: 10,
                        ));
            final assignedDrv = focusedOrd.assignedDriverName == null
                ? null
                : _store.drivers
                      .where((d) => d.fullName == focusedOrd.assignedDriverName)
                      .firstOrNull;
            final totalAirMeters = GeoMath.distanceMeters(
              focusedOrd.pickupLocation,
              focusedOrd.dropoffLocation,
            );
            final double realProgress =
                assignedDrv != null && totalAirMeters > 1
                ? (1.0 -
                          (GeoMath.distanceMeters(
                                assignedDrv.location,
                                focusedOrd.dropoffLocation,
                              ) /
                              totalAirMeters))
                      .clamp(0.08, 0.96)
                : 0.0;
            final double ordSpeedKmh;
            final double ordProgress;
            switch (focusedOrd.status) {
              case OrderStatus.draft:
              case OrderStatus.searching:
                ordSpeedKmh = 0;
                ordProgress = 0.0;
              case OrderStatus.accepted:
              case OrderStatus.arrivingPickup:
                ordSpeedKmh = isFocusedActiveRoute && _store.isDriverOnline
                    ? _store.currentSpeedKmh
                    : 0;
                ordProgress = realProgress > 0 ? realProgress : 0.18;
              case OrderStatus.inTransit:
                ordSpeedKmh = isFocusedActiveRoute && _store.isDriverOnline
                    ? _store.currentSpeedKmh
                    : 0;
                ordProgress = realProgress > 0
                    ? realProgress
                    : (isFocusedActiveRoute
                          ? (_store.routeProgressStep / 10.0).clamp(0.1, 0.95)
                          : 0.5);
              case OrderStatus.delivered:
                ordSpeedKmh = 0;
                ordProgress = 1.0;
              case OrderStatus.failed:
              case OrderStatus.returning:
              case OrderStatus.cancelled:
                ordSpeedKmh = 0;
                ordProgress = realProgress;
            }
            final colRight = Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.all(Radius.zero),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bản đồ Lộ trình & Vị trí đơn ${focusedOrd.trackingCode}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Map3dPerspectiveWidget(
                    height: 480,
                    mode: MapViewMode.customerLiveTracking,
                    is3dMode: _store.isMap3dEnabled,
                    speedKmh: ordSpeedKmh,
                    onToggle3d: _store.toggleMap3d,
                    driverLocation: _store.verifiedLocationForOrder(focusedOrd),
                    progressFraction: ordProgress,
                    routePoints: focusedRoutePoints,
                    pickupLabel: 'Lấy: ${focusedOrd.pickupAddress}',
                    dropoffLabel: 'Giao: ${focusedOrd.dropoffAddress}',
                    nextTurnInstruction:
                        'Đơn ${focusedOrd.trackingCode} (${focusedOrd.status.displayName}) • Tài xế: ${focusedOrd.assignedDriverName ?? "Đang tìm tài xế"}',
                    roadName:
                        '${focusedOrd.pickupAddress} → ${focusedOrd.dropoffAddress}',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final routeRes =
                              await SmartDispatchEngine.fetchLiveOsrmRoute(
                                focusedOrd.pickupLocation,
                                focusedOrd.dropoffLocation,
                              );
                          if (!context.mounted) return;
                          _rebuildMerchantUi(() {
                            _merchantSyncedPolylines[focusedOrd.trackingCode] =
                                routeRes.polylinePoints;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Đã đồng bộ lộ trình đường phố cho đơn ${focusedOrd.trackingCode} (${(routeRes.distanceMeters / 1000.0).toStringAsFixed(1)} km)!',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.alt_route_rounded, size: 15),
                        label: const Text(
                          'Đồng bộ lộ trình thực tế',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F1E8),
                      borderRadius: const BorderRadius.all(Radius.zero),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          focusedOrd.podImageNote != null
                              ? Icons.verified_outlined
                              : Icons.local_shipping_outlined,
                          color: focusedOrd.podImageNote != null
                              ? AppColors.success
                              : const Color(0xFF5B33E6),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            focusedOrd.podImageNote != null
                                ? 'Bằng chứng giao hàng (${focusedOrd.trackingCode}): ${focusedOrd.podImageNote}'
                                : 'Đơn ${focusedOrd.trackingCode} (${focusedOrd.status.displayName}) • Tài xế: ${focusedOrd.assignedDriverName ?? "Đang tìm tài xế"}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
            if (constraints.maxWidth < 1040) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [colRight, const SizedBox(height: 14), colLeft],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: colLeft),
                const SizedBox(width: 14),
                Expanded(flex: 6, child: colRight),
              ],
            );
          },
        ),
      ],
    );
  }

  /// UC36: Sửa / Hủy đơn hàng & Yêu cầu Giao lại / Hoàn hàng (Chuẩn uc36_sua_huy_don_v2)
  Widget _buildBulkPickupSchedulerCard() {
    final personalWhs = _store.merchantPersonalWarehouses;
    final pickupList = _store.merchantPersonalPickupRequests;
    final selectedWh = personalWhs.isEmpty
        ? null
        : personalWhs[_selectedWarehouseIndex.clamp(0, personalWhs.length - 1)];
    const vehicleOptions = [
      'Xe ba gác 300kg',
      'Xe tải van 500kg',
      'Xe tải thùng kín 1.5 tấn',
    ];
    const slotOptions = [
      '09:00 - 11:00 (Ca sáng)',
      '14:00 - 16:00 (Ca chiều)',
      '18:00 - 20:00 (Ca tối)',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Đặt lịch gọi xe thu gom số lượng lớn tại Kho (UC36)',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'Hẹn xe tải van / xe thùng kín đến kho gom nhiều kiện B2B cùng lúc theo khung giờ cố định.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<String>(
                  initialValue: vehicleOptions.contains(_pickupVehicleType)
                      ? _pickupVehicleType
                      : vehicleOptions[1],
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Loại xe thu gom',
                  ),
                  items: vehicleOptions
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(v, style: const TextStyle(fontSize: 12.5)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      _rebuildMerchantUi(() => _pickupVehicleType = v);
                    }
                  },
                ),
              ),
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<String>(
                  initialValue: slotOptions.contains(_pickupTimeSlot)
                      ? _pickupTimeSlot
                      : slotOptions[1],
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Khung giờ hẹn lấy',
                  ),
                  items: slotOptions
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s, style: const TextStyle(fontSize: 12.5)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      _rebuildMerchantUi(() => _pickupTimeSlot = v);
                    }
                  },
                ),
              ),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _pickupQtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Số lượng kiện',
                  ),
                ),
              ),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _pickupWeightCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Tổng KL (kg)',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _pickupNoteCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText:
                        'Ghi chú kho (${selectedWh?.name ?? "Kho mặc định"})',
                    hintText: 'VD: Có xe nâng hỗ trợ tại cửa kho số 2',
                  ),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B33E6),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final activeMer = _store.activeMerchantRecord;
                  if (activeMer == null ||
                      activeMer.approvalStatus != 'Đã duyệt') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: AppColors.danger,
                        content: Text(
                          'Vui lòng hoàn tất đăng ký & chờ Admin duyệt hồ sơ cửa hàng B2B trước khi đặt lịch xe thu gom!',
                        ),
                      ),
                    );
                    return;
                  }
                  final qty = int.tryParse(_pickupQtyCtrl.text.trim());
                  final weight = double.tryParse(_pickupWeightCtrl.text.trim());
                  final created = qty == null || weight == null
                      ? null
                      : _store.createScheduledPickupRequest(
                          warehouseId: selectedWh?.id ?? '',
                          vehicleType: _pickupVehicleType,
                          timeSlot: _pickupTimeSlot,
                          packageCount: qty,
                          totalWeightKg: weight,
                          note: _pickupNoteCtrl.text,
                        );
                  if (created == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: AppColors.danger,
                        content: Text(
                          'Chọn kho đã đăng ký và nhập số kiện, khối lượng lớn hơn 0.',
                        ),
                      ),
                    );
                    return;
                  }
                  _pickupNoteCtrl.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã tạo phiếu hẹn xe thu gom ${created.id} (${created.vehicleType} • ${created.timeSlot})!',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.local_shipping_outlined, size: 17),
                label: const Text('Đặt lịch xe thu gom'),
              ),
            ],
          ),
          if (pickupList.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...pickupList.take(4).map(
              (req) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      '${req.id} • ${req.vehicleType} • ${req.timeSlot} (${req.packageCount} kiện ~ ${req.totalWeightKg.toStringAsFixed(1)} kg)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      req.status,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: req.assignedDriverName != null
                            ? const Color(0xFF14B866)
                            : const Color(0xFF5B33E6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScheduledPickupRequestView() {
    final shopOrders = _store.merchantPersonalOrders;
    if (shopOrders.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBulkPickupSchedulerCard(),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.all(Radius.zero),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chưa có đơn hàng nào để chỉnh sửa hoặc hủy',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cửa hàng "${_store.merchantStoreName}" hiện chưa có vận đơn nào. Vui lòng tạo đơn hàng trước khi thực hiện sửa thông tin người nhận, hủy đơn hoặc yêu cầu hoàn hàng.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5E83),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () =>
                      _rebuildMerchantUi(() => _selectedScreenIndex = 2),
                  icon: const Icon(Icons.add_box_outlined, size: 18),
                  label: const Text('Mở Tạo đơn gửi hàng'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final safeIdx = _selectedWaybillOrderIndex.clamp(0, shopOrders.length - 1);
    final ord = shopOrders[safeIdx];
    if (_lastSyncedEditOrderCode != ord.trackingCode) {
      _editOrderNameCtrl.text = ord.recipientName;
      _editOrderPhoneCtrl.text = ord.recipientPhone;
      _editOrderAddrCtrl.text = ord.dropoffAddress;
      _editOrderCodCtrl.text = ord.codAmount.toStringAsFixed(0);
      _lastSyncedEditOrderCode = ord.trackingCode;
    }
    final cancelReasons = [
      'Khách hàng báo hủy đơn',
      'Shop hết hàng / Đổi mẫu sản phẩm',
      'Nhập sai địa chỉ hoặc tiền thu hộ COD',
      'Khách không nghe máy sau 3 lần gọi',
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final colLeft = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.zero),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: shopOrders.asMap().entries.map((e) {
                  final idx = e.key;
                  final item = e.value;
                  final selected = idx == safeIdx;
                  final statusLabel = item.paymentStatus == 'RETURNED'
                      ? 'Đã hoàn kho'
                      : item.status.displayName;
                  return ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${item.trackingCode} ($statusLabel)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    selected: selected,
                    selectedColor: const Color(0xFF5B33E6),
                    onSelected: (_) => _rebuildMerchantUi(() {
                      _selectedWaybillOrderIndex = idx;
                      _editOrderNameCtrl.text = item.recipientName;
                      _editOrderPhoneCtrl.text = item.recipientPhone;
                      _editOrderAddrCtrl.text = item.dropoffAddress;
                      _editOrderCodCtrl.text = item.codAmount.toStringAsFixed(
                        0,
                      );
                      _lastSyncedEditOrderCode = item.trackingCode;
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF5B33E6),
                  borderRadius: BorderRadius.all(Radius.zero),
                ),
                child: Text(
                  'Chỉnh sửa đơn hàng ${ord.trackingCode} (${ord.status.displayName})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _editOrderNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên người nhận',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editOrderPhoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại người nhận',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editOrderAddrCtrl,
                decoration: const InputDecoration(
                  labelText: 'Địa chỉ giao hàng mới',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editOrderCodCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tiền thu hộ COD (VNĐ)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF14B866),
                  ),
                  onPressed:
                      ord.status == OrderStatus.delivered ||
                          ord.status == OrderStatus.cancelled ||
                          ord.status == OrderStatus.returning ||
                          ord.paymentStatus == 'RETURNED'
                      ? null
                      : () {
                          if (_editOrderNameCtrl.text.trim().isEmpty ||
                              _editOrderPhoneCtrl.text.trim().isEmpty ||
                              _editOrderAddrCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Vui lòng nhập đầy đủ Tên, SĐT và Địa chỉ người nhận mới!',
                                ),
                              ),
                            );
                            return;
                          }
                          final cleanEditPhone = _editOrderPhoneCtrl.text
                              .trim()
                              .replaceAll(' ', '');
                          if (!RegExp(r'^(?:\+84|0)[0-9]{9}$')
                              .hasMatch(cleanEditPhone)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: AppColors.danger,
                                content: Text(
                                  'Số điện thoại người nhận không hợp lệ (10 chữ số bắt đầu bằng 0 hoặc +84)!',
                                ),
                              ),
                            );
                            return;
                          }
                          if (_editOrderAddrCtrl.text.trim().toLowerCase() ==
                              ord.pickupAddress.trim().toLowerCase()) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: AppColors.danger,
                                content: Text(
                                  'Địa chỉ giao mới không được trùng với địa chỉ lấy hàng!',
                                ),
                              ),
                            );
                            return;
                          }
                          final newCod =
                              double.tryParse(
                                _editOrderCodCtrl.text.replaceAll(
                                  RegExp(r'[^0-9.]'),
                                  '',
                                ),
                              ) ??
                              ord.codAmount;
                          final ok = _store.updateExistingOrderDetails(
                            trackingCode: ord.trackingCode,
                            recipientName: _editOrderNameCtrl.text,
                            recipientPhone: _editOrderPhoneCtrl.text,
                            dropoffAddress: _editOrderAddrCtrl.text,
                            codAmount: newCod,
                          );
                          if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.danger,
                                content: Text(
                                  'Không thể cập nhật đơn ${ord.trackingCode}: đơn đã khóa trạng thái (${ord.status.displayName}) hoặc địa chỉ mới thuộc khu vực hạn chế giao nhận.',
                                ),
                              ),
                            );
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Đã lưu thay đổi thông tin đơn ${ord.trackingCode} thành công!',
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Lưu thay đổi thông tin đơn'),
                ),
              ),
            ],
          ),
        );
        final colRight = Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.all(Radius.zero),
                    ),
                    child: Text(
                      'Hủy đơn hàng ${ord.trackingCode}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.transparent,
                    child: RadioGroup<String>(
                      groupValue: _shopCancelReason,
                      onChanged: (v) {
                        if (v != null) {
                          _rebuildMerchantUi(() => _shopCancelReason = v);
                        }
                      },
                      child: Column(
                        children: cancelReasons
                            .map(
                              (r) => RadioListTile<String>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: r,
                                title: Text(
                                  r,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                      ),
                      onPressed:
                          ord.status.canTransitionTo(OrderStatus.cancelled)
                          ? () {
                              final ok = _store.cancelOrder(
                                ord.trackingCode,
                                _shopCancelReason,
                              );
                              if (!ok) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppColors.danger,
                                    content: Text(
                                      'Không thể hủy đơn ${ord.trackingCode}: Tài xế đã lấy hàng hoặc đang giao (${ord.status.displayName}).',
                                    ),
                                  ),
                                );
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Đã hủy đơn ${ord.trackingCode}: $_shopCancelReason',
                                  ),
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Xác nhận Hủy đơn hàng'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Hành động nhanh (Đơn giao thất bại)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ord.status == OrderStatus.failed
                        ? 'Đơn ${ord.trackingCode} đang ở trạng thái Giao thất bại. Vui lòng chọn Giao lại hoặc Hoàn hàng về kho:'
                        : 'Chỉ kích hoạt khi vận đơn ${ord.trackingCode} chuyển sang trạng thái Giao thất bại (hiện tại: ${ord.status.displayName}).',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ord.status == OrderStatus.failed
                          ? AppColors.danger
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5E83),
                        ),
                        onPressed: ord.status != OrderStatus.failed
                            ? null
                            : () {
                                final ok = _store.requeueOrReturnOrder(
                                  ord.trackingCode,
                                  isReturn: false,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok
                                          ? 'Đã kích hoạt lệnh Giao lại cho đơn ${ord.trackingCode}!'
                                          : 'Không thể giao lại đơn ${ord.trackingCode} đã hoàn tất!',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.replay, size: 16),
                        label: const Text('Yêu cầu Giao lại'),
                      ),
                      OutlinedButton.icon(
                        onPressed: ord.status != OrderStatus.failed
                            ? null
                            : () {
                                final ok = _store.requeueOrReturnOrder(
                                  ord.trackingCode,
                                  isReturn: true,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok
                                          ? 'Đã cập nhật trạng thái Hoàn hàng về kho cho ${ord.trackingCode}!'
                                          : 'Không thể hoàn hàng đơn ${ord.trackingCode}!',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(
                          Icons.assignment_return_outlined,
                          size: 16,
                        ),
                        label: const Text('Hoàn hàng về điểm lấy'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBulkPickupSchedulerCard(),
              colLeft,
              const SizedBox(height: 16),
              colRight,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBulkPickupSchedulerCard(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: colLeft),
                const SizedBox(width: 16),
                Expanded(child: colRight),
              ],
            ),
          ],
        );
      },
    );
  }

  /// UC37: Đối soát công nợ tiền thu hộ COD (Chuẩn uc37_doi_soat_v2)
  Widget _buildCodReconciliationView() {
    double shipDeductedFromMerchantCod(ActiveOrderRecord o) {
      final isRecipientOrPrepaid =
          o.paymentMethod == 'Người nhận trả phí' ||
          o.paymentMethod.contains('MoMo') ||
          o.paymentMethod.contains('VNPay') ||
          o.paymentMethod.contains('ZaloPay') ||
          o.paymentMethod.contains('thanh toán trước');
      return isRecipientOrPrepaid ? 0.0 : o.totalAmount;
    }

    double codHandlingFeeOf(ActiveOrderRecord o) {
      return o.codAmount > 2000000
          ? (o.codAmount * 0.005).roundToDouble()
          : 0.0;
    }

    double returnFeeOf(ActiveOrderRecord o) {
      return ((o.deliveryFee + o.surchargeFee) * 0.50).roundToDouble();
    }

    final activeMer = _store.activeMerchantRecord;
    final activeMerId = activeMer?.id ?? '';
    final persistedRec = activeMerId.isEmpty
        ? null
        : _store.codReconciliations
              .where((r) => r.merchantId == activeMerId)
              .firstOrNull;
    final shopOrders = _store.merchantPersonalOrders;
    final deliveredCodOrders = shopOrders.where(
      (o) => o.status == OrderStatus.delivered && o.paymentStatus != 'RETURNED',
    );
    final returnedShopOrders = shopOrders.where(
      (o) => o.status == OrderStatus.delivered && o.paymentStatus == 'RETURNED',
    );
    final totalCod = deliveredCodOrders.fold<double>(
      0,
      (sum, o) => sum + o.codAmount,
    );
    final totalShipFee = deliveredCodOrders.fold<double>(
      0,
      (sum, o) => sum + shipDeductedFromMerchantCod(o),
    );
    final totalCodHandlingFee = deliveredCodOrders.fold<double>(
      0,
      (sum, o) => sum + codHandlingFeeOf(o),
    );
    final totalReturnFee = returnedShopOrders.fold<double>(
      0,
      (sum, o) => sum + returnFeeOf(o),
    );
    final totalDeductions = totalShipFee + totalCodHandlingFee + totalReturnFee;
    final compCredit = _store.computeMerchantCompensationCredits(activeMer);
    final netCod = totalCod - totalDeductions + compCredit;
    final availableCod = activeMer?.codBalance ?? 0.0;
    final withdrawnOrPendingCod = _store.merchantPersonalWithdrawals
        .where((w) => w.status != 'Từ chối')
        .fold<double>(0.0, (sum, w) => sum + w.amount);
    final accountedTotalCod = availableCod + withdrawnOrPendingCod;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.zero),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              const Text(
                'Đối soát Công nợ & Tiền thu hộ COD',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF14B866),
                ),
                onPressed: () {
                  final csvLines = <String>[
                    'ma_don,nguoi_nhan,tien_cod_vnd,phi_giao_hoac_hoan_vnd,phi_cod_vnd,thuc_nhan_vnd,trang_thai',
                    ...shopOrders.map((o) {
                      final isReturnedSettled =
                          o.status == OrderStatus.delivered &&
                          o.paymentStatus == 'RETURNED';
                      final isVoided =
                          o.status == OrderStatus.cancelled ||
                          o.status == OrderStatus.failed ||
                          o.status == OrderStatus.returning ||
                          isReturnedSettled;
                      final isSettled =
                          o.status == OrderStatus.delivered && !isVoided;
                      final codFee = isVoided ? 0.0 : codHandlingFeeOf(o);
                      final shipDeduct = isReturnedSettled
                          ? returnFeeOf(o)
                          : (isVoided ? 0.0 : shipDeductedFromMerchantCod(o));
                      final netVal = isReturnedSettled
                          ? -shipDeduct
                          : (!isSettled
                                ? 0.0
                                : (o.codAmount - shipDeduct - codFee));
                      final stLabel = isReturnedSettled
                          ? 'Đã hoàn kho'
                          : o.status.displayName;
                      return '${o.trackingCode},${o.recipientName},${(isVoided ? 0.0 : o.codAmount).toStringAsFixed(0)},${shipDeduct.toStringAsFixed(0)},${codFee.toStringAsFixed(0)},${netVal.toStringAsFixed(0)},$stLabel';
                    }),
                  ];
                  final path = _store.exportReportFileToDisk(
                    fileName: 'Doi_Soat_COD.csv',
                    content: csvLines.join('\n'),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Đã xuất bảng đối soát công nợ tại: $path'),
                    ),
                  );
                },
                icon: const Icon(Icons.table_view, size: 16),
                label: const Text('Xuất Excel'),
              ),
            ],
          ),
          if (persistedRec != null) ...[
            const SizedBox(height: 8),
            Text(
              'Kỳ đối soát #${persistedRec.id} (${persistedRec.periodLabel}) • Trạng thái: ${persistedRec.status}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5B33E6),
              ),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, codConstraints) {
              final maxW = codConstraints.maxWidth;
              final cols = maxW >= 880
                  ? 4
                  : maxW >= 460
                  ? 2
                  : 1;
              final cardW = cols == 1
                  ? maxW
                  : (maxW - (cols - 1) * 12.0) / cols;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _codCard(
                    'Tổng COD đã thu',
                    CurrencyFormatter.formatVnd(totalCod),
                    const Color(0xFF5B33E6),
                    width: cardW,
                  ),
                  _codCard(
                    'Khấu trừ Cước / COD / Hoàn',
                    '-${CurrencyFormatter.formatVnd(totalDeductions)}',
                    AppColors.danger,
                    width: cardW,
                  ),
                  _codCard(
                    'Thực nhận ròng (COD - Phí)',
                    CurrencyFormatter.formatVnd(netCod),
                    netCod >= 0 ? AppColors.success : AppColors.danger,
                    width: cardW,
                  ),
                  _codCard(
                    'Số dư + Đã rút / Chờ chi',
                    '${CurrencyFormatter.formatVnd(accountedTotalCod)} (Dư: ${CurrencyFormatter.formatVnd(availableCod)})',
                    const Color(0xFF14B866),
                    width: cardW,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F1E8)),
              columns: const [
                DataColumn(label: Text('Mã đơn')),
                DataColumn(label: Text('Ngày giao')),
                DataColumn(label: Text('Tiền COD')),
                DataColumn(label: Text('Phí giao / Hoàn')),
                DataColumn(label: Text('Phí COD')),
                DataColumn(label: Text('Thực nhận')),
                DataColumn(label: Text('Trạng thái')),
              ],
              rows: shopOrders.map((o) {
                final isReturnedCompleted =
                    o.status == OrderStatus.delivered &&
                    o.paymentStatus == 'RETURNED';
                final isReturnedToWarehouse =
                    o.paymentStatus == 'RETURNED' ||
                    o.status == OrderStatus.returning;
                final isVoided =
                    o.status == OrderStatus.cancelled ||
                    o.status == OrderStatus.failed ||
                    isReturnedToWarehouse;
                final done =
                    o.status == OrderStatus.delivered && !isReturnedToWarehouse;
                final codHandlingFee = isVoided ? 0.0 : codHandlingFeeOf(o);
                final shipDeduct = isVoided
                    ? 0.0
                    : shipDeductedFromMerchantCod(o);
                final retFee = isReturnedCompleted ? returnFeeOf(o) : 0.0;
                final expectedNet = isVoided
                    ? 0.0
                    : (o.codAmount - shipDeduct - codHandlingFee);
                final net = done ? expectedNet : 0.0;
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        o.trackingCode,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(Text(o.createdDateLabel)),
                    DataCell(
                      Text(
                        isVoided
                            ? '0 đ'
                            : CurrencyFormatter.formatVnd(o.codAmount),
                      ),
                    ),
                    DataCell(
                      Text(
                        isReturnedCompleted
                            ? '-${CurrencyFormatter.formatVnd(retFee)} (Phí hoàn 50%)'
                            : (isVoided || shipDeduct == 0
                                  ? '0 đ (${o.paymentMethod})'
                                  : '-${CurrencyFormatter.formatVnd(shipDeduct)}'),
                      ),
                    ),
                    DataCell(
                      Text(
                        codHandlingFee > 0
                            ? '-${CurrencyFormatter.formatVnd(codHandlingFee)}'
                            : '0 đ (Miễn phí)',
                      ),
                    ),
                    DataCell(
                      Text(
                        isReturnedCompleted
                            ? '-${CurrencyFormatter.formatVnd(retFee)}'
                            : done
                            ? CurrencyFormatter.formatVnd(net)
                            : isVoided
                            ? '0 đ'
                            : '0 đ (Dự kiến: ${CurrencyFormatter.formatVnd(expectedNet)})',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: isVoided
                              ? AppColors.danger
                              : done
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    DataCell(
                      Chip(
                        backgroundColor: isVoided
                            ? AppColors.danger.withValues(alpha: 0.14)
                            : done
                            ? AppColors.success.withValues(alpha: 0.14)
                            : const Color(0xFFF5F1E8),
                        label: Text(
                          isReturnedToWarehouse
                              ? 'Đã hoàn kho'
                              : isVoided
                              ? 'Đã hủy / Thất bại'
                              : done
                              ? 'Đã chuyển'
                              : 'Chờ thu COD',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isVoided
                                ? AppColors.danger
                                : done
                                ? AppColors.success
                                : const Color(0xFFFF5E83),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codCard(String title, String value, Color color, {double? width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1E8),
        borderRadius: BorderRadius.all(Radius.zero),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// UC38: Nhận tiền COD về tài khoản ngân hàng (Chuẩn uc38_nhan_tien_cod)
  Widget _buildCodWithdrawalView() {
    final activeMer = _store.activeMerchantRecord;
    final availableCod = activeMer?.codBalance ?? 0.0;
    final bankName = activeMer?.bankName ?? 'Chưa cập nhật';
    final bankAccount = activeMer?.bankAccount ?? '';
    final storeOwnerName = activeMer?.storeName ?? 'Chưa đăng ký cửa hàng';
    return LayoutBuilder(
      builder: (context, constraints) {
        final colLeft = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.zero),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Số dư COD khả dụng',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                CurrencyFormatter.formatVnd(availableCod),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFF5E83),
                ),
              ),
              const Divider(height: 22),
              Text(
                'Ngân hàng liên kết: $bankName',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                'Số tài khoản: ${bankAccount.isNotEmpty ? bankAccount : "Chưa liên kết TK"}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codWithdrawCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số tiền muốn rút ngay (VNĐ)',
                  hintText: 'Nhập số tiền COD muốn rút (VNĐ)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5E83),
                  ),
                  onPressed: () {
                    if (activeMer == null ||
                        activeMer.approvalStatus != 'Đã duyệt') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppColors.danger,
                          content: Text(
                            'Hồ sơ cửa hàng đang ở trạng thái "${activeMer?.approvalStatus ?? "Chưa gửi hồ sơ"}". Vui lòng chờ Admin phê duyệt để rút tiền COD!',
                          ),
                        ),
                      );
                      return;
                    }
                    if (bankAccount.trim().isEmpty ||
                        bankAccount.contains('Chưa liên kết')) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: AppColors.danger,
                          content: Text(
                            'Vui lòng liên kết số tài khoản ngân hàng tại mục Hồ sơ Cửa hàng trước khi rút tiền COD!',
                          ),
                        ),
                      );
                      _rebuildMerchantUi(() => _selectedScreenIndex = 0);
                      return;
                    }
                    final cleanWithdrawText = _codWithdrawCtrl.text
                        .trim()
                        .replaceAll('.', '')
                        .replaceAll(',', '');
                    final amt = double.tryParse(cleanWithdrawText) ?? 0;
                    final ok = _store.requestWithdrawal(
                      ownerName: storeOwnerName,
                      ownerRole: 'Cửa hàng (COD)',
                      amount: amt,
                      bankName: bankName,
                      accountMasked: bankAccount,
                    );
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppColors.danger,
                          content: Text(
                            amt <= 0
                                ? 'Vui lòng nhập số tiền rút COD hợp lệ (> 0đ).'
                                : 'Rút tiền thất bại: Số tiền vượt quá số dư COD khả dụng (${CurrencyFormatter.formatVnd(availableCod)}).',
                          ),
                        ),
                      );
                      return;
                    }
                    _rebuildMerchantUi(() => _codWithdrawCtrl.clear());
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã tạo lệnh rút COD ${CurrencyFormatter.formatVnd(amt)}!',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Yêu cầu Rút tiền ngay'),
                ),
              ),
            ],
          ),
        );
        final colRight = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.zero),
            border: Border.all(color: AppColors.divider),
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Lịch sử nhận tiền COD',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 10),
                if (_store.merchantPersonalWithdrawals.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Chưa có lệnh rút tiền COD nào cho cửa hàng hiện tại.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ..._store.merchantPersonalWithdrawals.map(
                  (w) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: AppColors.success,
                    ),
                    title: Text(
                      '#${w.id} • ${CurrencyFormatter.formatVnd(w.amount)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('${w.bankName} (${w.accountMasked})'),
                    trailing: Chip(
                      label: Text(
                        w.status,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [colLeft, const SizedBox(height: 16), colRight],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: colLeft),
            const SizedBox(width: 16),
            Expanded(flex: 6, child: colRight),
          ],
        );
      },
    );
  }

  /// UC39: Báo cáo & Thống kê Cửa hàng (Chuẩn anh_sua_lai/uc39_bao_cao_shop.jpg)
  Widget _buildReturnAndMonthlyAnalyticsView() {
    final shopOrders = _store.merchantPersonalOrders;
    final totalOrders = shopOrders.length;
    final safeTotal = totalOrders == 0 ? 1 : totalOrders;
    final deliveredOrders = shopOrders
        .where(
          (o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus != 'RETURNED',
        )
        .toList();
    final deliveredCount = deliveredOrders.length;
    final failedOnlyCount = shopOrders
        .where((o) => o.status == OrderStatus.failed)
        .length;
    final returnedCount = shopOrders
        .where(
          (o) =>
              o.status == OrderStatus.cancelled ||
              o.status == OrderStatus.returning ||
              o.paymentStatus == 'RETURNED',
        )
        .length;
    final failedCount = failedOnlyCount + returnedCount;
    final inProgressCount = (totalOrders - deliveredCount - failedCount).clamp(
      0,
      totalOrders,
    );
    final successRate = deliveredCount * 100.0 / safeTotal;
    final inProgressRate = inProgressCount * 100.0 / safeTotal;
    final failedRate = failedOnlyCount * 100.0 / safeTotal;
    final returnedRate = returnedCount * 100.0 / safeTotal;
    final totalCod = deliveredOrders.fold<double>(
      0,
      (sum, o) => sum + o.codAmount,
    );
    final totalShip = deliveredOrders.fold<double>(
      0,
      (sum, o) => sum + o.totalAmount,
    );
    final shopCo2SavedGrams = shopOrders
        .where((o) => o.status != OrderStatus.cancelled)
        .fold<double>(0.0, (sum, o) => sum + o.co2SavedGrams);
    final shopBatch2hCount = shopOrders
        .where(
          (o) =>
              o.serviceType == DeliveryServiceType.sameDay2h &&
              o.status != OrderStatus.cancelled,
        )
        .length;
    final now = DateTime.now();
    final recent7dOrders = shopOrders
        .where((o) => o.daysAgoFrom(now) <= 6)
        .toList();
    final chronoBuckets = List<(String, int)>.generate(7, (idx) {
      final daysAgo = 6 - idx;
      final dt = now.subtract(Duration(days: daysAgo));
      final label =
          '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
      final cnt = recent7dOrders
          .where((o) => o.daysAgoFrom(now) == daysAgo)
          .length;
      return (label, cnt);
    });
    final maxDay = chronoBuckets.fold<int>(
      1,
      (m, item) => item.$2 > m ? item.$2 : m,
    );
    final dailyChartItems = chronoBuckets.map((item) {
      final ratio = item.$2 == 0 ? 0.03 : (item.$2 / maxDay).clamp(0.18, 1.0);
      return (item.$1, ratio, item.$2);
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.zero),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                'Báo cáo & Thống kê Cửa hàng (Tháng ${DateTime.now().month}/${DateTime.now().year})',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5E83),
                ),
                onPressed: () {
                  final reportContent =
                      'BAO CAO THONG KE CUA HANG (${_store.merchantStoreName})\n'
                      'Tong don gui: $totalOrders\n'
                      'Giao thanh cong: $deliveredCount (${successRate.toStringAsFixed(1)}%)\n'
                      'Giao that bai / Hoan hang: $failedCount\n'
                      'Tong COD: ${totalCod.toStringAsFixed(0)} VND\n'
                      'Tong phi ship: ${totalShip.toStringAsFixed(0)} VND\n';
                  final path = _store.exportReportFileToDisk(
                    fileName: 'Bao_Cao_Shop_T${DateTime.now().month}.csv',
                    content: reportContent,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã xuất báo cáo thống kê cửa hàng tại: $path',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Xuất báo cáo ↗'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, kpiConstraints) {
              final maxW = kpiConstraints.maxWidth;
              final cols = maxW >= 860
                  ? 3
                  : maxW >= 460
                  ? 2
                  : 1;
              final cardW = cols == 1
                  ? maxW
                  : (maxW - (cols - 1) * 10.0) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _codCard(
                    'Tổng đơn gửi',
                    '$totalOrders đơn',
                    const Color(0xFF5B33E6),
                    width: cardW,
                  ),
                  _codCard(
                    'Giao thành công',
                    '$deliveredCount (${successRate.toStringAsFixed(1)}%)',
                    AppColors.success,
                    width: cardW,
                  ),
                  _codCard(
                    'Giao thất bại',
                    '$failedOnlyCount đơn (${failedRate.toStringAsFixed(1)}%)',
                    AppColors.danger,
                    width: cardW,
                  ),
                  _codCard(
                    'Hoàn hàng',
                    '$returnedCount đơn (${returnedRate.toStringAsFixed(1)}%)',
                    const Color(0xFFFF5E83),
                    width: cardW,
                  ),
                  _codCard(
                    'Tổng phí ship',
                    CurrencyFormatter.formatVnd(totalShip),
                    const Color(0xFF5B33E6),
                    width: cardW,
                  ),
                  _codCard(
                    'Tổng COD đã nhận',
                    CurrencyFormatter.formatVnd(totalCod),
                    AppColors.success,
                    width: cardW,
                  ),
                  _codCard(
                    'ESG Giảm phát thải CO₂',
                    '-${(shopCo2SavedGrams / 1000.0).toStringAsFixed(2)} kg CO₂',
                    AppColors.success,
                    width: cardW,
                  ),
                  _codCard(
                    'Đơn Giao 2H (Ghép cặp)',
                    '$shopBatch2hCount đơn',
                    const Color(0xFF0EA5E9),
                    width: cardW,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final chartBox = Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F1E8),
                  borderRadius: BorderRadius.all(Radius.zero),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Biểu đồ Số đơn gửi theo ngày (Tháng ${DateTime.now().month})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 140,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final item in dailyChartItems)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${item.$3}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    FractionallySizedBox(
                                      widthFactor: 0.65,
                                      child: Container(
                                        height: 76 * item.$2,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF5B33E6),
                                          borderRadius: BorderRadius.all(
                                            Radius.zero,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.$1,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              final statusBox = Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F1E8),
                  borderRadius: BorderRadius.all(Radius.zero),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tỷ lệ trạng thái đơn hàng',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.circle,
                          color: AppColors.success,
                        ),
                        title: Text(
                          'Thành công: ${successRate.toStringAsFixed(1)}% ($deliveredCount đơn)',
                        ),
                      ),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.circle,
                          color: Color(0xFF5B33E6),
                        ),
                        title: Text(
                          'Đang giao / Chờ xử lý: ${inProgressRate.toStringAsFixed(1)}% ($inProgressCount đơn)',
                        ),
                      ),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.circle,
                          color: AppColors.danger,
                        ),
                        title: Text(
                          'Thất bại: ${failedRate.toStringAsFixed(1)}% ($failedOnlyCount đơn)',
                        ),
                      ),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.circle,
                          color: Color(0xFFFF5E83),
                        ),
                        title: Text(
                          'Hoàn hàng / Đã hủy: ${returnedRate.toStringAsFixed(1)}% ($returnedCount đơn)',
                        ),
                      ),
                    ],
                  ),
                ),
              );
              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [chartBox, const SizedBox(height: 14), statusBox],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: chartBox),
                  const SizedBox(width: 14),
                  Expanded(flex: 5, child: statusBox),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// UC40: Khiếu nại & Hỗ trợ Cửa hàng (Chuẩn uc40_khieu_nai_shop_v2_1791015801837.jpg)
  Widget _buildMerchantComplaintSupportUc40View() {
    final shopOrders = _store.merchantPersonalOrders;
    final shopComplaints = _store.merchantPersonalComplaints;
    final complaintTypes = [
      'Hàng hư hỏng / Mất hàng',
      'Sai lệch tiền thu hộ COD',
      'Tài xế lấy / giao hàng trễ hẹn',
      'Sai cước phí vận chuyển',
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final colLeft = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.zero),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gửi khiếu nại mới',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: shopOrders.map((ord) {
                  final selected =
                      _shopComplaintOrderCtrl.text.trim() == ord.trackingCode;
                  return ActionChip(
                    backgroundColor: selected
                        ? const Color(0xFFEDE9FE)
                        : const Color(0xFFF5F1E8),
                    label: Text(
                      '${ord.trackingCode} (${ord.status.displayName})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    onPressed: () {
                      _rebuildMerchantUi(() {
                        _shopComplaintOrderCtrl.text = ord.trackingCode;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _shopComplaintOrderCtrl,
                decoration: const InputDecoration(
                  labelText: 'Chọn đơn hàng cần khiếu nại',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _shopComplaintType,
                decoration: const InputDecoration(
                  labelText: 'Loại khiếu nại',
                  isDense: true,
                ),
                items: complaintTypes
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    _rebuildMerchantUi(() => _shopComplaintType = v);
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _shopComplaintDescCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Mô tả chi tiết sự cố / yêu cầu bồi thường',
                  hintText: 'Nhập tình trạng kiện hàng hoặc chênh lệch COD...',
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () async {
                  if (_attachedShopEvidenceFiles.length >= 5) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Đã đạt tối đa 5 tệp bằng chứng đối soát!',
                        ),
                      ),
                    );
                    return;
                  }
                  final pickedName =
                      await SecurityAndBarcodeUtils.pickLocalDocumentOrImage(
                        dialogTitle:
                            'Chọn tệp ảnh / chứng từ khiếu nại Cửa hàng B2B',
                      );
                  if (!context.mounted || pickedName == null) return;
                  if (_attachedShopEvidenceFiles.contains(pickedName)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Tệp "$pickedName" đã được đính kèm!'),
                      ),
                    );
                    return;
                  }
                  _rebuildMerchantUi(() {
                    _attachedShopEvidenceFiles.add(pickedName);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã đính kèm tệp bằng chứng thực tế: $pickedName (${_attachedShopEvidenceFiles.length}/5)!',
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F1E8),
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: Color(0xFF5B33E6),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Đính kèm ảnh/video bằng chứng (Đã chọn: ${_attachedShopEvidenceFiles.length}/5 file - Bấm để thêm)',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_attachedShopEvidenceFiles.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _attachedShopEvidenceFiles
                      .map(
                        (f) => InputChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(f, style: const TextStyle(fontSize: 11)),
                          onDeleted: () => _rebuildMerchantUi(
                            () => _attachedShopEvidenceFiles.remove(f),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5E83),
                  ),
                  onPressed: () {
                    final orderCode = _shopComplaintOrderCtrl.text.trim();
                    if (orderCode.isEmpty ||
                        !shopOrders.any(
                          (o) =>
                              o.trackingCode.toUpperCase() ==
                              orderCode.toUpperCase(),
                        )) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: AppColors.danger,
                          content: Text(
                            'Vui lòng chọn mã vận đơn hợp lệ thuộc cửa hàng của bạn trước khi gửi khiếu nại!',
                          ),
                        ),
                      );
                      return;
                    }
                    final expectedIssue = 'Shop KN: $_shopComplaintType';
                    final duplicateOpen = shopComplaints.any(
                      (c) =>
                          c.orderId.toUpperCase() == orderCode.toUpperCase() &&
                          c.issueType == expectedIssue &&
                          c.status != 'Đã giải quyết',
                    );
                    if (duplicateOpen) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppColors.danger,
                          content: Text(
                            'Cửa hàng đã gửi khiếu nại "$_shopComplaintType" cho đơn $orderCode và hồ sơ đang chờ Admin xử lý!',
                          ),
                        ),
                      );
                      return;
                    }
                    final baseDesc = _shopComplaintDescCtrl.text.trim().isEmpty
                        ? 'Yêu cầu kiểm tra đối soát / bồi thường đơn hàng'
                        : _shopComplaintDescCtrl.text.trim();
                    final chosenFiles = List<String>.from(
                      _attachedShopEvidenceFiles,
                    );
                    final fullDesc = chosenFiles.isEmpty
                        ? baseDesc
                        : '$baseDesc • [Đính kèm: ${chosenFiles.join(", ")}]';
                    _store.addIncidentOrComplaint(
                      orderId: orderCode,
                      reporterName:
                          _store.activeMerchantRecord?.storeName ??
                          'Cửa hàng B2B',
                      issueType: 'Shop KN: $_shopComplaintType',
                      description: fullDesc,
                      evidenceFiles: chosenFiles,
                    );
                    _rebuildMerchantUi(() {
                      _shopComplaintDescCtrl.clear();
                      _attachedShopEvidenceFiles.clear();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Đã gửi hồ sơ khiếu nại của Cửa hàng lên bộ phận CSKH Admin!',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.send_outlined, size: 16),
                  label: const Text('Gửi khiếu nại'),
                ),
              ),
            ],
          ),
        );
        final colRight = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.zero),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Danh sách khiếu nại đã gửi',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
              ),
              const SizedBox(height: 12),
              if (shopComplaints.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Chưa có hồ sơ khiếu nại nào thuộc cửa hàng của bạn.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ...shopComplaints.map(
                (c) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F1E8),
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            '#${c.ticketCode} - Đơn ${c.orderId}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                          ),
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              'Theo dõi ${c.orderId}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: () {
                              final ordIdx = shopOrders.indexWhere(
                                (o) => o.trackingCode == c.orderId,
                              );
                              _rebuildMerchantUi(() {
                                if (ordIdx != -1) {
                                  _selectedWaybillOrderIndex = ordIdx;
                                }
                                _selectedScreenIndex = 5;
                              });
                            },
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              c.status,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Loại: ${c.issueType}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Color(0xFF5B33E6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(c.description, style: const TextStyle(fontSize: 12)),
                      if (c.evidenceFiles.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: c.evidenceFiles
                              .map(
                                (f) => Chip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: const Icon(
                                    Icons.attach_file,
                                    size: 13,
                                  ),
                                  label: Text(
                                    f,
                                    style: const TextStyle(fontSize: 10.5),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      if (c.replies.length > 1) ...[
                        const Divider(),
                        ...c.replies
                            .skip(1)
                            .map(
                              (rep) => Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(
                                  '• $rep',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [colLeft, const SizedBox(height: 16), colRight],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: colLeft),
            const SizedBox(width: 16),
            Expanded(flex: 6, child: colRight),
          ],
        );
      },
    );
  }
}
