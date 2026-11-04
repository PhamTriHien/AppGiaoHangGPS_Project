import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_orders_service.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/integrations/delivery_api_client.dart';
import '../../core/integrations/push_notification_service.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/admin_studio_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../widgets/admin_accounts_panel.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/backend_integration_settings.dart';
import '../widgets/cloud_logistics_panels.dart';
import '../widgets/cloud_notification_center.dart';
import '../widgets/cloud_order_labels.dart';
import '../widgets/cloud_pricing_dialog.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/ghst_button_icon.dart';
import '../widgets/market_commercial_sheets.dart';
import '../widgets/motion_3d_effects.dart';
import '../widgets/theme_mode_toggle.dart';
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
    this.onSwitchToUserMode,
  });

  final CloudAccountSession? session;
  final CloudOrdersService? service;
  final DeliveryApiClient? api;
  final VoidCallback? onSwitchToUserMode;

  @override
  State<AdminPortalScreen> createState() => _AdminPortalScreenState();
}

class _AdminPortalScreenState extends State<AdminPortalScreen>
    with WidgetsBindingObserver {
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
  String _accountsFilter = 'all';
  Object? _pushWatcher;

  static const _destinations = [
    (
      Icon3dStyle.analyticsChart,
      'Tổng quan',
      'Giám sát vận đơn, thương mại điện tử và sổ cái thời gian thực',
      'Tổng quan',
    ),
    (
      Icon3dStyle.userProfile,
      'Tài khoản',
      'Quản trị danh tính, phân quyền Điều hành viên/Đối tác và bảo mật tài khoản',
      'Tài khoản',
    ),
    (
      Icon3dStyle.cargoTruck,
      'Vận đơn',
      'Điều phối chuyến giao, lịch thu gom và hãng vận chuyển GHN',
      'Vận đơn',
    ),
    (
      Icon3dStyle.merchantStore,
      'Cửa hàng & Đánh giá',
      'Phê duyệt gian hàng đối tác và xử lý báo cáo vi phạm đánh giá',
      'Cửa hàng',
    ),
    (
      Icon3dStyle.walletVault,
      'Khuyến mãi & Đối soát',
      'Ngân sách voucher toàn sàn, sự kiện vòng xoay và đối soát kế toán kép',
      'Đối soát',
    ),
    (
      Icon3dStyle.settingsGear,
      'Tích hợp',
      'Quản lý khóa dịch vụ, kiểm tra kết nối và cấu trúc dữ liệu',
      'Tích hợp',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.start();
    _session.addListener(_onSessionChanged);
    _pushWatcher = PushNotificationService.instance.attachWatcher(_session);
    if (_service.signedIn && !_session.verified) {
      unawaited(_session.refresh().catchError((Object _) {}));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PushNotificationService.instance.setAppForeground(true);
      DeliveryApiClient.instance.resetConnectionPool();
      if (_service.signedIn) {
        unawaited(_session.refresh().catchError((Object _) {}));
      }
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      PushNotificationService.instance.setAppForeground(false);
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
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSessionChanged);
    if (_pushWatcher != null) {
      PushNotificationService.instance.detachWatcher(_pushWatcher!);
    }
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
              : 'Thông tin đăng nhập không hợp lệ hoặc chưa kết nối được dịch vụ.',
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

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AdminStudioTheme.of(context),
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

  Widget _buildDarkTopBanner({String? subtitle, List<Widget>? actions}) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          return Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 20,
              vertical: compact ? 10 : 14,
            ),
            decoration: const BoxDecoration(
              color: AdminStudioColors.shellDark,
              border: Border(
                bottom: BorderSide(color: AdminStudioColors.acid, width: 1.5),
              ),
            ),
            child: Row(
              children: [
                AdminStudioMark(size: compact ? 32 : 36),
                SizedBox(width: compact ? 8 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'GHST ADMIN',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 14.5 : 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                          color: Colors.white,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AdminStudioColors.acid,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: ThemeModeIconButton(onDarkHeader: true, compact: true),
                ),
                ...?actions,
              ],
            ),
          );
        },
      );

  Widget _buildLoginShowcase() {
    const pillars = [
      (
        Icon3dStyle.adminShieldOps,
        AdminStudioColors.acid,
        'Phân tách quyền Operator độc lập',
        'Xác thực phiên quản trị riêng biệt hoàn toàn với luồng ứng dụng người tiêu dùng.',
      ),
      (
        Icon3dStyle.walletVault,
        AdminStudioColors.gold,
        'Sổ cái kế toán kép & Đối soát',
        'Giám sát thu hộ COD, thanh toán trả trước, quyết toán cửa hàng và hoàn tiền minh bạch.',
      ),
      (
        Icon3dStyle.merchantStore,
        AdminStudioColors.pink,
        'Kiểm duyệt đối tác & Gian hàng',
        'Xét duyệt hồ sơ tài xế, cửa hàng mới và xử lý báo cáo đánh giá vi phạm.',
      ),
      (
        Icon3dStyle.aiAssistant,
        AdminStudioColors.violet,
        'Cấu hình dịch vụ tập trung',
        'Quản lý khóa dịch vụ bảo mật phân quyền kèm nhật ký kiểm toán thay đổi.',
      ),
    ];

    return AdminStudioGridBackdrop(
      enable3dHorizon: true,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(color: AdminStudioColors.line),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (box.maxHeight - 64).clamp(0.0, double.infinity),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      AdminStudioMark(size: 42),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'GHST ADMIN',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Cổng Điều hành Vận chuyển & Thương mại',
                              style: TextStyle(
                                color: AdminStudioColors.acid,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Animated3dIconBadge(
                              style: Icon3dStyle.adminShieldOps,
                              size: 50,
                              showRadarPulse: true,
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AdminStudioColors.shellElevated,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: AdminStudioColors.shellLine,
                                ),
                              ),
                              child: const Text(
                                'TRUNG TÂM ĐIỀU HÀNH BẢO MẬT',
                                style: TextStyle(
                                  color: AdminStudioColors.acid,
                                  fontSize: 10.5,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Điều phối vận đơn, đối tác và dịch vụ tích hợp trên một mặt phẳng duy nhất.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            height: 1.26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        for (final p in pillars)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Motion3dInteractiveSurface(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(12),
                              ),
                              maxTilt: 0.035,
                              hoverLift: -1.6,
                              enablePressScale: false,
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AdminStudioColors.shellElevated,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AdminStudioColors.shellLine,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GhstAiIcon(
                                      style: p.$1,
                                      size: 38,
                                      borderRadius: 10,
                                      selected: true,
                                      borderColor: p.$2.withValues(alpha: 0.72),
                                      glowColor: p.$2,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.$3,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            p.$4,
                                            style: const TextStyle(
                                              color:
                                                  AdminStudioColors.mutedOnDark,
                                              fontSize: 12,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Text(
                    'Mọi tác vụ cấu hình và đối soát đều được ghi vết kiểm toán theo tài khoản Operator.',
                    style: TextStyle(
                      color: AdminStudioColors.mutedOnDark,
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginFormCard() => Builder(
    builder: (context) {
      final p = AdminStudioPalette.of(context);
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AdminNeoBox(
          padding: const EdgeInsets.all(28),
          borderRadius: 20,
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Motion3dFloatingLayer(
                        floatAmplitude: 2.5,
                        tiltAmplitude: 0.04,
                        child: GhstAiIcon(
                          style: Icon3dStyle.adminShieldOps,
                          size: 46,
                          borderRadius: 13,
                          selected: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Đăng nhập quản trị',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: p.ink,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Xác thực phiên Điều hành viên',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: p.violet,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const ThemeModeIconButton(compact: true),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sử dụng tài khoản Điều hành viên đã được cấp quyền quản trị.',
                    style: TextStyle(
                      fontSize: 13,
                      color: p.muted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email quản trị',
                      prefixIcon: Padding(
                        padding: EdgeInsets.all(13),
                        child: GhstButtonIcon.glyph(
                          GhstActionKind.mail,
                          size: 19,
                        ),
                      ),
                    ),
                    validator: (v) => v == null || !v.trim().contains('@')
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
                      prefixIcon: const Padding(
                        padding: EdgeInsets.all(13),
                        child: GhstButtonIcon.glyph(
                          GhstActionKind.lock,
                          size: 19,
                        ),
                      ),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: GhstButtonIcon.glyph(
                          _obscure ? GhstActionKind.eye : GhstActionKind.eyeOff,
                          size: 19,
                        ),
                      ),
                    ),
                    validator: (v) => v == null || v.trim().length < 6
                        ? 'Mật khẩu tối thiểu 6 ký tự'
                        : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: p.dangerSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: p.danger.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GhstButtonIcon.glyph(
                            GhstActionKind.warning,
                            size: 18,
                            color: p.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: p.danger,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Motion3dInteractiveSurface(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    maxTilt: 0.055,
                    pressScale: 0.975,
                    hoverLift: -1.5,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _signIn,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.violet,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const GhstAiIcon(
                              style: Icon3dStyle.adminShieldOps,
                              size: 20,
                              circular: true,
                              selected: true,
                            ),
                      label: const Text(
                        'Đăng nhập',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _buildLogin() => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final split = constraints.maxWidth >= 900;
          if (split) {
            return Row(
              children: [
                SizedBox(
                  width: (constraints.maxWidth * 0.46).clamp(380.0, 560.0),
                  height: double.infinity,
                  child: _buildLoginShowcase(),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: _buildLoginFormCard(),
                    ),
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              _buildDarkTopBanner(subtitle: 'Cổng Điều hành Quản trị'),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildLoginFormCard(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _buildVerifying() => Builder(
    builder: (context) {
      final p = AdminStudioPalette.of(context);
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildDarkTopBanner(subtitle: 'Kiểm tra phiên quản trị'),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: AdminNeoBox(
                        padding: const EdgeInsets.all(28),
                        borderRadius: 20,
                        interactive3d: true,
                        maxTilt: 0.035,
                        enablePressScale: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_session.error == null) ...[
                              CircularProgressIndicator(
                                color: p.violet,
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Đang xác minh quyền quản trị...',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: p.ink,
                                ),
                              ),
                            ] else ...[
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: p.dangerSoft,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: p.danger.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                                child: Center(
                                  child: GhstButtonIcon.glyph(
                                    GhstActionKind.cloudOff,
                                    size: 24,
                                    color: p.danger,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Không xác minh được quyền quản trị.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: p.ink,
                                ),
                              ),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed: () => unawaited(
                                  _session.refresh().catchError((Object _) {}),
                                ),
                                icon: const GhstButtonIcon.glyph(
                                  GhstActionKind.refresh,
                                  size: 17,
                                ),
                                label: const Text('Thử lại'),
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: _signOut,
                              icon: const GhstButtonIcon.glyph(
                                GhstActionKind.logout,
                                size: 17,
                              ),
                              label: const Text('Đăng xuất'),
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
        ),
      );
    },
  );

  Widget _buildForbidden() => Builder(
    builder: (context) {
      final p = AdminStudioPalette.of(context);
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildDarkTopBanner(subtitle: 'Cảnh báo phân quyền truy cập'),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: AdminNeoBox(
                        padding: const EdgeInsets.all(28),
                        borderRadius: 20,
                        interactive3d: true,
                        maxTilt: 0.035,
                        enablePressScale: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: p.dangerSoft,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: p.danger.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                              ),
                              child: Center(
                                child: GhstButtonIcon.glyph(
                                  GhstActionKind.shield,
                                  size: 28,
                                  color: p.danger,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Tài khoản chưa có quyền quản trị.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: p.ink,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Cổng này chỉ dành cho điều hành viên hệ thống đã được cấp quyền quản trị.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: p.muted,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _signOut,
                              icon: const GhstButtonIcon.glyph(
                                GhstActionKind.logout,
                                size: 17,
                              ),
                              label: const Text('Đăng xuất'),
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
        ),
      );
    },
  );

  Future<void> _openPricing() async {
    final res = await _service.request('pricing');
    if (!mounted || !_session.isOperator) return;
    await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Theme(
        data: AdminStudioTheme.of(dialogCtx),
        child: CloudSessionBoundary(
          session: _session,
          operator: true,
          dialog: true,
          builder: (_, lease) => CloudPricingDialog(
            service: _service,
            pricing: Map<String, dynamic>.from(res['pricing'] as Map),
            lease: lease,
          ),
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
      builder: (dialogCtx) => Theme(
        data: AdminStudioTheme.of(dialogCtx),
        child: CloudSessionBoundary(
          session: _session,
          operator: true,
          dialog: true,
          builder: (dialog, _) {
            final p = AdminStudioPalette.of(dialog);
            return AlertDialog(
              title: const Text(
                'Nhật ký điều hành',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              content: SizedBox(
                width: 540,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (entries.isEmpty) const Text('Chưa có thay đổi.'),
                      for (final e in entries)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: p.surfaceSubtle,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: p.line),
                          ),
                          child: SelectableText(
                            '${adminAuditActionLabel(e['action'])} · ${e['action']} · ${e['target_id'] ?? ''}\n${cloudDate(e['created_at'])} · ${e['actor_id']}',
                            style: const TextStyle(fontSize: 12.5, height: 1.45),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(dialog),
                  icon: const GhstButtonIcon.glyph(
                    GhstActionKind.close,
                    size: 16,
                  ),
                  label: const Text('Đóng'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDesktopSidebar() => SizedBox(
    width: 262,
    child: AdminStudioGridBackdrop(
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(color: AdminStudioColors.line),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 20, 18, 18),
              child: Row(
                children: [
                  AdminStudioMark(size: 38),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GHST ADMIN',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'STUDIO · OPS CONSOLE',
                          style: TextStyle(
                            color: AdminStudioColors.acid,
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AdminStudioColors.shellLine, height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Text(
                'PHÂN HỆ QUẢN TRỊ',
                style: TextStyle(
                  color: AdminStudioColors.mutedOnDark,
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                itemCount: _destinations.length,
                itemBuilder: (context, index) {
                  final d = _destinations[index];
                  final selected = _tab == index;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Motion3dInteractiveSurface(
                      borderRadius: const BorderRadius.all(Radius.circular(10)),
                      maxTilt: 0.028,
                      pressScale: 0.978,
                      hoverLift: -0.8,
                      child: Material(
                        color: selected
                            ? AdminStudioColors.shellActive
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() {
                            _tab = index;
                            if (index == 1) _accountsFilter = 'all';
                          }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? AdminStudioColors.acid.withValues(
                                      alpha: 0.45,
                                    )
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: [
                              GhstAiIcon(
                                style: d.$1,
                                size: 26,
                                borderRadius: 8,
                                selected: selected,
                                borderColor: selected
                                    ? AdminStudioColors.acid.withValues(
                                        alpha: 0.72,
                                      )
                                    : AdminStudioColors.shellLine,
                                glowColor: AdminStudioColors.acid,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  d.$2,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
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
                },
              ),
            ),
            if (widget.onSwitchToUserMode != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Semantics(
                  button: true,
                  label: 'Giao diện Khách hàng',
                  excludeSemantics: true,
                  child: OutlinedButton.icon(
                    key: const ValueKey('admin-switch-user-mode'),
                    onPressed: widget.onSwitchToUserMode,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminStudioColors.acid,
                      backgroundColor: AdminStudioColors.shellElevated,
                      side: BorderSide(
                        color: AdminStudioColors.acid.withValues(alpha: 0.45),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                    ),
                    icon: const GhstAiIcon(
                      style: Icon3dStyle.scooterExpress,
                      size: 20,
                      circular: true,
                      selected: true,
                    ),
                    label: const Text(
                      'Giao diện Khách hàng',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminStudioColors.shellElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AdminStudioColors.shellLine),
              ),
              child: Row(
                children: [
                  const GhstAiIcon(
                    style: Icon3dStyle.adminShieldOps,
                    size: 28,
                    borderRadius: 8,
                    selected: true,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Operator đã xác thực',
                          style: TextStyle(
                            color: AdminStudioColors.acid,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _service.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildDesktopTopBar() {
    final active = _destinations[_tab];
    return Builder(
      builder: (context) {
        final p = AdminStudioPalette.of(context);
        return Material(
          color: p.surface,
          child: Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: p.line),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, bar) {
                final compactActions = bar.maxWidth < 740;
                return Row(
                  children: [
                    GhstAiIcon(
                      style: active.$1,
                      size: 38,
                      borderRadius: 10,
                      selected: true,
                      borderColor: p.line,
                      glowColor: p.violet,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        active.$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: p.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (compactActions) ...[
                      IconButton(
                        tooltip: 'Bảng giá cước',
                        onPressed: _openPricing,
                        icon: const GhstAiIcon(
                          style: Icon3dStyle.walletVault,
                          size: 22,
                          circular: true,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Nhật ký điều hành',
                        onPressed: _openAudit,
                        icon: const GhstAiIcon(
                          style: Icon3dStyle.orderReceipt,
                          size: 22,
                          circular: true,
                        ),
                      ),
                    ] else ...[
                      OutlinedButton.icon(
                        onPressed: _openPricing,
                        icon: const GhstAiIcon(
                          style: Icon3dStyle.walletVault,
                          size: 19,
                          circular: true,
                        ),
                        label: const Text('Bảng giá cước'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _openAudit,
                        icon: const GhstAiIcon(
                          style: Icon3dStyle.orderReceipt,
                          size: 19,
                          circular: true,
                        ),
                        label: const Text('Nhật ký điều hành'),
                      ),
                    ],
                    const SizedBox(width: 8),
                    const ThemeModeIconButton(),
                    const SizedBox(width: 8),
                    ListenableBuilder(
                      listenable: PushNotificationService.instance,
                      builder: (context, _) {
                        final unread =
                            PushNotificationService.instance.unreadCount;
                        return IconButton(
                          tooltip: 'Trung tâm thông báo',
                          onPressed: () => openCloudNotificationCenter(
                            context,
                            _session,
                            operator: true,
                            onOpenShippingOrder: (_) {
                              Navigator.of(context).maybePop();
                              setState(() => _tab = 2);
                            },
                            onOpenProfile: () {
                              Navigator.of(context).maybePop();
                              setState(() => _tab = 1);
                            },
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: p.surfaceSubtle,
                            foregroundColor: p.ink,
                            side: BorderSide(color: p.line),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: Badge.count(
                            count: unread,
                            isLabelVisible: unread > 0,
                            child: GhstAiIcon(
                              style: Icon3dStyle.notificationBell,
                              size: 22,
                              circular: true,
                              selected: unread > 0,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Đăng xuất',
                      onPressed: _signOut,
                      style: IconButton.styleFrom(
                        backgroundColor: p.surfaceSubtle,
                        foregroundColor: p.ink,
                        side: BorderSide(color: p.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const GhstButtonIcon.glyph(
                        GhstActionKind.logout,
                        size: 18,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildWorkspace(CloudSessionLease lease) {
    final body = switch (_tab) {
      0 => _AdminAnalyticsPanel(
        session: _session,
        lease: lease,
        onNavigateTab: (index, {accountsFilter}) => setState(() {
          _tab = index;
          if (accountsFilter != null) _accountsFilter = accountsFilter;
        }),
      ),
      1 => AdminAccountsPanel(
        session: _session,
        lease: lease,
        initialFilter: _accountsFilter,
      ),
      2 => CloudOrdersScreen(
        session: _session,
        admin: true,
        embedded: true,
        showAccountsToggle: false,
      ),
      3 => _AdminModerationPanel(session: _session, lease: lease),
      4 => _AdminFinancePromoPanel(session: _session, lease: lease),
      _ => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: BackendIntegrationSettings(api: widget.api),
          ),
        ),
      ),
    };

    final animatedBody = Motion3dSectionTransition(
      transitionKey: _tab,
      child: body,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        if (wide) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  _buildDesktopSidebar(),
                  Expanded(
                    child: Column(
                      children: [
                        _buildDesktopTopBar(),
                        Expanded(child: animatedBody),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _buildDarkTopBanner(
                  subtitle: _service.email,
                  actions: [
                    ListenableBuilder(
                      listenable: PushNotificationService.instance,
                      builder: (context, _) {
                        final unread =
                            PushNotificationService.instance.unreadCount;
                        return IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Trung tâm thông báo',
                          onPressed: () => openCloudNotificationCenter(
                            context,
                            _session,
                            operator: true,
                            onOpenShippingOrder: (_) {
                              Navigator.of(context).maybePop();
                              setState(() => _tab = 2);
                            },
                            onOpenProfile: () {
                              Navigator.of(context).maybePop();
                              setState(() => _tab = 1);
                            },
                          ),
                          icon: Badge.count(
                            count: unread,
                            isLabelVisible: unread > 0,
                            child: GhstAiIcon(
                              style: Icon3dStyle.notificationBell,
                              size: 20,
                              circular: true,
                              selected: unread > 0,
                            ),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Bảng giá cước',
                      onPressed: _openPricing,
                      icon: const GhstAiIcon(
                        style: Icon3dStyle.walletVault,
                        size: 20,
                        circular: true,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Nhật ký điều hành',
                      onPressed: _openAudit,
                      icon: const GhstAiIcon(
                        style: Icon3dStyle.orderReceipt,
                        size: 20,
                        circular: true,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Đăng xuất',
                      onPressed: _signOut,
                      icon: const GhstButtonIcon.glyph(
                        GhstActionKind.logout,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (widget.onSwitchToUserMode != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: const BoxDecoration(
                      color: AdminStudioColors.shellElevated,
                      border: Border(
                        bottom: BorderSide(color: AdminStudioColors.shellLine),
                      ),
                    ),
                    child: Row(
                      children: [
                        const GhstAiIcon(
                          style: Icon3dStyle.adminShieldOps,
                          size: 17,
                          circular: true,
                          selected: true,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'VAI TRÒ: QUẢN TRỊ VIÊN',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AdminStudioColors.mutedOnDark,
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Semantics(
                          button: true,
                          label: 'Giao diện Khách hàng',
                          excludeSemantics: true,
                          child: Motion3dInteractiveSurface(
                            borderRadius: const BorderRadius.all(
                              Radius.circular(999),
                            ),
                            maxTilt: 0.055,
                            pressScale: 0.96,
                            hoverLift: -1.0,
                            child: InkWell(
                              key: const ValueKey('admin-switch-user-mode'),
                              borderRadius: BorderRadius.circular(999),
                              onTap: widget.onSwitchToUserMode,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: AdminStudioColors.acid,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GhstAiIcon(
                                      style: Icon3dStyle.scooterExpress,
                                      size: 16,
                                      circular: true,
                                    ),
                                    SizedBox(width: 5),
                                    Text(
                                      'Giao diện Khách hàng',
                                      style: TextStyle(
                                        color: AdminStudioColors.ink,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
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
                  ),
                Expanded(child: animatedBody),
              ],
            ),
          ),
          bottomNavigationBar: Builder(
            builder: (context) {
              final p = AdminStudioPalette.of(context);
              return Material(
                color: p.surface,
                child: SafeArea(
                  top: false,
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: p.line),
                      ),
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < _destinations.length; i++)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: _tab == i,
                              label: _destinations[i].$2,
                              excludeSemantics: true,
                              child: InkWell(
                                onTap: () => setState(() {
                                  _tab = i;
                                  if (i == 1) _accountsFilter = 'all';
                                }),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 5,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      GhstAiIcon(
                                        style: _destinations[i].$1,
                                        size: 24,
                                        borderRadius: 8,
                                        selected: _tab == i,
                                        borderColor: _tab == i
                                            ? p.violet
                                            : p.line,
                                        glowColor: p.violet,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _destinations[i].$4,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: _tab == i
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: _tab == i
                                              ? p.violetInk
                                              : p.muted,
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
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _AdminAnalyticsPanel extends StatefulWidget {
  const _AdminAnalyticsPanel({
    required this.session,
    required this.lease,
    required this.onNavigateTab,
  });

  final CloudAccountSession session;
  final CloudSessionLease lease;
  final void Function(int index, {String? accountsFilter}) onNavigateTab;

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
              : 'Chưa tải được chỉ số điều hành.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _vnd(dynamic v) =>
      CurrencyFormatter.formatVnd((v as num? ?? 0).toDouble());

  int _intVal(dynamic v) => (v as num? ?? 0).toInt();

  Widget _kpiSummaryTile({
    required IconData icon,
    required Color accent,
    required Color tint,
    required String label,
    required String value,
    required String detail,
    bool compact = false,
  }) {
    final p = AdminStudioPalette.of(context);
    return AdminNeoBox(
      padding: EdgeInsets.all(compact ? 12 : 16),
      interactive3d: true,
      maxTilt: 0.034,
      enablePressScale: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 30 : 36,
                height: compact ? 30 : 36,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.line),
                ),
                child: Center(
                  child: GhstButtonIcon(
                    icon,
                    size: compact ? 16 : 19,
                    color: accent,
                  ),
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 11.5 : 12.5,
                    fontWeight: FontWeight.w700,
                    color: p.muted,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 17 : 22,
              fontWeight: FontWeight.w900,
              color: p.ink,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              color: p.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color accent,
    required Color tint,
    required String title,
    required List<(String, String)> rows,
    double? completionRatio,
  }) {
    final p = AdminStudioPalette.of(context);
    return AdminNeoBox(
      padding: const EdgeInsets.all(18),
      interactive3d: true,
      maxTilt: 0.022,
      enablePressScale: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.line),
                ),
                child: Center(
                  child: GhstButtonIcon(icon, size: 19, color: accent),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                    color: p.ink,
                  ),
                ),
              ),
              if (completionRatio != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: p.acidSoft,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: p.acidInk.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    '${(completionRatio * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      color: p.acidInk,
                    ),
                  ),
                ),
            ],
          ),
          if (completionRatio != null) ...[
            const SizedBox(height: 12),
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: completionRatio.clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: p.paper,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 14, color: p.line),
            Row(
              children: [
                Expanded(
                  child: Text(
                    rows[i].$1,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: p.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  rows[i].$2,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: p.ink,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AdminStudioPalette.of(context);
    final co = _data?['cloud_orders'] as Map? ?? const {};
    final mo = _data?['market_orders'] as Map? ?? const {};
    final fin = _data?['finance_totals'] as Map? ?? const {};
    final shops = _data?['shops'] as Map? ?? const {};
    final promo = _data?['promotions'] as Map? ?? const {};
    final ledger = _data?['ledger_balances'] as Map? ?? const {};

    final shipTotal = _intVal(co['total']);
    final shipDelivered = _intVal(co['delivered']);
    final marketTotal = _intVal(mo['total']);
    final marketDelivered = _intVal(mo['delivered']);
    final shopsPending = _intVal(shops['pending']);
    final membershipsPending = _intVal(_data?['memberships_pending']);
    final finPending = _intVal(fin['pending_requests']);
    final reportedReviews = _intVal(_data?['reported_reviews']);
    final pendingTotal =
        shopsPending + membershipsPending + finPending + reportedReviews;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AdminStudioGridBackdrop(
                      enable3dHorizon: true,
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AdminStudioColors.shellLine,
                          ),
                        ),
                        child: LayoutBuilder(
                          builder: (context, headerBox) {
                            final compact = headerBox.maxWidth < 520;
                            return Row(
                              children: [
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Chỉ số vận hành thời gian thực',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Tổng hợp trực tiếp từ dữ liệu đơn hàng và sổ cái giao dịch.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: AdminStudioColors.acid,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                if (compact)
                                  IconButton(
                                    tooltip: 'Làm mới',
                                    style: IconButton.styleFrom(
                                      backgroundColor:
                                          AdminStudioColors.shellElevated,
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(
                                        color: AdminStudioColors.shellLine,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: _busy ? null : _load,
                                    icon: const GhstButtonIcon.glyph(
                                      GhstActionKind.refresh,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  )
                                else
                                  FilledButton.icon(
                                    onPressed: _busy ? null : _load,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AdminStudioColors.acid,
                                      foregroundColor: p.onAccentInk,
                                    ),
                                    icon: GhstButtonIcon.glyph(
                                      GhstActionKind.refresh,
                                      size: 17,
                                      color: p.onAccentInk,
                                    ),
                                    label: const Text('Làm mới'),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  if (_busy)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        color: p.violet,
                        backgroundColor: p.paperWarm,
                      ),
                    ),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: p.dangerSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: p.danger.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: p.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (_data != null) ...[
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, c) {
                        final compact = c.maxWidth < 540;
                        final cols = c.maxWidth >= 920 ? 4 : 2;
                        final gap = compact ? 10.0 : 12.0;
                        final width = (c.maxWidth - gap * (cols - 1)) / cols;
                        final summaryTiles = [
                          _kpiSummaryTile(
                            compact: compact,
                            icon: Icons.local_shipping_outlined,
                            accent: p.onAccentInk,
                            tint: p.acid,
                            label: 'Tổng vận đơn',
                            value: '$shipTotal',
                            detail:
                                'Hoàn tất $shipDelivered · Đang giao ${_intVal(co['in_transit'])}',
                          ),
                          _kpiSummaryTile(
                            compact: compact,
                            icon: Icons.payments_outlined,
                            accent: Colors.white,
                            tint: p.violet,
                            label: 'Cước giao thành công',
                            value: _vnd(co['shipping_fee_delivered']),
                            detail:
                                'Chờ nhận chuyến: ${_intVal(co['searching'])}',
                          ),
                          _kpiSummaryTile(
                            compact: compact,
                            icon: Icons.account_balance_wallet_outlined,
                            accent: p.onAccentInk,
                            tint: p.gold,
                            label: 'Tổng thu hộ & Trả trước',
                            value: _vnd(fin['collections_completed']),
                            detail:
                                'Quyết toán shop: ${_vnd(fin['settlements_completed'])}',
                          ),
                          _kpiSummaryTile(
                            compact: compact,
                            icon: pendingTotal > 0
                                ? Icons.notification_important_outlined
                                : Icons.task_alt_rounded,
                            accent: pendingTotal > 0 ? p.pinkInk : p.acidInk,
                            tint: pendingTotal > 0 ? p.pinkSoft : p.acidSoft,
                            label: 'Tác vụ chờ phê duyệt',
                            value: '$pendingTotal',
                            detail:
                                '$shopsPending gian hàng · $membershipsPending đối tác · $finPending đối soát',
                          ),
                        ];
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final tile in summaryTiles)
                              SizedBox(width: width, child: tile),
                          ],
                        );
                      },
                    ),
                    if (pendingTotal > 0) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (membershipsPending > 0)
                            ActionChip(
                              backgroundColor: p.acid,
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: p.onAccentInk,
                              ),
                              avatar: GhstButtonIcon.glyph(
                                GhstActionKind.users,
                                size: 16,
                                color: p.onAccentInk,
                              ),
                              label: Text(
                                'Xét duyệt đối tác · $membershipsPending',
                              ),
                              onPressed: () => widget.onNavigateTab(
                                1,
                                accountsFilter: 'pending',
                              ),
                            ),
                          if (shopsPending > 0 || reportedReviews > 0)
                            ActionChip(
                              backgroundColor: p.gold,
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: p.onAccentInk,
                              ),
                              avatar: GhstButtonIcon.glyph(
                                GhstActionKind.checkCircle,
                                size: 16,
                                color: p.onAccentInk,
                              ),
                              label: Text(
                                'Kiểm duyệt gian hàng & báo cáo · ${shopsPending + reportedReviews}',
                              ),
                              onPressed: () => widget.onNavigateTab(3),
                            ),
                          if (finPending > 0)
                            ActionChip(
                              backgroundColor: p.violetSoft,
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: p.violetInk,
                              ),
                              avatar: GhstButtonIcon.glyph(
                                GhstActionKind.receipt,
                                size: 16,
                                color: p.violet,
                              ),
                              label: Text('Duyệt đối soát · $finPending'),
                              onPressed: () => widget.onNavigateTab(4),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, c) {
                        final cols = c.maxWidth >= 760 ? 2 : 1;
                        final width = (c.maxWidth - 16 * (cols - 1)) / cols;
                        final cards = [
                          _statCard(
                            icon: Icons.route_outlined,
                            accent: p.onAccentInk,
                            tint: p.acid,
                            title: 'Đơn vận chuyển',
                            completionRatio: shipTotal > 0
                                ? shipDelivered / shipTotal
                                : null,
                            rows: [
                              ('Tổng vận đơn', '$shipTotal'),
                              ('Chờ nhận chuyến', '${co['searching'] ?? 0}'),
                              ('Đang vận chuyển', '${co['in_transit'] ?? 0}'),
                              ('Đã giao thành công', '$shipDelivered'),
                              (
                                'Doanh thu cước đã giao',
                                _vnd(co['shipping_fee_delivered']),
                              ),
                            ],
                          ),
                          _statCard(
                            icon: Icons.shopping_bag_outlined,
                            accent: p.violet,
                            tint: p.violetSoft,
                            title: 'Đơn mua Thương mại điện tử',
                            completionRatio: marketTotal > 0
                                ? marketDelivered / marketTotal
                                : null,
                            rows: [
                              ('Tổng đơn cửa hàng', '$marketTotal'),
                              (
                                'Chờ cửa hàng xác nhận',
                                '${mo['pending'] ?? 0}',
                              ),
                              (
                                'Đang chuẩn bị / giao',
                                '${mo['accepted_ready'] ?? 0}',
                              ),
                              ('Đã giao hoàn tất', '$marketDelivered'),
                              ('Đã hủy', '${mo['cancelled'] ?? 0}'),
                            ],
                          ),
                          _statCard(
                            icon: Icons.menu_book_outlined,
                            accent: p.onAccentInk,
                            tint: p.gold,
                            title: 'Đối soát & Kế toán kép',
                            rows: [
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
                            ],
                          ),
                          _statCard(
                            icon: Icons.verified_outlined,
                            accent: p.pinkInk,
                            tint: p.pinkSoft,
                            title: 'Đối tác, Khuyến mãi & Kiểm duyệt',
                            rows: [
                              ('Cửa hàng đang mở', '${shops['active'] ?? 0}'),
                              ('Cửa hàng chờ duyệt', '$shopsPending'),
                              (
                                'Hồ sơ đối tác chờ duyệt',
                                '$membershipsPending',
                              ),
                              (
                                'Voucher đang chạy',
                                '${promo['active_vouchers'] ?? 0} · ${_vnd(promo['voucher_budget_used'])}',
                              ),
                              (
                                'Flash Sale / Xu lưu hành',
                                '${promo['active_flash_sales'] ?? 0} / ${promo['coins_circulating'] ?? 0} Xu',
                              ),
                              ('Đánh giá bị báo cáo', '$reportedReviews'),
                            ],
                          ),
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
                    const SizedBox(height: 16),
                    CloudDeliveryStatsCard(
                      service: widget.session.service,
                      lease: widget.lease,
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
      builder: (dialogCtx) => Theme(
        data: AdminStudioTheme.of(dialogCtx),
        child: CloudSessionBoundary(
          session: widget.session,
          operator: true,
          dialog: true,
          builder: (dialog, _) => AlertDialog(
            title: Text(
              hidden ? 'Ẩn đánh giá vi phạm' : 'Hiện lại đánh giá',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            content: TextField(
              controller: ctrl,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Lý do kiểm duyệt'),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(dialog),
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.close,
                  size: 16,
                ),
                label: const Text('Hủy'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialog, ctrl.text.trim()),
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.check,
                  size: 16,
                ),
                label: const Text('Xác nhận'),
              ),
            ],
          ),
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
  Widget build(BuildContext context) {
    final p = AdminStudioPalette.of(context);
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(
              bottom: BorderSide(color: p.line),
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: GhstAiIcon(
                      style: Icon3dStyle.merchantStore,
                      size: 18,
                      circular: true,
                    ),
                    label: Text('Duyệt cửa hàng'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: GhstButtonIcon.glyph(GhstActionKind.flag, size: 17),
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
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 960),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_busy)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: LinearProgressIndicator(
                                  color: p.violet,
                                ),
                              ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: p.danger,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            if (!_busy && _reported.isEmpty)
                              AdminNeoBox(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: p.acid,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: p.line,
                                        ),
                                      ),
                                      child: Center(
                                        child: GhstButtonIcon.glyph(
                                          GhstActionKind.shield,
                                          size: 22,
                                          color: p.onAccentInk,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Không có đánh giá bị báo cáo.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: p.ink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            for (final r in _reported)
                              AdminNeoBox(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: p.dangerSoft,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: p.line,
                                        ),
                                      ),
                                      child: Center(
                                        child: GhstButtonIcon.glyph(
                                          GhstActionKind.warning,
                                          color: p.danger,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${r['review_kind'] == 'partner' ? 'Đối tác' : 'Sản phẩm'} · ${r['rating']} sao · Báo cáo: ${r['report_count']}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: p.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${r['body']}',
                                            style: TextStyle(
                                              color: p.muted,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    OutlinedButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () => _moderate(
                                              r,
                                              r['hidden'] != true,
                                            ),
                                      icon: GhstButtonIcon.glyph(
                                        r['hidden'] == true
                                            ? GhstActionKind.eye
                                            : GhstActionKind.eyeOff,
                                        size: 16,
                                      ),
                                      label: Text(
                                        r['hidden'] == true ? 'Hiện lại' : 'Ẩn',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _AdminFinancePromoPanel extends StatefulWidget {
  const _AdminFinancePromoPanel({required this.session, required this.lease});
  final CloudAccountSession session;
  final CloudSessionLease lease;

  @override
  State<_AdminFinancePromoPanel> createState() =>
      _AdminFinancePromoPanelState();
}

class _AdminFinancePromoPanelState extends State<_AdminFinancePromoPanel> {
  Map<String, dynamic>? _promoSettings;
  Map<String, dynamic>? _promoSummary;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPromoStatus();
  }

  Future<void> _loadPromoStatus() async {
    if (!widget.lease.valid) return;
    try {
      final res = await widget.session.service.promoEvents('status');
      if (!mounted || !widget.lease.valid) return;
      if (res['settings'] is Map) {
        setState(() {
          _promoSettings = Map<String, dynamic>.from(res['settings'] as Map);
          if (res['admin_stats'] is Map) {
            _promoSummary = Map<String, dynamic>.from(
              res['admin_stats'] as Map,
            );
          }
        });
      }
    } catch (e) {
      widget.lease.handleAccessFailure(e);
    }
  }

  Future<void> _togglePromoEnabled(bool next) async {
    if (_busy || !widget.lease.valid) return;
    setState(() => _busy = true);
    try {
      final res = await widget.session.service.promoEvents(
        'admin_settings_save',
        {'enabled': next},
      );
      if (!mounted || !widget.lease.valid) return;
      if (res['settings'] is Map) {
        setState(() {
          _promoSettings = Map<String, dynamic>.from(res['settings'] as Map);
          if (res['admin_stats'] is Map) {
            _promoSummary = Map<String, dynamic>.from(
              res['admin_stats'] as Map,
            );
          }
        });
      }
    } catch (e) {
      widget.lease.handleAccessFailure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AdminStudioPalette.of(context);
    final enabled = _promoSettings?['enabled'] != false;
    final spins = (_promoSummary?['total_spins'] as num? ?? 0).toInt();
    final boxes = (_promoSummary?['total_boxes_opened'] as num? ?? 0).toInt();
    final personalVouchers =
        (_promoSummary?['personal_vouchers_active'] as num? ?? 0).toInt();

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(
              bottom: BorderSide(color: p.line),
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(
                        'Quản trị ngân sách khuyến mãi, tiến trình nền và đối soát hai bước',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: p.ink,
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => showVoucherEditorDialog(
                          context,
                          session: widget.session,
                          operator: true,
                        ),
                        icon: const GhstAiIcon(
                          style: Icon3dStyle.voucherFlash,
                          size: 18,
                          circular: true,
                        ),
                        label: const Text('Tạo voucher toàn sàn'),
                      ),
                    ],
                  ),
                  if (_promoSettings != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: enabled ? p.acidSoft : p.paperWarm,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: enabled
                              ? p.acidInk.withValues(alpha: 0.35)
                              : p.line,
                        ),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          Text(
                            'Sự kiện Vòng xoay & Hộp mù: ${enabled ? 'ĐANG MỞ' : 'TẠM TẮT'} · Quay: $spins · Hộp mù: $boxes · Voucher cá nhân: $personalVouchers',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: p.ink,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _togglePromoEnabled(!enabled),
                            icon: GhstButtonIcon.glyph(
                              enabled
                                  ? GhstActionKind.pause
                                  : GhstActionKind.play,
                              size: 16,
                            ),
                            label: Text(
                              enabled ? 'Tạm dừng sự kiện' : 'Mở lại sự kiện',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: MarketOrderServicesScreen(
            session: widget.session,
            lease: widget.lease,
            operator: true,
          ),
        ),
      ],
    );
  }
}
