import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/config/env_config.dart';
import '../../core/gps/smart_dispatch_engine.dart';
import '../../core/gps/osrm_dispatch_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/geo_math.dart';
import '../../core/utils/security_and_barcode_utils.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import '../../domain/enums/order_status.dart';
import '../../domain/enums/service_type.dart';
import '../../domain/enums/user_role.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/auth_provider_settings.dart';
import '../widgets/batch_route_optimizer.dart';
import '../widgets/delivery_integration_status.dart';
import '../widgets/support_ai_summary.dart';
import '../widgets/road_dispatch_comparison.dart';
import '../widgets/system_state_screens.dart';
import '../screens/cloud_orders_screen.dart';

part 'admin_overview_and_fleet_views.dart';
part 'admin_config_and_governance_views.dart';

/// Phân hệ Quản trị viên (GO-MAU Admin Web Portal) - 12 màn hình
/// Giao diện phân hệ nghiệp vụ chuẩn thiết kế gốc (uc22..uc29, uc43..uc46).
class AdminSubsystemEntry extends StatefulWidget {
  final int? forcedScreenIndex;
  final VoidCallback? onLogout;

  const AdminSubsystemEntry({super.key, this.forcedScreenIndex, this.onLogout});

  @override
  State<AdminSubsystemEntry> createState() => _AdminSubsystemEntryState();
}

class _AdminSubsystemEntryState extends State<AdminSubsystemEntry> {
  final AppStateStore _store = AppStateStore.instance;
  int _selectedScreenIndex = 0; // Mặc định: Dashboard Tổng quan (UC22)

  // Cấu hình giá cước
  late final TextEditingController _baseFareCtrl;
  late final TextEditingController _perKmCtrl;

  // Trả lời khiếu nại
  final TextEditingController _replyTicketCtrl = TextEditingController();
  String _userRoleFilter = 'ALL';
  int _selectedComplaintIndex = 0;
  int _selectedKycDriverIndex = 0;
  int _selectedKycMerchantIndex = 0;
  bool _selectedKycIsMerchant = false;
  int _selectedDispatchDriverIndex = 0;

  // Kiểm tra điểm Geofence & Vẽ Polygon trực tiếp trên bản đồ
  final TextEditingController _testLatCtrl = TextEditingController();
  final TextEditingController _testLngCtrl = TextEditingController();
  final TextEditingController _newZoneNameCtrl = TextEditingController();
  String _newZoneType = 'SURCHARGE_ZONE';
  double _newZoneSurcharge = 20000;
  String? _focusedFleetDriverId;
  final List<GeoPoint> _draftPolygonGeoPoints = <GeoPoint>[];
  bool _geofenceTapTestMode = false;
  String _geofenceCheckResult =
      'Nhập tọa độ hoặc chọn chế độ Kiểm tra điểm rồi chạm lên bản đồ để xác định vùng hoạt động.';

  // Gửi thông báo Broadcast
  final TextEditingController _broadcastTitleCtrl = TextEditingController();
  String _broadcastTarget = 'Tất cả người dùng';

  // Chọn nhóm quyền RBAC & Cấu hình Cloud Supabase
  int _selectedRbacRoleIndex = 0;
  final TextEditingController _supabaseUrlCtrl = TextEditingController();
  final TextEditingController _supabaseAnonKeyCtrl = TextEditingController();

