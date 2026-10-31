import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_orders_service.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/integrations/delivery_api_client.dart';
import '../../core/network/public_json_api.dart';
import '../../core/utils/currency_formatter.dart';
import '../widgets/backend_integration_settings.dart';
import '../widgets/cloud_order_labels.dart';
import '../widgets/cloud_pricing_dialog.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/market_commercial_sheets.dart';
import 'cloud_orders_screen.dart';
import 'market_order_services_screen.dart';
import 'marketplace_view.dart';

/// Cổng Điều hành Quản trị Cloud hợp nhất (/admin).
/// Độc lập hoàn toàn với giao diện người tiêu dùng và tài khoản SQLite cục bộ.
class AdminPortalScreen extends StatefulWidget {
  const AdminPortalScreen({
    super.key,
    this.session,
    this.service,
    this.api,
  });

  final CloudAccountSession? session;
  final CloudOrdersService? service;
  final DeliveryApiClient? api;

  @override
  State<AdminPortalScreen> createState() => _AdminPortalScreenState();
}

class _AdminPortalScreenState extends State<AdminPortalScreen> {
  late final CloudOrdersService _service =
      widget.session?.service ?? widget.service ?? CloudOrdersService();
  late final CloudAccountSession _session =
      widget.session ?? CloudAccountSession(service: _service);
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _session.start();
    _session.addListener(_onSessionChanged);
    if (_service.signedIn && !_session.verified) {
      unawaited(_session.refresh().catchError((Object _) {}));
    }
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      if (!_service.signedIn) {
        _tab = 0;
      }
    });
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    if (widget.session == null) _session.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.authenticate(_email.text.trim(), _password.text);
      _password.clear();
      await _session.refresh();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : e is AuthException
              ? e.message
              : 'Thông tin đăng nhập không hợp lệ hoặc chưa kết nối được Cloud.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await _service.signOut();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ThemeData _adminTheme() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087F5B)),
    scaffoldBackgroundColor: const Color(0xFFF4F6F5),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _adminTheme(),
      child: !_service.signedIn
          ? _buildLogin()
          : !_session.verified
          ? _buildVerifying()
          : !_session.isOperator
          ? _buildForbidden()
          : CloudSessionBoundary(
              key: ValueKey('${_service.identityScope}:${_session.revision}'),
              session: _session,
              operator: true,
              builder: (_, lease) => _buildWorkspace(lease),
            ),
    );
  }

  Widget _buildHeader({String? subtitle, List<Widget>? actions}) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          return Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 20,
              vertical: compact ? 10 : 14,
            ),
            color: Colors.white,
            child: Row(
              children: [
                const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: Color(0xFF087F5B),
                ),
                SizedBox(width: compact ? 8 : 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'GHST CLOUD ADMIN',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 15.5 : 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ),
                ...?actions,
              ],
            ),
          );
        },
      );

  Widget _buildLogin() => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Đăng nhập quản trị',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sử dụng tài khoản Operator đã được cấp quyền trên Cloud.',
                            style: TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email quản trị',
                            ),
                            validator: (v) =>
                                v == null || !v.trim().contains('@')
                                ? 'Nhập email quản trị hợp lệ'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _signIn(),
                            decoration: InputDecoration(
                              labelText: 'Mật khẩu',
                              suffixIcon: IconButton(
                                tooltip: _obscure
                                    ? 'Hiện mật khẩu'
                                    : 'Ẩn mật khẩu',
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (v) => v == null || v.trim().length < 6
                                ? 'Mật khẩu tối thiểu 6 ký tự'
                                : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: const TextStyle(color: Color(0xFFB42318)),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _busy ? null : _signIn,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Đăng nhập'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildVerifying() => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_session.error == null) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Đang xác minh quyền Operator Cloud...'),
              ] else ...[
                const Text('Không xác minh được quyền quản trị Cloud.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      unawaited(_session.refresh().catchError((Object _) {})),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ],
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Đăng xuất'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildForbidden() => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.gpp_bad_outlined,
                      size: 48,
                      color: Color(0xFFB42318),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Tài khoản cloud chưa có quyền operator.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Đăng xuất'),
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

  Future<void> _openPricing() async {
    final res = await _service.request('pricing');
    if (!mounted || !_session.isOperator) return;
    await showDialog<bool>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: _session,
        operator: true,
        dialog: true,
        builder: (_, lease) => CloudPricingDialog(
          service: _service,
          pricing: Map<String, dynamic>.from(res['pricing'] as Map),
          lease: lease,
        ),
      ),
    );
  }

  Future<void> _openAudit() async {
    final res = await _service.request('audit');
    if (!mounted || !_session.isOperator) return;
    final entries = (res['entries'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    await showDialog<void>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: _session,
        operator: true,
        dialog: true,
        builder: (dialog, _) => AlertDialog(
          title: const Text('Nhật ký điều hành Cloud'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entries.isEmpty) const Text('Chưa có thay đổi.'),
                  for (final e in entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: SelectableText(
                        '${e['action']} · ${e['target_id'] ?? ''}\n${cloudDate(e['created_at'])} · ${e['actor_id']}',
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Đóng'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspace(CloudSessionLease lease) {
    const destinations = [
      (Icons.analytics_outlined, 'Tổng quan'),
      (Icons.local_shipping_outlined, 'Đơn & Tài khoản'),
      (Icons.storefront_outlined, 'Cửa hàng & Đánh giá'),
      (Icons.account_balance_outlined, 'Khuyến mãi & Đối soát'),
      (Icons.settings_input_component_outlined, 'Tích hợp'),
    ];
    final body = switch (_tab) {
      0 => _AdminAnalyticsPanel(session: _session, lease: lease),
      1 => CloudOrdersScreen(
        session: _session,
        admin: true,
        embedded: true,
      ),
      2 => _AdminModerationPanel(session: _session, lease: lease),
      3 => _AdminFinancePromoPanel(session: _session, lease: lease),
      _ => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: BackendIntegrationSettings(api: widget.api),
          ),
        ),
      ),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(
                  subtitle: wide ? null : _service.email,
                  actions: [
                    if (wide) ...[
                      Text(
                        _service.email,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      visualDensity: wide ? null : VisualDensity.compact,
                      tooltip: 'Bảng giá cloud',
                      onPressed: _openPricing,
                      icon: const Icon(Icons.price_change_outlined),
                    ),
                    IconButton(
                      visualDensity: wide ? null : VisualDensity.compact,
                      tooltip: 'Nhật ký điều hành',
                      onPressed: _openAudit,
                      icon: const Icon(Icons.history),
                    ),
                    IconButton(
                      visualDensity: wide ? null : VisualDensity.compact,
                      tooltip: 'Đăng xuất',
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout),
                    ),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: wide
                      ? Row(
                          children: [
                            NavigationRail(
                              selectedIndex: _tab,
                              labelType: NavigationRailLabelType.all,
                              onDestinationSelected: (i) =>
                                  setState(() => _tab = i),
                              destinations: [
                                for (final d in destinations)
                                  NavigationRailDestination(
                                    icon: Icon(d.$1),
                                    label: Text(d.$2),
                                  ),
                              ],
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: body),
                          ],
                        )
                      : body,
                ),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: [
                    for (final d in destinations)
                      NavigationDestination(icon: Icon(d.$1), label: d.$2),
                  ],
                ),
        );
      },
    );
  }
}

