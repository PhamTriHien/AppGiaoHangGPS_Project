import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/integrations/push_notification_service.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../../core/theme/theme_controller.dart';
import '../customer/ghst_ai_chat_screen.dart';
import '../customer/ghst_user_shell.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/cloud_membership_panel.dart';
import '../widgets/cloud_notification_center.dart';
import '../widgets/cloud_profile_form.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/ghst_button_icon.dart';
import '../widgets/theme_mode_toggle.dart';
import 'cloud_address_book_screen.dart';
import 'cloud_local_import_screen.dart';

Future<void> openCloudAppSettings(
  BuildContext context,
  CloudAccountSession session, {
  GhstAiChatController? aiController,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CloudSessionBoundary(
      session: session,
      builder: (_, lease) => Scaffold(
        appBar: AppBar(title: const Text('Cài đặt ứng dụng')),
        body: SafeArea(
          child: CloudAppSettingsScreen(
            session: session,
            lease: lease,
            aiController: aiController,
          ),
        ),
      ),
    ),
  ),
);

class CloudAppSettingsScreen extends StatefulWidget {
  const CloudAppSettingsScreen({
    super.key,
    required this.session,
    this.lease,
    this.embedded = false,
    this.roleMode = GhstRoleMode.customer,
    this.availableModes,
    this.onSelectRoleMode,
    this.aiController,
    this.onOpenAddresses,
    this.onOpenNotifications,
    this.onOpenAiAssistant,
    this.onOpenOperator,
  });

  final CloudAccountSession session;
  final CloudSessionLease? lease;
  final bool embedded;
  final GhstRoleMode roleMode;
  final List<GhstRoleMode>? availableModes;
  final ValueChanged<GhstRoleMode>? onSelectRoleMode;
  final GhstAiChatController? aiController;
  final VoidCallback? onOpenAddresses;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenAiAssistant;
  final VoidCallback? onOpenOperator;

  @override
  State<CloudAppSettingsScreen> createState() => _CloudAppSettingsScreenState();
}

class _CloudAppSettingsScreenState extends State<CloudAppSettingsScreen> {
  static const String _appVersion = '1.0.0 (Build 1)';
  late final String _scope = widget.session.service.identityScope;
  bool _busy = false;
  bool _savingPref = false;
  bool _fallbackAiBubble = true;
  String? _notice;
  String? _error;

  CloudAccountSession get _session => widget.session;

