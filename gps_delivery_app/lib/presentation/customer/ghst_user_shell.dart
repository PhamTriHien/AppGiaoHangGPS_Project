import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/motion_3d_effects.dart';
import '../widgets/studio_design_widgets.dart';
import '../widgets/theme_mode_toggle.dart';

enum GhstRoleMode {
  customer,
  driver,
  merchant,
  operator;

  String get label => switch (this) {
    GhstRoleMode.operator => 'Quản trị',
    GhstRoleMode.driver => 'Đối tác Tài xế',
    GhstRoleMode.merchant => 'Cửa hàng',
    GhstRoleMode.customer => 'Khách hàng',
  };

  IconData get icon => switch (this) {
    GhstRoleMode.operator => Icons.admin_panel_settings_outlined,
    GhstRoleMode.driver => Icons.delivery_dining_rounded,
    GhstRoleMode.merchant => Icons.storefront_outlined,
    GhstRoleMode.customer => Icons.person_outline_rounded,
  };

  Icon3dStyle get icon3d => switch (this) {
    GhstRoleMode.operator => Icon3dStyle.adminShieldOps,
    GhstRoleMode.driver => Icon3dStyle.driverPartner,
    GhstRoleMode.merchant => Icon3dStyle.merchantStore,
    GhstRoleMode.customer => Icon3dStyle.scooterExpress,
  };

  Color get accentColor => switch (this) {
    GhstRoleMode.operator => const Color(0xFF087F5B),
    GhstRoleMode.driver => const Color(0xFF059669),
    GhstRoleMode.merchant => const Color(0xFFD97706),
    GhstRoleMode.customer => AppColors.violet,
  };

  Color get highlightColor => switch (this) {
    GhstRoleMode.operator => const Color(0xFF63E6BE),
    GhstRoleMode.driver => const Color(0xFF6EE7B7),
    GhstRoleMode.merchant => const Color(0xFFFCD34D),
    GhstRoleMode.customer => AppColors.acid,
  };
}

enum GhstUserSection {
  home,
  shipping,
  food,
  orders,
  profile,
  notifications,
  tracking,
  aiAssistant,
  workspace,
  merchantOrders,
  merchantOperations,
  driverQueue,
  driverTrips,
  driverPickups,
  driverStats,
  merchantCsvImport,
  merchantPickups,
}

/// Role-synchronized Cloud shell for Customer, Driver, and Merchant workspaces.
class GhstUserShell extends StatelessWidget {
  const GhstUserShell({
    super.key,
    required this.section,
    required this.child,
    required this.onNavigate,
    required this.onCreateOrder,
    required this.onAddresses,
    required this.onCart,
    required this.onLogout,
    required this.name,
    this.roleMode = GhstRoleMode.customer,
    this.availableModes = const [GhstRoleMode.customer],
    this.onRoleModeChanged,
    this.merchantOwner = false,
    this.onDriverOrders,
    this.floatingOverlay,
    this.address = '',
    this.merchant = false,
    this.driver = false,
    this.unreadNotifications = 0,
  });

  final GhstUserSection section;
  final Widget child;
  final Widget? floatingOverlay;
  final ValueChanged<GhstUserSection> onNavigate;
  final VoidCallback onCreateOrder, onAddresses, onCart, onLogout;
  final VoidCallback? onDriverOrders;
  final String name, address;
  final bool merchant, driver, merchantOwner;
  final int unreadNotifications;
  final GhstRoleMode roleMode;
  final List<GhstRoleMode> availableModes;
  final ValueChanged<GhstRoleMode>? onRoleModeChanged;

  bool get _canSwitchRole =>
      availableModes.length > 1 && onRoleModeChanged != null;

  Color get _accent => roleMode.accentColor;
  Color get _highlight => roleMode.highlightColor;

  String get _brandTitle => switch (roleMode) {
    GhstRoleMode.driver => 'GHST DRIVER',
    GhstRoleMode.merchant => 'GHST MERCHANT',
    GhstRoleMode.customer || GhstRoleMode.operator => 'GHST EXPRESS',
  };

