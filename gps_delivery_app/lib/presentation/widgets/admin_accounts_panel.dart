import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/admin_studio_theme.dart';
import 'cloud_membership_decision_dialog.dart';
import 'cloud_membership_panel.dart';
import 'cloud_order_labels.dart';
import 'cloud_profile_form.dart';
import 'cloud_session_boundary.dart';

const adminAuditActionLabels = {
  'pricing': 'Cập nhật bảng giá cước',
  'account_role': 'Cập nhật vai trò / trạng thái khóa',
  'account_profile': 'Cập nhật hồ sơ danh tính',
  'account_block': 'Khóa tài khoản',
  'account_unblock': 'Mở khóa tài khoản',
  'operator_grant': 'Cấp quyền Điều hành viên',
  'operator_revoke': 'Thu hồi quyền Điều hành viên',
  'membership_request': 'Người dùng gửi đăng ký đối tác',
  'membership_grant': 'Cấp trực tiếp tư cách đối tác',
  'membership_approve': 'Phê duyệt tư cách đối tác',
  'membership_reject': 'Từ chối hồ sơ đối tác',
  'membership_revoke': 'Thu hồi tư cách đối tác',
  'pickup_assign': 'Điều phối tài xế thu gom',
  'promo_settings_save': 'Cập nhật cấu hình Sự kiện & Vòng xoay',
};

String adminAuditActionLabel(dynamic raw) {
  final code = '$raw';
  return adminAuditActionLabels[code] ?? code;
}

class AdminAccountsPanel extends StatefulWidget {
  const AdminAccountsPanel({
    super.key,
    required this.session,
    required this.lease,
    this.initialFilter = 'all',
  });

  final CloudAccountSession session;
  final CloudSessionLease lease;
  final String initialFilter;

  @override
  State<AdminAccountsPanel> createState() => _AdminAccountsPanelState();
}