class _AdminAnalyticsPanel extends StatefulWidget {
  const _AdminAnalyticsPanel({required this.session, required this.lease});
  final CloudAccountSession session;
  final CloudSessionLease lease;

  @override
  State<_AdminAnalyticsPanel> createState() => _AdminAnalyticsPanelState();
}

class _AdminAnalyticsPanelState extends State<_AdminAnalyticsPanel> {
  Map<String, dynamic>? _data;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy || !widget.lease.valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.session.service.market('admin_analytics');
      if (mounted && widget.lease.valid) setState(() => _data = res);
    } catch (e) {
      if (mounted && !widget.lease.handleAccessFailure(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa tải được chỉ số điều hành Cloud.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _vnd(dynamic v) =>
      CurrencyFormatter.formatVnd((v as num? ?? 0).toDouble());

  Widget _statCard(String title, List<(String, String)> rows) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 10),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(child: Text(r.$1)),
                  const SizedBox(width: 8),
                  Text(
                    r.$2,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final co = _data?['cloud_orders'] as Map? ?? const {};
    final mo = _data?['market_orders'] as Map? ?? const {};
    final fin = _data?['finance_totals'] as Map? ?? const {};
    final shops = _data?['shops'] as Map? ?? const {};
    final promo = _data?['promotions'] as Map? ?? const {};
    final ledger = _data?['ledger_balances'] as Map? ?? const {};

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Chỉ số vận hành Cloud thời gian thực',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Làm mới',
                        onPressed: _busy ? null : _load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFB42318)),
                      ),
                    ),
                  if (_data != null) ...[
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, c) {
                        final cols = c.maxWidth >= 760 ? 2 : 1;
                        final width = (c.maxWidth - 16 * (cols - 1)) / cols;
                        final cards = [
                          _statCard('Đơn vận chuyển Cloud', [
                            ('Tổng vận đơn', '${co['total'] ?? 0}'),
                            ('Chờ nhận chuyến', '${co['searching'] ?? 0}'),
                            ('Đang vận chuyển', '${co['in_transit'] ?? 0}'),
                            ('Đã giao thành công', '${co['delivered'] ?? 0}'),
                            (
                              'Doanh thu cước đã giao',
                              _vnd(co['shipping_fee_delivered']),
                            ),
                          ]),
                          _statCard('Đơn mua Thương mại điện tử', [
                            ('Tổng đơn cửa hàng', '${mo['total'] ?? 0}'),
                            ('Chờ cửa hàng xác nhận', '${mo['pending'] ?? 0}'),
                            (
                              'Đang chuẩn bị / giao',
                              '${mo['accepted_ready'] ?? 0}',
                            ),
                            ('Đã giao hoàn tất', '${mo['delivered'] ?? 0}'),
                            ('Đã hủy', '${mo['cancelled'] ?? 0}'),
                          ]),
                          _statCard('Đối soát & Kế toán kép', [
                            (
                              'Đã thu COD / trả trước',
                              _vnd(fin['collections_completed']),
                            ),
                            (
                              'Đã thanh toán cho shop',
                              _vnd(fin['settlements_completed']),
                            ),
                            (
                              'Đã hoàn tiền khách',
                              _vnd(fin['refunds_completed']),
                            ),
                            (
                              'Yêu cầu chờ duyệt',
                              '${fin['pending_requests'] ?? 0}',
                            ),
                            for (final entry in ledger.entries)
                              ('Sổ cái ${entry.key}', _vnd(entry.value)),
                          ]),
                          _statCard('Đối tác, Khuyến mãi & Kiểm duyệt', [
                            ('Cửa hàng đang mở', '${shops['active'] ?? 0}'),
                            ('Cửa hàng chờ duyệt', '${shops['pending'] ?? 0}'),
                            (
                              'Hồ sơ đối tác chờ duyệt',
                              '${_data!['memberships_pending'] ?? 0}',
                            ),
                            (
                              'Voucher đang chạy',
                              '${promo['active_vouchers'] ?? 0} (${_vnd(promo['voucher_budget_used'])})',
                            ),
                            (
                              'Flash Sale / Xu lưu hành',
                              '${promo['active_flash_sales'] ?? 0} / ${promo['coins_circulating'] ?? 0} Xu',
                            ),
                            (
                              'Đánh giá bị báo cáo',
                              '${_data!['reported_reviews'] ?? 0}',
                            ),
                          ]),
                        ];
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final card in cards)
                              SizedBox(width: width, child: card),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminModerationPanel extends StatefulWidget {
  const _AdminModerationPanel({required this.session, required this.lease});
  final CloudAccountSession session;
  final CloudSessionLease lease;

  @override
  State<_AdminModerationPanel> createState() => _AdminModerationPanelState();
}

