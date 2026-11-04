import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/integrations/live_delivery_service.dart';
import '../../core/integrations/push_notification_service.dart';
import '../../data/datasources/local/app_state_store.dart';
import 'ghst_button_icon.dart';

class LiveOrderConnection extends StatefulWidget {
  const LiveOrderConnection({super.key, required this.room});
  final String room;
  @override
  State<LiveOrderConnection> createState() => _LiveOrderConnectionState();
}

class _LiveOrderConnectionState extends State<LiveOrderConnection> {
  final _service = LiveDeliveryService.instance;
  final _store = AppStateStore.instance;
  bool _busy = false;
  String? _error;
  String? _role;
  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    _store.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    _store.removeListener(_changed);
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_service.signedIn) {
        final ok = await showCloudSignIn(context);
        if (ok != true) return;
      }
      final role = await _service.memberRole(widget.room);
      await _store.connectLiveRoom(widget.room);
      if (mounted) setState(() => _role = role);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Chưa kết nối được. Kiểm tra tài khoản và quyền truy cập đơn hàng.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'PNG / JPEG',
            extensions: ['png', 'jpg', 'jpeg'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 5000000) throw StateError('Ảnh quá lớn.');
      final path = await _service.uploadEvidence(
        widget.room,
        await file.readAsBytes(),
        file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg',
      );
      final url = await _service.evidenceUrl(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Đã lưu ảnh giao hàng.'),
            action: SnackBarAction(
              label: 'Xem ảnh',
              onPressed: () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Chưa tải được ảnh giao hàng lên hệ thống.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GhstButtonIcon(
              _store.isRoomConnected(widget.room)
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              size: 18,
            ),
            Text(
              _store.liveRoomMessages[widget.room] ?? 'Dữ liệu trên thiết bị',
              style: const TextStyle(fontSize: 12),
            ),
            IconButton(
              tooltip: 'Kết nối đồng bộ đơn hàng',
              onPressed: _busy ? null : _connect,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const GhstButtonIcon(Icons.sync),
            ),
            if (_service.signedIn && PushNotificationService.supported)
              IconButton(
                tooltip: 'Bật thông báo đơn hàng',
                icon: const GhstButtonIcon(Icons.notifications_active_outlined),
                onPressed: () async {
                  try {
                    await PushNotificationService.instance.enable((text) {
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(text)));
                      }
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Đã bật thông báo.')),
                      );
                    }
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () => _error = 'Chưa bật được thông báo. Kiểm tra cấu hình Firebase và quyền thiết bị.',
                      );
                    }
                  }
                },
              ),
            if (_store.isRoomConnected(widget.room) &&
                ['driver', 'operator'].contains(_role))
              IconButton(
                tooltip: 'Tải ảnh giao hàng',
                onPressed: _busy ? null : _upload,
                icon: const GhstButtonIcon(Icons.add_a_photo_outlined),
              ),
            if (_store.liveEvidencePaths[widget.room] != null)
              IconButton(
                tooltip: 'Xem ảnh giao hàng',
                icon: const GhstButtonIcon(Icons.photo_outlined),
                onPressed: () async {
                  try {
                    final url = await _service.evidenceUrl(
                      _store.liveEvidencePaths[widget.room]!,
                    );
                    await launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (_) {
                    if (mounted) {
                      setState(() => _error = 'Chưa mở được ảnh giao hàng.');
                    }
                  }
                },
              ),
          ],
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
      ],
    ),
  );
}

Future<bool?> showCloudSignIn(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (_) => const _CloudSignInDialog(),
);

class _CloudSignInDialog extends StatefulWidget {
  const _CloudSignInDialog();
  @override
  State<_CloudSignInDialog> createState() => _CloudSignInDialogState();
}

class _CloudSignInDialogState extends State<_CloudSignInDialog> {
  late final _email = TextEditingController(
    text: AppStateStore.instance.activeAuthenticatedUser?.email ?? '',
  );
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppStateStore.instance.disconnectLiveRooms();
      await PushNotificationService.instance.disable();
      await LiveDeliveryService.instance.signOut();
      await LiveDeliveryService.instance.signIn(_email.text, _password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Chưa đăng nhập được. Kiểm tra thông tin tài khoản và kết nối mạng.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Đăng nhập trực tuyến'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Mật khẩu'),
            onSubmitted: (_) {
              if (!_busy) _signIn();
            },
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton.icon(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

        label: const Text('Hủy'),
      ),
      FilledButton.icon(
        onPressed: _busy ? null : _signIn,
        icon: GhstButtonIcon.forLabel(_busy ? 'Đang kết nối...' : 'Đăng nhập', size: 16),

        label: Text(_busy ? 'Đang kết nối...' : 'Đăng nhập'),
      ),
    ],
  );
}
