import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/studio_design_widgets.dart';

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

  Color get accentColor => switch (this) {
    GhstRoleMode.operator => const Color(0xFF1B5E7A),
    GhstRoleMode.driver => AppColors.teal,
    GhstRoleMode.merchant => AppColors.accent,
    GhstRoleMode.customer => AppColors.primary,
  };

  Color get softSurface => switch (this) {
    GhstRoleMode.operator => const Color(0xFFE3F2F8),
    GhstRoleMode.driver => AppColors.tealSoft,
    GhstRoleMode.merchant => AppColors.accentSoft,
    GhstRoleMode.customer => AppColors.primarySoft,
  };

  Color get highlightColor => switch (this) {
    GhstRoleMode.operator => const Color(0xFF7DD3FC),
    GhstRoleMode.driver => const Color(0xFF7AD9C1),
    GhstRoleMode.merchant => const Color(0xFFFBBF77),
    GhstRoleMode.customer => const Color(0xFF93C5FD),
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
  Color get _softSurface => roleMode.softSurface;
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
      'GIAO NHẬN & MUA SẮM TRỰC TUYẾN',
  };

  IconData get _brandIcon => switch (roleMode) {
    GhstRoleMode.driver => Icons.delivery_dining_rounded,
    GhstRoleMode.merchant => Icons.storefront_rounded,
    GhstRoleMode.customer || GhstRoleMode.operator =>
      Icons.local_shipping_outlined,
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
          (Icons.local_shipping_outlined, 'Gửi hàng', GhstUserSection.shipping),
          (
            Icons.warehouse_outlined,
            'Thu gom',
            GhstUserSection.merchantPickups,
          ),
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
            Icons.notifications_none_rounded,
            'Thông báo',
            GhstUserSection.notifications,
          ),
          (
            Icons.auto_awesome_outlined,
            'Trợ lý AI',
            GhstUserSection.aiAssistant,
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
      GhstUserSection.shipping ||
      GhstUserSection.merchantCsvImport ||
      GhstUserSection.orders => 2,
      GhstUserSection.merchantPickups => 3,
      GhstUserSection.aiAssistant => -1,
      _ => 4,
    },
    GhstRoleMode.merchant => switch (section) {
      GhstUserSection.workspace => 0,
      GhstUserSection.merchantOrders => 1,
      GhstUserSection.notifications => 2,
      GhstUserSection.aiAssistant => 3,
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
    GhstRoleMode.merchant => null,
    GhstRoleMode.customer || GhstRoleMode.operator =>
      switch (section) {
        GhstUserSection.notifications ||
        GhstUserSection.tracking ||
        GhstUserSection.aiAssistant ||
        GhstUserSection.workspace ||
        GhstUserSection.merchantOrders => GhstUserSection.home,
        _ => null,
      },
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 860;
      return Scaffold(
        backgroundColor: AppColors.paper,
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
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    _sidebar((constraints.maxWidth * .19).clamp(220, 290)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        wide ? _desktopHeader() : _mobileHeader(),
                        if (!wide && _canSwitchRole) _mobileRoleSwitcher(),
                        Expanded(child: child),
                        if (!wide) _bottomBar(),
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

  Widget _roleChip(GhstRoleMode mode, {required bool onDark}) {
    final active = roleMode == mode;
    final chipHighlight = mode.highlightColor;
    final chipAccent = mode.accentColor;
    final bg = onDark
        ? (active ? chipAccent.withValues(alpha: 0.34) : AppColors.techPanel)
        : (active ? mode.softSurface : AppColors.surface);
    final borderColor = onDark
        ? (active ? chipHighlight.withValues(alpha: 0.75) : AppColors.techLine)
        : (active ? chipAccent.withValues(alpha: 0.45) : AppColors.line);
    final iconColor = onDark
        ? (active ? chipHighlight : AppColors.techMuted)
        : (active ? chipAccent : AppColors.textSecondary);
    final textColor = onDark
        ? (active ? Colors.white : AppColors.techMuted)
        : (active ? AppColors.ink : AppColors.textSecondary);

    return Semantics(
      button: true,
      selected: active,
      label: 'Vai trò ${mode.label}',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('ghst-role-${mode.name}'),
        borderRadius: BorderRadius.circular(999),
        onTap: () => onRoleModeChanged?.call(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: active ? 1.2 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(mode.icon, size: 14, color: iconColor),
              const SizedBox(width: 5),
              Text(
                mode.label,
                maxLines: 1,
                style: TextStyle(
                  color: textColor,
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileRoleSwitcher() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: const BoxDecoration(
      color: AppColors.surfaceSubtle,
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Vai trò:',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final mode in availableModes) _roleChip(mode, onDark: false),
      ],
    ),
  );

  Widget _desktopRoleSwitcher() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            'Chế độ vai trò',
            style: TextStyle(
              color: AppColors.techMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final mode in availableModes) _roleChip(mode, onDark: true),
          ],
        ),
      ],
    ),
  );

  Widget _sidebar(double width) {
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
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 6),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.techMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
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
      decoration: const BoxDecoration(
        color: AppColors.techBg,
        border: Border(right: BorderSide(color: AppColors.line)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Icon(_brandIcon, color: Colors.white, size: 22),
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
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _brandSubtitle,
                          maxLines: 2,
                          style: TextStyle(
                            color: _highlight,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
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
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: navGroups,
              ),
            ),
            const Divider(color: AppColors.techLine, height: 1),
            const SizedBox(height: 4),
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
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    child: Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: action,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(color: _highlight.withValues(alpha: 0.32))
                : null,
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
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _roleHeaderBadge({double size = 38}) {
    if (roleMode == GhstRoleMode.customer) {
      return Animated3dIconBadge(
        style: Icon3dStyle.scooterExpress,
        size: size,
        showRadarPulse: false,
        isSelected: true,
        animateIdle: false,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _softSurface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _accent.withValues(alpha: 0.28)),
      ),
      child: Icon(_brandIcon, color: _accent, size: size * 0.54),
    );
  }

  Widget _desktopHeader() => LayoutBuilder(
    builder: (context, constraints) => Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          _roleHeaderBadge(),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                letterSpacing: -0.25,
              ),
            ),
          ),
          if (roleMode == GhstRoleMode.customer &&
              constraints.maxWidth >= 800 &&
              section != GhstUserSection.food)
            TextButton.icon(
              onPressed: () => onNavigate(GhstUserSection.food),
              icon: const Icon(
                Icons.restaurant_menu_rounded,
                color: AppColors.teal,
                size: 18,
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
              icon: const Icon(Icons.add_box_outlined, color: AppColors.ink),
            ),
          IconButton(
            key: const ValueKey('ghst-header-ai'),
            tooltip: 'Trợ lý AI',
            onPressed: () => onNavigate(GhstUserSection.aiAssistant),
            icon: Icon(
              Icons.auto_awesome_outlined,
              color: section == GhstUserSection.aiAssistant
                  ? _accent
                  : AppColors.ink,
            ),
          ),
          if (roleMode == GhstRoleMode.customer)
            IconButton(
              tooltip: 'Giỏ hàng',
              onPressed: onCart,
              icon: const Icon(
                Icons.shopping_cart_outlined,
                color: AppColors.ink,
              ),
            ),
          IconButton(
            tooltip: 'Trung tâm thông báo',
            onPressed: () => onNavigate(GhstUserSection.notifications),
            icon: Badge.count(
              count: unreadNotifications,
              isLabelVisible: unreadNotifications > 0,
              child: const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Hồ sơ cá nhân',
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onNavigate(GhstUserSection.profile),
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  4,
                  4,
                  constraints.maxWidth >= 920 ? 12 : 4,
                  4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _softSurface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.person, size: 17, color: _accent),
                    ),
                    if (constraints.maxWidth >= 920) ...[
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
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

  Widget _mobileHeader() {
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.line)),
        boxShadow: [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (backTarget != null)
            IconButton(
              tooltip: 'Quay lại',
              onPressed: () => onNavigate(backTarget),
              icon: Icon(Icons.arrow_back_rounded, color: _accent, size: 21),
            )
          else
            _roleHeaderBadge(size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headerSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('ghst-mobile-header-ai'),
            tooltip: 'Trợ lý AI',
            visualDensity: VisualDensity.compact,
            onPressed: () => onNavigate(GhstUserSection.aiAssistant),
            icon: Icon(
              Icons.auto_awesome_outlined,
              color: section == GhstUserSection.aiAssistant
                  ? _accent
                  : AppColors.ink,
              size: 20,
            ),
          ),
          if (roleMode == GhstRoleMode.customer)
            IconButton(
              tooltip: 'Giỏ hàng',
              visualDensity: VisualDensity.compact,
              onPressed: onCart,
              icon: const Icon(
                Icons.shopping_cart_outlined,
                color: AppColors.ink,
                size: 20,
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
                    ? _accent
                    : AppColors.ink,
                size: 20,
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
                color: AppColors.ink,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final items = _bottomItems;
    final activeIdx = _bottomIndex;
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 12,
            offset: Offset(0, -2),
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
                child: InkWell(
                  key: ValueKey('ghst-nav-${items[i].$3.name}'),
                  onTap: () => onNavigate(items[i].$3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: activeIdx == i
                              ? _softSurface
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Badge.count(
                          count: unreadNotifications,
                          isLabelVisible:
                              items[i].$3 == GhstUserSection.notifications &&
                              unreadNotifications > 0,
                          child: Icon(
                            items[i].$1,
                            size: 20,
                            color: activeIdx == i
                                ? _accent
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        items[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: activeIdx == i
                              ? _accent
                              : AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: activeIdx == i
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
