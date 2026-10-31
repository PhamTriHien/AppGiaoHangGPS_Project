import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/integrations/delivery_api_client.dart';
import '../../core/network/public_json_api.dart';

class BackendReadinessDialog extends StatefulWidget {
  const BackendReadinessDialog({
    super.key,
    required this.api,
    this.local = false,
    this.localAuth = false,
  });

  final DeliveryApiClient api;
  final bool local, localAuth;

  @override
  State<BackendReadinessDialog> createState() => _BackendReadinessDialogState();
}

class _BackendReadinessDialogState extends State<BackendReadinessDialog> {
  Map<String, dynamic>? _report;
  bool _busy = false, _migrating = false;
  String? _error, _message;
  bool get _canMigrate =>
      _report?['canMigrate'] == true ||
      (_report?['canMigrate'] == null && widget.local);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _report = null;
    });
    try {
      final report = await widget.api.request(
        'admin/integrations/readiness',
        localAuth: widget.localAuth,
      );
      if (mounted) setState(() => _report = report);
    } on PublicApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không đọc được trạng thái triển khai.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _migrate() async {
    if (_busy || !_canMigrate || _report?['databaseConfigured'] != true) {
      return;
    }
    final version = _report!['migrationVersion'];
    final revision = _report!['databaseRevision'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cập nhật schema cloud?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Áp dụng migration vào database backend đã lưu:'),
              const SizedBox(height: 12),
              for (final file in (_report!['migrations'] as List? ?? []))
                Text('$file'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Quay lại'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.system_update_alt),
            label: const Text('Áp dụng'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _migrating = true;
      _error = null;
      _message = null;
      _report = null;
    });
    try {
      final response = await widget.api.request(
        'admin/integrations/migrate-cloud',
        body: {'confirm': version, 'databaseRevision': revision},
        timeout: const Duration(seconds: 60),
        localAuth: widget.localAuth,
      );
      if (!mounted) return;
      setState(() {
        _report = (response['readiness'] as Map?)?.cast<String, dynamic>();
        _message = response['completed'] == true
            ? 'Đã áp dụng migration. Kết quả kiểm tra lại ở bên dưới.'
            : null;
      });
    } on PublicApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Chưa xác nhận cập nhật schema. Kiểm tra lại trạng thái.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _migrating = false;
        });
      }
    }
  }

  Widget _check(Map row) {
    final status = row['status'];
    final label =
        const {
          'ok': 'Đạt',
          'missing': 'Còn thiếu',
          'error': 'Lỗi kết nối',
          'unchecked': 'Chưa kiểm tra',
          'disabled': 'Đang tắt',
        }[status] ??
        'Chưa xác định';
    final color = status == 'ok'
        ? Colors.green.shade700
        : status == 'error'
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            status == 'ok' ? Icons.check_circle_outline : Icons.info_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['label']} · $label',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text('${row['detail']}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _callback(Map row) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Callback ${row['label']}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                '${row['url'] ?? 'Chưa có URL HTTPS công khai'}',
              ),
            ),
            IconButton(
              tooltip: 'Sao chép callback ${row['label']}',
              onPressed: row['url'] == null
                  ? null
                  : () =>
                        Clipboard.setData(ClipboardData(text: '${row['url']}')),
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
        Text('${row['authentication']}'),
        const Text('Chưa xác minh đăng ký callback tại nhà cung cấp.'),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_migrating,
    child: AlertDialog(
      title: const Text('Sẵn sàng triển khai'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_migrating) const Text('Đang cập nhật schema cloud...'),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_message != null) Text(_message!),
              if (_report != null) ...[
                Text('Kiểm tra lúc: ${_report!['checkedAt']}'),
                for (final row
                    in (_report!['checks'] as List? ?? []).whereType<Map>())
                  _check(row),
                const Divider(),
                for (final row
                    in (_report!['callbacks'] as List? ?? []).whereType<Map>())
                  _callback(row),
                const Divider(),
                const Text('Giao dịch payOS/GHN thực tế: chưa nghiệm thu.'),
                const SizedBox(height: 12),
                if (_canMigrate)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: _busy || _report!['databaseConfigured'] != true
                          ? null
                          : _migrate,
                      icon: const Icon(Icons.system_update_alt),
                      label: const Text('Cập nhật schema cloud'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Kiểm tra lại triển khai',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
        TextButton(
          onPressed: _migrating ? null : () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
}
