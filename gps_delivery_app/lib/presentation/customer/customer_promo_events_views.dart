part of 'customer_subsystem_views.dart';

extension _CustomerPromoEventsViews on _CustomerSubsystemEntryState {
  void _openPromoHubAtTab(int tabIndex) {
    _rebuildCustomerUi(() {
      _selectedPromoHubTabIndex = tabIndex.clamp(0, 3);
      _selectedScreenIndex = 12;
    });
  }

  void _applyVoucherToGrabFood(BuildContext context, String code) {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) return;
    _rebuildCustomerUi(() {
      _selectedFoodVoucherCode = cleanCode;
      _selectedScreenIndex = 13;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Đã gắn mã $cleanCode vào Giỏ hàng GrabFood! Chọn món ngon để hưởng ưu đãi ngay.',
        ),
      ),
    );
  }

  void _showPromoRewardRevealDialog(
    BuildContext context,
    PromoActionOutcome outcome, {
    required String sourceBadge,
  }) {
    final rarityColor = switch (outcome.rarity) {
      PromoRarityTier.legendary => AppColors.pink,
      PromoRarityTier.rare => AppColors.violet,
      PromoRarityTier.common => const Color(0xFF00B14F),
    };
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: AppColors.ink, width: 2),
          ),
          backgroundColor: Colors.white,
          titlePadding: EdgeInsets.zero,
          title: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.techBg,
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  sourceBadge,
                  style: const TextStyle(
                    color: AppColors.acid,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Consolas',
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  color: rarityColor,
                  child: Text(
                    'HẠNG ${outcome.rarity.code} • ${outcome.rarity.displayName.toUpperCase()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Consolas',
                    ),
                  ),
                ),
              ],
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    border: Border.all(color: AppColors.ink, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: rarityColor,
                        offset: const Offset(0, 4), blurRadius: 14,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        outcome.mintedVoucherCode != null
                            ? Icons.confirmation_number_rounded
                            : Icons.stars_rounded,
                        size: 42,
                        color: rarityColor,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        outcome.rewardTitle.isNotEmpty
                            ? outcome.rewardTitle
                            : 'Phần thưởng may mắn',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        outcome.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (outcome.mintedVoucherCode != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.acid,
                            border: Border.all(
                              color: AppColors.ink,
                              width: 1.4,
                            ),
                          ),
                          child: Text(
                            'MÃ VOUCHER: ${outcome.mintedVoucherCode}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Consolas',
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (outcome.mintedVoucherCode != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.violet,
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                        ),
                        onPressed: () {
                          final code = outcome.mintedVoucherCode!;
                          Navigator.of(dialogCtx).pop();
                          _applyVoucherAndProceed(context, code);
                        },
                        icon: const Icon(
                          Icons.local_shipping_outlined,
                          size: 16,
                        ),
                        label: const Text(
                          'Dùng Giao hàng',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00B14F),
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                        ),
                        onPressed: () {
                          final code = outcome.mintedVoucherCode!;
                          Navigator.of(dialogCtx).pop();
                          _applyVoucherToGrabFood(context, code);
                        },
                        icon: const Icon(
                          Icons.restaurant_menu_rounded,
                          size: 16,
                        ),
                        label: const Text(
                          'Dùng GrabFood',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text(
                'Tiếp tục săn thưởng',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Banner Sự kiện Săn Thưởng Shopee × Grab nổi bật trên Trang chủ Khách hàng (Screen 0)
  Widget _buildHomePromoEventsBanner(BuildContext context) {
    final wallet = _store.activeCustomerPromoWallet;
    final flashWindow = PromoEventGamificationEngine.resolveFlashCountdown(
      DateTime.now(),
    );
    final remHours = flashWindow.remaining.inHours;
    final remMins = flashWindow.remaining.inMinutes % 60;
    final checkedInToday = wallet.hasCheckedInOn(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.techBg,
        border: Border.all(color: AppColors.ink, width: 1.6),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFFEE4D2D),
            offset: Offset(0, 4), blurRadius: 14,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    color: const Color(0xFFEE4D2D),
                    child: const Text(
                      'SHOPEE × GRAB EVENT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    color: AppColors.acid,
                    child: Text(
                      '${flashWindow.activeWindowLabel} • Còn ${remHours}h${remMins.toString().padLeft(2, '0')}p',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildWalletMiniBadge(
                    icon: Icons.monetization_on_rounded,
                    label: '${wallet.ghstCoins} Xu',
                    bg: const Color(0xFFFEF3C7),
                    fg: const Color(0xFFB45309),
                  ),
                  _buildWalletMiniBadge(
                    icon: Icons.casino_outlined,
                    label: '${wallet.spinTickets} Quay',
                    bg: const Color(0xFFEDE9FE),
                    fg: AppColors.violet,
                  ),
                  _buildWalletMiniBadge(
                    icon: Icons.redeem_rounded,
                    label: '${wallet.blindBoxTickets} Hộp mù',
                    bg: const Color(0xFFFFE4E6),
                    fg: const Color(0xFFBE123C),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Đấu Trường Săn Sale • Vòng Xoay May Mắn & Hộp Mù Bí Ẩn Freeship 60K',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            checkedInToday
                ? 'Đã điểm danh hôm nay (Chuỗi ${wallet.checkInStreak}/7 ngày) • Sẵn sàng quay thưởng & khui Hộp Mù SSR!'
                : 'Điểm danh hôm nay nhận ngay GHST Xu miễn phí, săn mã Flash Sale 0H & mở Hộp Mù Gacha!',
            style: const TextStyle(color: AppColors.techMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: const Color(0xFFEE4D2D),
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                onPressed: () => _openPromoHubAtTab(0),
                icon: const Icon(Icons.flash_on_rounded, size: 15),
                label: Text(
                  checkedInToday ? 'Flash Sale & Nhiệm vụ' : 'Điểm danh & Săn Sale',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: AppColors.acid,
                  foregroundColor: AppColors.ink,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                onPressed: () => _openPromoHubAtTab(1),
                icon: const Icon(Icons.radar_rounded, size: 15),
                label: Text(
                  'Vòng Xoay (${wallet.spinTickets})',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.pink, width: 1.4),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                onPressed: () => _openPromoHubAtTab(2),
                icon: const Icon(
                  Icons.card_giftcard_rounded,
                  size: 15,
                  color: AppColors.pink,
                ),
                label: Text(
                  'Khui Hộp Mù (${wallet.blindBoxTickets})',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWalletMiniBadge({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      color: bg,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              fontFamily: 'Consolas',
            ),
          ),
        ],
      ),
    );
  }

  /// Màn hình Trung tâm Ưu đãi & Sự kiện Gamification (Screen Index 12)
  Widget _buildPromoEventsAndVoucherHubView(BuildContext context) {
    final wallet = _store.activeCustomerPromoWallet;
    final usableVouchers = _store.vouchers.where((v) => v.isUsable).toList();
    final missions = PromoEventGamificationEngine.evaluateCustomerMissions(
      customerOrders: _store.customerOrders,
      claimedMissionIds: wallet.claimedMissionIds,
    );
    final claimableMissionsCount = missions.where((m) => m.canClaim).length;

    final tabs = <(IconData, String, String?)>[
      (
        Icons.local_fire_department_rounded,
        'Flash Sale & Nhiệm Vụ',
        claimableMissionsCount > 0 ? '+$claimableMissionsCount' : null,
      ),
      (
        Icons.track_changes_rounded,
        'Vòng Xoay May Mắn',
        '${wallet.spinTickets} vé',
      ),
      (
        Icons.redeem_rounded,
        'Hộp Mù Bí Ẩn',
        '${wallet.blindBoxTickets} vé',
      ),
      (
        Icons.confirmation_number_outlined,
        'Kho Voucher',
        '${usableVouchers.length}',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header tổng quan Ví Xu & Lượt Chơi Shopee × Grab
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.techBg,
            border: Border.all(color: AppColors.ink, width: 1.6),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFFEE4D2D),
                offset: Offset(0, 4), blurRadius: 14,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    color: const Color(0xFFEE4D2D),
                    child: const Text(
                      'SHOPEE FLASH × GRAB REWARDS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    color: const Color(0xFF00B14F),
                    child: const Text(
                      'ÁP DỤNG GIAO HÀNG & GRABFOOD',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Ưu đãi & Đấu Trường Săn Thưởng Siêu Ứng Dụng',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Điểm danh tích GHST Xu, săn mã Khung Giờ Vàng, quay Vòng Xoay May Mắn và khui Hộp Mù Gacha bậc SSR.',
                style: TextStyle(color: AppColors.techMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _buildPromoStatCard(
                    title: 'GHST XU TÍCH LŨY',
                    value: '${wallet.ghstCoins} Xu',
                    accent: const Color(0xFFF59E0B),
                    icon: Icons.monetization_on_rounded,
                  ),
                  _buildPromoStatCard(
                    title: 'VÉ VÒNG XOAY',
                    value: '${wallet.spinTickets} lượt',
                    accent: AppColors.acid,
                    icon: Icons.casino_rounded,
                  ),
                  _buildPromoStatCard(
                    title: 'VÉ HỘP MÙ GACHA',
                    value: '${wallet.blindBoxTickets} hộp',
                    accent: AppColors.pink,
                    icon: Icons.card_giftcard_rounded,
                  ),
                  _buildPromoStatCard(
                    title: 'VOUCHER KHẢ DỤNG',
                    value: '${usableVouchers.length} mã',
                    accent: const Color(0xFF38BDF8),
                    icon: Icons.local_offer_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Thanh chuyển đổi 4 phân khu sự kiện
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.ink, width: 1.5),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(tabs.length, (idx) {
              final selected = _selectedPromoHubTabIndex == idx;
              final item = tabs[idx];
              return InkWell(
                onTap: () =>
                    _rebuildCustomerUi(() => _selectedPromoHubTabIndex = idx),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.ink : AppColors.paper,
                    border: Border.all(color: AppColors.ink, width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.$1,
                        size: 16,
                        color: selected ? AppColors.acid : AppColors.ink,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          item.$2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: selected ? Colors.white : AppColors.ink,
                          ),
                        ),
                      ),
                      if (item.$3 != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          color: selected
                              ? AppColors.acid
                              : const Color(0xFFEE4D2D),
                          child: Text(
                            item.$3!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Consolas',
                              color: selected ? AppColors.ink : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 14),
        switch (_selectedPromoHubTabIndex) {
          0 => _buildFlashSaleAndMissionsTab(context, wallet, missions),
          1 => _LuckySpinWheelSection(
            store: _store,
            wallet: wallet,
            onGoToExchangeOrMissions: () =>
                _rebuildCustomerUi(() => _selectedPromoHubTabIndex = 0),
            onSpinCompleted: (outcome) {
              _rebuildCustomerUi(() {});
              if (outcome.success) {
                _showPromoRewardRevealDialog(
                  context,
                  outcome,
                  sourceBadge: 'VÒNG XOAY MAY MẮN',
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppColors.danger,
                    content: Text(outcome.message),
                  ),
                );
              }
            },
          ),
          2 => _MysteryBlindBoxSection(
            store: _store,
            wallet: wallet,
            onUseVoucherDelivery: (code) =>
                _applyVoucherAndProceed(context, code),
            onUseVoucherGrabFood: (code) =>
                _applyVoucherToGrabFood(context, code),
            onGoToExchange: () =>
                _rebuildCustomerUi(() => _selectedPromoHubTabIndex = 0),
            onBoxOpened: (outcome) {
              _rebuildCustomerUi(() {});
              if (outcome.success) {
                _showPromoRewardRevealDialog(
                  context,
                  outcome,
                  sourceBadge: 'KHUI HỘP MÙ BÍ ẨN GACHA',
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppColors.danger,
                    content: Text(outcome.message),
                  ),
                );
              }
            },
          ),
          _ => _buildMyVoucherVaultTab(context, usableVouchers, wallet),
        },
      ],
    );
  }

  Widget _buildPromoStatCard({
    required String title,
    required String value,
    required Color accent,
    required IconData icon,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1C2C),
        border: Border.all(color: accent, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.techMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Consolas',
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: accent,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Consolas',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Tab 0: Điểm danh 7 ngày Shopee Xu + Khung Giờ Vàng Flash Sale + Nhiệm vụ Grab + Đổi Xu
  Widget _buildFlashSaleAndMissionsTab(
    BuildContext context,
    CustomerPromoWalletState wallet,
    List<PromoMissionProgress> missions,
  ) {
    final now = DateTime.now();
    final checkedInToday = wallet.hasCheckedInOn(now);
    final flashCountdown = PromoEventGamificationEngine.resolveFlashCountdown(
      now,
    );
    final hStr = flashCountdown.remaining.inHours.toString().padLeft(2, '0');
    final mStr = (flashCountdown.remaining.inMinutes % 60).toString().padLeft(
      2,
      '0',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Điểm danh 7 ngày kiểu Shopee Xu
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.ink, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFFF59E0B),
                offset: Offset(0, 4), blurRadius: 14,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        color: Color(0xFFD97706),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Điểm Danh 7 Ngày Săn GHST Xu & Vé Chơi (Shopee Style)',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: checkedInToday
                          ? AppColors.textSecondary
                          : const Color(0xFFEE4D2D),
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    onPressed: checkedInToday
                        ? null
                        : () {
                            final res = _store.claimDailyPromoCheckIn();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(res.message)),
                            );
                          },
                    icon: Icon(
                      checkedInToday
                          ? Icons.check_circle_rounded
                          : Icons.touch_app_rounded,
                      size: 16,
                    ),
                    label: Text(
                      checkedInToday
                          ? 'Đã điểm danh hôm nay (${wallet.checkInStreak}/7)'
                          : 'Điểm danh nhận Xu ngay',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PromoEventGamificationEngine.dailyCheckInSchedule.map(
                  (spec) {
                    final isDone = spec.dayNumber <= wallet.checkInStreak;
                    final isNext =
                        !checkedInToday &&
                        spec.dayNumber == (wallet.checkInStreak % 7) + 1;
                    final isBigDay =
                        spec.bonusSpinTickets > 0 ||
                        spec.bonusBlindBoxTickets > 0;
                    return Container(
                      width: 112,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDone
                            ? const Color(0xFFDCFCE7)
                            : isNext
                            ? const Color(0xFFFFFBEB)
                            : AppColors.paper,
                        border: Border.all(
                          color: isNext
                              ? const Color(0xFFEE4D2D)
                              : AppColors.ink,
                          width: isNext ? 1.8 : 1.1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'NGÀY ${spec.dayNumber}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'Consolas',
                                ),
                              ),
                              Icon(
                                isDone
                                    ? Icons.check_circle_rounded
                                    : (isBigDay
                                          ? Icons.card_giftcard_rounded
                                          : Icons.monetization_on_outlined),
                                size: 14,
                                color: isDone
                                    ? const Color(0xFF166534)
                                    : (isBigDay
                                          ? const Color(0xFFEE4D2D)
                                          : const Color(0xFFD97706)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            spec.highlightLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 2. Khung Giờ Vàng Flash Sale (Shopee 0H/12H/20H × GrabFood Deal)
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.ink, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFFEE4D2D),
                offset: Offset(0, 4), blurRadius: 14,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        color: Color(0xFFEE4D2D),
                        size: 22,
                      ),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Khung Giờ Vàng Săn Mã Flash Sale (Shopee × Grab)',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    color: AppColors.ink,
                    child: Text(
                      'KẾT THÚC SAU $hStr:$mStr:00',
                      style: const TextStyle(
                        color: AppColors.acid,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cols = constraints.maxWidth >= 720 ? 2 : 1;
                  final gap = 10.0;
                  final itemW =
                      (constraints.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: PromoEventGamificationEngine.flashSaleCampaigns
                        .map((camp) {
                          final isClaimed = wallet.claimedCampaignIds.contains(
                            camp.id,
                          );
                          final badgeColor =
                              camp.platformStyle.contains('GrabFood')
                              ? const Color(0xFF00B14F)
                              : camp.platformStyle.contains('Xanh')
                              ? const Color(0xFF0284C7)
                              : const Color(0xFFEE4D2D);
                          final progressPct =
                              ((camp.baseClaimedRatio +
                                          (isClaimed ? 0.05 : 0.0))
                                      .clamp(0.1, 0.98) *
                                  100)
                                  .round();
                          return SizedBox(
                            width: itemW,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.paper,
                                border: Border.all(
                                  color: AppColors.ink,
                                  width: 1.3,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    alignment: WrapAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        color: badgeColor,
                                        child: Text(
                                          camp.platformStyle,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        color: AppColors.ink,
                                        child: Text(
                                          camp.timeSlotBadge,
                                          style: const TextStyle(
                                            color: AppColors.acid,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            fontFamily: 'Consolas',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    camp.title,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    camp.subtitle,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRect(
                                    child: LinearProgressIndicator(
                                      minHeight: 7,
                                      value: progressPct / 100.0,
                                      backgroundColor: Colors.white,
                                      color: badgeColor,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      Text(
                                        'Đã săn $progressPct% • Tặng +${camp.bonusCoins} Xu',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          fontFamily: 'Consolas',
                                          color: AppColors.ink,
                                        ),
                                      ),
                                      if (!isClaimed)
                                        FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            backgroundColor: badgeColor,
                                            foregroundColor: Colors.white,
                                            shape: const RoundedRectangleBorder(
                                              borderRadius: BorderRadius.all(Radius.circular(12)),
                                            ),
                                          ),
                                          onPressed: () {
                                            final outcome = _store
                                                .claimFlashSaleCampaign(
                                                  camp.id,
                                                );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(outcome.message),
                                              ),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.download_done_rounded,
                                            size: 14,
                                          ),
                                          label: const Text(
                                            'Lưu mã ngay',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        )
                                      else
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            OutlinedButton(
                                              style: OutlinedButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                shape:
                                                    const RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.all(Radius.circular(12)),
                                                    ),
                                              ),
                                              onPressed: () =>
                                                  _applyVoucherAndProceed(
                                                    context,
                                                    camp.codePrefix,
                                                  ),
                                              child: const Text(
                                                'Dùng Ship',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            OutlinedButton(
                                              style: OutlinedButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                foregroundColor: const Color(
                                                  0xFF00853B,
                                                ),
                                                shape:
                                                    const RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.all(Radius.circular(12)),
                                                    ),
                                              ),
                                              onPressed: () =>
                                                  _applyVoucherToGrabFood(
                                                    context,
                                                    camp.codePrefix,
                                                  ),
                                              child: const Text(
                                                'Dùng Food',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        })
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 3. Nhiệm vụ GrabChallenges & Cửa hàng Đổi GHST Xu
        LayoutBuilder(
          builder: (context, constraints) {
            final missionsCard = Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.ink, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.emoji_events_rounded,
                        color: Color(0xFF00B14F),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Nhiệm Vụ Săn Vé Quay & Hộp Mù (GrabChallenges)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...missions.map((m) {
                    final rewards = <String>[
                      '+${m.rewardCoins} Xu',
                      if (m.rewardSpinTickets > 0)
                        '+${m.rewardSpinTickets} Vé Quay',
                      if (m.rewardBlindBoxTickets > 0)
                        '+${m.rewardBlindBoxTickets} Hộp Mù',
                    ].join(' • ');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: m.isClaimed
                            ? const Color(0xFFF0FDF4)
                            : AppColors.paper,
                        border: Border.all(color: AppColors.ink, width: 1.1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                '${m.title} (${m.currentCount}/${m.targetCount})',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.ink,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                color: AppColors.acid,
                                child: Text(
                                  rewards,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'Consolas',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            m.description,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: LinearProgressIndicator(
                                  minHeight: 6,
                                  value: m.progressRatio,
                                  backgroundColor: Colors.white,
                                  color: const Color(0xFF00B14F),
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (m.isClaimed)
                                const Text(
                                  'Đã nhận ✓',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF166534),
                                  ),
                                )
                              else if (m.canClaim)
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: const Color(0xFF00B14F),
                                    foregroundColor: Colors.white,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(12)),
                                    ),
                                  ),
                                  onPressed: () {
                                    final res = _store.claimPromoMissionReward(
                                      m.id,
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(res.message)),
                                    );
                                  },
                                  child: const Text(
                                    'Nhận thưởng',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                )
                              else
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(12)),
                                    ),
                                  ),
                                  onPressed: () => _rebuildCustomerUi(() {
                                    _selectedScreenIndex =
                                        m.id == 'MIS_GRABFOOD_FAN' ? 13 : 2;
                                  }),
                                  child: const Text(
                                    'Thực hiện',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
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

            final coinShopCard = Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.ink, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.storefront_rounded,
                        color: AppColors.violet,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Trạm Đổi GHST Xu (${wallet.ghstCoins} Xu)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Dùng GHST Xu tích lũy từ Điểm danh & Nhiệm vụ để đổi thêm lượt chơi hoặc mã giảm trực tiếp:',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildCoinExchangeTile(
                    context: context,
                    title: '+1 Vé Vòng Xoay May Mắn',
                    subtitle: 'Thử vận may trúng Jackpot 45k hoặc thêm Hộp Mù',
                    costCoins: PromoEventGamificationEngine.coinsPerSpinTicket,
                    currentCoins: wallet.ghstCoins,
                    targetType: 'SPIN_TICKET',
                    accent: AppColors.violet,
                  ),
                  const SizedBox(height: 8),
                  _buildCoinExchangeTile(
                    context: context,
                    title: '+1 Vé Mở Hộp Mù Bí Ẩn (Gacha)',
                    subtitle: 'Cơ hội khui trúng Thẻ Kim Cương SSR 60.000đ',
                    costCoins:
                        PromoEventGamificationEngine.coinsPerBlindBoxTicket,
                    currentCoins: wallet.ghstCoins,
                    targetType: 'BLIND_BOX_TICKET',
                    accent: AppColors.pink,
                  ),
                  const SizedBox(height: 8),
                  _buildCoinExchangeTile(
                    context: context,
                    title: 'Đổi thẳng Voucher Freeship 25.000đ',
                    subtitle: 'Cấp ngay mã giảm 25k cho đơn từ 20.000đ',
                    costCoins:
                        PromoEventGamificationEngine.coinsPerDirectVoucher25k,
                    currentCoins: wallet.ghstCoins,
                    targetType: 'VOUCHER_25K',
                    accent: const Color(0xFF00B14F),
                  ),
                ],
              ),
            );

            if (constraints.maxWidth >= 820) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: missionsCard),
                  const SizedBox(width: 14),
                  Expanded(flex: 5, child: coinShopCard),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                missionsCard,
                const SizedBox(height: 14),
                coinShopCard,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCoinExchangeTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required int costCoins,
    required int currentCoins,
    required String targetType,
    required Color accent,
  }) {
    final affordable = currentCoins >= costCoins;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border.all(color: AppColors.ink, width: 1.15),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: affordable ? accent : AppColors.textSecondary,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
            onPressed: () {
              final outcome = _store.exchangePromoCoins(targetType: targetType);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: outcome.success ? null : AppColors.danger,
                  content: Text(outcome.message),
                ),
              );
            },
            child: Text(
              'Đổi $costCoins Xu',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tab 3: Kho Voucher của tôi + Nhập mã ưu đãi thủ công (tương thích ngược UC11)
  Widget _buildMyVoucherVaultTab(
    BuildContext context,
    List<VoucherRecord> usableVouchers,
    CustomerPromoWalletState wallet,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink, width: 1.5),
      ),
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
                'Ưu đãi & Kho Voucher Của Bạn (${usableVouchers.length} khả dụng)',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                onPressed: () =>
                    _rebuildCustomerUi(() => _selectedPromoHubTabIndex = 1),
                icon: const Icon(Icons.casino_outlined, size: 15),
                label: const Text(
                  'Quay thêm mã mới',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _voucherCtrl,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Nhập mã ưu đãi (Giao hàng / GrabFood)',
              prefixIcon: const Icon(Icons.local_offer_outlined),
              suffixIcon: IconButton(
                tooltip: 'Áp dụng',
                icon: const Icon(Icons.check),
                onPressed: () =>
                    _applyVoucherAndProceed(context, _voucherCtrl.text),
              ),
            ),
            onSubmitted: (code) => _applyVoucherAndProceed(context, code),
          ),
          const SizedBox(height: 14),
          if (usableVouchers.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.paper,
                border: Border.all(color: AppColors.ink),
              ),
              child: Column(
                children: [
                  const Text(
                    'Chưa có ưu đãi khả dụng trong kho.',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Hãy sang tab Flash Sale, Vòng Xoay May Mắn hoặc Hộp Mù Bí Ẩn để săn ngay Voucher Freeship!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEE4D2D),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _rebuildCustomerUi(
                          () => _selectedPromoHubTabIndex = 0,
                        ),
                        icon: const Icon(Icons.flash_on_rounded, size: 15),
                        label: const Text('Săn Flash Sale'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.violet,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _rebuildCustomerUi(
                          () => _selectedPromoHubTabIndex = 2,
                        ),
                        icon: const Icon(Icons.redeem_rounded, size: 15),
                        label: const Text('Khui Hộp Mù'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            ...usableVouchers.map((voucher) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  border: Border.all(color: AppColors.ink, width: 1.3),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
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
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                color: AppColors.acid,
                                child: Text(
                                  voucher.code,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'Consolas',
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                color: AppColors.pink,
                                child: Text(
                                  voucher.discountLabel,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            voucher.title,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Đơn tối thiểu: ${CurrencyFormatter.formatVnd(voucher.minOrderValue)} • Lượt còn: ${voucher.usageLimit - voucher.usedCount} • HSD: ${voucher.expiryDate}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: AppColors.violet,
                            foregroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
                          ),
                          onPressed: () =>
                              _applyVoucherAndProceed(context, voucher.code),
                          icon: const Icon(
                            Icons.local_shipping_outlined,
                            size: 14,
                          ),
                          label: const Text(
                            'Dùng Giao hàng',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: const Color(0xFF00B14F),
                            foregroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
                          ),
                          onPressed: () =>
                              _applyVoucherToGrabFood(context, voucher.code),
                          icon: const Icon(
                            Icons.restaurant_menu_rounded,
                            size: 14,
                          ),
                          label: const Text(
                            'Dùng GrabFood',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          if (wallet.history.isNotEmpty) ...[
            const Divider(height: 24),
            const Text(
              'Nhật ký Săn Thưởng & Mở Quà Gần Đây',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            ...wallet.history.take(8).map((h) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  color: AppColors.paper,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        '[${h.rarityCode}] ${h.title} — ${h.summary}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        h.timestampLabel,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'Consolas',
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// WIDGET TAB 1: VÒNG XOAY MAY MẮN 8 Ô (LUCKY SPIN WHEEL NEO-BRUTALIST)
// =============================================================================

class _LuckySpinWheelSection extends StatefulWidget {
  final AppStateStore store;
  final CustomerPromoWalletState wallet;
  final VoidCallback onGoToExchangeOrMissions;
  final ValueChanged<PromoActionOutcome> onSpinCompleted;

  const _LuckySpinWheelSection({
    required this.store,
    required this.wallet,
    required this.onGoToExchangeOrMissions,
    required this.onSpinCompleted,
  });

  @override
  State<_LuckySpinWheelSection> createState() => _LuckySpinWheelSectionState();
}

class _LuckySpinWheelSectionState extends State<_LuckySpinWheelSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;
  Animation<double>? _angleAnimation;
  double _currentAngle = 0.0;
  bool _isSpinning = false;
  PromoActionOutcome? _pendingOutcome;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..addListener(() {
        if (!mounted || _angleAnimation == null) return;
        setState(() {
          _currentAngle = _angleAnimation!.value;
        });
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          final outcome = _pendingOutcome;
          _pendingOutcome = null;
          if (mounted) {
            setState(() => _isSpinning = false);
          }
          if (outcome != null) {
            widget.onSpinCompleted(outcome);
          }
        }
      });
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  void _triggerSpin() {
    if (_isSpinning) return;
    final outcome = widget.store.spinLuckyWheel();
    if (!outcome.success || outcome.wheelSegmentIndex == null) {
      widget.onSpinCompleted(outcome);
      return;
    }

    final segCount = PromoEventGamificationEngine.spinWheelSegments.length;
    final sliceRad = (2 * 3.141592653589793) / segCount;
    final targetIdx = outcome.wheelSegmentIndex!;
    final desiredMod = ((segCount - targetIdx) % segCount) * sliceRad;
    const twoPi = 2 * 3.141592653589793;
    final curMod = _currentAngle % twoPi;
    final deltaToTarget = (desiredMod - curMod + twoPi) % twoPi;
    final targetAngle = _currentAngle + (5 * twoPi) + deltaToTarget;

    _pendingOutcome = outcome;
    setState(() => _isSpinning = true);
    _angleAnimation = Tween<double>(begin: _currentAngle, end: targetAngle)
        .animate(
          CurvedAnimation(parent: _spinController, curve: Curves.easeOutQuart),
        );
    _spinController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final spinHistory = widget.wallet.history
        .where((h) => h.source == 'SPIN_WHEEL')
        .take(5)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wheelSize = (constraints.maxWidth < 420
                ? constraints.maxWidth - 40
                : 310.0)
            .clamp(210.0, 320.0);

        final wheelCard = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.ink, width: 1.6),
            boxShadow: const [
              BoxShadow(
                color: AppColors.violet,
                offset: Offset(0, 4), blurRadius: 14,
              ),
            ],
          ),
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    color: AppColors.ink,
                    child: Text(
                      'LƯỢT QUAY HIỆN CÓ: ${widget.wallet.spinTickets}',
                      style: const TextStyle(
                        color: AppColors.acid,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    color: const Color(0xFFFFE4E6),
                    child: const Text(
                      '100% TRÚNG QUÀ THẬT',
                      style: TextStyle(
                        color: Color(0xFFBE123C),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: wheelSize,
                height: wheelSize + 14,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 12,
                      child: SizedBox(
                        width: wheelSize,
                        height: wheelSize,
                        child: CustomPaint(
                          painter: LuckySpinWheelPainter(
                            rotationRadians: _currentAngle,
                            segments:
                                PromoEventGamificationEngine.spinWheelSegments,
                          ),
                        ),
                      ),
                    ),
                    // Kim chỉ đỉnh 12h
                    Positioned(
                      top: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.pink,
                          border: Border.all(color: AppColors.ink, width: 2),
                        ),
                        child: const Icon(
                          Icons.arrow_drop_down_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    // Nút QUAY trung tâm
                    Positioned(
                      top: 12 + (wheelSize - 68) / 2,
                      child: InkWell(
                        onTap: _isSpinning ? null : _triggerSpin,
                        child: Container(
                          width: 68,
                          height: 68,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _isSpinning
                                ? AppColors.textSecondary
                                : AppColors.ink,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.acid,
                              width: 3,
                            ),
                          ),
                          child: Text(
                            _isSpinning ? 'ĐANG\nQUAY' : 'QUAY\nNGAY',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.acid,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.violet,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    onPressed: _isSpinning ? null : _triggerSpin,
                    icon: const Icon(Icons.casino_rounded, size: 18),
                    label: Text(
                      _isSpinning
                          ? 'Vòng xoay đang chạy...'
                          : 'Bấm Quay Thưởng (-1 Vé)',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    onPressed: widget.onGoToExchangeOrMissions,
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    label: const Text(
                      'Kiếm thêm lượt quay',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        final prizeInfoCard = Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.ink, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Cơ cấu 8 Ô Giải Thưởng & Tỷ Lệ Công Khai',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              ...PromoEventGamificationEngine.spinWheelSegments.map((seg) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      border: Border.all(color: AppColors.ink, width: 1.0),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Color(seg.sliceHexColor),
                            border: Border.all(color: AppColors.ink),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            seg.fullTitle,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        Text(
                          '${seg.weight}%',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Consolas',
                            color: AppColors.violet,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              if (spinHistory.isNotEmpty) ...[
                const Divider(height: 20),
                const Text(
                  'Lịch sử Vòng Xoay gần nhất:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                ...spinHistory.map((h) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${h.title} (${h.summary})',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        );

        if (constraints.maxWidth >= 820) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: wheelCard),
              const SizedBox(width: 14),
              Expanded(flex: 5, child: prizeInfoCard),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            wheelCard,
            const SizedBox(height: 14),
            prizeInfoCard,
          ],
        );
      },
    );
  }
}

class LuckySpinWheelPainter extends CustomPainter {
  final double rotationRadians;
  final List<SpinWheelSegment> segments;

  const LuckySpinWheelPainter({
    required this.rotationRadians,
    required this.segments,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = (size.shortestSide / 2) - 2;
    final wheelRadius = outerRadius - 10;
    const pi = 3.141592653589793;
    final segCount = segments.length;
    final sliceAngle = (2 * pi) / segCount;

    // Viền ngoài Neo-Brutalist kèm đèn LED trang trí
    final rimPaint = Paint()..color = AppColors.ink;
    canvas.drawCircle(center, outerRadius, rimPaint);

    final studPaint = Paint()..color = AppColors.acid;
    for (var i = 0; i < 16; i++) {
      final a = (i * pi / 8) + rotationRadians * 0.5;
      final sx = center.dx + (outerRadius - 5) * _cos(a);
      final sy = center.dy + (outerRadius - 5) * _sin(a);
      canvas.drawCircle(Offset(sx, sy), 2.3, studPaint);
    }

    final borderPaint = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final rect = Rect.fromCircle(center: center, radius: wheelRadius);

    for (var i = 0; i < segCount; i++) {
      final seg = segments[i];
      final startAngle =
          (-pi / 2) - (sliceAngle / 2) + (i * sliceAngle) + rotationRadians;
      final fillPaint = Paint()
        ..color = Color(seg.sliceHexColor)
        ..style = PaintingStyle.fill;

      canvas.drawArc(rect, startAngle, sliceAngle, true, fillPaint);
      canvas.drawArc(rect, startAngle, sliceAngle, true, borderPaint);

      // Vẽ nhãn chữ hướng tâm rõ nét cho từng ô
      final midAngle = startAngle + sliceAngle / 2;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(midAngle);

      final tp = TextPainter(
        text: TextSpan(
          text: seg.shortLabel,
          style: TextStyle(
            color: Color(seg.textHexColor),
            fontSize: size.shortestSide < 240 ? 9.0 : 10.5,
            fontWeight: FontWeight.w900,
            fontFamily: 'Consolas',
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: wheelRadius * 0.62);

      tp.paint(
        canvas,
        Offset(wheelRadius * 0.34, -tp.height / 2),
      );
      canvas.restore();
    }
  }

  double _cos(double x) {
    // Khai triển lượng giác chuẩn từ dart:math thông qua Offset.fromDirection
    return Offset.fromDirection(x).dx;
  }

  double _sin(double x) {
    return Offset.fromDirection(x).dy;
  }

  @override
  bool shouldRepaint(covariant LuckySpinWheelPainter oldDelegate) =>
      oldDelegate.rotationRadians != rotationRadians;
}

// =============================================================================
// WIDGET TAB 2: HỘP MÙ BÍ ẨN 6 Ô (MYSTERY BLIND BOX GACHA)
// =============================================================================

class _MysteryBlindBoxSection extends StatefulWidget {
  final AppStateStore store;
  final CustomerPromoWalletState wallet;
  final ValueChanged<String> onUseVoucherDelivery;
  final ValueChanged<String> onUseVoucherGrabFood;
  final VoidCallback onGoToExchange;
  final ValueChanged<PromoActionOutcome> onBoxOpened;

  const _MysteryBlindBoxSection({
    required this.store,
    required this.wallet,
    required this.onUseVoucherDelivery,
    required this.onUseVoucherGrabFood,
    required this.onGoToExchange,
    required this.onBoxOpened,
  });

  @override
  State<_MysteryBlindBoxSection> createState() =>
      _MysteryBlindBoxSectionState();
}

class _MysteryBlindBoxSectionState extends State<_MysteryBlindBoxSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  int? _shakingBoxIndex;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          final targetIdx = _shakingBoxIndex;
          if (mounted) {
            setState(() => _shakingBoxIndex = null);
          }
          if (targetIdx != null) {
            final outcome = widget.store.openMysteryBlindBox(targetIdx);
            widget.onBoxOpened(outcome);
          }
        }
      });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _handleTapBlindBox(int boxIndex) {
    if (_shakingBoxIndex != null) return;
    if (widget.wallet.openedBlindBoxes.containsKey(boxIndex) ||
        widget.wallet.blindBoxTickets <= 0) {
      final outcome = widget.store.openMysteryBlindBox(boxIndex);
      widget.onBoxOpened(outcome);
      return;
    }
    setState(() => _shakingBoxIndex = boxIndex);
    _shakeController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final openedMap = widget.wallet.openedBlindBoxes;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink, width: 1.6),
        boxShadow: const [
          BoxShadow(
            color: AppColors.pink,
            offset: Offset(0, 4), blurRadius: 14,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bàn Gacha 6 Hộp Mù Bí Ẩn (Mystery Blind Box)',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    'Chạm vào chiếc hộp bất kỳ để lắc & khui quà • Đã mở ${openedMap.length}/6 hộp • Vé hiện có: ${widget.wallet.blindBoxTickets}',
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
                  if (openedMap.isNotEmpty)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      onPressed: () {
                        widget.store.resetMysteryBlindBoxBoard();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Đã xếp mới bộ 6 Hộp Mù niêm phong trên bàn Gacha!',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text(
                        'Làm mới bộ 6 Hộp',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppColors.pink,
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    onPressed: widget.onGoToExchange,
                    icon: const Icon(Icons.monetization_on_rounded, size: 15),
                    label: const Text(
                      'Đổi Xu lấy Vé Hộp Mù',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: const [
              _RarityLegendChip(
                code: 'SSR • 18%',
                desc: 'Freeship 60k / Giảm 80%',
                color: AppColors.pink,
              ),
              _RarityLegendChip(
                code: 'SR • 42%',
                desc: 'Giảm 35k / Giảm 50% + Vé Quay',
                color: AppColors.violet,
              ),
              _RarityLegendChip(
                code: 'R • 40%',
                desc: 'Freeship 20k 0Đ / +350 Xu',
                color: Color(0xFF00B14F),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 760
                  ? 3
                  : (constraints.maxWidth >= 430 ? 2 : 1);
              final gap = 12.0;
              final boxWidth =
                  (constraints.maxWidth - gap * (cols - 1)) / cols;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: PromoEventGamificationEngine.blindBoxBoardSlots.map((
                  slot,
                ) {
                  final opened = openedMap[slot.boxIndex];
                  final isShaking = _shakingBoxIndex == slot.boxIndex;
                  final accentColor = Color(slot.accentHexColor);

                  return AnimatedBuilder(
                    animation: _shakeController,
                    builder: (context, child) {
                      double dx = 0;
                      if (isShaking) {
                        final t = _shakeController.value;
                        dx =
                            Offset.fromDirection(
                              t * 3.141592653589793 * 8,
                            ).dy *
                            7.0;
                      }
                      return Transform.translate(
                        offset: Offset(dx, 0),
                        child: child,
                      );
                    },
                    child: SizedBox(
                      width: boxWidth,
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: opened != null
                              ? const Color(0xFFFFFBEB)
                              : AppColors.paper,
                          border: Border.all(
                            color: opened != null ? accentColor : AppColors.ink,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor,
                              offset: const Offset(0, 4), blurRadius: 14,
                            ),
                          ],
                        ),
                        child: opened == null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        color: AppColors.ink,
                                        child: Text(
                                          slot.boxCode,
                                          style: const TextStyle(
                                            color: AppColors.acid,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            fontFamily: 'Consolas',
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        color: accentColor,
                                        child: const Text(
                                          'NIÊM PHONG ?',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w900,
                                            fontFamily: 'Consolas',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Center(
                                    child: Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(
                                          color: AppColors.ink,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.inventory_2_rounded,
                                        size: 32,
                                        color: accentColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    slot.themeTitle,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    slot.themeTag,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: AppColors.ink,
                                      foregroundColor: AppColors.acid,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.all(Radius.circular(12)),
                                      ),
                                    ),
                                    onPressed: isShaking
                                        ? null
                                        : () =>
                                              _handleTapBlindBox(slot.boxIndex),
                                    icon: const Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 14,
                                    ),
                                    label: Text(
                                      isShaking
                                          ? 'Đang khui hộp...'
                                          : 'Khui Hộp Mù (-1 Vé)',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        slot.boxCode,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w900,
                                          fontFamily: 'Consolas',
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        color: opened.rarityCode == 'SSR'
                                            ? AppColors.pink
                                            : opened.rarityCode == 'SR'
                                            ? AppColors.violet
                                            : const Color(0xFF00B14F),
                                        child: Text(
                                          'ĐÃ KHUI • ${opened.rarityCode}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w900,
                                            fontFamily: 'Consolas',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    opened.title,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    opened.summary,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.violet,
                                      fontFamily: 'Consolas',
                                    ),
                                  ),
                                  if (opened.voucherCode != null) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            shape: const RoundedRectangleBorder(
                                              borderRadius: BorderRadius.all(Radius.circular(12)),
                                            ),
                                          ),
                                          onPressed: () =>
                                              widget.onUseVoucherDelivery(
                                                opened.voucherCode!,
                                              ),
                                          child: const Text(
                                            'Dùng Ship',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            foregroundColor: const Color(
                                              0xFF00853B,
                                            ),
                                            shape: const RoundedRectangleBorder(
                                              borderRadius: BorderRadius.all(Radius.circular(12)),
                                            ),
                                          ),
                                          onPressed: () =>
                                              widget.onUseVoucherGrabFood(
                                                opened.voucherCode!,
                                              ),
                                          child: const Text(
                                            'Dùng Food',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RarityLegendChip extends StatelessWidget {
  final String code;
  final String desc;
  final Color color;

  const _RarityLegendChip({
    required this.code,
    required this.desc,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border.all(color: AppColors.ink),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            color: color,
            child: Text(
              code,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                fontFamily: 'Consolas',
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              desc,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