  String get _brandSubtitle => switch (roleMode) {
    GhstRoleMode.driver => 'ĐỐI TÁC TÀI XẾ',
    GhstRoleMode.merchant =>
      merchantOwner ? 'ĐỐI TÁC CỬA HÀNG & B2B' : 'NHÂN SỰ GIAN HÀNG',
    GhstRoleMode.customer || GhstRoleMode.operator =>
      'SUPER-APP GIAO NHẬN & ẨM THỰC',
  };

  String get title => switch (section) {
    GhstUserSection.home => 'Trang chủ',
    GhstUserSection.shipping =>
      roleMode == GhstRoleMode.merchant
          ? 'Gửi vận đơn shop'
          : 'Tạo đơn hàng mới',
    GhstUserSection.food => 'Ăn uống & Mua sắm',
    GhstUserSection.orders =>
      roleMode == GhstRoleMode.merchant ? 'Vận đơn đã gửi' : 'Đơn hàng',
    GhstUserSection.profile => 'Hồ sơ cá nhân',
    GhstUserSection.notifications => 'Trung tâm thông báo',
    GhstUserSection.tracking =>
      roleMode == GhstRoleMode.driver
          ? 'Bản đồ hành trình'
          : 'Theo dõi hành trình',
    GhstUserSection.aiAssistant => 'Trợ lý AI',
    GhstUserSection.workspace => 'Cửa hàng của tôi',
    GhstUserSection.merchantOrders => 'Đơn của cửa hàng',
    GhstUserSection.merchantOperations => 'Kinh doanh & Hậu mãi',
    GhstUserSection.driverQueue => 'Sàn chuyến chờ nhận',
    GhstUserSection.driverTrips => 'Chuyến giao của tôi',
    GhstUserSection.driverPickups => 'Lịch xe thu gom',
    GhstUserSection.driverStats => 'Hiệu suất giao hàng',
    GhstUserSection.merchantCsvImport => 'Nhập đơn hàng loạt CSV',
    GhstUserSection.merchantPickups => 'Lịch xe thu gom kho',
  };

  List<(IconData, String, GhstUserSection)> get _bottomItems =>
      switch (roleMode) {
        GhstRoleMode.driver => const [
          (Icons.radar_rounded, 'Chờ nhận', GhstUserSection.driverQueue),
          (
            Icons.delivery_dining_rounded,
            'Chuyến giao',
            GhstUserSection.driverTrips,
          ),
          (Icons.warehouse_outlined, 'Thu gom', GhstUserSection.driverPickups),
          (Icons.insights_rounded, 'Hiệu suất', GhstUserSection.driverStats),
          (Icons.person_outline_rounded, 'Hồ sơ', GhstUserSection.profile),
        ],
        GhstRoleMode.merchant when merchantOwner => const [
          (Icons.storefront_rounded, 'Cửa hàng', GhstUserSection.workspace),
          (
            Icons.inventory_2_outlined,
            'Đơn shop',
            GhstUserSection.merchantOrders,
          ),
          (
            Icons.analytics_outlined,
            'Kinh doanh',
            GhstUserSection.merchantOperations,
          ),
          (Icons.local_shipping_outlined, 'Gửi hàng', GhstUserSection.shipping),
          (Icons.person_outline_rounded, 'Hồ sơ', GhstUserSection.profile),
        ],
        GhstRoleMode.merchant => const [
          (Icons.storefront_rounded, 'Cửa hàng', GhstUserSection.workspace),
          (
            Icons.inventory_2_outlined,
            'Đơn shop',
            GhstUserSection.merchantOrders,
          ),
          (
            Icons.support_agent_rounded,
            'Hậu mãi',
            GhstUserSection.merchantOperations,
          ),
          (
            Icons.notifications_none_rounded,
            'Thông báo',
            GhstUserSection.notifications,
          ),
          (Icons.person_outline_rounded, 'Hồ sơ', GhstUserSection.profile),
        ],
        GhstRoleMode.customer || GhstRoleMode.operator => const [
          (Icons.home_rounded, 'Trang chủ', GhstUserSection.home),
          (Icons.local_shipping_outlined, 'Giao hàng', GhstUserSection.shipping),
          (Icons.restaurant_menu_rounded, 'Ăn uống', GhstUserSection.food),
          (Icons.receipt_long_outlined, 'Đơn hàng', GhstUserSection.orders),
          (Icons.person_outline_rounded, 'Hồ sơ', GhstUserSection.profile),
        ],
      };

