part of 'admin_subsystem_views.dart';

extension _AdminOverviewAndFleetViews on _AdminSubsystemEntryState {
  /// UC22: Dashboard Tổng quan Hệ thống (Khớp 100% uc22_dashboard_1791014957650.jpg)
  Widget _buildSystemOverviewDashboard() {
    final canViewFinance = _store.hasAdminPermission('Tài chính: Báo cáo');
    final canViewOrders = _store.hasAdminPermission('Đơn: Xem');
    final totalOrders = _store.orders.length;
    final totalRevenue = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus != 'RETURNED',
        )
        .fold<double>(0.0, (sum, o) => sum + o.totalAmount);
    final pipelineGmv = _store.orders
        .where(
          (o) =>
              o.status != OrderStatus.cancelled &&
              o.status != OrderStatus.failed &&
              o.status != OrderStatus.returning &&
              o.paymentStatus != 'RETURNED',
        )
        .fold<double>(0.0, (sum, o) => sum + o.totalAmount);
    final onlineDriversCount = _store.drivers
        .where((d) => d.isOnline && d.approvalStatus == 'Đã duyệt')
        .length;
    final activeDeliveriesCount = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.inTransit ||
              o.status == OrderStatus.accepted ||
              o.status == OrderStatus.arrivingPickup ||
              o.status == OrderStatus.searching,
        )
        .length;

    final safeTotal = totalOrders > 0 ? totalOrders : 1;
    final deliveredCount = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus != 'RETURNED',
        )
        .length;
    final inTransitCount = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.inTransit ||
              o.status == OrderStatus.accepted ||
              o.status == OrderStatus.arrivingPickup,
        )
        .length;
    final cancelledCount = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.cancelled ||
              o.status == OrderStatus.failed ||
              o.status == OrderStatus.returning ||
              o.paymentStatus == 'RETURNED',
        )
        .length;
    final otherCount =
        (totalOrders - deliveredCount - inTransitCount - cancelledCount).clamp(
          0,
          totalOrders,
        );

    final deliveredPct = ((deliveredCount / safeTotal) * 100).round();
    final inTransitPct = ((inTransitCount / safeTotal) * 100).round();
    final cancelledPct = ((cancelledCount / safeTotal) * 100).round();
    final otherPct = totalOrders == 0
        ? 0
        : (100 - deliveredPct - inTransitPct - cancelledPct).clamp(0, 100);

    final bucketsRev = List<double>.filled(7, 0.0);
    final bucketsCnt = List<int>.filled(7, 0);
    final now = DateTime.now();
    final chartDayLabels = List<String>.generate(7, (idx) {
      final d = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 6 - idx));
      return '${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}';
    });
    for (final ord in _store.orders) {
      final daysAgo = ord.daysAgoFrom(now);
      if (daysAgo < 0 || daysAgo > 6) continue;
      final dayIdx = (6 - daysAgo).clamp(0, 6);
      bucketsCnt[dayIdx] += 1;
      if (ord.status == OrderStatus.delivered &&
          ord.paymentStatus != 'RETURNED') {
        bucketsRev[dayIdx] += ord.totalAmount;
      }
    }
    final maxRev = bucketsRev.fold<double>(1.0, (a, b) => a > b ? a : b);
    final maxCnt = bucketsCnt.fold<int>(1, (a, b) => a > b ? a : b);
    final blueNorm = List<double>.generate(7, (i) {
      if (!canViewFinance || bucketsRev[i] <= 0) return 0.96;
      final ratio = (bucketsRev[i] / maxRev).clamp(0.08, 0.92);
      return (1.0 - ratio).clamp(0.06, 0.94);
    });
    final orangeNorm = List<double>.generate(7, (i) {
      if (bucketsCnt[i] <= 0) return 0.96;
      final ratio = (bucketsCnt[i] / maxCnt).clamp(0.08, 0.90);
      return (1.0 - ratio).clamp(0.08, 0.94);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tổng quan hệ thống',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Dashboard Tổng quan Hệ thống • ${_store.lastSyncStatusMessage}',
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF4A4754)),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, kpiConstraints) {
            final maxW = kpiConstraints.maxWidth;
            final cols = maxW >= 960
                ? 4
                : maxW >= 540
                ? 2
                : 1;
            final cardWidth = cols == 1
                ? maxW
                : (maxW - (cols - 1) * 16.0) / cols;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildGoMauKpiCard(
                  width: cardWidth,
                  title: 'Tổng đơn hàng',
                  value: '$totalOrders',
                  delta: '(${_store.users.length} tài khoản)',
                  deltaPositive: true,
                  badgeColor: const Color(0xFF2563EB),
                  icon: Icons.shopping_cart_rounded,
                  showSparkline: true,
                  sparklineColor: const Color(0xFF2563EB),
                  sparklineFactors: orangeNorm,
                ),
                _buildGoMauKpiCard(
                  width: cardWidth,
                  title: 'Doanh thu',
                  value: canViewFinance
                      ? CurrencyFormatter.formatVnd(totalRevenue)
                      : '🔒 Quyền Báo cáo',
                  delta: canViewFinance
                      ? '(${_store.orders.where((o) => o.paymentStatus == "PAID").length} đã TT)'
                      : '(Ẩn theo RBAC)',
                  deltaPositive: canViewFinance,
                  badgeColor: const Color(0xFFF43F5E),
                  icon: Icons.monetization_on_rounded,
                  showSparkline: canViewFinance,
                  sparklineColor: const Color(0xFFF43F5E),
                  sparklineFactors: blueNorm,
                ),
                _buildGoMauKpiCard(
                  width: cardWidth,
                  title: 'Tài xế online',
                  value: '$onlineDriversCount/${_store.drivers.length}',
                  delta: '(Trực tuyến)',
                  deltaPositive: onlineDriversCount > 0,
                  badgeColor: const Color(0xFF14B866),
                  icon: Icons.sensors_rounded,
                  showSparkline: false,
                  sparklineColor: const Color(0xFF14B866),
                ),
                _buildGoMauKpiCard(
                  width: cardWidth,
                  title: 'Đơn đang giao',
                  value: '$activeDeliveriesCount',
                  delta: '(Hoạt động)',
                  deltaPositive: true,
                  badgeColor: const Color(0xFFEAB308),
                  icon: Icons.local_shipping_rounded,
                  showSparkline: false,
                  sparklineColor: const Color(0xFFEAB308),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Builder(
          builder: (context) {
            final evDriversCount =
                _store.drivers.where((d) => d.isElectricVehicle).length;
            final co2Kg = _store.totalSystemCo2SavedGrams / 1000.0;
            final greenFund = _store.totalGreenFundContributedVnd;
            final batchedCount = _store.orders
                .where(
                  (o) =>
                      o.batchGroupId != null &&
                      o.batchGroupId!.trim().isNotEmpty,
                )
                .length;
            final insuredCount =
                _store.orders.where((o) => o.declaredValueVnd > 0).length;
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                border: Border.all(color: const Color(0xFF0F172A)),
              ),
              child: Wrap(
                spacing: 18,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: GhstButtonIcon(
                              Icons.eco_rounded,
                              size: 16,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ),
                        TextSpan(
                          text:
                              'ESG Xe điện: $evDriversCount xe • Giảm ${co2Kg.toStringAsFixed(2)} kg CO₂',
                        ),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    'Quỹ Xanh: ${CurrencyFormatter.formatVnd(greenFund)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF166534),
                    ),
                  ),
                  Text(
                    'Ghép đơn 2H cùng hướng: $batchedCount đơn',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  Text(
                    'Bảo hiểm khai giá: $insuredCount đơn',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF9A3412),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, rowConstraints) {
            if (_store.orders.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Row(
                  children: [
                    GhstButtonIcon(Icons.inbox_outlined, color: AppColors.textSecondary),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Chưa có đơn hàng',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              );
            }
            final isDesktopRow = rowConstraints.maxWidth >= 820;
            final revenueChartCard = Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.all(color: const Color(0xFF0F172A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Biểu đồ Doanh thu (7 ngày gần nhất)',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    canViewFinance
                        ? 'Thực thu đã giao: ${CurrencyFormatter.formatVnd(totalRevenue)} • Tổng GMV luồng đơn: ${CurrencyFormatter.formatVnd(pipelineGmv)}'
                        : '🔒 Vai trò hiện tại không có quyền "Tài chính: Báo cáo" để xem số liệu doanh thu.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF4A4754),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 190,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _GoMauRevenueLineChartPainter(
                        blueNorm: blueNorm,
                        orangeNorm: orangeNorm,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: chartDayLabels
                        .map(
                          (lbl) => Flexible(
                            child: Text(
                              lbl,
                              style: const TextStyle(fontSize: 9.5),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            );

            final statusDonutCard = Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.all(color: const Color(0xFF0F172A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Trạng thái Đơn hàng',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: SizedBox(
                      width: 136,
                      height: 136,
                      child: CustomPaint(
                        painter: _GoMauOrderDonutPainter(
                          deliveredRatio: deliveredPct / 100.0,
                          inTransitRatio: inTransitPct / 100.0,
                          cancelledRatio: cancelledPct / 100.0,
                          otherRatio: otherPct / 100.0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDonutLegendRow(
                    const Color(0xFF2563EB),
                    'Giao thành công: $deliveredPct% ($deliveredCount đơn)',
                  ),
                  const SizedBox(height: 5),
                  _buildDonutLegendRow(
                    const Color(0xFFF43F5E),
                    'Đang giao: $inTransitPct% ($inTransitCount đơn)',
                  ),
                  const SizedBox(height: 5),
                  _buildDonutLegendRow(
                    const Color(0xFFDC2626),
                    'Đã hủy: $cancelledPct% ($cancelledCount đơn)',
                  ),
                  const SizedBox(height: 5),
                  _buildDonutLegendRow(
                    const Color(0xFF94A3B8),
                    'Đang tìm xe / Khác: $otherPct% ($otherCount đơn)',
                  ),
                ],
              ),
            );

            final newestOrdersCard = Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.all(color: const Color(0xFF0F172A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đơn hàng mới nhất (${_store.orders.length} đơn)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Mã Đơn',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            color: Color(0xFF4A4754),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Khách hàng',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            color: Color(0xFF4A4754),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Tài xế',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            color: Color(0xFF4A4754),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Giá trị',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            color: Color(0xFF4A4754),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Trạng thái',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            color: Color(0xFF4A4754),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  if (!canViewOrders)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '🔒 Vai trò điều hành hiện tại không có quyền "Đơn: Xem" để xem chi tiết danh sách vận đơn.',
                        style: TextStyle(color: AppColors.danger, fontSize: 12),
                      ),
                    )
                  else if (_store.orders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Chưa có vận đơn nào được ghi nhận trong hệ thống.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  else
                    ..._store.orders.map((o) {
                      final isReturned = o.paymentStatus == 'RETURNED';
                      final isDone =
                          o.status == OrderStatus.delivered && !isReturned;
                      final isCancelled =
                          o.status == OrderStatus.cancelled ||
                          o.status == OrderStatus.failed ||
                          o.status == OrderStatus.returning ||
                          isReturned;
                      return InkWell(
                        onTap: () {
                          _store.selectDriverOrder(o.trackingCode);
                          _rebuildAdminUi(() => _selectedScreenIndex = 8);
                        },
                        child: _buildNewestOrderRow(
                          code: o.trackingCode,
                          customer: o.customerName,
                          driver: o.assignedDriverName ?? 'Đang tìm tài xế',
                          amount: CurrencyFormatter.formatVnd(o.totalAmount),
                          statusLabel: isReturned
                              ? 'Đã hoàn kho'
                              : o.status.displayName,
                          pillBg: isDone
                              ? const Color(0xFFDCFCE7)
                              : isCancelled
                              ? const Color(0xFFFEE2E2)
                              : const Color(0xFFEFF3F8),
                          pillFg: isDone
                              ? const Color(0xFF14B866)
                              : isCancelled
                              ? const Color(0xFFB91C1C)
                              : const Color(0xFF2563EB),
                        ),
                      );
                    }),
                ],
              ),
            );

            if (isDesktopRow) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: revenueChartCard),
                  const SizedBox(width: 16),
                  Expanded(flex: 3, child: statusDonutCard),
                  const SizedBox(width: 16),
                  Expanded(flex: 5, child: newestOrdersCard),
                ],
              );
            }
            return Column(
              children: [
                revenueChartCard,
                const SizedBox(height: 16),
                statusDonutCard,
                const SizedBox(height: 16),
                newestOrdersCard,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildGoMauKpiCard({
    double? width,
    required String title,
    required String value,
    required String delta,
    required bool deltaPositive,
    required Color badgeColor,
    required IconData icon,
    required bool showSparkline,
    required Color sparklineColor,
    List<double> sparklineFactors = const [],
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(12)),
        border: Border.all(color: const Color(0xFF0F172A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: GhstButtonIcon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF4A4754),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        Text(
                          value,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          delta,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: deltaPositive
                                ? const Color(0xFF14B866)
                                : const Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showSparkline && sparklineFactors.length >= 2) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 28,
              width: double.infinity,
              child: CustomPaint(
                painter: _MiniSparklinePainter(
                  color: sparklineColor,
                  yFactors: sparklineFactors,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDonutLegendRow(Color dotColor, String text) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNewestOrderRow({
    required String code,
    required String customer,
    required String driver,
    required String amount,
    required String statusLabel,
    required Color pillBg,
    required Color pillFg,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              customer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              driver,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              amount,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: Text(
                statusLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: pillFg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// UC23: Quản lý Người dùng & Cửa hàng (Chuẩn uc23_nguoi_dung_1791015002658.jpg)
  Widget _buildUserAndMerchantManagementView() {
    final canManageUsers = _store.hasAdminPermission('User: Khóa/Mở');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(12)),
        border: Border.all(color: const Color(0xFF0F172A)),
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
                'Quản lý Tài khoản Người dùng & Đối tác (${_store.users.length} tài khoản)',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Color(0xFF0F172A),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                ),
                onPressed: canManageUsers
                    ? () => _showCreateUserAccountDialog(context)
                    : null,
                icon: const GhstButtonIcon(Icons.person_add_alt_1, size: 16),
                label: const Text('+ Thêm tài khoản'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                [
                  ('ALL', 'Tất cả vai trò'),
                  ('CUSTOMER', 'Khách hàng'),
                  ('DRIVER', 'Tài xế'),
                  ('MERCHANT', 'Cửa hàng B2B'),
                  ('ADMIN', 'Quản trị viên'),
                ].map((item) {
                  return ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel(item.$2, size: 15), label: Text(item.$2), selected: _userRoleFilter == item.$1, onSelected: (_) =>
                        _rebuildAdminUi(() => _userRoleFilter = item.$1),);
                }).toList(),
          ),
          const SizedBox(height: 12),
          if (_store.users
              .where(
                (u) =>
                    _userRoleFilter == 'ALL' || u.roleDbCode == _userRoleFilter,
              )
              .isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Không tìm thấy tài khoản người dùng nào phù hợp bộ lọc hiện tại.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF4F7FA),
                ),
                columns: const [
                  DataColumn(label: Text('ID')),
                  DataColumn(label: Text('Họ và tên')),
                  DataColumn(label: Text('Số điện thoại')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Vai trò')),
                  DataColumn(label: Text('Trạng thái')),
                ],
                rows: _store.users
                    .where(
                      (u) =>
                          _userRoleFilter == 'ALL' ||
                          u.roleDbCode == _userRoleFilter,
                    )
                    .map((u) {
                      return DataRow(
                        cells: [
                          DataCell(Text(u.id)),
                          DataCell(
                            Text(
                              u.fullName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              SecurityAndBarcodeUtils.maskPhoneNumber(
                                u.phone,
                                shouldMask: !canManageUsers,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              u.email.isEmpty
                                  ? 'Chưa cập nhật'
                                  : (canManageUsers
                                        ? u.email
                                        : '***@${u.email.split("@").last}'),
                            ),
                          ),
                          DataCell(
                            Chip(
                              label: Text(
                                u.role.title,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            ActionChip(
                              onPressed: canManageUsers
                                  ? () {
                                      if (u.role == SubsystemRole.admin ||
                                          u.id ==
                                              _store
                                                  .activeAuthenticatedUser
                                                  ?.id) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            backgroundColor: AppColors.danger,
                                            content: Text(
                                              'Không được phép tự khóa tài khoản Quản trị viên đang điều hành!',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      _store.toggleUserAccountStatus(u.id);
                                    }
                                  : null,
                              backgroundColor: u.status == 'ACTIVE'
                                  ? AppColors.success.withValues(alpha: 0.14)
                                  : AppColors.danger.withValues(alpha: 0.14),
                              avatar: GhstButtonIcon.glyph(u.status == 'ACTIVE' ? GhstActionKind.checkCircle : GhstActionKind.lock, size: 14, color: u.status == 'ACTIVE' ? AppColors.success : AppColors.danger),
                              label: Text(
                                u.status == 'ACTIVE' ? 'Hoạt động' : 'Đã khóa',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: u.status == 'ACTIVE'
                                      ? AppColors.success
                                      : AppColors.danger,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    })
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  void _showCreateUserAccountDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final pwdCtrl = TextEditingController();
    SubsystemRole selectedRole = SubsystemRole.customer;

    final canCreateAdminRole = _store.hasAdminPermission('Hệ thống: Bảo mật');
    Animation<double>? dialogRouteAnim;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        dialogRouteAnim ??= ModalRoute.of(dialogCtx)?.animation;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Thêm tài khoản Người dùng / Đối tác',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Họ và tên / Tên đơn vị',
                        hintText: 'Nhập họ và tên hoặc tên cửa hàng',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại (9-11 chữ số)',
                        hintText: 'VD: 0908123456',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email liên hệ',
                        hintText: 'VD: lienhe@donvi.vn',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: pwdCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Mật khẩu khởi tạo',
                        hintText: 'Nhập tối thiểu 6 ký tự',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<SubsystemRole>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), initialValue: selectedRole, decoration: const InputDecoration(
                        labelText: 'Phân quyền vai trò',
                      ), items: [
                        const DropdownMenuItem(
                          value: SubsystemRole.customer,
                          child: Text('Khách hàng'),
                        ),
                        const DropdownMenuItem(
                          value: SubsystemRole.driver,
                          child: Text('Tài xế'),
                        ),
                        const DropdownMenuItem(
                          value: SubsystemRole.merchant,
                          child: Text('Cửa hàng B2B'),
                        ),
                        if (canCreateAdminRole)
                          const DropdownMenuItem(
                            value: SubsystemRole.admin,
                            child: Text('Quản trị viên'),
                          ),
                      ], onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedRole = v);
                        }
                      },),
                  ],
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

                  label: const Text('Hủy'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                  ),
                  onPressed: () {
                    if (pwdCtrl.text.trim().length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Vui lòng nhập mật khẩu khởi tạo tối thiểu 6 ký tự!',
                          ),
                        ),
                      );
                      return;
                    }
                    final created = _store.registerUserAccountWithRole(
                      phone: phoneCtrl.text.trim(),
                      fullName: nameCtrl.text.trim(),
                      password: pwdCtrl.text.trim(),
                      role: selectedRole,
                      email: emailCtrl.text.trim(),
                      activateSession: false,
                    );
                    if (created == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Vui lòng nhập Họ tên và Số điện thoại hợp lệ (chưa trùng lặp, tối thiểu 9 chữ số)!',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.of(dialogCtx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã tạo tài khoản ${created.id} (${created.phone} • ${created.role.title}) thành công!',
                        ),
                      ),
                    );
                  },
                  icon: const GhstButtonIcon.glyph(GhstActionKind.userPlus, size: 16),

                  label: const Text('Tạo tài khoản'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      SecurityAndBarcodeUtils.disposeControllersAfterDialog([
        nameCtrl,
        phoneCtrl,
        emailCtrl,
        pwdCtrl,
      ], dialogRouteAnim);
    });
  }

  /// UC24: Xét duyệt Hồ sơ Tài xế & Đối tác Cửa hàng B2B KYC
  Widget _buildDriverKycApprovalView() {
    final canViewDrivers = _store.hasAdminPermission('Tài xế: Xem');
    final canApproveDriver = _store.hasAdminPermission('Tài xế: Phê duyệt');
    final canEditDriver = _store.hasAdminPermission('Tài xế: Chỉnh sửa');
    final canSuspendDriver = _store.hasAdminPermission('Tài xế: Đình chỉ');
    if (!canViewDrivers) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quản lý Hồ sơ Tài xế & Đối tác B2B',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                '🔒 Vai trò điều hành hiện tại không có quyền "Tài xế: Xem" để truy cập hồ sơ đối tác.',
                style: TextStyle(color: AppColors.danger),
              ),
            ],
          ),
        ),
      );
    }
    final safeDrvIdx = _store.drivers.isEmpty
        ? 0
        : _selectedKycDriverIndex.clamp(0, _store.drivers.length - 1);
    final featuredDriver = _store.drivers.isNotEmpty
        ? _store.drivers[safeDrvIdx]
        : null;
    final safeMerIdx = _store.merchantApplicants.isEmpty
        ? 0
        : _selectedKycMerchantIndex.clamp(
            0,
            _store.merchantApplicants.length - 1,
          );
    final featuredMerchant = _store.merchantApplicants.isNotEmpty
        ? _store.merchantApplicants[safeMerIdx]
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final colLeft = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(12)),
            border: Border.all(color: const Color(0xFF0F172A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '1. Danh sách Hồ sơ Đăng ký Tài xế',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                'Khi bấm "Duyệt hồ sơ", hệ thống tự động nâng cấp tài khoản tương ứng lên vai trò Tài xế và kích hoạt quyền nhận chuyến.',
                style: TextStyle(fontSize: 12, color: Color(0xFF4A4754)),
              ),
              if (!canApproveDriver)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    '🔒 Vai trò hiện tại không có quyền "Tài xế: Phê duyệt" (Cấu hình tại mục Phân quyền RBAC).',
                    style: TextStyle(color: AppColors.danger, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              if (_store.drivers.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Chưa có hồ sơ đăng ký tài xế nào trong hệ thống.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else
                ..._store.drivers.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final drv = entry.value;
                  final isSelected =
                      !_selectedKycIsMerchant && idx == safeDrvIdx;
                  return InkWell(
                    onTap: () => _rebuildAdminUi(() {
                      _selectedKycIsMerchant = false;
                      _selectedKycDriverIndex = idx;
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFEDE9FE)
                            : const Color(0xFFF4F7FA),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.violet
                              : const Color(0xFF0F172A),
                          width: isSelected ? 1.8 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${drv.id} • ${drv.fullName} (${drv.phone})',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'CCCD: ${drv.citizenId} • Xe: ${drv.vehicleType} (${drv.licensePlate}) • Trạng thái: ${drv.approvalStatus}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                ),
                                onPressed:
                                    canApproveDriver &&
                                        drv.approvalStatus != 'Đã duyệt'
                                    ? () {
                                        _rebuildAdminUi(
                                          () => _selectedKycDriverIndex = idx,
                                        );
                                        _store.updateDriverApproval(
                                          drv.id,
                                          'Đã duyệt',
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Đã duyệt hồ sơ tài xế ${drv.fullName} (${drv.id})!',
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                                icon: GhstButtonIcon.forLabel(drv.approvalStatus == 'Đã duyệt'
                                      ? 'Đã duyệt'
                                      : 'Duyệt hồ sơ', size: 16),

                                label: Text(
                                  drv.approvalStatus == 'Đã duyệt'
                                      ? 'Đã duyệt'
                                      : 'Duyệt hồ sơ',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed:
                                    canApproveDriver &&
                                        drv.approvalStatus != 'Từ chối'
                                    ? () {
                                        _rebuildAdminUi(
                                          () => _selectedKycDriverIndex = idx,
                                        );
                                        _store.updateDriverApproval(
                                          drv.id,
                                          'Từ chối',
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Đã từ chối hồ sơ tài xế ${drv.fullName} (${drv.id}).',
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                                icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

                                label: const Text(
                                  'Từ chối',
                                  style: TextStyle(color: AppColors.danger),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: canEditDriver
                                    ? () => _showAdminEditDriverVehicleDialog(
                                        context,
                                        drv,
                                      )
                                    : null,
                                icon: const GhstButtonIcon(
                                  Icons.edit_road_rounded,
                                  size: 15,
                                ),
                                label: const Text('Sửa xe'),
                              ),
                              OutlinedButton.icon(
                                onPressed:
                                    canSuspendDriver &&
                                        (drv.approvalStatus == 'Đã duyệt' ||
                                            drv.approvalStatus == 'Đình chỉ')
                                    ? () {
                                        final ok = _store
                                            .suspendOrUnsuspendDriver(drv.id);
                                        if (!ok) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              drv.approvalStatus == 'Đình chỉ'
                                                  ? 'Đã đình chỉ hoạt động tài xế ${drv.fullName} (${drv.id}).'
                                                  : 'Đã mở đình chỉ tài xế ${drv.fullName} (${drv.id}).',
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                                icon: GhstButtonIcon(
                                  drv.approvalStatus == 'Đình chỉ'
                                      ? Icons.lock_open_rounded
                                      : Icons.pause_circle_outline_rounded,
                                  size: 15,
                                  color: drv.approvalStatus == 'Đình chỉ'
                                      ? AppColors.success
                                      : AppColors.warning,
                                ),
                                label: Text(
                                  drv.approvalStatus == 'Đình chỉ'
                                      ? 'Mở đình chỉ'
                                      : 'Đình chỉ',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const Divider(height: 24),
              const Text(
                '2. Danh sách Hồ sơ Đăng ký Cửa hàng B2B',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                'Khi bấm "Duyệt cửa hàng", hệ thống tự động nâng cấp tài khoản tương ứng lên vai trò Cửa hàng B2B và mở khóa chức năng vận đơn doanh nghiệp.',
                style: TextStyle(fontSize: 12, color: Color(0xFF4A4754)),
              ),
              const SizedBox(height: 12),
              if (_store.merchantApplicants.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Chưa có hồ sơ đăng ký cửa hàng B2B nào trong hệ thống.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else
                ..._store.merchantApplicants.asMap().entries.map((mEntry) {
                  final mIdx = mEntry.key;
                  final mer = mEntry.value;
                  final isMerSelected =
                      _selectedKycIsMerchant && mIdx == safeMerIdx;
                  return InkWell(
                    onTap: () => _rebuildAdminUi(() {
                      _selectedKycIsMerchant = true;
                      _selectedKycMerchantIndex = mIdx;
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMerSelected
                            ? const Color(0xFFEDE9FE)
                            : const Color(0xFFF4F7FA),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        border: Border.all(
                          color: isMerSelected
                              ? AppColors.violet
                              : const Color(0xFF0F172A),
                          width: isMerSelected ? 1.8 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${mer.id} • ${mer.storeName} (${mer.ownerPhone})',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'MST: ${mer.taxCode} • Loại hình: ${mer.businessType} • Đại diện: ${mer.representativeName}\nNgân hàng COD: ${mer.bankName} (${mer.bankAccount}) • Trạng thái: ${mer.approvalStatus}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                ),
                                onPressed:
                                    canApproveDriver &&
                                        mer.approvalStatus != 'Đã duyệt'
                                    ? () {
                                        _rebuildAdminUi(() {
                                          _selectedKycIsMerchant = true;
                                          _selectedKycMerchantIndex = mIdx;
                                        });
                                        _store.updateMerchantApproval(
                                          mer.id,
                                          'Đã duyệt',
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Đã duyệt cửa hàng ${mer.storeName} (${mer.id})!',
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                                icon: GhstButtonIcon.forLabel(mer.approvalStatus == 'Đã duyệt'
                                      ? 'Đã duyệt'
                                      : 'Duyệt cửa hàng', size: 16),

                                label: Text(
                                  mer.approvalStatus == 'Đã duyệt'
                                      ? 'Đã duyệt'
                                      : 'Duyệt cửa hàng',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed:
                                    canApproveDriver &&
                                        mer.approvalStatus != 'Từ chối'
                                    ? () {
                                        _rebuildAdminUi(() {
                                          _selectedKycIsMerchant = true;
                                          _selectedKycMerchantIndex = mIdx;
                                        });
                                        _store.updateMerchantApproval(
                                          mer.id,
                                          'Từ chối',
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Đã từ chối hồ sơ cửa hàng ${mer.storeName} (${mer.id}).',
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                                icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

                                label: const Text(
                                  'Từ chối',
                                  style: TextStyle(color: AppColors.danger),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
        final colRight = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(12)),
            border: Border.all(color: const Color(0xFF0F172A)),
          ),
          child: (_selectedKycIsMerchant && featuredMerchant != null)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chi tiết Hồ sơ Pháp lý B2B: ${featuredMerchant.storeName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '• Mã đối tác: ${featuredMerchant.id} (SĐT: ${featuredMerchant.ownerPhone})',
                    ),
                    Text(
                      '• Mã số thuế / ĐKKD: ${featuredMerchant.taxCode} (${featuredMerchant.businessType})',
                    ),
                    Text(
                      '• Người đại diện pháp luật: ${featuredMerchant.representativeName}',
                    ),
                    Text(
                      '• Khung giờ hoạt động: ${featuredMerchant.openHours}',
                    ),
                    Text(
                      '• Tài khoản nhận đối soát COD: ${featuredMerchant.bankName} - ${featuredMerchant.bankAccount}',
                    ),
                    Text(
                      '• Trạng thái xét duyệt: ${featuredMerchant.approvalStatus}',
                    ),
                    if (featuredMerchant.attachedKycDocs.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: featuredMerchant.attachedKycDocs
                            .map(
                              (doc) => ActionChip(
                                visualDensity: VisualDensity.compact,
                                avatar: const GhstButtonIcon(
                                  Icons.insert_drive_file_outlined,
                                  size: 14,
                                ),
                                label: Text(
                                  doc,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () => _showKycDocumentInspectDialog(
                                  context,
                                  docTitle: 'Tệp đính kèm thực tế: $doc',
                                  applicantName: featuredMerchant.storeName,
                                  details:
                                      '• Tên tệp đối tác tải lên: $doc\n• Mã cửa hàng: ${featuredMerchant.id}\n• Mã số thuế: ${featuredMerchant.taxCode}\n• Trạng thái xét duyệt: ${featuredMerchant.approvalStatus}',
                                  onQuickApprove:
                                      canApproveDriver &&
                                          featuredMerchant.approvalStatus !=
                                              'Đã duyệt'
                                      ? () => _store.updateMerchantApproval(
                                          featuredMerchant.id,
                                          'Đã duyệt',
                                        )
                                      : null,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          '• Tệp đính kèm từ thiết bị: Chưa tải lên tệp chứng từ mới.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    const Divider(height: 20),
                    const Text(
                      'Hồ sơ pháp lý B2B đính kèm đã tải lên (Bấm để đối chiếu):',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: const GhstButtonIcon(Icons.business_outlined, size: 16),
                          label: const Text('Giấy phép ĐKKD B2B'),
                          onPressed: () => _showKycDocumentInspectDialog(
                            context,
                            docTitle: 'Giấy phép ĐKKD B2B',
                            applicantName: featuredMerchant.storeName,
                            details:
                                '• Mã đối tác: ${featuredMerchant.id}\n• Loại hình: ${featuredMerchant.businessType}\n• Người đại diện pháp luật: ${featuredMerchant.representativeName}\n• Khung giờ hoạt động: ${featuredMerchant.openHours}\n• Trạng thái hiện tại: ${featuredMerchant.approvalStatus}',
                            onQuickApprove:
                                canApproveDriver &&
                                    featuredMerchant.approvalStatus !=
                                        'Đã duyệt'
                                ? () => _store.updateMerchantApproval(
                                    featuredMerchant.id,
                                    'Đã duyệt',
                                  )
                                : null,
                          ),
                        ),
                        ActionChip(
                          avatar: const GhstButtonIcon(
                            Icons.receipt_long_outlined,
                            size: 16,
                          ),
                          label: const Text('Chứng nhận Mã số thuế'),
                          onPressed: () => _showKycDocumentInspectDialog(
                            context,
                            docTitle: 'Chứng nhận Đăng ký Mã số thuế',
                            applicantName: featuredMerchant.storeName,
                            details:
                                '• Mã số thuế doanh nghiệp: ${featuredMerchant.taxCode}\n• Chủ sở hữu / SĐT: ${featuredMerchant.ownerPhone}\n• Ngành nghề đăng ký: ${featuredMerchant.businessType}',
                            onQuickApprove:
                                canApproveDriver &&
                                    featuredMerchant.approvalStatus !=
                                        'Đã duyệt'
                                ? () => _store.updateMerchantApproval(
                                    featuredMerchant.id,
                                    'Đã duyệt',
                                  )
                                : null,
                          ),
                        ),
                        ActionChip(
                          avatar: const GhstButtonIcon(
                            Icons.account_balance_outlined,
                            size: 16,
                          ),
                          label: const Text('Tài khoản Đối soát COD'),
                          onPressed: () => _showKycDocumentInspectDialog(
                            context,
                            docTitle:
                                'Thông tin Tài khoản Đối soát & Thanh toán COD',
                            applicantName: featuredMerchant.storeName,
                            details:
                                '• Ngân hàng thụ hưởng: ${featuredMerchant.bankName}\n• Số tài khoản nhận COD: ${featuredMerchant.bankAccount}\n• Số dư COD hiện tại: ${CurrencyFormatter.formatVnd(featuredMerchant.codBalance)}\n• Trạng thái hồ sơ: ${featuredMerchant.approvalStatus}',
                            onQuickApprove:
                                canApproveDriver &&
                                    featuredMerchant.approvalStatus !=
                                        'Đã duyệt'
                                ? () => _store.updateMerchantApproval(
                                    featuredMerchant.id,
                                    'Đã duyệt',
                                  )
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : _selectedKycIsMerchant
              ? const Text(
                  'Chưa có hồ sơ đăng ký cửa hàng B2B nào trong hệ thống.',
                )
              : featuredDriver == null
              ? const Text('Chưa có hồ sơ tài xế nào trong hệ thống.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chi tiết Hồ sơ Pháp lý: ${featuredDriver.fullName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '• Mã định danh: ${featuredDriver.id} (${featuredDriver.phone})',
                    ),
                    Text('• Số CCCD gắn chip: ${featuredDriver.citizenId}'),
                    Text(
                      '• Phương tiện: ${featuredDriver.vehicleType} (${featuredDriver.licensePlate})',
                    ),
                    Text(
                      '• Ngân hàng & Ký quỹ: ${featuredDriver.bankName} (${featuredDriver.bankAccount}) • Ví: ${CurrencyFormatter.formatVnd(featuredDriver.walletBalance)}',
                    ),
                    Text(
                      '• Trạng thái xét duyệt: ${featuredDriver.approvalStatus}',
                    ),
                    if (featuredDriver.attachedKycDocs.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: featuredDriver.attachedKycDocs
                            .map(
                              (doc) => ActionChip(
                                visualDensity: VisualDensity.compact,
                                avatar: const GhstButtonIcon(
                                  Icons.insert_drive_file_outlined,
                                  size: 14,
                                ),
                                label: Text(
                                  doc,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () => _showKycDocumentInspectDialog(
                                  context,
                                  docTitle: 'Tệp chứng từ thực tế: $doc',
                                  applicantName: featuredDriver.fullName,
                                  details:
                                      '• Tên tệp tài xế tải lên: $doc\n• Mã định danh: ${featuredDriver.id} (${featuredDriver.phone})\n• CCCD: ${featuredDriver.citizenId} • Biển số: ${featuredDriver.licensePlate}\n• Trạng thái xét duyệt: ${featuredDriver.approvalStatus}',
                                  onQuickApprove:
                                      canApproveDriver &&
                                          featuredDriver.approvalStatus !=
                                              'Đã duyệt'
                                      ? () => _store.updateDriverApproval(
                                          featuredDriver.id,
                                          'Đã duyệt',
                                        )
                                      : null,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          '• Chứng từ đính kèm từ thiết bị: Chưa tải lên tệp ảnh mới.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    const Divider(height: 20),
                    const Text(
                      'Tài liệu đính kèm đã tải lên (Bấm để đối chiếu):',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: const GhstButtonIcon(Icons.badge_outlined, size: 16),
                          label: const Text('CCCD Mặt trước & sau'),
                          onPressed: () => _showKycDocumentInspectDialog(
                            context,
                            docTitle: 'Căn cước công dân gắn chip (2 mặt)',
                            applicantName: featuredDriver.fullName,
                            details:
                                '• Họ và tên: ${featuredDriver.fullName}\n• Số CCCD: ${featuredDriver.citizenId}\n• Số điện thoại xác thực: ${featuredDriver.phone}\n• Tệp đính kèm: ${featuredDriver.attachedKycDocs.isEmpty ? "Chưa tải tệp" : featuredDriver.attachedKycDocs.first}\n• Trạng thái eKYC: ${featuredDriver.approvalStatus == "Đã duyệt"
                                    ? "Đã xác thực bởi Quản trị viên"
                                    : featuredDriver.approvalStatus == "Từ chối"
                                    ? "Hồ sơ không đạt yêu cầu"
                                    : "Đang chờ đối chiếu nhân công"}',
                            onQuickApprove:
                                canApproveDriver &&
                                    featuredDriver.approvalStatus != 'Đã duyệt'
                                ? () => _store.updateDriverApproval(
                                    featuredDriver.id,
                                    'Đã duyệt',
                                  )
                                : null,
                          ),
                        ),
                        ActionChip(
                          avatar: const GhstButtonIcon(Icons.credit_card, size: 16),
                          label: const Text('Bằng lái xe A1/B2'),
                          onPressed: () => _showKycDocumentInspectDialog(
                            context,
                            docTitle: 'Giấy phép lái xe (Hạng A1/B2)',
                            applicantName: featuredDriver.fullName,
                            details:
                                '• Chủ GPLX: ${featuredDriver.fullName}\n• Hạng GPLX đăng ký: Phù hợp ${featuredDriver.vehicleType}\n• Tệp GPLX: ${featuredDriver.attachedKycDocs.length >= 2 ? featuredDriver.attachedKycDocs[1] : "Chưa tải tệp"}\n• Tình trạng xét duyệt: ${featuredDriver.approvalStatus}',
                            onQuickApprove:
                                canApproveDriver &&
                                    featuredDriver.approvalStatus != 'Đã duyệt'
                                ? () => _store.updateDriverApproval(
                                    featuredDriver.id,
                                    'Đã duyệt',
                                  )
                                : null,
                          ),
                        ),
                        ActionChip(
                          avatar: const GhstButtonIcon(Icons.two_wheeler, size: 16),
                          label: const Text('Đăng ký xe (Cà vẹt)'),
                          onPressed: () => _showKycDocumentInspectDialog(
                            context,
                            docTitle: 'Chứng nhận Đăng ký xe (Cà vẹt)',
                            applicantName: featuredDriver.fullName,
                            details:
                                '• Loại phương tiện: ${featuredDriver.vehicleType} (${featuredDriver.vehicleColor})\n• Biển kiểm soát: ${featuredDriver.licensePlate}\n• Tệp Cà vẹt: ${featuredDriver.attachedKycDocs.length >= 3 ? featuredDriver.attachedKycDocs[2] : "Chưa tải tệp"}\n• Chủ phương tiện: ${featuredDriver.fullName}',
                            onQuickApprove:
                                canApproveDriver &&
                                    featuredDriver.approvalStatus != 'Đã duyệt'
                                ? () => _store.updateDriverApproval(
                                    featuredDriver.id,
                                    'Đã duyệt',
                                  )
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
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
            Expanded(flex: 6, child: colLeft),
            const SizedBox(width: 16),
            Expanded(flex: 5, child: colRight),
          ],
        );
      },
    );
  }

  void _showKycDocumentInspectDialog(
    BuildContext context, {
    required String docTitle,
    required String applicantName,
    required String details,
    VoidCallback? onQuickApprove,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          '$docTitle — $applicantName',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
        ),
        content: Text(details, style: const TextStyle(height: 1.45)),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

            label: const Text('Đóng'),
          ),
          if (onQuickApprove != null)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
              onPressed: () {
                onQuickApprove();
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Đã xác thực chứng từ "$docTitle" và phê duyệt hồ sơ $applicantName!',
                    ),
                  ),
                );
              },
              icon: const GhstButtonIcon(Icons.verified_outlined, size: 16),
              label: const Text('Xác thực & Duyệt ngay'),
            ),
        ],
      ),
    );
  }

  /// UC25: Bản đồ Giám sát Đội xe GPS Toàn Thành phố (Chuẩn uc25_giam_sat_gps)
  Widget _buildFleetLiveGpsMonitorView() {
    if (!_store.hasAdminPermission('Tài xế: Xem')) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bản đồ Giám sát Đội xe GPS Thời gian thực',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                '🔒 Vai trò điều hành hiện tại không có quyền "Tài xế: Xem" để truy cập tọa độ GPS trực tuyến của đội xe.',
                style: TextStyle(color: AppColors.danger),
              ),
            ],
          ),
        ),
      );
    }

    final approvedDrivers = _store.drivers
        .where((d) => d.approvalStatus == 'Đã duyệt')
        .toList();
    final unapprovedCount = (_store.drivers.length - approvedDrivers.length)
        .clamp(0, _store.drivers.length);
    final busyDriverNames = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.accepted ||
              o.status == OrderStatus.arrivingPickup ||
              o.status == OrderStatus.inTransit ||
              o.status == OrderStatus.returning,
        )
        .map((o) => o.assignedDriverName)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet();
    final onlineApprovedDrivers = approvedDrivers
        .where((d) => d.isOnline)
        .toList();
    final offlineApprovedDrivers = approvedDrivers
        .where((d) => !d.isOnline)
        .toList();
    final busyCount = onlineApprovedDrivers
        .where((d) => busyDriverNames.contains(d.fullName))
        .length;
    final freeOnlineCount = onlineApprovedDrivers
        .where((d) => !busyDriverNames.contains(d.fullName))
        .length;
    final focusedDriver =
        (_focusedFleetDriverId != null
            ? approvedDrivers
                  .where((d) => d.id == _focusedFleetDriverId)
                  .firstOrNull
            : null) ??
        onlineApprovedDrivers.firstOrNull ??
        approvedDrivers.firstOrNull;
    final focusedLocation =
        focusedDriver?.location ?? _store.activeDriverLocation;
    final activeOrder = _store.activeOrderRecord ?? _store.orders.firstOrNull;
    final roadCandidates = onlineApprovedDrivers
        .where((driver) {
          final vehicle = driver.vehicleType.toLowerCase();
          final compatible =
              activeOrder?.serviceType != DeliveryServiceType.truck ||
              vehicle.contains('tải') ||
              vehicle.contains('truck') ||
              vehicle.contains('van');
          return compatible &&
              driver.walletBalance >= 200000 &&
              !busyDriverNames.contains(driver.fullName) &&
              _store.verifiedDriverLocations.containsKey(driver.id);
        })
        .map(
          (driver) => RoadDispatchCandidate(
            id: driver.id,
            name: '${driver.fullName} (${driver.licensePlate})',
            location: _store.verifiedDriverLocations[driver.id]!,
          ),
        )
        .toList();
    final hasFocusedActiveRoute =
        activeOrder != null &&
        focusedDriver != null &&
        activeOrder.assignedDriverName == focusedDriver.fullName &&
        (activeOrder.status == OrderStatus.accepted ||
            activeOrder.status == OrderStatus.arrivingPickup ||
            activeOrder.status == OrderStatus.inTransit ||
            activeOrder.status == OrderStatus.returning);
    final fleetRoutePoints = hasFocusedActiveRoute
        ? (_store.activeRoutePolyline.length >= 2 &&
                  _store.activeDriverId == focusedDriver.id
              ? _store.activeRoutePolyline
              : SmartDispatchEngine.generateRoutePolyline(
                  activeOrder.pickupLocation,
                  activeOrder.dropoffLocation,
                  segments: 12,
                ))
        : const <GeoPoint>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bản đồ Giám sát Đội xe GPS Thời gian thực',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Đang rảnh: $freeOnlineCount xe (Xanh lá)')),
                Chip(label: Text('Đang giao hàng: $busyCount xe (Cam)')),
                Chip(
                  label: Text(
                    'Đã duyệt • Ngoại tuyến: ${offlineApprovedDrivers.length} xe (Xám)',
                  ),
                ),
                if (unapprovedCount > 0)
                  Chip(
                    label: Text(
                      'Hồ sơ chờ duyệt / từ chối: $unapprovedCount (Chưa cấp phép chạy)',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_store.orders.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _store.orders.map((ord) {
                  final isFocused =
                      ord.trackingCode == activeOrder?.trackingCode;
                  return ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.glyph(GhstActionKind.receipt, size: 15, color: (isFocused) ? Colors.white : null), visualDensity: VisualDensity.compact, label: Text(
                      '${ord.trackingCode} (${ord.assignedDriverName ?? "Chưa có TX"} • ${ord.paymentStatus == "RETURNED" ? "Đã hoàn kho" : ord.status.displayName})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isFocused ? Colors.white : AppColors.ink,
                      ),
                    ), selected: isFocused, selectedColor: AppColors.violet, onSelected: (_) {
                      final matchedDrv = approvedDrivers
                          .where((d) => d.fullName == ord.assignedDriverName)
                          .firstOrNull;
                      _rebuildAdminUi(() {
                        _focusedFleetDriverId = matchedDrv?.id;
                      });
                      _store.selectCustomerOrder(ord.trackingCode);
                      _store.selectDriverOrder(ord.trackingCode);
                    },);
                }).toList(),
              ),
            const SizedBox(height: AppSpacing.sm),
            Map3dPerspectiveWidget(
              height: 560,
              mode: MapViewMode.fleetOverview,
              is3dMode: _store.isMap3dEnabled,
              speedKmh:
                  focusedDriver != null &&
                      focusedDriver.isOnline &&
                      busyDriverNames.contains(focusedDriver.fullName)
                  ? _store.currentSpeedKmh
                  : 0.0,
              onToggle3d: _store.toggleMap3d,
              progressFraction: _store.routeProgressStep / 10.0,
              routePoints: fleetRoutePoints,
              customFleetDrivers: approvedDrivers,
              focusedCenterPoint: focusedLocation,
              nextTurnInstruction:
                  'Trung tâm Giám sát Đội xe • ${onlineApprovedDrivers.length}/${approvedDrivers.length} xe trực tuyến',
              roadName: focusedDriver != null
                  ? 'Tâm bản đồ: ${focusedDriver.fullName} (${focusedDriver.licensePlate} • ${focusedDriver.vehicleType}) • (${focusedLocation.latitude.toStringAsFixed(4)}, ${focusedLocation.longitude.toStringAsFixed(4)})'
                  : (activeOrder != null
                        ? 'Đơn hoạt động: ${activeOrder.trackingCode} • Tọa độ xe: (${_store.activeDriverLocation.latitude.toStringAsFixed(4)}, ${_store.activeDriverLocation.longitude.toStringAsFixed(4)})'
                        : 'Chưa có đơn hàng hoạt động • Đội xe sẵn sàng'),
            ),
            if (activeOrder?.status == OrderStatus.searching)
              RoadDispatchComparison(
                key: ValueKey('road-${activeOrder!.trackingCode}'),
                pickup: activeOrder.pickupLocation,
                candidates: roadCandidates,
              ),
            BatchRouteOptimizer(store: _store),
            if (approvedDrivers.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: approvedDrivers.map((d) {
                  final isBusy =
                      d.isOnline && busyDriverNames.contains(d.fullName);
                  final isSelectedDrv = focusedDriver?.id == d.id;
                  final stateColor = !d.isOnline
                      ? AppColors.textSecondary
                      : (isBusy ? AppColors.accent : AppColors.success);
                  final stateText = !d.isOnline
                      ? 'Ngoại tuyến'
                      : (isBusy ? 'Đang giao' : 'Rảnh');
                  return ChoiceChip(showCheckmark: false, visualDensity: VisualDensity.compact, selected: isSelectedDrv, selectedColor: AppColors.violet.withValues(alpha: 0.16), avatar: GhstButtonIcon(
                      d.isOnline
                          ? Icons.navigation_rounded
                          : Icons.portable_wifi_off_outlined,
                      size: 14,
                      color: stateColor,
                    ), label: Text(
                      '${d.fullName} (${d.licensePlate}) • (${d.location.latitude.toStringAsFixed(4)}, ${d.location.longitude.toStringAsFixed(4)}) • $stateText',
                      style: const TextStyle(fontSize: 11),
                    ), onSelected: (_) {
                      _rebuildAdminUi(() => _focusedFleetDriverId = d.id);
                      final drvActiveOrd = _store.orders
                          .where(
                            (o) =>
                                o.assignedDriverName == d.fullName &&
                                (o.status == OrderStatus.accepted ||
                                    o.status == OrderStatus.arrivingPickup ||
                                    o.status == OrderStatus.inTransit ||
                                    o.status == OrderStatus.returning),
                          )
                          .firstOrNull;
                      if (drvActiveOrd != null) {
                        _store.selectCustomerOrder(drvActiveOrd.trackingCode);
                        _store.selectDriverOrder(drvActiveOrd.trackingCode);
                      }
                    },);
                }).toList(),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final msg = await _store.syncLiveOsrmRouteForActiveOrder();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(msg)));
                  },
                  icon: const GhstButtonIcon(Icons.alt_route_rounded, size: 16),
                  label: const Text('Đồng bộ lộ trình thực tế'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final msg = await _store.acquireRealHardwareGps();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(msg)));
                  },
                  icon: const GhstButtonIcon(Icons.my_location_rounded, size: 16),
                  label: const Text('Cập nhật định vị thiết bị'),
                ),
                if (activeOrder != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.violet,
                    ),
                    onPressed: () {
                      _rebuildAdminUi(() => _selectedScreenIndex = 8);
                    },
                    icon: const GhstButtonIcon(Icons.assignment_ind_outlined, size: 16),
                    label: Text('Điều phối đơn ${activeOrder.trackingCode}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAdminEditDriverVehicleDialog(
    BuildContext context,
    DriverApplicantRecord drv,
  ) {
    final plateCtrl = TextEditingController(text: drv.licensePlate);
    String selectedType = drv.vehicleType.contains('Tải')
        ? 'Xe Tải 500kg'
        : 'Xe Máy';
    Animation<double>? dialogRouteAnim;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        dialogRouteAnim ??= ModalRoute.of(dialogCtx)?.animation;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) => AlertDialog(
            title: Text(
              'Cập nhật phương tiện: ${drv.fullName} (${drv.id})',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Loại phương tiện vận chuyển:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: ['Xe Máy', 'Xe Tải 500kg']
                      .map(
                        (vt) => ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel(vt, size: 15), label: Text(vt), selected: selectedType == vt, onSelected: (_) =>
                              setDialogState(() => selectedType = vt),),
                      )
                      .toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: plateCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Biển kiểm soát',
                    hintText: '59-P1 123.45',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

                label: const Text('Hủy'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final plate = plateCtrl.text.trim();
                  if (plate.length < 5) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Vui lòng nhập biển kiểm soát hợp lệ (tối thiểu 5 ký tự)!',
                        ),
                      ),
                    );
                    return;
                  }
                  final ok = _store.adminUpdateDriverVehicleInfo(
                    driverId: drv.id,
                    vehicleType: selectedType,
                    licensePlate: plate,
                  );
                  Navigator.of(dialogCtx).pop();
                  if (ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã cập nhật phương tiện ${drv.fullName}: $selectedType ($plate)!',
                        ),
                      ),
                    );
                  }
                },
                icon: const GhstButtonIcon.glyph(GhstActionKind.save, size: 16),

                label: const Text('Lưu phương tiện'),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      SecurityAndBarcodeUtils.disposeControllersAfterDialog([
        plateCtrl,
      ], dialogRouteAnim);
    });
  }
}
