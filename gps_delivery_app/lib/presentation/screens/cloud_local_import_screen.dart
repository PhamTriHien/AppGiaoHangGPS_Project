import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../data/datasources/local/app_state_store.dart';

typedef LegacyAddressReader = Future<Map<String, dynamic>> Function({
  required String identifier,
  required String password,
});

class CloudLocalImportScreen extends StatefulWidget {
  const CloudLocalImportScreen({
    super.key,
    required this.session,
    required this.lease,
    this.readSource,
  });
  final CloudAccountSession session;
  final CloudSessionLease lease;
  final LegacyAddressReader? readSource;
  @override
  State<CloudLocalImportScreen> createState() => _CloudLocalImportScreenState();
}

class _CloudLocalImportScreenState extends State<CloudLocalImportScreen> {
  final _identifier = TextEditingController(),
      _password = TextEditingController();
  final _selected = <String>{};
  List<Map<String, dynamic>> _items = [], _report = [];
  String? _sourceName, _error, _notice;
  bool _busy = false, _confirmed = false;
  bool get _allowed => mounted && widget.lease.valid;

  @override
  void initState() {
    super.initState();
    widget.lease.addListener(_invalidated);
  }

  void _invalidated() {
    if (!mounted || widget.lease.valid) return;
    _identifier.clear();
    _password.clear();
    setState(() {
      _items = [];
      _report = [];
      _selected.clear();
      _sourceName = null;
      _error = null;
      _notice = null;
      _confirmed = false;
    });
  }

  @override
  void dispose() {
    widget.lease.removeListener(_invalidated);
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!_allowed || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (error) {
      if (_allowed &&
          error is PublicApiException &&
          [401, 403].contains(error.statusCode)) {
        widget.session.invalidateVerification();
      }
      if (_allowed) {
        setState(
          () => _error = error is PublicApiException
              ? error.message
              : 'Không hoàn tất được yêu cầu. Kiểm tra thông tin và thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _read() => _run(() async {
    if (_identifier.text.trim().isEmpty || _password.text.isEmpty) {
      setState(
        () => _error = 'Nhập tài khoản và mật khẩu đã dùng trên thiết bị.',
      );
      return;
    }
    final reader =
        widget.readSource ?? AppStateStore.instance.previewLegacyAddresses;
    Map<String, dynamic> data;
    try {
      data = await reader(
        identifier: _identifier.text.trim(),
        password: _password.text,
      );
    } finally {
      if (mounted) _password.clear();
    }
    if (!_allowed) return;
    final sourceId = data['source_id'];
    final rows = (data['addresses'] as List).cast<Map>();
    setState(() {
      _sourceName = data['source_name'] as String;
      _items = [
        for (final row in rows)
          {
            'source_key': sha256
                .convert(
                  utf8.encode(
                    jsonEncode([
                      'local-address-v1',
                      data['source_instance'],
                      sourceId,
                      row['source_id'],
                    ]),
                  ),
                )
                .toString(),
            'details': Map<String, dynamic>.from(row['details'] as Map),
          },
      ];
      _selected.clear();
      _report = [];
      _confirmed = false;
      final drafts = (data['draft_count'] as num).toInt();
      _notice = drafts > 0
          ? 'Có $drafts đơn nháp cần kiểm tra và đặt lại riêng.'
          : null;
    });
  });

  List<Map<String, dynamic>> get _selection =>
      _items.where((i) => _selected.contains(i['source_key'])).toList();
  Future<void> _preview() => _run(() async {
    final response = await widget.session.service.request(
      'imports/preview',
      body: {'items': _selection},
    );
    if (!_allowed) return;
    setState(() {
      _report = (response['rows'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      _confirmed = false;
    });
  });
  Future<void> _commit() => _run(() async {
    if (!_confirmed ||
        _report.isEmpty ||
        _report.any((r) => ['invalid', 'conflict'].contains(r['status']))) {
      return;
    }
    final response = await widget.session.service.request(
      'imports/commit',
      body: {'items': _selection},
    );
    if (!_allowed) return;
    setState(() {
      _notice = 'Đã nhập ${response['ready']} địa chỉ.';
      _report = [];
      _selected.clear();
      _confirmed = false;
    });
  });

  @override
  Widget build(BuildContext context) {
    if (!widget.lease.valid) {
      return const Scaffold(
        body: Center(child: Text('Phiên làm việc đã thay đổi.')),
      );
    }
    final statuses = {
      'ready': 'Có thể nhập',
      'invalid': 'Cần bổ sung',
      'conflict': 'Nội dung đã thay đổi',
      'duplicate': 'Địa chỉ trùng',
      'imported': 'Đã nhập trước đây',
    };
    final canCommit =
        _report.isNotEmpty &&
        _report.any((r) => r['status'] == 'ready') &&
        !_report.any((r) => ['invalid', 'conflict'].contains(r['status']));
    return Scaffold(
      appBar: AppBar(title: const Text('Nhập địa chỉ từ thiết bị')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Tài khoản nhận: ${widget.session.service.email}'),
                const SizedBox(height: 20),
                if (_sourceName == null) ...[
                  TextField(
                    controller: _identifier,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Tài khoản trên thiết bị',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu trên thiết bị',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _busy ? null : _read,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Xác minh nguồn'),
                  ),
                ] else ...[
                  Text(
                    'Nguồn: $_sourceName',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Không có địa chỉ đã lưu.'),
                    ),
                  for (final item in _items)
                    Builder(
                      builder: (_) {
                        final key = item['source_key'] as String,
                            details = item['details'] as Map;
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${details['label']}'),
                          subtitle: Text(
                            '${details['full_address']}\n${details['recipient_name']} · ${details['recipient_phone']}',
                          ),
                          value: _selected.contains(key),
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  if (value == true && _selected.length < 25) {
                                    _selected.add(key);
                                  } else {
                                    _selected.remove(key);
                                  }
                                  _report = [];
                                  _confirmed = false;
                                }),
                        );
                      },
                    ),
                  if (_items.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: _busy || _selected.isEmpty ? null : _preview,
                      icon: const Icon(Icons.preview_outlined),
                      label: const Text('Kiểm tra bản ghi đã chọn'),
                    ),
                  for (final row in _report)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '${(row['details'] as Map?)?['label'] ?? 'Địa chỉ'} · ${statuses[row['status']]}${(row['problem'] as String? ?? '').isEmpty ? '' : '\n${row['problem']}'}',
                      ),
                    ),
                  if (canCommit) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _confirmed,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _confirmed = v == true),
                      title: const Text(
                        'Tôi xác nhận nhập các địa chỉ đã chọn vào tài khoản nhận ở trên.',
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _busy || !_confirmed ? null : _commit,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('Nhập địa chỉ'),
                    ),
                  ],
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _sourceName = null;
                            _items = [];
                            _report = [];
                            _selected.clear();
                            _confirmed = false;
                          }),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Đổi nguồn'),
                  ),
                ],
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_notice != null) Text(_notice!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
