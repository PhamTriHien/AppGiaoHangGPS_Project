import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/integrations/delivery_api_client.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/admin_studio_theme.dart';
import 'ghst_button_icon.dart';

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
      builder: (context) {
        final p = AdminStudioPalette.of(context);
        return Theme(
          data: AdminStudioTheme.of(context),
          child: AlertDialog(
            title: Text(
              'Cập nhật cấu trúc dữ liệu?',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: p.ink,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Áp dụng migration vào database backend đã lưu:'),
                  const SizedBox(height: 12),
                  for (final file in (_report!['migrations'] as List? ?? []))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '$file',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(context, false),
                icon: const GhstButtonIcon.glyph(GhstActionKind.back, size: 16),

                label: const Text('Quay lại'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const GhstButtonIcon(Icons.system_update_alt),
                label: const Text('Áp dụng'),
              ),
            ],
          ),
        );
      },
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

  Widget _check(AdminStudioPalette p, Map row) {
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
    final (Color fg, Color bg) = switch (status) {
      'ok' => (p.acidInk, p.acidSoft),
      'error' => (p.dangerInk, p.dangerSoft),
      'missing' => (p.goldInk, p.goldSoft),
      _ => (p.muted, p.surfaceSubtle),
    };
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GhstButtonIcon(
            status == 'ok' ? Icons.check_circle_outline : Icons.info_outline,
            color: fg,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['label']} · $label',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: status == 'error' ? fg : p.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${row['detail']}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: p.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _callback(AdminStudioPalette p, Map row) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: p.surfaceSubtle,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: p.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Callback ${row['label']}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: p.ink,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                '${row['url'] ?? 'Chưa có URL HTTPS công khai'}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: p.ink,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Sao chép callback ${row['label']}',
              onPressed: row['url'] == null
                  ? null
                  : () =>
                        Clipboard.setData(ClipboardData(text: '${row['url']}')),
              icon: const GhstButtonIcon(Icons.copy, size: 18),
            ),
          ],
        ),
        Text(
          '${row['authentication']}',
          style: TextStyle(fontSize: 12.5, color: p.muted),
        ),
        Text(
          'Chưa xác minh đăng ký callback tại nhà cung cấp.',
          style: TextStyle(fontSize: 12, color: p.muted),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = AdminStudioPalette.of(context);
    return Theme(
      data: AdminStudioTheme.of(context),
      child: PopScope(
        canPop: !_migrating,
        child: AlertDialog(
          title: Text(
            'Sẵn sàng triển khai',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: p.ink,
            ),
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_busy)
                    LinearProgressIndicator(
                      color: p.violet,
                      backgroundColor: p.paperWarm,
                    ),
                  if (_migrating)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Đang cập nhật cấu trúc dữ liệu...',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: p.dangerSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: p.danger,
                          width: 1.4,
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: p.dangerInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (_message != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: p.acidSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: p.acidInk,
                          width: 1.4,
                        ),
                      ),
                      child: Text(
                        _message!,
                        style: TextStyle(
                          color: p.acidInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (_report != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Kiểm tra lúc: ${_report!['checkedAt']}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: p.muted,
                        ),
                      ),
                    ),
                    for (final row
                        in (_report!['checks'] as List? ?? []).whereType<Map>())
                      _check(p, row),
                    const SizedBox(height: 12),
                    const Divider(),
                    for (final row
                        in (_report!['callbacks'] as List? ?? [])
                            .whereType<Map>())
                      _callback(p, row),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 10),
                    Text(
                      'Giao dịch payOS/GHN thực tế: chưa nghiệm thu.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: p.muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_canMigrate)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed:
                              _busy || _report!['databaseConfigured'] != true
                              ? null
                              : _migrate,
                          icon: const GhstButtonIcon(Icons.system_update_alt),
                          label: const Text('Cập nhật cấu trúc dữ liệu'),
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
              icon: const GhstButtonIcon(Icons.refresh),
            ),
            TextButton.icon(
              onPressed: _migrating ? null : () => Navigator.pop(context),
              icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

              label: const Text('Đóng'),
            ),
          ],
        ),
      ),
    );
  }
}