class _AdminModerationPanelState extends State<_AdminModerationPanel> {
  bool _reviewsTab = false;
  List<Map<String, dynamic>> _reported = [];
  bool _busy = false;
  String? _error;

  Future<void> _loadReports({bool force = false}) async {
    if ((_busy && !force) || !widget.lease.valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.session.service.market('operations');
      if (mounted && widget.lease.valid) {
        setState(() {
          _reported = (res['reported_reviews'] as List? ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (e) {
      if (mounted && !widget.lease.handleAccessFailure(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa tải được danh sách đánh giá.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _moderate(Map<String, dynamic> rev, bool hidden) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: widget.session,
        operator: true,
        dialog: true,
        builder: (dialog, _) => AlertDialog(
          title: Text(hidden ? 'Ẩn đánh giá vi phạm' : 'Hiện lại đánh giá'),
          content: TextField(
            controller: ctrl,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Lý do kiểm duyệt'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, ctrl.text.trim()),
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), ctrl.dispose);
    if (reason == null || reason.length < 3 || !widget.lease.valid) return;
    setState(() => _busy = true);
    try {
      await widget.session.service.market('review_moderate', {
        'review_kind': rev['review_kind'],
        'id': rev['id'],
        'hidden': hidden,
        'reason': reason,
      });
      await _loadReports(force: true);
    } catch (e) {
      if (mounted && !widget.lease.handleAccessFailure(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa cập nhật được trạng thái đánh giá.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Duyệt cửa hàng')),
            ButtonSegment(
              value: true,
              label: Text('Đánh giá bị báo cáo'),
            ),
          ],
          selected: {_reviewsTab},
          onSelectionChanged: (v) {
            setState(() => _reviewsTab = v.first);
            if (v.first) _loadReports();
          },
        ),
      ),
      Expanded(
        child: !_reviewsTab
            ? MarketplaceView(
                session: widget.session,
                view: MarketView.moderation,
                lease: widget.lease,
                showHeading: false,
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null) Text(_error!),
                  if (!_busy && _reported.isEmpty)
                    const Text('Không có đánh giá bị báo cáo.'),
                  for (final r in _reported)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${r['review_kind'] == 'partner' ? 'Đối tác' : 'Sản phẩm'} · ${r['rating']} sao · Báo cáo: ${r['report_count']}',
                        ),
                        subtitle: Text('${r['body']}'),
                        trailing: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _moderate(r, r['hidden'] != true),
                          child: Text(r['hidden'] == true ? 'Hiện lại' : 'Ẩn'),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    ],
  );
}

class _AdminFinancePromoPanel extends StatelessWidget {
  const _AdminFinancePromoPanel({required this.session, required this.lease});
  final CloudAccountSession session;
  final CloudSessionLease lease;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => showVoucherEditorDialog(
              context,
              session: session,
              operator: true,
            ),
            icon: const Icon(Icons.confirmation_num_outlined),
            label: const Text('Tạo voucher toàn sàn'),
          ),
        ),
      ),
      Expanded(
        child: MarketOrderServicesScreen(
          session: session,
          lease: lease,
          operator: true,
        ),
      ),
    ],
  );
}
