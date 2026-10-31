import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../customer/ghst_home_screen.dart';
import '../customer/ghst_shipping_screen.dart';
import '../customer/ghst_user_shell.dart';
import '../widgets/cloud_profile_form.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/studio_user_auth_frame.dart';
import 'cloud_address_book_screen.dart';
import 'cloud_auth_screen.dart';
import 'cloud_orders_screen.dart';
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
  bool _purchaseOrders = false;
  String _address = '';
  late String _knownIdentity = _session.service.identityScope;
  Map<String, dynamic>? _shippingDetails;
  int _formRevision = 0, _homeRevision = 0;
  bool _recovery = false, _foreground = true;
  StreamSubscription<AuthState>? _auth;
  Timer? _poll;
  CloudAccountSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.start();
    _session.addListener(_changed);
    _auth = _session.service.authChanges.listen((state) {
      if (mounted && state.event == AuthChangeEvent.passwordRecovery) {
        setState(() => _recovery = true);
      }
      if (mounted && state.event == AuthChangeEvent.signedOut) {
        setState(() {
          _recovery = false;
          _section = GhstUserSection.home;
          _shippingDetails = null;
          _address = '';
          _purchaseOrders = false;
        });
      }
    });
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground && _session.service.signedIn) _refresh();
    });
  }

  void _changed() {
    if (mounted) {
      setState(() {
        if (_knownIdentity != _session.service.identityScope) {
          _knownIdentity = _session.service.identityScope;
          _address = '';
          _section = widget.initialShipping
              ? GhstUserSection.orders
              : GhstUserSection.home;
          _shippingDetails = null;
          _purchaseOrders = false;
        }
        if (_session.verified &&
            !_session.hasMerchantAccess &&
            [
              GhstUserSection.workspace,
              GhstUserSection.merchantOrders,
            ].contains(_section)) {
          _section = GhstUserSection.profile;
        }
      });
    }
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
      if (view == MarketView.orders) _purchaseOrders = true;
      _section = target;
    });
  }

  void _go(GhstUserSection section) {
    if (!_session.canUseBusiness) return;
    if ([
          GhstUserSection.workspace,
          GhstUserSection.merchantOrders,
        ].contains(section) &&
        !_session.hasMerchantAccess) {
      return;
    }
    if (section == GhstUserSection.shipping) {
      _createOrder({});
    } else {
      setState(() => _section = section);
    }
  }

  void _openShipping() => setState(() {
    _purchaseOrders = false;
    _section = GhstUserSection.orders;
  });

  void _createOrder(Map<String, dynamic> details) {
    if (!_session.canCreateShippingOrder) return;
    setState(() {
      _formRevision++;
      _shippingDetails = details;
      _section = GhstUserSection.shipping;
    });
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
      if (!_foreground) {
        _foreground = true;
        _session.invalidateVerification();
        _refresh();
      } else if (_session.service.signedIn &&
          !_session.verified &&
          _session.error == null) {
        _refresh();
      }
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_foreground) {
        _foreground = false;
        _session.invalidateVerification();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
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
    if (!_session.verified || !_foreground) {
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
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _session.service.signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Đăng xuất'),
            ),
          ],
        ),
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
            TextButton.icon(
              onPressed: _session.service.signOut,
              icon: const Icon(Icons.logout),
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
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _session.service.signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Đăng xuất'),
            ),
          ],
        ),
      );
    }
    final scope = '${_session.service.identityScope}:${_session.revision}';
    Widget market(MarketView view) => MarketplaceView(
      key: ValueKey('$scope:$view'),
      session: _session,
      view: view,
      showHeading: false,
      onNavigate: _navigate,
      onOpenShipping: _openShipping,
    );
    final home = GhstHomeScreen(
      key: ValueKey('$scope:$_section:$_homeRevision'),
      session: _session,
      trackingOnly: _section == GhstUserSection.tracking,
      onCreateOrder: _createOrder,
      onCatalog: () => _go(GhstUserSection.food),
      onAddresses: _addresses,
      onOrders: _openShipping,
      onAddressChanged: (address) {
        if (mounted && _address != address) setState(() => _address = address);
      },
    );
    final Widget content = switch (_section) {
      GhstUserSection.home || GhstUserSection.tracking => home,
      GhstUserSection.shipping => GhstShippingScreen(
        key: ValueKey('$scope:form:$_formRevision'),
        session: _session,
        initialDetails: _shippingDetails,
        onCreated: _openShipping,
      ),
      GhstUserSection.food => market(MarketView.catalog),
      GhstUserSection.profile => market(MarketView.account),
      GhstUserSection.notifications => market(MarketView.notifications),
      GhstUserSection.workspace => market(MarketView.workspace),
      GhstUserSection.merchantOrders => market(MarketView.merchantOrders),
      GhstUserSection.orders => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Đơn giao hàng'),
                  icon: Icon(Icons.local_shipping_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Đơn mua'),
                  icon: Icon(Icons.shopping_bag_outlined),
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
    return GhstUserShell(
      section: _section,
      name: '${_session.account?['full_name'] ?? ''}',
      address: _address,
      merchant: _session.hasMerchantAccess,
      driver: _session.hasRole('driver'),
      onNavigate: _go,
      onDriverOrders: _openShipping,
      onAddresses: _addresses,
      onCreateOrder: () => _createOrder({}),
      onCart: () => openMarketplaceView(context, _session, MarketView.cart),
      onLogout: _session.service.signOut,
      child: content,
    );
  }
}
