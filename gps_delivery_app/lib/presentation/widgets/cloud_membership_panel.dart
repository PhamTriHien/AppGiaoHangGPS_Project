import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';

const partnerRoleNames = {'merchant': 'Cửa hàng', 'driver': 'Tài xế'};
const partnerStateNames = {
  'pending': 'Chờ duyệt',
  'active': 'Đã duyệt',
  'rejected': 'Chưa được duyệt',
  'revoked': 'Đã thu hồi',
};

class CloudMembershipPanel extends StatefulWidget {
  const CloudMembershipPanel({super.key, required this.session, this.lease});
  final CloudAccountSession session;
  final CloudSessionLease? lease;
  @override
  State<CloudMembershipPanel> createState() => _CloudMembershipPanelState();
}

class _CloudMembershipPanelState extends State<CloudMembershipPanel> {
  late final _scope = widget.session.service.identityScope;
  bool _busy = false, _invalidated = false;
  String? _error;
  bool get _allowed =>
      !_invalidated &&
      widget.session.canUseBusiness &&
      widget.session.service.identityScope == _scope &&
      (widget.lease?.valid ?? true);

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (!_allowed) {
      _invalidated = true;
      _error = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    super.dispose();
  }

  Future<void> _request(String role) async {
    if (!_allowed || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.requestMembership(role);
    } catch (error) {
      if (mounted && _allowed) {
        setState(
          () => _error = error is PublicApiException
              ? error.message
              : 'Không gửi được yêu cầu. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed || widget.session.schemaVersion < 3) {
      return const SizedBox.shrink();
    }
    final memberships = (widget.session.account!['memberships'] as List)
        .cast<Map>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Text('Đăng ký đối tác', style: Theme.of(context).textTheme.titleMedium),
        for (final role in partnerRoleNames.keys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Builder(
              builder: (_) {
                final membership = memberships
                    .where((m) => m['role'] == role)
                    .firstOrNull;
                final state = membership?['state'];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(
                          role == 'merchant'
                              ? Icons.storefront_outlined
                              : Icons.delivery_dining,
                        ),
                        Text(partnerRoleNames[role]!),
                        if (state != null) Text(partnerStateNames[state]!),
                        if (state != 'active' && state != 'pending')
                          TextButton.icon(
                            key: ValueKey('request-$role'),
                            onPressed: _busy ? null : () => _request(role),
                            icon: const Icon(Icons.person_add_alt_1),
                            label: Text(
                              state == null ? 'Đăng ký' : 'Gửi lại yêu cầu',
                            ),
                          ),
                      ],
                    ),
                    if ((membership?['reason'] as String? ?? '').isNotEmpty)
                      Text(membership!['reason'] as String),
                  ],
                );
              },
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
