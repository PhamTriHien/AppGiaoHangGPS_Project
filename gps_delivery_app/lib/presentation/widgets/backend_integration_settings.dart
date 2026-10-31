import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/env_config.dart';
import '../../core/integrations/delivery_api_client.dart';
import '../../core/network/public_json_api.dart';
import 'backend_readiness_dialog.dart';

class BackendIntegrationSettings extends StatefulWidget {
  const BackendIntegrationSettings({super.key, this.api});
  final DeliveryApiClient? api;

  @override
  State<BackendIntegrationSettings> createState() =>
      _BackendIntegrationSettingsState();
}

class _BackendIntegrationSettingsState
    extends State<BackendIntegrationSettings> {
  final _controllers = <String, TextEditingController>{};
  final _booleans = <String, bool>{};
  final _clear = <String>{};
  Map<String, dynamic>? _providers;
  List<dynamic>? _audit;
  Map<String, dynamic>? _usage;
  bool _local = false;
  bool _busy = false;
  String? _message;
  bool _failed = false;
  DeliveryApiClient get _api => widget.api ?? DeliveryApiClient.instance;
  Uri? get _backend => Uri.tryParse(EnvConfig.deliveryApiBaseUrl);
  bool get _loopback =>
      const ['localhost', '127.0.0.1', '::1'].contains(_backend?.host);
  String get _backendAddress {
    final backend = _backend;
    if (backend == null || backend.host.isEmpty) return '';
    return Uri(
      scheme: backend.scheme,
      host: backend.host,
      port: backend.hasPort ? backend.port : null,
      path: backend.path,
    ).toString();
  }

  bool get _localAuth =>
      !kIsWeb && EnvConfig.otpEmailWebhookToken.isNotEmpty && _loopback;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _accept(Map<String, dynamic> response, {String? savedProvider}) {
    _providers = Map<String, dynamic>.from(response['providers'] as Map);
    _local = response['local'] == true || _local;
    for (final entry in _providers!.entries) {
      for (final field in (entry.value['fields'] as List).cast<Map>()) {
        final key = field['key'] as String;
        final controller = _controllers.putIfAbsent(
          key,
          TextEditingController.new,
        );
        if (savedProvider == null || savedProvider == entry.key) {
          controller.text = field['secret'] == true
              ? ''
              : field['value']?.toString() ?? '';
          _booleans[key] = field['value'] == 'true';
          _clear.remove(key);
        }
      }
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
    });
    try {
      await operation();
    } on PublicApiException catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = 'Không đọc được cấu hình backend.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final response = await _api.request(
      'admin/integrations',
      localAuth: _localAuth,
    );
    if (mounted) {
      setState(() {
        _local = response['local'] == true;
        _accept(response);
      });
    }
  });

  Future<void> _save(String id, Map provider) => _run(() async {
    final values = <String, String>{};
    final clear = <String>[];
    for (final field in (provider['fields'] as List).cast<Map>()) {
      final key = field['key'] as String;
      if (field['localOnly'] == true && !_local) continue;
      if (_clear.contains(key)) {
        clear.add(key);
      } else if (field['type'] == 'boolean') {
        final value = (_booleans[key] ?? false).toString();
        if (value != field['value']) values[key] = value;
      } else {
        final value = _controllers[key]!.text.trim();
        if (field['secret'] == true) {
          if (value.isNotEmpty) values[key] = value;
        } else if (value != field['value']) {
          values[key] = value;
        }
      }
    }
    final response = await _api.request(
      'admin/integrations/config',
      body: {'values': values, 'clear': clear},
      localAuth: _localAuth,
    );
    if (mounted) {
      setState(() {
        _accept(response, savedProvider: id);
        _message = 'Đã lưu ${provider['label']}.';
        _audit = null;
      });
    }
  });

  Future<void> _test(String id) => _run(() async {
    final response = await _api.request(
      'admin/integrations/test/$id',
      body: const {},
      localAuth: _localAuth,
    );
    if (mounted) {
      setState(() {
        _providers![id]['lastCheck'] = response;
        _failed = response['ok'] != true;
        _message = response['message']?.toString();
      });
    }
  });

  Future<void> _readiness() => showDialog<void>(
    context: context,
    builder: (_) =>
        BackendReadinessDialog(api: _api, local: _local, localAuth: _localAuth),
  );

  Widget _field(Map field, bool available) {
    final key = field['key'] as String;
    final localOnly = field['localOnly'] == true && !_local;
    final enabled = !_busy && available && !localOnly;
    if (field['type'] == 'select') {
      final value = _controllers[key]!.text;
      final options = (field['options'] as List).cast<String>();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DropdownButtonFormField<String>(
          initialValue: options.contains(value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: field['label'].toString()),
          items: options
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: enabled
              ? (value) => setState(() => _controllers[key]!.text = value ?? '')
              : null,
        ),
      );
    }
    if (field['type'] == 'boolean') {
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(field['label'].toString()),
        value: _booleans[key] ?? false,
        onChanged: enabled
            ? (value) => setState(() => _booleans[key] = value)
            : null,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: TextField(
        key: ValueKey('integration-field-$key'),
        controller: _controllers[key],
        enabled: enabled && !_clear.contains(key),
        obscureText: field['secret'] == true && field['type'] != 'certificate',
        maxLines: field['type'] == 'certificate' ? 8 : 1,
        minLines: field['type'] == 'certificate' ? 4 : 1,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: field['type'] == 'number'
            ? TextInputType.number
            : field['type'] == 'certificate'
            ? TextInputType.multiline
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: field['label'].toString(),
          helperText: localOnly
              ? 'Project xác thực chỉ đổi tại máy chủ backend'
              : _clear.contains(key)
              ? 'Sẽ xóa khi lưu'
              : null,
          hintText: field['secret'] == true && field['configured'] == true
              ? 'Đã lưu tại backend'
              : null,
          suffixIcon: enabled && field['configured'] == true
              ? IconButton(
                  tooltip: _clear.contains(key)
                      ? 'Giữ giá trị hiện tại'
                      : 'Xóa giá trị đã lưu',
                  icon: Icon(
                    _clear.contains(key) ? Icons.undo : Icons.delete_outline,
                  ),
                  onPressed: () => setState(() {
                    if (!_clear.remove(key)) _clear.add(key);
                  }),
                )
              : null,
        ),
      ),
    );
  }

  Widget _provider(String id, Map provider) {
    final available = provider['available'] != false;
    final check = provider['lastCheck'];
    return ExpansionTile(
      key: ValueKey('integration-$id'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8),
      title: Text(
        provider['label'].toString(),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        !available
            ? 'Chưa có luồng giao dịch'
            : !provider['configured']
            ? 'Thiếu cấu hình'
            : provider['enabled'] == true
            ? 'Đang bật'
            : 'Đang tắt',
      ),
      children: [
        ...((provider['fields'] as List).cast<Map>()).map(
          (field) => _field(field, available),
        ),
        if (check is Map)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              check['verified'] == true
                  ? Icons.check_circle_outline
                  : Icons.info_outline,
            ),
            title: Text(check['message'].toString()),
            subtitle: Text('${check['checkedAt']} · ${check['latencyMs']} ms'),
          ),
        if (available)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: ValueKey('save-integration-$id'),
                  onPressed: _busy ? null : () => _save(id, provider),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Lưu'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _busy || (id != 'backend' && provider['enabled'] != true)
                      ? null
                      : id == 'backend'
                      ? _readiness
                      : () => _test(id),
                  icon: const Icon(Icons.network_check_outlined),
                  label: Text(
                    id == 'backend'
                        ? 'Kiểm tra triển khai'
                        : 'Kiểm tra kết nối',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          TextButton.icon(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.settings_outlined),
            label: Text(
              _providers == null ? 'Quản lý API backend' : 'Tải lại cấu hình',
            ),
          ),
          if (_providers != null)
            IconButton(
              tooltip: 'Sẵn sàng triển khai',
              onPressed: _busy ? null : _readiness,
              icon: const Icon(Icons.fact_check_outlined),
            ),
          if (_providers != null)
            IconButton(
              tooltip: 'Hoạt động API',
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final response = await _api.request(
                        'admin/integrations/usage',
                        localAuth: _localAuth,
                      );
                      if (mounted) setState(() => _usage = response);
                    }),
              icon: const Icon(Icons.monitor_heart_outlined),
            ),
          if (_providers != null)
            IconButton(
              tooltip: 'Lịch sử cấu hình',
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final response = await _api.request(
                        'admin/integrations/audit',
                        localAuth: _localAuth,
                      );
                      if (mounted) {
                        setState(() => _audit = response['entries'] as List);
                      }
                    }),
              icon: const Icon(Icons.history),
            ),
        ],
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            _message!,
            style: TextStyle(
              color: _failed ? Theme.of(context).colorScheme.error : null,
            ),
          ),
        ),
      if (_providers != null)
        ListTile(
          key: const ValueKey('managed-backend-address'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            _loopback ? Icons.computer_outlined : Icons.cloud_outlined,
          ),
          title: Text(_loopback ? 'Backend local' : 'Backend từ xa'),
          subtitle: SelectableText(_backendAddress),
        ),
      if (_providers != null)
        ..._providers!.entries.map(
          (entry) => _provider(entry.key, entry.value as Map),
        ),
      if (_usage != null) ...[
        const Divider(),
        const Text(
          'Hoạt động API',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        Text('Từ khi backend khởi động: ${_usage!['since']}'),
        if ((_usage!['providers'] as List).isEmpty)
          const Text('Chưa ghi nhận yêu cầu API.'),
        for (final row in (_usage!['providers'] as List).whereType<Map>())
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${row['provider']} · ${row['requests']} yêu cầu'),
            subtitle: Text(
              'Thành công ${row['successes']} · Lỗi ${row['failures']} · Giới hạn 429: ${row['rateLimited']}\nTrung bình ${row['averageMs']} ms · HTTP gần nhất ${row['lastStatus']}',
            ),
          ),
      ],
      if (_audit != null) ...[
        const Divider(),
        const Text(
          'Lịch sử cấu hình',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        if (_audit!.isEmpty) const Text('Chưa có thay đổi.'),
        ..._audit!.whereType<Map>().map(
          (row) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text((row['changed'] as List).join(', ')),
            subtitle: Text('${row['at']} · ${row['actor']}'),
          ),
        ),
      ],
    ],
  );
}