  static const List<String> _screenTitles = [
    'Bảng điều khiển',
    'Quản lý Người dùng',
    'Duyệt hồ sơ Đối tác',
    'Giám sát Đội xe GPS',
    'Giá cước & Khuyến mãi',
    'Báo cáo thống kê',
    'Khiếu nại & Hỗ trợ',
    'Tài chính & Rút tiền',
    'Điều phối Đơn hàng',
    'Vùng Geofence',
    'Thông báo hệ thống',
    'Phân quyền RBAC',
    'Vận hành thương mại',
    'API & Dịch vụ',
    'Đơn hàng cloud',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.forcedScreenIndex != null) {
      _selectedScreenIndex = widget.forcedScreenIndex!.clamp(
        0,
        _screenTitles.length - 1,
      );
    }
    _baseFareCtrl = TextEditingController(
      text: _store.baseFareConfig.toStringAsFixed(0),
    );
    _perKmCtrl = TextEditingController(
      text: _store.pricePerKmConfig.toStringAsFixed(0),
    );
    if (EnvConfig.isSupabaseConfigured) {
      _supabaseUrlCtrl.text = EnvConfig.supabaseUrl;
    }
    if (EnvConfig.supabaseAnonKey.isNotEmpty) {
      _supabaseAnonKeyCtrl.text = EnvConfig.supabaseAnonKey;
    }
    _store.addListener(_onStoreChanged);
  }

  @override
  void didUpdateWidget(covariant AdminSubsystemEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forcedScreenIndex != null &&
        widget.forcedScreenIndex != oldWidget.forcedScreenIndex) {
      _selectedScreenIndex = widget.forcedScreenIndex!.clamp(
        0,
        _screenTitles.length - 1,
      );
    }
  }

  String? _lastSyncedAdminPricingKey;

  void _onStoreChanged() {
    if (!mounted) return;
    final storeBase = _store.baseFareConfig.toStringAsFixed(0);
    final storePerKm = _store.pricePerKmConfig.toStringAsFixed(0);
    final pricingKey = '$storeBase|$storePerKm';
    if (_lastSyncedAdminPricingKey != pricingKey) {
      _lastSyncedAdminPricingKey = pricingKey;
      _baseFareCtrl.text = storeBase;
      _perKmCtrl.text = storePerKm;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _baseFareCtrl.dispose();
    _perKmCtrl.dispose();
    _replyTicketCtrl.dispose();
    _testLatCtrl.dispose();
    _testLngCtrl.dispose();
    _newZoneNameCtrl.dispose();
    _broadcastTitleCtrl.dispose();
    _supabaseUrlCtrl.dispose();
    _supabaseAnonKeyCtrl.dispose();
    super.dispose();
  }

  Icon3dStyle _adminScreen3dStyle(int index) {
    switch (index) {
      case 2:
      case 8:
        return Icon3dStyle.scooterExpress;
      case 3:
      case 9:
        return Icon3dStyle.gpsPinRadar;
      case 4:
      case 5:
      case 7:
      case 11:
        return Icon3dStyle.walletVault;
      default:
        return Icon3dStyle.parcelBox;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        if (isWide) {
          final sidebarWidth = (constraints.maxWidth * 0.185).clamp(
            210.0,
            290.0,
          );
          final contentPadding = (constraints.maxWidth * 0.02).clamp(
            16.0,
            32.0,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildGoMauAdminSidebar(sidebarWidth),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAdminWhiteTopBar(showLogout: false),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(contentPadding),
                        child: _buildActiveAdminScreen(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        final mobilePadding = (constraints.maxWidth * 0.035).clamp(10.0, 18.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAdminWhiteTopBar(),
            Padding(
              padding: EdgeInsets.fromLTRB(mobilePadding, 10, mobilePadding, 0),
              child: _buildScreenSelectorBar(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(mobilePadding),
                child: _buildActiveAdminScreen(context),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGoMauAdminSidebar(double sidebarWidth) {
    // Thứ tự hiển thị trên Sidebar giống uc22_dashboard.jpg:
    // Nhóm 1: Dashboard (0), Người dùng (1), Tài xế (2), Đơn hàng (8), Giám sát GPS (3)
    // Nhóm 2: Giá cước (4), Khuyến mãi (5), Khu vực Geofence (9), Khiếu nại (6), Tài chính (7), Thông báo Push (10), Cài đặt (11)
    const topGroupIndices = [0, 1, 2, 8, 3];
    const bottomGroupIndices = [4, 5, 9, 6, 7, 10, 11, 13, 14];

    return Container(
      width: sidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.techBg,
        border: Border(right: BorderSide(color: AppColors.ink, width: 1.6)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 16, 20),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.acid,
                        border: Border.all(color: AppColors.techBg),
                      ),
                      child: const Icon(
                        Icons.hexagon_outlined,
                        color: AppColors.techBg,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GO-MAU',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16.5,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'QUẢN TRỊ HỆ THỐNG',
                            style: TextStyle(
                              color: AppColors.acid,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ...topGroupIndices.map(_buildSidebarItem),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Divider(color: AppColors.techLine, height: 1),
              ),
              ...bottomGroupIndices.map(_buildSidebarItem),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Divider(color: AppColors.techLine, height: 1),
              ),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: const Icon(
                  Icons.logout_rounded,
                  color: AppColors.pink,
                  size: 19,
                ),
                title: const Text(
                  'Đăng xuất',
                  style: TextStyle(
                    color: AppColors.pink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onTap: widget.onLogout,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarItem(int index) {
    final selected = _selectedScreenIndex == index;
    const icons = [
      Icons.grid_view_rounded, // 0: Dashboard
      Icons.people_outline_rounded, // 1: Người dùng
      Icons.person_pin_circle_outlined, // 2: Tài xế
      Icons.location_on_outlined, // 3: Giám sát GPS
      Icons.paid_outlined, // 4: Giá cước
      Icons.analytics_outlined, // 5: Báo cáo thống kê
      Icons.chat_bubble_outline_rounded, // 6: Khiếu nại
      Icons.credit_card_rounded, // 7: Tài chính
      Icons.shopping_cart_outlined, // 8: Đơn hàng
      Icons.layers_outlined, // 9: Vùng Geofence
      Icons.notifications_active_outlined, // 10: Thông báo Push
      Icons.settings_outlined, // 11: Cài đặt
      Icons.sync_lock_outlined, // 12: Vận hành thương mại
      Icons.hub_outlined,
      Icons.cloud_outlined,
    ];
    final safeIcon = icons[index];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: InkWell(
        onTap: () => setState(() => _selectedScreenIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.violet.withValues(alpha: 0.25)
                : Colors.transparent,
            border: selected
                ? const Border(
                    left: BorderSide(color: AppColors.acid, width: 4.0),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                safeIcon,
                size: 19,
                color: selected ? AppColors.acid : AppColors.techMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _screenTitles[index],
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.techMuted,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminWhiteTopBar({bool showLogout = true}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showProfileText = constraints.maxWidth >= 640;
        final compact = constraints.maxWidth < 520;
        return Container(
          height: 64,
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: AppColors.ink, width: 1.5),
            ),
          ),
          child: Row(
            children: [
              Animated3dIconBadge(
                style: _adminScreen3dStyle(_selectedScreenIndex),
                size: compact ? 32 : 38,
                showRadarPulse: false,
                isSelected: true,
              ),
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: Text(
                  _selectedScreenIndex == 0
                      ? 'Tổng quan'
                      : _screenTitles[_selectedScreenIndex],
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 15.5 : 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => setState(() => _selectedScreenIndex = 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.acid,
                        border: Border.all(color: AppColors.ink, width: 1.2),
                      ),
                      child: const Icon(
                        Icons.person,
                        color: AppColors.ink,
                        size: 18,
                      ),
                    ),
                    if (showProfileText) ...[
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Admin',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                color: AppColors.ink,
                              ),
                            ),
                            Text(
                              '${(_store.activeAuthenticatedUser?.role == SubsystemRole.admin ? _store.activeAuthenticatedUser?.fullName : null) ?? _store.users.where((u) => u.role == SubsystemRole.admin).firstOrNull?.fullName ?? 'Quản trị viên'} (${_store.currentAdminRoleName})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showLogout && widget.onLogout != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    backgroundColor: AppColors.acid,
                    side: const BorderSide(color: AppColors.ink, width: 1.2),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 8 : 10,
                      vertical: 6,
                    ),
                  ),
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded, size: 15),
                  label: Text(
                    compact ? 'Thoát' : 'Đăng xuất',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildScreenSelectorBar() {
    return Semantics(
      label: 'Mục quản trị',
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.ink, width: 1.2),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _selectedScreenIndex,
            isExpanded: true,
            menuMaxHeight: 480,
            items: [
              for (var index = 0; index < _screenTitles.length; index++)
                DropdownMenuItem(
                  value: index,
                  child: Text(
                    _screenTitles[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
            ],
            onChanged: (index) {
              if (index != null) setState(() => _selectedScreenIndex = index);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildActiveAdminScreen(BuildContext context) {
    switch (_selectedScreenIndex) {
      case 0:
        return _buildSystemOverviewDashboard();
      case 1:
        return _buildUserAndMerchantManagementView();
      case 2:
        return _buildDriverKycApprovalView();
      case 3:
        return _buildFleetLiveGpsMonitorView();
      case 4:
        return _buildDynamicPricingConfigView();
      case 5:
        return _buildVoucherCampaignsView();
      case 6:
        return _buildComplaintResolutionView();
      case 7:
        return _buildFinancialWithdrawalApprovalView();
      case 8:
        return _buildManualOrderDispatchView();
      case 9:
        return _buildGeofencePolygonZonesView();
      case 10:
        return _buildBroadcastNotificationView();
      case 11:
        return _buildRbacPermissionMatrixView();
      case 12:
        return _buildCommercialOperationsView();
      case 13:
        if (!_store.hasAdminPermission('Hệ thống: Bảo mật')) {
          return const Text('Cần quyền Hệ thống: Bảo mật để quản lý API.');
        }
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthProviderSettings(canEdit: true),
            Divider(height: 24),
            DeliveryIntegrationStatus(),
          ],
        );
      case 14:
        return const CloudOrdersScreen(admin: true, embedded: true);
      default:
        return _buildSystemOverviewDashboard();
    }
  }

  void _rebuildAdminUi(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }
}

class _MiniSparklinePainter extends CustomPainter {
  final Color color;
  final List<double> yFactors;

  const _MiniSparklinePainter({
    required this.color,
    this.yFactors = const [0.85, 0.65, 0.35, 0.58, 0.12, 0.25],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final safeFactors = yFactors.length >= 2
        ? yFactors
        : const [0.85, 0.65, 0.35, 0.58, 0.12, 0.25];
    final pts = List<Offset>.generate(safeFactors.length, (i) {
      final x = size.width * (i / (safeFactors.length - 1));
      final y = size.height * safeFactors[i].clamp(0.06, 0.94);
      return Offset(x, y);
    });

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final prev = pts[i - 1];
      final curr = pts[i];
      final midX = (prev.dx + curr.dx) / 2;
      path.cubicTo(midX, prev.dy, midX, curr.dy, curr.dx, curr.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0.26),
            color.withValues(alpha: 0.02),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniSparklinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.yFactors != yFactors;
}

class _GoMauRevenueLineChartPainter extends CustomPainter {
  final List<double> blueNorm;
  final List<double> orangeNorm;

  const _GoMauRevenueLineChartPainter({
    this.blueNorm = const [0.85, 0.34, 0.52, 0.10, 0.35, 0.48, 0.06],
    this.orangeNorm = const [0.80, 0.52, 0.60, 0.28, 0.62, 0.66, 0.30],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF15131E)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * (i / 4.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    _drawSmoothSeries(canvas, size, blueNorm, const Color(0xFF5B33E6));
    _drawSmoothSeries(canvas, size, orangeNorm, const Color(0xFFFF5E83));
  }

  void _drawSmoothSeries(
    Canvas canvas,
    Size size,
    List<double> yFactors,
    Color color,
  ) {
    final path = Path();
    for (var i = 0; i < yFactors.length; i++) {
      final x = size.width * (i / (yFactors.length - 1));
      final y = size.height * yFactors[i];
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final prevX = size.width * ((i - 1) / (yFactors.length - 1));
        final prevY = size.height * yFactors[i - 1];
        final midX = (prevX + x) / 2;
        path.cubicTo(midX, prevY, midX, y, x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _GoMauRevenueLineChartPainter oldDelegate) =>
      oldDelegate.blueNorm != blueNorm || oldDelegate.orangeNorm != orangeNorm;
}

class _GoMauOrderDonutPainter extends CustomPainter {
  final double deliveredRatio;
  final double inTransitRatio;
  final double cancelledRatio;
  final double otherRatio;

  const _GoMauOrderDonutPainter({
    this.deliveredRatio = 0.25,
    this.inTransitRatio = 0.25,
    this.cancelledRatio = 0.25,
    this.otherRatio = 0.25,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = 24.0;
    final insetRect = rect.deflate(strokeWidth / 2);

    final segments = [
      (deliveredRatio, const Color(0xFF5B33E6)),
      (inTransitRatio, const Color(0xFFFF5E83)),
      (cancelledRatio, const Color(0xFFDC2626)),
      (otherRatio, const Color(0xFF94A3B8)),
    ];

    var startAngle = -math.pi / 2;
    for (final seg in segments) {
      if (seg.$1 <= 0.0) continue;
      final sweep = seg.$1 * 2 * math.pi;
      final drawSweep = sweep > 0.04 ? sweep - 0.03 : sweep;
      canvas.drawArc(
        insetRect,
        startAngle,
        drawSweep,
        false,
        Paint()
          ..color = seg.$2
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _GoMauOrderDonutPainter oldDelegate) =>
      oldDelegate.deliveredRatio != deliveredRatio ||
      oldDelegate.inTransitRatio != inTransitRatio ||
      oldDelegate.cancelledRatio != cancelledRatio ||
      oldDelegate.otherRatio != otherRatio;
}