  int get _bottomIndex => switch (roleMode) {
    GhstRoleMode.driver => switch (section) {
      GhstUserSection.driverQueue || GhstUserSection.tracking => 0,
      GhstUserSection.driverTrips => 1,
      GhstUserSection.driverPickups => 2,
      GhstUserSection.driverStats => 3,
      GhstUserSection.aiAssistant => -1,
      _ => 4,
    },
    GhstRoleMode.merchant when merchantOwner => switch (section) {
      GhstUserSection.workspace => 0,
      GhstUserSection.merchantOrders => 1,
      GhstUserSection.merchantOperations => 2,
      GhstUserSection.shipping ||
      GhstUserSection.merchantCsvImport ||
      GhstUserSection.orders ||
      GhstUserSection.merchantPickups => 3,
      GhstUserSection.aiAssistant || GhstUserSection.notifications => -1,
      _ => 4,
    },
    GhstRoleMode.merchant => switch (section) {
      GhstUserSection.workspace => 0,
      GhstUserSection.merchantOrders => 1,
      GhstUserSection.merchantOperations => 2,
      GhstUserSection.notifications => 3,
      GhstUserSection.aiAssistant => -1,
      _ => 4,
    },
    GhstRoleMode.customer || GhstRoleMode.operator => switch (section) {
      GhstUserSection.home => 0,
      GhstUserSection.shipping => 1,
      GhstUserSection.food => 2,
      GhstUserSection.orders || GhstUserSection.tracking => 3,
      GhstUserSection.aiAssistant => -1,
      _ => 4,
    },
  };

