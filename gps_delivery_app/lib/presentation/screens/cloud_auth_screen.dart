import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/integrations/cloud_orders_service.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../widgets/ghst_button_icon.dart';
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

class _CloudAuthScreenState extends State<CloudAuthScreen>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _code = TextEditingController();
  late _AuthMode _mode = widget.recovery ? _AuthMode.password : _AuthMode.login;
  late bool _googleAvailable = widget.service.cachedGoogleSignInAvailable;
  bool _busy = false,
      _obscure = true,
      _googleAuthoritative = false,
      _probingGoogle = false;
  String? _error, _notice;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _googleRetryTimer;

  bool get _testing =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = widget.service.authChanges.listen(
      (_) {},
      onError: (Object error) {
        if (!mounted || widget.service.signedIn) return;
        setState(() => _error = _authErrorMessage(error));
      },
    );
    unawaited(_checkGoogleAvailability());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_googleAuthoritative) {
      unawaited(_checkGoogleAvailability());
    }
  }

  Future<void> _checkGoogleAvailability() async {
    if (_probingGoogle || !mounted || widget.service.signedIn) return;
    _googleRetryTimer?.cancel();
    _probingGoogle = true;
    try {
      final res = await widget.service.probeGoogleSignIn();
      if (!mounted) return;
      if (_googleAvailable != res.enabled ||
          _googleAuthoritative != res.authoritative) {
        setState(() {
          _googleAvailable = res.enabled;
          _googleAuthoritative = res.authoritative;
        });
      } else {
        _googleAuthoritative = res.authoritative;
      }
      if (!res.authoritative && !_testing && !widget.service.signedIn) {
        _googleRetryTimer = Timer(
          const Duration(seconds: 3),
          _checkGoogleAvailability,
        );
      }
    } finally {
      _probingGoogle = false;
    }
  }

  @override
  void didUpdateWidget(covariant CloudAuthScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recovery && !oldWidget.recovery && _mode != _AuthMode.password) {
      _mode = _AuthMode.password;
      _code.clear();
    }
    if (!identical(widget.service, oldWidget.service)) {
      _googleAuthoritative = false;
      unawaited(_checkGoogleAvailability());
    }
  }

  String _authErrorMessage(Object error) {
    if (error is! AuthException) {
      return 'Không kết nối được dịch vụ đăng nhập. Vui lòng thử lại.';
    }
    return switch (error.code) {
      'over_email_send_rate_limit' =>
        'Vui lòng đợi ít giây trước khi yêu cầu gửi lại mã xác nhận.',
      'same_password' => 'Mật khẩu mới phải khác mật khẩu hiện tại.',
      'otp_expired' || 'otp_disabled' =>
        'Mã xác nhận email không đúng hoặc đã hết hạn. Vui lòng kiểm tra lại hoặc gửi lại mã.',
      _ when error.statusCode == '429' =>
        'Vui lòng đợi ít giây trước khi yêu cầu gửi lại mã xác nhận.',
      _ =>
        'Không xác thực được. Kiểm tra thông tin, email xác nhận hoặc thử lại sau.',
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _googleRetryTimer?.cancel();
    unawaited(_authSubscription?.cancel());
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _switch(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _password.clear();
      _code.clear();
      _error = _notice = null;
    });
    if (!_googleAuthoritative) {
      unawaited(_checkGoogleAvailability());
    }
  }

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
        setState(() => _error = _authErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendCode() async {
    final email = _email.text.trim();
    if (_busy || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _form.currentState?.validate();
      return;
    }
    setState(() {
      _busy = true;
      _error = _notice = null;
    });
    try {
      await widget.service.requestPasswordReset(email);
      if (mounted) {
        setState(() {
          _code.clear();
          _notice = 'Yêu cầu đã được gửi. Vui lòng kiểm tra email.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelRecovery() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = _notice = null;
    });
    try {
      await widget.service.signOut();
      widget.onRecovered?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
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
            const SizedBox(height: 16),
            if ([_AuthMode.login, _AuthMode.register].contains(_mode)) ...[
              StudioAuthTabBar(
                loginSelected: _mode == _AuthMode.login,
                enabled: !_busy,
                onSelectLogin: () => _switch(_AuthMode.login),
                onSelectRegister: () => _switch(_AuthMode.register),
              ),
              const SizedBox(height: 18),
            ],
            Text(
              _mode == _AuthMode.login ? 'Đăng nhập hệ thống' : title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: tokens.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 5),
            if (_mode == _AuthMode.login)
              Text(
                'Nhập Email và mật khẩu đã đăng ký',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: tokens.inkSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            const SizedBox(height: 18),
            if (_mode != _AuthMode.password) ...[
              TextFormField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Padding(
                    padding: EdgeInsets.all(14),
                    child: GhstButtonIcon.glyph(GhstActionKind.mail, size: 18),
                  ),
                ),
                validator: (v) =>
                    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                        .hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Nhập email hợp lệ.',
              ),
              const SizedBox(height: 14),
            ],
            if (_mode == _AuthMode.recover) ...[
              TextFormField(
                controller: _code,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: const InputDecoration(
                  labelText: 'Mã xác nhận email',
                  prefixIcon: Padding(
                    padding: EdgeInsets.all(14),
                    child: GhstButtonIcon.glyph(
                      GhstActionKind.pinCode,
                      size: 18,
                    ),
                  ),
                ),
                validator: (v) =>
                    (v?.trim().length ?? 0) >= 6 ? null : 'Nhập mã xác nhận.',
              ),
              const SizedBox(height: 14),
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
                  prefixIcon: const Padding(
                    padding: EdgeInsets.all(14),
                    child: GhstButtonIcon.glyph(GhstActionKind.lock, size: 18),
                  ),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: GhstButtonIcon.glyph(
                      _obscure ? GhstActionKind.eye : GhstActionKind.eyeOff,
                      size: 18,
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
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: tokens.rose.fill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tokens.rose.border),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: tokens.rose.foreground,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (_notice != null)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: tokens.emerald.fill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tokens.emerald.border),
                ),
                child: Text(
                  _notice!,
                  style: TextStyle(
                    color: tokens.emerald.foreground,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: _busy
                    ? null
                    : [
                        BoxShadow(
                          color: tokens.primary.withValues(alpha: 0.28),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _busy ? null : _submit,
                icon: GhstButtonIcon.glyph(
                  switch (_mode) {
                    _AuthMode.login => GhstActionKind.login,
                    _AuthMode.register => GhstActionKind.userPlus,
                    _AuthMode.reset => GhstActionKind.mail,
                    _AuthMode.recover || _AuthMode.password =>
                      GhstActionKind.key,
                  },
                  size: 18,
                ),
                label: Text(
                  _mode == _AuthMode.reset ? 'Gửi email khôi phục' : title,
                ),
              ),
            ),
            if (_mode == _AuthMode.login) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _busy ? null : () => _switch(_AuthMode.reset),
                icon: const GhstButtonIcon.glyph(GhstActionKind.key, size: 16),
                label: const Text('Quên mật khẩu?'),
              ),
              if (_googleAvailable) ...[
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _submit(google: true),
                  icon: const GhstButtonIcon.glyph(
                    GhstActionKind.google,
                    size: 20,
                  ),
                  label: const Text('Tiếp tục với Google'),
                ),
              ],
            ] else if (_mode == _AuthMode.password) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _busy ? null : _cancelRecovery,
                icon: const GhstButtonIcon.glyph(GhstActionKind.back, size: 16),
                label: const Text('Trở về đăng nhập'),
              ),
            ] else ...[
              if (_mode == _AuthMode.register && _googleAvailable)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _submit(google: true),
                    icon: const GhstButtonIcon.glyph(
                      GhstActionKind.google,
                      size: 20,
                    ),
                    label: const Text('Tiếp tục với Google'),
                  ),
                ),
              if (_mode == _AuthMode.recover)
                TextButton.icon(
                  onPressed: _busy ? null : _resendCode,
                  icon: const GhstButtonIcon.glyph(
                    GhstActionKind.refresh,
                    size: 16,
                  ),
                  label: const Text('Gửi lại mã xác nhận'),
                ),
              TextButton.icon(
                onPressed: _busy ? null : () => _switch(_AuthMode.login),
                icon: const GhstButtonIcon.glyph(GhstActionKind.back, size: 16),
                label: const Text('Trở về đăng nhập'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
