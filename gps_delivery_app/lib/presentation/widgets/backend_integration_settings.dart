import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config/env_config.dart';
import '../../core/integrations/delivery_api_client.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/admin_studio_theme.dart';
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
  String? _storage;
  String? _activeProvider;
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

  String get _payosWebhookUrl {
    final configuredPublic =
        _controllers['PUBLIC_BASE_URL']?.text.trim() ?? '';
    final publicUri = Uri.tryParse(configuredPublic);
    if (publicUri != null &&
        (publicUri.scheme == 'https' || publicUri.scheme == 'http') &&
        publicUri.host.isNotEmpty) {
      final base = configuredPublic.replaceAll(RegExp(r'/+$'), '');
      return base.endsWith('/delivery')
          ? '$base/payments/webhook'
          : '$base/delivery/payments/webhook';
    }
    final backend = _backendAddress;
    if (backend.isEmpty) return '';
    return '${backend.endsWith('/') ? backend : '$backend/'}payments/webhook';
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
    _storage = response['storage']?.toString() ?? _storage;
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

  Future<void> _run(
    Future<void> Function() operation, {
    String? providerId,
  }) async {
    setState(() {
      _busy = true;
      _activeProvider = providerId;
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

  Future<void> _save(String id, Map provider) => _run(providerId: id, () async {
    FocusManager.instance.primaryFocus?.unfocus();
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
        final next = (_providers?[id] as Map?) ?? provider;
        final changed = (response['changed'] as List?)?.length ?? 0;
        final cloudSuffix = _storage == 'cloud_postgres'
            ? ' · đã đồng bộ hệ thống'
            : '';
        if (changed == 0 && values.isEmpty && clear.isEmpty) {
          _message = 'Đã đồng bộ trạng thái ${provider['label']}.';
        } else if (id != 'backend' &&
            next['configured'] == true &&
            next['enabled'] != true) {
          _message =
              'Đã lưu ${provider['label']}$cloudSuffix. Bật "Cho phép backend sử dụng" rồi bấm Lưu để kích hoạt.';
        } else if (next['configured'] != true) {
          _message =
              'Đã lưu ${provider['label']}$cloudSuffix. Điền đủ các trường bắt buộc để hoàn tất cấu hình.';
        } else {
          _message = 'Đã lưu ${provider['label']}$cloudSuffix.';
        }
        _audit = null;
      });
    }
  });

  Future<void> _test(String id) => _run(providerId: id, () async {
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

  IconData _providerIcon(String id) => switch (id) {
    'backend' => Icons.dns_outlined,
    'supabase' => Icons.cloud_sync_outlined,
    'trackasia' || 'google_maps' || 'photon' || 'osrm' => Icons.map_outlined,
    'smtp' => Icons.mail_outline_rounded,
    'sms' => Icons.sms_outlined,
    'google' => Icons.login_rounded,
    'payos' => Icons.payments_outlined,
    'ghn' => Icons.local_shipping_outlined,
    'banks' => Icons.account_balance_outlined,
    'weather' => Icons.wb_sunny_outlined,
    'ocr' => Icons.document_scanner_outlined,
    'vroom' => Icons.alt_route_rounded,
    'firebase' => Icons.notifications_active_outlined,
    'turnstile' => Icons.shield_outlined,
    'gemini' => Icons.auto_awesome_outlined,
    'telegram' => Icons.send_outlined,
    'meilisearch' => Icons.manage_search_rounded,
    _ => Icons.extension_outlined,
  };

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
        activeTrackColor: AdminStudioColors.violet,
        title: Text(
          field['label'].toString(),
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AdminStudioColors.ink,
          ),
        ),
        value: _booleans[key] ?? false,
        onChanged: enabled
            ? (value) => setState(() => _booleans[key] = value)
            : null,
      );
    }
    final savedSecret =
        field['secret'] == true &&
        field['configured'] == true &&
        !_clear.contains(key);
    final maskedPreview = field['maskedValue']?.toString().trim();
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
          floatingLabelBehavior: savedSecret
              ? FloatingLabelBehavior.always
              : null,
          helperText: localOnly
              ? 'Project xác thực chỉ đổi tại máy chủ backend'
              : _clear.contains(key)
              ? 'Sẽ xóa khi lưu'
              : savedSecret
              ? (_storage == 'cloud_postgres'
                    ? 'Khóa bảo mật đã đồng bộ hệ thống — để trống nếu giữ nguyên'
                    : 'Khóa bảo mật đã lưu tại backend — để trống nếu giữ nguyên')
              : null,
          hintText: field['secret'] == true && field['configured'] == true
              ? (maskedPreview != null && maskedPreview.isNotEmpty
                    ? maskedPreview
                    : 'Đã lưu tại backend')
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

  Widget _providerStatusBadge(bool available, Map provider) {
    final (String text, Color fg, Color bg) = !available
        ? (
            'Chưa có luồng giao dịch',
            AdminStudioColors.muted,
            AdminStudioColors.paperWarm,
          )
        : provider['configured'] != true
        ? (
            'Thiếu cấu hình',
            AdminStudioColors.goldInk,
            AdminStudioColors.goldSoft,
          )
        : provider['enabled'] == true
        ? ('Đang bật', AdminStudioColors.ink, AdminStudioColors.acid)
        : ('Đang tắt', AdminStudioColors.muted, AdminStudioColors.paperWarm);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: AdminStudioColors.ink, width: 1.1),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: fg,
          ),
        ),
      ),
    );
  }

  Widget _cardSurface({
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    Color borderColor = AdminStudioColors.ink,
    Offset shadowOffset = const Offset(3, 3),
  }) => AdminNeoBox(
    padding: padding,
    borderColor: borderColor,
    shadowOffset: shadowOffset,
    child: child,
  );

  Widget _provider(String id, Map provider) {
    final available = provider['available'] != false;
    final active =
        available &&
        provider['configured'] == true &&
        provider['enabled'] == true;
    final check = provider['lastCheck'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _cardSurface(
        borderColor: AdminStudioColors.ink,
        shadowOffset: active ? const Offset(4, 4) : const Offset(2, 2),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey('integration-$id'),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 6,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: active
                    ? AdminStudioColors.acid
                    : AdminStudioColors.paperWarm,
                border: Border.all(color: AdminStudioColors.ink, width: 1.2),
              ),
              child: Icon(
                _providerIcon(id),
                size: 19,
                color: AdminStudioColors.ink,
              ),
            ),
            title: Text(
              provider['label'].toString(),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                color: AdminStudioColors.ink,
              ),
            ),
            subtitle: _providerStatusBadge(available, provider),
            children: [
              const Divider(height: 16, color: AdminStudioColors.line),
              if (id == 'payos' && _payosWebhookUrl.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AdminStudioColors.paperWarm,
                    border: Border.all(
                      color: AdminStudioColors.ink,
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.webhook_outlined,
                            size: 17,
                            color: AdminStudioColors.ink,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'WEBHOOK THANH TOÁN PAYOS',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                color: AdminStudioColors.ink,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Sao chép Webhook payOS',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              final webhook = _payosWebhookUrl;
                              Clipboard.setData(ClipboardData(text: webhook));
                              if (mounted) {
                                setState(() {
                                  _failed = false;
                                  _message =
                                      'Đã sao chép địa chỉ Webhook payOS.';
                                });
                              }
                            },
                            icon: const Icon(
                              Icons.copy_rounded,
                              size: 17,
                              color: AdminStudioColors.ink,
                            ),
                          ),
                        ],
                      ),
                      SelectableText(
                        _payosWebhookUrl,
                        key: const ValueKey('payos-webhook-url'),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AdminStudioColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Nhập Client ID, API Key, Checksum Key rồi bấm Lưu và Kiểm tra kết nối để tự động xác thực và đăng ký Webhook này với payOS.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminStudioColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ...((provider['fields'] as List).cast<Map>()).map(
                (field) => _field(field, available),
              ),
              if (check is Map)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: check['verified'] == true
                        ? AdminStudioColors.acidSoft
                        : AdminStudioColors.paper,
                    border: Border.all(
                      color: AdminStudioColors.ink,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        check['verified'] == true
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        size: 18,
                        color: check['verified'] == true
                            ? AdminStudioColors.acidInk
                            : AdminStudioColors.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              check['message'].toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AdminStudioColors.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${check['checkedAt']} · ${check['latencyMs']} ms',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontFamily: 'monospace',
                                color: AdminStudioColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (_message != null && _activeProvider == id)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _statusBanner(),
                ),
              if (available)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: ValueKey('save-integration-$id'),
                        onPressed: _busy ? null : () => _save(id, provider),
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Lưu'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _busy ||
                                (id != 'backend' && provider['enabled'] != true)
                            ? null
                            : id == 'backend'
                            ? _readiness
                            : () => _test(id),
                        icon: const Icon(
                          Icons.network_check_outlined,
                          size: 18,
                        ),
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
          ),
        ),
      ),
    );
  }

  Widget _statusBanner({EdgeInsetsGeometry margin = EdgeInsets.zero}) =>
      Container(
        margin: margin,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _failed
              ? AdminStudioColors.dangerSoft
              : AdminStudioColors.acidSoft,
          border: Border.all(
            color: _failed ? AdminStudioColors.danger : AdminStudioColors.ink,
            width: 1.4,
          ),
        ),
        child: Text(
          _message!,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: _failed ? AdminStudioColors.danger : AdminStudioColors.ink,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final activeCount =
        _providers?.values
            .whereType<Map>()
            .where(
              (p) =>
                  p['available'] != false &&
                  p['configured'] == true &&
                  p['enabled'] == true,
            )
            .length ??
        0;

    return Theme(
      data: AdminStudioTheme.themeData(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminStudioGridBackdrop(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                border: Border.all(color: AdminStudioColors.ink, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: AdminStudioColors.violet,
                    offset: Offset(4, 4),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AdminStudioColors.acid,
                          border: Border.all(
                            color: AdminStudioColors.ink,
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.hub_outlined,
                          size: 20,
                          color: AdminStudioColors.ink,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cổng tích hợp & Dịch vụ Backend',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            if (_providers != null)
                              Text(
                                'Kích hoạt $activeCount/${_providers!.length} dịch vụ${_storage == 'cloud_postgres' ? ' · Lưu trữ tập trung' : ''}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AdminStudioColors.acid,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _load,
                        style: FilledButton.styleFrom(
                          backgroundColor: AdminStudioColors.acid,
                          foregroundColor: AdminStudioColors.ink,
                        ),
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        label: Text(
                          _providers == null
                              ? 'Quản lý API backend'
                              : 'Tải lại cấu hình',
                        ),
                      ),
                      if (_providers != null)
                        IconButton(
                          tooltip: 'Sẵn sàng triển khai',
                          style: IconButton.styleFrom(
                            backgroundColor: AdminStudioColors.shellElevated,
                            foregroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                              side: BorderSide(color: AdminStudioColors.acid),
                            ),
                          ),
                          onPressed: _busy ? null : _readiness,
                          icon: const Icon(Icons.fact_check_outlined),
                        ),
                      if (_providers != null)
                        IconButton(
                          tooltip: 'Hoạt động API',
                          style: IconButton.styleFrom(
                            backgroundColor: AdminStudioColors.shellElevated,
                            foregroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                              side: BorderSide(
                                color: AdminStudioColors.shellLine,
                              ),
                            ),
                          ),
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  final response = await _api.request(
                                    'admin/integrations/usage',
                                    localAuth: _localAuth,
                                  );
                                  if (mounted) {
                                    setState(() => _usage = response);
                                  }
                                }),
                          icon: const Icon(Icons.monitor_heart_outlined),
                        ),
                      if (_providers != null)
                        IconButton(
                          tooltip: 'Lịch sử cấu hình',
                          style: IconButton.styleFrom(
                            backgroundColor: AdminStudioColors.shellElevated,
                            foregroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                              side: BorderSide(
                                color: AdminStudioColors.shellLine,
                              ),
                            ),
                          ),
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  final response = await _api.request(
                                    'admin/integrations/audit',
                                    localAuth: _localAuth,
                                  );
                                  if (mounted) {
                                    setState(
                                      () =>
                                          _audit = response['entries'] as List,
                                    );
                                  }
                                }),
                          icon: const Icon(Icons.history),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(
                color: AdminStudioColors.violet,
                backgroundColor: AdminStudioColors.paperWarm,
              ),
            ),
          if (_message != null &&
              (_activeProvider == null ||
                  _providers?.containsKey(_activeProvider) != true))
            _statusBanner(margin: const EdgeInsets.only(top: 12)),
          if (_providers != null) ...[
            const SizedBox(height: 14),
            _cardSurface(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: ListTile(
                key: const ValueKey('managed-backend-address'),
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AdminStudioColors.violetSoft,
                    border: Border.all(
                      color: AdminStudioColors.ink,
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    _loopback ? Icons.computer_outlined : Icons.cloud_outlined,
                    size: 18,
                    color: AdminStudioColors.violet,
                  ),
                ),
                title: Text(
                  _loopback ? 'Backend local' : 'Backend từ xa',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: AdminStudioColors.ink,
                  ),
                ),
                subtitle: SelectableText(
                  _backendAddress,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: AdminStudioColors.muted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            ..._providers!.entries.map(
              (entry) => _provider(entry.key, entry.value as Map),
            ),
          ],
          if (_usage != null) ...[
            const SizedBox(height: 14),
            _cardSurface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hoạt động API',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: AdminStudioColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Từ khi backend khởi động: ${_usage!['since']}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: AdminStudioColors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if ((_usage!['providers'] as List).isEmpty)
                    const Text('Chưa ghi nhận yêu cầu API.'),
                  for (final row
                      in (_usage!['providers'] as List).whereType<Map>())
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${row['provider']} · ${row['requests']} yêu cầu',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        'Thành công ${row['successes']} · Lỗi ${row['failures']} · Giới hạn 429: ${row['rateLimited']}\nTrung bình ${row['averageMs']} ms · HTTP gần nhất ${row['lastStatus']}',
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (_audit != null) ...[
            const SizedBox(height: 14),
            _cardSurface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lịch sử cấu hình',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: AdminStudioColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_audit!.isEmpty) const Text('Chưa có thay đổi.'),
                  ..._audit!.whereType<Map>().map(
                    (row) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        (row['changed'] as List).join(', '),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${row['at']} · ${row['actor']}',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
