part of 'merchant_subsystem_views.dart';

extension _MerchantStoreAndOrderViews on _MerchantSubsystemEntryState {
  /// UC30: Đăng ký & xác thực cửa hàng (Khớp 100% uc30_dang_ky_cua_hang.jpg)
  Widget _buildMerchantRegistrationView() {
    final activeMer = _store.activeMerchantRecord;
    final merStatus = activeMer?.approvalStatus ?? 'Chưa gửi hồ sơ';
    final isMerApproved = merStatus == 'Đã duyệt';
    final isMerRejected = merStatus == 'Từ chối';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Đăng ký & xác thực cửa hàng',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Color(0xFF15131E),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMerApproved
                ? const Color(0xFFDCFCE7)
                : isMerRejected
                ? const Color(0xFFFEE2E2)
                : const Color(0xFFFEF3C7),
            border: Border.all(
              color: isMerApproved
                  ? AppColors.success
                  : isMerRejected
                  ? AppColors.danger
                  : const Color(0xFFF59E0B),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isMerApproved
                    ? Icons.verified_rounded
                    : isMerRejected
                    ? Icons.cancel_rounded
                    : Icons.pending_actions_rounded,
                color: isMerApproved
                    ? AppColors.success
                    : isMerRejected
                    ? AppColors.danger
                    : const Color(0xFFB45309),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  activeMer != null
                      ? 'Trạng thái KYC Cửa hàng B2B (${activeMer.id}): $merStatus • MST: ${activeMer.taxCode} • Đã đính kèm ${_attachedMerchantDocs.length}/2 giấy tờ pháp lý'
                      : 'Trạng thái KYC Cửa hàng B2B: $merStatus • Vui lòng điền thông tin và đính kèm giấy tờ pháp lý',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: Color(0xFF15131E),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildMerchantStepDot(
                icon: Icons.storefront_rounded,
                label: 'Thông tin cửa hàng',
                active:
                    _storeNameCtrl.text.trim().isNotEmpty &&
                    _taxCodeCtrl.text.trim().isNotEmpty,
              ),
              _buildMerchantStepConnector(
                active: _attachedMerchantDocs.isNotEmpty,
              ),
              _buildMerchantStepDot(
                icon: Icons.description_outlined,
                label: 'Giấy tờ (${_attachedMerchantDocs.length}/2)',
                active: _attachedMerchantDocs.isNotEmpty,
              ),
              _buildMerchantStepConnector(
                active: _bankAccountCtrl.text.trim().isNotEmpty,
              ),
              _buildMerchantStepDot(
                icon: Icons.account_balance_outlined,
                label: 'Tài khoản ngân hàng',
                active: _bankAccountCtrl.text.trim().isNotEmpty,
              ),
              _buildMerchantStepConnector(
                active: _store.activeMerchantRecord != null,
              ),
              _buildMerchantStepDot(
                icon: _store.activeMerchantRecord?.approvalStatus == 'Đã duyệt'
                    ? Icons.verified_rounded
                    : Icons.access_time_rounded,
                label:
                    _store.activeMerchantRecord?.approvalStatus ?? 'Chờ duyệt',
                active: _store.activeMerchantRecord != null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.zero),
            border: Border.all(color: const Color(0xFF15131E)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final col1 = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Thông tin cơ bản',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _storeNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Tên cửa hàng',
                          hintText: 'Nhập tên cửa hàng của bạn',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _taxCodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Mã số thuế',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _shopPhoneCtrl,
                              decoration: const InputDecoration(
                                labelText: 'SĐT',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _shopEmailCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                  final col2 = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Thông tin liên hệ',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          _businessCategory.trim().isNotEmpty
                              ? _businessCategory.trim()
                              : '',
                        ),
                        isExpanded: true,
                        initialValue: _businessCategory.trim().isNotEmpty
                            ? _businessCategory.trim()
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Loại hình kinh doanh',
                        ),
                        items:
                            <String>{
                                  'Gốm sứ & Nội thất',
                                  'Thời trang & Phụ kiện',
                                  'Thực phẩm & Đồ uống',
                                  'Điện tử & Gia dụng',
                                  'Công ty TNHH',
                                  if (_businessCategory.trim().isNotEmpty)
                                    _businessCategory.trim(),
                                }
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(
                                      e,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            _rebuildMerchantUi(() => _businessCategory = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _repNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Người đại diện',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _shopAddressCtrl,
                        decoration: const InputDecoration(labelText: 'Địa chỉ'),
                      ),
                    ],
                  );
                  if (constraints.maxWidth < 640) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [col1, const SizedBox(height: 16), col2],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: col1),
                      const SizedBox(width: 20),
                      Expanded(child: col2),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              const Text(
                'Giấy tờ & Hình ảnh',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildDashedUploadBox(
                      title: 'Giấy phép kinh doanh',
                      subtitle: 'Kéo thả hoặc bấm để tải lên (Đã đính kèm)',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDashedUploadBox(
                      title: 'Biển hiệu cửa hàng',
                      subtitle: 'Kéo thả hoặc bấm để tải lên (Đã đính kèm)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Thông tin thanh toán',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final trimmedBank = _selectedBankName.trim().isNotEmpty
                      ? _selectedBankName.trim()
                      : '';
                  final bankDrop = BankDirectoryField(
                    initialValue: trimmedBank,
                    label: 'Ngân hàng',
                    onChanged: (v) {
                      _rebuildMerchantUi(() => _selectedBankName = v);
                    },
                  );
                  final accField = TextField(
                    controller: _bankAccountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số tài khoản nhận COD',
                    ),
                  );
                  if (constraints.maxWidth < 640) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        bankDrop,
                        const SizedBox(height: 12),
                        accField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: bankDrop),
                      const SizedBox(width: 16),
                      Expanded(child: accField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5E83),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.zero),
                    ),
                  ),
                  onPressed: () {
                    final sName = _storeNameCtrl.text.trim();
                    final tCode = _taxCodeCtrl.text.trim();
                    final repName = _repNameCtrl.text.trim();
                    final sPhone = _shopPhoneCtrl.text.trim();
                    final bAcc = _bankAccountCtrl.text.trim();
                    if (sName.isEmpty ||
                        tCode.isEmpty ||
                        repName.isEmpty ||
                        sPhone.isEmpty ||
                        bAcc.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Vui lòng điền đầy đủ Tên cửa hàng, Mã số thuế, Người đại diện, SĐT và Số tài khoản!',
                          ),
                        ),
                      );
                      return;
                    }
                    if (_attachedMerchantDocs.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: AppColors.danger,
                          content: Text(
                            'Vui lòng đính kèm ít nhất 1 giấy tờ pháp lý (Giấy phép kinh doanh / Biển hiệu cửa hàng)!',
                          ),
                        ),
                      );
                      return;
                    }
                    _store.updateMerchantProfile(
                      storeName: sName,
                      taxCode: tCode,
                      businessType: _businessCategory,
                      representativeName: repName,
                      phone: sPhone,
                      email: _shopEmailCtrl.text.trim(),
                      bankName: _selectedBankName,
                      bankAccount: bAcc,
                      warehouseAddress: _shopAddressCtrl.text.trim(),
                      attachedDocs: _attachedMerchantDocs.toList(),
                    );
                    final updatedStatus =
                        _store.activeMerchantRecord?.approvalStatus ??
                        'Chờ duyệt';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          updatedStatus == 'Đã duyệt'
                              ? 'Đã cập nhật hồ sơ & tài khoản ngân hàng Cửa hàng B2B thành công!'
                              : 'Đã gửi hồ sơ đăng ký Cửa hàng B2B ($updatedStatus) chờ Admin phê duyệt!',
                        ),
                      ),
                    );
                  },
                  child: Text(
                    isMerApproved ? 'Cập nhật hồ sơ Shop' : 'Gửi hồ sơ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMerchantStepDot({
    required IconData icon,
    required String label,
    required bool active,
  }) {
    final color = active ? const Color(0xFFFF5E83) : const Color(0xFF15131E);
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(
            icon,
            color: active ? Colors.white : const Color(0xFF4A4754),
            size: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? const Color(0xFFFF5E83) : const Color(0xFF4A4754),
          ),
        ),
      ],
    );
  }

  Widget _buildMerchantStepConnector({required bool active}) {
    return Container(
      width: 65,
      height: 2,
      margin: const EdgeInsets.only(bottom: 20, left: 6, right: 6),
      color: active ? const Color(0xFFFF5E83) : const Color(0xFF15131E),
    );
  }

  Widget _buildDashedUploadBox({
    required String title,
    required String subtitle,
  }) {
    final matchedDoc = _attachedMerchantDocs
        .where((d) => d == title || d.startsWith('$title:'))
        .firstOrNull;
    final isAttached = matchedDoc != null;
    final attachedName =
        (matchedDoc != null && matchedDoc.startsWith('$title:'))
        ? matchedDoc.substring(title.length + 1).trim()
        : '';
    return InkWell(
      onTap: () async {
        if (isAttached) {
          _rebuildMerchantUi(() => _attachedMerchantDocs.remove(matchedDoc));
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Đã gỡ đính kèm: $title')));
          return;
        }
        final picked = await SecurityAndBarcodeUtils.pickLocalDocumentOrImage(
          dialogTitle: 'Tải lên hồ sơ pháp lý Cửa hàng: $title',
        );
        if (picked == null || !mounted) return;
        _rebuildMerchantUi(() {
          _attachedMerchantDocs
            ..removeWhere((d) => d == title || d.startsWith('$title:'))
            ..add('$title: $picked');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã đính kèm $title ($picked)!')),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: isAttached ? const Color(0xFFDCFCE7) : const Color(0xFFF5F1E8),
          borderRadius: const BorderRadius.all(Radius.zero),
          border: Border.all(
            color: isAttached ? AppColors.success : const Color(0xFF15131E),
            width: isAttached ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              isAttached ? Icons.check_circle_rounded : Icons.upload_rounded,
              size: 26,
              color: isAttached ? AppColors.success : const Color(0xFF334155),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              isAttached
                  ? (attachedName.isNotEmpty
                        ? 'Đã đính kèm: $attachedName (Bấm để gỡ)'
                        : subtitle)
                  : 'Bấm để chọn tệp tài liệu tải lên',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF4A4754)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreConfigAndWarehousesView() {
    final personalWhs = _store.merchantPersonalWarehouses;
    final safeWhIdx = personalWhs.isEmpty
        ? 0
        : _selectedWarehouseIndex.clamp(0, personalWhs.length - 1);
    final wh = personalWhs.isNotEmpty ? personalWhs[safeWhIdx] : null;
    final activeWhCoord =
        _pinnedWarehouseLocation ??
        wh?.location ??
        SmartDispatchEngine.resolveAddressToCoordinate(
          _shopAddressCtrl.text,
          fallback:
              _store.liveDeviceLocation ??
              const GeoPoint(latitude: 10.7725, longitude: 106.6980),
        );
    final activeWhName = _warehouseNameCtrl.text.trim().isNotEmpty
        ? _warehouseNameCtrl.text.trim()
        : (wh?.name ?? 'Kho lấy hàng');
    final activeWhAddr = _shopAddressCtrl.text.trim().isNotEmpty
        ? _shopAddressCtrl.text.trim()
        : (wh?.address ?? 'Chạm lên bản đồ để chọn địa chỉ kho lấy hàng');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Quản lý Điểm lấy hàng & Cấu hình Kho',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF15131E),
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final col1 = Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Danh sách Điểm lấy hàng',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  if (personalWhs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Chưa có điểm lấy hàng nào. Nhấn "Thêm điểm lấy hàng mới" để khởi tạo kho.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF4A4754),
                        ),
                      ),
                    ),
                  ...personalWhs.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final w = entry.value;
                    final isSelected = idx == safeWhIdx;
                    return InkWell(
                      onTap: () {
                        _rebuildMerchantUi(() {
                          _selectedWarehouseIndex = idx;
                          _warehouseNameCtrl.text = w.name;
                          _warehouseIsPrimary = w.isPrimary;
                          _warehousePhoneCtrl.text = w.contactPhone.isNotEmpty
                              ? w.contactPhone
                              : _shopPhoneCtrl.text;
                          _warehouseOpenHoursCtrl.text = w.openHours.isNotEmpty
                              ? w.openHours
                              : '08:00 - 21:00';
                          _shopAddressCtrl.text = w.address;
                          _pinnedWarehouseLocation = null;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFF5F1E8)
                              : Colors.white,
                          borderRadius: const BorderRadius.all(Radius.zero),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFFF5E83)
                                : const Color(0xFF15131E),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    w.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                if (w.isPrimary) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFF5E83),
                                      borderRadius: BorderRadius.all(
                                        Radius.zero,
                                      ),
                                    ),
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
                                if (personalWhs.length > 1)
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Xóa kho lấy hàng này',
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: AppColors.danger,
                                    ),
                                    onPressed: () {
                                      final removed = _store
                                          .deleteMerchantWarehouse(w.id);
                                      if (removed) {
                                        _rebuildMerchantUi(() {
                                          _selectedWarehouseIndex = 0;
                                          _pinnedWarehouseLocation = null;
                                          final updatedWhs =
                                              _store.merchantPersonalWarehouses;
                                          if (updatedWhs.isNotEmpty) {
                                            final firstWh = updatedWhs.first;
                                            _warehouseNameCtrl.text =
                                                firstWh.name;
                                            _warehouseIsPrimary =
                                                firstWh.isPrimary;
                                            _shopAddressCtrl.text =
                                                firstWh.address;
                                          }
                                        });
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Đã xóa điểm lấy hàng ${w.name} (${w.id}).',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              w.address,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF4A4754),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'GPS: ${w.location.latitude.toStringAsFixed(4)}, ${w.location.longitude.toStringAsFixed(4)} • ${w.contactPhone.isNotEmpty ? "${w.contactPhone} • " : ""}${w.openHours}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF4A4754),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5E83),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _showAddMerchantWarehouseDialog(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Thêm điểm lấy hàng mới'),
                  ),
                ],
              ),
            );
            final col2 = Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Cập nhật Điểm lấy hàng',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _warehouseNameCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Tên điểm lấy hàng / Kho nhánh',
                      ),
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, whConstraints) {
                        final contactField = TextField(
                          controller: _warehouseContactCtrl,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Người liên hệ tại kho',
                          ),
                        );
                        final phoneField = TextField(
                          controller: _warehousePhoneCtrl,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'SĐT kho lấy hàng',
                          ),
                        );
                        final addrField = TextField(
                          controller: _shopAddressCtrl,
                          onChanged: (_) => _rebuildMerchantUi(() {
                            _pinnedWarehouseLocation = null;
                          }),
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Địa chỉ kho chi tiết',
                          ),
                        );
                        final hoursField = TextField(
                          controller: _warehouseOpenHoursCtrl,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Giờ mở cửa',
                          ),
                        );
                        if (whConstraints.maxWidth < 520) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              contactField,
                              const SizedBox(height: 10),
                              phoneField,
                              const SizedBox(height: 10),
                              addrField,
                              const SizedBox(height: 10),
                              hoursField,
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: contactField),
                                const SizedBox(width: 10),
                                Expanded(child: phoneField),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(flex: 2, child: addrField),
                                const SizedBox(width: 10),
                                Expanded(child: hoursField),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _warehouseIsPrimary,
                      title: const Text(
                        'Đặt làm kho lấy hàng mặc định',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onChanged: (v) {
                        if (v != null) {
                          _rebuildMerchantUi(() => _warehouseIsPrimary = v);
                        }
                      },
                    ),
                    const SizedBox(height: 6),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5E83),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () {
                        if (_warehouseNameCtrl.text.trim().isEmpty ||
                            _shopAddressCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Vui lòng nhập Tên điểm lấy hàng và Địa chỉ chi tiết!',
                              ),
                            ),
                          );
                          return;
                        }
                        if (wh != null) {
                          _store.updateMerchantWarehouseDetails(
                            warehouseId: wh.id,
                            name: _warehouseNameCtrl.text.trim(),
                            address: _shopAddressCtrl.text.trim(),
                            setPrimary: _warehouseIsPrimary,
                            contactName: _warehouseContactCtrl.text.trim(),
                            contactPhone: _warehousePhoneCtrl.text.trim(),
                            openHours: _warehouseOpenHoursCtrl.text.trim(),
                            customLocation: _pinnedWarehouseLocation,
                          );
                        } else {
                          _store.addMerchantWarehouse(
                            name: _warehouseNameCtrl.text.trim(),
                            address: _shopAddressCtrl.text.trim(),
                            contactName: _warehouseContactCtrl.text.trim(),
                            contactPhone: _warehousePhoneCtrl.text.trim(),
                            openHours: _warehouseOpenHoursCtrl.text.trim(),
                            isPrimary: _warehouseIsPrimary,
                            customLocation: _pinnedWarehouseLocation,
                          );
                        }
                        _rebuildMerchantUi(() {
                          _pinnedWarehouseLocation = null;
                        });
                        _parseCsvBatch();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Đã lưu cấu hình điểm lấy hàng "${_warehouseNameCtrl.text.trim()}"!',
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        'Lưu thay đổi',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const Divider(height: 24),
                    const Text(
                      'Webhook API trạng thái vận đơn (HMAC-SHA256)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _webhookUrlCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Endpoint nhận sự kiện (HTTPS POST)',
                        hintText: 'https://erp.shop.vn/webhooks/gomau',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _isTestingWebhook
                          ? null
                          : () async {
                              _rebuildMerchantUi(
                                () => _isTestingWebhook = true,
                              );
                              final msg = await _store
                                  .saveAndTestMerchantWebhook(
                                    webhookUrl: _webhookUrlCtrl.text,
                                  );
                              if (!context.mounted) return;
                              _rebuildMerchantUi(
                                () => _isTestingWebhook = false,
                              );
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text(msg)));
                            },
                      icon: const Icon(Icons.webhook_rounded, size: 16),
                      label: Text(
                        _isTestingWebhook
                            ? 'Đang gửi gói tin chữ ký số...'
                            : 'Lưu & Test Webhook',
                      ),
                    ),
                  ],
                ),
              ),
            );
            final mapCard = Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      const Text(
                        'Bản đồ Tọa độ Kho lấy hàng (Chạm lên bản đồ để ghim vị trí mới)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                            ),
                            onPressed: () async {
                              _rebuildMerchantUi(() {
                                _isReverseGeocodingWarehouse = true;
                              });
                              final pos = await _store
                                  .acquireCustomerDeviceGps();
                              if (!mounted || !context.mounted) return;
                              if (pos == null) {
                                _rebuildMerchantUi(() {
                                  _isReverseGeocodingWarehouse = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppColors.danger,
                                    content: Text(_store.liveGpsStatusMessage),
                                    action: SnackBarAction(
                                      label: 'Mở Cài đặt',
                                      textColor: AppColors.acid,
                                      onPressed: () {
                                        unawaited(
                                          _store.openDeviceLocationSettings(),
                                        );
                                      },
                                    ),
                                  ),
                                );
                                return;
                              }
                              final addr =
                                  _store.liveDeviceAddress.trim().isNotEmpty
                                  ? _store.liveDeviceAddress.trim()
                                  : await SmartDispatchEngine.reverseGeocodeCoordinate(
                                      pos,
                                    );
                              if (!mounted) return;
                              _rebuildMerchantUi(() {
                                _pinnedWarehouseLocation = pos;
                                _shopAddressCtrl.text = addr;
                                _isReverseGeocodingWarehouse = false;
                              });
                            },
                            icon: const Icon(
                              Icons.my_location_rounded,
                              size: 14,
                            ),
                            label: const Text(
                              'Lấy GPS hiện tại cho Kho',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            _isReverseGeocodingWarehouse
                                ? 'Đang giải mã địa chỉ GPS...'
                                : (_pinnedWarehouseLocation != null ||
                                          wh != null
                                      ? 'Vĩ độ: ${activeWhCoord.latitude.toStringAsFixed(6)} | Kinh độ: ${activeWhCoord.longitude.toStringAsFixed(6)}'
                                      : 'Chưa chọn vị trí kho'),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF4A4754),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(Radius.zero),
                      border: Border.all(color: const Color(0xFF15131E)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Map3dPerspectiveWidget(
                      height: 430,
                      mode: MapViewMode.customerPreview,
                      is3dMode: _store.isMap3dEnabled,
                      speedKmh: 0,
                      onToggle3d: _store.toggleMap3d,
                      routePoints: const [],
                      singlePinPoint:
                          _pinnedWarehouseLocation != null || wh != null
                          ? activeWhCoord
                          : null,
                      singlePinLabel: '📍 $activeWhName',
                      nextTurnInstruction: 'Vị trí Kho lấy hàng: $activeWhName',
                      roadName: activeWhAddr,
                      onTapGeoPoint: (pt) async {
                        _rebuildMerchantUi(() {
                          _pinnedWarehouseLocation = pt;
                          _isReverseGeocodingWarehouse = true;
                        });
                        final addr =
                            await SmartDispatchEngine.reverseGeocodeCoordinate(
                              pt,
                            );
                        if (!mounted) return;
                        _rebuildMerchantUi(() {
                          _shopAddressCtrl.text = addr;
                          _isReverseGeocodingWarehouse = false;
                        });
                      },
                    ),
                  ),
                ],
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (constraints.maxWidth < 860) ...[
                  col1,
                  const SizedBox(height: 16),
                  col2,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 4, child: col1),
                      const SizedBox(width: 16),
                      Expanded(flex: 6, child: col2),
                    ],
                  ),
                const SizedBox(height: 16),
                mapCard,
              ],
            );
          },
        ),
      ],
    );
  }

  void _showAddMerchantWarehouseDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final addrCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(text: _shopPhoneCtrl.text.trim());
    final openHoursCtrl = TextEditingController(text: '08:00 - 21:00');
    bool setPrimary = _store.merchantPersonalWarehouses.isEmpty;
    Animation<double>? dialogRouteAnim;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        dialogRouteAnim ??= ModalRoute.of(dialogCtx)?.animation;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Thêm Điểm lấy hàng / Kho nhánh mới',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên điểm lấy hàng',
                        hintText: 'VD: Kho Quận 3 / Cửa hàng chi nhánh 2',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: addrCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Địa chỉ kho chi tiết',
                        hintText: 'Nhập số nhà, tên đường, phường/quận, TP',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'SĐT liên hệ tại kho',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: openHoursCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Khung giờ mở cửa',
                        hintText: '08:00 - 21:00',
                      ),
                    ),
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: setPrimary,
                      title: const Text(
                        'Đặt làm kho lấy hàng mặc định',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => setPrimary = v);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5E83),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final wName = nameCtrl.text.trim();
                    final wAddr = addrCtrl.text.trim();
                    if (wName.isEmpty || wAddr.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Vui lòng nhập đầy đủ Tên kho và Địa chỉ chi tiết!',
                          ),
                        ),
                      );
                      return;
                    }
                    final created = _store.addMerchantWarehouse(
                      name: wName,
                      address: wAddr,
                      contactPhone: phoneCtrl.text.trim(),
                      openHours: openHoursCtrl.text.trim().isNotEmpty
                          ? openHoursCtrl.text.trim()
                          : '08:00 - 21:00',
                      isPrimary: setPrimary,
                    );
                    Navigator.of(dialogCtx).pop();
                    final updatedList = _store.merchantPersonalWarehouses;
                    final newIdx = updatedList.indexWhere(
                      (x) => x.id == created.id,
                    );
                    _rebuildMerchantUi(() {
                      if (newIdx >= 0) {
                        _selectedWarehouseIndex = newIdx;
                      }
                      _warehouseNameCtrl.text = created.name;
                      _shopAddressCtrl.text = created.address;
                      _warehousePhoneCtrl.text = created.contactPhone;
                      _warehouseOpenHoursCtrl.text = created.openHours;
                      _warehouseIsPrimary = created.isPrimary;
                      _pinnedWarehouseLocation = null;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã thêm điểm lấy hàng "${created.name}" (${created.id}) thành công!',
                        ),
                      ),
                    );
                  },
                  child: const Text('Lưu điểm lấy hàng'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      SecurityAndBarcodeUtils.disposeControllersAfterDialog([
        nameCtrl,
        addrCtrl,
        phoneCtrl,
        openHoursCtrl,
      ], dialogRouteAnim);
    });
  }

  Widget _buildSingleOrderCreateView() {
    final personalWhs = _store.merchantPersonalWarehouses;
    final safeWhSelectIdx = personalWhs.isEmpty
        ? 0
        : _selectedWarehouseIndex.clamp(0, personalWhs.length - 1);
    final selectedWhObj = personalWhs.isNotEmpty
        ? personalWhs[safeWhSelectIdx]
        : null;
    final String? activeWarehouseId = selectedWhObj?.id;
    final String? activeWarehouseLabel = selectedWhObj != null
        ? '${selectedWhObj.name} - ${selectedWhObj.address}'
        : null;
    final pickupAddr =
        selectedWhObj?.address ??
        (personalWhs.isNotEmpty
            ? personalWhs.first.address
            : _shopAddressCtrl.text);
    final pCoord =
        selectedWhObj?.location ??
        SmartDispatchEngine.resolveAddressToCoordinate(
          pickupAddr,
          fallback: const GeoPoint(latitude: 10.7725, longitude: 106.6980),
        );
    final hasDropoffInput =
        _pinnedSingleDropoffLocation != null ||
        _singleAddrCtrl.text.trim().isNotEmpty;
    final dCoord =
        _pinnedSingleDropoffLocation ??
        (hasDropoffInput
            ? SmartDispatchEngine.resolveAddressToCoordinate(
                _singleAddrCtrl.text,
                fallback: const GeoPoint(
                  latitude: 10.7850,
                  longitude: 106.6880,
                ),
              )
            : null);
    final rawAirMeters = dCoord != null
        ? GeoMath.distanceMeters(pCoord, dCoord)
        : 0.0;
    final distMeters = dCoord != null
        ? (rawAirMeters * 1.28).round().clamp(1500, 45000)
        : 0;
    final durationSec = dCoord != null
        ? ((distMeters / 1000.0) * 180).round()
        : 0;
    final distKm = distMeters / 1000.0;
    final etaMins = dCoord == null
        ? 0
        : _merchantServiceType == DeliveryServiceType.express30m
        ? (15 + (distKm * 3.5).round())
        : _merchantServiceType == DeliveryServiceType.standard
        ? (30 + (distKm * 4.5).round())
        : _merchantServiceType == DeliveryServiceType.truck
        ? (40 + (distKm * 5.0).round())
        : (45 + (distKm * 6.0).round());
    final weightVal = double.tryParse(_singleWeightCtrl.text) ?? 1.0;
    double geofenceFee = dCoord != null
        ? _store.computeGeofenceSurchargeForPoint(dCoord)
        : 0.0;
    if (_store.isWeatherSurchargeActive) {
      geofenceFee += _store.badWeatherSurchargeConfig;
    }
    if (weightVal > 5.0) {
      geofenceFee += ((weightVal - 5.0) * 3000).roundToDouble();
    }
    if (_isFragile) {
      geofenceFee += 5000;
    }
    if (_isKeepCold) {
      geofenceFee += 10000;
    }
    final cleanDeclaredPreview = _singleDeclaredValueCtrl.text
        .trim()
        .replaceAll('.', '')
        .replaceAll(',', '');
    final rawDeclaredVal = double.tryParse(cleanDeclaredPreview) ?? 0.0;
    final merchantDeclaredVal = rawDeclaredVal.isFinite && rawDeclaredVal > 0
        ? rawDeclaredVal.clamp(0.0, PricingEstimate.maxInsuredDeclaredValueVnd)
        : 0.0;
    final merchantEst = PricingEstimate.calculate(
      serviceType: _merchantServiceType,
      distanceMeters: distMeters,
      durationSeconds: durationSec,
      isPeakHour: _store.isPeakSurchargeActive,
      geofenceSurcharge: geofenceFee,
      voucherDiscount: 0,
      baseFareScale: (_store.baseFareConfig / 25000.0).clamp(0.4, 5.0),
      pricePerKmScale: (_store.pricePerKmConfig / 5000.0).clamp(0.4, 5.0),
      configuredStandardPeakSurcharge: _store.peakHourSurchargeConfig,
      declaredValueVnd: merchantDeclaredVal,
      isRoundTrip: _merchantIsRoundTrip,
      preferEcoEv: _merchantPreferEcoEv,
    );
    final cleanCodPreview = _singleCodCtrl.text
        .trim()
        .replaceAll('.', '')
        .replaceAll(',', '');
    final codVal = double.tryParse(cleanCodPreview) ?? 0.0;
    final totalEstimated = dCoord != null ? merchantEst.totalAmount : 0.0;
    final previewMerchantRoute = dCoord == null
        ? const <GeoPoint>[]
        : (_singleLiveOsrmPolyline != null &&
                  _singleLiveOsrmPolyline!.length >= 2
              ? _singleLiveOsrmPolyline!
              : SmartDispatchEngine.generateRoutePolyline(
                  pCoord,
                  dCoord,
                  segments: 10,
                ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tạo đơn gửi hàng',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF15131E),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Tạo Đơn Giao hàng Lẻ B2B',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF4A4754)),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, innerConstraints) {
            final twoCol = innerConstraints.maxWidth >= 680;
            final leftFormCard = Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Điểm lấy hàng',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        '${personalWhs.length}_${activeWarehouseId ?? "NONE"}',
                      ),
                      isExpanded: true,
                      initialValue: activeWarehouseId,
                      decoration: const InputDecoration(
                        hintText: 'Chọn điểm lấy hàng',
                      ),
                      items: personalWhs
                          .map(
                            (w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(
                                '${w.name} - ${w.address}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (whId) {
                        if (whId != null) {
                          final idx = personalWhs.indexWhere(
                            (w) => w.id == whId,
                          );
                          _rebuildMerchantUi(() {
                            if (idx >= 0 && idx < personalWhs.length) {
                              _selectedWarehouseIndex = idx;
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Thông tin người nhận',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, formConstraints) {
                        final isNarrowForm = formConstraints.maxWidth < 520;
                        final nameField = TextField(
                          controller: _singleNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Tên người nhận',
                          ),
                        );
                        final phoneField = TextField(
                          controller: _singlePhoneCtrl,
                          decoration: const InputDecoration(labelText: 'SĐT'),
                        );
                        final addrField = TextField(
                          controller: _singleAddrCtrl,
                          onChanged: (_) => _rebuildMerchantUi(() {
                            _pinnedSingleDropoffLocation = null;
                            _singleLiveOsrmPolyline = null;
                          }),
                          decoration: const InputDecoration(
                            labelText:
                                'Địa chỉ giao (Hoặc chạm lên bản đồ bên cạnh)',
                            suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                        );
                        final scanner = ShippingLabelScanner(
                          onApply: (fields) => _rebuildMerchantUi(() {
                            if (fields['recipientName']!.isNotEmpty) {
                              _singleNameCtrl.text = fields['recipientName']!;
                            }
                            if (fields['recipientPhone']!.isNotEmpty) {
                              _singlePhoneCtrl.text = fields['recipientPhone']!;
                            }
                            if (fields['dropoffAddress']!.isNotEmpty) {
                              _singleAddrCtrl.text = fields['dropoffAddress']!;
                              _pinnedSingleDropoffLocation = null;
                              _singleLiveOsrmPolyline = null;
                            }
                          }),
                        );
                        final photon = PhotonAddressLookup(
                          controller: _singleAddrCtrl,
                          onSelected: (place) => _rebuildMerchantUi(() {
                            _singleAddrCtrl.text = place.address;
                            _pinnedSingleDropoffLocation = place.point;
                            _singleLiveOsrmPolyline = null;
                          }),
                        );
                        if (isNarrowForm) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              nameField,
                              const SizedBox(height: 10),
                              phoneField,
                              const SizedBox(height: 10),
                              addrField,
                              const SizedBox(height: 8),
                              photon,
                              scanner,
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: nameField),
                                const SizedBox(width: 12),
                                Expanded(child: phoneField),
                              ],
                            ),
                            const SizedBox(height: 12),
                            addrField,
                            photon,
                            scanner,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...SmartDispatchEngine.searchAddressSuggestions(
                              _singleAddrCtrl.text,
                            )
                            .take(3)
                            .map(
                              (place) => ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  place.title,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () => _rebuildMerchantUi(() {
                                  _singleAddrCtrl.text = place.fullAddress;
                                  _pinnedSingleDropoffLocation = place.location;
                                  _singleLiveOsrmPolyline = null;
                                }),
                              ),
                            ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Thông tin kiện hàng',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, pkgConstraints) {
                        final isNarrowPkg = pkgConstraints.maxWidth < 520;
                        final catField = DropdownButtonFormField<String>(
                          key: ValueKey(_singlePkgCategory),
                          isExpanded: true,
                          initialValue: _singlePkgCategory,
                          decoration: const InputDecoration(
                            labelText: 'Loại hàng',
                          ),
                          items:
                              const [
                                    'Quần áo, Điện tử',
                                    'Gốm sứ & Đồ dễ vỡ',
                                    'Thực phẩm khô',
                                    'Tài liệu / Hợp đồng',
                                  ]
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(
                                        c,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              _rebuildMerchantUi(() => _singlePkgCategory = v);
                            }
                          },
                        );
                        final weightField = TextField(
                          controller: _singleWeightCtrl,
                          onChanged: (_) => _rebuildMerchantUi(() {}),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Trọng lượng (kg)',
                          ),
                        );
                        final dimField = TextField(
                          controller: _singleDimCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Kích thước (cm) (D x R x C)',
                          ),
                        );
                        final codField = TextField(
                          controller: _singleCodCtrl,
                          onChanged: (_) => _rebuildMerchantUi(() {}),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Tiền thu hộ COD',
                            suffixText: 'VND',
                          ),
                        );
                        if (isNarrowPkg) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              catField,
                              const SizedBox(height: 10),
                              weightField,
                              const SizedBox(height: 10),
                              dimField,
                              const SizedBox(height: 10),
                              codField,
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: catField),
                                const SizedBox(width: 12),
                                Expanded(child: weightField),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: dimField),
                                const SizedBox(width: 12),
                                Expanded(child: codField),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _singleDeclaredValueCtrl,
                      onChanged: (_) => _rebuildMerchantUi(() {}),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Khai giá bảo hiểm B2B (VNĐ - tùy chọn)',
                        suffixText: 'VND',
                        helperText: merchantDeclaredVal > 0
                            ? 'Phí bảo hiểm 0.5%: ${CurrencyFormatter.formatVnd(PricingEstimate.calculateInsuranceFee(merchantDeclaredVal))}'
                            : 'Đền bù tối đa 30tr VNĐ • Lọc Tài xế chuẩn >= 4.5★',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _singleNoteCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú cho tài xế',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        FilterChip(
                          label: const Text('Hàng dễ vỡ'),
                          selected: _isFragile,
                          onSelected: (v) =>
                              _rebuildMerchantUi(() => _isFragile = v),
                        ),
                        FilterChip(
                          label: const Text('Giữ lạnh'),
                          selected: _isKeepCold,
                          onSelected: (v) =>
                              _rebuildMerchantUi(() => _isKeepCold = v),
                        ),
                        FilterChip(
                          avatar: const Icon(
                            Icons.electric_moped_rounded,
                            size: 15,
                            color: AppColors.success,
                          ),
                          label: const Text('Xe điện Xanh (Eco EV)'),
                          selected: _merchantPreferEcoEv,
                          onSelected: (v) =>
                              _rebuildMerchantUi(() => _merchantPreferEcoEv = v),
                        ),
                        FilterChip(
                          avatar: const Icon(
                            Icons.swap_horiz_rounded,
                            size: 15,
                            color: Color(0xFF5B33E6),
                          ),
                          label: const Text('Giao 2 chiều (Khứ hồi)'),
                          selected: _merchantIsRoundTrip,
                          onSelected: (v) =>
                              _rebuildMerchantUi(() => _merchantIsRoundTrip = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Người trả phí vận chuyển',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    RadioGroup<String>(
                      groupValue: _feePayer,
                      onChanged: (v) {
                        if (v != null) _rebuildMerchantUi(() => _feePayer = v);
                      },
                      child: const Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: 'Người gửi trả phí',
                              title: Text(
                                'Người gửi trả phí',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: 'Người nhận trả phí',
                              title: Text(
                                'Người nhận trả phí',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Loại dịch vụ',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    RadioGroup<DeliveryServiceType>(
                      groupValue: _merchantServiceType,
                      onChanged: (v) {
                        if (v != null) {
                          _rebuildMerchantUi(() => _merchantServiceType = v);
                        }
                      },
                      child: const Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: RadioListTile<DeliveryServiceType>(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  value: DeliveryServiceType.express30m,
                                  title: Text(
                                    'Giao nhanh',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: RadioListTile<DeliveryServiceType>(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  value: DeliveryServiceType.standard,
                                  title: Text(
                                    'Tiêu chuẩn',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: RadioListTile<DeliveryServiceType>(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  value: DeliveryServiceType.saving,
                                  title: Text(
                                    'Tiết kiệm',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: RadioListTile<DeliveryServiceType>(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  value: DeliveryServiceType.truck,
                                  title: Text(
                                    'Xe tải / Lớn',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          RadioListTile<DeliveryServiceType>(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: DeliveryServiceType.sameDay2h,
                            title: Text(
                              'Giao nhanh 2H (Ghép đơn cùng hướng - Tiết kiệm B2B)',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );

            final rightSummaryCol = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.all(Radius.zero),
                    border: Border.all(color: const Color(0xFF15131E)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Map3dPerspectiveWidget(
                    height: 420,
                    mode: MapViewMode.customerPreview,
                    is3dMode: _store.isMap3dEnabled,
                    speedKmh: 0,
                    onToggle3d: _store.toggleMap3d,
                    routePoints: previewMerchantRoute,
                    singlePinPoint:
                        dCoord == null && pickupAddr.trim().isNotEmpty
                        ? pCoord
                        : null,
                    singlePinLabel: dCoord == null
                        ? '[A] ${selectedWhObj?.name ?? "Kho lấy hàng"}'
                        : null,
                    pickupLabel: '[A] ${selectedWhObj?.name ?? "Kho Shop"}',
                    dropoffLabel: '[B] Điểm giao',
                    nextTurnInstruction: _isReverseGeocodingSingleDropoff
                        ? 'Đang giải mã địa chỉ giao & tính lộ trình OSRM...'
                        : (dCoord == null
                              ? 'Chạm trực tiếp lên bản đồ để chọn điểm giao hàng [B]'
                              : 'Lộ trình Kho → Điểm giao (${distKm.toStringAsFixed(1)} km)'),
                    roadName: activeWarehouseLabel ?? pickupAddr,
                    onTapGeoPoint: (pt) async {
                      _rebuildMerchantUi(() {
                        _pinnedSingleDropoffLocation = pt;
                        _isReverseGeocodingSingleDropoff = true;
                      });
                      final addrFuture =
                          SmartDispatchEngine.reverseGeocodeCoordinate(pt);
                      final routeFuture =
                          SmartDispatchEngine.fetchLiveOsrmRoute(pCoord, pt);
                      final addr = await addrFuture;
                      final routeRes = await routeFuture;
                      if (!mounted) return;
                      _rebuildMerchantUi(() {
                        _singleAddrCtrl.text = addr;
                        _singleLiveOsrmPolyline = routeRes.polylinePoints;
                        _isReverseGeocodingSingleDropoff = false;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: const Color(0xFF15131E)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Phí ước tính',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _merchantEstimateRow(
                        'Khoảng cách',
                        '${distKm.toStringAsFixed(1)} km',
                      ),
                      const SizedBox(height: 8),
                      _merchantEstimateRow(
                        'Thời gian dự kiến',
                        '$etaMins phút',
                      ),
                      const SizedBox(height: 8),
                      _merchantEstimateRow(
                        'Phí vận chuyển',
                        CurrencyFormatter.formatVnd(totalEstimated),
                      ),
                      if (dCoord != null && merchantEst.insuranceFee > 0) ...[
                        const SizedBox(height: 8),
                        _merchantEstimateRow(
                          'Trong đó Phí bảo hiểm (0.5%)',
                          CurrencyFormatter.formatVnd(merchantEst.insuranceFee),
                        ),
                      ],
                      if (dCoord != null &&
                          _merchantPreferEcoEv &&
                          merchantEst.estimatedCo2SavedGrams > 0) ...[
                        const SizedBox(height: 8),
                        _merchantEstimateRow(
                          'Giảm phát thải Eco EV',
                          '-${merchantEst.estimatedCo2SavedGrams.toStringAsFixed(0)}g CO₂',
                        ),
                      ],
                      const SizedBox(height: 8),
                      _merchantEstimateRow(
                        'Tiền thu hộ COD',
                        CurrencyFormatter.formatVnd(codVal),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _feePayer == 'Người nhận trả phí'
                                  ? 'Tổng thu người nhận (Cước + COD)'
                                  : 'Tổng cước vận chuyển',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            CurrencyFormatter.formatVnd(
                              _feePayer == 'Người nhận trả phí'
                                  ? totalEstimated + codVal
                                  : totalEstimated,
                            ),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF15131E),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5E83),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.zero),
                      ),
                    ),
                    onPressed: () {
                      final activeMer = _store.activeMerchantRecord;
                      if (activeMer == null ||
                          activeMer.approvalStatus != 'Đã duyệt') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.danger,
                            content: Text(
                              activeMer == null
                                  ? 'Vui lòng gửi hồ sơ pháp lý Cửa hàng B2B và chờ Admin duyệt trước khi tạo đơn!'
                                  : 'Hồ sơ cửa hàng B2B đang ở trạng thái "${activeMer.approvalStatus}". Vui lòng chờ Admin duyệt KYC trước khi tạo đơn!',
                            ),
                          ),
                        );
                        _rebuildMerchantUi(() => _selectedScreenIndex = 0);
                        return;
                      }
                      final rName = _singleNameCtrl.text.trim();
                      final rPhone = _singlePhoneCtrl.text.trim().replaceAll(
                        ' ',
                        '',
                      );
                      final rAddr = _singleAddrCtrl.text.trim();
                      if (rName.isEmpty || rPhone.isEmpty || rAddr.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Vui lòng nhập đầy đủ Tên, SĐT và Địa chỉ người nhận!',
                            ),
                          ),
                        );
                        return;
                      }
                      if (pickupAddr.trim().toLowerCase() ==
                          rAddr.trim().toLowerCase()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: AppColors.danger,
                            content: Text(
                              'Địa chỉ giao hàng không được trùng với địa chỉ kho lấy hàng!',
                            ),
                          ),
                        );
                        return;
                      }
                      final targetDropoffCoord =
                          dCoord ??
                          SmartDispatchEngine.resolveAddressToCoordinate(
                            rAddr,
                            fallback: const GeoPoint(
                              latitude: 10.7725,
                              longitude: 106.6980,
                            ),
                          );
                      final restrictedZone = _store
                          .findActiveRestrictedZoneForRoute(
                            pCoord,
                            targetDropoffCoord,
                          );
                      if (restrictedZone != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.danger,
                            content: Text(
                              'Không thể tạo đơn: Lộ trình đi qua khu vực hạn chế giao nhận (${restrictedZone.zoneName})!',
                            ),
                          ),
                        );
                        return;
                      }
                      if (!RegExp(r'^(?:\+84|0)[0-9]{9}$').hasMatch(rPhone)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Số điện thoại người nhận không hợp lệ (gồm 10 chữ số)!',
                            ),
                          ),
                        );
                        return;
                      }
                      final parsedWeight = double.tryParse(
                        _singleWeightCtrl.text.trim(),
                      );
                      if (parsedWeight == null ||
                          parsedWeight <= 0 ||
                          parsedWeight > 500) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: AppColors.danger,
                            content: Text(
                              'Khối lượng kiện hàng phải lớn hơn 0 và tối đa 500 kg!',
                            ),
                          ),
                        );
                        return;
                      }
                      final cleanCodText = _singleCodCtrl.text
                          .trim()
                          .replaceAll('.', '')
                          .replaceAll(',', '');
                      final parsedCod = double.tryParse(
                        cleanCodText.isEmpty ? '0' : cleanCodText,
                      );
                      if (parsedCod == null || parsedCod < 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.danger,
                            content: Text(
                              parsedCod == null
                                  ? 'Số tiền thu hộ COD không hợp lệ (chỉ nhập chữ số)!'
                                  : 'Số tiền thu hộ COD không được là số âm!',
                            ),
                          ),
                        );
                        return;
                      }
                      final tags = <String>[
                        _isFragile ? 'Dễ vỡ' : 'Tiêu chuẩn',
                        if (_isKeepCold) 'Giữ lạnh',
                      ];
                      final noteStr = _singleNoteCtrl.text.trim();
                      final pkgDesc = noteStr.isNotEmpty
                          ? '$_singlePkgCategory (${tags.join(", ")}) • Ghi chú: $noteStr'
                          : '$_singlePkgCategory (${tags.join(", ")})';
                      final ord = _store.createNewOrder(
                        pickupAddress: pickupAddr,
                        dropoffAddress: rAddr,
                        recipientName: rName,
                        recipientPhone: rPhone,
                        packageDescription: pkgDesc,
                        weightKg: weightVal,
                        dimensionsCm: _singleDimCtrl.text.trim(),
                        serviceType: _merchantServiceType,
                        codAmount: codVal,
                        paymentMethod: _feePayer,
                        customDistanceMeters: distMeters > 0
                            ? distMeters
                            : null,
                        customDurationSeconds: durationSec > 0
                            ? durationSec
                            : null,
                        isFragileTag: _isFragile,
                        isKeepColdTag: _isKeepCold,
                        customCustomerName:
                            _store.activeMerchantRecord?.storeName ??
                            _store.merchantStoreName,
                        customPickupLocation: pCoord,
                        customDropoffLocation: targetDropoffCoord,
                        preferEcoEv: _merchantPreferEcoEv,
                        declaredValueVnd: merchantDeclaredVal,
                        isRoundTrip: _merchantIsRoundTrip,
                      );
                      _rebuildMerchantUi(() {
                        _singleNameCtrl.clear();
                        _singlePhoneCtrl.clear();
                        _singleAddrCtrl.clear();
                        _singleNoteCtrl.clear();
                        _singleCodCtrl.text = '0';
                        _pinnedSingleDropoffLocation = null;
                        _singleLiveOsrmPolyline = null;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã tạo vận đơn B2B ${ord.trackingCode} thành công!',
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'Tạo đơn',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            );

            if (twoCol) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: leftFormCard),
                  const SizedBox(width: 20),
                  Expanded(flex: 4, child: rightSummaryCol),
                ],
              );
            }
            return Column(
              children: [
                leftFormCard,
                const SizedBox(height: 16),
                rightSummaryCol,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _merchantEstimateRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF4A4754), fontSize: 13.5),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: Color(0xFF15131E),
            ),
          ),
        ),
      ],
    );
  }

  /// UC33: Tạo đơn hàng loạt từ Excel/CSV & Kiểm lỗi tự động (Chuẩn uc33_don_hang_loat_v2)
  Widget _buildBatchCsvUploadAndValidationView() {
    final personalWhs = _store.merchantPersonalWarehouses;
    final validCount = _parsedRows.where((r) => r.isValid).length;
    final errorCount = _parsedRows.length - validCount;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.zero),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFFF5E83),
              borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
            ),
            child: const Text(
              'Tạo đơn hàng loạt (Excel / CSV)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5B33E6),
                      ),
                      onPressed: () {
                        final path = _store.exportReportFileToDisk(
                          fileName: 'Mau_Tao_Don_7_Cot.csv',
                          content: 'ten_nguoi_nhan,sdt_nguoi_nhan,dia_chi_giao,mo_ta_hang,khoi_luong_kg,tien_cod_vnd,loai_dich_vu\n',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Đã xuất mẫu 7 cột đầy đủ tại: $path',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Tải mẫu Đầy đủ (7 cột .csv)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final path = _store.exportReportFileToDisk(
                          fileName: 'Mau_Tao_Don_4_Cot.csv',
                          content: 'ten_nguoi_nhan,sdt_nguoi_nhan,dia_chi_giao,tien_cod_vnd\n',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Đã lưu file mẫu rút gọn 4 cột tại: $path',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.description_outlined, size: 16),
                      label: const Text('Tải mẫu Rút gọn (4 cột .csv)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final path = _store.exportReportFileToDisk(
                          fileName: 'Mau_Tao_Don_Toa_Do.csv',
                          content: 'ten_nguoi_nhan,sdt_nguoi_nhan,dia_chi_giao,mo_ta_hang,khoi_luong_kg,tien_cod_vnd,loai_dich_vu,dia_chi_lay,pickup_lat,pickup_lng,dropoff_lat,dropoff_lng\n',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Đã xuất mẫu tọa độ tại: $path'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.pin_drop_outlined, size: 16),
                      label: const Text('Tải mẫu kèm tọa độ'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked =
                            await SecurityAndBarcodeUtils.pickLocalCsvFileContent();
                        if (!mounted || picked == null) return;
                        _rebuildMerchantUi(() {
                          _csvInputCtrl.text = picked.content.trim();
                          _parseCsvBatch();
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Đã nạp tệp CSV từ máy: ${picked.filePath}',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.folder_open_outlined, size: 16),
                      label: const Text('Chọn tệp CSV từ máy'),
                    ),
                  ],
                ),
                if (personalWhs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey(
                      '${personalWhs.length}_${_selectedWarehouseIndex.clamp(0, personalWhs.length - 1)}',
                    ),
                    isExpanded: true,
                    initialValue: _selectedWarehouseIndex.clamp(
                      0,
                      personalWhs.length - 1,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Kho lấy hàng áp dụng cho lô đơn CSV',
                      prefixIcon: Icon(
                        Icons.warehouse_outlined,
                        color: Color(0xFF5B33E6),
                        size: 18,
                      ),
                    ),
                    items: List.generate(personalWhs.length, (idx) {
                      final wh = personalWhs[idx];
                      return DropdownMenuItem<int>(
                        value: idx,
                        child: Text(
                          '${wh.name} (${wh.address})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                    onChanged: (idx) {
                      if (idx != null) {
                        _rebuildMerchantUi(() {
                          _selectedWarehouseIndex = idx;
                          _parseCsvBatch();
                        });
                      }
                    },
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Người trả cước lô CSV:',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('Người gửi trả phí'),
                      selected: _batchFeePayer == 'Người gửi trả phí',
                      selectedColor: const Color(0xFFEDE9FE),
                      onSelected: (_) => _rebuildMerchantUi(
                        () => _batchFeePayer = 'Người gửi trả phí',
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('Người nhận trả phí'),
                      selected: _batchFeePayer == 'Người nhận trả phí',
                      selectedColor: const Color(0xFFEDE9FE),
                      onSelected: (_) => _rebuildMerchantUi(
                        () => _batchFeePayer = 'Người nhận trả phí',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F1E8),
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            color: Color(0xFF5B33E6),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Kéo thả file Excel/CSV hoặc nhập dữ liệu hàng loạt để kiểm lỗi trực tiếp:',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _csvInputCtrl,
                        maxLines: 3,
                        onChanged: (_) => _rebuildMerchantUi(_parseCsvBatch),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Tên người nhận, SĐT (10 số), Địa chỉ chi tiết, Tiền COD',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const Text(
                      'Bảng xem trước dữ liệu & Kiểm lỗi (Preview)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.all(Radius.zero),
                          ),
                          child: Text(
                            'Hợp lệ: $validCount đơn',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.all(Radius.zero),
                          ),
                          child: Text(
                            'Lỗi: $errorCount đơn',
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      const Color(0xFFF5F1E8),
                    ),
                    columns: const [
                      DataColumn(label: Text('Dòng')),
                      DataColumn(label: Text('Người nhận')),
                      DataColumn(label: Text('Số điện thoại')),
                      DataColumn(label: Text('Địa chỉ giao hàng')),
                      DataColumn(label: Text('KL (kg)')),
                      DataColumn(label: Text('Dịch vụ')),
                      DataColumn(label: Text('COD (đ)')),
                      DataColumn(label: Text('Trạng thái kiểm lỗi')),
                    ],
                    rows: _parsedRows.map((r) {
                      return DataRow(
                        color: WidgetStateProperty.all(
                          r.isValid
                              ? Colors.white
                              : AppColors.danger.withValues(alpha: 0.06),
                        ),
                        cells: [
                          DataCell(Text('#${r.rowNumber}')),
                          DataCell(
                            Text(
                              r.recipientName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          DataCell(Text(r.recipientPhone)),
                          DataCell(Text(r.dropoffAddress)),
                          DataCell(Text('${r.weightKg.toStringAsFixed(1)} kg')),
                          DataCell(Text(r.serviceType.displayName)),
                          DataCell(
                            Text(
                              r.codAmount.isFinite
                                  ? CurrencyFormatter.formatVnd(r.codAmount)
                                  : '-',
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  r.isValid ? Icons.check_circle : Icons.cancel,
                                  size: 16,
                                  color: r.isValid
                                      ? AppColors.success
                                      : AppColors.danger,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  r.isValid ? 'Hợp lệ' : r.statusNote,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: r.isValid
                                        ? AppColors.success
                                        : AppColors.danger,
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
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5E83),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 13,
                      ),
                    ),
                    onPressed: validCount == 0
                        ? null
                        : () {
                            final activeMer = _store.activeMerchantRecord;
                            if (activeMer == null ||
                                activeMer.approvalStatus != 'Đã duyệt') {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: AppColors.danger,
                                  content: Text(
                                    activeMer == null
                                        ? 'Vui lòng gửi hồ sơ pháp lý Cửa hàng B2B và chờ Admin duyệt trước khi tạo đơn hàng loạt!'
                                        : 'Hồ sơ cửa hàng B2B đang ở trạng thái "${activeMer.approvalStatus}". Vui lòng chờ Admin duyệt KYC trước khi tạo đơn hàng loạt!',
                                  ),
                                ),
                              );
                              _rebuildMerchantUi(
                                () => _selectedScreenIndex = 0,
                              );
                              return;
                            }
                            final result = _store
                                .parseAndCreateBulkOrdersFromCsv(
                                  _csvInputCtrl.text,
                                  customPickupAddress: _batchPickupAddress,
                                  feePayerMethod: _batchFeePayer,
                                  commitOrders: true,
                                );
                            final createdTotal =
                                result.createdTrackingCodes.length;
                            _rebuildMerchantUi(() {
                              if (createdTotal > 0) {
                                _csvInputCtrl.clear();
                                _parsedRows = [];
                              } else {
                                _parsedRows = result.rows;
                              }
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  createdTotal > 0
                                      ? 'Đã tạo $createdTotal đơn hàng. Bỏ qua ${result.invalidCount} dòng lỗi.'
                                      : 'Dữ liệu đã thay đổi. Vui lòng kiểm tra các dòng lỗi.',
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.playlist_add_check),
                    label: Text(
                      'Xác nhận tạo $validCount đơn hợp lệ',
                      style: const TextStyle(fontWeight: FontWeight.w800),
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

  /// UC34: Quản lý & In phiếu gửi hàng A6 (Chuẩn uc34_in_phieu_v2)
  Widget _buildWaybillA6PrintView() {
    final shopOrders = _store.merchantPersonalOrders;
    final personalWhs = _store.merchantPersonalWarehouses;
    final fallbackWhAddr = personalWhs.isNotEmpty
        ? personalWhs.first.address
        : '';
    final activeStoreName =
        _store.activeMerchantRecord?.storeName ?? _store.merchantStoreName;
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
              'Chưa có vận đơn nào thuộc cửa hàng để in phiếu A6',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              'Cửa hàng "$activeStoreName" hiện chưa khởi tạo đơn hàng nào. Vui lòng tạo đơn lẻ hoặc tải file CSV hàng loạt trước khi in phiếu gửi hàng.',
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
      );
    }
    final safeIdx = _selectedWaybillOrderIndex.clamp(0, shopOrders.length - 1);
    final ord = shopOrders[safeIdx];
    final recipientShipFee = ord.paymentMethod == 'Người nhận trả phí'
        ? ord.totalAmount
        : 0.0;
    final totalCollectFromRecipient = ord.codAmount + recipientShipFee;
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
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  const Text(
                    'Chọn đơn cần in phiếu gửi hàng',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5E83),
                    ),
                    onPressed: () async {
                      final savedPath =
                          await SecurityAndBarcodeUtils.exportA6LabelToHtmlFile(
                            trackingCode: ord.trackingCode,
                            barcodePayload:
                                'GOMAU-${ord.id}-${ord.trackingCode}',
                            qrPayload:
                                'GOMAU|${ord.trackingCode}|${ord.recipientPhone}|THU:${totalCollectFromRecipient.toStringAsFixed(0)}',
                            storeName: activeStoreName,
                            warehouseAddress: ord.pickupAddress.isNotEmpty
                                ? ord.pickupAddress
                                : fallbackWhAddr,
                            recipientName: ord.recipientName,
                            recipientPhone: ord.recipientPhone,
                            dropoffAddress: ord.dropoffAddress,
                            packageDescription: ord.packageDescription,
                            codAmount: ord.codAmount,
                            recipientShippingFee: recipientShipFee,
                          );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã kết xuất tệp vận đơn khổ A6 thực tế tại: $savedPath',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.print, size: 16),
                    label: Text('In phiếu A6 (${ord.trackingCode})'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  showCheckboxColumn: false,
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFFF5F1E8),
                  ),
                  columns: const [
                    DataColumn(label: Text('Chọn')),
                    DataColumn(label: Text('Mã đơn')),
                    DataColumn(label: Text('Người nhận')),
                    DataColumn(label: Text('Thu hộ COD')),
                    DataColumn(label: Text('Trạng thái')),
                  ],
                  rows: shopOrders.asMap().entries.map((entry) {
                    final rowIdx = entry.key;
                    final o = entry.value;
                    final isSelected = rowIdx == safeIdx;
                    return DataRow(
                      selected: isSelected,
                      onSelectChanged: (_) {
                        _rebuildMerchantUi(
                          () => _selectedWaybillOrderIndex = rowIdx,
                        );
                      },
                      cells: [
                        DataCell(
                          Icon(
                            isSelected
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            color: const Color(0xFFFF5E83),
                            size: 18,
                          ),
                        ),
                        DataCell(
                          Text(
                            o.trackingCode,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        DataCell(Text(o.recipientName)),
                        DataCell(
                          Text(CurrencyFormatter.formatVnd(o.codAmount)),
                        ),
                        DataCell(
                          Text(
                            o.paymentStatus == 'RETURNED'
                                ? 'Đã hoàn kho'
                                : o.status.displayName,
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
                'Xem trước Phiếu gửi hàng (Khổ A6)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.zero),
                  border: Border.all(color: Colors.black87, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Code128BarcodeWidget(
                            data: 'GOMAU-${ord.id}-${ord.trackingCode}',
                            height: 42,
                          ),
                        ),
                        const SizedBox(width: 10),
                        QrMatrixPainterWidget(
                          payload:
                              'GOMAU|${ord.trackingCode}|${ord.recipientPhone}|THU:${totalCollectFromRecipient.toStringAsFixed(0)}',
                          size: 62,
                        ),
                      ],
                    ),
                    const Divider(),
                    Text(
                      'NGƯỜI GỬI: $activeStoreName',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Kho lấy: ${ord.pickupAddress.isNotEmpty ? ord.pickupAddress : fallbackWhAddr}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    const Divider(),
                    Text(
                      'NGƯỜI NHẬN: ${ord.recipientName} - ${ord.recipientPhone}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    Text(
                      'Địa chỉ: ${ord.dropoffAddress}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Hàng hóa: ${ord.packageDescription}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'COD: ${CurrencyFormatter.formatVnd(ord.codAmount)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (recipientShipFee > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Cước người nhận trả: +${CurrencyFormatter.formatVnd(recipientShipFee)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF5B33E6),
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'TỔNG THU NGƯỜI NHẬN: ${CurrencyFormatter.formatVnd(totalCollectFromRecipient)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.danger,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        if (constraints.maxWidth < 820) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [colLeft, const SizedBox(height: 16), colRight],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: colLeft),
            const SizedBox(width: 16),
            Expanded(flex: 5, child: colRight),
          ],
        );
      },
    );
  }

  Widget _buildMerchantGrabFoodMenuManagerView(BuildContext context) {
    final activeMer = _store.activeMerchantRecord;
    final personalWhs = _store.merchantPersonalWarehouses;
    final primaryWh =
        personalWhs.where((w) => w.isPrimary).firstOrNull ??
        personalWhs.firstOrNull;
    final activeStoreName =
        activeMer?.storeName.trim().isNotEmpty == true
        ? activeMer!.storeName.trim()
        : (_store.merchantStoreName.trim().isNotEmpty
              ? _store.merchantStoreName.trim()
              : 'Quán Đối tác B2B');
    final activeStoreAddr =
        primaryWh?.address.trim().isNotEmpty == true
        ? primaryWh!.address.trim()
        : (_shopAddressCtrl.text.trim().isNotEmpty
              ? _shopAddressCtrl.text.trim()
              : 'Chưa cấu hình kho lấy hàng (dùng tọa độ mặc định)');
    final myMenuItems = _store.activeMerchantPersonalMenuItems;

    const slotOptions = <(String, String)>[
      ('breakfast', 'Bữa sáng (05-10h)'),
      ('lunch', 'Cơm trưa (11-13h)'),
      ('afternoonTea', 'Trà chiều (14-16h)'),
      ('dinner', 'Ăn tối (17-21h)'),
      ('lateNight', 'Đêm khuya (22-04h)'),
    ];

    Widget buildDishEditorCard() {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.ink, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0xFF00B14F),
              offset: Offset(4, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Text(
                    _editingMenuItemId != null
                        ? 'Cập nhật món ăn ($_editingMenuItemId)'
                        : 'Đăng món mới lên GrabFood',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  if (_editingMenuItemId != null)
                    TextButton(
                      onPressed: () => _rebuildMerchantUi(() {
                        _editingMenuItemId = null;
                        _menuDishNameCtrl.clear();
                        _menuDishDescCtrl.clear();
                        _menuDishPriceCtrl.text = '49000';
                        _menuDishPrepCtrl.text = '12';
                      }),
                      child: const Text('Hủy sửa'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                color: const Color(0xFFF0FDF4),
                child: Text(
                  'Quán hiển thị: $activeStoreName\nĐiểm lấy món GPS: $activeStoreAddr',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _menuDishNameCtrl,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Tên món ăn / đồ uống',
                  hintText: 'VD: Bún Bò Huế Đặc Biệt / Trà Đào Cam Sả...',
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, rowConstraints) {
                  final priceField = TextField(
                    controller: _menuDishPriceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Giá bán (VNĐ)',
                    ),
                  );
                  final prepField = TextField(
                    controller: _menuDishPrepCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Chuẩn bị (phút)',
                    ),
                  );
                  if (rowConstraints.maxWidth < 420) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        priceField,
                        const SizedBox(height: 10),
                        prepField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: priceField),
                      const SizedBox(width: 10),
                      Expanded(child: prepField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _menuDishCategory,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Nhóm ẩm thực (hiển thị bộ lọc Khách hàng)',
                ),
                items: <String>{
                  ...GrabFoodRecommendationEngine.supportedCategories,
                  _menuDishCategory,
                }.map((cat) {
                  return DropdownMenuItem(
                    value: cat,
                    child: Text(cat, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    _rebuildMerchantUi(() => _menuDishCategory = val);
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _menuDishDescCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Mô tả thành phần / khẩu phần',
                  hintText: 'VD: Nước hầm xương 10h, tặng kèm rau sống & ớt sa tế',
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Khung giờ mở bán (đề xuất thông minh theo giờ):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: slotOptions.map((opt) {
                  final selected = _menuDishMealSlots.contains(opt.$1);
                  return FilterChip(
                    visualDensity: VisualDensity.compact,
                    selected: selected,
                    selectedColor: AppColors.acid,
                    label: Text(
                      opt.$2,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                      ),
                    ),
                    onSelected: (on) {
                      _rebuildMerchantUi(() {
                        if (on) {
                          _menuDishMealSlots.add(opt.$1);
                        } else if (_menuDishMealSlots.length > 1) {
                          _menuDishMealSlots.remove(opt.$1);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '🌱 Sử dụng bao bì Xanh (hộp bã mía / giấy)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    activeThumbColor: const Color(0xFF00B14F),
                    value: _menuDishEco,
                    onChanged: (v) => _rebuildMerchantUi(() => _menuDishEco = v),
                  ),
                ],
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '❄ Đồ uống lạnh / Kem (tự động gắn túi giữ nhiệt)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    activeThumbColor: const Color(0xFF0284C7),
                    value: _menuDishCold,
                    onChanged: (v) =>
                        _rebuildMerchantUi(() => _menuDishCold = v),
                  ),
                ],
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '🔥 Đang có Ưu đãi / Món Signature của quán',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    activeThumbColor: AppColors.pink,
                    value: _menuDishPromo,
                    onChanged: (v) =>
                        _rebuildMerchantUi(() => _menuDishPromo = v),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00B14F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onPressed: () async {
                  final dishName = _menuDishNameCtrl.text.trim();
                  final price =
                      double.tryParse(
                        _menuDishPriceCtrl.text
                            .replaceAll('.', '')
                            .replaceAll(',', '')
                            .trim(),
                      ) ??
                      0.0;
                  final prep =
                      int.tryParse(_menuDishPrepCtrl.text.trim()) ?? 15;
                  if (dishName.isEmpty || price <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: AppColors.danger,
                        content: Text(
                          'Vui lòng nhập Tên món và Giá bán hợp lệ (> 0đ)!',
                        ),
                      ),
                    );
                    return;
                  }
                  final saved = await _store.upsertMerchantMenuItem(
                    id: _editingMenuItemId,
                    name: dishName,
                    priceVnd: price,
                    description: _menuDishDescCtrl.text,
                    category: _menuDishCategory,
                    prepMinutes: prep,
                    mealSlots: _menuDishMealSlots.toList(),
                    isEcoPackaging: _menuDishEco,
                    isColdItem: _menuDishCold,
                    hasPromoBadge: _menuDishPromo,
                  );
                  if (!context.mounted) return;
                  _rebuildMerchantUi(() {
                    _editingMenuItemId = null;
                    _menuDishNameCtrl.clear();
                    _menuDishDescCtrl.clear();
                    _menuDishPriceCtrl.text = '49000';
                    _menuDishPrepCtrl.text = '12';
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã đồng bộ món "${saved.name}" lên kênh Gợi ý Ăn uống Khách hàng!',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.publish_rounded, size: 18),
                label: Text(
                  _editingMenuItemId != null
                      ? 'Lưu cập nhật món ăn'
                      : 'Đăng món lên GrabFood',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildDishListCard() {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.ink, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Thực đơn Đối tác B2B (${myMenuItems.length} món)',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Các món đang ở trạng thái "Còn món" sẽ xuất hiện ngay lập tức kèm nhãn ĐỐI TÁC B2B trên ứng dụng Khách hàng.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const Divider(height: 18),
            if (myMenuItems.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                color: AppColors.paper,
                child: const Column(
                  children: [
                    Icon(
                      Icons.restaurant_outlined,
                      size: 34,
                      color: AppColors.textSecondary,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Cửa hàng chưa đăng món ăn nào lên GrabFood',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppColors.ink,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Điền thông tin món ăn ở biểu mẫu để tiếp cận khách hàng quanh bán kính kho lấy hàng của bạn.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...myMenuItems.map((item) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: item.isAvailable
                        ? AppColors.paper
                        : const Color(0xFFF3F4F6),
                    border: Border.all(color: AppColors.ink, width: 1.1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            color: item.isAvailable
                                ? const Color(0xFF00B14F)
                                : AppColors.danger,
                            child: Text(
                              item.isAvailable ? 'CÒN MÓN' : 'TẠM HẾT',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            color: AppColors.violet,
                            child: Text(
                              item.category,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (item.isColdItem)
                            const Text(
                              '❄ Đồ lạnh',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0369A1),
                              ),
                            ),
                          if (item.isEcoPackaging)
                            const Text(
                              '🌱 Bao bì Xanh',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF166534),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                      if (item.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.description,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        '${CurrencyFormatter.formatVnd(item.priceVnd)} • Chuẩn bị ${item.prepMinutes}p • Đã bán ${item.soldCount}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Consolas',
                          color: Color(0xFF00853B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () async {
                              await _store.toggleMerchantMenuItemAvailability(
                                item.id,
                              );
                            },
                            icon: Icon(
                              item.isAvailable
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                              size: 15,
                            ),
                            label: Text(
                              item.isAvailable ? 'Báo tạm hết' : 'Mở bán lại',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _rebuildMerchantUi(() {
                              _editingMenuItemId = item.id;
                              _menuDishNameCtrl.text = item.name;
                              _menuDishPriceCtrl.text = item.priceVnd
                                  .round()
                                  .toString();
                              _menuDishPrepCtrl.text = item.prepMinutes
                                  .toString();
                              _menuDishDescCtrl.text = item.description;
                              _menuDishCategory = item.category;
                              _menuDishMealSlots
                                ..clear()
                                ..addAll(item.mealSlots);
                              _menuDishEco = item.isEcoPackaging;
                              _menuDishCold = item.isColdItem;
                              _menuDishPromo = item.hasPromoBadge;
                            }),
                            icon: const Icon(Icons.edit_outlined, size: 15),
                            label: const Text(
                              'Sửa',
                              style: TextStyle(fontSize: 11.5),
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: AppColors.danger,
                            ),
                            onPressed: () async {
                              await _store.deleteMerchantMenuItem(item.id);
                            },
                            icon: const Icon(Icons.delete_outline, size: 15),
                            label: const Text(
                              'Xóa',
                              style: TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Quản lý Thực đơn Ăn uống Đối tác B2B (GrabFood)',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Đồng bộ thời gian thực món ăn, khung giờ phục vụ và bao bì Xanh sang ứng dụng Khách hàng',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 860) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildDishEditorCard(),
                  const SizedBox(height: 16),
                  buildDishListCard(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: buildDishEditorCard()),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: buildDishListCard()),
              ],
            );
          },
        ),
      ],
    );
  }
}
