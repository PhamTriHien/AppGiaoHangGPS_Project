part of 'driver_subsystem_views.dart';

extension _DriverWalletAndAnalyticsViews on _DriverSubsystemEntryState {
  /// UC18: Thu nhập và rút tiền (Khớp 100% anh_sua_lai/uc18_thu_nhap.jpg)
  Widget _buildDriverWalletView() {
    final activeDrv = _store.activeDriverRecord;
    final isApprovedDriver =
        activeDrv != null && activeDrv.approvalStatus == 'Đã duyệt';
    final availableWallet = activeDrv?.walletBalance ?? 0.0;
    final personalOrders = _store.driverPersonalOrders;
    final myTransactions = _store.driverPersonalTransactions;
    final tipByOrderCode = <String, double>{};
    for (final tx in myTransactions) {
      if (tx.id.startsWith('TIP-') && tx.accountMasked.isNotEmpty) {
        tipByOrderCode[tx.accountMasked] =
            (tipByOrderCode[tx.accountMasked] ?? 0.0) + tx.amount;
      }
    }
    double tripDriverEarning(ActiveOrderRecord o) {
      final tipBonus = tipByOrderCode[o.trackingCode] ?? 0.0;
      if (o.paymentStatus == 'RETURNED') {
        return ((o.deliveryFee + o.surchargeFee) * 0.40).roundToDouble() +
            tipBonus;
      }
      if (o.status == OrderStatus.delivered) {
        return ((o.deliveryFee + o.surchargeFee) * 0.80).roundToDouble() +
            tipBonus;
      }
      return 0.0;
    }

    final settledOrders = personalOrders
        .where(
          (o) =>
              o.status == OrderStatus.delivered ||
              o.paymentStatus == 'RETURNED',
        )
        .toList();
    final deliveredOrders = personalOrders
        .where(
          (o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus != 'RETURNED',
        )
        .toList();
    final now = DateTime.now();

    double sumOrdersInDayRange(int minDaysAgo, int maxDaysAgo) {
      return settledOrders
          .where((o) {
            final d = o.daysAgoFrom(now);
            return d >= minDaysAgo && d <= maxDaysAgo;
          })
          .fold<double>(0, (sum, o) => sum + tripDriverEarning(o));
    }

    final todayDeliveredSum = sumOrdersInDayRange(0, 0);
    final weekDeliveredSum = sumOrdersInDayRange(0, 6);
    final monthDeliveredSum = sumOrdersInDayRange(0, 29);
    final periodEarning = _incomePeriod == 'Ngày'
        ? todayDeliveredSum
        : _incomePeriod == 'Tuần'
            ? weekDeliveredSum
            : monthDeliveredSum;

    final List<(String, double)> rawBuckets = _incomePeriod == 'Ngày'
        ? [
            ('3 ngày trước', sumOrdersInDayRange(3, 3)),
            ('2 ngày trước', sumOrdersInDayRange(2, 2)),
            ('Hôm qua', sumOrdersInDayRange(1, 1)),
            ('Hôm nay', todayDeliveredSum),
          ]
        : _incomePeriod == 'Tuần'
            ? [
                ('Tuần -3', sumOrdersInDayRange(21, 27)),
                ('Tuần -2', sumOrdersInDayRange(14, 20)),
                ('Tuần trước', sumOrdersInDayRange(7, 13)),
                ('Tuần này', weekDeliveredSum),
              ]
            : [
                ('Tuần 1', sumOrdersInDayRange(21, 29)),
                ('Tuần 2', sumOrdersInDayRange(14, 20)),
                ('Tuần 3', sumOrdersInDayRange(7, 13)),
                ('7 ngày qua', weekDeliveredSum),
              ];
    final maxW = [
      for (final b in rawBuckets) b.$2,
      1.0,
    ].reduce((a, b) => a > b ? a : b);
    String fmtShort(double v) => v >= 1000000
        ? '${(v / 1000000).toStringAsFixed(2)}M'
        : '${(v / 1000).toStringAsFixed(0)}k';
    double barRatio(double v) => v <= 0 ? 0.03 : (v / maxW).clamp(0.15, 1.0);
    final weeklyBars = [
      for (final b in rawBuckets) (b.$1, barRatio(b.$2), fmtShort(b.$2)),
    ];
    final linkedBankLabel = (activeDrv != null &&
            activeDrv.bankName.trim().isNotEmpty &&
            activeDrv.bankAccount.trim().isNotEmpty)
        ? '${activeDrv.bankName.trim()} - ${activeDrv.bankAccount.trim()}'
        : '';
    final bankOptions = <String>{
      if (linkedBankLabel.isNotEmpty)
        linkedBankLabel
      else
        'Chưa liên kết ngân hàng (Cập nhật tại Hồ sơ KYC)',
    }.toList();
    final effectiveBank = bankOptions.contains(_selectedBank)
        ? _selectedBank
        : bankOptions.first;
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            color: const Color(0xFF14B866),
            child: Column(
              children: [
                const Text(
                  'Thu nhập của tôi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  CurrencyFormatter.formatVnd(periodEarning),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.all(Radius.zero),
                  ),
                  child: Text(
                    'Đã hoàn tất ${deliveredOrders.length}/${personalOrders.length} chuyến • Số dư khả dụng: ${CurrencyFormatter.formatVnd(availableWallet)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
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
                Row(
                  children: ['Ngày', 'Tuần', 'Tháng'].map((tab) {
                    final selected = _incomePeriod == tab;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Center(child: Text(tab)),
                          selected: selected,
                          selectedColor: const Color(0xFF14B866),
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : const Color(0xFF0F172A),
                            fontWeight: FontWeight.w800,
                          ),
                          onSelected: (_) =>
                              _rebuildDriverUi(() => _incomePeriod = tab),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F7FA),
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: const Color(0xFF0F172A)),
                  ),
                  child: SizedBox(
                    height: 120,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: weeklyBars.map((b) {
                        return Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                b.$3,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF4A4754),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 32,
                                height: 76 * b.$2,
                                decoration: BoxDecoration(
                                  color: b.$2 > 0.9
                                      ? const Color(0xFF14B866)
                                      : const Color(0xFF86EFAC),
                                  borderRadius: BorderRadius.all(Radius.zero),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                b.$1,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: const Color(0xFF0F172A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Số dư ví có thể rút',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF4A4754),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                CurrencyFormatter.formatVnd(
                                  (availableWallet - 200000.0)
                                      .clamp(0.0, double.infinity),
                                ),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                'Tổng số dư: ${CurrencyFormatter.formatVnd(availableWallet)} (Giữ tối thiểu 200.000đ ký quỹ)',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF4A4754),
                                ),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.all(Radius.zero),
                                  ),
                                ),
                                onPressed: () {
                                  if (!isApprovedDriver) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: AppColors.danger,
                                        content: Text(
                                          activeDrv == null
                                              ? 'Vui lòng gửi hồ sơ KYC Tài xế và chờ Admin duyệt trước khi rút tiền!'
                                              : 'Hồ sơ Tài xế đang ở trạng thái "${activeDrv.approvalStatus}". Chỉ tài khoản Đã duyệt KYC mới được rút tiền!',
                                        ),
                                      ),
                                    );
                                    _rebuildDriverUi(
                                      () => _selectedScreenIndex = 0,
                                    );
                                    return;
                                  }
                                  if (linkedBankLabel.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        backgroundColor: AppColors.warning,
                                        content: Text(
                                          'Vui lòng cập nhật Ngân hàng & Số tài khoản nhận tiền tại Hồ sơ KYC trước khi rút tiền!',
                                        ),
                                      ),
                                    );
                                    _rebuildDriverUi(
                                      () => _selectedScreenIndex = 0,
                                    );
                                    return;
                                  }
                                  final amt = double.tryParse(
                                    _withdrawAmountCtrl.text
                                        .trim()
                                        .replaceAll(RegExp(r'\.0+$'), '')
                                        .replaceAll(RegExp(r'[^0-9]'), ''),
                                  );
                                  if (amt == null || amt < 50000) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Vui lòng nhập số tiền rút hợp lệ (Tối thiểu 50.000đ)!',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  final parts = effectiveBank.split(' - ');
                                  final parsedBank = parts.first.trim();
                                  final parsedMask = parts.length > 1
                                      ? parts.last.trim()
                                      : activeDrv.bankAccount;
                                  final ok = _store.requestWithdrawal(
                                    ownerName: activeDrv.fullName,
                                    ownerRole: 'Tài xế',
                                    amount: amt,
                                    bankName: parsedBank,
                                    accountMasked: parsedMask,
                                  );
                                  if (ok) {
                                    _withdrawAmountCtrl.clear();
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        ok
                                            ? 'Đã gửi yêu cầu rút ${CurrencyFormatter.formatVnd(amt)} về $effectiveBank!'
                                            : 'Không thể rút tiền: Số dư ví sau khi rút phải giữ tối thiểu 200.000đ tiền ký quỹ.',
                                      ),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'Rút tiền',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final amountField = TextField(
                            controller: _withdrawAmountCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Số tiền rút / nạp (VNĐ)',
                              hintText: 'VD: 500000',
                            ),
                          );
                          final bankField = DropdownButtonFormField<String>(
                            key: ValueKey(effectiveBank),
                            isExpanded: true,
                            initialValue: effectiveBank,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Ngân hàng liên kết',
                            ),
                            items: bankOptions
                                .map(
                                  (b) => DropdownMenuItem(
                                    value: b,
                                    child: Text(
                                      b,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                _rebuildDriverUi(() => _selectedBank = v);
                              }
                            },
                          );
                          if (constraints.maxWidth < 480) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                amountField,
                                const SizedBox(height: 10),
                                bankField,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: amountField),
                              const SizedBox(width: 10),
                              Expanded(child: bankField),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (myTransactions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Sổ cái biến động số dư & Lệnh rút tiền Ví Tài xế',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...myTransactions.map((w) {
                    final isCredit = !w.id.startsWith('WD-');
                    final isApproved =
                        w.status == 'Đã duyệt' ||
                        w.status == 'Đã chuyển' ||
                        isCredit;
                    final isRejected = w.status == 'Từ chối';
                    final statusColor = isApproved
                        ? const Color(0xFF14B866)
                        : isRejected
                            ? AppColors.danger
                            : const Color(0xFFD97706);
                    final signPrefix = isCredit ? '+' : '-';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFF0F172A)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '#${w.id} • $signPrefix${CurrencyFormatter.formatVnd(w.amount)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: isCredit
                                        ? const Color(0xFF14B866)
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  '${w.ownerRole} • ${w.bankName} (${w.accountMasked}) • ${w.requestDate}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF4A4754),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.14),
                              border: Border.all(color: statusColor),
                            ),
                            child: Text(
                              w.status,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => _rebuildDriverUi(() => _selectedScreenIndex = 9),
                  icon: const Icon(Icons.history),
                  label: const Text('Lịch sử giao hàng'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// UC19: Lịch sử giao hàng của Tài xế (Khớp 100% uc19_lich_su_giao_1791014821234.jpg)
  Widget _buildDriverTripHistoryUc19View() {
    final now = DateTime.now();
    final personalOrders = _store.driverPersonalOrders;
    final filteredTrips = _driverHistoryPeriod == 'Hôm nay'
        ? personalOrders.where((o) => o.daysAgoFrom(now) == 0).toList()
        : _driverHistoryPeriod == 'Tuần này'
            ? personalOrders.where((o) => o.daysAgoFrom(now) <= 6).toList()
            : personalOrders.where((o) => o.daysAgoFrom(now) <= 29).toList();
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF14B866),
            child: const Row(
              children: [
                Icon(Icons.history_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Lịch sử giao hàng',
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
                Wrap(
                  spacing: 8,
                  children: ['Hôm nay', 'Tuần này', 'Tháng này'].map((period) {
                    final selected = _driverHistoryPeriod == period;
                    return ChoiceChip(
                      label: Text(period),
                      selected: selected,
                      selectedColor: const Color(0xFF14B866),
                      labelStyle: TextStyle(
                        color:
                            selected ? Colors.white : const Color(0xFF0F172A),
                        fontWeight: FontWeight.w800,
                      ),
                      onSelected: (_) =>
                          _rebuildDriverUi(() => _driverHistoryPeriod = period),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                if (filteredTrips.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F7FA),
                      border: Border.all(color: const Color(0xFF0F172A)),
                    ),
                    child: Text(
                      'Chưa có chuyến giao hàng nào trong khoảng thời gian "$_driverHistoryPeriod".',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4A4754),
                      ),
                    ),
                  ),
                ...filteredTrips.map((ord) {
                  final isReturned = ord.paymentStatus == 'RETURNED';
                  final isCancelledOrFailed =
                      ord.status == OrderStatus.cancelled ||
                      ord.status == OrderStatus.failed ||
                      ord.status == OrderStatus.returning;
                  final statusDisplay =
                      isReturned ? 'Đã hoàn kho (Phí hoàn 40%)' : ord.status.displayName;
                  final driverNetFee = isReturned
                      ? ((ord.deliveryFee + ord.surchargeFee) * 0.40)
                            .roundToDouble()
                      : isCancelledOrFailed
                          ? 0.0
                          : ((ord.deliveryFee + ord.surchargeFee) * 0.80)
                                .roundToDouble();
                  return InkWell(
                    onTap: () => _rebuildDriverUi(() {
                      _store.selectDriverOrder(ord.trackingCode);
                      _selectedScreenIndex =
                          ord.status == OrderStatus.delivered ? 5 : 3;
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.all(Radius.zero),
                        border: Border.all(color: const Color(0xFF0F172A)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Hình thu nhỏ lộ trình GPS bên trái giống uc19_lich_su_giao_1791014821234.jpg
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.all(Radius.zero),
                              border: Border.all(color: const Color(0xFF86EFAC)),
                            ),
                            child: const Stack(
                              children: [
                                Center(
                                  child: Icon(
                                    Icons.route_rounded,
                                    color: Color(0xFF14B866),
                                    size: 32,
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  child: Icon(
                                    Icons.circle,
                                    size: 8,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                                Positioned(
                                  bottom: 6,
                                  right: 6,
                                  child: Icon(
                                    Icons.location_on,
                                    size: 14,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${ord.trackingCode} • ${ord.createdDateLabel}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isCancelledOrFailed
                                            ? const Color(0xFFFEE2E2)
                                            : const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.all(Radius.zero),
                                      ),
                                      child: Text(
                                        isCancelledOrFailed
                                            ? statusDisplay
                                            : ord.ratingStars != null
                                                ? '${ord.ratingStars}.0 ★'
                                                : 'Chưa ĐG',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: isCancelledOrFailed
                                              ? AppColors.danger
                                              : const Color(0xFFD97706),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Từ: ${ord.pickupAddress}\nĐến: ${ord.dropoffAddress}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF4A4754),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        statusDisplay,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: isCancelledOrFailed
                                              ? AppColors.danger
                                              : const Color(0xFF14B866),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isCancelledOrFailed
                                          ? '0 đ'
                                          : '+ ${CurrencyFormatter.formatVnd(driverNetFee)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14.5,
                                        color: isCancelledOrFailed
                                            ? AppColors.danger
                                            : const Color(0xFF14B866),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// UC20: Báo cáo sự cố trên đường (Khớp 100% anh_sua_lai/uc20_bao_cao_su_co.jpg)
  Widget _buildRoadIncidentReportView() {
    final activeOrder = _store.activeDriverPersonalOrderRecord;
    final resolvedDrvName = (_store.activeDriverRecord?.fullName ??
            _store.activeAuthenticatedUser?.fullName ??
            _store.activeDriverName)
        .trim();
    final drvLower = resolvedDrvName.toLowerCase();
    final driverIncidents = _store.complaints.where((c) {
      if (drvLower.isEmpty) return false;
      return c.driverName.trim().toLowerCase() == drvLower ||
          c.customerName.trim().toLowerCase() == 'tài xế $drvLower';
    }).toList();
    if (activeOrder == null) {
      return Card(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: AppColors.ink, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chưa có chuyến giao để báo cáo sự cố',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tài khoản của bạn hiện chưa nhận cuốc xe nào nên không có vận đơn để gửi báo cáo sự cố trên đường.',
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
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('Mở Nhận đơn mới'),
              ),
            ],
          ),
        ),
      );
    }
    final reasons = [
      'Hàng bị hỏng',
      'Khách không nhận hàng',
      'Tai nạn / Xe hỏng',
      'Kẹt xe nghiêm trọng / Khác',
    ];
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF14B866),
            child: Row(
              children: [
                const Icon(
                  Icons.report_problem_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Báo cáo sự cố (${activeOrder.trackingCode})',
                    style: const TextStyle(
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
                if (_store.driverPersonalOrders.length > 1) ...[
                  const Text(
                    'Chọn vận đơn gặp sự cố',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _store.driverPersonalOrders.map((o) {
                      final isCur = o.trackingCode == activeOrder.trackingCode;
                      return ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${o.trackingCode} (${o.status.displayName})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isCur ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        selected: isCur,
                        selectedColor: const Color(0xFF14B866),
                        onSelected: (_) => _rebuildDriverUi(
                          () => _store.selectDriverOrder(o.trackingCode),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'Chọn loại sự cố',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    reasons.contains(_incidentType)
                        ? _incidentType
                        : reasons.first,
                  ),
                  isExpanded: true,
                  initialValue: reasons.contains(_incidentType)
                      ? _incidentType
                      : reasons.first,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.report_problem_outlined),
                  ),
                  items: reasons
                      .map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(r, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _rebuildDriverUi(() => _incidentType = v);
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Mô tả sự cố',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _incidentNoteCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Nhập chi tiết tình trạng hiện tại...',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Hình ảnh / Tệp minh chứng hiện trường',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF14B866),
                        side: const BorderSide(color: Color(0xFF14B866)),
                      ),
                      onPressed: () async {
                        if (_driverIncidentEvidenceFiles.length >= 4) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Tối đa 4 tệp minh chứng cho mỗi báo cáo sự cố!',
                              ),
                            ),
                          );
                          return;
                        }
                        final picked = await SecurityAndBarcodeUtils
                            .pickLocalDocumentOrImage(
                          dialogTitle:
                              'Đính kèm ảnh hiện trường sự cố (${activeOrder.trackingCode})',
                        );
                        if (picked == null || !mounted) return;
                        _rebuildDriverUi(() {
                          if (!_driverIncidentEvidenceFiles.contains(picked)) {
                            _driverIncidentEvidenceFiles.add(picked);
                          }
                        });
                      },
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: Text(
                        'Chọn tệp minh chứng (${_driverIncidentEvidenceFiles.length}/4)',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    ..._driverIncidentEvidenceFiles.map(
                      (fileName) => InputChip(
                        label: Text(
                          fileName,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        backgroundColor: const Color(0xFFDCFCE7),
                        onDeleted: () => _rebuildDriverUi(() {
                          _driverIncidentEvidenceFiles.remove(fileName);
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFF14B866),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Vị trí hiện tại đã được đính kèm (${_store.activeDriverLocation.latitude.toStringAsFixed(4)}, ${_store.activeDriverLocation.longitude.toStringAsFixed(4)})',
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
                const SizedBox(height: 14),
                SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF14B866),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.zero),
                      ),
                    ),
                    onPressed: activeOrder.status == OrderStatus.delivered ||
                            activeOrder.status == OrderStatus.cancelled ||
                            activeOrder.paymentStatus == 'RETURNED'
                        ? null
                        : () {
                            final rawDesc =
                                _incidentNoteCtrl.text.trim().isEmpty
                                    ? 'Báo cáo sự cố trên lộ trình: $_incidentType'
                                    : _incidentNoteCtrl.text.trim();
                            final gpsTag =
                                '(${_store.activeDriverLocation.latitude.toStringAsFixed(4)}, ${_store.activeDriverLocation.longitude.toStringAsFixed(4)})';
                            final evidenceCopy = List<String>.from(
                              _driverIncidentEvidenceFiles,
                            );
                            final evidenceSuffix = evidenceCopy.isNotEmpty
                                ? ' • Minh chứng: ${evidenceCopy.join(", ")}'
                                : '';
                            _store.addIncidentOrComplaint(
                              orderId: activeOrder.trackingCode,
                              reporterName: 'Tài xế $resolvedDrvName',
                              issueType: _incidentType,
                              description: '$rawDesc$evidenceSuffix • GPS: $gpsTag',
                              evidenceFiles: evidenceCopy,
                            );
                            _incidentNoteCtrl.clear();
                            _rebuildDriverUi(
                              _driverIncidentEvidenceFiles.clear,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Đã gửi báo cáo sự cố đơn ${activeOrder.trackingCode} (${evidenceCopy.length} tệp minh chứng) kèm tọa độ GPS về Trung tâm Điều phối!',
                                ),
                              ),
                            );
                          },
                    child: Text(
                      activeOrder.status == OrderStatus.delivered ||
                              activeOrder.status == OrderStatus.cancelled ||
                              activeOrder.paymentStatus == 'RETURNED'
                          ? 'Đơn đã hoàn tất / Đã hủy (Không thể báo sự cố)'
                          : 'Gửi báo cáo',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                if (driverIncidents.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Text(
                    'Lịch sử báo cáo sự cố & Phản hồi từ Trung tâm Điều phối',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                  ),
                  const SizedBox(height: 8),
                  ...driverIncidents.map(
                    (inc) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F7FA),
                        border: Border.all(color: const Color(0xFF0F172A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${inc.ticketCode} • Đơn ${inc.orderId} • ${inc.issueType} (${inc.status})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                          if (inc.evidenceFiles.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: inc.evidenceFiles
                                  .map(
                                    (f) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      color: const Color(0xFFDCFCE7),
                                      child: Text(
                                        '📎 $f',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 4),
                          ...inc.replies.map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '• $r',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                            ),
                          ),
                        ],
                      ),
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

  /// UC21: Thống kê hoạt động (Dark Mode Analytics - Khớp 100% anh_sua_lai/uc21_thong_ke.jpg)
  Widget _buildDarkModeAnalyticsView() {
    final activeDrv = _store.activeDriverRecord;
    final allOrders = _store.driverPersonalOrders;
    final now = DateTime.now();

    final todayOrders =
        allOrders.where((o) => o.daysAgoFrom(now) == 0).toList();
    final weekOrders =
        allOrders.where((o) => o.daysAgoFrom(now) <= 6).toList();
    final monthOrders =
        allOrders.where((o) => o.daysAgoFrom(now) <= 29).toList();
    final periodOrders = _statsPeriod == 'Hôm nay'
        ? todayOrders
        : (_statsPeriod == 'Tuần này' ? weekOrders : monthOrders);
    final totalOrdersCount = periodOrders.length;
    final safeTotal = totalOrdersCount == 0 ? 1 : totalOrdersCount;
    final deliveredCount = periodOrders
        .where(
          (o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus != 'RETURNED',
        )
        .length;
    final nonCancelledCount = periodOrders
        .where(
          (o) =>
              o.status != OrderStatus.cancelled &&
              o.status != OrderStatus.failed &&
              o.status != OrderStatus.returning &&
              o.paymentStatus != 'RETURNED',
        )
        .length;
    final acceptRatio = activeDrv != null
        ? activeDrv.acceptanceRate
        : (nonCancelledCount / safeTotal).clamp(0.0, 1.0);
    final acceptPct = (acceptRatio * 100).round();
    final hasAcceptanceHistory = (activeDrv != null &&
        activeDrv.totalTrips + activeDrv.rejectedCount > 0) || periodOrders.isNotEmpty;
    final ratedOrders =
        periodOrders.where((o) => o.ratingStars != null).toList();
    final avgRating = ratedOrders.isNotEmpty
        ? (ratedOrders.fold<int>(0, (s, o) => s + o.ratingStars!) /
            ratedOrders.length)
        : (activeDrv?.rating ?? 0.0);
    final periodCo2SavedGrams = periodOrders
        .where((o) => o.status != OrderStatus.cancelled)
        .fold<double>(0.0, (s, o) => s + o.co2SavedGrams);

    final dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    int weekdayIndexOfOrder(ActiveOrderRecord o) {
      return (o.createdAtDateTime.weekday - 1).clamp(0, 6);
    }

    final dayCounts = List<int>.generate(7, (idx) {
      return periodOrders
          .where((o) => weekdayIndexOfOrder(o) == idx)
          .length;
    });
    final maxDayCount = dayCounts.fold<int>(1, (m, c) => c > m ? c : m);
    final dailyBars = List.generate(7, (idx) {
      final c = dayCounts[idx];
      final ratio = c / maxDayCount;
      return (dayLabels[idx], ratio, '$c');
    });
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.all(Radius.zero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              const Text(
                'Thống kê hoạt động',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ['Hôm nay', 'Tuần này', 'Tháng này'].map((p) {
                  final selected = _statsPeriod == p;
                  return ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      p,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? Colors.white : const Color(0xFF0F172A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    selected: selected,
                    selectedColor: const Color(0xFF14B866),
                    onSelected: (_) => _rebuildDriverUi(() => _statsPeriod = p),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 3 thẻ KPI chuẩn anh_sua_lai/uc21_thong_ke.jpg
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.all(Radius.zero),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Số đơn hoàn thành / Tổng cuốc xe',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$deliveredCount / $totalOrdersCount đơn',
                        style: const TextStyle(
                          color: Color(0xFF4ADE80),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Color(0xFF4ADE80),
                  size: 36,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.all(Radius.zero),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tỷ lệ chấp nhận đơn',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              value: hasAcceptanceHistory ? acceptRatio : 0,
                              strokeWidth: 4,
                              color: const Color(0xFF14B866),
                              backgroundColor: Colors.white24,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              hasAcceptanceHistory ? '$acceptPct%' : '--',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.all(Radius.zero),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Điểm đánh giá TB',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              avgRating > 0 ? avgRating.toStringAsFixed(1) : '--',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFF59E0B),
                            size: 24,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF064E3B),
              border: Border.all(color: const Color(0xFF4ADE80)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.eco_rounded,
                  color: Color(0xFF4ADE80),
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Chỉ số Giao hàng Xanh ESG (Giảm phát thải Xe điện)',
                        style: TextStyle(color: Colors.white70, fontSize: 11.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '-${(periodCo2SavedGrams / 1000.0).toStringAsFixed(2)} kg CO₂ (${periodCo2SavedGrams.toStringAsFixed(0)}g)',
                        style: const TextStyle(
                          color: Color(0xFF4ADE80),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.all(Radius.zero),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Đơn hàng theo thời gian',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 120,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: dailyBars.map((bar) {
                      return Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              bar.$3,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: 22,
                              height: 75 * bar.$2,
                              decoration: BoxDecoration(
                                color: bar.$2 == 1.0
                                    ? const Color(0xFF14B866)
                                    : const Color(0xFF38BDF8),
                                borderRadius: BorderRadius.all(Radius.zero),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              bar.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Đánh giá gần đây từ khách hàng',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 8),
          ...allOrders
              .where((o) => o.ratingStars != null)
              .map((ratedOrder) {
            final starsStr = '★' * (ratedOrder.ratingStars ?? 5);
            return InkWell(
              onTap: () => _rebuildDriverUi(() {
                _store.selectDriverOrder(ratedOrder.trackingCode);
                _selectedScreenIndex = 9;
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.all(Radius.zero),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Khách hàng ${ratedOrder.customerName} (${ratedOrder.trackingCode})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          starsStr,
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ratedOrder.ratingComment?.trim().isNotEmpty == true
                          ? '"${ratedOrder.ratingComment}"' : 'Không có nhận xét',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (allOrders.where((o) => o.ratingStars != null).isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Chưa có đánh giá nào từ khách hàng cho các chuyến xe của bạn.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4ADE80),
                side: const BorderSide(color: Color(0xFF4ADE80)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () =>
                  _rebuildDriverUi(() => _selectedScreenIndex = 0),
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: const Text(
                'Cập nhật Hồ sơ & Pháp lý KYC',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          if (widget.onLogout != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF87171),
                  side: const BorderSide(color: Color(0xFFF87171)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text(
                  'Đăng xuất tài khoản Tài xế',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
