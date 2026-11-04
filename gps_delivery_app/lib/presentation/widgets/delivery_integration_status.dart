import 'package:flutter/material.dart';

import '../../core/integrations/delivery_api_client.dart';
import '../../core/integrations/live_delivery_service.dart';
import 'live_order_connection.dart';
import 'backend_integration_settings.dart';
import 'ghst_button_icon.dart';

class DeliveryIntegrationStatus extends StatefulWidget {
  const DeliveryIntegrationStatus({super.key});
  @override
  State<DeliveryIntegrationStatus> createState() =>
      _DeliveryIntegrationStatusState();
}

class _DeliveryIntegrationStatusState extends State<DeliveryIntegrationStatus> {
  final _cloud = LiveDeliveryService.instance;
  Map<String, dynamic>? _status;
  String? _error;
  bool _busy = false;
  final _room = TextEditingController();
  final _user = TextEditingController();
  String _role = 'customer';

  @override
  void initState() {
    super.initState();
    _cloud.addListener(_onCloudChanged);
    _cloud.loadInstallationIdentity();
    _cloud.restoreSession();
  }

  void _onCloudChanged() {
    if (mounted) setState(() {});
  }

  String _shortId(String value) {
    final id = value.trim();
    if (id.isEmpty) return 'đang nhận diện';
    if (id.length <= 12) return id;
    return '${id.substring(0, 8)}...${id.substring(id.length - 4)}';
  }

  @override
  void dispose() {
    _cloud.removeListener(_onCloudChanged);
    _room.dispose();
    _user.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await DeliveryApiClient.instance.request('integrations');
      if (mounted) {
        setState(() {
          _status = status;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Chưa truy cập được máy chủ tích hợp.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Dịch vụ giao hàng',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: _busy ? null : _check,
            icon: const GhstButtonIcon(Icons.refresh),
            label: const Text('Kiểm tra kết nối'),
          ),
          TextButton.icon(
            onPressed: () async {
              await showCloudSignIn(context);
              if (mounted) setState(() {});
            },
            icon: const GhstButtonIcon(Icons.cloud_outlined),
            label: Text(
              _cloud.signedIn ? 'Đổi tài khoản' : 'Đăng nhập tài khoản',
            ),
          ),
          if (_cloud.signedIn)
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      await _cloud.signOut();
                      if (mounted) setState(() {});
                    },
              icon: const GhstButtonIcon(Icons.logout),
              label: const Text('Đăng xuất'),
            ),
        ],
      ),
      Container(
        margin: const EdgeInsets.only(top: 4, bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _cloud.isOperator
              ? Colors.green.withValues(alpha: 0.08)
              : Colors.amber.withValues(alpha: 0.10),
          border: Border.all(
            color: _cloud.isOperator ? Colors.green : Colors.amber,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GhstButtonIcon(
              _cloud.isOperator
                  ? Icons.verified_user_outlined
                  : _cloud.signedIn
                  ? Icons.info_outline
                  : Icons.cloud_off_outlined,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _cloud.signedIn
                    ? '${_cloud.status}\n'
                          'Dự án: ${_cloud.cloudProjectRef}\n'
                          'Email: ${_cloud.email}\n'
                          'Auth UUID: ${_cloud.userId}\n'
                          'Bản cài đặt: ${_shortId(_cloud.installationId)}'
                    : '${_cloud.status}\n'
                          'Dự án đang cấu hình: ${_cloud.cloudProjectRef}\n'
                          'Bản cài đặt: ${_shortId(_cloud.installationId)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      if (_cloud.signedIn && !_cloud.isOperator)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Tài khoản đã đăng nhập nhưng chưa có quyền điều hành. Sau khi cấp quyền điều hành, hãy bấm Đổi tài khoản để đăng nhập lại.',
            style: TextStyle(fontSize: 12, color: Colors.deepOrange),
          ),
        ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (_status != null)
        ...{
          'supabase': 'Supabase',
          'firebase': 'Firebase FCM',
          'photon': 'Photon',
          'vroom': 'VROOM',
          'ocr': 'OCR Việt / Anh',
          'turnstile': 'Turnstile',
          'telegram': 'Telegram',
          'gemini': 'Gemini',
        }.entries.map(
          (item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                GhstButtonIcon(
                  _status![item.key] == true
                      ? Icons.check_circle_outline
                      : Icons.pending_outlined,
                  color: _status![item.key] == true
                      ? Colors.green.shade700
                      : Colors.grey.shade600,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(item.value)),
                Text(
                  _status![item.key] == true ? 'Đã cấu hình' : 'Chưa cấu hình',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      BackendIntegrationSettings(
        key: ValueKey('${_cloud.cloudProjectRef}:${_cloud.userId}'),
      ),
      if (LiveDeliveryService.instance.isOperator) ...[
        const Divider(),
        const Text(
          'Thành viên đơn hàng',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        TextField(
          controller: _room,
          decoration: const InputDecoration(labelText: 'Mã vận đơn'),
        ),
        TextField(
          controller: _user,
          decoration: const InputDecoration(labelText: 'Supabase Auth User ID'),
        ),
        DropdownButtonFormField<String>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), initialValue: _role, items: const [
            DropdownMenuItem(value: 'customer', child: Text('Khách hàng')),
            DropdownMenuItem(value: 'merchant', child: Text('Cửa hàng')),
            DropdownMenuItem(value: 'driver', child: Text('Tài xế')),
          ], onChanged: (value) => setState(() => _role = value!), decoration: const InputDecoration(labelText: 'Vai trò trong đơn'),),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const GhstButtonIcon(Icons.person_add_alt),
            label: const Text('Cấp quyền'),
            onPressed: _busy
                ? null
                : () async {
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    try {
                      await LiveDeliveryService.instance.provisionRoom(
                        _room.text.trim(),
                        _user.text.trim(),
                        _role,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Đã cấp quyền truy cập đơn hàng.'),
                          ),
                        );
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => _error = 'Chưa cấp được quyền. Kiểm tra mã đơn và User ID.',
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
          ),
        ),
      ],
    ],
  );
}