class _AdminAccountsPanelState extends State<AdminAccountsPanel> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _accounts = const [];
  Map<String, dynamic> _summary = const {};
  late String _filter = widget.initialFilter;
  bool _busy = false;
  bool _loaded = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminAccountsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFilter != oldWidget.initialFilter) {
      setState(() => _filter = widget.initialFilter);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int _intVal(dynamic v) => (v as num? ?? 0).toInt();

  List<Map<String, dynamic>> _rows(dynamic raw) => (raw as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  List<String> _strings(dynamic raw) =>
      (raw as List? ?? const []).map((e) => '$e').toList();

  Future<void> _load({bool force = false}) async {
    if ((_busy && !force) || !widget.lease.valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.session.service.adminAccounts('list');
      if (!mounted || !widget.lease.valid) return;
      setState(() {
        _accounts = _rows(res['accounts']);
        _summary = Map<String, dynamic>.from(
          res['summary'] as Map? ?? const {},
        );
        _loaded = true;
      });
    } catch (e) {
      if (mounted && !widget.lease.handleAccessFailure(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa tải được danh sách tài khoản.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<T?> _showProtectedDialog<T>({
    required Widget Function(BuildContext dialog, CloudSessionLease lease)
    builder,
  }) {
    if (!widget.lease.valid) return Future.value(null);
    return showDialog<T>(
      context: context,
      builder: (dialogCtx) => Theme(
        data: AdminStudioTheme.of(dialogCtx),
        child: CloudSessionBoundary(
          session: widget.session,
          operator: true,
          dialog: true,
          builder: builder,
        ),
      ),
    );
  }

  Future<void> _runMutation(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_busy || !widget.lease.valid) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      if (!mounted || !widget.lease.valid) return;
      if (successMessage != null) _notice = successMessage;
      await _load(force: true);
    } catch (e) {
      if (mounted && !widget.lease.handleAccessFailure(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Không thực hiện được thao tác quản trị tài khoản.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _displayName(Map<String, dynamic> a) {
    final name = '${a['full_name'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
    final email = '${a['email'] ?? ''}'.trim();
    if (email.isNotEmpty) return email.split('@').first;
    return 'Chưa cập nhật hồ sơ';
  }

  String _initials(Map<String, dynamic> a) {
    final name = _displayName(a);
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }

  Map<String, dynamic>? _membershipFor(Map<String, dynamic> a, String role) {
    for (final m in _rows(a['memberships'])) {
      if (m['role'] == role) return m;
    }
    return null;
  }

  bool _hasPending(Map<String, dynamic> a) =>
      _rows(a['memberships']).any((m) => m['state'] == 'pending');

  List<Map<String, dynamic>> get _visibleAccounts {
    final q = _search.text.trim().toLowerCase();
    return _accounts.where((a) {
      final approved = _strings(a['approved_roles']);
      final matchesFilter = switch (_filter) {
        'pending' => _hasPending(a),
        'operator' => a['is_operator'] == true,
        'driver' => approved.contains('driver'),
        'merchant' => approved.contains('merchant'),
        'incomplete' => a['has_profile'] != true,
        'blocked' => a['blocked'] == true,
        _ => true,
      };
      if (!matchesFilter) return false;
      if (q.isEmpty) return true;
      return [
        a['full_name'],
        a['email'],
        a['phone'],
        a['user_id'],
        a['citizen_id'],
        a['birth_date'],
        formatIsoBirthDate(a['birth_date'] as String?),
      ].any((v) => '${v ?? ''}'.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _copyUuid(String uid) async {
    await Clipboard.setData(ClipboardData(text: uid));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã sao chép mã định danh UUID.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _editProfile(Map<String, dynamic> account) async {
    final uid = '${account['user_id']}';
    final result = await _showProtectedDialog<Map<String, String>>(
      builder: (_, _) => _EditAccountProfileDialog(account: account),
    );
    if (result == null || !mounted || !widget.lease.valid) return;
    final hadBirth = '${account['birth_date'] ?? ''}'.trim().isNotEmpty;
    final hadCitizen = '${account['citizen_id'] ?? ''}'.trim().isNotEmpty;
    final nextBirth = result['birth_date'] ?? '';
    final nextCitizen = result['citizen_id'] ?? '';
    await _runMutation(
      () async {
        await widget.session.service.adminAccounts('update_profile', {
          'user_id': uid,
          'full_name': result['full_name'],
          'phone': result['phone'],
          if (nextBirth.isNotEmpty || hadBirth) 'birth_date': nextBirth,
          if (nextCitizen.isNotEmpty || hadCitizen) 'citizen_id': nextCitizen,
          'reason': result['reason'] ?? '',
        });
        if (uid == widget.session.service.userId) {
          await widget.session.refresh();
        }
      },
      successMessage: 'Đã cập nhật hồ sơ danh tính.',
    );
  }

  Future<void> _decideMembership(
    Map<String, dynamic> account,
    String role,
    String decision,
  ) async {
    final uid = '${account['user_id']}';
    final roleLabel = partnerRoleNames[role] ?? role;
    final current = _membershipFor(account, role);
    final version = _intVal(current?['version']);
    final actionVerb = switch (decision) {
      'grant' => 'Cấp quyền',
      'approve' => 'Duyệt',
      'reject' => 'Từ chối',
      _ => 'Thu hồi',
    };
    final reasonRequired = decision == 'reject' || decision == 'revoke';
    final reason = await _showProtectedDialog<String>(
      builder: (_, _) => CloudMembershipDecisionDialog(
        title: '$actionVerb $roleLabel',
        accountName:
            '${_displayName(account)}${'${account['email'] ?? ''}'.isNotEmpty ? ' · ${account['email']}' : ''}',
        reasonRequired: reasonRequired,
      ),
    );
    if (reason == null || !mounted || !widget.lease.valid) return;
    await _runMutation(
      () async {
        await widget.session.service.request(
          'accounts/$uid/memberships/$role',
          body: {
            'decision': decision,
            'version': decision == 'grant' && current == null ? 0 : version,
            'reason': reason,
          },
        );
        if (uid == widget.session.service.userId) {
          await widget.session.refresh();
        }
      },
      successMessage: 'Đã cập nhật quyền đối tác $roleLabel.',
    );
  }

  Future<void> _toggleBlocked(Map<String, dynamic> account) async {
    final uid = '${account['user_id']}';
    final nextBlocked = account['blocked'] != true;
    final reason = await _showProtectedDialog<String>(
      builder: (_, _) => _BlockAccountDialog(
        account: account,
        displayName: _displayName(account),
        block: nextBlocked,
      ),
    );
    if (reason == null || !mounted || !widget.lease.valid) return;
    await _runMutation(
      () async {
        await widget.session.service.adminAccounts('set_blocked', {
          'user_id': uid,
          'blocked': nextBlocked,
          'reason': reason,
        });
      },
      successMessage: nextBlocked
          ? 'Đã khóa tài khoản.'
          : 'Đã mở khóa tài khoản.',
    );
  }

  Future<void> _toggleOperator(Map<String, dynamic> account) async {
    final uid = '${account['user_id']}';
    final nextOperator = account['is_operator'] != true;
    final reason = await _showProtectedDialog<String>(
      builder: (_, _) => CloudMembershipDecisionDialog(
        title: nextOperator
            ? 'Cấp quyền Điều hành viên'
            : 'Thu hồi quyền Điều hành viên',
        accountName:
            '${_displayName(account)}${'${account['email'] ?? ''}'.isNotEmpty ? ' · ${account['email']}' : ''}',
        reasonRequired: true,
      ),
    );
    if (reason == null || !mounted || !widget.lease.valid) return;
    await _runMutation(
      () async {
        await widget.session.service.adminAccounts('set_operator', {
          'user_id': uid,
          'operator': nextOperator,
          'reason': reason,
        });
      },
      successMessage: nextOperator
          ? 'Đã cấp quyền Điều hành viên.'
          : 'Đã thu hồi quyền Điều hành viên.',
    );
  }

  Future<void> _openDetail(Map<String, dynamic> account) async {
    final changed = await _showProtectedDialog<bool>(
      builder: (_, lease) => _AccountGovernanceDetailDialog(
        session: widget.session,
        lease: lease,
        initialAccount: account,
      ),
    );
    if (changed == true && mounted && widget.lease.valid) {
      await _load(force: true);
    }
  }

  Widget _kpiTile({
    required IconData icon,
    required Color accent,
    required Color tint,
    required String label,
    required String value,
    required String detail,
    required String filterKey,
    bool compact = false,
  }) {
    final p = AdminStudioPalette.of(context);
    final selected = _filter == filterKey;
    return AdminNeoBox(
      backgroundColor: selected ? p.acidSoft : p.surface,
      borderColor: selected ? p.violet : p.line,
      borderWidth: selected ? 1.8 : 1.0,
      shadowColor: selected ? p.violet : p.ink,
      shadowOffset: selected ? const Offset(4, 4) : const Offset(3, 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _filter = filterKey),
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: compact ? 30 : 34,
                    height: compact ? 30 : 34,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: p.line,
                      ),
                    ),
                    child: Icon(icon, size: compact ? 16 : 18, color: accent),
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
              SizedBox(height: compact ? 8 : 10),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 18 : 23,
                  fontWeight: FontWeight.w900,
                  color: p.ink,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 2),
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
        ),
      ),
    );
  }

  Widget _badge({
    required String label,
    required Color fg,
    required Color bg,
    IconData? icon,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: fg.withValues(alpha: 0.22)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _metricPill(IconData icon, String text, {Color? accent}) {
    final p = AdminStudioPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: p.surfaceSubtle,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent ?? p.muted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accent ?? p.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _partnerRoleBlock(Map<String, dynamic> account, String role) {
    final p = AdminStudioPalette.of(context);
    final roleLabel = partnerRoleNames[role] ?? role;
    final membership = _membershipFor(account, role);
    final state = membership?['state'] as String?;
    final hasProfile = account['has_profile'] == true;
    final blocked = account['blocked'] == true;
    final reason = '${membership?['reason'] ?? ''}'.trim();

    final (statusText, fg, bg) = switch (state) {
      'active' => (
        '$roleLabel · Đã duyệt',
        p.onAccentInk,
        p.acid,
      ),
      'pending' => (
        '$roleLabel · Chờ duyệt',
        p.onAccentInk,
        p.gold,
      ),
      'rejected' => (
        '$roleLabel · Chưa được duyệt',
        p.danger,
        p.dangerSoft,
      ),
      'revoked' => (
        '$roleLabel · Đã thu hồi',
        p.muted,
        p.paperWarm,
      ),
      _ => (
        '$roleLabel · Chưa đăng ký',
        p.muted,
        p.surface,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: state == 'pending' ? p.goldSoft : p.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: state == 'pending'
              ? p.goldInk.withValues(alpha: 0.35)
              : p.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _badge(
                label: statusText,
                fg: fg,
                bg: bg,
                icon: role == 'driver'
                    ? Icons.two_wheeler_rounded
                    : Icons.storefront_outlined,
              ),
              if (state == 'pending') ...[
                FilledButton.tonalIcon(
                  onPressed: _busy || blocked || !hasProfile
                      ? null
                      : () => _decideMembership(account, role, 'approve'),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.acidSoft,
                    foregroundColor: p.acidInk,
                    side: BorderSide(
                      color: p.acidInk.withValues(alpha: 0.35),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: Text('Duyệt $roleLabel'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || blocked || !hasProfile
                      ? null
                      : () => _decideMembership(account, role, 'reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.danger,
                    side: BorderSide(
                      color: p.danger,
                      width: 1.3,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: Text('Từ chối $roleLabel'),
                ),
              ] else if (state == 'active')
                OutlinedButton.icon(
                  onPressed: _busy || blocked
                      ? null
                      : () => _decideMembership(account, role, 'revoke'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.danger,
                    side: BorderSide(
                      color: p.danger,
                      width: 1.3,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.person_remove_outlined, size: 16),
                  label: Text('Thu hồi $roleLabel'),
                )
              else if (hasProfile && !blocked)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _decideMembership(account, role, 'grant'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.violet,
                    side: BorderSide(
                      color: p.violet,
                      width: 1.3,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.verified_outlined, size: 16),
                  label: Text('Cấp quyền $roleLabel'),
                ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Ghi chú xét duyệt: $reason',
              style: TextStyle(
                fontSize: 12,
                color: p.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _accountCard(Map<String, dynamic> a) {
    final p = AdminStudioPalette.of(context);
    final uid = '${a['user_id']}';
    final shortUid = uid.length > 12 ? '${uid.substring(0, 8)}…' : uid;
    final isSelf = uid == widget.session.service.userId;
    final hasProfile = a['has_profile'] == true;
    final blocked = a['blocked'] == true;
    final isOp = a['is_operator'] == true;
    final email = '${a['email'] ?? ''}'.trim();
    final emailConfirmed = a['email_confirmed'] == true;
    final phone = '${a['phone'] ?? ''}'.trim();
    final birthDate = formatIsoBirthDate(a['birth_date'] as String?);
    final citizenMasked = maskCitizenId(a['citizen_id'] as String?);
    final kycVerified = a['identity_verified'] == true;
    final providers = _strings(a['auth_providers']);
    final lastSignIn = cloudDate(a['last_sign_in_at']);
    final createdAt = cloudDate(a['created_at'] ?? a['updated_at']);
    final ordersCount = _intVal(a['orders_count']);
    final driverOrders = _intVal(a['driver_orders_count']);
    final activeTrips = _intVal(a['active_driver_trips']);
    final shopsCount = _intVal(a['shops_count']);
    final coins = _intVal(a['coin_balance']);

    final avatarBg = blocked
        ? p.dangerSoft
        : isOp
        ? p.acid
        : p.violetSoft;
    final avatarFg = blocked
        ? p.danger
        : isOp
        ? p.onAccentInk
        : p.violetInk;

    return AdminNeoBox(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      shadowColor: blocked
          ? p.pink
          : _hasPending(a)
          ? p.violet
          : p.ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: avatarBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.line),
                ),
                child: Text(
                  _initials(a),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: avatarFg,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _displayName(a),
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color: p.ink,
                          ),
                        ),
                        if (isSelf)
                          _badge(
                            label: 'Phiên hiện tại',
                            fg: Colors.white,
                            bg: p.violet,
                          ),
                        if (isOp)
                          _badge(
                            label: 'Operator',
                            fg: p.onAccentInk,
                            bg: p.acid,
                            icon: Icons.shield_outlined,
                          ),
                        if (blocked)
                          _badge(
                            label: 'Đang khóa',
                            fg: p.danger,
                            bg: p.dangerSoft,
                            icon: Icons.lock_outline_rounded,
                          )
                        else if (!hasProfile)
                          _badge(
                            label: 'Chưa hoàn tất hồ sơ',
                            fg: p.onAccentInk,
                            bg: p.gold,
                            icon: Icons.warning_amber_rounded,
                          )
                        else
                          _badge(
                            label: 'Đang hoạt động',
                            fg: p.acidInk,
                            bg: p.acidSoft,
                          ),
                        if (kycVerified)
                          _badge(
                            label: 'Đã định danh CCCD',
                            fg: p.acidInk,
                            bg: p.acidSoft,
                            icon: Icons.verified_user_outlined,
                          ),
                        for (final prov in providers)
                          _badge(
                            label: prov == 'google'
                                ? 'Google OAuth'
                                : prov == 'email'
                                ? 'Email / Mật khẩu'
                                : prov,
                            fg: p.ink,
                            bg: p.paper,
                            icon: prov == 'google'
                                ? Icons.public_rounded
                                : Icons.alternate_email_rounded,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (email.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.mail_outline_rounded,
                                size: 14,
                                color: p.muted,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: p.ink,
                                  ),
                                ),
                              ),
                              if (emailConfirmed) ...[
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: 'Email đã xác thực',
                                  child: Icon(
                                    Icons.verified_rounded,
                                    size: 14,
                                    color: p.violet,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.phone_outlined,
                              size: 14,
                              color: p.muted,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                phone.isNotEmpty ? phone : 'Chưa cập nhật SĐT',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: phone.isNotEmpty
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: phone.isNotEmpty ? p.ink : p.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (birthDate.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cake_outlined,
                                size: 14,
                                color: p.muted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                birthDate,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: p.ink,
                                ),
                              ),
                            ],
                          ),
                        if (citizenMasked.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.badge_outlined,
                                size: 14,
                                color: p.muted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                citizenMasked,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: p.ink,
                                ),
                              ),
                            ],
                          ),
                        InkWell(
                          onTap: () => _copyUuid(uid),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fingerprint_rounded,
                                  size: 14,
                                  color: p.muted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  shortUid,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    color: p.muted,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Icon(
                                  Icons.copy_rounded,
                                  size: 12,
                                  color: p.muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metricPill(
                Icons.local_shipping_outlined,
                'Đơn đặt: $ordersCount',
              ),
              _metricPill(
                Icons.two_wheeler_outlined,
                activeTrips > 0
                    ? 'Chuyến giao: $driverOrders · $activeTrips đang chạy'
                    : 'Chuyến giao: $driverOrders',
                accent: activeTrips > 0 ? p.violet : null,
              ),
              _metricPill(Icons.storefront_outlined, 'Gian hàng: $shopsCount'),
              _metricPill(Icons.monetization_on_outlined, 'Ví Xu: $coins Xu'),
              if (lastSignIn.isNotEmpty)
                _metricPill(Icons.login_rounded, 'Đăng nhập: $lastSignIn')
              else if (createdAt.isNotEmpty)
                _metricPill(Icons.calendar_today_outlined, 'Tạo: $createdAt'),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth >= 680) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _partnerRoleBlock(a, 'driver')),
                    const SizedBox(width: 10),
                    Expanded(child: _partnerRoleBlock(a, 'merchant')),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _partnerRoleBlock(a, 'driver'),
                  const SizedBox(height: 8),
                  _partnerRoleBlock(a, 'merchant'),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _openDetail(a),
                    icon: const Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 17,
                    ),
                    label: const Text('Chi tiết & Phân quyền'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _editProfile(a),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: Text(hasProfile ? 'Sửa hồ sơ' : 'Hoàn tất hồ sơ'),
                  ),
                  if (!isSelf || !isOp)
                    OutlinedButton.icon(
                      onPressed: _busy || (blocked && !isOp)
                          ? null
                          : () => _toggleOperator(a),
                      icon: Icon(
                        isOp
                            ? Icons.remove_moderator_outlined
                            : Icons.add_moderator_outlined,
                        size: 17,
                      ),
                      label: Text(
                        isOp ? 'Thu hồi Operator' : 'Cấp quyền Operator',
                      ),
                    ),
                ],
              ),
              if (hasProfile)
                Tooltip(
                  message: isSelf && !blocked
                      ? 'Không thể tự khóa tài khoản quản trị đang đăng nhập'
                      : '',
                  child: OutlinedButton.icon(
                    onPressed: _busy || (isSelf && !blocked)
                        ? null
                        : () => _toggleBlocked(a),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: blocked ? p.acidInk : p.danger,
                      side: BorderSide(
                        color: blocked ? p.acidInk : p.danger,
                        width: 1.4,
                      ),
                    ),
                    icon: Icon(
                      blocked
                          ? Icons.lock_open_rounded
                          : Icons.lock_outline_rounded,
                      size: 17,
                    ),
                    label: Text(
                      blocked ? 'Mở khóa tài khoản' : 'Khóa tài khoản',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _loaded
        ? (_summary.containsKey('total_accounts')
              ? _intVal(_summary['total_accounts'])
              : _accounts.length)
        : 0;
    final completed = _loaded
        ? (_summary.containsKey('completed_profiles')
              ? _intVal(_summary['completed_profiles'])
              : _accounts.where((a) => a['has_profile'] == true).length)
        : 0;
    final incomplete = _loaded
        ? (_summary.containsKey('incomplete_profiles')
              ? _intVal(_summary['incomplete_profiles'])
              : _accounts.where((a) => a['has_profile'] != true).length)
        : 0;
    final operators = _loaded
        ? (_summary.containsKey('operators')
              ? _intVal(_summary['operators'])
              : _accounts.where((a) => a['is_operator'] == true).length)
        : 0;
    final drivers = _loaded
        ? (_summary.containsKey('active_drivers')
              ? _intVal(_summary['active_drivers'])
              : _accounts
                    .where(
                      (a) => _strings(a['approved_roles']).contains('driver'),
                    )
                    .length)
        : 0;
    final merchants = _loaded
        ? (_summary.containsKey('active_merchants')
              ? _intVal(_summary['active_merchants'])
              : _accounts
                    .where(
                      (a) => _strings(a['approved_roles']).contains('merchant'),
                    )
                    .length)
        : 0;
    final pendingCount = _loaded
        ? (_summary.containsKey('pending_memberships')
              ? _intVal(_summary['pending_memberships'])
              : _accounts.where(_hasPending).length)
        : 0;
    final blockedCount = _loaded
        ? (_summary.containsKey('blocked_accounts')
              ? _intVal(_summary['blocked_accounts'])
              : _accounts.where((a) => a['blocked'] == true).length)
        : 0;

    final visible = _visibleAccounts;
    final filterOptions = [
      ('all', 'Tất cả · $total'),
      ('pending', 'Chờ duyệt · $pendingCount'),
      ('operator', 'Quản trị viên · $operators'),
      ('driver', 'Tài xế · $drivers'),
      ('merchant', 'Cửa hàng · $merchants'),
      if (incomplete > 0 || _filter == 'incomplete')
        ('incomplete', 'Chưa hoàn tất hồ sơ · $incomplete'),
      ('blocked', 'Đang khóa · $blockedCount'),
    ];

    final p = AdminStudioPalette.of(context);
    return Theme(
      data: AdminStudioTheme.of(context),
      child: RefreshIndicator(
        onRefresh: () => _load(force: true),
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
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AdminStudioColors.shellLine,
                            ),
                          ),
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final compact = box.maxWidth < 520;
                              return Row(
                                children: [
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Trung tâm Quản trị Danh tính & Phân quyền',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Đồng bộ trực tiếp từ hồ sơ tài khoản, phân quyền đối tác và nhật ký kiểm toán.',
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
                                      tooltip: 'Làm mới danh sách tài khoản',
                                      style: IconButton.styleFrom(
                                        backgroundColor:
                                            AdminStudioColors.shellElevated,
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(
                                          color: AdminStudioColors.shellLine,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                      onPressed: _busy
                                          ? null
                                          : () => _load(force: true),
                                      icon: const Icon(Icons.refresh_rounded),
                                    )
                                  else
                                    FilledButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () => _load(force: true),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AdminStudioColors.acid,
                                        foregroundColor: p.onAccentInk,
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
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: p.dangerSoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: p.danger.withValues(alpha: 0.45),
                          ),
                        ),
                        child: SelectableText(
                          _error!,
                          style: TextStyle(
                            color: p.danger,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (_notice != null)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: p.acidSoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: p.acidInk.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              color: p.acidInk,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _notice!,
                                style: TextStyle(
                                  color: p.acidInk,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_loaded) ...[
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, c) {
                          final compact = c.maxWidth < 540;
                          final cols = c.maxWidth >= 900 ? 3 : 2;
                          final gap = compact ? 10.0 : 12.0;
                          final width = (c.maxWidth - gap * (cols - 1)) / cols;
                          final tiles = [
                            _kpiTile(
                              compact: compact,
                              icon: Icons.people_alt_outlined,
                              accent: p.onAccentInk,
                              tint: p.acid,
                              label: 'Tổng tài khoản Auth',
                              value: '$total',
                              detail:
                                  'Đủ hồ sơ: $completed · Chưa hoàn tất: $incomplete',
                              filterKey: 'all',
                            ),
                            _kpiTile(
                              compact: compact,
                              icon: Icons.shield_outlined,
                              accent: Colors.white,
                              tint: p.violet,
                              label: 'Điều hành viên',
                              value: '$operators',
                              detail: 'Quyền quản trị Operator toàn hệ thống',
                              filterKey: 'operator',
                            ),
                            _kpiTile(
                              compact: compact,
                              icon: pendingCount > 0
                                  ? Icons.pending_actions_rounded
                                  : Icons.task_alt_rounded,
                              accent: pendingCount > 0
                                  ? p.onAccentInk
                                  : p.acidInk,
                              tint: pendingCount > 0 ? p.gold : p.acidSoft,
                              label: 'Hồ sơ đối tác chờ duyệt',
                              value: '$pendingCount',
                              detail: 'Yêu cầu Tài xế / Cửa hàng mới',
                              filterKey: 'pending',
                            ),
                            _kpiTile(
                              compact: compact,
                              icon: Icons.two_wheeler_rounded,
                              accent: p.violet,
                              tint: p.violetSoft,
                              label: 'Tài xế đã phê duyệt',
                              value: '$drivers',
                              detail: 'Đủ điều kiện nhận chuyến',
                              filterKey: 'driver',
                            ),
                            _kpiTile(
                              compact: compact,
                              icon: Icons.storefront_outlined,
                              accent: p.pinkInk,
                              tint: p.pinkSoft,
                              label: 'Đối tác Cửa hàng',
                              value: '$merchants',
                              detail: 'Được tạo & vận hành gian hàng',
                              filterKey: 'merchant',
                            ),
                            _kpiTile(
                              compact: compact,
                              icon: Icons.lock_outline_rounded,
                              accent: blockedCount > 0 ? p.danger : p.muted,
                              tint: blockedCount > 0
                                  ? p.dangerSoft
                                  : p.paperWarm,
                              label: 'Tài khoản đang khóa',
                              value: '$blockedCount',
                              detail: 'Tạm đình chỉ giao dịch',
                              filterKey: 'blocked',
                            ),
                          ];
                          return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              for (final t in tiles)
                                SizedBox(width: width, child: t),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      AdminNeoBox(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _search,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText:
                                    'Tìm theo họ tên, email, số điện thoại hoặc UUID',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Xóa tìm kiếm',
                                        onPressed: () =>
                                            setState(_search.clear),
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final opt in filterOptions)
                                  ChoiceChip(
                                    label: Text(opt.$2),
                                    selected: _filter == opt.$1,
                                    selectedColor: p.acid,
                                    backgroundColor: p.surfaceSubtle,
                                    labelStyle: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: _filter == opt.$1
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: _filter == opt.$1
                                          ? p.onAccentInk
                                          : p.ink,
                                    ),
                                    onSelected: (_) =>
                                        setState(() => _filter = opt.$1),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Hiển thị ${visible.length} / ${_accounts.length} tài khoản đã tải',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: p.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_accounts.isEmpty && !_busy)
                        AdminNeoBox(
                          padding: const EdgeInsets.all(28),
                          child: Center(
                            child: Text(
                              'Chưa có tài khoản nào trên hệ thống.',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: p.muted,
                              ),
                            ),
                          ),
                        )
                      else if (visible.isEmpty && !_busy)
                        AdminNeoBox(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            children: [
                              Icon(
                                Icons.person_search_outlined,
                                size: 36,
                                color: p.muted,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Không tìm thấy tài khoản phù hợp bộ lọc hiện tại.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: p.ink,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: () => setState(() {
                                  _filter = 'all';
                                  _search.clear();
                                }),
                                child: const Text('Đặt lại bộ lọc'),
                              ),
                            ],
                          ),
                        )
                      else
                        for (final account in visible) _accountCard(account),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditAccountProfileDialog extends StatefulWidget {
  const _EditAccountProfileDialog({required this.account});

  final Map<String, dynamic> account;

  @override
  State<_EditAccountProfileDialog> createState() =>
      _EditAccountProfileDialogState();
}

class _EditAccountProfileDialogState extends State<_EditAccountProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: '${widget.account['full_name'] ?? ''}',
  );
  late final _phone = TextEditingController(
    text: '${widget.account['phone'] ?? ''}',
  );
  late final _birthDate = TextEditingController(
    text: formatIsoBirthDate(widget.account['birth_date'] as String?),
  );
  late final _citizenId = TextEditingController(
    text: '${widget.account['citizen_id'] ?? ''}',
  );
  final _reason = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _birthDate.dispose();
    _citizenId.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime initial = DateTime(2000, 1, 1);
    final currentIso = parseBirthDateToIso(_birthDate.text);
    if (currentIso != null && currentIso.isNotEmpty) {
      final parts = currentIso.split('-').map(int.parse).toList();
      initial = DateTime(parts[0], parts[1], parts[2]);
    }
    if (initial.isAfter(today)) initial = today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900, 1, 1),
      lastDate: today,
      helpText: 'Chọn ngày tháng năm sinh',
      cancelText: 'Hủy',
      confirmText: 'Chọn',
    );
    if (picked == null || !mounted) return;
    final dd = picked.day.toString().padLeft(2, '0');
    final mm = picked.month.toString().padLeft(2, '0');
    setState(() {
      _birthDate.text = '$dd/$mm/${picked.year}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AdminStudioPalette.of(context);
    final hasProfile = widget.account['has_profile'] == true;
    final email = '${widget.account['email'] ?? ''}'.trim();
    return AlertDialog(
      title: Text(
        hasProfile ? 'Chỉnh sửa hồ sơ tài khoản' : 'Hoàn tất hồ sơ',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (email.isNotEmpty) ...[
                  Text(
                    email,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: p.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _name,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Họ và tên'),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty || s.length > 120) {
                      return 'Nhập họ và tên từ 1 đến 120 ký tự.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại',
                    hintText: '0901234567',
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (!RegExp(r'^0[35789][0-9]{8}$').hasMatch(s)) {
                      return 'Nhập đúng số điện thoại di động Việt Nam 10 số.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _birthDate,
                  maxLength: 10,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [BirthDateSlashFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Ngày tháng năm sinh',
                    hintText: 'dd/MM/yyyy',
                    counterText: '',
                    suffixIcon: IconButton(
                      tooltip: 'Chọn ngày sinh',
                      icon: const Icon(Icons.calendar_month_outlined),
                      onPressed: _pickBirthDate,
                    ),
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return null;
                    return parseBirthDateToIso(s) == null
                        ? 'Ngày sinh không hợp lệ, nhập dd/MM/yyyy.'
                        : null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _citizenId,
                  maxLength: 12,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Số CCCD định danh',
                    hintText: '12 chữ số',
                    counterText: '',
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return null;
                    return RegExp(r'^\d{12}$').hasMatch(s)
                        ? null
                        : 'Số CCCD phải gồm đúng 12 chữ số.';
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _reason,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú quản trị',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Quay lại'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'full_name': _name.text.trim(),
                'phone': _phone.text.trim(),
                'birth_date': parseBirthDateToIso(_birthDate.text) ?? '',
                'citizen_id': _citizenId.text.trim(),
                'reason': _reason.text.trim(),
              });
            }
          },
          child: const Text('Lưu hồ sơ'),
        ),
      ],
    );
  }
}

class _BlockAccountDialog extends StatefulWidget {
  const _BlockAccountDialog({
    required this.account,
    required this.displayName,
    required this.block,
  });

  final Map<String, dynamic> account;
  final String displayName;
  final bool block;

  @override
  State<_BlockAccountDialog> createState() => _BlockAccountDialogState();
}

class _BlockAccountDialogState extends State<_BlockAccountDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AdminStudioPalette.of(context);
    final email = '${widget.account['email'] ?? ''}'.trim();
    final phone = '${widget.account['phone'] ?? ''}'.trim();
    return AlertDialog(
      title: Text(
        widget.block ? 'Khóa tài khoản' : 'Mở khóa tài khoản',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.displayName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (email.isNotEmpty || phone.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    [if (email.isNotEmpty) email, if (phone.isNotEmpty) phone]
                        .join(' · '),
                    style: TextStyle(
                      fontSize: 13,
                      color: p.muted,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                widget.block
                    ? 'Tài khoản bị khóa sẽ không thể đặt đơn, vận hành gian hàng hay nhận chuyến giao.'
                    : 'Mở khóa để khôi phục quyền giao dịch và các tư cách đối tác đang hiệu lực.',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú kiểm toán',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Quay lại'),
        ),
        FilledButton(
          style: widget.block
              ? FilledButton.styleFrom(
                  backgroundColor: p.danger,
                  foregroundColor: Colors.white,
                )
              : null,
          onPressed: () => Navigator.pop(context, _reason.text.trim()),
          child: const Text('Xác nhận'),
        ),
      ],
    );
  }
}

class _AccountGovernanceDetailDialog extends StatefulWidget {
  const _AccountGovernanceDetailDialog({
    required this.session,
    required this.lease,
    required this.initialAccount,
  });

  final CloudAccountSession session;
  final CloudSessionLease lease;
  final Map<String, dynamic> initialAccount;

  @override
  State<_AccountGovernanceDetailDialog> createState() =>
      _AccountGovernanceDetailDialogState();
}

class _AccountGovernanceDetailDialogState
    extends State<_AccountGovernanceDetailDialog> {
  late Map<String, dynamic> _account = widget.initialAccount;
  List<Map<String, dynamic>> _shops = const [];
  List<Map<String, dynamic>> _audit = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  List<Map<String, dynamic>> _rows(dynamic raw) => (raw as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  Future<void> _loadDetail() async {
    if (!widget.lease.valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.session.service.adminAccounts('detail', {
        'user_id': '${_account['user_id']}',
      });
      if (!mounted || !widget.lease.valid) return;
      setState(() {
        if (res['account'] is Map) {
          _account = Map<String, dynamic>.from(res['account'] as Map);
        }
        _shops = _rows(res['shops']);
        _audit = _rows(res['audit']);
      });
    } catch (e) {
      if (mounted && !widget.lease.handleAccessFailure(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa tải được chi tiết kiểm toán tài khoản.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: LayoutBuilder(
      builder: (context, c) {
        final p = AdminStudioPalette.of(context);
        final display = value.isEmpty ? '—' : value;
        if (c.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: p.muted,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                display,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: p.muted,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                display,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = AdminStudioPalette.of(context);
    final providers = (_account['auth_providers'] as List? ?? const [])
        .map((e) => '$e')
        .join(', ');
    final approved = (_account['approved_roles'] as List? ?? const [])
        .map((r) => partnerRoleNames['$r'] ?? '$r')
        .toList();
    return AlertDialog(
      title: Text(
        'Hồ sơ & Kiểm toán: ${'${_account['full_name'] ?? ''}'.trim().isNotEmpty ? _account['full_name'] : (_account['email'] ?? _account['user_id'])}',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: p.danger,
                      fontSize: 13,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: p.surfaceSubtle,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: p.line,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _infoRow('UUID định danh', '${_account['user_id']}'),
                    _infoRow(
                      'Email xác thực',
                      '${_account['email'] ?? ''}${_account['email_confirmed'] == true ? ' · Đã xác minh' : ''}',
                    ),
                    _infoRow(
                      'Số điện thoại',
                      '${_account['phone'] ?? ''}'.isNotEmpty
                          ? '${_account['phone']}'
                          : 'Chưa cập nhật',
                    ),
                    _infoRow(
                      'Ngày tháng năm sinh',
                      formatIsoBirthDate(
                        _account['birth_date'] as String?,
                      ).isNotEmpty
                          ? formatIsoBirthDate(
                              _account['birth_date'] as String?,
                            )
                          : 'Chưa cập nhật',
                    ),
                    _infoRow(
                      'Số CCCD định danh',
                      '${_account['citizen_id'] ?? ''}'.isNotEmpty
                          ? '${_account['citizen_id']} · Đã định danh CCCD'
                          : 'Chưa định danh',
                    ),
                    _infoRow('Nhà cung cấp Auth', providers),
                    _infoRow(
                      'Quyền hệ thống',
                      [
                        if (_account['has_profile'] == true) 'Khách hàng',
                        ...approved,
                        if (_account['is_operator'] == true) 'Operator',
                      ].join(' · '),
                    ),
                    _infoRow(
                      'Ngày tạo Auth',
                      cloudDate(_account['created_at']),
                    ),
                    _infoRow(
                      'Đăng nhập gần nhất',
                      cloudDate(_account['last_sign_in_at']),
                    ),
                    _infoRow(
                      'Cập nhật hồ sơ',
                      cloudDate(_account['updated_at']),
                    ),
                  ],
                ),
              ),
              if (_shops.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Gian hàng sở hữu',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 8),
                for (final s in _shops)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.surfaceSubtle,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: p.line,
                      ),
                    ),
                    child: Text(
                      '${s['name']} · ${s['status'] == 'active' ? 'Đang hoạt động' : s['status'] == 'pending' ? 'Chờ duyệt' : 'Tạm khóa'}${s['paused'] == true ? ' (Tạm nghỉ)' : ''}\n${s['address'] ?? ''}',
                      style: const TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Text(
                'Nhật ký kiểm toán tài khoản này',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 8),
              if (_audit.isEmpty && !_busy)
                Text(
                  'Chưa có bản ghi kiểm toán nào cho tài khoản này.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: p.muted,
                  ),
                ),
              for (final e in _audit)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.surfaceSubtle,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: p.line,
                    ),
                  ),
                  child: Builder(
                    builder: (_) {
                      final after = e['after_value'] as Map?;
                      final reason = '${after?['reason'] ?? ''}'.trim();
                      final actor = '${e['actor_email'] ?? ''}'.trim().isNotEmpty
                          ? '${e['actor_email']}'
                          : '${e['actor_id']}';
                      return SelectableText(
                        '${adminAuditActionLabel(e['action'])} · ${e['action']}\n'
                        '${cloudDate(e['created_at'])} · Thực hiện bởi: $actor'
                        '${reason.isNotEmpty ? '\nGhi chú: $reason' : ''}',
                        style: const TextStyle(fontSize: 12, height: 1.45),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}
