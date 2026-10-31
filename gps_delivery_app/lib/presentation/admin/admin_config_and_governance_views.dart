part of 'admin_subsystem_views.dart';

extension _AdminConfigAndGovernanceViews on _AdminSubsystemEntryState {
  /// UC26: Cấu hình Công thức Tính cước, Phụ phí & Khuyến mãi Voucher (Chuẩn uc26_gia_cuoc_1791015101391.jpg)
  Widget _buildDynamicPricingConfigView() {
    final canEditSystem = _store.hasAdminPermission('Hệ thống: Cài đặt');

    return LayoutBuilder(
      builder: (context, constraints) {
        final colLeft = Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cấu hình Bảng giá & Phụ phí Động',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (!canEditSystem)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '🔒 Vai trò hiện tại không có quyền "Hệ thống: Cài đặt" để thay đổi bảng giá hoặc voucher.',
                      style: TextStyle(color: AppColors.danger, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                LayoutBuilder(
                  builder: (context, pricingConstraints) {
                    final baseField = TextField(
                      controller: _baseFareCtrl,
                      enabled: canEditSystem,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Giá mở cửa chuẩn (VNĐ)',
                      ),
                    );
                    final perKmField = TextField(
                      controller: _perKmCtrl,
                      enabled: canEditSystem,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Đơn giá mỗi km tiếp theo (VNĐ/km)',
                      ),
                    );
                    if (pricingConstraints.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          baseField,
                          const SizedBox(height: AppSpacing.sm),
                          perKmField,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: baseField),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: perKmField),
                      ],
                    );
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Phụ phí giờ cao điểm (+${CurrencyFormatter.formatVnd(_store.peakHourSurchargeConfig)})',
                  ),
                  subtitle: const Text(
                    'Áp dụng cho gói Tiêu chuẩn & Xe tải (Hỏa tốc 30p đã gồm +20.000đ)',
                  ),
                  value: _store.isPeakSurchargeActive,
                  onChanged: canEditSystem
                      ? (v) => _store.savePricingConfiguration(
                          baseFare:
                              double.tryParse(_baseFareCtrl.text) ??
                              _store.baseFareConfig,
                          pricePerKm:
                              double.tryParse(_perKmCtrl.text) ??
                              _store.pricePerKmConfig,
                          isPeakEnabled: v,
                          isWeatherEnabled: _store.isWeatherSurchargeActive,
                        )
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Phụ phí thời tiết xấu / Mưa ngập (+${CurrencyFormatter.formatVnd(_store.badWeatherSurchargeConfig)})',
                  ),
                  value: _store.isWeatherSurchargeActive,
                  onChanged: canEditSystem
                      ? (v) => _store.savePricingConfiguration(
                          baseFare:
                              double.tryParse(_baseFareCtrl.text) ??
                              _store.baseFareConfig,
                          pricePerKm:
                              double.tryParse(_perKmCtrl.text) ??
                              _store.pricePerKmConfig,
                          isPeakEnabled: _store.isPeakSurchargeActive,
                          isWeatherEnabled: v,
                        )
                      : null,
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                    ),
                    onPressed: canEditSystem
                        ? () {
                            final parsedBase = double.tryParse(
                              _baseFareCtrl.text.trim(),
                            );
                            final parsedPerKm = double.tryParse(
                              _perKmCtrl.text.trim(),
                            );
                            if (parsedBase == null ||
                                parsedBase <= 0 ||
                                parsedPerKm == null ||
                                parsedPerKm <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Vui lòng nhập giá mở cửa và đơn giá mỗi km lớn hơn 0!',
                                  ),
                                ),
                              );
                              return;
                            }
                            _store.savePricingConfiguration(
                              baseFare: parsedBase,
                              pricePerKm: parsedPerKm,
                              isPeakEnabled: _store.isPeakSurchargeActive,
                              isWeatherEnabled: _store.isWeatherSurchargeActive,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Đã cập nhật cấu hình giá cước hệ thống thành công!',
                                ),
                              ),
                            );
                          }
                        : null,
                    child: const Text('Lưu cấu hình Bảng giá'),
                  ),
                ),
              ],
            ),
          ),
        );
        final colRight = Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Quản lý Chiến dịch Khuyến mãi & Voucher',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: canEditSystem
                              ? () {
                                  final added =
                                      _store.publishPresetFlashCampaignsForAdmin();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        added > 0
                                            ? 'Đã phát hành $added chiến dịch Flash Sale (Shopee × Grab) vào kho ưu đãi toàn hệ thống!'
                                            : 'Toàn bộ chiến dịch Flash Sale (Shopee × Grab) đã sẵn sàng trong hệ thống.',
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.bolt_rounded, size: 16),
                          label: const Text('Gói Flash Sale (Shopee/Grab)'),
                        ),
                        OutlinedButton.icon(
                          onPressed: canEditSystem
                              ? () => _showCreateVoucherDialog(context)
                              : null,
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text('Phát hành mã mới'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_store.vouchers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Chưa có mã khuyến mãi nào đang phát hành.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                else
                  ..._store.vouchers.map(
                    (v) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.paper,
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.local_offer_outlined,
                                  color: AppColors.accent,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${v.code} • ${v.title}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Mức giảm: ${v.discountLabel} (Tối đa: ${CurrencyFormatter.formatVnd(v.maxDiscount)}) • Đơn tối thiểu: ${CurrencyFormatter.formatVnd(v.minOrderValue)} • Đã dùng: ${v.usedCount}/${v.usageLimit} • HSD: ${v.expiryDate}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            onPressed: canEditSystem
                                ? () => _store.toggleVoucherStatus(v.code)
                                : null,
                            label: Text(
                              v.isExpired ? '${v.status} (Hết hạn)' : v.status,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
        if (constraints.maxWidth < 860) {
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

  void _showCreateVoucherDialog(BuildContext context) {
    final futureExp = DateTime.now().add(const Duration(days: 90));
    final defaultExp =
        '${futureExp.day.toString().padLeft(2, '0')}/${futureExp.month.toString().padLeft(2, '0')}/${futureExp.year}';
    final codeCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final discountCtrl = TextEditingController();
    final maxDiscountCtrl = TextEditingController();
    final minOrderCtrl = TextEditingController();
    final usageLimitCtrl = TextEditingController();
    final expiryCtrl = TextEditingController(text: defaultExp);
    bool isPct = false;
    Animation<double>? dialogRouteAnim;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        dialogRouteAnim ??= ModalRoute.of(dialogCtx)?.animation;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Phát hành Mã Khuyến mãi & Voucher mới',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mã Voucher',
                        hintText: 'VD: PROMO25K',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên chương trình ưu đãi',
                        hintText: 'VD: Giảm 25k đơn giao nội thành',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Giảm theo phần trăm (%)'),
                      value: isPct,
                      onChanged: (v) {
                        setDialogState(() {
                          isPct = v;
                          discountCtrl.clear();
                        });
                      },
                    ),
                    TextField(
                      controller: discountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: isPct
                            ? 'Phần trăm giảm giá (1 - 100%)'
                            : 'Số tiền giảm giá (VNĐ)',
                        hintText: isPct ? 'VD: 15' : 'VD: 25000',
                      ),
                    ),
                    if (isPct) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: maxDiscountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Giảm tối đa (VNĐ)',
                          hintText: 'VD: 35000',
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: minOrderCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Giá trị đơn hàng tối thiểu (VNĐ)',
                        hintText: 'VD: 50000 (nhập 0 nếu không giới hạn)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: usageLimitCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Giới hạn lượt dùng',
                        hintText: 'VD: 100',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: expiryCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Hạn sử dụng (DD/MM/YYYY)',
                      ),
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
                    backgroundColor: AppColors.accent,
                  ),
                  onPressed: () {
                    final code = codeCtrl.text.trim().toUpperCase();
                    final title = titleCtrl.text.trim();
                    final discount =
                        double.tryParse(discountCtrl.text.trim()) ?? 0;
                    final maxDisc = isPct
                        ? (double.tryParse(maxDiscountCtrl.text.trim()) ??
                              30000)
                        : discount;
                    final minOrder =
                        double.tryParse(minOrderCtrl.text.trim()) ?? 0;
                    final usageLim =
                        int.tryParse(usageLimitCtrl.text.trim()) ?? 0;
                    final expiry = expiryCtrl.text.trim().isNotEmpty
                        ? expiryCtrl.text.trim()
                        : '31/12/2027';
                    final validExpiryFormat = RegExp(r'^\d{2}/\d{2}/\d{4}$')
                        .hasMatch(expiry);
                    final isDuplicateCode = _store.vouchers.any(
                      (v) => v.code.trim().toUpperCase() == code,
                    );
                    if (isDuplicateCode) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppColors.danger,
                          content: Text(
                            'Mã khuyến mãi "$code" đã tồn tại trong hệ thống. Vui lòng nhập mã mới hoặc bật/tắt mã hiện có!',
                          ),
                        ),
                      );
                      return;
                    }
                    if (code.isEmpty ||
                        title.isEmpty ||
                        discount <= 0 ||
                        (isPct && (discount > 100 || maxDisc <= 0)) ||
                        minOrder < 0 ||
                        usageLim <= 0 ||
                        !validExpiryFormat) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Vui lòng nhập mã, mức giảm, giới hạn lượt dùng (>0) và hạn sử dụng định dạng DD/MM/YYYY!',
                          ),
                        ),
                      );
                      return;
                    }
                    _store.createNewVoucher(
                      code: code,
                      title: title,
                      discountValue: discount,
                      isPercentage: isPct,
                      minOrderValue: minOrder,
                      maxDiscount: maxDisc,
                      usageLimit: usageLim,
                      expiryDate: expiry,
                    );
                    Navigator.of(dialogCtx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã phát hành mã khuyến mãi $code ($usageLim lượt • HSD: $expiry) thành công!',
                        ),
                      ),
                    );
                  },
                  child: const Text('Phát hành mã'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      SecurityAndBarcodeUtils.disposeControllersAfterDialog([
        codeCtrl,
        titleCtrl,
        discountCtrl,
        maxDiscountCtrl,
        minOrderCtrl,
        usageLimitCtrl,
        expiryCtrl,
      ], dialogRouteAnim);
    });
  }

  /// UC27: Báo cáo thống kê Hệ thống (Khớp 100% anh_sua_lai/uc27_bao_cao.jpg)
  Widget _buildVoucherCampaignsView() {
    if (!_store.hasAdminPermission('Tài chính: Báo cáo')) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Báo cáo thống kê hệ thống',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                '🔒 Vai trò điều hành hiện tại không có quyền "Tài chính: Báo cáo" để xem báo cáo doanh thu & SLA.',
                style: TextStyle(color: AppColors.danger),
              ),
            ],
          ),
        ),
      );
    }

    final now = DateTime.now();
    final totalOrders = _store.orders.length;
    final deliveredOrders = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus != 'RETURNED',
        )
        .toList();
    final deliveredCount = deliveredOrders.length;
    final closedOrdersCount = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.delivered ||
              o.status == OrderStatus.cancelled ||
              o.status == OrderStatus.failed ||
              o.status == OrderStatus.returning ||
              o.paymentStatus == 'RETURNED',
        )
        .length;
    final grossFareRevenue = deliveredOrders.fold<double>(
      0.0,
      (sum, o) => sum + o.deliveryFee + o.surchargeFee,
    );
    final totalVoucherSubsidy = deliveredOrders.fold<double>(
      0.0,
      (sum, o) => sum + o.discountAmount,
    );
    final totalRevenue = deliveredOrders.fold<double>(
      0.0,
      (sum, o) => sum + o.totalAmount,
    );
    final driverPayout80 = deliveredOrders.fold<double>(
      0.0,
      (sum, o) =>
          sum + ((o.deliveryFee + o.surchargeFee) * 0.80).roundToDouble(),
    );
    final platformCommission = grossFareRevenue - driverPayout80;
    final platformNetAfterVoucher = platformCommission - totalVoucherSubsidy;

    int targetSlaSecondsFor(DeliveryServiceType st) {
      switch (st) {
        case DeliveryServiceType.express30m:
          return 2700;
        case DeliveryServiceType.sameDay2h:
          return 7200;
        case DeliveryServiceType.standard:
          return 7200;
        case DeliveryServiceType.saving:
          return 14400;
        case DeliveryServiceType.truck:
          return 10800;
      }
    }

    bool hasDeliveryTiming(ActiveOrderRecord o) =>
        o.deliveredAtMs != null && o.deliveredAtMs! >= o.createdAtMs;

    int elapsedDeliverySec(ActiveOrderRecord o) {
      if (o.deliveredAtMs != null && o.deliveredAtMs! > o.createdAtMs) {
        return ((o.deliveredAtMs! - o.createdAtMs) ~/ 1000);
      }
      return 0;
    }

    final onTimeDeliveredCount = deliveredOrders
        .where(
          (o) =>
              hasDeliveryTiming(o) &&
              elapsedDeliverySec(o) <= targetSlaSecondsFor(o.serviceType),
        )
        .length;
    final unknownTimingCount = deliveredOrders
        .where((o) => !hasDeliveryTiming(o))
        .length;
    final slaDenom = closedOrdersCount - unknownTimingCount;
    final slaRate = slaDenom == 0
        ? 0.0
        : (onTimeDeliveredCount * 100.0 / slaDenom);
    final slaLabel = slaDenom == 0
        ? 'Chưa có dữ liệu'
        : '${slaRate.toStringAsFixed(1)}%';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.zero),
        border: Border.all(color: const Color(0xFF15131E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Báo cáo thống kê hệ thống',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF15131E),
                    ),
                  ),
                  Text(
                    'Kỳ báo cáo: Tháng ${now.month}/${now.year} • Cước gốc: ${CurrencyFormatter.formatVnd(grossFareRevenue)} • Trợ giá Voucher: -${CurrencyFormatter.formatVnd(totalVoucherSubsidy)} • Chi trả TX (80%): -${CurrencyFormatter.formatVnd(driverPayout80)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF4A4754),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF14B866),
                    ),
                    onPressed: () {
                      final path = _store.exportReportFileToDisk(
                        fileName:
                            'Bao_Cao_He_Thong_T${now.month}_${now.year}.csv',
                        content:
                            'tong_don,giao_thanh_cong,cuoc_goc_vnd,tro_gia_voucher_vnd,doanh_thu_thuc_thu_vnd,chi_tra_tai_xe_80_vnd,hoa_hong_gop_20_vnd,doanh_thu_rong_san_vnd,sla_pct\n'
                            '$totalOrders,$deliveredCount,${grossFareRevenue.toStringAsFixed(0)},${totalVoucherSubsidy.toStringAsFixed(0)},${totalRevenue.toStringAsFixed(0)},${driverPayout80.toStringAsFixed(0)},${platformCommission.toStringAsFixed(0)},${platformNetAfterVoucher.toStringAsFixed(0)},${slaRate.toStringAsFixed(1)}',
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã xuất báo cáo thống kê CSV tại: $path',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.table_view, size: 16),
                    label: const Text('Xuất CSV'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                    ),
                    onPressed: () {
                      final deliveredPct = totalOrders > 0
                          ? (deliveredCount * 100.0 / totalOrders)
                          : 0.0;
                      final path = _store.exportReportFileToDisk(
                        fileName:
                            'Bao_Cao_He_Thong_T${now.month}_${now.year}_Summary.txt',
                        content:
                            'BAO CAO THONG KE HE THONG GO-MAU (THANG ${now.month}/${now.year})\n'
                            'Tong so don: $totalOrders\n'
                            'Giao thanh cong: $deliveredCount (${deliveredPct.toStringAsFixed(1)}%)\n'
                            'Ty le dung han SLA: ${slaRate.toStringAsFixed(1)}%\n'
                            'Tong cuoc goc: ${CurrencyFormatter.formatVnd(grossFareRevenue)}\n'
                            'Tro gia Voucher: -${CurrencyFormatter.formatVnd(totalVoucherSubsidy)}\n'
                            'Tong khach thanh toan: ${CurrencyFormatter.formatVnd(totalRevenue)}\n'
                            'Chi tra Tai xe (80% cuoc goc): ${CurrencyFormatter.formatVnd(driverPayout80)}\n'
                            'Hoa hong gop san (20% cuoc goc): ${CurrencyFormatter.formatVnd(platformCommission)}\n'
                            'Doanh thu rong san (sau Voucher): ${CurrencyFormatter.formatVnd(platformNetAfterVoucher)}\n',
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã xuất bản tóm tắt báo cáo (.txt) tại: $path',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: const Text('Xuất Báo cáo (.txt)'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, kpiConstraints) {
              final maxW = kpiConstraints.maxWidth;
              final cols = maxW >= 780
                  ? 3
                  : maxW >= 520
                  ? 2
                  : 1;
              final cardWidth = cols == 1
                  ? maxW
                  : (maxW - (cols - 1) * 14.0) / cols;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _buildGoMauKpiCard(
                    width: cardWidth,
                    title: 'Thực thu khách trả (Sau KM)',
                    value: CurrencyFormatter.formatVnd(totalRevenue),
                    delta:
                        '(Cước gốc ${CurrencyFormatter.formatVnd(grossFareRevenue)})',
                    deltaPositive: true,
                    badgeColor: const Color(0xFF5B33E6),
                    icon: Icons.payments_outlined,
                    showSparkline: false,
                    sparklineColor: const Color(0xFF5B33E6),
                  ),
                  _buildGoMauKpiCard(
                    width: cardWidth,
                    title: 'Chiết khấu Sàn 20% (Ròng)',
                    value: CurrencyFormatter.formatVnd(platformNetAfterVoucher),
                    delta:
                        '(Gộp 20%: ${CurrencyFormatter.formatVnd(platformCommission)})',
                    deltaPositive: platformNetAfterVoucher >= 0,
                    badgeColor: const Color(0xFF14B866),
                    icon: Icons.account_balance_outlined,
                    showSparkline: false,
                    sparklineColor: const Color(0xFF14B866),
                  ),
                  _buildGoMauKpiCard(
                    width: cardWidth,
                    title: 'Tổng đơn hoàn thành',
                    value: '$deliveredCount/$totalOrders đơn',
                    delta: 'SLA: $slaLabel',
                    deltaPositive: true,
                    badgeColor: const Color(0xFFFF5E83),
                    icon: Icons.task_alt_rounded,
                    showSparkline: false,
                    sparklineColor: const Color(0xFFFF5E83),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Builder(
            builder: (context) {
              final safeTotal = totalOrders == 0 ? 1 : totalOrders;
              final expOrders = _store.orders
                  .where((o) => o.serviceType == DeliveryServiceType.express30m)
                  .toList();
              final stdOrders = _store.orders
                  .where((o) => o.serviceType == DeliveryServiceType.standard)
                  .toList();
              final savOrders = _store.orders
                  .where((o) => o.serviceType == DeliveryServiceType.saving)
                  .toList();
              final batch2hOrders = _store.orders
                  .where((o) => o.serviceType == DeliveryServiceType.sameDay2h)
                  .toList();
              final trkOrders = _store.orders
                  .where((o) => o.serviceType == DeliveryServiceType.truck)
                  .toList();

              String pctStr(int count) =>
                  '${((count / safeTotal) * 100).round()}% ($count đơn)';
              String slaFor(List<ActiveOrderRecord> list) {
                if (list.isEmpty) return 'Chưa có dữ liệu';
                final closedList = list
                    .where(
                      (o) =>
                          o.status == OrderStatus.delivered ||
                          o.status == OrderStatus.cancelled ||
                          o.status == OrderStatus.failed ||
                          o.status == OrderStatus.returning ||
                          o.paymentStatus == 'RETURNED',
                    )
                    .toList();
                final measurable = closedList
                    .where(
                      (o) =>
                          o.status != OrderStatus.delivered ||
                          hasDeliveryTiming(o),
                    )
                    .toList();
                if (measurable.isEmpty) return 'Chưa có dữ liệu';
                final ok = measurable
                    .where(
                      (o) =>
                          o.status == OrderStatus.delivered &&
                          o.paymentStatus != 'RETURNED' &&
                          hasDeliveryTiming(o) &&
                          elapsedDeliverySec(o) <=
                              targetSlaSecondsFor(o.serviceType),
                    )
                    .length;
                return '${((ok / measurable.length) * 100).clamp(0.0, 100.0).toStringAsFixed(1)}%';
              }

              int? weekBucketOfOrder(ActiveOrderRecord o) {
                final dt = o.createdAtDateTime;
                if (dt.year != now.year || dt.month != now.month) return null;
                return ((dt.day - 1) ~/ 7).clamp(0, 3);
              }

              final wkCounts = List<double>.generate(4, (wIdx) {
                final sum = deliveredOrders
                    .where((o) => weekBucketOfOrder(o) == wIdx)
                    .fold<double>(0, (s, o) => s + o.totalAmount);
                return sum;
              });
              final maxWk = wkCounts.fold<double>(1.0, (m, v) => v > m ? v : m);
              final wkBars = List.generate(4, (wIdx) {
                final ratio = wkCounts[wIdx] <= 0
                    ? 0.03
                    : (wkCounts[wIdx] / maxWk).clamp(0.14, 1.0);
                final amtLabel = wkCounts[wIdx] <= 0
                    ? '0đ'
                    : '${(wkCounts[wIdx] / 1000).round()}k';
                return ('Tuần ${wIdx + 1} ($amtLabel)', ratio);
              });

              return LayoutBuilder(
                builder: (context, constraints) {
                  final chartCard = Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F1E8),
                      borderRadius: BorderRadius.all(Radius.zero),
                      border: Border.all(color: const Color(0xFF15131E)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Doanh thu theo tuần (Tháng ${DateTime.now().month}/${DateTime.now().year})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 140,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              for (final wk in wkBars)
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 105 * wk.$2,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF5B33E6),
                                          borderRadius: BorderRadius.all(
                                            Radius.zero,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        wk.$1,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                  final tableCard = Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F1E8),
                      borderRadius: BorderRadius.all(Radius.zero),
                      border: Border.all(color: const Color(0xFF15131E)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tóm tắt đơn hàng theo Loại dịch vụ',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowHeight: 36,
                            dataRowMinHeight: 36,
                            dataRowMaxHeight: 42,
                            columns: const [
                              DataColumn(label: Text('Dịch vụ')),
                              DataColumn(label: Text('Tỷ trọng')),
                              DataColumn(label: Text('SLA Đúng giờ')),
                            ],
                            rows: [
                              DataRow(
                                cells: [
                                  const DataCell(
                                    Text('Giao Nhanh 30p (Express)'),
                                  ),
                                  DataCell(Text(pctStr(expOrders.length))),
                                  DataCell(Text(slaFor(expOrders))),
                                ],
                              ),
                              DataRow(
                                cells: [
                                  const DataCell(
                                    Text('Giao Tiêu chuẩn (Standard)'),
                                  ),
                                  DataCell(Text(pctStr(stdOrders.length))),
                                  DataCell(Text(slaFor(stdOrders))),
                                ],
                              ),
                              DataRow(
                                cells: [
                                  const DataCell(
                                    Text('Giao Tiết kiệm (Saving)'),
                                  ),
                                  DataCell(Text(pctStr(savOrders.length))),
                                  DataCell(Text(slaFor(savOrders))),
                                ],
                              ),
                              DataRow(
                                cells: [
                                  const DataCell(
                                    Text('Giao Nhanh 2H (Ghép đơn)'),
                                  ),
                                  DataCell(Text(pctStr(batch2hOrders.length))),
                                  DataCell(Text(slaFor(batch2hOrders))),
                                ],
                              ),
                              DataRow(
                                cells: [
                                  const DataCell(
                                    Text('Xe tải / Hàng lớn (Truck)'),
                                  ),
                                  DataCell(Text(pctStr(trkOrders.length))),
                                  DataCell(Text(slaFor(trkOrders))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                  if (constraints.maxWidth < 860) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        chartCard,
                        const SizedBox(height: 16),
                        tableCard,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: chartCard),
                      const SizedBox(width: 16),
                      Expanded(flex: 6, child: tableCard),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  /// UC28: Giải quyết Khiếu nại & Sự cố (Chuẩn uc28_khieu_nai_1791015159812.jpg)
  Widget _buildComplaintResolutionView() {
    final canResolveComplaint = _store.hasAdminPermission('Khiếu nại: Xử lý');
    if (_store.complaints.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trung tâm Giải quyết Khiếu nại & Sự cố',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Hiện chưa có hồ sơ khiếu nại hoặc báo cáo sự cố nào.',
              ),
            ],
          ),
        ),
      );
    }
    final safeIdx = _selectedComplaintIndex.clamp(
      0,
      _store.complaints.length - 1,
    );
    final activeTicket = _store.complaints[safeIdx];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trung tâm Giải quyết Khiếu nại & Sự cố',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (!canResolveComplaint)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '🔒 Vai trò hiện tại không có quyền "Khiếu nại: Xử lý" (Cấu hình tại mục Phân quyền RBAC).',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _store.complaints.asMap().entries.map((entry) {
                final idx = entry.key;
                final c = entry.value;
                return ChoiceChip(
                  label: Text('${c.ticketCode} (${c.orderId}) • ${c.status}'),
                  selected: idx == safeIdx,
                  onSelected: (_) =>
                      _rebuildAdminUi(() => _selectedComplaintIndex = idx),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Ticket đang chọn: ${activeTicket.ticketCode} (${activeTicket.orderId}) • Loại: ${activeTicket.issueType} • Trạng thái: ${activeTicket.status}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Builder(
              builder: (context) {
                final linkedOrd = _store.orders
                    .where((o) => o.trackingCode == activeTicket.orderId)
                    .firstOrNull;
                if (linkedOrd == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Đơn liên kết: ${linkedOrd.trackingCode} (${linkedOrd.status.displayName}) • Khách: ${linkedOrd.customerName} • TX: ${linkedOrd.assignedDriverName ?? "Chưa có TX"}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          _store.selectCustomerOrder(linkedOrd.trackingCode);
                          _store.selectDriverOrder(linkedOrd.trackingCode);
                          _rebuildAdminUi(() => _selectedScreenIndex = 8);
                        },
                        icon: const Icon(
                          Icons.local_shipping_outlined,
                          size: 15,
                        ),
                        label: Text(
                          'Điều phối đơn ${linkedOrd.trackingCode}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            if (activeTicket.evidenceFiles.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Bằng chứng đính kèm:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  ...activeTicket.evidenceFiles.map(
                    (f) => Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.attach_file, size: 14),
                      label: Text(f, style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            ...activeTicket.replies.map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• $r', style: const TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _replyTicketCtrl,
              enabled: canResolveComplaint,
              decoration: const InputDecoration(
                labelText: 'Phản hồi của Quản trị viên / Phương án đền bù',
              ),
            ),
            if (canResolveComplaint)
              SupportAiSummary(
                key: ValueKey(activeTicket.ticketCode),
                text: '${activeTicket.issueType}\n${activeTicket.description}',
                onApply: (text) => _replyTicketCtrl.text = text,
              ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      canResolveComplaint &&
                          activeTicket.status != 'Đã giải quyết'
                      ? () {
                          final note = _replyTicketCtrl.text.trim().isNotEmpty
                              ? _replyTicketCtrl.text.trim()
                              : 'Đang xác minh lộ trình GPS & bằng chứng POD với Tài xế.';
                          _store.replyComplaint(
                            activeTicket.ticketCode,
                            note,
                            'Đang xử lý',
                          );
                          _replyTicketCtrl.clear();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Đã cập nhật tiến độ "Đang xử lý" cho ticket ${activeTicket.ticketCode}!',
                              ),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.pending_actions_outlined, size: 16),
                  label: const Text('Cập nhật: Đang xử lý'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                  onPressed: canResolveComplaint
                      ? () {
                          if (_replyTicketCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Vui lòng nhập nội dung phản hồi / phương án đền bù trước khi đóng khiếu nại!',
                                ),
                              ),
                            );
                            return;
                          }
                          _store.replyComplaint(
                            activeTicket.ticketCode,
                            _replyTicketCtrl.text,
                            'Đã giải quyết',
                          );
                          _replyTicketCtrl.clear();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Đã phản hồi và đóng khiếu nại ${activeTicket.ticketCode} (${activeTicket.orderId})!',
                              ),
                            ),
                          );
                        }
                      : null,
                  child: const Text('Phản hồi & Đóng khiếu nại'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// UC29: Đối soát Tài chính & Phê duyệt Rút tiền (Chuẩn uc29_tai_chinh_1791015185346.jpg)
  Widget _buildFinancialWithdrawalApprovalView() {
    final canViewTransactions = _store.hasAdminPermission(
      'Tài chính: Giao dịch',
    );
    final canApprovePayout = _store.hasAdminPermission('Tài chính: Thanh toán');
    if (!canViewTransactions) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Đối soát Tài chính & Duyệt Lệnh Rút tiền',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                '🔒 Vai trò điều hành hiện tại không có quyền "Tài chính: Giao dịch" để truy cập sổ cái rút tiền.',
                style: TextStyle(color: AppColors.danger),
              ),
            ],
          ),
        ),
      );
    }
    final payoutRequests = _store.withdrawalRequests.where((req) {
      final isLedgerEntry =
          req.id.startsWith('TOPUP-') ||
          req.id.startsWith('EARN-') ||
          req.id.startsWith('RET-') ||
          req.id.startsWith('TIP-') ||
          req.id.startsWith('COMP-') ||
          req.id.startsWith('REFUND-');
      return !isLedgerEntry &&
          (req.ownerRole == 'Tài xế' || req.ownerRole == 'Cửa hàng (COD)');
    }).toList();
    final totalDriverEscrow = _store.drivers.fold<double>(
      0.0,
      (s, d) => s + d.walletBalance,
    );
    final totalMerchantCodPool = _store.merchantApplicants.fold<double>(
      0.0,
      (s, m) => s + m.codBalance,
    );
    final totalPendingPayout = payoutRequests
        .where((r) => r.status == 'Chờ duyệt')
        .fold<double>(0.0, (s, r) => s + r.amount);
    final totalApprovedPayout = payoutRequests
        .where((r) => r.status == 'Đã duyệt')
        .fold<double>(0.0, (s, r) => s + r.amount);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đối soát Tài chính & Duyệt Lệnh Rút tiền',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (!canApprovePayout)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '🔒 Vai trò hiện tại không có quyền "Tài chính: Thanh toán" (Cấu hình tại mục Phân quyền RBAC).',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.shield_outlined, size: 16),
                  label: Text(
                    'Tổng ví ký quỹ Tài xế: ${CurrencyFormatter.formatVnd(totalDriverEscrow)}',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.storefront_outlined, size: 16),
                  label: Text(
                    'Tổng quỹ COD Cửa hàng: ${CurrencyFormatter.formatVnd(totalMerchantCodPool)}',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.hourglass_top_rounded, size: 16),
                  label: Text(
                    'Chờ giải ngân: ${CurrencyFormatter.formatVnd(totalPendingPayout)}',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    'Đã giải ngân: ${CurrencyFormatter.formatVnd(totalApprovedPayout)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (payoutRequests.isEmpty)
              const Text(
                'Hiện chưa có lệnh rút tiền nào từ Tài xế hoặc Cửa hàng.',
              )
            else
              ...payoutRequests.map(
                (req) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${req.ownerName} (${req.ownerRole}) • ${CurrencyFormatter.formatVnd(req.amount)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${req.bankName} (${req.accountMasked}) • Ngày: ${req.requestDate} • Trạng thái: ${req.status}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          TextButton(
                            onPressed:
                                canApprovePayout && req.status == 'Chờ duyệt'
                                ? () {
                                    _store.updateWithdrawalStatus(
                                      req.id,
                                      'Đã duyệt',
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Đã duyệt lệnh rút ${req.id} (${CurrencyFormatter.formatVnd(req.amount)}) cho ${req.ownerName}!',
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            child: const Text('Duyệt lệnh'),
                          ),
                          TextButton(
                            onPressed:
                                canApprovePayout && req.status == 'Chờ duyệt'
                                ? () {
                                    _store.updateWithdrawalStatus(
                                      req.id,
                                      'Từ chối',
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Đã từ chối lệnh rút ${req.id} và hoàn tiền về ví ${req.ownerName}.',
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            child: const Text(
                              'Từ chối',
                              style: TextStyle(color: AppColors.danger),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// UC43: Quản lý & Điều phối Đơn hàng Thủ công (Chuẩn uc43_don_hang_1791094600371.jpg)
  Widget _buildManualOrderDispatchView() {
    final canViewOrders = _store.hasAdminPermission('Đơn: Xem');
    final canCreateOrder = _store.hasAdminPermission('Đơn: Tạo');
    final canEditOrder = _store.hasAdminPermission('Đơn: Sửa');
    final canCancelOrder = _store.hasAdminPermission('Đơn: Xóa');
    if (!canViewOrders) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quản lý & Điều phối Đơn hàng Thủ công',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                '🔒 Vai trò điều hành hiện tại không có quyền "Đơn: Xem" để truy cập danh sách điều phối.',
                style: TextStyle(color: AppColors.danger),
              ),
            ],
          ),
        ),
      );
    }

    final eligibleDrivers = _store.drivers.where((d) {
      if (d.approvalStatus != 'Đã duyệt' ||
          !d.isOnline ||
          d.walletBalance < 200000) {
        return false;
      }
      final linkedUser = _store.findUserByPhone(d.phone);
      return linkedUser == null || linkedUser.status == 'ACTIVE';
    }).toList();
    final safeDispDrvIdx = eligibleDrivers.isEmpty
        ? 0
        : _selectedDispatchDriverIndex.clamp(0, eligibleDrivers.length - 1);
    final selectedDispatchDriver = eligibleDrivers.isNotEmpty
        ? eligibleDrivers[safeDispDrvIdx]
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
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
                  'Quản lý & Điều phối Đơn hàng Thủ công',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.violet,
                  ),
                  onPressed: canCreateOrder
                      ? () => _showAdminQuickCreateOrderDialog(context)
                      : null,
                  icon: const Icon(Icons.add_box_outlined, size: 16),
                  label: const Text(
                    'Tạo vận đơn điều phối',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (eligibleDrivers.isNotEmpty) ...[
              const Text(
                'Chọn Tài xế đủ điều kiện (Đã duyệt • Online • Ký quỹ >= 200k) để gán / điều phối lại:',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: eligibleDrivers.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final drv = entry.value;
                  final isSel = idx == safeDispDrvIdx;
                  return ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${drv.fullName} (${drv.vehicleType} • ${drv.licensePlate} • ★${drv.rating.toStringAsFixed(1)})',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isSel ? Colors.white : AppColors.ink,
                      ),
                    ),
                    selected: isSel,
                    selectedColor: AppColors.violet,
                    onSelected: (_) => _rebuildAdminUi(
                      () => _selectedDispatchDriverIndex = idx,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
            if (_store.orders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Chưa có vận đơn nào cần điều phối.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else
              ..._store.orders.map(
                (ord) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    border: Border.all(color: AppColors.divider),
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
                            '${ord.trackingCode} (${ord.serviceType.displayName}) • ${ord.pickupAddress} -> ${ord.dropoffAddress}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Trạng thái: ${ord.paymentStatus == "RETURNED" ? "Đã hoàn kho" : ord.status.displayName} • Tài xế: ${ord.assignedDriverName ?? "Chưa có tài xế"} (${ord.assignedDriverPlate ?? "--"})',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () =>
                                _showAdminOrderTimelineAndPodDialog(
                                  context,
                                  ord,
                                ),
                            icon: const Icon(Icons.timeline_rounded, size: 15),
                            label: const Text(
                              'Chi tiết & POD',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          if (selectedDispatchDriver != null &&
                              ord.status != OrderStatus.delivered &&
                              ord.status != OrderStatus.cancelled &&
                              ord.status != OrderStatus.returning &&
                              ord.paymentStatus != 'RETURNED')
                            OutlinedButton.icon(
                              onPressed: canEditOrder
                                  ? () {
                                      final ok = _store
                                          .adminAssignOrReassignDriver(
                                            trackingCode: ord.trackingCode,
                                            driver: selectedDispatchDriver,
                                          );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          backgroundColor: ok
                                              ? null
                                              : AppColors.danger,
                                          content: Text(
                                            ok
                                                ? 'Đã gán đơn ${ord.trackingCode} cho tài xế ${selectedDispatchDriver.fullName} (${selectedDispatchDriver.licensePlate})!'
                                                : 'Không thể gán ${selectedDispatchDriver.fullName}: kiểm tra loại xe phù hợp (${ord.serviceType.displayName}) và số dư ký quỹ >= 200.000đ.',
                                          ),
                                        ),
                                      );
                                    }
                                  : null,
                              icon: const Icon(
                                Icons.person_pin_circle_outlined,
                                size: 16,
                              ),
                              label: Text(
                                'Gán: ${selectedDispatchDriver.fullName}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          if (ord.status.canTransitionTo(OrderStatus.cancelled))
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                              ),
                              onPressed: canCancelOrder
                                  ? () => _showAdminCancelOrderDialog(
                                      context,
                                      ord,
                                    )
                                  : null,
                              icon: const Icon(Icons.cancel_outlined, size: 15),
                              label: const Text(
                                'Hủy đơn',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ElevatedButton(
                            onPressed:
                                canEditOrder &&
                                    ord.status != OrderStatus.delivered &&
                                    ord.status != OrderStatus.cancelled
                                ? () {
                                    if (ord.status == OrderStatus.inTransit) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          backgroundColor: AppColors.danger,
                                          content: Text(
                                            'Đơn ${ord.trackingCode} đang giao trên đường. Việc hoàn tất giao hàng bắt buộc Tài xế chụp ảnh POD và xác thực OTP 4 số của khách tại điểm giao (<= 100m)!',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    if (ord.status.canTransitionTo(
                                      OrderStatus.accepted,
                                    )) {
                                      if (selectedDispatchDriver == null) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            backgroundColor: AppColors.danger,
                                            content: Text(
                                              'Hiện không có tài xế Online đủ điều kiện ký quỹ >= 200.000đ để gán đơn!',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      final ok = _store
                                          .adminAssignOrReassignDriver(
                                            trackingCode: ord.trackingCode,
                                            driver: selectedDispatchDriver,
                                          );
                                      if (!ok) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            backgroundColor: AppColors.danger,
                                            content: Text(
                                              'Không thể gán ${selectedDispatchDriver.fullName} cho đơn ${ord.trackingCode} (${ord.serviceType.displayName} yêu cầu phương tiện tương thích).',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                    } else {
                                      _store.driverAdvanceOrderStatus(
                                        ord.trackingCode,
                                        allowAdminOverride: true,
                                      );
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Đã điều phối đơn ${ord.trackingCode} → Trạng thái: ${ord.paymentStatus == "RETURNED" ? "Đã hoàn kho" : ord.status.displayName} (${ord.assignedDriverName ?? _store.activeDriverName})',
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            child: Text(
                              ord.paymentStatus == 'RETURNED'
                                  ? 'Đã hoàn kho'
                                  : ord.status == OrderStatus.delivered
                                  ? 'Đã hoàn tất'
                                  : ord.status == OrderStatus.cancelled
                                  ? 'Đã hủy'
                                  : ord.status == OrderStatus.failed
                                  ? 'Giao lại chuyến hàng'
                                  : ord.status == OrderStatus.returning
                                  ? 'Hoàn tất trả kho'
                                  : ord.status == OrderStatus.inTransit
                                  ? 'Đang giao (Chờ POD & OTP)'
                                  : ord.status.canTransitionTo(
                                      OrderStatus.accepted,
                                    )
                                  ? 'Gán tài xế ngay'
                                  : 'Chuyển bước lấy hàng',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAdminCancelOrderDialog(
    BuildContext context,
    ActiveOrderRecord ord,
  ) {
    final reasonCtrl = TextEditingController();
    Animation<double>? dialogRouteAnim;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        dialogRouteAnim ??= ModalRoute.of(dialogCtx)?.animation;
        return AlertDialog(
          title: Text(
            'Hủy đơn hàng ${ord.trackingCode}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          content: TextField(
            controller: reasonCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Lý do hủy đơn (lưu vào lịch sử vận đơn)',
              hintText: 'Nhập lý do xác minh vận hành để hủy đơn...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Đóng'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
              ),
              onPressed: () {
                if (reasonCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Vui lòng nhập lý do hủy đơn vận hành trước khi xác nhận!',
                      ),
                    ),
                  );
                  return;
                }
                final reason = 'Admin: ${reasonCtrl.text.trim()}';
                final ok = _store.cancelOrder(ord.trackingCode, reason);
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: ok ? null : AppColors.danger,
                    content: Text(
                      ok
                          ? 'Đã hủy đơn ${ord.trackingCode} và cập nhật hoàn phí/lịch sử!'
                          : 'Không thể hủy đơn ${ord.trackingCode} ở trạng thái ${ord.status.displayName}.',
                    ),
                  ),
                );
              },
              child: const Text('Xác nhận hủy đơn'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      SecurityAndBarcodeUtils.disposeControllersAfterDialog([
        reasonCtrl,
      ], dialogRouteAnim);
    });
  }

  void _showAdminQuickCreateOrderDialog(BuildContext context) {
    final pickupCtrl = TextEditingController();
    final dropoffCtrl = TextEditingController();
    final recipientCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final pkgCtrl = TextEditingController();
    final codCtrl = TextEditingController();
    DeliveryServiceType selectedSvc = DeliveryServiceType.standard;
    Animation<double>? dialogRouteAnim;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        dialogRouteAnim ??= ModalRoute.of(dialogCtx)?.animation;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) => AlertDialog(
            title: const Text(
              'Tạo vận đơn điều phối trực tiếp',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: pickupCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ lấy hàng',
                      hintText: 'Nhập địa chỉ kho / điểm lấy hàng...',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: dropoffCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ giao hàng',
                      hintText: 'Nhập địa chỉ người nhận...',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: recipientCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên người nhận',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'SĐT người nhận',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pkgCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mô tả kiện hàng',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: codCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Thu hộ COD (VNĐ, để trống nếu 0đ)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: DeliveryServiceType.values
                        .map(
                          (st) => ChoiceChip(
                            label: Text(
                              st.displayName,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            selected: selectedSvc == st,
                            onSelected: (_) =>
                                setDialogState(() => selectedSvc = st),
                          ),
                        )
                        .toList(),
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
                onPressed: () {
                  final pickup = pickupCtrl.text.trim();
                  final dropoff = dropoffCtrl.text.trim();
                  final recName = recipientCtrl.text.trim();
                  final recPhone = phoneCtrl.text.trim();
                  if (pickup.isEmpty ||
                      dropoff.isEmpty ||
                      recName.isEmpty ||
                      recPhone.length < 9) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Vui lòng nhập đầy đủ địa chỉ lấy/giao, tên và SĐT người nhận hợp lệ!',
                        ),
                      ),
                    );
                    return;
                  }
                  final pickupPt =
                      SmartDispatchEngine.resolveAddressToCoordinate(
                        pickup,
                        fallback: const GeoPoint(
                          latitude: 10.7765,
                          longitude: 106.6980,
                        ),
                      );
                  final dropoffPt =
                      SmartDispatchEngine.resolveAddressToCoordinate(
                        dropoff,
                        fallback: const GeoPoint(
                          latitude: 10.7850,
                          longitude: 106.7050,
                        ),
                      );
                  final restricted = _store.findActiveRestrictedZoneForRoute(
                    pickupPt,
                    dropoffPt,
                  );
                  if (restricted != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: AppColors.danger,
                        content: Text(
                          'Điểm lấy/giao nằm trong vùng hạn chế "${restricted.zoneName}". Không thể tạo đơn!',
                        ),
                      ),
                    );
                    return;
                  }
                  final codVal =
                      double.tryParse(
                        codCtrl.text.trim().replaceAll(RegExp(r'[.,\s]'), ''),
                      ) ??
                      0.0;
                  final created = _store.createNewOrder(
                    pickupAddress: pickup,
                    dropoffAddress: dropoff,
                    recipientName: recName,
                    recipientPhone: recPhone,
                    packageDescription: pkgCtrl.text.trim().isNotEmpty
                        ? pkgCtrl.text.trim()
                        : 'Hàng điều phối trung tâm',
                    weightKg: 1.5,
                    dimensionsCm: '25x20x15',
                    serviceType: selectedSvc,
                    codAmount: codVal,
                    paymentMethod: 'Tiền mặt (Người gửi trả phí)',
                    isPrepaidConfirmed: false,
                    customCustomerName: 'Khách điều phối trung tâm',
                    customPickupLocation: pickupPt,
                    customDropoffLocation: dropoffPt,
                  );
                  Navigator.of(dialogCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã khởi tạo vận đơn điều phối ${created.trackingCode} (${CurrencyFormatter.formatVnd(created.totalAmount)})!',
                      ),
                    ),
                  );
                },
                child: const Text('Tạo đơn'),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      SecurityAndBarcodeUtils.disposeControllersAfterDialog([
        pickupCtrl,
        dropoffCtrl,
        recipientCtrl,
        phoneCtrl,
        pkgCtrl,
        codCtrl,
      ], dialogRouteAnim);
    });
  }

  void _showAdminOrderTimelineAndPodDialog(
    BuildContext context,
    ActiveOrderRecord ord,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          'Hồ sơ Vận đơn & POD: ${ord.trackingCode}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '• Người gửi: ${ord.customerName} • Dịch vụ: ${ord.serviceType.displayName}',
                ),
                Text(
                  '• Người nhận: ${ord.recipientName} (${ord.recipientPhone})',
                ),
                Text(
                  '• Lộ trình: ${ord.pickupAddress} → ${ord.dropoffAddress} (${(ord.distanceMeters / 1000).toStringAsFixed(1)} km)',
                ),
                Text(
                  '• Tổng cước: ${CurrencyFormatter.formatVnd(ord.totalAmount)} • COD: ${CurrencyFormatter.formatVnd(ord.codAmount)} • TT: ${ord.paymentStatus}',
                ),
                if (ord.podImageNote != null &&
                    ord.podImageNote!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '• Bằng chứng POD: ${ord.podImageNote}',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const Divider(height: 18),
                const Text(
                  'Nhật ký chuyển trạng thái (order_status_histories):',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(height: 6),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _store.fetchOrderStatusHistories(ord.id),
                  builder: (ctx, snap) {
                    final rows = snap.data ?? const <Map<String, dynamic>>[];
                    if (rows.isEmpty) {
                      return Text(
                        '• Trạng thái hiện hành: ${ord.status.displayName}',
                        style: const TextStyle(fontSize: 12),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: rows.map((r) {
                        final st = r['status']?.toString() ?? '';
                        final note = r['note']?.toString() ?? '';
                        final ts = (r['updated_at'] ?? r['changed_at'] ?? '')
                            .toString();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• [$st] $note ($ts)',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  /// Quản lý Vùng hoạt động Geofencing Polygon (Tương tác chấm đỉnh trên bản đồ)
  Widget _buildGeofencePolygonZonesView() {
    final canEditGeofence = _store.hasAdminPermission('Hệ thống: Cài đặt');
    String zoneTypeLabel(String typeCode) {
      switch (typeCode) {
        case 'CENTER_ZONE':
          return 'Vùng trung tâm';
        case 'RESTRICTED_ZONE':
          return 'Vùng hạn chế / Cấm tải';
        default:
          return 'Vùng phụ phí';
      }
    }

    Future<void> inspectGeofencePoint(
      GeoPoint pt, {
      String? customPlace,
    }) async {
      final placeLabel =
          customPlace ?? await SmartDispatchEngine.reverseGeocodeCoordinate(pt);
      if (!mounted) return;
      final matched = _store.geofenceZones
          .where((z) => z.isActive && GeoMath.isPointInPolygon(pt, z.boundary))
          .firstOrNull;
      _rebuildAdminUi(() {
        _testLatCtrl.text = pt.latitude.toStringAsFixed(6);
        _testLngCtrl.text = pt.longitude.toStringAsFixed(6);
        _geofenceCheckResult = matched != null
            ? 'Tọa độ ($placeLabel) thuộc vùng: ${matched.zoneName} (${zoneTypeLabel(matched.zoneType)} • ${matched.zoneType == "RESTRICTED_ZONE" ? "Chặn tạo đơn / cấm tải" : "Phụ phí: ${CurrencyFormatter.formatVnd(matched.surchargeRate)}"})'
            : 'Tọa độ ($placeLabel) nằm ngoài các vùng Geofence đặc biệt đang bật.';
      });
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quản lý Vùng Hoạt động Geofencing',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (!canEditGeofence)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '🔒 Vai trò hiện tại không có quyền "Hệ thống: Cài đặt" để lưu hoặc bật/tắt vùng Geofence.',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Chế độ tương tác bản đồ:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.polyline_rounded, size: 15),
                  label: const Text('Chấm đỉnh Polygon mới'),
                  selected: !_geofenceTapTestMode,
                  onSelected: (_) =>
                      _rebuildAdminUi(() => _geofenceTapTestMode = false),
                ),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.my_location_rounded, size: 15),
                  label: const Text('Kiểm tra điểm trên bản đồ'),
                  selected: _geofenceTapTestMode,
                  onSelected: (_) =>
                      _rebuildAdminUi(() => _geofenceTapTestMode = true),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Map3dPerspectiveWidget(
              height: 540,
              is3dMode: false,
              routePoints: const [],
              focusedCenterPoint: const GeoPoint(
                latitude: 10.7680,
                longitude: 106.7020,
              ),
              geofenceZones: _store.geofenceZones,
              drawnPolygonGeoPoints: _draftPolygonGeoPoints,
              nextTurnInstruction: _geofenceTapTestMode
                  ? 'Chế độ Kiểm tra tọa độ • Chạm lên bản đồ để xác định vùng hoạt động'
                  : 'Chế độ Vẽ Đa giác Địa lý • Đã chấm ${_draftPolygonGeoPoints.length} đỉnh (cần >= 3 đỉnh để lưu)',
              roadName: _draftPolygonGeoPoints.isNotEmpty
                  ? 'Đỉnh gần nhất: (${_draftPolygonGeoPoints.last.latitude.toStringAsFixed(5)}, ${_draftPolygonGeoPoints.last.longitude.toStringAsFixed(5)}) • Lăn chuột để thu phóng'
                  : 'Hiển thị ${_store.geofenceZones.where((z) => z.isActive).length}/${_store.geofenceZones.length} vùng hoạt động • Kéo hoặc lăn chuột để xem toàn TP.HCM',
              onTapGeoPoint: (pt) {
                if (_geofenceTapTestMode) {
                  inspectGeofencePoint(pt);
                  return;
                }
                _rebuildAdminUi(() {
                  _draftPolygonGeoPoints.add(pt);
                });
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            LayoutBuilder(
              builder: (context, constraints) {
                final nameField = TextField(
                  controller: _newZoneNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên vùng Geofence mới',
                    hintText: 'VD: Vùng Phụ phí Khu Công nghệ cao TP. Thủ Đức',
                  ),
                );
                final buttons = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_draftPolygonGeoPoints.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _rebuildAdminUi(
                          () => _draftPolygonGeoPoints.removeLast(),
                        ),
                        icon: const Icon(Icons.undo_rounded, size: 15),
                        label: const Text('Hoàn tác đỉnh'),
                      ),
                    OutlinedButton(
                      onPressed: _draftPolygonGeoPoints.isEmpty
                          ? null
                          : () => _rebuildAdminUi(
                              () => _draftPolygonGeoPoints.clear(),
                            ),
                      child: const Text('Xóa đỉnh'),
                    ),
                    ElevatedButton(
                      onPressed:
                          canEditGeofence && _draftPolygonGeoPoints.length >= 3
                          ? () {
                              final zoneName = _newZoneNameCtrl.text.trim();
                              if (zoneName.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Vui lòng nhập tên vùng Geofence trước khi lưu!',
                                    ),
                                  ),
                                );
                                return;
                              }
                              final vertices = List<GeoPoint>.from(
                                _draftPolygonGeoPoints,
                              );
                              final effectiveFee =
                                  _newZoneType == 'SURCHARGE_ZONE'
                                  ? (_newZoneSurcharge > 0
                                        ? _newZoneSurcharge
                                        : 20000.0)
                                  : 0.0;
                              _store.addCustomGeofenceZone(
                                zoneName: zoneName,
                                zoneType: _newZoneType,
                                surchargeRate: effectiveFee,
                                vertices: vertices,
                              );
                              _rebuildAdminUi(() {
                                _draftPolygonGeoPoints.clear();
                                _newZoneNameCtrl.clear();
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Đã lưu vùng "$zoneName" (${zoneTypeLabel(_newZoneType)} • ${vertices.length} đỉnh tọa độ thực)!',
                                  ),
                                ),
                              );
                            }
                          : null,
                      child: const Text('Lưu vùng mới'),
                    ),
                  ],
                );
                if (constraints.maxWidth < 620) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [nameField, const SizedBox(height: 8), buttons],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: nameField),
                    const SizedBox(width: 8),
                    buttons,
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Loại vùng Geofence:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                ...[
                  ('CENTER_ZONE', 'Vùng trung tâm (0đ)'),
                  ('SURCHARGE_ZONE', 'Vùng phụ phí'),
                  ('RESTRICTED_ZONE', 'Vùng hạn chế / Cấm tải'),
                ].map((zt) {
                  final sel = _newZoneType == zt.$1;
                  return ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(zt.$2, style: const TextStyle(fontSize: 11)),
                    selected: sel,
                    onSelected: (_) => _rebuildAdminUi(() {
                      _newZoneType = zt.$1;
                      if (_newZoneType != 'SURCHARGE_ZONE') {
                        _newZoneSurcharge = 0;
                      } else if (_newZoneSurcharge <= 0) {
                        _newZoneSurcharge = 20000;
                      }
                    }),
                  );
                }),
              ],
            ),
            if (_newZoneType == 'SURCHARGE_ZONE') ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Mức phụ phí vùng mới:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  ...[10000.0, 15000.0, 20000.0, 25000.0, 30000.0].map((fee) {
                    final selected = _newZoneSurcharge == fee;
                    return ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '+${CurrencyFormatter.formatVnd(fee)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: selected,
                      onSelected: (_) =>
                          _rebuildAdminUi(() => _newZoneSurcharge = fee),
                    );
                  }),
                ],
              ),
            ],
            const Divider(),
            if (_store.geofenceZones.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Chưa cấu hình vùng địa lý Geofence nào.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else
              ..._store.geofenceZones.map(
                (z) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${z.zoneName} • ${zoneTypeLabel(z.zoneType)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Phụ phí vùng: ${CurrencyFormatter.formatVnd(z.surchargeRate)} • Số đỉnh tọa độ: ${z.boundary.length}',
                  ),
                  value: z.isActive,
                  onChanged: canEditGeofence
                      ? (v) => _store.toggleGeofenceZone(z.id, v)
                      : null,
                ),
              ),
            const Divider(),
            LayoutBuilder(
              builder: (context, constraints) {
                final latField = TextField(
                  controller: _testLatCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Vĩ độ kiểm tra (Lat)',
                    hintText: 'VD: 10.7725',
                  ),
                );
                final lngField = TextField(
                  controller: _testLngCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Kinh độ kiểm tra (Lng)',
                    hintText: 'VD: 106.6980',
                  ),
                );
                final checkBtn = ElevatedButton(
                  onPressed: () {
                    final lat = double.tryParse(_testLatCtrl.text.trim());
                    final lng = double.tryParse(_testLngCtrl.text.trim());
                    if (lat == null ||
                        lng == null ||
                        lat < -90 ||
                        lat > 90 ||
                        lng < -180 ||
                        lng > 180) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Vui lòng nhập Vĩ độ (-90..90) và Kinh độ (-180..180) hợp lệ hoặc chạm lên bản đồ ở chế độ Kiểm tra điểm!',
                          ),
                        ),
                      );
                      return;
                    }
                    inspectGeofencePoint(
                      GeoPoint(latitude: lat, longitude: lng),
                    );
                  },
                  child: const Text('Kiểm tra tọa độ'),
                );
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: latField),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: lngField),
                        ],
                      ),
                      const SizedBox(height: 8),
                      checkBtn,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: latField),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: lngField),
                    const SizedBox(width: AppSpacing.sm),
                    checkBtn,
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              _geofenceCheckResult,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Gửi Thông báo Hệ thống Hàng loạt (Broadcast Push)
  Widget _buildBroadcastNotificationView() {
    final canBroadcast = _store.hasAdminPermission('Hệ thống: Cài đặt');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Phát Thông báo Hệ thống Hàng loạt',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (!canBroadcast)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '🔒 Vai trò hiện tại không có quyền "Hệ thống: Cài đặt" để phát thông báo hàng loạt.',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children:
                  [
                    'Tất cả người dùng',
                    'Khách hàng',
                    'Tài xế',
                    'Cửa hàng B2B',
                  ].map((g) {
                    return ChoiceChip(
                      label: Text(g),
                      selected: _broadcastTarget == g,
                      onSelected: (_) =>
                          _rebuildAdminUi(() => _broadcastTarget = g),
                    );
                  }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _broadcastTitleCtrl,
              decoration: const InputDecoration(
                labelText: 'Tiêu đề & Nội dung thông báo hệ thống',
                hintText: 'Nhập nội dung thông báo gửi đến nhóm người dùng...',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                ),
                onPressed: canBroadcast
                    ? () {
                        if (_broadcastTitleCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Vui lòng nhập tiêu đề & nội dung thông báo trước khi phát!',
                              ),
                            ),
                          );
                          return;
                        }
                        _store.broadcastSystemNotification(
                          title: _broadcastTitleCtrl.text.trim(),
                          targetGroup: _broadcastTarget,
                        );
                        _broadcastTitleCtrl.clear();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Đã phát thông báo tới nhóm: $_broadcastTarget!',
                            ),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Phát thông báo ngay'),
              ),
            ),
            const Divider(height: 24),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  'Lịch sử Thông báo Hệ thống đã phát (${_store.notifications.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                if (_store.notifications.any((n) => !n.isRead))
                  TextButton.icon(
                    onPressed: () => _store.markAllNotificationsAsRead(),
                    icon: const Icon(Icons.done_all_rounded, size: 16),
                    label: const Text(
                      'Đánh dấu đã đọc tất cả',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_store.notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Chưa có thông báo hệ thống nào được phát.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else
              ..._store.notifications.map(
                (n) => InkWell(
                  onTap: () => _store.markNotificationAsRead(n.id),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: n.isRead ? Colors.white : const Color(0xFFF5F1E8),
                      border: Border.all(
                        color: const Color(0xFF15131E),
                        width: n.isRead ? 1.0 : 1.4,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          n.isRead
                              ? Icons.notifications_none_outlined
                              : Icons.notifications_active_outlined,
                          size: 18,
                          color: n.isRead
                              ? AppColors.textSecondary
                              : AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                n.title,
                                style: TextStyle(
                                  fontWeight: n.isRead
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Nhóm nhận: ${n.targetGroup} • Phân loại: ${n.category} • ${n.timeAgo}${n.isRead ? " • Đã đọc" : " • Chưa đọc"}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Phân quyền Quản trị viên (RBAC Permission Matrix)
  Widget _buildRbacPermissionMatrixView() {
    if (_store.rbacRoles.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Chưa có vai trò phân quyền RBAC nào được cấu hình trong hệ thống.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final canManageSecurity = _store.hasAdminPermission('Hệ thống: Bảo mật');
    final canViewAuditLogs = _store.hasAdminPermission('Hệ thống: Nhật ký');
    final safeRoleIdx = _selectedRbacRoleIndex.clamp(
      0,
      _store.rbacRoles.length - 1,
    );
    final activeRole = _store.rbacRoles[safeRoleIdx];
    final isCurrentSessionRole =
        activeRole.roleName == _store.currentAdminRoleName;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ma trận Phân quyền Quản trị viên (RBAC)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  avatar: const Icon(Icons.verified_user_outlined, size: 15),
                  label: Text(
                    'Phiên điều hành hiện tại: ${_store.currentAdminRoleName}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!isCurrentSessionRole && canManageSecurity)
                  OutlinedButton.icon(
                    onPressed: () {
                      final ok = _store.setAdminActiveRole(activeRole.roleName);
                      if (!ok) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã chuyển phiên điều hành sang vai trò "${activeRole.roleName}" để kiểm chứng quyền hạn!',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.switch_account_outlined, size: 15),
                    label: Text(
                      'Chuyển phiên sang "${activeRole.roleName}"',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (_store.currentAdminRoleName != 'Super Admin')
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.violet,
                    ),
                    onPressed: () {
                      if (canManageSecurity ||
                          _store.activeAuthenticatedUser == null) {
                        _store.setAdminActiveRole('Super Admin');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Đã khôi phục phiên điều hành về "Super Admin" (Toàn quyền hệ thống)!',
                            ),
                          ),
                        );
                        return;
                      }
                      _showRestoreSuperAdminPasswordDialog(context);
                    },
                    icon: const Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 15,
                    ),
                    label: const Text(
                      'Khôi phục Super Admin',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            if (!canManageSecurity)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  '🔒 Phiên hiện tại không có quyền "Hệ thống: Bảo mật". Bấm "Khôi phục Super Admin" (xác thực mật khẩu quản trị) để chỉnh sửa ma trận quyền hoặc kết nối máy chủ đám mây.',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Chọn nhóm quyền cần xem / cấu hình trong ma trận:',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: List.generate(_store.rbacRoles.length, (index) {
                final r = _store.rbacRoles[index];
                return ChoiceChip(
                  label: Text(r.roleName),
                  selected: safeRoleIdx == index,
                  onSelected: (_) {
                    _rebuildAdminUi(() => _selectedRbacRoleIndex = index);
                  },
                );
              }),
            ),
            const Divider(),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: activeRole.permissions.entries.map((entry) {
                final isLockedSuperSecurity =
                    activeRole.roleName == 'Super Admin' &&
                    entry.key == 'Hệ thống: Bảo mật';
                return FilterChip(
                  label: Text(entry.key),
                  selected: entry.value,
                  onSelected: canManageSecurity && !isLockedSuperSecurity
                      ? (v) => _store.toggleRbacPermission(
                          activeRole.roleName,
                          entry.key,
                          v,
                        )
                      : null,
                );
              }).toList(),
            ),
            const Divider(height: 24),
            Text(
              'Kết nối Máy chủ Cơ sở dữ liệu Đám mây (Supabase)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _supabaseUrlCtrl,
              enabled: canManageSecurity,
              decoration: const InputDecoration(
                labelText: 'SUPABASE_URL (Project URL)',
                hintText: 'https://<project-ref>.supabase.co',
                prefixIcon: Icon(Icons.cloud_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _supabaseAnonKeyCtrl,
              enabled: canManageSecurity,
              decoration: const InputDecoration(
                labelText: 'SUPABASE_ANON_KEY (Public API Key)',
                prefixIcon: Icon(Icons.vpn_key_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  _store.lastSyncStatusMessage,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: canManageSecurity
                      ? () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final msg = await _store
                              .configureAndSyncSupabaseCloud(
                                url: _supabaseUrlCtrl.text,
                                anonKey: _supabaseAnonKeyCtrl.text,
                              );
                          if (!context.mounted) return;
                          messenger.showSnackBar(SnackBar(content: Text(msg)));
                        }
                      : null,
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Kết nối & Đồng bộ dữ liệu'),
                ),
              ],
            ),
            const Divider(height: 24),
            if (canManageSecurity) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      _rebuildAdminUi(() => _selectedScreenIndex = 13),
                  icon: const Icon(Icons.hub_outlined),
                  label: const Text('API & Dịch vụ'),
                ),
              ),
              const Divider(height: 24),
            ],
            Text(
              'Nhật ký Kiểm toán Hệ thống (Audit Logs)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            if (!canViewAuditLogs)
              const Text(
                '🔒 Vai trò điều hành hiện tại không có quyền "Hệ thống: Nhật ký" để xem lịch sử kiểm toán.',
                style: TextStyle(color: AppColors.danger, fontSize: 12),
              )
            else if (_store.systemAuditLogs.isEmpty)
              const Text(
                'Chưa phát sinh bản ghi kiểm toán mới trong phiên hiện tại.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              )
            else
              ..._store.systemAuditLogs.take(12).map((entry) {
                final action = entry['action']?.toString() ?? 'ACTION';
                final actor = entry['actor']?.toString() ?? 'SYSTEM';
                final ts = entry['timestamp']?.toString() ?? '';
                final summary = entry['summary']?.toString() ?? '';
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    '[$action] • Thực hiện: $actor • $ts\n$summary',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildCommercialOperationsView() {
    final future = Future.wait<List<Map<String, dynamic>>>([
      _store.scheduledOrders(),
      _store.pendingWebhookDeliveries(),
      _store.paymentLedgerEntries(),
      _store.auditLogEntries(),
    ]);
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: future,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <List<Map<String, dynamic>>>[];
        final scheduled = rows.isNotEmpty
            ? rows[0]
            : const <Map<String, dynamic>>[];
        final webhooks = rows.length > 1
            ? rows[1]
            : const <Map<String, dynamic>>[];
        final ledger = rows.length > 2
            ? rows[2]
            : const <Map<String, dynamic>>[];
        final audits = rows.length > 3
            ? rows[3]
            : const <Map<String, dynamic>>[];
        final pendingSchedules = scheduled
            .where((row) => row['status'] == 'PENDING')
            .length;
        final pendingWebhooks = webhooks.length;
        final ledgerTotal = ledger.fold<double>(
          0,
          (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Vận hành thương mại',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                OutlinedButton.icon(
                  onPressed: snapshot.connectionState == ConnectionState.waiting
                      ? null
                      : () async {
                          final delivered = await _store
                              .processDueWebhookDeliveries();
                          if (!context.mounted) return;
                          _rebuildAdminUi(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Đã xử lý $delivered webhook đến hạn.',
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.sync_rounded, size: 17),
                  label: const Text('Chạy retry webhook'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Theo dõi đơn đặt lịch, giao nhận đa điểm, thanh toán idempotency, webhook và nhật ký kiểm toán trên cùng một màn hình.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 760 ? 4 : 2;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.4,
                  children: [
                    _commercialMetric(
                      'Đặt lịch chờ',
                      '$pendingSchedules',
                      Icons.event_available_outlined,
                    ),
                    _commercialMetric(
                      'Webhook chờ retry',
                      '$pendingWebhooks',
                      Icons.webhook_outlined,
                    ),
                    _commercialMetric(
                      'Bút toán',
                      ledger.length.toString(),
                      Icons.account_balance_wallet_outlined,
                    ),
                    _commercialMetric(
                      'Tổng ledger',
                      CurrencyFormatter.formatVnd(ledgerTotal),
                      Icons.payments_outlined,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            _commercialSection(
              title: 'Webhook đang chờ',
              icon: Icons.webhook_outlined,
              child: webhooks.isEmpty
                  ? const Text(
                      'Không có webhook đến hạn.',
                      style: TextStyle(color: AppColors.textSecondary),
                    )
                  : Column(
                      children: webhooks.take(8).map((row) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.sync_problem_outlined,
                            color: AppColors.pink,
                          ),
                          title: Text(
                            '${row['event_type']} • ${row['aggregate_id']}',
                          ),
                          subtitle: Text(
                            '${row['endpoint_url']} • lần thử ${row['attempt_count'] ?? 0}',
                          ),
                          trailing: Text(
                            row['status']?.toString() ?? 'PENDING',
                          ),
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: 14),
            _commercialSection(
              title: 'Nhật ký kiểm toán gần nhất',
              icon: Icons.fact_check_outlined,
              child: audits.isEmpty
                  ? const Text(
                      'Chưa có audit log.',
                      style: TextStyle(color: AppColors.textSecondary),
                    )
                  : Column(
                      children: audits.take(8).map((row) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.history_rounded),
                          title: Text(
                            '${row['action']} • ${row['entity_type']}',
                          ),
                          subtitle: Text(
                            '${row['actor_role'] ?? 'SYSTEM'} • ${row['entity_id'] ?? ''}',
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _commercialMetric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.violet),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _commercialSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Material(type: MaterialType.transparency, child: child),
        ],
      ),
    );
  }

  void _showRestoreSuperAdminPasswordDialog(BuildContext context) {
    final pwdCtrl = TextEditingController();
    Animation<double>? dialogRouteAnim;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        dialogRouteAnim ??= ModalRoute.of(dialogCtx)?.animation;
        return AlertDialog(
          title: const Text(
            'Xác thực khôi phục quyền Super Admin',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          content: TextField(
            controller: pwdCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Mật khẩu tài khoản Quản trị tối cao',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.violet,
              ),
              onPressed: () {
                final ok = _store.setAdminActiveRole(
                  'Super Admin',
                  adminPassword: pwdCtrl.text.trim(),
                  requirePasswordVerification: true,
                );
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppColors.danger,
                      content: Text(
                        'Mật khẩu xác thực Super Admin không chính xác!',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Đã xác thực và khôi phục phiên điều hành về "Super Admin"!',
                    ),
                  ),
                );
              },
              child: const Text('Xác nhận'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      SecurityAndBarcodeUtils.disposeControllersAfterDialog([
        pwdCtrl,
      ], dialogRouteAnim);
    });
  }
}
