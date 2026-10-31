import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/integrations/cloud_orders_service.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/studio_user_auth_frame.dart';

enum _AuthMode { login, register, reset, recover, password }

class CloudAuthScreen extends StatefulWidget {
  const CloudAuthScreen({
    super.key,
    required this.service,
    this.recovery = false,
    this.onRecovered,
  });
  final CloudOrdersService service;
  final bool recovery;
  final VoidCallback? onRecovered;

  @override
  State<CloudAuthScreen> createState() => _CloudAuthScreenState();
}

class _CloudAuthScreenState extends State<CloudAuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _code = TextEditingController();
  late _AuthMode _mode = widget.recovery ? _AuthMode.password : _AuthMode.login;
  bool _busy = false, _obscure = true, _googleAvailable = false;
  String? _error, _notice;

  @override
  void initState() {
    super.initState();
    widget.service.googleSignInAvailable().then((enabled) {
      if (mounted) setState(() => _googleAvailable = enabled);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _switch(_AuthMode mode) => setState(() {
    _mode = mode;
    _password.clear();
    _code.clear();
    _error = _notice = null;
  });

  Future<void> _submit({bool google = false}) async {
    if (_busy || !google && !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = _notice = null;
    });
    try {
      if (google) {
        await widget.service.authenticateGoogle();
      } else {
        switch (_mode) {
          case _AuthMode.login:
          case _AuthMode.register:
            final notice = await widget.service.authenticate(
              _email.text,
              _password.text,
              register: _mode == _AuthMode.register,
            );
            if (mounted) {
              setState(() {
                _notice = notice;
                _password.clear();
              });
            }
          case _AuthMode.reset:
            await widget.service.requestPasswordReset(_email.text);
            if (mounted) {
              setState(() {
                _mode = _AuthMode.recover;
                _notice = 'Yêu cầu đã được gửi. Vui lòng kiểm tra email.';
              });
            }
          case _AuthMode.recover:
            await widget.service.recoverPassword(
              _email.text,
              _code.text,
              _password.text,
            );
            widget.onRecovered?.call();
          case _AuthMode.password:
            await widget.service.updatePassword(_password.text);
            widget.onRecovered?.call();
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AuthException
              ? 'Không xác thực được. Kiểm tra thông tin, email xác nhận hoặc thử lại sau.'
              : 'Không kết nối được dịch vụ đăng nhập. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_mode) {
      _AuthMode.login => 'Đăng nhập',
      _AuthMode.register => 'Tạo tài khoản',
      _AuthMode.reset => 'Khôi phục mật khẩu',
      _AuthMode.recover || _AuthMode.password => 'Đặt mật khẩu mới',
    };
    return StudioUserAuthFrame(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StudioUserAuthBrand(),
            const SizedBox(height: 12),
            if ([_AuthMode.login, _AuthMode.register].contains(_mode)) ...[
              SegmentedButton<_AuthMode>(
                segments: const [
                  ButtonSegment(
                    value: _AuthMode.login,
                    label: Text('Đăng nhập'),
                  ),
                  ButtonSegment(
                    value: _AuthMode.register,
                    label: Text('Đăng ký tài khoản'),
                  ),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: _busy
                    ? null
                    : (value) => _switch(value.first),
                style: SegmentedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.ink,
                  selectedBackgroundColor: AppColors.violet,
                  selectedForegroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                  side: const BorderSide(color: AppColors.ink, width: 1.5),
                  shape: const RoundedRectangleBorder(),
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              _mode == _AuthMode.login ? 'Đăng nhập hệ thống' : title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            if (_mode == _AuthMode.login)
              const Text(
                'Nhập Email và mật khẩu đã đăng ký',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            const SizedBox(height: 14),
            if (_mode != _AuthMode.password) ...[
              TextFormField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: (v) =>
                    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                        .hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Nhập email hợp lệ.',
              ),
              const SizedBox(height: 16),
            ],
            if (_mode == _AuthMode.recover) ...[
              TextFormField(
                controller: _code,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Mã xác nhận email',
                ),
                validator: (v) =>
                    (v?.trim().length ?? 0) >= 6 ? null : 'Nhập mã xác nhận.',
              ),
              const SizedBox(height: 16),
            ],
            if (_mode != _AuthMode.reset) ...[
              TextFormField(
                controller: _password,
                enabled: !_busy,
                obscureText: _obscure,
                autofillHints: [
                  _mode == _AuthMode.login
                      ? AutofillHints.password
                      : AutofillHints.newPassword,
                ],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: _mode == _AuthMode.login
                      ? 'Mật khẩu'
                      : 'Mật khẩu mới',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (v) =>
                    (v?.length ?? 0) >= (_mode == _AuthMode.login ? 6 : 8)
                    ? null
                    : 'Mật khẩu cần ít nhất ${_mode == _AuthMode.login ? 6 : 8} ký tự.',
              ),
              const SizedBox(height: 16),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_notice!),
              ),
            if (_busy) const LinearProgressIndicator(),
            DecoratedBox(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(color: AppColors.ink, offset: Offset(5, 5)),
                ],
              ),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.violet,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                  shape: const RoundedRectangleBorder(
                    side: BorderSide(color: AppColors.ink, width: 1.5),
                  ),
                ),
                onPressed: _busy ? null : _submit,
                child: Text(
                  _mode == _AuthMode.reset ? 'Gửi email khôi phục' : title,
                ),
              ),
            ),
            if (_mode == _AuthMode.login) ...[
              TextButton(
                onPressed: _busy ? null : () => _switch(_AuthMode.reset),
                child: const Text('Quên mật khẩu?'),
              ),
              if (_googleAvailable)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _submit(google: true),
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('Tiếp tục với Google'),
                ),
            ] else if (_mode != _AuthMode.password)
              TextButton(
                onPressed: _busy ? null : () => _switch(_AuthMode.login),
                child: const Text('Trở về đăng nhập'),
              ),
          ],
        ),
      ),
    );
  }
}
