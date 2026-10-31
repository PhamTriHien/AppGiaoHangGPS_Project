import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import 'cloud_membership_panel.dart';

const cloudAccountRoles = {
  'customer': 'Khách hàng',
  'merchant': 'Cửa hàng',
  'driver': 'Tài xế',
};

/// Edits only server-supported fields; approved roles remain server-owned.
class CloudProfileForm extends StatefulWidget {
  const CloudProfileForm({
    super.key,
    required this.session,
    this.lease,
    this.onSaved,
    this.onCancel,
  });

  final CloudAccountSession session;
  final CloudSessionLease? lease;
  final VoidCallback? onSaved, onCancel;

  @override
  State<CloudProfileForm> createState() => _CloudProfileFormState();
}

class _CloudProfileFormState extends State<CloudProfileForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: _initialName(),
  );
  late final _phone = TextEditingController(
    text: widget.session.account?['phone'] as String? ?? '',
  );
  late final _identity = widget.session.service.identityScope;
  late String _requested = _initialRole();
  bool _busy = false, _invalidated = false;
  String? _error, _notice;

  String _initialName() {
    final saved = (widget.session.account?['full_name'] as String?)?.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    try {
      final metadata = Supabase.instance.client.auth.currentUser?.userMetadata;
      final candidate = (metadata?['full_name'] ?? metadata?['name'])?.toString().trim() ?? '';
      return candidate.length <= 120 ? candidate : candidate.substring(0, 120);
    } catch (_) {
      return '';
    }
  }

  String _initialRole() {
    if (widget.session.schemaVersion >= 3) return 'customer';
    final account = widget.session.account;
    final role = account?['requested_role'] ?? account?['role'];
    return cloudAccountRoles.containsKey(role) ? role as String : 'customer';
  }

  bool get _allowed =>
      !_invalidated &&
      widget.session.verified &&
      widget.session.service.identityScope == _identity &&
      widget.session.account?['blocked'] != true &&
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
      _name.clear();
      _phone.clear();
      _requested = 'customer';
      _error = null;
      _notice = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_allowed || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.session.saveProfile(
        fullName: _name.text,
        phone: _phone.text,
        requestedRole: _requested,
      );
      if (mounted && _allowed) {
        setState(() => _notice = 'Đã lưu hồ sơ.');
        widget.onSaved?.call();
      }
    } catch (error) {
      if (mounted && _allowed) {
        setState(
          () => _error = error is PublicApiException
              ? error.message
              : 'Không lưu được hồ sơ. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const Text('Phiên làm việc đã thay đổi. Vui lòng mở lại hồ sơ.');
    }
    final account = widget.session.account;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Thông tin tài khoản',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(widget.session.service.email),
            if (account != null && widget.session.schemaVersion < 3)
              Text('Vai trò: ${cloudAccountRoles[account['role']]}'),
            if (account?['requested_role'] != null &&
                widget.session.schemaVersion < 3)
              Text(
                'Chờ duyệt vai trò ${cloudAccountRoles[account!['requested_role']]}',
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              enabled: !_busy,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Họ và tên',
                counterText: '',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value == null ||
                      value.trim().isEmpty ||
                      value.trim().length > 120
                  ? 'Họ tên từ 1 đến 120 ký tự.'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              enabled: !_busy,
              maxLength: 10,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Số điện thoại',
                counterText: '',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  RegExp(r'^0[35789][0-9]{8}$').hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Số điện thoại Việt Nam không hợp lệ.',
            ),
            const SizedBox(height: 14),
            if (widget.session.schemaVersion < 3)
              DropdownButtonFormField<String>(
                initialValue: _requested,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Đăng ký vai trò',
                  border: OutlineInputBorder(),
                ),
                items: cloudAccountRoles.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _requested = value!),
              ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_notice != null) Text(_notice!),
            if (_busy) const LinearProgressIndicator(),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Lưu hồ sơ'),
            ),
            if (widget.onCancel != null)
              TextButton(
                onPressed: _busy ? null : widget.onCancel,
                child: const Text('Quay lại'),
              ),
            if (account != null && widget.session.schemaVersion >= 3)
              CloudMembershipPanel(
                session: widget.session,
                lease: widget.lease,
              ),
          ],
        ),
      ),
    );
  }
}
