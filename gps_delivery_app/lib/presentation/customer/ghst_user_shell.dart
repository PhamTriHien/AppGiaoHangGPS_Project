import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/studio_design_widgets.dart';

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
}

/// The original customer workspace presentation, independent of account storage.
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
    this.onDriverOrders,
    this.floatingOverlay,
    this.address = '',
    this.merchant = false,
    this.driver = false,
  });

  final GhstUserSection section;
  final Widget child;
  final Widget? floatingOverlay;
  final ValueChanged<GhstUserSection> onNavigate;
  final VoidCallback onCreateOrder, onAddresses, onCart, onLogout;
  final VoidCallback? onDriverOrders;
  final String name, address;
  final bool merchant, driver;

  String get title => switch (section) {
    GhstUserSection.home => 'Trang chủ',
    GhstUserSection.shipping => 'Tạo đơn hàng mới',
    GhstUserSection.food => 'Ăn uống & Mua sắm',
    GhstUserSection.orders => 'Đơn hàng',
    GhstUserSection.profile => 'Hồ sơ cá nhân',
    GhstUserSection.notifications => 'Trung tâm thông báo',
    GhstUserSection.tracking => 'Theo dõi hành trình',
    GhstUserSection.aiAssistant => 'Trợ lý AI',
    GhstUserSection.workspace => 'Cửa hàng của tôi',
    GhstUserSection.merchantOrders => 'Đơn của cửa hàng',
  };

  int get _bottomIndex => switch (section) {
    GhstUserSection.home => 0,
    GhstUserSection.shipping => 1,
    GhstUserSection.food => 2,
    GhstUserSection.orders || GhstUserSection.tracking => 3,
    GhstUserSection.aiAssistant => -1,
    _ => 4,
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
              const IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: Studio3dMainWorkspaceMapPainter(
                      accentColor: AppColors.violet,
                      lightweightBackdrop: true,
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    _sidebar((constraints.maxWidth * .185).clamp(210, 290)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        wide ? _desktopHeader() : _mobileHeader(),
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

  Widget _sidebar(double width) {
    Widget item(IconData icon, String label, GhstUserSection target) =>
        _menuItem(icon, label, section == target, () => onNavigate(target));
    Widget group(String label, List<Widget> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 6),
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
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: AppColors.techBg,
        border: Border(right: BorderSide(color: AppColors.ink, width: 1.6)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 16, 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: ColoredBox(
                      color: AppColors.acid,
                      child: Icon(
                        Icons.local_shipping_outlined,
                        color: AppColors.techBg,
                        size: 22,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GHST EXPRESS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        Text(
                          'SUPER-APP GIAO NHẬN & ẨM THỰC',
                          maxLines: 2,
                          style: TextStyle(
                            color: AppColors.acid,
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
            Expanded(
              child: ListView(
                children: [
                  group('DỊCH VỤ CHÍNH', [
                    item(
                      Icons.home_outlined,
                      'Trang chủ',
                      GhstUserSection.home,
                    ),
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
                    item(
                      Icons.receipt_long_outlined,
                      'Đơn hàng',
                      GhstUserSection.orders,
                    ),
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
                          section == GhstUserSection.orders,
                          onDriverOrders ??
                              () => onNavigate(GhstUserSection.orders),
                        ),
                    ]),
                ],
              ),
            ),
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
    VoidCallback action,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1.5),
    child: Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: action,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.violet.withValues(alpha: .25)
                : Colors.transparent,
            border: selected
                ? const Border(
                    left: BorderSide(color: AppColors.acid, width: 4),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppColors.acid : AppColors.techMuted,
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
            ],
          ),
        ),
      ),
    ),
  );

  Widget _desktopHeader() => LayoutBuilder(
    builder: (context, constraints) => Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.ink, width: 1.5)),
      ),
      child: Row(
        children: [
          const Animated3dIconBadge(
            style: Icon3dStyle.scooterExpress,
            size: 38,
            showRadarPulse: false,
            isSelected: true,
            animateIdle: false,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
                letterSpacing: 0,
              ),
            ),
          ),
          if (constraints.maxWidth >= 800 && section != GhstUserSection.food)
            TextButton.icon(
              onPressed: () => onNavigate(GhstUserSection.food),
              icon: const Icon(
                Icons.restaurant_menu_rounded,
                color: Color(0xFF00853B),
              ),
              label: const Text('Ăn uống'),
            ),
          if (section != GhstUserSection.home &&
              section != GhstUserSection.shipping)
            IconButton(
              tooltip: 'Tạo đơn hàng mới',
              onPressed: onCreateOrder,
              icon: const Icon(Icons.add_box_outlined),
            ),
          IconButton(
            key: const ValueKey('ghst-header-ai'),
            tooltip: 'Trợ lý AI',
            onPressed: () => onNavigate(GhstUserSection.aiAssistant),
            icon: Icon(
              Icons.auto_awesome_outlined,
              color: section == GhstUserSection.aiAssistant
                  ? AppColors.violet
                  : AppColors.ink,
            ),
          ),
          IconButton(
            tooltip: 'Giỏ hàng',
            onPressed: onCart,
            icon: const Icon(Icons.shopping_cart_outlined),
          ),
          IconButton(
            tooltip: 'Trung tâm thông báo',
            onPressed: () => onNavigate(GhstUserSection.notifications),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Hồ sơ cá nhân',
            child: InkWell(
              onTap: () => onNavigate(GhstUserSection.profile),
              child: Row(
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
                      size: 19,
                      color: AppColors.ink,
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
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
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
    ),
  );

  Widget _mobileHeader() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.techBg,
      border: Border.all(color: AppColors.ink, width: 1.5),
      boxShadow: const [
        BoxShadow(color: AppColors.violet, offset: Offset(6, 6)),
      ],
    ),
    child: Row(
      children: [
        if (section == GhstUserSection.notifications ||
            section == GhstUserSection.tracking ||
            section == GhstUserSection.aiAssistant ||
            section == GhstUserSection.workspace ||
            section == GhstUserSection.merchantOrders)
          IconButton(
            tooltip: 'Quay lại',
            onPressed: () => onNavigate(GhstUserSection.home),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.acid,
              size: 21,
            ),
          )
        else
          const Animated3dIconBadge(
            style: Icon3dStyle.scooterExpress,
            size: 36,
            showRadarPulse: false,
            animateIdle: false,
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section == GhstUserSection.home
                    ? 'VỊ TRÍ • ${address.isEmpty ? 'Chưa chọn' : address}'
                    : 'GHST EXPRESS',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.acid,
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
        IconButton(
          key: const ValueKey('ghst-mobile-header-ai'),
          tooltip: 'Trợ lý AI',
          visualDensity: VisualDensity.compact,
          onPressed: () => onNavigate(GhstUserSection.aiAssistant),
          icon: Icon(
            Icons.auto_awesome_outlined,
            color: section == GhstUserSection.aiAssistant
                ? AppColors.acid
                : Colors.white,
            size: 20,
          ),
        ),
        IconButton(
          tooltip: 'Giỏ hàng',
          visualDensity: VisualDensity.compact,
          onPressed: onCart,
          icon: const Icon(
            Icons.shopping_cart_outlined,
            color: Colors.white,
            size: 20,
          ),
        ),
        IconButton(
          tooltip: 'Trung tâm thông báo',
          visualDensity: VisualDensity.compact,
          onPressed: () => onNavigate(GhstUserSection.notifications),
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ],
    ),
  );

  Widget _bottomBar() {
    const items = [
      (Icons.home_rounded, 'Trang chủ', GhstUserSection.home),
      (Icons.local_shipping_outlined, 'Giao hàng', GhstUserSection.shipping),
      (Icons.restaurant_menu_rounded, 'Ăn uống', GhstUserSection.food),
      (Icons.receipt_long_outlined, 'Đơn hàng', GhstUserSection.orders),
      (Icons.person_outline_rounded, 'Hồ sơ', GhstUserSection.profile),
    ];
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: AppColors.techBg,
        border: Border.all(color: AppColors.ink, width: 1.5),
        boxShadow: const [
          BoxShadow(color: AppColors.violet, offset: Offset(5, 5)),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: _bottomIndex == i,
                child: InkWell(
                  key: ValueKey('ghst-nav-${items[i].$3.name}'),
                  onTap: () => onNavigate(items[i].$3),
                  child: Container(
                    decoration: BoxDecoration(
                      border: _bottomIndex == i
                          ? const Border(
                              top: BorderSide(color: AppColors.acid, width: 3),
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          items[i].$1,
                          size: 20,
                          color: _bottomIndex == i
                              ? AppColors.acid
                              : AppColors.techMuted,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i].$2,
                          maxLines: 1,
                          style: TextStyle(
                            color: _bottomIndex == i
                                ? AppColors.acid
                                : AppColors.techMuted,
                            fontSize: 10.5,
                            letterSpacing: 0,
                            fontWeight: _bottomIndex == i
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
        ],
      ),
    );
  }
}
