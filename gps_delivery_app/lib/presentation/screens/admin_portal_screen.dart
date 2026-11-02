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
import '../widgets/cloud_logistics_panels.dart';
import '../widgets/cloud_order_labels.dart';
import '../widgets/cloud_pricing_dialog.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/market_commercial_sheets.dart';
import 'cloud_orders_screen.dart';
import 'market_order_services_screen.dart';
import 'marketplace_view.dart';

const _kAdminDark = Color(0xFF081C18);
const _kAdminDarkElevated = Color(0xFF10312A);
const _kAdminDarkActive = Color(0xFF15443A);
const _kAdminPrimary = Color(0xFF087F5B);
const _kAdminAccent = Color(0xFF12B886);
const _kAdminCanvas = Color(0xFFF1F5F9);
const _kAdminBorder = Color(0xFFE2E8F0);
const _kAdminText = Color(0xFF0F172A);
const _kAdminMuted = Color(0xFF64748B);
const _kAdminDanger = Color(0xFFB42318);

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

  static const _destinations = [
    (
      Icons.space_dashboard_outlined,
      Icons.space_dashboard_rounded,
      'Tổng quan',
      'Giám sát vận đơn, thương mại điện tử và sổ cái thời gian thực',
    ),
    (
      Icons.local_shipping_outlined,
      Icons.local_shipping_rounded,
      'Đơn & Tài khoản',
      'Điều phối chuyến giao, hãng vận chuyển GHN và xét duyệt hồ sơ đối tác',
    ),
    (
      Icons.storefront_outlined,
      Icons.storefront_rounded,
      'Cửa hàng & Đánh giá',
      'Phê duyệt gian hàng đối tác và xử lý báo cáo vi phạm đánh giá',
    ),
    (
      Icons.account_balance_outlined,
      Icons.account_balance_rounded,
      'Khuyến mãi & Đối soát',
      'Ngân sách voucher toàn sàn, tiến trình nền và đối soát kế toán kép',
    ),
    (
      Icons.hub_outlined,
      Icons.hub_rounded,
      'Tích hợp',
      'Quản lý khóa dịch vụ Cloud PostgreSQL, kiểm tra kết nối và schema',
    ),
  ];

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

  ThemeData _adminTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _kAdminPrimary,
      primary: _kAdminPrimary,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _kAdminCanvas,
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _kAdminBorder),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: _kAdminBorder,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kAdminPrimary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kAdminDanger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _kAdminPrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _kAdminText,
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

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

  Widget _buildBrandEmblem({double size = 38}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_kAdminAccent, _kAdminPrimary],
      ),
      borderRadius: BorderRadius.circular(size * 0.28),
      boxShadow: [
        BoxShadow(
          color: _kAdminPrimary.withValues(alpha: 0.28),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Icon(Icons.shield_outlined, color: Colors.white, size: size * 0.54),
  );

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
              color: _kAdminDark,
              border: Border(bottom: BorderSide(color: Color(0xFF1A433A))),
            ),
            child: Row(
              children: [
                _buildBrandEmblem(size: compact ? 32 : 36),
                SizedBox(width: compact ? 8 : 12),
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
                          fontSize: compact ? 14.5 : 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
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
                            color: Color(0xFF94A3B8),
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

  Widget _buildLoginShowcase() {
    const pillars = [
      (
        Icons.verified_user_outlined,
        'Phân tách quyền Operator độc lập',
        'Xác thực phiên quản trị riêng biệt hoàn toàn với luồng ứng dụng người tiêu dùng.',
      ),
      (
        Icons.account_balance_wallet_outlined,
        'Sổ cái kế toán kép & Đối soát',
        'Giám sát thu hộ COD, thanh toán trả trước, quyết toán cửa hàng và hoàn tiền minh bạch.',
      ),
      (
        Icons.storefront_outlined,
        'Kiểm duyệt đối tác & Gian hàng',
        'Xét duyệt hồ sơ tài xế, cửa hàng mới và xử lý báo cáo đánh giá vi phạm.',
      ),
      (
        Icons.cloud_done_outlined,
        'Cấu hình hạ tầng Cloud tập trung',
        'Quản lý khóa dịch vụ trên PostgreSQL khóa RLS kèm nhật ký kiểm toán thay đổi.',
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kAdminDark, Color(0xFF0D2E27), Color(0xFF0A3C30)],
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
                Row(
                  children: [
                    _buildBrandEmblem(size: 42),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GHST CLOUD ADMIN',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Cổng Điều hành Vận chuyển & Thương mại Cloud',
                            style: TextStyle(
                              color: Color(0xFF8CE99A),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _kAdminDarkActive,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFF206050)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: Color(0xFF63E6BE),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'TRUNG TÂM ĐIỀU HÀNH BẢO MẬT',
                              style: TextStyle(
                                color: Color(0xFF63E6BE),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Điều phối vận đơn, đối tác và tích hợp Cloud trên một mặt phẳng duy nhất.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 24),
                      for (final p in pillars)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: _kAdminDarkElevated,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF1E5245),
                                  ),
                                ),
                                child: Icon(
                                  p.$1,
                                  size: 18,
                                  color: const Color(0xFF63E6BE),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.$2,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      p.$3,
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 12.5,
                                        height: 1.4,
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
                const Text(
                  'Mọi tác vụ cấu hình và đối soát đều được ghi vết kiểm toán theo tài khoản Operator.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginFormCard() => Container(
    constraints: const BoxConstraints(maxWidth: 420),
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _kAdminBorder),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F0F172A),
          blurRadius: 28,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6FCF5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings_outlined,
                    color: _kAdminPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Đăng nhập quản trị',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _kAdminText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Xác thực phiên Operator Cloud',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.blueGrey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Sử dụng tài khoản Operator đã được cấp quyền trên Cloud.',
              style: TextStyle(fontSize: 13, color: _kAdminMuted, height: 1.4),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email quản trị',
                prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
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
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                  onPressed: () => setState(() => _obscure = !_obscure),
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECDCA)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: _kAdminDanger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: _kAdminDanger,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _signIn,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Đăng nhập',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
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
                  width: (constraints.maxWidth * 0.45).clamp(380.0, 540.0),
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
              _buildDarkTopBanner(subtitle: 'Cổng Điều hành Quản trị Cloud'),
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

  Widget _buildVerifying() => Scaffold(
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
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_session.error == null) ...[
                            const CircularProgressIndicator(),
                            const SizedBox(height: 18),
                            const Text(
                              'Đang xác minh quyền Operator Cloud...',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _kAdminText,
                              ),
                            ),
                          ] else ...[
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3F2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.cloud_off_outlined,
                                color: _kAdminDanger,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Không xác minh được quyền quản trị Cloud.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: () => unawaited(
                                _session.refresh().catchError((Object _) {}),
                              ),
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
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildForbidden() => Scaffold(
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
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3F2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.gpp_bad_outlined,
                              size: 32,
                              color: _kAdminDanger,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Tài khoản cloud chưa có quyền operator.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _kAdminText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Cổng này chỉ dành cho điều hành viên hệ thống đã được cấp vai trò Operator trên cơ sở dữ liệu Cloud.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: _kAdminMuted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),
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
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kAdminBorder),
                      ),
                      child: SelectableText(
                        '${e['action']} · ${e['target_id'] ?? ''}\n${cloudDate(e['created_at'])} · ${e['actor_id']}',
                        style: const TextStyle(fontSize: 12.5, height: 1.45),
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

  Widget _buildDesktopSidebar() => Container(
    width: 256,
    decoration: const BoxDecoration(
      color: _kAdminDark,
      border: Border(right: BorderSide(color: Color(0xFF153830))),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Row(
            children: [
              _buildBrandEmblem(size: 38),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GHST CLOUD ADMIN',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Điều hành Trung tâm',
                      style: TextStyle(
                        color: Color(0xFF63E6BE),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF153830), height: 1),
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Text(
            'PHÂN HỆ QUẢN TRỊ',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            itemCount: _destinations.length,
            itemBuilder: (context, index) {
              final d = _destinations[index];
              final selected = _tab == index;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: selected ? _kAdminDarkActive : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _tab = index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF206A58)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected ? d.$2 : d.$1,
                            size: 20,
                            color: selected
                                ? const Color(0xFF63E6BE)
                                : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              d.$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFFCBD5E1),
                                fontSize: 13.5,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
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
          ),
        ),
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kAdminDarkElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1A473C)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.verified_user_rounded,
                size: 18,
                color: Color(0xFF63E6BE),
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
                        color: Color(0xFF63E6BE),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _service.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildDesktopTopBar() {
    final active = _destinations[_tab];
    return Material(
      color: Colors.white,
      child: Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _kAdminBorder)),
        ),
        child: LayoutBuilder(
          builder: (context, bar) {
            final compactActions = bar.maxWidth < 740;
            return Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6FCF5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(active.$2, size: 20, color: _kAdminPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    active.$4,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _kAdminText,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (compactActions) ...[
                  IconButton(
                    tooltip: 'Bảng giá cloud',
                    onPressed: _openPricing,
                    icon: const Icon(Icons.price_change_outlined, size: 19),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Nhật ký điều hành',
                    onPressed: _openAudit,
                    icon: const Icon(Icons.history_rounded, size: 19),
                  ),
                ] else ...[
                  OutlinedButton.icon(
                    onPressed: _openPricing,
                    icon: const Icon(Icons.price_change_outlined, size: 18),
                    label: const Text('Bảng giá cloud'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _openAudit,
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('Nhật ký điều hành'),
                  ),
                ],
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Đăng xuất',
                  onPressed: _signOut,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF8FAFC),
                    side: const BorderSide(color: _kAdminBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 19),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildWorkspace(CloudSessionLease lease) {
    final body = switch (_tab) {
      0 => _AdminAnalyticsPanel(
        session: _session,
        lease: lease,
        onNavigateTab: (index) => setState(() => _tab = index),
      ),
      1 => CloudOrdersScreen(session: _session, admin: true, embedded: true),
      2 => _AdminModerationPanel(session: _session, lease: lease),
      3 => _AdminFinancePromoPanel(session: _session, lease: lease),
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
                        Expanded(child: body),
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
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Bảng giá cloud',
                      onPressed: _openPricing,
                      icon: const Icon(
                        Icons.price_change_outlined,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Nhật ký điều hành',
                      onPressed: _openAudit,
                      icon: const Icon(
                        Icons.history_rounded,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Đăng xuất',
                      onPressed: _signOut,
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Expanded(child: body),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            height: 66,
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFFD3F9D8),
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              for (final d in _destinations)
                NavigationDestination(
                  icon: Icon(d.$1),
                  selectedIcon: Icon(d.$2, color: _kAdminPrimary),
                  label: d.$3,
                ),
            ],
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
  final ValueChanged<int> onNavigateTab;

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

  int _intVal(dynamic v) => (v as num? ?? 0).toInt();

  Widget _kpiSummaryTile({
    required IconData icon,
    required Color accent,
    required Color tint,
    required String label,
    required String value,
    required String detail,
    bool compact = false,
  }) => Container(
    padding: EdgeInsets.all(compact ? 12 : 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(compact ? 14 : 16),
      border: Border.all(color: _kAdminBorder),
    ),
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
                borderRadius: BorderRadius.circular(compact ? 8 : 10),
              ),
              child: Icon(icon, size: compact ? 16 : 19, color: accent),
            ),
            SizedBox(width: compact ? 8 : 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11.5 : 12.5,
                  fontWeight: FontWeight.w600,
                  color: _kAdminMuted,
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
            fontWeight: FontWeight.w800,
            color: _kAdminText,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: compact ? 11 : 12, color: _kAdminMuted),
        ),
      ],
    ),
  );

  Widget _statCard({
    required IconData icon,
    required Color accent,
    required Color tint,
    required String title,
    required List<(String, String)> rows,
    double? completionRatio,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
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
                ),
                child: Icon(icon, size: 19, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                    color: _kAdminText,
                  ),
                ),
              ),
              if (completionRatio != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${(completionRatio * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
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
                  minHeight: 6,
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 14, color: Color(0xFFF1F5F9)),
            Row(
              children: [
                Expanded(
                  child: Text(
                    rows[i].$1,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  rows[i].$2,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: _kAdminText,
                  ),
                ),
              ],
            ),
          ],
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
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_kAdminDark, Color(0xFF0E392F)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: LayoutBuilder(
                      builder: (context, headerBox) {
                        final compact = headerBox.maxWidth < 520;
                        return Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Chỉ số vận hành Cloud thời gian thực',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Đồng bộ trực tiếp từ cơ sở dữ liệu PostgreSQL & sổ cái giao dịch Cloud.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFFA7F3D0),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (compact)
                              IconButton(
                                tooltip: 'Làm mới',
                                onPressed: _busy ? null : _load,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  color: Colors.white,
                                ),
                              )
                            else
                              FilledButton.icon(
                                onPressed: _busy ? null : _load,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _kAdminDarkActive,
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                    color: Color(0xFF206A58),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                ),
                                label: const Text('Làm mới'),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                        child: LinearProgressIndicator(minHeight: 4),
                      ),
                    ),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECDCA)),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: _kAdminDanger,
                          fontWeight: FontWeight.w600,
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
                            accent: _kAdminPrimary,
                            tint: const Color(0xFFE6FCF5),
                            label: 'Tổng vận đơn Cloud',
                            value: '$shipTotal',
                            detail:
                                'Hoàn tất $shipDelivered · Đang giao ${_intVal(co['in_transit'])}',
                          ),
                          _kpiSummaryTile(
                            compact: compact,
                            icon: Icons.payments_outlined,
                            accent: const Color(0xFF0B7285),
                            tint: const Color(0xFFE3FAFC),
                            label: 'Cước giao thành công',
                            value: _vnd(co['shipping_fee_delivered']),
                            detail:
                                'Chờ nhận chuyến: ${_intVal(co['searching'])}',
                          ),
                          _kpiSummaryTile(
                            compact: compact,
                            icon: Icons.account_balance_wallet_outlined,
                            accent: const Color(0xFF364FC7),
                            tint: const Color(0xFFEDF2FF),
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
                            accent: pendingTotal > 0
                                ? const Color(0xFFD9480F)
                                : _kAdminPrimary,
                            tint: pendingTotal > 0
                                ? const Color(0xFFFFF4E6)
                                : const Color(0xFFE6FCF5),
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
                              avatar: const Icon(
                                Icons.badge_outlined,
                                size: 16,
                                color: _kAdminPrimary,
                              ),
                              label: Text(
                                'Xét duyệt đối tác ($membershipsPending)',
                              ),
                              onPressed: () => widget.onNavigateTab(1),
                            ),
                          if (shopsPending > 0 || reportedReviews > 0)
                            ActionChip(
                              avatar: const Icon(
                                Icons.fact_check_outlined,
                                size: 16,
                                color: _kAdminPrimary,
                              ),
                              label: Text(
                                'Kiểm duyệt gian hàng & báo cáo (${shopsPending + reportedReviews})',
                              ),
                              onPressed: () => widget.onNavigateTab(2),
                            ),
                          if (finPending > 0)
                            ActionChip(
                              avatar: const Icon(
                                Icons.receipt_long_outlined,
                                size: 16,
                                color: _kAdminPrimary,
                              ),
                              label: Text('Duyệt đối soát ($finPending)'),
                              onPressed: () => widget.onNavigateTab(3),
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
                            accent: _kAdminPrimary,
                            tint: const Color(0xFFE6FCF5),
                            title: 'Đơn vận chuyển Cloud',
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
                            accent: const Color(0xFF364FC7),
                            tint: const Color(0xFFEDF2FF),
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
                            accent: const Color(0xFF0B7285),
                            tint: const Color(0xFFE3FAFC),
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
                            accent: const Color(0xFF5F3DC4),
                            tint: const Color(0xFFF3F0FF),
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
                                '${promo['active_vouchers'] ?? 0} (${_vnd(promo['voucher_budget_used'])})',
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
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: _kAdminBorder)),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.storefront_outlined, size: 18),
                  label: Text('Duyệt cửa hàng'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.flag_outlined, size: 18),
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
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: LinearProgressIndicator(),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: _kAdminDanger),
                              ),
                            ),
                          if (!_busy && _reported.isEmpty)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE6FCF5),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.verified_outlined,
                                        color: _kAdminPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Không có đánh giá bị báo cáo.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _kAdminText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          for (final r in _reported)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF3F2),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.report_problem_outlined,
                                          color: _kAdminDanger,
                                          size: 20,
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
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: _kAdminText,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '${r['body']}',
                                              style: const TextStyle(
                                                color: Color(0xFF334155),
                                                height: 1.4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      OutlinedButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _moderate(
                                                r,
                                                r['hidden'] != true,
                                              ),
                                        child: Text(
                                          r['hidden'] == true
                                              ? 'Hiện lại'
                                              : 'Ẩn',
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
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: _kAdminBorder)),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                const Text(
                  'Quản trị ngân sách khuyến mãi, tiến trình nền và đối soát hai bước',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _kAdminText,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => showVoucherEditorDialog(
                    context,
                    session: session,
                    operator: true,
                  ),
                  icon: const Icon(Icons.confirmation_num_outlined, size: 18),
                  label: const Text('Tạo voucher toàn sàn'),
                ),
              ],
            ),
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