  bool get _valid =>
      _session.canUseBusiness &&
      _session.service.identityScope == _scope &&
      (widget.lease?.valid ?? true);

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
    unawaited(_loadFallbackBubblePref());
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFallbackBubblePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool('ghst_ai_bubble');
      if (mounted && saved != null && saved != _fallbackAiBubble) {
        setState(() => _fallbackAiBubble = saved);
      }
    } catch (_) {}
  }

  List<GhstRoleMode> _resolvedModes() {
    if (widget.availableModes != null && widget.availableModes!.isNotEmpty) {
      return widget.availableModes!;
    }
    return [
      if (_session.isOperator) GhstRoleMode.operator,
      if (_session.hasMerchantAccess) GhstRoleMode.merchant,
      if (_session.hasRole('driver')) GhstRoleMode.driver,
      GhstRoleMode.customer,
    ];
  }

  String _cloudRoleKeyFor(GhstRoleMode mode) =>
      mode == GhstRoleMode.operator ? 'admin' : mode.name;

  String _platformLabel() {
    if (kIsWeb) return 'Trình duyệt Web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => 'Windows Desktop',
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.linux => 'Linux',
      _ => 'Đa nền tảng',
    };
  }

  String _authProviderLabel() {
    final meta = _session.service.authSession?.user.appMetadata;
    final providers = meta?['providers'];
    if (providers is List && providers.isNotEmpty) {
      final labels = <String>[];
      for (final p in providers) {
        final key = '$p'.toLowerCase();
        if (key == 'google') {
          labels.add('Google');
        } else if (key == 'email') {
          labels.add('Email & Mật khẩu');
        }
      }
      if (labels.isNotEmpty) return labels.join(' · ');
    }
    final single = '${meta?['provider'] ?? ''}'.toLowerCase();
    if (single == 'google') return 'Google';
    if (single == 'email') return 'Email & Mật khẩu';
    return 'Email xác thực';
  }

  String _maskedCitizenId() {
    final raw = _session.citizenId?.trim() ?? '';
    if (raw.length != 12) return 'Chưa cập nhật';
    return '••••••••${raw.substring(8)}';
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    String? successNotice,
  }) async {
    if (_busy || !_valid) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      if (mounted && _valid && successNotice != null) {
        setState(() => _notice = successNotice);
      }
    } catch (e) {
      if (mounted && widget.lease?.handleAccessFailure(e) != true) {
        setState(() => _error = _describeError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describeError(Object error) {
    if (error is PublicApiException) return error.message;
    if (error is AuthException) return error.message;
    if (error is StateError) return error.message;
    if (error is ArgumentError) {
      return '${error.message ?? 'Dữ liệu không hợp lệ.'}';
    }
    return 'Không thể thực hiện thao tác. Vui lòng thử lại.';
  }

  Future<void> _toggleNotificationPref(String key, bool value) async {
    if (_savingPref || !_valid) return;
    setState(() {
      _savingPref = true;
      _error = null;
      _notice = null;
    });
    try {
      await PushNotificationService.instance.updatePreferences(
        {key: value},
        session: _session,
      );
    } catch (e) {
      if (mounted && widget.lease?.handleAccessFailure(e) != true) {
        setState(() => _error = _describeError(e));
      }
    } finally {
      if (mounted) setState(() => _savingPref = false);
    }
  }

  Future<void> _toggleAiBubble(
    ThemeController? themeController,
    bool value,
  ) async {
    if (themeController != null) {
      await themeController.setShowAiFloatingBubble(value);
      return;
    }
    setState(() => _fallbackAiBubble = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('ghst_ai_bubble', value);
    } catch (_) {}
  }

  Future<void> _selectDefaultRole(GhstRoleMode mode) async {
    final key = _cloudRoleKeyFor(mode);
    await _runAction(
      () async {
        await _session.saveUiPreferences(preferredRole: key);
        widget.onSelectRoleMode?.call(mode);
      },
      successNotice: 'Đã đặt "${mode.label}" làm không gian mở mặc định.',
    );
  }

  Future<void> _openEditProfile() async {
    if (!_valid) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudSessionBoundary(
          session: _session,
          profile: true,
          builder: (pageContext, lease) => Scaffold(
            appBar: AppBar(title: const Text('Chỉnh sửa hồ sơ cá nhân')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: CloudProfileForm(
                    session: _session,
                    lease: lease,
                    onSaved: () => Navigator.pop(pageContext),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted && _valid) {
      setState(() {});
    }
  }

  Future<void> _openPartnerMemberships() async {
    if (!_valid || _session.schemaVersion < 3) return;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            const GhstAiIcon(
              style: Icon3dStyle.driverPartner,
              size: 28,
              borderRadius: 8,
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('Quản lý vai trò Đối tác')),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: CloudMembershipPanel(
              session: _session,
              lease: widget.lease,
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(dialogCtx),
            icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),
            label: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddressBook() async {
    if (!_valid) return;
    if (widget.onOpenAddresses != null) {
      widget.onOpenAddresses!();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudSessionBoundary(
          session: _session,
          builder: (_, lease) => CloudAddressBookScreen(
            service: _session.service,
            lease: lease,
          ),
        ),
      ),
    );
  }

  Future<void> _openLocalImport() async {
    if (!_valid || _session.schemaVersion < 3) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudSessionBoundary(
          session: _session,
          builder: (_, lease) => CloudLocalImportScreen(
            session: _session,
            lease: lease,
          ),
        ),
      ),
    );
  }

  Future<void> _openNotifications() async {
    if (!_valid) return;
    if (widget.onOpenNotifications != null) {
      widget.onOpenNotifications!();
      return;
    }
    await openCloudNotificationCenter(context, _session);
  }

  Future<void> _showChangePasswordDialog() async {
    if (!_valid || _busy) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        email: _session.service.email,
        onUpdatePassword: _session.service.updatePassword,
        describeError: _describeError,
      ),
    );
    if (changed == true && mounted) {
      setState(() {
        _error = null;
        _notice = 'Đã cập nhật mật khẩu đăng nhập thành công.';
      });
    }
  }

  Future<void> _confirmClearAiHistory() async {
    if (!_valid || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Xóa lịch sử Trợ lý AI?'),
        content: const Text(
          'Toàn bộ cuộc trò chuyện đã lưu với Trợ lý AI của tài khoản sẽ bị xóa vĩnh viễn.',
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(dialogCtx, false),
            icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),
            label: const Text('Hủy'),
          ),
          FilledButton.icon(
            key: const ValueKey('settings-confirm-clear-ai'),
            onPressed: () => Navigator.pop(dialogCtx, true),
            icon: const GhstButtonIcon.glyph(GhstActionKind.delete, size: 16),
            label: const Text('Xóa lịch sử'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runAction(
      () async {
        widget.aiController?.reset();
        await _session.service.aiHistory('clear');
      },
      successNotice: 'Đã xóa lịch sử trò chuyện Trợ lý AI.',
    );
  }

  Future<void> _clearShippingDraft() async {
    await _runAction(
      () async {
        await _session.service.accountPreferences('clear_draft');
        _session.updateCachedShippingDraft(null);
      },
      successNotice: 'Đã xóa bản nháp tạo vận đơn.',
    );
  }

  Widget _sectionHeading({
    required GhstThemeTokens tokens,
    required Icon3dStyle icon,
    required String title,
    required String subtitle,
  }) => Row(
    children: [
      GhstAiIcon(
        style: icon,
        size: 38,
        borderRadius: 11,
        selected: true,
        borderColor: tokens.sapphire.border,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: tokens.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: tokens.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _metaRow(
    GhstThemeTokens tokens,
    String label,
    String value, {
    TonePair? badgeTone,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: tokens.inkSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 6,
          child: Align(
            alignment: Alignment.centerRight,
            child: badgeTone != null
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: badgeTone.fill,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: badgeTone.border),
                    ),
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: badgeTone.foreground,
                      ),
                    ),
                  )
                : Text(
                    value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: tokens.ink,
                    ),
                  ),
          ),
        ),
      ],
    ),
  );

  Widget _buildHeaderBanner(GhstThemeTokens tokens) {
    final fullName = '${_session.account?['full_name'] ?? ''}'.trim();
    final email = _session.service.email;
    final verifiedKyc = _session.identityVerified;
    return GhstAuroraBanner(
      gradient: tokens.heroGradient,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const GhstAiIcon(
                style: Icon3dStyle.settingsGear,
                size: 46,
                borderRadius: 13,
                selected: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cài đặt ứng dụng',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tùy chỉnh giao diện Sáng/Tối, cảnh báo thời gian thực, bảo mật đăng nhập và dữ liệu cá nhân',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.84),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _bannerPill(
                icon: GhstActionKind.user,
                text: fullName.isEmpty ? email : '$fullName · $email',
              ),
              _bannerPill(
                icon: verifiedKyc ? GhstActionKind.shield : GhstActionKind.info,
                text: verifiedKyc
                    ? 'Đã xác thực định danh'
                    : 'Chưa xác thực CCCD',
              ),
              _bannerPill(
                icon: GhstActionKind.layers,
                text: 'Không gian: ${widget.roleMode.label}',
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('settings-refresh-session'),
                onPressed: _busy
                    ? null
                    : () => _runAction(
                        () async {
                          await _session.refresh();
                          await PushNotificationService.instance.pollNow();
                        },
                        successNotice: 'Đã đồng bộ trạng thái tài khoản mới nhất.',
                      ),
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.refresh,
                  size: 16,
                ),
                label: const Text('Đồng bộ lại'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerPill({
    required GhstActionKind icon,
    required String text,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GhstButtonIcon.glyph(icon, size: 14, color: Colors.white),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildFallbackThemeCard(GhstThemeTokens tokens) {
    final currentRaw =
        _session.cloudThemeMode ?? (tokens.isDark ? 'dark' : 'light');
    final options = const [
      ('light', GhstActionKind.sun, 'Sáng', Key('theme-mode-light')),
      ('dark', GhstActionKind.moon, 'Tối', Key('theme-mode-dark')),
      (
        'system',
        GhstActionKind.autoTheme,
        'Hệ thống',
        Key('theme-mode-system'),
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.cardSubtle,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chủ đề hiển thị',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: tokens.ink,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    key: options[i].$4,
                    showCheckmark: false,
                    avatar: GhstButtonIcon.glyph(options[i].$2, size: 15),
                    label: Text(options[i].$3),
                    selected: currentRaw == options[i].$1,
                    onSelected: _busy
                        ? null
                        : (_) => unawaited(
                            _session.saveUiPreferences(
                              themeMode: options[i].$1,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceCard(
    GhstThemeTokens tokens,
    ThemeController? themeController,
  ) {
    final modes = _resolvedModes();
    final preferredRaw =
        _session.cloudPreferredRole ?? _cloudRoleKeyFor(widget.roleMode);
    final showBubble =
        themeController?.showAiFloatingBubble ?? _fallbackAiBubble;

    return GhstLuminousCard(
      padding: const EdgeInsets.all(16),
      accentGlow: tokens.sapphire.glow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeading(
            tokens: tokens,
            icon: Icon3dStyle.themeSunMoon,
            title: 'Giao diện & Không gian làm việc',
            subtitle: 'Chủ đề màu sắc, vai trò mặc định và tiện ích nổi',
          ),
          const SizedBox(height: 14),
          if (themeController != null)
            const ThemeModeSelectorCard()
          else
            _buildFallbackThemeCard(tokens),
          const SizedBox(height: 14),
          Text(
            'Không gian mở mặc định khi vào ứng dụng',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: tokens.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            modes.length > 1
                ? 'Chọn chế độ làm việc ưu tiên cho tài khoản đa vai trò'
                : 'Tài khoản đang sử dụng chế độ ${modes.first.label}',
            style: TextStyle(fontSize: 11.5, color: tokens.inkSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in modes)
                ChoiceChip(
                  key: ValueKey('settings-default-role-${mode.name}'),
                  showCheckmark: false,
                  avatar: GhstAiIcon(
                    style: mode.icon3d,
                    size: 16,
                    circular: true,
                    selected: preferredRaw == _cloudRoleKeyFor(mode),
                  ),
                  label: Text(mode.label),
                  selected: preferredRaw == _cloudRoleKeyFor(mode),
                  onSelected: _busy
                      ? null
                      : (selected) {
                          if (selected) unawaited(_selectDefaultRole(mode));
                        },
                ),
            ],
          ),
          if (modes.length == 1 && _session.schemaVersion >= 3) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _openPartnerMemberships,
                icon: const GhstAiIcon(
                  style: Icon3dStyle.driverPartner,
                  size: 18,
                  circular: true,
                ),
                label: const Text('Đăng ký thêm vai trò Tài xế / Cửa hàng'),
              ),
            ),
          ],
          const Divider(height: 24),
          SwitchListTile(
            key: const ValueKey('settings-toggle-ai-bubble'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: showBubble,
            onChanged: (v) => unawaited(_toggleAiBubble(themeController, v)),
            secondary: const GhstAiIcon(
              style: Icon3dStyle.aiAssistant,
              size: 28,
              circular: true,
            ),
            title: const Text(
              'Hiển thị nút nổi Trợ lý AI',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Nút truy cập nhanh Trợ lý AI ở góc dưới màn hình làm việc',
            ),
          ),
          if (widget.onOpenAiAssistant != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('settings-open-ai'),
                onPressed: widget.onOpenAiAssistant,
                icon: const GhstAiIcon(
                  style: Icon3dStyle.aiAssistant,
                  size: 18,
                  circular: true,
                ),
                label: const Text('Mở Trợ lý AI toàn màn hình'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNotificationCard(GhstThemeTokens tokens) {
    return ListenableBuilder(
      listenable: PushNotificationService.instance,
      builder: (context, _) {
        final prefs = PushNotificationService.instance.preferences;
        final unread = PushNotificationService.instance.unreadCount;
        final devicePushOn =
            PushNotificationService.instance.enabled &&
            prefs['push_enabled'] != false;

        return GhstLuminousCard(
          padding: const EdgeInsets.all(16),
          accentGlow: tokens.cyan.glow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeading(
                tokens: tokens,
                icon: Icon3dStyle.notificationBell,
                title: 'Thông báo & Cảnh báo thời gian thực',
                subtitle:
                    'Quản lý thông báo đẩy trên thiết bị và nhóm tin nhận về',
              ),
              const SizedBox(height: 10),
              if (PushNotificationService.supported)
                SwitchListTile(
                  key: const ValueKey('settings-push-enabled'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: devicePushOn,
                  onChanged: _savingPref
                      ? null
                      : (v) => _toggleNotificationPref('push_enabled', v),
                  secondary: const GhstButtonIcon(
                    Icons.notifications_active_outlined,
                  ),
                  title: const Text(
                    'Thông báo đẩy trên thiết bị',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    devicePushOn
                        ? 'Hiển thị thông báo hệ thống ngay khi có cập nhật mới'
                        : 'Bật để nhận cảnh báo tức thời trên thiết bị này',
                  ),
                ),
              SwitchListTile(
                key: const ValueKey('settings-pref-shipping'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: prefs['shipping_updates'] != false,
                onChanged: _savingPref
                    ? null
                    : (v) => _toggleNotificationPref('shipping_updates', v),
                secondary: const GhstButtonIcon(Icons.local_shipping_outlined),
                title: const Text('Cập nhật vận đơn & thu gom'),
                subtitle: const Text(
                  'Trạng thái nhận chuyến, đang giao, hoàn tất và điều xe',
                ),
              ),
              SwitchListTile(
                key: const ValueKey('settings-pref-market'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: prefs['market_updates'] != false,
                onChanged: _savingPref
                    ? null
                    : (v) => _toggleNotificationPref('market_updates', v),
                secondary: const GhstButtonIcon(Icons.storefront_outlined),
                title: const Text('Đơn mua sắm & gian hàng'),
                subtitle: const Text(
                  'Xác nhận đơn ăn uống, hậu mãi hoàn tiền và quyết toán',
                ),
              ),
              SwitchListTile(
                key: const ValueKey('settings-pref-promo'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: prefs['promo_updates'] != false,
                onChanged: _savingPref
                    ? null
                    : (v) => _toggleNotificationPref('promo_updates', v),
                secondary: const GhstButtonIcon(Icons.card_giftcard_outlined),
                title: const Text('Ưu đãi, sự kiện & Ví Xu'),
                subtitle: const Text(
                  'Tích Xu đơn hoàn tất, hoàn Xu và phần thưởng sự kiện',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Thông báo bảo mật, định danh hồ sơ và duyệt vai trò luôn được bật.',
                style: TextStyle(fontSize: 11.5, color: tokens.inkSecondary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('settings-open-notifications'),
                    onPressed: _openNotifications,
                    icon: const GhstAiIcon(
                      style: Icon3dStyle.notificationBell,
                      size: 18,
                      circular: true,
                    ),
                    label: Text(
                      unread > 0
                          ? 'Mở Trung tâm thông báo ($unread chưa đọc)'
                          : 'Mở Trung tâm thông báo',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccountCard(GhstThemeTokens tokens) {
    final acc = _session.account;
    final phone = '${acc?['phone'] ?? 'Chưa cập nhật'}';
    final birthDisplay = formatIsoBirthDate(_session.birthDate);
    final verifiedKyc = _session.identityVerified;

    return GhstLuminousCard(
      padding: const EdgeInsets.all(16),
      accentGlow: tokens.emerald.glow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeading(
            tokens: tokens,
            icon: Icon3dStyle.userProfile,
            title: 'Tài khoản, Định danh & Địa chỉ',
            subtitle: 'Thông tin hồ sơ xác thực, vai trò đối tác và sổ địa chỉ',
          ),
          const SizedBox(height: 12),
          _metaRow(
            tokens,
            'Họ và tên',
            '${acc?['full_name'] ?? 'Chưa cập nhật'}',
          ),
          _metaRow(tokens, 'Số điện thoại', phone),
          _metaRow(
            tokens,
            'Ngày sinh',
            birthDisplay.isEmpty ? 'Chưa cập nhật' : birthDisplay,
          ),
          _metaRow(tokens, 'Căn cước công dân', _maskedCitizenId()),
          _metaRow(
            tokens,
            'Trạng thái định danh',
            verifiedKyc ? 'Đã xác thực' : 'Chưa xác thực',
            badgeTone: verifiedKyc ? tokens.emerald : tokens.amber,
          ),
          _metaRow(
            tokens,
            'Số dư Ví Xu',
            '${_session.coinBalance} Xu',
            badgeTone: tokens.sapphire,
          ),
          const Divider(height: 22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('settings-edit-profile'),
                onPressed: _busy ? null : _openEditProfile,
                icon: const GhstAiIcon(
                  style: Icon3dStyle.userProfile,
                  size: 18,
                  circular: true,
                ),
                label: const Text('Chỉnh sửa hồ sơ'),
              ),
              if (_session.schemaVersion >= 3)
                OutlinedButton.icon(
                  key: const ValueKey('settings-partner-roles'),
                  onPressed: _busy ? null : _openPartnerMemberships,
                  icon: const GhstAiIcon(
                    style: Icon3dStyle.driverPartner,
                    size: 18,
                    circular: true,
                  ),
                  label: const Text('Vai trò Đối tác'),
                ),
              OutlinedButton.icon(
                key: const ValueKey('settings-address-book'),
                onPressed: _busy ? null : _openAddressBook,
                icon: const GhstAiIcon(
                  style: Icon3dStyle.addressBook,
                  size: 18,
                  circular: true,
                ),
                label: const Text('Sổ địa chỉ'),
              ),
              if (_session.schemaVersion >= 3)
                OutlinedButton.icon(
                  key: const ValueKey('settings-local-import'),
                  onPressed: _busy ? null : _openLocalImport,
                  icon: const GhstAiIcon(
                    style: Icon3dStyle.csvImport,
                    size: 18,
                    circular: true,
                  ),
                  label: const Text('Nhập địa chỉ thiết bị'),
                ),
              if (_session.isOperator && widget.onOpenOperator != null)
                OutlinedButton.icon(
                  key: const ValueKey('settings-open-operator'),
                  onPressed: widget.onOpenOperator,
                  icon: const GhstAiIcon(
                    style: Icon3dStyle.adminShieldOps,
                    size: 18,
                    circular: true,
                  ),
                  label: const Text('Cổng Quản trị'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityCard(GhstThemeTokens tokens) {
    return GhstLuminousCard(
      padding: const EdgeInsets.all(16),
      accentGlow: tokens.violet.glow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeading(
            tokens: tokens,
            icon: Icon3dStyle.adminShieldOps,
            title: 'Bảo mật & Phiên đăng nhập',
            subtitle: 'Quản lý mật khẩu đăng nhập và kiểm soát phiên thiết bị',
          ),
          const SizedBox(height: 12),
          _metaRow(tokens, 'Email đăng nhập', _session.service.email),
          _metaRow(
            tokens,
            'Phương thức liên kết',
            _authProviderLabel(),
            badgeTone: tokens.violet,
          ),
          _metaRow(
            tokens,
            'Trạng thái tài khoản',
            'Đang hoạt động',
            badgeTone: tokens.emerald,
          ),
          const Divider(height: 22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('settings-change-password'),
                onPressed: _busy ? null : _showChangePasswordDialog,
                icon: const GhstButtonIcon.glyph(GhstActionKind.lock, size: 16),
                label: const Text('Đổi mật khẩu'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('settings-revalidate-session'),
                onPressed: _busy
                    ? null
                    : () => _runAction(
                        _session.refresh,
                        successNotice: 'Phiên đăng nhập đã được xác thực lại.',
                      ),
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.refresh,
                  size: 16,
                ),
                label: const Text('Làm mới phiên'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('settings-sign-out'),
                onPressed: _busy
                    ? null
                    : () => _runAction(_session.service.signOut),
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.logout,
                  size: 16,
                ),
                label: const Text('Đăng xuất'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataAndPrivacyCard(GhstThemeTokens tokens) {
    final hasDraft = _session.shippingDraft != null;
    final aiCount = widget.aiController?.messages.length ?? 0;

    return GhstLuminousCard(
      padding: const EdgeInsets.all(16),
      accentGlow: tokens.amber.glow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeading(
            tokens: tokens,
            icon: Icon3dStyle.parcelBox,
            title: 'Dữ liệu tạm & Lịch sử Trợ lý AI',
            subtitle: 'Quản lý bản nháp tạo đơn và lịch sử hội thoại đã lưu',
          ),
          const SizedBox(height: 12),
          _metaRow(
            tokens,
            'Bản nháp vận đơn',
            hasDraft ? 'Đang có 1 bản nháp chưa gửi' : 'Trống',
            badgeTone: hasDraft ? tokens.amber : tokens.neutral,
          ),
          _metaRow(
            tokens,
            'Phiên trò chuyện Trợ lý AI',
            aiCount > 0
                ? 'Đang mở $aiCount tin nhắn gần nhất'
                : 'Lưu tự động theo tài khoản',
          ),
          const Divider(height: 22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('settings-clear-draft'),
                onPressed: _busy ? null : _clearShippingDraft,
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.delete,
                  size: 16,
                ),
                label: const Text('Xóa bản nháp vận đơn'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('settings-clear-ai-history'),
                onPressed: _busy ? null : _confirmClearAiHistory,
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.delete,
                  size: 16,
                ),
                label: const Text('Xóa lịch sử Trợ lý AI'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppInfoCard(GhstThemeTokens tokens) {
    return GhstLuminousCard(
      padding: const EdgeInsets.all(16),
      accentGlow: tokens.neutral.glow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeading(
            tokens: tokens,
            icon: Icon3dStyle.scooterExpress,
            title: 'Thông tin ứng dụng',
            subtitle: 'Phiên bản phát hành và môi trường vận hành hiện tại',
          ),
          const SizedBox(height: 12),
          _metaRow(tokens, 'Tên ứng dụng', 'GHST EXPRESS'),
          _metaRow(
            tokens,
            'Phiên bản phát hành',
            _appVersion,
            badgeTone: tokens.sapphire,
          ),
          _metaRow(tokens, 'Nền tảng thiết bị', _platformLabel()),
          _metaRow(
            tokens,
            'Bảo vệ dữ liệu',
            'Xác thực phiên trực tiếp & phân quyền theo vai trò',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final themeController = ThemeControllerScope.maybeOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCol = constraints.maxWidth >= 900;
        final appearance = _buildAppearanceCard(tokens, themeController);
        final notifications = _buildNotificationCard(tokens);
        final account = _buildAccountCard(tokens);
        final security = _buildSecurityCard(tokens);
        final dataPrivacy = _buildDataAndPrivacyCard(tokens);
        final appInfo = _buildAppInfoCard(tokens);

        return RefreshIndicator(
          onRefresh: () => _runAction(() async {
            await _session.refresh();
            await PushNotificationService.instance.pollNow();
          }),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              widget.embedded ? 14 : 18,
              14,
              widget.embedded ? 14 : 18,
              28,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeaderBanner(tokens),
                      if (_busy || _savingPref) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        GhstLuminousCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          backgroundColor: tokens.rose.fill,
                          borderColor: tokens.rose.border,
                          child: Row(
                            children: [
                              GhstButtonIcon.glyph(
                                GhstActionKind.warning,
                                size: 18,
                                color: tokens.rose.icon,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: tokens.rose.foreground,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_notice != null) ...[
                        const SizedBox(height: 12),
                        GhstLuminousCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          backgroundColor: tokens.emerald.fill,
                          borderColor: tokens.emerald.border,
                          child: Row(
                            children: [
                              GhstButtonIcon.glyph(
                                GhstActionKind.checkCircle,
                                size: 18,
                                color: tokens.emerald.icon,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _notice!,
                                  style: TextStyle(
                                    color: tokens.emerald.foreground,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      if (twoCol) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: appearance),
                            const SizedBox(width: 14),
                            Expanded(child: notifications),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: account),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  security,
                                  const SizedBox(height: 14),
                                  dataPrivacy,
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        appInfo,
                      ] else ...[
                        appearance,
                        const SizedBox(height: 14),
                        notifications,
                        const SizedBox(height: 14),
                        account,
                        const SizedBox(height: 14),
                        security,
                        const SizedBox(height: 14),
                        dataPrivacy,
                        const SizedBox(height: 14),
                        appInfo,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({
    required this.email,
    required this.onUpdatePassword,
    required this.describeError,
  });

  final String email;
  final Future<void> Function(String password) onUpdatePassword;
  final String Function(Object error) describeError;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _dialogError;

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final next = _newPassCtrl.text;
    final confirm = _confirmPassCtrl.text;
    if (next.length < 8) {
      setState(() => _dialogError = 'Mật khẩu mới phải có tối thiểu 8 ký tự.');
      return;
    }
    if (next != confirm) {
      setState(() => _dialogError = 'Mật khẩu xác nhận chưa trùng khớp.');
      return;
    }
    setState(() {
      _submitting = true;
      _dialogError = null;
    });
    try {
      await widget.onUpdatePassword(next);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _dialogError = widget.describeError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const GhstButtonIcon.glyph(GhstActionKind.lock, size: 22),
          const SizedBox(width: 10),
          const Expanded(child: Text('Đổi mật khẩu đăng nhập')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Áp dụng cho tài khoản ${widget.email}. Mật khẩu mới cần từ 8 ký tự trở lên.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('settings-new-password'),
                controller: _newPassCtrl,
                enabled: !_submitting,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu mới',
                  hintText: 'Tối thiểu 8 ký tự',
                  suffixIcon: IconButton(
                    tooltip: _obscureNew ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    onPressed: _submitting
                        ? null
                        : () => setState(() => _obscureNew = !_obscureNew),
                    icon: GhstButtonIcon.glyph(
                      _obscureNew ? GhstActionKind.eye : GhstActionKind.eyeOff,
                      size: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('settings-confirm-password'),
                controller: _confirmPassCtrl,
                enabled: !_submitting,
                obscureText: _obscureConfirm,
                onSubmitted: (_) => unawaited(_submit()),
                decoration: InputDecoration(
                  labelText: 'Nhập lại mật khẩu mới',
                  suffixIcon: IconButton(
                    tooltip: _obscureConfirm ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    onPressed: _submitting
                        ? null
                        : () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                    icon: GhstButtonIcon.glyph(
                      _obscureConfirm
                          ? GhstActionKind.eye
                          : GhstActionKind.eyeOff,
                      size: 18,
                    ),
                  ),
                ),
              ),
              if (_submitting) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_dialogError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _dialogError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),
          label: const Text('Hủy'),
        ),
        FilledButton.icon(
          key: const ValueKey('settings-submit-password'),
          onPressed: _submitting ? null : _submit,
          icon: const GhstButtonIcon.glyph(GhstActionKind.save, size: 16),
          label: const Text('Lưu mật khẩu'),
        ),
      ],
    );
  }
}
