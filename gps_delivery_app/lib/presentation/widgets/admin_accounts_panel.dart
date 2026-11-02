import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import 'cloud_membership_decision_dialog.dart';
import 'cloud_membership_panel.dart';
import 'cloud_order_labels.dart';
import 'cloud_session_boundary.dart';

const _kDark = Color(0xFF081C18);
const _kDarkActive = Color(0xFF15443A);
const _kPrimary = Color(0xFF087F5B);
const _kBorder = Color(0xFFE2E8F0);
const _kText = Color(0xFF0F172A);
const _kMuted = Color(0xFF64748B);
const _kDanger = Color(0xFFB42318);

const adminAuditActionLabels = {
  'pricing': 'Cập nhật bảng giá cước',
  'account_role': 'Cập nhật vai trò / trạng thái khóa',
  'account_profile': 'Cập nhật hồ sơ danh tính',
  'account_block': 'Khóa tài khoản Cloud',
  'account_unblock': 'Mở khóa tài khoản Cloud',
  'operator_grant': 'Cấp quyền Điều hành viên (Operator)',
  'operator_revoke': 'Thu hồi quyền Điều hành viên (Operator)',
  'membership_request': 'Người dùng gửi đăng ký đối tác',
  'membership_grant': 'Cấp trực tiếp tư cách đối tác',
  'membership_approve': 'Phê duyệt tư cách đối tác',
  'membership_reject': 'Từ chối hồ sơ đối tác',
  'membership_revoke': 'Thu hồi tư cách đối tác',
  'pickup_assign': 'Điều phối tài xế thu gom',
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
              : 'Chưa tải được danh sách tài khoản Cloud.',
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
      builder: (_) => CloudSessionBoundary(
        session: widget.session,
        operator: true,
        dialog: true,
        builder: builder,
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
    await _runMutation(
      () async {
        await widget.session.service.adminAccounts('update_profile', {
          'user_id': uid,
          'full_name': result['full_name'],
          'phone': result['phone'],
          'reason': result['reason'] ?? '',
        });
        if (uid == widget.session.service.userId) {
          await widget.session.refresh();
        }
      },
      successMessage: 'Đã cập nhật hồ sơ danh tính Cloud.',
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
          ? 'Đã khóa tài khoản Cloud.'
          : 'Đã mở khóa tài khoản Cloud.',
    );
  }

  Future<void> _toggleOperator(Map<String, dynamic> account) async {
    final uid = '${account['user_id']}';
    final nextOperator = account['is_operator'] != true;
    final reason = await _showProtectedDialog<String>(
      builder: (_, _) => CloudMembershipDecisionDialog(
        title: nextOperator
            ? 'Cấp quyền Điều hành viên (Operator)'
            : 'Thu hồi quyền Điều hành viên (Operator)',
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
          ? 'Đã cấp quyền Điều hành viên (Operator).'
          : 'Đã thu hồi quyền Điều hành viên (Operator).',
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
    final selected = _filter == filterKey;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(compact ? 14 : 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        onTap: () => setState(() => _filter = filterKey),
        child: Container(
          padding: EdgeInsets.all(compact ? 12 : 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 14 : 16),
            border: Border.all(
              color: selected ? accent : _kBorder,
              width: selected ? 1.6 : 1,
            ),
          ),
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
                      borderRadius: BorderRadius.circular(compact ? 8 : 10),
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
                        fontWeight: FontWeight.w600,
                        color: _kMuted,
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
                  fontSize: compact ? 18 : 22,
                  fontWeight: FontWeight.w800,
                  color: _kText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: compact ? 11 : 12, color: _kMuted),
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
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _metricPill(IconData icon, String text, {Color? accent}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _kBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: accent ?? _kMuted),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accent ?? const Color(0xFF334155),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _partnerRoleBlock(Map<String, dynamic> account, String role) {
    final roleLabel = partnerRoleNames[role] ?? role;
    final membership = _membershipFor(account, role);
    final state = membership?['state'] as String?;
    final hasProfile = account['has_profile'] == true;
    final blocked = account['blocked'] == true;
    final reason = '${membership?['reason'] ?? ''}'.trim();

    final (statusText, fg, bg) = switch (state) {
      'active' => (
        '$roleLabel · Đã duyệt',
        _kPrimary,
        const Color(0xFFE6FCF5),
      ),
      'pending' => (
        '$roleLabel · Chờ duyệt',
        const Color(0xFFD9480F),
        const Color(0xFFFFF4E6),
      ),
      'rejected' => (
        '$roleLabel · Chưa được duyệt',
        _kDanger,
        const Color(0xFFFEF3F2),
      ),
      'revoked' => (
        '$roleLabel · Đã thu hồi',
        const Color(0xFF475569),
        const Color(0xFFF1F5F9),
      ),
      _ => (
        '$roleLabel · Chưa đăng ký',
        _kMuted,
        const Color(0xFFF8FAFC),
      ),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: state == 'pending' ? const Color(0xFFFFD8A8) : _kBorder,
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
                    backgroundColor: const Color(0xFFD3F9D8),
                    foregroundColor: const Color(0xFF087F5B),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: Text('Duyệt $roleLabel'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || blocked || !hasProfile
                      ? null
                      : () => _decideMembership(account, role, 'reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kDanger,
                    side: const BorderSide(color: Color(0xFFFECDCA)),
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
                    foregroundColor: _kDanger,
                    side: const BorderSide(color: Color(0xFFFECDCA)),
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
                    foregroundColor: _kPrimary,
                    side: const BorderSide(color: Color(0xFF96F2D7)),
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
              style: const TextStyle(fontSize: 12, color: _kMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _accountCard(Map<String, dynamic> a) {
    final uid = '${a['user_id']}';
    final shortUid = uid.length > 12 ? '${uid.substring(0, 8)}…' : uid;
    final isSelf = uid == widget.session.service.userId;
    final hasProfile = a['has_profile'] == true;
    final blocked = a['blocked'] == true;
    final isOp = a['is_operator'] == true;
    final email = '${a['email'] ?? ''}'.trim();
    final emailConfirmed = a['email_confirmed'] == true;
    final phone = '${a['phone'] ?? ''}'.trim();
    final providers = _strings(a['auth_providers']);
    final lastSignIn = cloudDate(a['last_sign_in_at']);
    final createdAt = cloudDate(a['created_at'] ?? a['updated_at']);
    final ordersCount = _intVal(a['orders_count']);
    final driverOrders = _intVal(a['driver_orders_count']);
    final activeTrips = _intVal(a['active_driver_trips']);
    final shopsCount = _intVal(a['shops_count']);
    final coins = _intVal(a['coin_balance']);

    final avatarBg = blocked
        ? const Color(0xFFFEF3F2)
        : isOp
        ? const Color(0xFFE6FCF5)
        : const Color(0xFFEDF2FF);
    final avatarFg = blocked
        ? _kDanger
        : isOp
        ? _kPrimary
        : const Color(0xFF364FC7);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: blocked
              ? const Color(0xFFFECDCA)
              : _hasPending(a)
              ? const Color(0xFFFFD8A8)
              : _kBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: _kText,
                            ),
                          ),
                          if (isSelf)
                            _badge(
                              label: 'Phiên hiện tại',
                              fg: const Color(0xFF0B7285),
                              bg: const Color(0xFFE3FAFC),
                            ),
                          if (isOp)
                            _badge(
                              label: 'Operator',
                              fg: _kPrimary,
                              bg: const Color(0xFFE6FCF5),
                              icon: Icons.shield_outlined,
                            ),
                          if (blocked)
                            _badge(
                              label: 'Đang khóa',
                              fg: _kDanger,
                              bg: const Color(0xFFFEF3F2),
                              icon: Icons.lock_outline_rounded,
                            )
                          else if (!hasProfile)
                            _badge(
                              label: 'Chưa hoàn tất hồ sơ',
                              fg: const Color(0xFFD9480F),
                              bg: const Color(0xFFFFF4E6),
                              icon: Icons.warning_amber_rounded,
                            )
                          else
                            _badge(
                              label: 'Đang hoạt động',
                              fg: _kPrimary,
                              bg: const Color(0xFFE6FCF5),
                            ),
                          for (final p in providers)
                            _badge(
                              label: p == 'google'
                                  ? 'Google OAuth'
                                  : p == 'email'
                                  ? 'Email / Mật khẩu'
                                  : p,
                              fg: const Color(0xFF334155),
                              bg: const Color(0xFFF1F5F9),
                              icon: p == 'google'
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
                                const Icon(
                                  Icons.mail_outline_rounded,
                                  size: 14,
                                  color: _kMuted,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                ),
                                if (emailConfirmed) ...[
                                  const SizedBox(width: 4),
                                  const Tooltip(
                                    message: 'Email đã xác thực',
                                    child: Icon(
                                      Icons.verified_rounded,
                                      size: 14,
                                      color: _kPrimary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.phone_outlined,
                                size: 14,
                                color: _kMuted,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  phone.isNotEmpty ? phone : 'Chưa cập nhật SĐT',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: phone.isNotEmpty
                                        ? const Color(0xFF334155)
                                        : _kMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => _copyUuid(uid),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.fingerprint_rounded,
                                    size: 14,
                                    color: _kMuted,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    shortUid,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: _kMuted,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  const Icon(
                                    Icons.copy_rounded,
                                    size: 12,
                                    color: _kMuted,
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
                _metricPill(Icons.local_shipping_outlined, 'Đơn đặt: $ordersCount'),
                _metricPill(
                  Icons.two_wheeler_outlined,
                  activeTrips > 0
                      ? 'Chuyến giao: $driverOrders ($activeTrips đang chạy)'
                      : 'Chuyến giao: $driverOrders',
                  accent: activeTrips > 0 ? const Color(0xFFD9480F) : null,
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
                      icon: const Icon(Icons.admin_panel_settings_outlined, size: 17),
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
                        foregroundColor: blocked ? _kPrimary : _kDanger,
                        side: BorderSide(
                          color: blocked
                              ? const Color(0xFF96F2D7)
                              : const Color(0xFFFECDCA),
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
                    .where((a) => _strings(a['approved_roles']).contains('driver'))
                    .length)
        : 0;
    final merchants = _loaded
        ? (_summary.containsKey('active_merchants')
              ? _intVal(_summary['active_merchants'])
              : _accounts
                    .where((a) => _strings(a['approved_roles']).contains('merchant'))
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
      ('all', 'Tất cả ($total)'),
      ('pending', 'Chờ duyệt ($pendingCount)'),
      ('operator', 'Quản trị viên ($operators)'),
      ('driver', 'Tài xế ($drivers)'),
      ('merchant', 'Cửa hàng ($merchants)'),
      if (incomplete > 0 || _filter == 'incomplete')
        ('incomplete', 'Chưa hoàn tất hồ sơ ($incomplete)'),
      ('blocked', 'Đang khóa ($blockedCount)'),
    ];

    return RefreshIndicator(
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
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_kDark, Color(0xFF0E392F)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final compact = box.maxWidth < 520;
                        return Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Trung tâm Quản trị Danh tính & Phân quyền Cloud',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Đồng bộ trực tiếp từ Supabase Auth, hồ sơ vận hành và sổ kiểm toán PostgreSQL.',
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
                                tooltip: 'Làm mới danh sách tài khoản',
                                onPressed: _busy ? null : () => _load(force: true),
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  color: Colors.white,
                                ),
                              )
                            else
                              FilledButton.icon(
                                onPressed: _busy ? null : () => _load(force: true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _kDarkActive,
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                    color: Color(0xFF206A58),
                                  ),
                                ),
                                icon: const Icon(Icons.refresh_rounded, size: 18),
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
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECDCA)),
                      ),
                      child: SelectableText(
                        _error!,
                        style: const TextStyle(
                          color: _kDanger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (_notice != null)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6FCF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF96F2D7)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline_rounded,
                            color: _kPrimary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _notice!,
                              style: const TextStyle(
                                color: _kPrimary,
                                fontWeight: FontWeight.w700,
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
                            accent: _kPrimary,
                            tint: const Color(0xFFE6FCF5),
                            label: 'Tổng tài khoản Auth',
                            value: '$total',
                            detail:
                                'Đủ hồ sơ: $completed · Chưa hoàn tất: $incomplete',
                            filterKey: 'all',
                          ),
                          _kpiTile(
                            compact: compact,
                            icon: Icons.shield_outlined,
                            accent: const Color(0xFF0B7285),
                            tint: const Color(0xFFE3FAFC),
                            label: 'Điều hành viên Cloud',
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
                                ? const Color(0xFFD9480F)
                                : _kPrimary,
                            tint: pendingCount > 0
                                ? const Color(0xFFFFF4E6)
                                : const Color(0xFFE6FCF5),
                            label: 'Hồ sơ đối tác chờ duyệt',
                            value: '$pendingCount',
                            detail: 'Yêu cầu Tài xế / Cửa hàng mới',
                            filterKey: 'pending',
                          ),
                          _kpiTile(
                            compact: compact,
                            icon: Icons.two_wheeler_rounded,
                            accent: const Color(0xFF364FC7),
                            tint: const Color(0xFFEDF2FF),
                            label: 'Tài xế đã phê duyệt',
                            value: '$drivers',
                            detail: 'Đủ điều kiện nhận chuyến Cloud',
                            filterKey: 'driver',
                          ),
                          _kpiTile(
                            compact: compact,
                            icon: Icons.storefront_outlined,
                            accent: const Color(0xFF5F3DC4),
                            tint: const Color(0xFFF3F0FF),
                            label: 'Đối tác Cửa hàng',
                            value: '$merchants',
                            detail: 'Được tạo & vận hành gian hàng',
                            filterKey: 'merchant',
                          ),
                          _kpiTile(
                            compact: compact,
                            icon: Icons.lock_outline_rounded,
                            accent: blockedCount > 0 ? _kDanger : _kMuted,
                            tint: blockedCount > 0
                                ? const Color(0xFFFEF3F2)
                                : const Color(0xFFF1F5F9),
                            label: 'Tài khoản đang khóa',
                            value: '$blockedCount',
                            detail: 'Tạm đình chỉ giao dịch Cloud',
                            filterKey: 'blocked',
                          ),
                        ];
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final t in tiles) SizedBox(width: width, child: t),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
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
                                        onPressed: () => setState(_search.clear),
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
                                    selectedColor: const Color(0xFFD3F9D8),
                                    labelStyle: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: _filter == opt.$1
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: _filter == opt.$1
                                          ? _kPrimary
                                          : const Color(0xFF334155),
                                    ),
                                    onSelected: (_) =>
                                        setState(() => _filter = opt.$1),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Hiển thị ${visible.length} / ${_accounts.length} tài khoản đã tải',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _kMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_accounts.isEmpty && !_busy)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Center(
                            child: Text(
                              'Chưa có tài khoản Cloud nào trên hệ thống.',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _kMuted,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (visible.isEmpty && !_busy)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.person_search_outlined,
                                size: 36,
                                color: _kMuted,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Không tìm thấy tài khoản phù hợp bộ lọc hiện tại.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _kText,
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
  final _reason = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasProfile = widget.account['has_profile'] == true;
    final email = '${widget.account['email'] ?? ''}'.trim();
    return AlertDialog(
      title: Text(
        hasProfile ? 'Chỉnh sửa hồ sơ tài khoản' : 'Hoàn tất hồ sơ Cloud',
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _kMuted,
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
                  controller: _reason,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú quản trị (không bắt buộc)',
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
    final email = '${widget.account['email'] ?? ''}'.trim();
    final phone = '${widget.account['phone'] ?? ''}'.trim();
    return AlertDialog(
      title: Text(widget.block ? 'Khóa tài khoản' : 'Mở khóa tài khoản'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.displayName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (email.isNotEmpty || phone.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    [if (email.isNotEmpty) email, if (phone.isNotEmpty) phone]
                        .join(' · '),
                    style: const TextStyle(fontSize: 13, color: _kMuted),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                widget.block
                    ? 'Tài khoản bị khóa sẽ không thể đặt đơn, vận hành gian hàng hay nhận chuyến giao trên Cloud.'
                    : 'Mở khóa để khôi phục quyền giao dịch Cloud và các tư cách đối tác đang hiệu lực.',
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
              ? FilledButton.styleFrom(backgroundColor: _kDanger)
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
        final display = value.isEmpty ? '—' : value;
        if (c.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: _kMuted),
              ),
              const SizedBox(height: 2),
              SelectableText(
                display,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _kText,
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
                style: const TextStyle(fontSize: 12.5, color: _kMuted),
              ),
            ),
            Expanded(
              child: SelectableText(
                display,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _kText,
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
    final providers = (_account['auth_providers'] as List? ?? const [])
        .map((e) => '$e')
        .join(', ');
    final approved = (_account['approved_roles'] as List? ?? const [])
        .map((r) => partnerRoleNames['$r'] ?? '$r')
        .toList();
    return AlertDialog(
      title: Text(
        'Hồ sơ & Kiểm toán: ${'${_account['full_name'] ?? ''}'.trim().isNotEmpty ? _account['full_name'] : (_account['email'] ?? _account['user_id'])}',
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
                    style: const TextStyle(color: _kDanger, fontSize: 13),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _infoRow('UUID định danh', '${_account['user_id']}'),
                    _infoRow(
                      'Email xác thực',
                      '${_account['email'] ?? ''}${_account['email_confirmed'] == true ? ' (Đã xác minh)' : ''}',
                    ),
                    _infoRow(
                      'Số điện thoại',
                      '${_account['phone'] ?? ''}'.isNotEmpty
                          ? '${_account['phone']}'
                          : 'Chưa cập nhật',
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
                const Text(
                  'Gian hàng sở hữu',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: _kText,
                  ),
                ),
                const SizedBox(height: 8),
                for (final s in _shops)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Text(
                      '${s['name']} · ${s['status'] == 'active' ? 'Đang hoạt động' : s['status'] == 'pending' ? 'Chờ duyệt' : 'Tạm khóa'}${s['paused'] == true ? ' (Tạm nghỉ)' : ''}\n${s['address'] ?? ''}',
                      style: const TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Nhật ký kiểm toán tài khoản này',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: _kText,
                ),
              ),
              const SizedBox(height: 8),
              if (_audit.isEmpty && !_busy)
                const Text(
                  'Chưa có bản ghi kiểm toán nào cho tài khoản này.',
                  style: TextStyle(fontSize: 12.5, color: _kMuted),
                ),
              for (final e in _audit)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Builder(
                    builder: (_) {
                      final after = e['after_value'] as Map?;
                      final reason = '${after?['reason'] ?? ''}'.trim();
                      final actor = '${e['actor_email'] ?? ''}'.trim().isNotEmpty
                          ? '${e['actor_email']}'
                          : '${e['actor_id']}';
                      return SelectableText(
                        '${adminAuditActionLabel(e['action'])} (${e['action']})\n'
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
