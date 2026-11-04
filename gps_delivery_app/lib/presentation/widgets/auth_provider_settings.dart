import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import '../../core/config/env_config.dart';
import '../../data/datasources/local/app_state_store.dart';
import 'ghst_button_icon.dart';

class AuthProviderSettings extends StatefulWidget {
  const AuthProviderSettings({super.key, required this.canEdit});

  final bool canEdit;

  @override
  State<AuthProviderSettings> createState() => _AuthProviderSettingsState();
}

class _AuthProviderSettingsState extends State<AuthProviderSettings> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fields = {
      'relayUrl': TextEditingController(text: EnvConfig.otpEmailWebhookUrl),
      'relayToken': TextEditingController(),
    };
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _value(String field) => _fields[field]!.text.trim();

  Future<void> _save() async {
    if (_saving || !widget.canEdit || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppStateStore.instance.saveAuthProviderConfigsToDatabase(
        smtpHost: EnvConfig.smtpHost,
        smtpPort: EnvConfig.smtpPort,
        smtpSenderEmail: EnvConfig.smtpSenderEmail,
        smtpAppPassword: EnvConfig.smtpAppPassword,
        smsWebhookUrl: EnvConfig.smsWebhookUrl,
        googleClientId: EnvConfig.googleClientId,
        googleClientSecret: EnvConfig.googleClientSecret,
        otpEmailWebhookUrl: _value('relayUrl'),
        otpEmailWebhookToken: _value('relayToken').isEmpty
            ? EnvConfig.otpEmailWebhookToken
            : _value('relayToken'),
      );
      final relay = Uri.tryParse(_value('relayUrl'));
      if (relay != null && relay.hasAuthority) {
        final base = relay.resolve('delivery/').toString();
        EnvConfig.configureDeliveryApiRuntime(baseUrl: base);
      }
      if (!mounted) return;
      _fields['relayToken']!.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu cấu hình đăng nhập trên thiết bị.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Không lưu được cấu hình. Vui lòng thử lại.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    String id,
    String label, {
    bool secret = false,
    bool configured = false,
    bool nativeOnly = false,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        key: ValueKey('auth-config-$id'),
        controller: _fields[id],
        enabled: widget.canEdit && !_saving && !(nativeOnly && kIsWeb),
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: !secret,
        keyboardType: id == 'smtpPort' ? TextInputType.number : null,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: secret && configured ? 'Đã lưu' : null,
          prefixIcon: secret ? const GhstButtonIcon(Icons.lock_outline, size: 18) : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kết nối máy chủ',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _status('Backend', EnvConfig.isOtpEmailWebhookConfigured),
            ],
          ),
          const SizedBox(height: 16),
          _field(
            'relayUrl',
            'Email OTP relay URL',
            validator: (value) {
              if (value == null || value.trim().isEmpty) return null;
              final uri = Uri.tryParse(value.trim());
              return uri != null &&
                      uri.host.isNotEmpty &&
                      (uri.scheme == 'https' || uri.scheme == 'http')
                  ? null
                  : 'URL relay không hợp lệ.';
            },
          ),
          _field(
            'relayToken',
            'Token máy chủ local',
            nativeOnly: true,
            secret: true,
            configured: EnvConfig.otpEmailWebhookToken.isNotEmpty,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton.icon(
            onPressed: widget.canEdit && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const GhstButtonIcon(Icons.save_outlined, size: 18),
            label: Text(_saving ? 'Đang lưu...' : 'Lưu cấu hình đăng nhập'),
          ),
        ],
      ),
    );
  }

  Widget _status(String label, bool ready) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GhstButtonIcon(
          ready ? Icons.check_circle_outline : Icons.pending_outlined,
          size: 16,
          color: ready ? Colors.green.shade700 : Colors.grey.shade700,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '$label: ${ready ? 'Đã cấu hình' : 'Chưa cấu hình'}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}