  GhstUserSection? get _mobileBackTarget => switch (roleMode) {
    GhstRoleMode.driver =>
      switch (section) {
        GhstUserSection.notifications ||
        GhstUserSection.tracking ||
        GhstUserSection.aiAssistant => GhstUserSection.driverQueue,
        _ => null,
      },
    GhstRoleMode.merchant when merchantOwner =>
      switch (section) {
        GhstUserSection.notifications || GhstUserSection.aiAssistant =>
          GhstUserSection.workspace,
        _ => null,
      },
    GhstRoleMode.merchant =>
      switch (section) {
        GhstUserSection.aiAssistant => GhstUserSection.workspace,
        _ => null,
      },
    GhstRoleMode.customer || GhstRoleMode.operator =>
      switch (section) {
        GhstUserSection.notifications ||
        GhstUserSection.tracking ||
        GhstUserSection.aiAssistant ||
        GhstUserSection.workspace ||
        GhstUserSection.merchantOrders ||
        GhstUserSection.merchantOperations => GhstUserSection.home,
        _ => null,
      },
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final tokens = GhstThemeTokens.of(context);
      final wide = constraints.maxWidth >= 860;
      return Scaffold(
        backgroundColor: tokens.canvas,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: Studio3dMainWorkspaceMapPainter(
                      accentColor: _accent,
                      lightweightBackdrop: true,
                      isDark: tokens.isDark,
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    _sidebar(
                      tokens,
                      (constraints.maxWidth * .185).clamp(210, 290),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        wide ? _desktopHeader(tokens) : _mobileHeader(tokens),
                        if (!wide && _canSwitchRole)
                          _mobileRoleSwitcher(tokens),
                        Expanded(
                          child: Motion3dSectionTransition(
                            transitionKey: '${roleMode.name}:${section.name}',
                            child: child,
                          ),
                        ),
                        if (!wide) _bottomBar(tokens),
                      ],
                    ),
                  ),
                ],
              ),
              ?floatingOverlay,
            ],
          ),
        ),
      );
    },
  );

  Widget _roleChip(GhstRoleMode mode) {
    final active = roleMode == mode;
    final chipHighlight = mode.highlightColor;
    final chipAccent = mode.accentColor;
    return Semantics(
      button: true,
      selected: active,
      label: 'Vai trò ${mode.label}',
      excludeSemantics: true,
      child: Motion3dInteractiveSurface(
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        maxTilt: 0.032,
        pressScale: 0.972,
        hoverLift: -0.8,
        child: InkWell(
          key: ValueKey('ghst-role-${mode.name}'),
          borderRadius: BorderRadius.circular(999),
          onTap: () => onRoleModeChanged?.call(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? chipAccent.withValues(alpha: 0.30)
                : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? chipHighlight.withValues(alpha: 0.72)
                  : AppColors.techLine,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GhstAiIcon(
                style: mode.icon3d,
                size: 18,
                circular: true,
                selected: active,
                borderColor: active
                    ? chipHighlight.withValues(alpha: 0.85)
                    : AppColors.techLine,
              ),
              const SizedBox(width: 6),
              Text(
                mode.label,
                maxLines: 1,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.techMuted,
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _mobileRoleSwitcher(GhstThemeTokens tokens) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: tokens.shellBg,
      border: Border(bottom: BorderSide(color: tokens.shellBorder)),
    ),
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'VAI TRÒ:',
          style: TextStyle(
            color: AppColors.techMuted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        for (final mode in availableModes) _roleChip(mode),
      ],
    ),
  );

  Widget _desktopRoleSwitcher() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            'CHẾ ĐỘ VAI TRÒ',
            style: TextStyle(
              color: AppColors.techMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final mode in availableModes) _roleChip(mode)],
        ),
      ],
    ),
  );

  Widget _sidebar(GhstThemeTokens tokens, double width) {
    Widget item(IconData icon, String label, GhstUserSection target) =>
        _menuItem(
          icon,
          label,
          section == target,
          () => onNavigate(target),
          badgeCount: target == GhstUserSection.notifications
              ? unreadNotifications
              : 0,
        );
    Widget group(String label, List<Widget> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 11, 14, 5),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.techMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        ...items,
      ],
    );

    final navGroups = switch (roleMode) {
      GhstRoleMode.driver => <Widget>[
        group('ĐIỀU PHỐI CHUYẾN GIAO', [
          item(
            Icons.radar_rounded,
            'Sàn chuyến chờ nhận',
            GhstUserSection.driverQueue,
          ),
          item(
            Icons.delivery_dining_rounded,
            'Chuyến giao của tôi',
            GhstUserSection.driverTrips,
          ),
          item(
            Icons.warehouse_outlined,
            'Lịch xe thu gom',
            GhstUserSection.driverPickups,
          ),
          item(
            Icons.map_outlined,
            'Bản đồ hành trình',
            GhstUserSection.tracking,
          ),
          item(
            Icons.insights_rounded,
            'Hiệu suất giao hàng',
            GhstUserSection.driverStats,
          ),
        ]),
        group('HỖ TRỢ & TÀI KHOẢN', [
          item(
            Icons.auto_awesome_outlined,
            'Trợ lý AI',
            GhstUserSection.aiAssistant,
          ),
          item(
            Icons.notifications_none_rounded,
            'Trung tâm thông báo',
            GhstUserSection.notifications,
          ),
          item(
            Icons.person_outline_rounded,
            'Hồ sơ cá nhân',
            GhstUserSection.profile,
          ),
        ]),
      ],
      GhstRoleMode.merchant => <Widget>[
        group('QUẢN LÝ GIAN HÀNG', [
          item(
            Icons.storefront_outlined,
            'Cửa hàng của tôi',
            GhstUserSection.workspace,
          ),
          item(
            Icons.inventory_2_outlined,
            'Đơn của cửa hàng',
            GhstUserSection.merchantOrders,
          ),
          item(
            Icons.analytics_outlined,
            'Kinh doanh & Hậu mãi',
            GhstUserSection.merchantOperations,
          ),
        ]),
        if (merchantOwner)
          group('VẬN CHUYỂN B2B', [
            item(
              Icons.add_box_outlined,
              'Gửi vận đơn shop',
              GhstUserSection.shipping,
            ),
            item(
              Icons.upload_file_outlined,
              'Nhập đơn hàng loạt CSV',
              GhstUserSection.merchantCsvImport,
            ),
            item(
              Icons.local_shipping_outlined,
              'Vận đơn đã gửi',
              GhstUserSection.orders,
            ),
            item(
              Icons.warehouse_outlined,
              'Lịch xe thu gom kho',
              GhstUserSection.merchantPickups,
            ),
            _menuItem(
              Icons.bookmarks_outlined,
              'Sổ địa chỉ kho',
              false,
              onAddresses,
            ),
          ]),
        group('HỖ TRỢ & TÀI KHOẢN', [
          item(
            Icons.auto_awesome_outlined,
            'Trợ lý AI',
            GhstUserSection.aiAssistant,
          ),
          item(
            Icons.notifications_none_rounded,
            'Trung tâm thông báo',
            GhstUserSection.notifications,
          ),
          item(
            Icons.person_outline_rounded,
            'Hồ sơ cá nhân',
            GhstUserSection.profile,
          ),
        ]),
      ],
      GhstRoleMode.customer || GhstRoleMode.operator => <Widget>[
        group('DỊCH VỤ CHÍNH', [
          item(Icons.home_outlined, 'Trang chủ', GhstUserSection.home),
          item(
            Icons.add_box_outlined,
            'Tạo đơn hàng mới',
            GhstUserSection.shipping,
          ),
          item(
            Icons.restaurant_menu_rounded,
            'Ăn uống & Mua sắm',
            GhstUserSection.food,
          ),
          item(
            Icons.auto_awesome_outlined,
            'Trợ lý AI',
            GhstUserSection.aiAssistant,
          ),
        ]),
        group('ĐƠN HÀNG & BẢN ĐỒ', [
          item(Icons.receipt_long_outlined, 'Đơn hàng', GhstUserSection.orders),
          item(
            Icons.my_location_rounded,
            'Theo dõi hành trình',
            GhstUserSection.tracking,
          ),
          _menuItem(
            Icons.bookmarks_outlined,
            'Sổ địa chỉ nhận hàng',
            false,
            onAddresses,
          ),
        ]),
        group('CÁ NHÂN', [
          item(
            Icons.notifications_none_rounded,
            'Trung tâm thông báo',
            GhstUserSection.notifications,
          ),
          item(
            Icons.person_outline_rounded,
            'Hồ sơ cá nhân',
            GhstUserSection.profile,
          ),
        ]),
        if (merchant || driver)
          group('CÔNG VIỆC CỦA TÔI', [
            if (merchant) ...[
              item(
                Icons.storefront_outlined,
                'Cửa hàng của tôi',
                GhstUserSection.workspace,
              ),
              item(
                Icons.inventory_2_outlined,
                'Đơn của cửa hàng',
                GhstUserSection.merchantOrders,
              ),
              item(
                Icons.analytics_outlined,
                'Kinh doanh & Hậu mãi',
                GhstUserSection.merchantOperations,
              ),
            ],
            if (driver)
              _menuItem(
                Icons.delivery_dining,
                'Chuyến giao của tôi',
                section == GhstUserSection.driverTrips,
                onDriverOrders ?? () => onNavigate(GhstUserSection.driverTrips),
              ),
          ]),
      ],
    };

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: tokens.shellBg,
        border: Border(right: BorderSide(color: tokens.shellBorder)),
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.92),
          radius: 1.25,
          colors: [
            Color.alphaBlend(_accent.withValues(alpha: 0.22), tokens.shellBg),
            tokens.shellBg,
          ],
          stops: const [0.0, 0.72],
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
              child: Row(
                children: [
                  GhstAiIcon(
                    style: roleMode.icon3d,
                    size: 42,
                    borderRadius: 12,
                    selected: true,
                    borderColor: _highlight,
                    glowColor: _highlight,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _brandTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        Text(
                          _brandSubtitle,
                          maxLines: 2,
                          style: TextStyle(
                            color: _highlight,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.techLine, height: 1),
            if (_canSwitchRole) ...[
              _desktopRoleSwitcher(),
              const Divider(color: AppColors.techLine, height: 1),
            ],
            Expanded(child: ListView(children: navGroups)),
            const Divider(color: AppColors.techLine, height: 1),
            _menuItem(Icons.logout_rounded, 'Đăng xuất', false, onLogout),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(
    IconData icon,
    String label,
    bool selected,
    VoidCallback action, {
    int badgeCount = 0,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1.5),
    child: Semantics(
      button: true,
      selected: selected,
      child: Motion3dInteractiveSurface(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        maxTilt: 0.028,
        pressScale: 0.978,
        hoverLift: -0.8,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: action,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? _accent.withValues(alpha: .28)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? _highlight : AppColors.techMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.techMuted,
                    fontSize: 12.5,
                    letterSpacing: 0,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ),
        ),
      ),
    ),
  );

  Widget _roleHeaderBadge({double size = 38}) => Animated3dIconBadge(
    style: roleMode.icon3d,
    size: size,
    showRadarPulse: false,
    isSelected: true,
    animateIdle: false,
  );

  Widget _desktopHeader(GhstThemeTokens tokens) => LayoutBuilder(
    builder: (context, constraints) => Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        border: Border(bottom: BorderSide(color: tokens.border)),
        boxShadow: tokens.cardShadow,
      ),
      child: Row(
        children: [
          _roleHeaderBadge(),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: tokens.ink,
                letterSpacing: 0,
              ),
            ),
          ),
          if (roleMode == GhstRoleMode.customer &&
              constraints.maxWidth >= 800 &&
              section != GhstUserSection.food)
            TextButton.icon(
              onPressed: () => onNavigate(GhstUserSection.food),
              icon: const GhstAiIcon(
                style: Icon3dStyle.foodMarket,
                size: 22,
                borderRadius: 6,
              ),
              label: const Text('Ăn uống'),
            ),
          if ((roleMode == GhstRoleMode.customer ||
                  (roleMode == GhstRoleMode.merchant && merchantOwner)) &&
              section != GhstUserSection.home &&
              section != GhstUserSection.shipping)
            IconButton(
              tooltip: 'Tạo đơn hàng mới',
              onPressed: onCreateOrder,
              icon: Icon(Icons.add_box_outlined, color: tokens.ink),
            ),
          const ThemeModeIconButton(),
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('ghst-header-ai'),
            tooltip: 'Trợ lý AI',
            onPressed: () => onNavigate(GhstUserSection.aiAssistant),
            icon: GhstAiIcon(
              style: Icon3dStyle.aiAssistant,
              size: 26,
              circular: true,
              selected: section == GhstUserSection.aiAssistant,
            ),
          ),
          if (roleMode == GhstRoleMode.customer)
            IconButton(
              tooltip: 'Giỏ hàng',
              onPressed: onCart,
              icon: Icon(Icons.shopping_cart_outlined, color: tokens.ink),
            ),
          IconButton(
            tooltip: 'Trung tâm thông báo',
            onPressed: () => onNavigate(GhstUserSection.notifications),
            icon: Badge.count(
              count: unreadNotifications,
              isLabelVisible: unreadNotifications > 0,
              child: Icon(Icons.notifications_none_rounded, color: tokens.ink),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Hồ sơ cá nhân',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onNavigate(GhstUserSection.profile),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: tokens.sapphire.fill,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: tokens.sapphire.border),
                      ),
                      child: Icon(
                        Icons.person_rounded,
                        size: 19,
                        color: tokens.sapphire.icon,
                      ),
                    ),
                    if (constraints.maxWidth >= 920) ...[
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _mobileHeader(GhstThemeTokens tokens) {
    final backTarget = _mobileBackTarget;
    final headerSubtitle = switch (roleMode) {
      GhstRoleMode.driver => 'GHST DRIVER • ĐỐI TÁC TÀI XẾ',
      GhstRoleMode.merchant =>
        merchantOwner
            ? 'GHST MERCHANT • CỬA HÀNG B2B'
            : 'GHST MERCHANT • NHÂN SỰ SHOP',
      GhstRoleMode.customer || GhstRoleMode.operator =>
        section == GhstUserSection.home
            ? 'VỊ TRÍ • ${address.isEmpty ? 'Chưa chọn' : address}'
            : 'GHST EXPRESS',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.shellBg,
        border: Border(bottom: BorderSide(color: tokens.shellBorder)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x240F172A),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          if (backTarget != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Quay lại',
              onPressed: () => onNavigate(backTarget),
              icon: Icon(Icons.arrow_back_rounded, color: _highlight, size: 21),
            )
          else
            _roleHeaderBadge(size: 34),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headerSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _highlight,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const ThemeModeIconButton(onDarkHeader: true, compact: true),
          IconButton(
            key: const ValueKey('ghst-mobile-header-ai'),
            tooltip: 'Trợ lý AI',
            visualDensity: VisualDensity.compact,
            onPressed: () => onNavigate(GhstUserSection.aiAssistant),
            icon: GhstAiIcon(
              style: Icon3dStyle.aiAssistant,
              size: 23,
              circular: true,
              selected: section == GhstUserSection.aiAssistant,
            ),
          ),
          if (roleMode == GhstRoleMode.customer)
            IconButton(
              tooltip: 'Giỏ hàng',
              visualDensity: VisualDensity.compact,
              onPressed: onCart,
              icon: const Icon(
                Icons.shopping_cart_outlined,
                color: Colors.white,
                size: 19,
              ),
            )
          else if (roleMode == GhstRoleMode.driver)
            IconButton(
              tooltip: 'Bản đồ hành trình',
              visualDensity: VisualDensity.compact,
              onPressed: () => onNavigate(GhstUserSection.tracking),
              icon: Icon(
                Icons.map_outlined,
                color: section == GhstUserSection.tracking
                    ? _highlight
                    : Colors.white,
                size: 19,
              ),
            ),
          IconButton(
            tooltip: 'Trung tâm thông báo',
            visualDensity: VisualDensity.compact,
            onPressed: () => onNavigate(GhstUserSection.notifications),
            icon: Badge.count(
              count: unreadNotifications,
              isLabelVisible: unreadNotifications > 0,
              child: const Icon(
                Icons.notifications_none_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(GhstThemeTokens tokens) {
    final items = _bottomItems;
    final activeIdx = _bottomIndex;
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: tokens.shellBg,
        border: Border(top: BorderSide(color: tokens.shellBorder)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x220F172A),
            blurRadius: 14,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: activeIdx == i,
                child: Motion3dInteractiveSurface(
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  maxTilt: 0.035,
                  pressScale: 0.968,
                  hoverLift: -0.8,
                  child: InkWell(
                    key: ValueKey('ghst-nav-${items[i].$3.name}'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onNavigate(items[i].$3),
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: activeIdx == i
                          ? _accent.withValues(alpha: 0.24)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Badge.count(
                          count: unreadNotifications,
                          isLabelVisible:
                              items[i].$3 == GhstUserSection.notifications &&
                              unreadNotifications > 0,
                          child: Icon(
                            items[i].$1,
                            size: 20,
                            color: activeIdx == i
                                ? _highlight
                                : AppColors.techMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: activeIdx == i
                                ? _highlight
                                : AppColors.techMuted,
                            fontSize: 10.5,
                            letterSpacing: 0,
                            fontWeight: activeIdx == i
                                ? FontWeight.w900
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
