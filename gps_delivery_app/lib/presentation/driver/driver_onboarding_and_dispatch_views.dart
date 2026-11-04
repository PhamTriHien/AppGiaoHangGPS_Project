part of 'driver_subsystem_views.dart';

extension _DriverOnboardingAndDispatchViews on _DriverSubsystemEntryState {
  /// UC13: ĐĂNG KÝ TÀI KHOẢN TÀI XẾ (Khớp 100% uc13_dang_ky_tai_xe_1791014665242.jpg)
  Widget _buildDriverKycRegistrationView() {
    const requiredDocLabels = <String>[
      'CCCD mặt trước',
      'CCCD mặt sau',
      'Giấy phép lái xe',
      'Đăng ký xe',
    ];
    final docCount = requiredDocLabels
        .where(
          (lbl) =>
              _attachedKycDocs.any((d) => d == lbl || d.startsWith('$lbl:')),
        )
        .length;
    final kycProgress = (0.34 + (docCount / 4.0) * 0.66).clamp(0.34, 1.0);
    final stepLabel = docCount >= 4
        ? 'Bước 3/3 (Đủ 4/4)'
        : 'Bước 2/3 ($docCount/4)';
    final isAlreadyApproved =
        _store.activeDriverRecord?.approvalStatus == 'Đã duyệt';
    return Card(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.ink, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            color: const Color(0xFF0F172A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'ĐĂNG KÝ TÀI KHOẢN TÀI XẾ',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    stepLabel,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            value: kycProgress,
            minHeight: 5,
            backgroundColor: const Color(0xFFD1FAE5),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF14B866)),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_store.activeDriverRecord != null) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color:
                          _store.activeDriverRecord!.approvalStatus ==
                              'Đã duyệt'
                          ? const Color(0xFFDCFCE7)
                          : _store.activeDriverRecord!.approvalStatus ==
                                'Từ chối'
                          ? const Color(0xFFFEE2E2)
                          : const Color(0xFFFEF3C7),
                      border: Border.all(color: const Color(0xFF0F172A)),
                    ),
                    child: Row(
                      children: [
                        GhstButtonIcon(
                          _store.activeDriverRecord!.approvalStatus ==
                                  'Đã duyệt'
                              ? Icons.verified_rounded
                              : Icons.pending_actions_rounded,
                          size: 18,
                          color:
                              _store.activeDriverRecord!.approvalStatus ==
                                  'Đã duyệt'
                              ? const Color(0xFF14B866)
                              : const Color(0xFFD97706),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Hồ sơ hiện tại (${_store.activeDriverRecord!.id}): ${_store.activeDriverRecord!.approvalStatus} • ${_store.activeDriverRecord!.vehicleType} (${_store.activeDriverRecord!.licensePlate})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Text(
                  '1. Thông tin cá nhân',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final nameField = TextField(
                      controller: _drvNameCtrl,
                      decoration: const InputDecoration(labelText: 'Họ và tên'),
                    );
                    final phoneField = TextField(
                      controller: _drvPhoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại',
                      ),
                    );
                    if (constraints.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          nameField,
                          const SizedBox(height: 10),
                          phoneField,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: nameField),
                        const SizedBox(width: 10),
                        Expanded(child: phoneField),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _drvCitizenCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Số CCCD / CMND',
                    hintText: 'Nhập 12 chữ số CCCD',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '2. Thông tin phương tiện',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final trimmedVehicle = _vehicleType.trim().isNotEmpty
                        ? _vehicleType.trim()
                        : 'Xe máy';
                    final vehicleDropdown = DropdownButtonFormField<String>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), key: ValueKey(trimmedVehicle), isExpanded: true, initialValue: trimmedVehicle, decoration: const InputDecoration(labelText: 'Loại xe'), items:
                          <String>{
                                'Xe máy',
                                'Xe máy điện (VinFast EV)',
                                'Xe tải 500kg',
                                'Xe tải nhỏ',
                                'Xe bán tải',
                                'Xe Van',
                                trimmedVehicle,
                              }
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(
                                    v,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(), onChanged: (v) {
                        if (v != null) _rebuildDriverUi(() => _vehicleType = v);
                      },);
                    final plateField = TextField(
                      controller: _drvPlateCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Biển số xe',
                        hintText: 'VD: 59-P1 123.45',
                      ),
                    );
                    final bankNameField = BankDirectoryField(
                      controller: _drvBankNameCtrl,
                      label: 'Ngân hàng nhận thu nhập',
                    );
                    final bankAccField = TextField(
                      controller: _drvBankAccCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Số tài khoản ngân hàng',
                        hintText: 'Nhập số tài khoản nhận thu nhập',
                      ),
                    );
                    if (constraints.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          vehicleDropdown,
                          const SizedBox(height: 10),
                          plateField,
                          const SizedBox(height: 10),
                          bankNameField,
                          const SizedBox(height: 10),
                          bankAccField,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: vehicleDropdown),
                            const SizedBox(width: 10),
                            Expanded(child: plateField),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: bankNameField),
                            const SizedBox(width: 10),
                            Expanded(child: bankAccField),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  '3. Tải lên giấy tờ (Chụp ảnh)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildKycCameraBox('CCCD mặt trước')),
                    const SizedBox(width: 10),
                    Expanded(child: _buildKycCameraBox('CCCD mặt sau')),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildKycCameraBox('Giấy phép lái xe')),
                    const SizedBox(width: 10),
                    Expanded(child: _buildKycCameraBox('Đăng ký xe')),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    onPressed: () {
                      final fName = _drvNameCtrl.text.trim();
                      final phone = _drvPhoneCtrl.text.trim();
                      final citizen = _drvCitizenCtrl.text.trim();
                      final plate = _drvPlateCtrl.text.trim();
                      if (fName.isEmpty ||
                          phone.isEmpty ||
                          citizen.isEmpty ||
                          plate.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Vui lòng điền đầy đủ Họ tên, SĐT, CCCD và Biển số xe trước khi gửi hồ sơ!',
                            ),
                          ),
                        );
                        return;
                      }
                      if (!RegExp(r'^(\+84|0)[0-9]{8,10}$').hasMatch(phone) ||
                          !RegExp(r'^[0-9]{9,12}$').hasMatch(citizen)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: AppColors.danger,
                            content: Text(
                              'Vui lòng nhập Số điện thoại (10-11 số) và Số CCCD (9-12 chữ số) hợp lệ!',
                            ),
                          ),
                        );
                        return;
                      }
                      if (_attachedKycDocs.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Vui lòng đính kèm ít nhất 1 giấy tờ định danh (CCCD / GPLX / Đăng ký xe)!',
                            ),
                          ),
                        );
                        return;
                      }
                      _store.registerOrUpdateDriverKyc(
                        fullName: fName,
                        phone: phone,
                        citizenId: citizen,
                        vehicleType: _vehicleType,
                        licensePlate: plate,
                        bankName: _drvBankNameCtrl.text.trim(),
                        bankAccount: _drvBankAccCtrl.text.trim(),
                        attachedDocs: _attachedKycDocs.toList(),
                      );
                      final nowApproved =
                          _store.activeDriverRecord?.approvalStatus ==
                          'Đã duyệt';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            nowApproved
                                ? 'Đã cập nhật thông tin hồ sơ & tài khoản ngân hàng Tài xế thành công!'
                                : 'Đã gửi hồ sơ đăng ký Tài xế chờ duyệt thành công!',
                          ),
                        ),
                      );
                    },
                    icon: const GhstButtonIcon(Icons.send_rounded, size: 18),
                    label: Text(
                      isAlreadyApproved
                          ? 'CẬP NHẬT HỒ SƠ & NGÂN HÀNG'
                          : 'GỬI HỒ SƠ CHỜ DUYỆT',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKycCameraBox(String label) {
    final matchedDoc = _attachedKycDocs
        .where((d) => d == label || d.startsWith('$label:'))
        .firstOrNull;
    final isAttached = matchedDoc != null;
    final attachedFileName =
        (matchedDoc != null && matchedDoc.startsWith('$label:'))
        ? matchedDoc.substring(label.length + 1).trim()
        : '';
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      onTap: () async {
        if (isAttached) {
          _rebuildDriverUi(() => _attachedKycDocs.remove(matchedDoc));
          return;
        }
        final picked = await SecurityAndBarcodeUtils.pickLocalDocumentOrImage(
          dialogTitle: 'Chọn tệp / ảnh giấy tờ: $label',
        );
        if (picked == null || !mounted) return;
        _rebuildDriverUi(() {
          _attachedKycDocs
            ..removeWhere((d) => d == label || d.startsWith('$label:'))
            ..add('$label: $picked');
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: isAttached ? const Color(0xFFDCFCE7) : const Color(0xFFF4F7FA),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: Border.all(
            color: const Color(0xFF14B866),
            width: isAttached ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          children: [
            GhstButtonIcon(
              isAttached
                  ? Icons.check_circle_rounded
                  : Icons.upload_file_rounded,
              color: const Color(0xFF0F172A),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              isAttached
                  ? (attachedFileName.isNotEmpty
                        ? '$label\n($attachedFileName)'
                        : '$label (Đã đính kèm)')
                  : '$label (Chọn tệp)',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF065F46),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Trang chủ Tài xế & Gạt trạng thái Online/Offline (Khớp 100% uc14_bat_tat_trang_thai_1791021276770.jpg)
  Widget _buildDriverHomeOnlineView() {
    final activeDrv = _store.activeDriverRecord;
    final now = DateTime.now();
    final todayOrderCount = _store.driverPersonalOrders
        .where(
          (o) =>
              (o.daysAgoFrom(now) == 0 ||
                  o.status == OrderStatus.accepted ||
                  o.status == OrderStatus.arrivingPickup ||
                  o.status == OrderStatus.inTransit) &&
              o.status != OrderStatus.cancelled &&
              o.status != OrderStatus.failed &&
              o.status != OrderStatus.returning &&
              o.paymentStatus != 'RETURNED',
        )
        .length;
    final driverRating = activeDrv?.rating ?? 0.0;
    final availableWallet = activeDrv?.walletBalance ?? 0.0;

    return Card(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.ink, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: DeliveryWeatherStrip(point: _store.liveDeviceLocation),
          ),
          // Thanh trạng thái Tài xế độc lập phía trên Bản đồ (không đè lên bản đồ)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: AppColors.ink, width: 1.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Animated3dIconBadge(
                      style: Icon3dStyle.scooterExpress,
                      size: 46,
                      showRadarPulse: _store.isDriverOnline,
                      isSelected: _store.isDriverOnline,
                      animateIdle: _store.isDriverOnline,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Xin chào, ${_store.activeDriverName}!',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _store.isDriverOnline
                                      ? const Color(0xFF14B866)
                                      : const Color(0xFF94A3B8),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  _store.isDriverOnline
                                      ? 'Đang Online - Sẵn sàng nhận đơn'
                                      : 'Đang Offline - Nghỉ ngơi',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _store.isDriverOnline
                                        ? const Color(0xFF14B866)
                                        : const Color(0xFF4A4754),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _store.isDriverOnline
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFF4F7FA),
                        borderRadius: const BorderRadius.all(Radius.circular(12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _store.isDriverOnline ? 'ON' : 'OFF',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              color: _store.isDriverOnline
                                  ? const Color(0xFF14B866)
                                  : const Color(0xFF4A4754),
                            ),
                          ),
                          Switch(
                            value: _store.isDriverOnline,
                            activeThumbColor: const Color(0xFF14B866),
                            onChanged: (v) => _handleHeaderToggleDriverOnline(
                              context,
                              targetOnline: v,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 6,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF4F7FA),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        child: Text(
                          'Đơn hôm nay: $todayOrderCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 6,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF4F7FA),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        child: Text(
                          'Ví: ${CurrencyFormatter.formatVnd(availableWallet)}',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF14B866),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 6,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF4F7FA),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        child: Text(
                          driverRating > 0
                              ? 'Đánh giá: ${driverRating.toStringAsFixed(1)}★'
                              : 'Chưa có đánh giá',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (activeDrv != null && activeDrv.isElectricVehicle) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      border: Border.all(color: const Color(0xFF14B866)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const GhstButtonIcon(
                              Icons.electric_moped_rounded,
                              size: 16,
                              color: Color(0xFF059669),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Xe điện Xanh • Pin SoC: ${activeDrv.batteryPercent}% (Khả dụng ~${(SmartDispatchEngine.estimateEvUsableRangeMeters(activeDrv.batteryPercent) / 1000.0).toStringAsFixed(1)} km)',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF065F46),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                          ),
                          child: Slider(
                            value: activeDrv.batteryPercent
                                .clamp(5, 100)
                                .toDouble(),
                            min: 5,
                            max: 100,
                            divisions: 19,
                            activeColor: activeDrv.batteryPercent < 20
                                ? AppColors.danger
                                : const Color(0xFF14B866),
                            onChanged: (val) {
                              _store.updateActiveDriverBatteryPercent(
                                val.round(),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Builder(
            builder: (context) {
              final ongoingOrder = _store.activeDriverInProgressOrder;
              final compatibleSearchingOrders = _store.isDriverOnline
                  ? _store.orders
                        .where(_isSearchingOrderCompatibleWithActiveDriver)
                        .toList()
                  : const <ActiveOrderRecord>[];
              return Map3dPerspectiveWidget(
                height: 500,
                mode: MapViewMode.driverRadar,
                is3dMode: _store.isMap3dEnabled,
                speedKmh: _store.isDriverOnline && ongoingOrder != null
                    ? _store.currentSpeedKmh
                    : 0.0,
                onToggle3d: _store.toggleMap3d,
                driverLocation:
                    _store.verifiedDriverLocations[_store.activeDriverId],
                nearbySearchingOrders: compatibleSearchingOrders,
                routePoints: ongoingOrder != null
                    ? [
                        if (_store.verifiedDriverLocations[_store
                                .activeDriverId] !=
                            null)
                          _store.verifiedDriverLocations[_store
                              .activeDriverId]!,
                        ongoingOrder.pickupLocation,
                        ongoingOrder.dropoffLocation,
                      ]
                    : const [],
                pickupLabel: ongoingOrder != null
                    ? 'Lấy: ${ongoingOrder.pickupAddress}'
                    : 'Điểm lấy [A]',
                dropoffLabel: ongoingOrder != null
                    ? 'Giao: ${ongoingOrder.dropoffAddress}'
                    : 'Điểm giao [B]',
                nextTurnInstruction: _store.isDriverOnline
                    ? (ongoingOrder != null
                          ? 'Đang thực hiện đơn ${ongoingOrder.trackingCode} (${ongoingOrder.status.displayName})'
                          : (compatibleSearchingOrders.isNotEmpty
                                ? 'Có ${compatibleSearchingOrders.length} đơn hàng mới quanh bạn'
                                : 'Đang tìm đơn hàng quanh bạn'))
                    : 'Bật trạng thái ON để nhận đơn hàng mới',
                roadName:
                    ongoingOrder?.pickupAddress ??
                    (_store.liveDeviceAddress.trim().isNotEmpty
                        ? 'GPS Thiết bị: ${_store.liveDeviceAddress.trim()} (${_store.activeDriverLocation.latitude.toStringAsFixed(4)}, ${_store.activeDriverLocation.longitude.toStringAsFixed(4)})'
                        : 'Đang chờ vị trí GPS'),
              );
            },
          ),
          Builder(
            builder: (context) {
              final searchingOrd = _store.orders
                  .where(_isSearchingOrderCompatibleWithActiveDriver)
                  .firstOrNull;
              final activeOrd =
                  _store.activeDriverInProgressOrder ?? searchingOrd;
              if (!_store.isDriverOnline) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  color: AppColors.paper,
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Bạn đang ở chế độ Nghỉ ngơi (Offline). Bật trực tuyến để hệ thống tự động phát cuốc xe gần bạn.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14B866),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _handleHeaderToggleDriverOnline(
                          context,
                          targetOnline: true,
                        ),
                        icon: const GhstButtonIcon(
                          Icons.power_settings_new_rounded,
                          size: 18,
                        ),
                        label: const Text('BẬT ONLINE NGAY'),
                      ),
                    ],
                  ),
                );
              }

              if (activeOrd != null &&
                  activeOrd.status == OrderStatus.searching) {
                final estNet =
                    (activeOrd.deliveryFee + activeOrd.surchargeFee) * 0.80;
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCFCE7),
                    border: Border(
                      top: BorderSide(color: AppColors.ink, width: 1.5),
                    ),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CÓ ĐƠN HÀNG MỚI QUANH BẠN • ${activeOrd.trackingCode} (Thu nhập: ${CurrencyFormatter.formatVnd(estNet)})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: Color(0xFF166534),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Lấy: ${activeOrd.pickupAddress} → Giao: ${activeOrd.dropoffAddress}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF14B866),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _rebuildDriverUi(
                              () => _selectedScreenIndex = 2,
                            ),
                            icon: const GhstButtonIcon(
                              Icons.notifications_active_outlined,
                              size: 18,
                            ),
                            label: const Text('Xem & Nhận đơn (28s)'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }

              if (activeOrd != null &&
                  activeOrd.status != OrderStatus.delivered &&
                  activeOrd.status != OrderStatus.cancelled) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: AppColors.paper,
                    border: Border(
                      top: BorderSide(color: AppColors.ink, width: 1.5),
                    ),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CUỐC XE ĐANG THỰC HIỆN: ${activeOrd.trackingCode} (${activeOrd.status.displayName})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Điểm giao: ${activeOrd.dropoffAddress} • Khách: ${activeOrd.recipientName}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              _store.selectDriverOrder(activeOrd.trackingCode);
                              _rebuildDriverUi(() => _selectedScreenIndex = 3);
                            },
                            icon: const GhstButtonIcon(
                              Icons.navigation_outlined,
                              size: 18,
                            ),
                            label: const Text('Điều hướng GPS'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              _store.selectDriverOrder(activeOrd.trackingCode);
                              _rebuildDriverUi(() => _selectedScreenIndex = 5);
                            },
                            icon: const GhstButtonIcon(
                              Icons.fact_check_outlined,
                              size: 18,
                            ),
                            label: const Text('Xác nhận POD'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }

              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  /// UC15: Nhận thông báo đơn hàng mới (Khớp 100% uc15_nhan_tu_choi_don_1791021299473.jpg)
  Widget _buildIncomingOrderPopupView() {
    final searchingOrders = _store.orders
        .where(_isSearchingOrderCompatibleWithActiveDriver)
        .toList();
    final selectedFromStore = searchingOrders
        .where((o) => o.trackingCode == _store.selectedDriverOrderCode)
        .firstOrNull;
    final targetOrder = selectedFromStore ?? searchingOrders.firstOrNull;
    final ongoingTrip = _store.activeDriverInProgressOrder;
    if (targetOrder == null) {
      return Card(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: AppColors.ink, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Đang dò tìm đơn hàng mới quanh khu vực của bạn',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                ongoingTrip != null
                    ? 'Hiện chưa có cuốc xe mới (SEARCHING) phù hợp phương tiện của bạn. Bạn đang thực hiện cuốc xe ${ongoingTrip.trackingCode} (${ongoingTrip.status.displayName}).'
                    : 'Hiện tại chưa có đơn hàng nào đang chờ nhận (SEARCHING) phù hợp phương tiện quanh vị trí của bạn.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF14B866),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () =>
                        _rebuildDriverUi(() => _selectedScreenIndex = 1),
                    icon: const GhstButtonIcon(Icons.radar_rounded, size: 18),
                    label: const Text('Quay lại Radar Trực tuyến'),
                  ),
                  if (ongoingTrip != null)
                    OutlinedButton.icon(
                      onPressed: () {
                        _store.selectDriverOrder(ongoingTrip.trackingCode);
                        _rebuildDriverUi(() => _selectedScreenIndex = 3);
                      },
                      icon: const GhstButtonIcon(Icons.navigation_outlined, size: 18),
                      label: Text('Điều hướng ${ongoingTrip.trackingCode}'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    final rankedCandidates = SmartDispatchEngine.rankDriversForPickup(
      pickupLocation: targetOrder.pickupLocation,
      drivers: _store.drivers,
      excludedDriverIds: _rejectedDriverIds,
      requireElectricVehicle: targetOrder.preferEcoEv,
      preferElectricVehicle: targetOrder.preferEcoEv,
      totalOrderRouteMeters: targetOrder.isRoundTrip
          ? (targetOrder.distanceMeters * 2)
          : targetOrder.distanceMeters,
      declaredValueVnd: targetOrder.declaredValueVnd,
      codAmount: targetOrder.codAmount,
      serviceType: targetOrder.serviceType,
    );
    final topCandidate = rankedCandidates.isNotEmpty
        ? rankedCandidates.first
        : null;
    final isTimerRunning = _dispatchCountdownTimer?.isActive ?? false;
    final greenDeduction = targetOrder.greenFundContributed ? 1000.0 : 0.0;
    final driverCommissionBase =
        (targetOrder.deliveryFee +
                targetOrder.surchargeFee -
                targetOrder.insuranceFee -
                greenDeduction)
            .clamp(0.0, double.infinity);
    final expectedNetDriverEarning = driverCommissionBase * 0.80;
    final popupOrders = searchingOrders;

    return Card(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.ink, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (popupOrders.length > 1) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: popupOrders.map((ord) {
                  final selected = ord.trackingCode == targetOrder.trackingCode;
                  return ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.glyph(GhstActionKind.receipt, size: 15, color: (selected) ? Colors.white : null), visualDensity: VisualDensity.compact, label: Text(
                      '${ord.trackingCode} (${ord.status.displayName})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : AppColors.ink,
                      ),
                    ), selected: selected, selectedColor: const Color(0xFF14B866), onSelected: (_) {
                      _store.selectDriverOrder(ord.trackingCode);
                      _rebuildDriverUi(() => _countdownSeconds = 28);
                    },);
                }).toList(),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        child: Text(
                          '${targetOrder.serviceType.displayName.toUpperCase()} • ${(targetOrder.distanceMeters / 1000).toStringAsFixed(1)} KM',
                          style: const TextStyle(
                            color: Color(0xFF14B866),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'ĐƠN HÀNG MỚI!',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: _countdownSeconds / 28.0,
                        strokeWidth: 5,
                        backgroundColor: const Color(0xFF0F172A),
                        color: isTimerRunning
                            ? AppColors.danger
                            : const Color(0xFF14B866),
                      ),
                      Text(
                        '${_countdownSeconds}s',
                        style: const TextStyle(
                          color: Color(0xFF14B866),
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (topCandidate != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FA),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    const Animated3dIconBadge(
                      style: Icon3dStyle.gpsPinRadar,
                      size: 44,
                      showRadarPulse: true,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Hệ thống điều phối cuốc xe trong bán kính ${topCandidate.searchRadiusTierMeters ~/ 1000} km gần vị trí của bạn • Thời gian phản hồi: ${_countdownSeconds}s',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF166534),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7FA),
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.all(color: const Color(0xFF14B866), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Thu nhập dự kiến (80%): ${CurrencyFormatter.formatVnd(expectedNetDriverEarning)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: Color(0xFF14B866),
                        ),
                      ),
                      Text(
                        'Khoảng cách: ${(targetOrder.distanceMeters / 1000).toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  Text('• Điểm lấy hàng: ${targetOrder.pickupAddress}'),
                  const SizedBox(height: 4),
                  Text('• Điểm giao hàng: ${targetOrder.dropoffAddress}'),
                  const SizedBox(height: 4),
                  Text(
                    '• Ứng tiền COD: ${CurrencyFormatter.formatVnd(targetOrder.codAmount)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                  if (targetOrder.preferEcoEv ||
                      targetOrder.batchGroupId != null ||
                      targetOrder.declaredValueVnd > 0 ||
                      targetOrder.extraStopCount > 0 ||
                      targetOrder.isRoundTrip) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (targetOrder.preferEcoEv)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            color: const Color(0xFFDCFCE7),
                            child: Text(
                              'Xe điện Xanh • -${targetOrder.co2SavedGrams.toStringAsFixed(0)}g CO₂',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF065F46),
                              ),
                            ),
                          ),
                        if (targetOrder.batchGroupId != null &&
                            targetOrder.batchGroupId!.trim().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            color: const Color(0xFFE0F2FE),
                            child: Text(
                              'Đơn ghép 2H: ${targetOrder.batchGroupId}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0369A1),
                              ),
                            ),
                          ),
                        if (targetOrder.declaredValueVnd > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            color: const Color(0xFFFEF3C7),
                            child: Text(
                              'Bảo hiểm khai giá: ${CurrencyFormatter.formatVnd(targetOrder.declaredValueVnd)}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ),
                        if (targetOrder.extraStopCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            color: const Color(0xFFEDE9FE),
                            child: Text(
                              'Đa điểm dừng (+${targetOrder.extraStopCount} trạm)',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        if (targetOrder.isRoundTrip)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            color: const Color(0xFFFCE7F3),
                            child: const Text(
                              'Giao 2 chiều (Khứ hồi)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF9D174D),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: () {
                      _store.recordDriverDispatchRejection(
                        targetOrder.trackingCode,
                      );
                      _rebuildDriverUi(() {
                        _rejectedOrderCodes.add(targetOrder.trackingCode);
                        _countdownSeconds = 28;
                        _reassignToNextCandidate();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã từ chối cuốc ${targetOrder.trackingCode}. Hệ thống đã ghi nhận vào tỷ lệ nhận đơn và chuyển tiếp cho tài xế kế tiếp.',
                          ),
                        ),
                      );
                    },
                    icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

                    label: const Text('Từ chối (Chuyển tiếp)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF14B866),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: () {
                      final currentActiveDrv = _store.activeDriverRecord;
                      if (currentActiveDrv == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: AppColors.danger,
                            content: Text(
                              'Vui lòng hoàn tất đăng ký hồ sơ KYC Tài xế trước khi nhận đơn!',
                            ),
                          ),
                        );
                        _rebuildDriverUi(() => _selectedScreenIndex = 0);
                        return;
                      }
                      if (currentActiveDrv.approvalStatus != 'Đã duyệt') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.danger,
                            content: Text(
                              'Hồ sơ Tài xế đang ở trạng thái "${currentActiveDrv.approvalStatus}". Vui lòng chờ Admin duyệt KYC trước khi nhận đơn!',
                            ),
                          ),
                        );
                        return;
                      }
                      final drvBal = currentActiveDrv.walletBalance;
                      final minEscrow =
                          SmartDispatchEngine.requiredMinWalletForOrder(
                            codAmount: targetOrder.codAmount,
                            declaredValueVnd: targetOrder.declaredValueVnd,
                          );
                      if (drvBal < minEscrow) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.warning,
                            content: Text(
                              'Ví ký quỹ (${CurrencyFormatter.formatVnd(drvBal)}) chưa đạt tối thiểu ${CurrencyFormatter.formatVnd(minEscrow)} cho đơn hàng này. Đang chuyển tới Ví Thu nhập...',
                            ),
                          ),
                        );
                        _rebuildDriverUi(() => _selectedScreenIndex = 6);
                        return;
                      }
                      final inProg = _store.activeDriverInProgressOrder;
                      if (inProg != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.warning,
                            content: Text(
                              'Bạn đang thực hiện cuốc xe ${inProg.trackingCode} (${inProg.status.displayName}). Vui lòng hoàn tất cuốc hiện tại trước khi nhận cuốc mới!',
                            ),
                          ),
                        );
                        _store.selectDriverOrder(inProg.trackingCode);
                        _rebuildDriverUi(() => _selectedScreenIndex = 3);
                        return;
                      }
                      _dispatchCountdownTimer?.cancel();
                      if (!_store.isDriverOnline) {
                        _store.setDriverOnlineStatus(true);
                      }
                      final assignedName = currentActiveDrv.fullName;
                      final assignedPlate = currentActiveDrv.licensePlate;
                      final wasStillSearching =
                          targetOrder.status == OrderStatus.searching;
                      _store.driverAcceptOrder(
                        targetOrder.trackingCode,
                        customDriverName: assignedName,
                        customPlate: assignedPlate,
                      );
                      if (targetOrder.status != OrderStatus.accepted) {
                        final failReason = !wasStillSearching
                            ? 'Đơn hàng ${targetOrder.trackingCode} vừa được xử lý hoặc đã hết hiệu lực nhận chuyến!'
                            : 'Phương tiện hoặc ví ký quỹ của bạn chưa đủ điều kiện nhận đơn này!';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.danger,
                            content: Text(failReason),
                          ),
                        );
                        return;
                      }
                      _store.selectDriverOrder(targetOrder.trackingCode);
                      _podRecipientCtrl.text = targetOrder.recipientName;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã nhận cuốc xe ${targetOrder.trackingCode} thành công!',
                          ),
                        ),
                      );
                      _rebuildDriverUi(() => _selectedScreenIndex = 3);
                    },
                    icon: const GhstButtonIcon(Icons.check_circle_outline),
                    label: const Text('NHẬN ĐƠN NGAY'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// UC16: Điều hướng 3D GPS Turn-by-Turn tới điểm lấy/giao hàng (Khớp 100% uc16_dieu_huong_gps_1791021319175.jpg)
  Widget _buildTurnByTurnNavigationView() {
    final activeOrder = _store.activeDriverPersonalOrderRecord;
    if (activeOrder == null) {
      return Card(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: AppColors.ink, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chưa có cuốc xe đang điều hướng',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tài khoản tài xế của bạn hiện chưa nhận đơn hàng nào. Vui lòng mở màn hình Nhận đơn mới để nhận cuốc xe trước khi bắt đầu dẫn đường GPS.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF14B866),
                  foregroundColor: Colors.white,
                ),
                onPressed: () =>
                    _rebuildDriverUi(() => _selectedScreenIndex = 2),
                icon: const GhstButtonIcon(Icons.notifications_active_outlined, size: 18),
                label: const Text('Mở Nhận đơn mới'),
              ),
            ],
          ),
        ),
      );
    }
    final isReturningToWarehouse = activeOrder.status == OrderStatus.returning;
    final isHeadingToPickup =
        isReturningToWarehouse ||
        activeOrder.status == OrderStatus.searching ||
        activeOrder.status == OrderStatus.accepted ||
        activeOrder.status == OrderStatus.arrivingPickup;
    final remMeters = isHeadingToPickup
        ? _store.distanceFromDriverToPickupMeters()
        : _store.distanceFromDriverToDropoffMeters();
    final targetAddress = isHeadingToPickup
        ? activeOrder.pickupAddress
        : activeOrder.dropoffAddress;
    final navHeadline = !_store.hasRealDeviceGpsFix
        ? 'Đang chờ vị trí GPS'
        : remMeters <= 100
        ? 'Gần điểm đến'
        : targetAddress;
    final navSubline = !_store.hasRealDeviceGpsFix
        ? targetAddress
        : 'Khoảng cách thẳng đến điểm ${isHeadingToPickup ? 'lấy' : 'giao'}: ${(remMeters / 1000).toStringAsFixed(2)} km';
    final shouldMaskPhone =
        activeOrder.status == OrderStatus.delivered ||
        activeOrder.status == OrderStatus.cancelled ||
        activeOrder.status == OrderStatus.failed ||
        activeOrder.status == OrderStatus.returning ||
        activeOrder.paymentStatus == 'RETURNED';
    final displayPhone = SecurityAndBarcodeUtils.maskPhoneNumber(
      activeOrder.recipientPhone,
      shouldMask: shouldMaskPhone,
    );

    return Card(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.ink, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: LiveOrderConnection(
              key: ValueKey('driver-live-${activeOrder.trackingCode}'),
              room: activeOrder.trackingCode,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: DeliveryWeatherStrip(
              point: isHeadingToPickup
                  ? activeOrder.pickupLocation
                  : activeOrder.dropoffLocation,
            ),
          ),
          Builder(
            builder: (context) {
              final quickNote = _store.quickDeliveryInstructionFor(
                activeOrder.trackingCode,
              );
              final recipientTrust = _store.evaluateRecipientTrust(
                activeOrder.recipientPhone,
              );
              return Container(
                margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  border: Border.all(color: const Color(0xFF2563EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Tín nhiệm người nhận: ${recipientTrust.trustScore}/100 (${recipientTrust.riskTier})',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: recipientTrust.isHighRisk
                                ? AppColors.danger
                                : const Color(0xFF065F46),
                          ),
                        ),
                        if (_store.isMultiStopRouteActive)
                          const Text(
                            '• Đang chạy lộ trình ghép tuyến 2-Opt',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF14B866),
                            ),
                          ),
                      ],
                    ),
                    if (quickNote.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '📌 Chỉ dẫn giao nhanh từ Khách: "$quickNote"',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          // Dark Navy Turn-by-Turn Instruction Banner (#0F172A)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF0F172A),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF14B866),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  child: GhstButtonIcon(
                    remMeters <= 100
                        ? Icons.flag_rounded
                        : Icons.turn_right_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        navHeadline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        navSubline,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_store.driverPersonalOrders.length > 1) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _store.driverPersonalOrders.map((ord) {
                      final selected =
                          ord.trackingCode == activeOrder.trackingCode;
                      return ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.glyph(GhstActionKind.receipt, size: 15, color: (selected) ? Colors.white : null), visualDensity: VisualDensity.compact, label: Text(
                          '${ord.trackingCode} (${ord.status.displayName})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : AppColors.ink,
                          ),
                        ), selected: selected, selectedColor: const Color(0xFF14B866), onSelected: (_) {
                          _store.selectDriverOrder(ord.trackingCode);
                          _podRecipientCtrl.text = ord.recipientName;
                        },);
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                ],
                Map3dPerspectiveWidget(
                  height: 520,
                  mode: MapViewMode.driverTurnByTurn,
                  showTopBanner: false,
                  is3dMode: _store.isMap3dEnabled,
                  speedKmh:
                      _store.isDriverOnline &&
                          (activeOrder.status == OrderStatus.accepted ||
                              activeOrder.status ==
                                  OrderStatus.arrivingPickup ||
                              activeOrder.status == OrderStatus.inTransit ||
                              activeOrder.status == OrderStatus.returning)
                      ? _store.currentSpeedKmh
                      : 0.0,
                  onToggle3d: _store.toggleMap3d,
                  driverLocation:
                      _store.verifiedDriverLocations[_store.activeDriverId],
                  progressFraction: activeOrder.status == OrderStatus.delivered
                      ? 1.0
                      : (_store.routeProgressStep > 0
                            ? (_store.routeProgressStep / 10.0)
                            : (1.0 -
                                      (_store
                                              .distanceFromDriverToDropoffMeters() /
                                          activeOrder.distanceMeters.clamp(
                                            250.0,
                                            500000.0,
                                          )))
                                  .clamp(0.0, 1.0)),
                  routePoints: _store.activeRoutePolyline.length >= 2
                      ? _store.activeRoutePolyline
                      : <GeoPoint>[
                          activeOrder.pickupLocation,
                          _store.activeDriverLocation,
                          activeOrder.dropoffLocation,
                        ],
                  pickupLabel: 'Lấy: ${activeOrder.pickupAddress}',
                  dropoffLabel: 'Giao: ${activeOrder.dropoffAddress}',
                  nextTurnInstruction: navHeadline,
                  roadName:
                      'Còn ${(remMeters / 1000).toStringAsFixed(2)} km • Góc hướng: ${_store.activeDriverBearing.toStringAsFixed(0)}°',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Khách nhận: ${activeOrder.recipientName} ($displayPhone)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        if (shouldMaskPhone) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'SĐT Khách hàng đã ẩn bảo mật ($displayPhone) do đơn hàng đã đóng.',
                              ),
                            ),
                          );
                          return;
                        }
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(
                          ClipboardData(text: activeOrder.recipientPhone),
                        );
                        _store.sendChatMessage(
                          activeOrder.trackingCode,
                          '📞 Đã thực hiện cuộc gọi liên hệ người nhận ($displayPhone)',
                          isCustomer: false,
                        );
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Đã sao chép SĐT ${activeOrder.recipientPhone} vào khay nhớ tạm và ghi nhận nhật ký cuộc gọi tới ${activeOrder.recipientName}!',
                            ),
                          ),
                        );
                      },
                      icon: const GhstButtonIcon(Icons.phone_in_talk_outlined, size: 16),
                      label: const Text('Gọi khách'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final msg = await _store.acquireRealHardwareGps();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(msg)));
                      },
                      icon: const GhstButtonIcon(Icons.satellite_alt, size: 16),
                      label: const Text('Định vị GPS Thiết bị'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final msg = await _store
                            .syncLiveOsrmRouteForActiveOrder();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(msg)));
                      },
                      icon: const GhstButtonIcon(Icons.alt_route_rounded, size: 16),
                      label: const Text('Đồng bộ OSRM'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          _rebuildDriverUi(() => _selectedScreenIndex = 7),
                      icon: const GhstButtonIcon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: AppColors.danger,
                      ),
                      label: const Text('Báo cáo sự cố'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _rebuildDriverUi(
                        () => _showDriverChatPanel = !_showDriverChatPanel,
                      ),
                      icon: const GhstButtonIcon(
                        Icons.chat_bubble_outline_rounded,
                        size: 16,
                        color: Color(0xFF2563EB),
                      ),
                      label: Text(
                        'Chat với Khách (${_store.chatMessages.where((m) => m.orderId == activeOrder.trackingCode).length})',
                      ),
                    ),
                  ],
                ),
                if (_showDriverChatPanel) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F7FA),
                      border: Border.all(color: const Color(0xFF0F172A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const GhstButtonIcon(
                              Icons.forum_rounded,
                              size: 16,
                              color: Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Trao đổi trực tiếp với khách nhận (${activeOrder.trackingCode})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 150),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: _store.chatMessages
                                  .where(
                                    (m) =>
                                        m.orderId == activeOrder.trackingCode,
                                  )
                                  .map(
                                    (m) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '${m.isCustomer ? "[Khách]" : "[Tài xế]"} ${m.senderName}: ${m.text}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: m.isCustomer
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          color: m.isCustomer
                                              ? const Color(0xFF2563EB)
                                              : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children:
                              [
                                'Tôi đang trên đường giao hàng',
                                'Tôi đã đến điểm giao, vui lòng nhận hàng',
                                'Vui lòng đọc mã OTP 4 số nhận hàng',
                              ].map((quickMsg) {
                                final canQuickChat =
                                    activeOrder.status ==
                                        OrderStatus.accepted ||
                                    activeOrder.status ==
                                        OrderStatus.arrivingPickup ||
                                    activeOrder.status ==
                                        OrderStatus.inTransit ||
                                    activeOrder.status == OrderStatus.returning;
                                return ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: const GhstButtonIcon.glyph(GhstActionKind.chat, size: 14),
                                  label: Text(
                                    quickMsg,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onPressed: canQuickChat
                                      ? () {
                                          _store.sendChatMessage(
                                            activeOrder.trackingCode,
                                            quickMsg,
                                            isCustomer: false,
                                          );
                                        }
                                      : null,
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _driverChatInputCtrl,
                                enabled:
                                    activeOrder.status ==
                                        OrderStatus.accepted ||
                                    activeOrder.status ==
                                        OrderStatus.arrivingPickup ||
                                    activeOrder.status ==
                                        OrderStatus.inTransit ||
                                    activeOrder.status == OrderStatus.returning,
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText:
                                      (activeOrder.status ==
                                              OrderStatus.accepted ||
                                          activeOrder.status ==
                                              OrderStatus.arrivingPickup ||
                                          activeOrder.status ==
                                              OrderStatus.inTransit ||
                                          activeOrder.status ==
                                              OrderStatus.returning)
                                      ? 'Nhập tin nhắn gửi khách hàng...'
                                      : 'Chỉ nhắn tin khi đang thực hiện chuyến giao',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF14B866),
                                foregroundColor: Colors.white,
                              ),
                              onPressed:
                                  (activeOrder.status == OrderStatus.accepted ||
                                      activeOrder.status ==
                                          OrderStatus.arrivingPickup ||
                                      activeOrder.status ==
                                          OrderStatus.inTransit ||
                                      activeOrder.status ==
                                          OrderStatus.returning)
                                  ? () {
                                      final txt = _driverChatInputCtrl.text
                                          .trim();
                                      if (txt.isEmpty) return;
                                      _store.sendChatMessage(
                                        activeOrder.trackingCode,
                                        txt,
                                        isCustomer: false,
                                      );
                                      _driverChatInputCtrl.clear();
                                    }
                                  : null,
                              icon: const GhstButtonIcon.glyph(GhstActionKind.send, size: 16),

                              label: const Text('Gửi'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// UC17: Cập nhật tiến độ chuyến giao (Khớp 100% uc17_cap_nhat_trang_thai_pod_1791021350773.jpg)
  Widget _buildTripStepProgressView() {
    final ord = _store.activeDriverPersonalOrderRecord;
    if (ord == null) {
      return Card(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: AppColors.ink, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chưa có chuyến giao cần cập nhật tiến độ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bạn chưa nhận cuốc xe nào. Vui lòng nhận đơn hàng mới trước khi cập nhật tiến độ giao nhận.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF14B866),
                  foregroundColor: Colors.white,
                ),
                onPressed: () =>
                    _rebuildDriverUi(() => _selectedScreenIndex = 2),
                icon: const GhstButtonIcon(Icons.notifications_active_outlined, size: 18),
                label: const Text('Mở Nhận đơn mới'),
              ),
            ],
          ),
        ),
      );
    }
    final isNormalFlow =
        ord.status.index >= OrderStatus.accepted.index &&
        ord.status.index <= OrderStatus.delivered.index &&
        ord.paymentStatus != 'RETURNED';
    final isTerminal =
        ord.status == OrderStatus.delivered ||
        ord.status == OrderStatus.cancelled ||
        ord.paymentStatus == 'RETURNED';
    return Card(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.ink, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF14B866),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: Text(
                'Cập nhật trạng thái đơn ${ord.trackingCode}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_store.driverPersonalOrders.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _store.driverPersonalOrders.map((o) {
                  final selected = o.trackingCode == ord.trackingCode;
                  final statusText = o.paymentStatus == 'RETURNED'
                      ? 'Đã hoàn kho'
                      : o.status.displayName;
                  return ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.glyph(GhstActionKind.receipt, size: 15, color: (selected) ? Colors.white : null), visualDensity: VisualDensity.compact, label: Text(
                      '${o.trackingCode} ($statusText)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF0F172A),
                      ),
                    ), selected: selected, selectedColor: const Color(0xFF14B866), onSelected: (_) => _rebuildDriverUi(
                      () => _store.selectDriverOrder(o.trackingCode),
                    ),);
                }).toList(),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Mã vận đơn: ${ord.trackingCode} • Trạng thái hiện tại: ${ord.status.displayName}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF14B866),
              ),
            ),
            const SizedBox(height: 10),
            _stepTile(
              'Bước 1: Đã nhận đơn',
              isNormalFlow && ord.status.index >= OrderStatus.accepted.index,
            ),
            _stepTile(
              'Bước 2: Đã đến điểm lấy hàng',
              isNormalFlow &&
                  ord.status.index >= OrderStatus.arrivingPickup.index,
            ),
            _stepTile(
              'Bước 3: Đã lấy hàng & Đang giao',
              isNormalFlow && ord.status.index >= OrderStatus.inTransit.index,
            ),
            _stepTile(
              'Bước 4: Đã giao hàng thành công & Ký nhận POD',
              isNormalFlow && ord.status == OrderStatus.delivered,
            ),
            if (ord.status == OrderStatus.returning ||
                ord.paymentStatus == 'RETURNED')
              _stepTile(
                ord.paymentStatus == 'RETURNED'
                    ? 'Hoàn kho: Đã bàn giao kiện hàng về kho gửi thành công'
                    : 'Hoàn kho: Đang vận chuyển kiện hàng quay về kho gửi [A]',
                ord.paymentStatus == 'RETURNED',
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF14B866),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: isTerminal
                        ? null
                        : () {
                            final activeDrv = _store.activeDriverRecord;
                            if (activeDrv != null &&
                                activeDrv.approvalStatus != 'Đã duyệt') {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: AppColors.danger,
                                  content: Text(
                                    'Hồ sơ tài xế đang ở trạng thái "${activeDrv.approvalStatus}". Chưa thể cập nhật chuyến giao!',
                                  ),
                                ),
                              );
                              return;
                            }
                            if (!_store.isDriverOnline) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: AppColors.danger,
                                  content: Text(
                                    'Vui lòng bật trạng thái Trực tuyến (Online) trước khi cập nhật tiến độ đơn hàng!',
                                  ),
                                ),
                              );
                              return;
                            }
                            if (ord.status == OrderStatus.inTransit) {
                              _rebuildDriverUi(() => _selectedScreenIndex = 5);
                            } else if (ord.status == OrderStatus.searching ||
                                ord.status == OrderStatus.draft) {
                              if ((activeDrv?.walletBalance ?? 0.0) < 200000) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: AppColors.danger,
                                    content: Text(
                                      'Số dư Ví ký quỹ tối thiểu phải đạt 200.000đ mới được nhận đơn (Đang mở Ví thu nhập để nạp ký quỹ)!',
                                    ),
                                  ),
                                );
                                _rebuildDriverUi(
                                  () => _selectedScreenIndex = 6,
                                );
                                return;
                              }
                              _store.driverAcceptOrder(ord.trackingCode);
                            } else {
                              _store.driverAdvanceOrderStatus(ord.trackingCode);
                            }
                          },
                    icon: const GhstButtonIcon(Icons.double_arrow),
                    label: Text(
                      ord.paymentStatus == 'RETURNED'
                          ? 'Đã hoàn trả về Kho thành công'
                          : ord.status == OrderStatus.delivered
                          ? 'Đã hoàn tất giao hàng'
                          : ord.status == OrderStatus.cancelled
                          ? 'Đơn hàng đã hủy'
                          : ord.status == OrderStatus.failed
                          ? 'Bắt đầu giao lại chuyến hàng'
                          : ord.status == OrderStatus.returning
                          ? 'Xác nhận hoàn trả về Kho'
                          : ord.status == OrderStatus.inTransit
                          ? 'Đã đến điểm giao • Xác nhận POD & OTP'
                          : 'Cập nhật bước tiếp theo',
                    ),
                  ),
                ),
              ],
            ),
            if (ord.status == OrderStatus.inTransit) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger, width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () =>
                      _showDriverMarkDeliveryFailedDialog(context, ord),
                  icon: const GhstButtonIcon(Icons.assignment_late_outlined, size: 18),
                  label: const Text(
                    'Báo giao thất bại (Khách không nhận / Không nghe máy)',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stepTile(String label, bool completed) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: GhstButtonIcon(
        completed ? Icons.check_circle : Icons.radio_button_unchecked,
        color: completed ? const Color(0xFF14B866) : AppColors.textSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: completed ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }

  /// UC17: Xác nhận giao hàng thành công (POD Photo + OTP 4 số + Kiểm tra <= 100m)
  Widget _buildPodConfirmationView() {
    final ord = _store.activeDriverPersonalOrderRecord;
    if (ord == null) {
      return Card(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: AppColors.ink, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chưa có đơn hàng cần xác nhận POD & OTP',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bạn chưa có chuyến giao nào được gán. Vui lòng nhận đơn hàng mới trước khi chụp ảnh xác nhận POD.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF14B866),
                  foregroundColor: Colors.white,
                ),
                onPressed: () =>
                    _rebuildDriverUi(() => _selectedScreenIndex = 2),
                icon: const GhstButtonIcon(Icons.notifications_active_outlined, size: 18),
                label: const Text('Mở Nhận đơn mới'),
              ),
            ],
          ),
        ),
      );
    }
    final distMeters = _store.distanceFromDriverToDropoffMeters();
    final isWithin100m = _store.hasRealDeviceGpsFix && distMeters <= 100.0;
    final isOrderClosed =
        ord.status == OrderStatus.delivered ||
        ord.status == OrderStatus.cancelled;
    final isInTransit = ord.status == OrderStatus.inTransit;
    final canConfirmPod = isInTransit && isWithin100m && !isOrderClosed;
    final expectedOtp4 = SecurityAndBarcodeUtils.generateOrderDeliveryOtp4(
      ord.trackingCode,
    );

    return Card(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.ink, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF14B866),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: Text(
                'Xác nhận Giao hàng POD & Mã OTP (${ord.trackingCode})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_store.driverPersonalOrders.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _store.driverPersonalOrders.map((o) {
                  final selected = o.trackingCode == ord.trackingCode;
                  return ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.glyph(GhstActionKind.receipt, size: 15, color: (selected) ? Colors.white : null), visualDensity: VisualDensity.compact, label: Text(
                      '${o.trackingCode} (${o.status.displayName})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF0F172A),
                      ),
                    ), selected: selected, selectedColor: const Color(0xFF14B866), onSelected: (_) => _rebuildDriverUi(() {
                      _store.selectDriverOrder(o.trackingCode);
                      if (o.recipientName.trim().isNotEmpty) {
                        _podRecipientCtrl.text = o.recipientName.trim();
                      }
                    }),);
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            if (ord.extraStopCount > 0 || ord.isRoundTrip) ...[
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _store.orderStopsFor(ord.id),
                builder: (context, snapshot) {
                  final stops = snapshot.data ?? const [];
                  if (stops.isEmpty) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F7FA),
                      border: Border.all(color: AppColors.ink),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Checklist Lộ trình Đa điểm dừng / Khứ hồi (${stops.length} trạm)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...stops.map((s) {
                          final seqNo =
                              (s['sequence_no'] as num?)?.toInt() ?? 0;
                          final stopType = (s['stop_type'] ?? 'DROPOFF')
                              .toString();
                          final isCompleted =
                              (s['status'] ?? 'PENDING').toString() ==
                              'COMPLETED';
                          final addr = (s['address'] ?? '').toString();
                          final rName = (s['recipient_name'] ?? '').toString();
                          final stopOtp = (s['otp_code'] ?? '').toString();
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                GhstButtonIcon(
                                  isCompleted
                                      ? Icons.check_circle_rounded
                                      : (stopType == 'RETURN'
                                            ? Icons.keyboard_return_rounded
                                            : Icons.location_on_outlined),
                                  size: 18,
                                  color: isCompleted
                                      ? const Color(0xFF14B866)
                                      : AppColors.violet,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Trạm #${seqNo + 1}${stopType == 'RETURN' ? ' (Khứ hồi về điểm lấy)' : ''}: $addr',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          decoration: isCompleted
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      Text(
                                        'Người nhận: ${rName.isEmpty ? ord.recipientName : rName}${stopOtp.isNotEmpty ? ' • OTP trạm: $stopOtp' : ''}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isCompleted && isInTransit)
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                    ),
                                    onPressed: () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      final ok = await _store.completeOrderStop(
                                        orderId: ord.id,
                                        sequenceNo: seqNo,
                                        otpInput: stopOtp.isNotEmpty
                                            ? stopOtp
                                            : null,
                                      );
                                      if (!mounted) return;
                                      if (ok) {
                                        _rebuildDriverUi(() {});
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Đã xác nhận hoàn thành Trạm #${seqNo + 1}!',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    icon: const GhstButtonIcon.glyph(GhstActionKind.checkCircle, size: 16),

                                    label: const Text(
                                      'Xong trạm',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
            ],
            PodGpsWatermarkPhotoCard(
              driverLocation:
                  _store.verifiedDriverLocations[_store.activeDriverId],
              recipientName: _podRecipientCtrl.text,
              otpCode: _podOtpCtrl.text,
              distanceToDropoffMeters: distMeters,
            ),
            if (!isInTransit && !isOrderClosed) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '⚠️ Đơn ${ord.trackingCode} đang ở trạng thái "${ord.status.displayName}". Tài xế cần hoàn tất bước Nhận đơn & Lấy hàng trước khi xác nhận POD.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        _rebuildDriverUi(() => _selectedScreenIndex = 4),
                    icon: const GhstButtonIcon(
                      Icons.playlist_add_check_rounded,
                      size: 16,
                    ),
                    label: const Text('Mở Tiến độ chuyến'),
                  ),
                ],
              ),
            ],
            if (!isWithin100m) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '⚠️ Yêu cầu vị trí: Tài xế phải cách điểm giao <= 100m mới được phép xác nhận hoàn tất POD.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        _rebuildDriverUi(() => _selectedScreenIndex = 4),
                    icon: const GhstButtonIcon(
                      Icons.playlist_add_check_rounded,
                      size: 16,
                    ),
                    label: const Text('Xác nhận đã đến điểm giao'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final recipientField = TextField(
                  controller: _podRecipientCtrl,
                  onChanged: (_) => _rebuildDriverUi(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Tên người thực nhận',
                  ),
                );
                final otpField = TextField(
                  controller: _podOtpCtrl,
                  maxLength: 4,
                  onChanged: (_) => _rebuildDriverUi(() {}),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Mã OTP xác nhận (4 chữ số)',
                    helperText: 'Nhập mã OTP 4 chữ số do người nhận cung cấp',
                    suffixIcon: _podOtpCtrl.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Xóa mã OTP đã nhập',
                            icon: const GhstButtonIcon(Icons.clear_rounded, size: 18),
                            onPressed: () => _rebuildDriverUi(() {
                              _podOtpCtrl.clear();
                            }),
                          )
                        : null,
                  ),
                );
                if (constraints.maxWidth < 520) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      recipientField,
                      const SizedBox(height: 10),
                      otpField,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: recipientField),
                    const SizedBox(width: 10),
                    Expanded(child: otpField),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: canConfirmPod
                      ? const Color(0xFF14B866)
                      : AppColors.textSecondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                onPressed: !canConfirmPod
                    ? null
                    : () async {
                        final recName = _podRecipientCtrl.text.trim();
                        if (recName.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Vui lòng nhập tên người thực nhận trước khi xác nhận POD!',
                              ),
                            ),
                          );
                          return;
                        }
                        final otpInput = _podOtpCtrl.text.trim();
                        if (!RegExp(r'^[0-9]{4}$').hasMatch(otpInput) ||
                            otpInput != expectedOtp4) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Mã OTP 4 chữ số không chính xác. Vui lòng đề nghị người nhận kiểm tra mã OTP trên màn hình Theo dõi đơn hàng!',
                              ),
                            ),
                          );
                          return;
                        }
                        final svgFilePath =
                            await SecurityAndBarcodeUtils.exportPodWatermarkToSvgFile(
                              orderCode: ord.trackingCode,
                              recipientName: recName,
                              otpCode: otpInput,
                              driverLocation: _store.activeDriverLocation,
                              distanceMeters: _store
                                  .distanceFromDriverToDropoffMeters(),
                            );
                        _store.driverAdvanceOrderStatus(
                          ord.trackingCode,
                          podNote:
                              'POD: $recName • OTP $otpInput • GPS (${_store.activeDriverLocation.latitude.toStringAsFixed(4)}, ${_store.activeDriverLocation.longitude.toStringAsFixed(4)}) • Tệp: $svgFilePath',
                        );
                        _podOtpCtrl.clear();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Hoàn tất đơn ${ord.trackingCode}! Đã lưu tệp bằng chứng POD tại: $svgFilePath',
                            ),
                          ),
                        );
                        _rebuildDriverUi(() => _selectedScreenIndex = 6);
                      },
                icon: const GhstButtonIcon(Icons.task_alt),
                label: Text(
                  ord.status == OrderStatus.delivered
                      ? 'ĐƠN HÀNG ĐÃ HOÀN TẤT POD'
                      : ord.status == OrderStatus.cancelled
                      ? 'ĐƠN HÀNG ĐÃ HỦY'
                      : !isInTransit
                      ? 'CHỜ NHẬN HÀNG ĐỂ GIAO'
                      : isWithin100m
                      ? 'XÁC NHẬN GIAO & XUẤT POD'
                      : 'VÀO VÙNG < 100M ĐỂ MỞ POD',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
            if (isInTransit) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger, width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () =>
                      _showDriverMarkDeliveryFailedDialog(context, ord),
                  icon: const GhstButtonIcon(Icons.assignment_late_outlined, size: 18),
                  label: const Text(
                    'Báo giao thất bại (Chờ Shop xử lý Giao lại / Hoàn kho)',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDriverMarkDeliveryFailedDialog(
    BuildContext context,
    ActiveOrderRecord ord,
  ) {
    const failReasons = <String>[
      'Khách không nghe máy / Không liên lạc được',
      'Khách từ chối nhận hàng tại điểm giao',
      'Sai địa chỉ giao hàng / Không tìm thấy người nhận',
      'Khách hẹn giao lại ca sau',
    ];
    String selectedReason = failReasons.first;
    final extraNoteCtrl = TextEditingController();
    Animation<double>? dialogRouteAnim;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        dialogRouteAnim ??= ModalRoute.of(dialogCtx)?.animation;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(
                'Báo giao thất bại (${ord.trackingCode})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Chọn lý do giao thất bại thực tế tại điểm giao:',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), isExpanded: true, initialValue: selectedReason, decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Lý do giao thất bại',
                        ), items: failReasons
                            .map(
                              (r) => DropdownMenuItem(
                                value: r,
                                child: Text(
                                  r,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                            )
                            .toList(), onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => selectedReason = v);
                          }
                        },),
                      const SizedBox(height: 10),
                      TextField(
                        controller: extraNoteCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Ghi chú hiện trường (Tùy chọn)',
                          hintText:
                              'VD: Đã gọi 3 cuộc lúc 14:20 không bắt máy...',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

                  label: const Text('Đóng'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                  ),
                  onPressed: () {
                    final extra = extraNoteCtrl.text.trim();
                    final fullReason = extra.isEmpty
                        ? selectedReason
                        : '$selectedReason ($extra)';
                    final ok = _store.driverMarkDeliveryFailed(
                      ord.trackingCode,
                      fullReason,
                    );
                    Navigator.of(dialogCtx).pop();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: ok
                            ? AppColors.warning
                            : AppColors.danger,
                        content: Text(
                          ok
                              ? 'Đã chuyển đơn ${ord.trackingCode} sang trạng thái Giao thất bại ($selectedReason). Chờ Cửa hàng/Khách yêu cầu Giao lại hoặc Hoàn kho!'
                              : 'Không thể báo giao thất bại ở trạng thái hiện tại.',
                        ),
                      ),
                    );
                  },
                  icon: const GhstButtonIcon.glyph(GhstActionKind.warning, size: 16),

                  label: const Text('Xác nhận Giao thất bại'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      SecurityAndBarcodeUtils.disposeControllersAfterDialog([
        extraNoteCtrl,
      ], dialogRouteAnim);
    });
  }
}
