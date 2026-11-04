import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/delivery_api_client.dart';
import '../../core/integrations/push_notification_service.dart';
import '../../core/theme/theme_controller.dart';
import '../customer/ghst_ai_chat_screen.dart';
import '../customer/ghst_home_screen.dart';
import '../customer/ghst_shipping_screen.dart';
import '../customer/ghst_user_shell.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/cloud_logistics_panels.dart';
import '../widgets/cloud_notification_center.dart';
import '../widgets/cloud_profile_form.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/ghst_button_icon.dart';
import '../widgets/merchant_cloud_panels.dart';
import '../widgets/studio_user_auth_frame.dart';
import 'admin_portal_screen.dart';
import 'cloud_address_book_screen.dart';
import 'cloud_app_settings_screen.dart';
import 'cloud_auth_screen.dart';
import 'cloud_order_details_screen.dart';
import 'cloud_order_import_screen.dart';
import 'cloud_orders_screen.dart';
import 'cloud_pickup_screen.dart';
import 'cloud_promo_events_screen.dart';
import 'market_order_services_screen.dart';
import 'marketplace_view.dart';

/// Canonical entry point. Legacy SQLite accounts never enter this workspace.
class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({
    super.key,
    required this.session,
    this.initialShipping = false,
  });
  final CloudAccountSession session;
  final bool initialShipping;
  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with WidgetsBindingObserver {
  late GhstUserSection _section = widget.initialShipping
      ? GhstUserSection.orders
      : GhstUserSection.home;
  GhstRoleMode? _roleMode;
  bool _userSelectedRole = false;
  Set<GhstRoleMode> _knownUnlockedModes = const {};
  int _merchantShipTab = 0;
  bool _purchaseOrders = false;
  String _address = '';
  late String _knownIdentity = _session.service.identityScope;
  Map<String, dynamic>? _shippingDetails;
  int _formRevision = 0, _homeRevision = 0;
  bool _recovery = false, _foreground = true;
  String? _aiScope;
  GhstAiChatController? _aiController;
  StreamSubscription<AuthState>? _auth;
  StreamSubscription<Map<String, dynamic>>? _pushAlertsSub;
  Object? _pushWatcher;
  Timer? _poll;
  CloudAccountSession get _session => widget.session;

  GhstRoleMode get _effectiveRoleMode => _roleMode ?? GhstRoleMode.customer;

  List<GhstRoleMode> _unlockedModes() {
    if (!_session.verified) return const [GhstRoleMode.customer];
    return [
      if (_session.isOperator) GhstRoleMode.operator,
      if (_session.hasMerchantAccess) GhstRoleMode.merchant,
      if (_session.hasRole('driver')) GhstRoleMode.driver,
      GhstRoleMode.customer,
    ];
  }

  GhstRoleMode _defaultRoleMode({bool allowOperator = true}) {
    if (widget.initialShipping) return GhstRoleMode.customer;
    final saved = _session.cloudPreferredRole;
    if (saved != null) {
      final preferred = switch (saved) {
        'admin' || 'operator' =>
          allowOperator && _session.isOperator ? GhstRoleMode.operator : null,
        'merchant' => _session.hasMerchantAccess ? GhstRoleMode.merchant : null,
        'driver' => _session.hasRole('driver') ? GhstRoleMode.driver : null,
        'customer' => GhstRoleMode.customer,
        _ => null,
      };
      if (preferred != null) return preferred;
    }
    if (allowOperator && _session.isOperator) return GhstRoleMode.operator;
    final primary = _session.account?['role'];
    if (primary == 'driver' && _session.hasRole('driver')) {
      return GhstRoleMode.driver;
    }
    if (primary == 'merchant' && _session.hasMerchantAccess) {
      return GhstRoleMode.merchant;
    }
    if (_session.hasRole('driver') && !_session.hasMerchantAccess) {
      return GhstRoleMode.driver;
    }
    if (_session.hasMerchantAccess) {
      return GhstRoleMode.merchant;
    }
    return GhstRoleMode.customer;
  }

  GhstUserSection _defaultSectionFor(GhstRoleMode mode) => switch (mode) {
    GhstRoleMode.driver => GhstUserSection.driverQueue,
    GhstRoleMode.merchant => GhstUserSection.workspace,
    GhstRoleMode.customer || GhstRoleMode.operator =>
      widget.initialShipping ? GhstUserSection.orders : GhstUserSection.home,
  };

  void _syncRoleState() {
    if (!_session.verified) return;
    final unlocked = _unlockedModes().toSet();
    if (_roleMode == null) {
      final initial = _defaultRoleMode();
      _roleMode = initial;
      _section = _defaultSectionFor(initial);
    } else if (!unlocked.contains(_roleMode)) {
      final previous = _roleMode;
      final fallback = _defaultRoleMode();
      _roleMode = fallback;
      _userSelectedRole = false;
      if (fallback == GhstRoleMode.customer &&
          (previous == GhstRoleMode.merchant ||
              previous == GhstRoleMode.driver)) {
        _section = GhstUserSection.profile;
      } else {
        _section = _defaultSectionFor(fallback);
      }
    } else if (!_userSelectedRole) {
      final newlyUnlocked = unlocked.difference(_knownUnlockedModes);
      if (newlyUnlocked.contains(GhstRoleMode.operator) ||
          newlyUnlocked.contains(GhstRoleMode.driver) ||
          newlyUnlocked.contains(GhstRoleMode.merchant)) {
        final upgraded = _defaultRoleMode();
        if (upgraded != _roleMode) {
          _roleMode = upgraded;
          _section = _defaultSectionFor(upgraded);
        }
      }
    }
    _knownUnlockedModes = unlocked;

    if (!_session.hasMerchantAccess &&
        [
          GhstUserSection.workspace,
          GhstUserSection.merchantOrders,
          GhstUserSection.merchantOperations,
          GhstUserSection.merchantCsvImport,
          GhstUserSection.merchantPickups,
        ].contains(_section)) {
      _section = GhstUserSection.profile;
    }
    if (!_session.hasRole('driver') &&
        [
          GhstUserSection.driverQueue,
          GhstUserSection.driverTrips,
          GhstUserSection.driverPickups,
          GhstUserSection.driverStats,
        ].contains(_section)) {
      _section = GhstUserSection.profile;
    }
    if (!_session.hasRole('merchant') &&
        [
          GhstUserSection.merchantCsvImport,
          GhstUserSection.merchantPickups,
        ].contains(_section)) {
      _section = _session.hasMerchantAccess
          ? GhstUserSection.workspace
          : GhstUserSection.profile;
    }
    if (!_session.canCreateShippingOrder &&
        _section == GhstUserSection.shipping) {
      _section = GhstUserSection.profile;
    }
  }

  void _selectRoleMode(GhstRoleMode mode) {
    final unlocked = _unlockedModes();
    if (!unlocked.contains(mode)) return;
    setState(() {
      _userSelectedRole = true;
      _roleMode = mode;
      _merchantShipTab = 0;
      _purchaseOrders = false;
      _section = _defaultSectionFor(mode);
    });
    final cloudRole = mode == GhstRoleMode.operator ? 'admin' : mode.name;
    unawaited(
      _session
          .saveUiPreferences(preferredRole: cloudRole)
          .catchError((Object _) {}),
    );
  }

  void _clearAiController({bool immediate = false}) {
    final old = _aiController;
    _aiController = null;
    _aiScope = null;
    if (old == null) return;
    if (immediate) {
      old.dispose();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  GhstAiChatController _resolveAiController(String scope) {
    if (_aiController == null || _aiScope != scope || !_aiController!.valid) {
      final old = _aiController;
      _aiScope = scope;
      _aiController = GhstAiChatController(session: _session);
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    }
    return _aiController!;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.start();
    _syncRoleState();
    _session.addListener(_changed);
    _pushWatcher = PushNotificationService.instance.attachWatcher(_session);
    _pushAlertsSub = PushNotificationService.instance.incomingAlerts.listen((
      item,
    ) {
      if (!mounted || !_foreground || _section == GhstUserSection.notifications) {
        return;
      }
      final title = '${item['title'] ?? 'Thông báo mới'}'.trim();
      final body = '${item['body'] ?? ''}'.trim();
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          content: Text(body.isNotEmpty ? '$title · $body' : title),
          action: SnackBarAction(
            label: 'Xem',
            onPressed: () {
              if (mounted) _go(GhstUserSection.notifications);
            },
          ),
        ),
      );
    });
    _auth = _session.service.authChanges.listen((state) {
      if (mounted && state.event == AuthChangeEvent.passwordRecovery) {
        setState(() => _recovery = true);
      }
      if (mounted && state.event == AuthChangeEvent.signedOut) {
        setState(() {
          _clearAiController();
          _recovery = false;
          _roleMode = null;
          _userSelectedRole = false;
          _knownUnlockedModes = const {};
          _merchantShipTab = 0;
          _section = GhstUserSection.home;
          _shippingDetails = null;
          _address = '';
          _purchaseOrders = false;
        });
      }
    }, onError: (Object _) {});
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_foreground && _session.service.signedIn) _refresh();
    });
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (_knownIdentity != _session.service.identityScope) {
        _clearAiController();
        _knownIdentity = _session.service.identityScope;
        _address = '';
        _roleMode = null;
        _userSelectedRole = false;
        _knownUnlockedModes = const {};
        _merchantShipTab = 0;
        _section = widget.initialShipping
            ? GhstUserSection.orders
            : GhstUserSection.home;
        _shippingDetails = null;
        _purchaseOrders = false;
      }
      _syncRoleState();
    });
  }

  void _navigate(MarketView view) {
    if (!_session.canUseBusiness) return;
    if ([MarketView.workspace, MarketView.merchantOrders].contains(view) &&
        !_session.hasMerchantAccess) {
      return;
    }
    final target = switch (view) {
      MarketView.catalog => GhstUserSection.food,
      MarketView.orders => GhstUserSection.orders,
      MarketView.notifications => GhstUserSection.notifications,
      MarketView.workspace => GhstUserSection.workspace,
      MarketView.merchantOrders => GhstUserSection.merchantOrders,
      _ => GhstUserSection.profile,
    };
    setState(() {
      if ([MarketView.workspace, MarketView.merchantOrders].contains(view)) {
        _userSelectedRole = true;
        _roleMode = GhstRoleMode.merchant;
      } else if ([MarketView.catalog, MarketView.orders].contains(view)) {
        _userSelectedRole = true;
        _roleMode = GhstRoleMode.customer;
      }
      if (view == MarketView.orders) _purchaseOrders = true;
      _section = target;
    });
  }

  void _go(GhstUserSection section) {
    if (!_session.canUseBusiness) return;
    if ([
          GhstUserSection.workspace,
          GhstUserSection.merchantOrders,
          GhstUserSection.merchantOperations,
        ].contains(section) &&
        !_session.hasMerchantAccess) {
      return;
    }
    if ([
          GhstUserSection.merchantCsvImport,
          GhstUserSection.merchantPickups,
        ].contains(section) &&
        !_session.hasRole('merchant')) {
      return;
    }
    if ([
          GhstUserSection.driverQueue,
          GhstUserSection.driverTrips,
          GhstUserSection.driverPickups,
          GhstUserSection.driverStats,
        ].contains(section) &&
        !_session.hasRole('driver')) {
      return;
    }
    if (section == GhstUserSection.shipping) {
      _createOrder({});
      return;
    }
    setState(() {
      if ([
        GhstUserSection.workspace,
        GhstUserSection.merchantOrders,
        GhstUserSection.merchantOperations,
        GhstUserSection.merchantCsvImport,
        GhstUserSection.merchantPickups,
      ].contains(section)) {
        _userSelectedRole = true;
        _roleMode = GhstRoleMode.merchant;
      } else if ([
        GhstUserSection.driverQueue,
        GhstUserSection.driverTrips,
        GhstUserSection.driverPickups,
        GhstUserSection.driverStats,
      ].contains(section)) {
        _userSelectedRole = true;
        _roleMode = GhstRoleMode.driver;
      }
      _section = section;
    });
  }

  void _openShipping() => setState(() {
    _purchaseOrders = false;
    _section = GhstUserSection.orders;
  });

  void _openDriverTrips() {
    if (!_session.hasRole('driver')) {
      _openShipping();
      return;
    }
    setState(() {
      _userSelectedRole = true;
      _roleMode = GhstRoleMode.driver;
      _section = GhstUserSection.driverTrips;
    });
  }

  void _createOrder(Map<String, dynamic> details) {
    if (!_session.canCreateShippingOrder) return;
    setState(() {
      _formRevision++;
      _merchantShipTab = 0;
      _shippingDetails = details;
      _section = GhstUserSection.shipping;
    });
  }

  Future<void> _openShippingDetails(Map<String, dynamic> order) async {
    if (!_session.canUseBusiness || !mounted) return;
    final identity = _session.service.identityScope;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CloudSessionBoundary(
          session: _session,
          builder: (_, lease) => CloudOrderDetailsScreen(
            lease: lease,
            order: order,
          ),
        ),
      ),
    );
    if (mounted && identity == _session.service.identityScope) {
      _refresh();
    }
  }

  void _handleOrderCreated(
    Map<String, dynamic> createdOrder, {
    bool merchantMobile = false,
  }) {
    if (merchantMobile) {
      setState(() => _merchantShipTab = 2);
    } else {
      _openShipping();
    }
    final code = '${createdOrder['tracking_code'] ?? ''}'.trim();
    if (code.isEmpty || createdOrder['id'] == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Text('Đã tạo vận đơn $code · Đang điều phối tài xế'),
        action: SnackBarAction(
          label: 'Xem hành trình',
          onPressed: () {
            if (mounted) unawaited(_openShippingDetails(createdOrder));
          },
        ),
      ),
    );
  }

  Future<void> _addresses() async {
    if (!_session.canUseBusiness) return;
    final identity = _session.service.identityScope;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudSessionBoundary(
          session: _session,
          builder: (_, lease) =>
              CloudAddressBookScreen(service: _session.service, lease: lease),
        ),
      ),
    );
    if (mounted && identity == _session.service.identityScope) {
      setState(() => _homeRevision++);
    }
  }

  void _refresh() => unawaited(_session.refresh().catchError((Object _) {}));

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final resumedFromBackground = !_foreground;
      _foreground = true;
      PushNotificationService.instance.setAppForeground(true);
      if (resumedFromBackground) {
        DeliveryApiClient.instance.resetConnectionPool();
      }
      if (_session.service.signedIn &&
          (resumedFromBackground ||
              (!_session.verified && _session.error == null))) {
        _refresh();
      }
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      PushNotificationService.instance.setAppForeground(false);
    }
  }

  @override
  void dispose() {
    _clearAiController(immediate: true);
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    if (_pushWatcher != null) {
      PushNotificationService.instance.detachWatcher(_pushWatcher!);
    }
    unawaited(_pushAlertsSub?.cancel());
    _poll?.cancel();
    unawaited(_auth?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_session.service.signedIn || _recovery) {
      return CloudAuthScreen(
        service: _session.service,
        recovery: _recovery,
        onRecovered: () {
          setState(() => _recovery = false);
          _refresh();
        },
      );
    }
    if (!_session.verified) {
      return StudioUserAuthFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StudioUserAuthBrand(),
            const SizedBox(height: 18),
            if (_session.error == null) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 14),
              const Text(
                'Đang đồng bộ tài khoản GHST EXPRESS...',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ] else ...[
              const Text(
                'Chưa tải được tài khoản.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _refresh,
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.refresh,
                  size: 17,
                ),
                label: const Text('Thử lại'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _session.service.signOut,
              icon: const GhstButtonIcon.glyph(GhstActionKind.logout, size: 17),
              label: const Text('Đăng xuất'),
            ),
          ],
        ),
      );
    }

    final scope = '${_session.service.identityScope}:${_session.revision}';
    final roleMode = _effectiveRoleMode;
    if (roleMode == GhstRoleMode.operator && _session.isOperator) {
      return AdminPortalScreen(
        key: ValueKey('$scope:operator-portal'),
        session: _session,
        onSwitchToUserMode: () =>
            _selectRoleMode(_defaultRoleMode(allowOperator: false)),
      );
    }

    if (_session.phase == CloudAccountPhase.blocked) {
      return StudioUserAuthFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StudioUserAuthBrand(),
            const SizedBox(height: 18),
            const Text(
              'Tài khoản đang bị khóa.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (_session.isOperator)
              OutlinedButton.icon(
                key: const ValueKey('blocked-return-operator'),
                onPressed: () => _selectRoleMode(GhstRoleMode.operator),
                icon: const GhstAiIcon(
                  style: Icon3dStyle.adminShieldOps,
                  size: 18,
                  circular: true,
                ),
                label: const Text('Quay lại Cổng Quản trị'),
              ),
            TextButton.icon(
              onPressed: _session.service.signOut,
              icon: const GhstButtonIcon.glyph(GhstActionKind.logout, size: 17),
              label: const Text('Đăng xuất'),
            ),
          ],
        ),
      );
    }
    if (_session.phase == CloudAccountPhase.incomplete) {
      return StudioUserAuthFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StudioUserAuthBrand(),
            const SizedBox(height: 14),
            const Text(
              'Hoàn tất hồ sơ GHST EXPRESS',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'Bổ sung họ tên và số điện thoại liên hệ một lần duy nhất để vào Trang chủ.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            CloudProfileForm(session: _session),
            if (_session.isOperator) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('incomplete-return-operator'),
                onPressed: () => _selectRoleMode(GhstRoleMode.operator),
                icon: const GhstAiIcon(
                  style: Icon3dStyle.adminShieldOps,
                  size: 18,
                  circular: true,
                ),
                label: const Text('Quay lại Cổng Quản trị'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _session.service.signOut,
              icon: const GhstButtonIcon.glyph(GhstActionKind.logout, size: 17),
              label: const Text('Đăng xuất'),
            ),
          ],
        ),
      );
    }

    final aiController = _resolveAiController(scope);
    Widget market(MarketView view) => MarketplaceView(
      key: ValueKey('$scope:$view'),
      session: _session,
      view: view,
      showHeading: false,
      onNavigate: _navigate,
      onOpenShipping: _openDriverTrips,
      onOpenDeliveryJourney: _openShippingDetails,
      onOpenOperations: () => _go(GhstUserSection.merchantOperations),
      onOpenSettings: () => _go(GhstUserSection.settings),
      onOpenOperator: _session.isOperator
          ? () => _selectRoleMode(GhstRoleMode.operator)
          : null,
    );
    final home = GhstHomeScreen(
      key: ValueKey('$scope:$_section:$_homeRevision'),
      session: _session,
      trackingOnly: _section == GhstUserSection.tracking,
      onCreateOrder: _createOrder,
      onCatalog: () => _go(GhstUserSection.food),
      onAddresses: _addresses,
      onOrders: _openShipping,
      onAiAssistant: () => _go(GhstUserSection.aiAssistant),
      onOpenPromoHub: (tab) => openCloudPromoEvents(
        context,
        _session,
        initialTab: tab,
        onOpenCatalog: () => _go(GhstUserSection.food),
      ),
      onAddressChanged: (address) {
        if (mounted && _address != address) setState(() => _address = address);
      },
    );

    final isWide = MediaQuery.sizeOf(context).width >= 860;
    final Widget shippingContent =
        roleMode == GhstRoleMode.merchant &&
            _session.hasRole('merchant') &&
            !isWide
        ? Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Đơn lẻ'),
                      icon: GhstAiIcon(
                        style: Icon3dStyle.createPlus,
                        size: 16,
                        circular: true,
                      ),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Nhập CSV'),
                      icon: GhstAiIcon(
                        style: Icon3dStyle.csvImport,
                        size: 16,
                        circular: true,
                      ),
                    ),
                    ButtonSegment(
                      value: 2,
                      label: Text('Đã gửi'),
                      icon: GhstAiIcon(
                        style: Icon3dStyle.orderReceipt,
                        size: 16,
                        circular: true,
                      ),
                    ),
                    ButtonSegment(
                      value: 3,
                      label: Text('Thu gom'),
                      icon: GhstAiIcon(
                        style: Icon3dStyle.hub2hBatch,
                        size: 16,
                        circular: true,
                      ),
                    ),
                  ],
                  selected: {_merchantShipTab},
                  onSelectionChanged: (v) =>
                      setState(() => _merchantShipTab = v.first),
                ),
              ),
              Expanded(
                child: switch (_merchantShipTab) {
                  1 => CloudSessionBoundary(
                    key: ValueKey('$scope:merchant-csv-mobile'),
                    session: _session,
                    roles: const {'merchant'},
                    builder: (_, lease) =>
                        CloudOrderImportScreen(session: _session, lease: lease),
                  ),
                  2 => CloudOrdersScreen(
                    key: ValueKey('$scope:merchant-ship-mobile'),
                    session: _session,
                    embedded: true,
                  ),
                  3 => CloudSessionBoundary(
                    key: ValueKey('$scope:merchant-pickups-mobile'),
                    session: _session,
                    roles: const {'merchant'},
                    builder: (_, lease) =>
                        CloudPickupScreen(session: _session, lease: lease),
                  ),
                  _ => GhstShippingScreen(
                    key: ValueKey('$scope:form:$_formRevision'),
                    session: _session,
                    initialDetails: _shippingDetails,
                    onCreated: () => setState(() => _merchantShipTab = 2),
                    onOrderCreated: (created) =>
                        _handleOrderCreated(created, merchantMobile: true),
                  ),
                },
              ),
            ],
          )
        : GhstShippingScreen(
            key: ValueKey('$scope:form:$_formRevision'),
            session: _session,
            initialDetails: _shippingDetails,
            onCreated: _openShipping,
            onOrderCreated: _handleOrderCreated,
          );

    final Widget content = switch (_section) {
      GhstUserSection.home => home,
      GhstUserSection.tracking =>
        roleMode == GhstRoleMode.driver && _session.hasRole('driver')
            ? CloudSessionBoundary(
                key: ValueKey('$scope:driver-cockpit'),
                session: _session,
                roles: const {'driver'},
                builder: (_, lease) => DriverLiveCockpitPanel(
                  session: _session,
                  lease: lease,
                  onOpenQueue: () => _go(GhstUserSection.driverQueue),
                  onOpenOrderDetails: _openShippingDetails,
                ),
              )
            : home,
      GhstUserSection.shipping => shippingContent,
      GhstUserSection.food => market(MarketView.catalog),
      GhstUserSection.profile => market(MarketView.account),
      GhstUserSection.settings => CloudSessionBoundary(
        key: ValueKey('$scope:settings'),
        session: _session,
        builder: (_, lease) => CloudAppSettingsScreen(
          session: _session,
          lease: lease,
          embedded: true,
          roleMode: roleMode,
          availableModes: _unlockedModes(),
          onSelectRoleMode: _selectRoleMode,
          aiController: aiController,
          onOpenAddresses: _addresses,
          onOpenNotifications: () => _go(GhstUserSection.notifications),
          onOpenAiAssistant: () => _go(GhstUserSection.aiAssistant),
          onOpenOperator: _session.isOperator
              ? () => _selectRoleMode(GhstRoleMode.operator)
              : null,
        ),
      ),
      GhstUserSection.notifications => CloudSessionBoundary(
        key: ValueKey('$scope:notifications'),
        session: _session,
        builder: (_, lease) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: CloudNotificationCenter(
              session: _session,
              lease: lease,
              embedded: true,
              onOpenShippingOrder: (_) {
                setState(() {
                  _purchaseOrders = false;
                  _section = roleMode == GhstRoleMode.driver
                      ? GhstUserSection.driverTrips
                      : GhstUserSection.orders;
                });
              },
              onOpenMarketOrder: (orderId) => openMarketOrderServices(
                context,
                _session,
                orderId: orderId,
              ),
              onOpenPickup: () {
                if (_session.hasRole('merchant')) {
                  _go(GhstUserSection.merchantPickups);
                } else if (_session.hasRole('driver')) {
                  _go(GhstUserSection.driverPickups);
                } else {
                  openCloudPickups(context, _session);
                }
              },
              onOpenPromo: () => openCloudPromoEvents(
                context,
                _session,
                onOpenCatalog: () => _go(GhstUserSection.food),
              ),
              onOpenProfile: () => _go(GhstUserSection.profile),
            ),
          ),
        ),
      ),
      GhstUserSection.aiAssistant => GhstAiChatScreen(
        key: ValueKey('$scope:ai'),
        session: _session,
        controller: aiController,
      ),
      GhstUserSection.workspace => market(MarketView.workspace),
      GhstUserSection.merchantOrders => market(MarketView.merchantOrders),
      GhstUserSection.merchantOperations => CloudSessionBoundary(
        key: ValueKey('$scope:merchant-ops'),
        session: _session,
        roles: const {'merchant'},
        builder: (_, lease) => MerchantOperationsCenter(
          session: _session,
          lease: lease,
          onOpenDeliveryJourney: _openShippingDetails,
        ),
      ),
      GhstUserSection.merchantCsvImport => CloudSessionBoundary(
        key: ValueKey('$scope:merchant-csv'),
        session: _session,
        roles: const {'merchant'},
        builder: (_, lease) =>
            CloudOrderImportScreen(session: _session, lease: lease),
      ),
      GhstUserSection.merchantPickups => CloudSessionBoundary(
        key: ValueKey('$scope:merchant-pickups'),
        session: _session,
        roles: const {'merchant'},
        builder: (_, lease) =>
            CloudPickupScreen(session: _session, lease: lease),
      ),
      GhstUserSection.driverQueue => CloudOrdersScreen(
        key: ValueKey('$scope:driver-queue'),
        session: _session,
        embedded: true,
        initialQueue: true,
      ),
      GhstUserSection.driverTrips => CloudOrdersScreen(
        key: ValueKey('$scope:driver-trips'),
        session: _session,
        embedded: true,
      ),
      GhstUserSection.driverPickups => CloudSessionBoundary(
        key: ValueKey('$scope:driver-pickups'),
        session: _session,
        roles: const {'driver'},
        builder: (_, lease) =>
            CloudPickupScreen(session: _session, lease: lease),
      ),
      GhstUserSection.driverStats => CloudSessionBoundary(
        key: ValueKey('$scope:driver-stats'),
        session: _session,
        roles: const {'driver'},
        builder: (_, lease) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CloudDeliveryStatsCard(
                      service: _session.service,
                      lease: lease,
                    ),
                    DriverReviewsPanel(
                      service: _session.service,
                      lease: lease,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      GhstUserSection.orders =>
        roleMode == GhstRoleMode.merchant
            ? CloudOrdersScreen(
                key: ValueKey('$scope:merchant-shipping'),
                session: _session,
                embedded: true,
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Đơn giao hàng'),
                          icon: GhstAiIcon(
                            style: Icon3dStyle.scooterExpress,
                            size: 18,
                            circular: true,
                          ),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Đơn mua'),
                          icon: GhstAiIcon(
                            style: Icon3dStyle.shoppingCart,
                            size: 18,
                            circular: true,
                          ),
                        ),
                      ],
                      selected: {_purchaseOrders},
                      onSelectionChanged: (value) =>
                          setState(() => _purchaseOrders = value.first),
                    ),
                  ),
                  Expanded(
                    child: _purchaseOrders
                        ? market(MarketView.orders)
                        : CloudOrdersScreen(
                            key: ValueKey('$scope:shipping'),
                            session: _session,
                            embedded: true,
                          ),
                  ),
                ],
              ),
    };

    final showAiBubble =
        ThemeControllerScope.maybeOf(context)?.showAiFloatingBubble ?? true;

    return ListenableBuilder(
      listenable: PushNotificationService.instance,
      builder: (context, _) => GhstUserShell(
        section: _section,
        roleMode: roleMode,
        availableModes: _unlockedModes(),
        onRoleModeChanged: _selectRoleMode,
        name: '${_session.account?['full_name'] ?? ''}',
        address: _address,
        merchant: _session.hasMerchantAccess,
        merchantOwner: _session.hasRole('merchant'),
        driver: _session.hasRole('driver'),
        unreadNotifications: PushNotificationService.instance.unreadCount,
        onNavigate: _go,
        onDriverOrders: _openDriverTrips,
        onAddresses: _addresses,
        onCreateOrder: () => _createOrder({}),
        onCart: () => openMarketplaceView(context, _session, MarketView.cart),
        onLogout: _session.service.signOut,
        floatingOverlay:
            _section == GhstUserSection.aiAssistant || !showAiBubble
            ? null
            : GhstAiFloatingBubble(
                key: ValueKey('$scope:ai-bubble'),
                controller: aiController,
                onExpandFullScreen: () => _go(GhstUserSection.aiAssistant),
              ),
        child: content,
      ),
    );
  }
}
