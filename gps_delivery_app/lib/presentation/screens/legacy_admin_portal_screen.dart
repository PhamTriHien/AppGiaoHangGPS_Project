import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/auth/real_auth_delivery_service.dart';
import '../../core/config/env_config.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/enums/user_role.dart';
import '../admin/admin_subsystem_views.dart';
import '../bloc/system_architecture_cubit.dart';

class LegacyAdminPortalScreen extends StatefulWidget {
  const LegacyAdminPortalScreen({super.key});

  @override
  State<LegacyAdminPortalScreen> createState() =>
      _LegacyAdminPortalScreenState();
}

class _LegacyAdminPortalScreenState extends State<LegacyAdminPortalScreen> {
  final _store = AppStateStore.instance;
  final _formKey = GlobalKey<FormState>();
  final _identity = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _otp = TextEditingController();
  bool _setup = false;
  bool _authenticated = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  UserAccountRecord? _pendingAdmin;
  OtpDeliveryReceipt? _receipt;

  bool get _canSetup =>
      _store.isDatabaseReady &&
      !_store.users.any((user) => user.role == SubsystemRole.admin);

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (!mounted) return;
    setState(() {
      if (_authenticated &&
          (_store.activeAuthenticatedUser?.role != SubsystemRole.admin ||
              _store.activeAuthenticatedUser?.status == 'LOCKED')) {
        _authenticated = false;
        _error = 'Phiên quản trị đã kết thúc. Vui lòng đăng nhập lại.';
      }
    });
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _identity.dispose();
    _password.dispose();
    _name.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _openSession(UserAccountRecord user) {
    final current = _store.findUserByPhone(user.phone);
    if (current == null ||
        current.role != SubsystemRole.admin ||
        current.status == 'LOCKED' ||
        current.passwordHash != user.passwordHash) {
      setState(() => _error = 'Tài khoản không có quyền truy cập quản trị.');
      return;
    }
    _store.applyAuthenticatedUserSession(current);
    context.read<SystemArchitectureCubit>().selectRole(SubsystemRole.admin);
    setState(() {
      _authenticated = true;
      _setup = false;
      _pendingAdmin = null;
      _receipt = null;
      _error = null;
      _password.clear();
      _otp.clear();
    });
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    if (!_store.isDatabaseReady) {
      setState(() => _error = 'Chưa mở được dữ liệu trên thiết bị.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_pendingAdmin != null) {
        final user = _pendingAdmin!;
        if (_receipt?.channel == 'TWILIO_VERIFY_V2') {
          final valid = await RealAuthDeliveryService.instance
              .verifyTwilioVerifyV2Code(
                phoneNumber: user.phone,
                otpCode: _otp.text.trim(),
              );
          if (!mounted) return;
          if (!valid) {
            setState(() => _error = 'Mã OTP không chính xác hoặc đã hết hạn.');
            return;
          }
        } else if (!_store.verifyOtpCode(user.phone, _otp.text.trim())) {
          setState(() => _error = 'Mã OTP không chính xác hoặc đã hết hạn.');
          return;
        }
        _openSession(user);
        return;
      }
      if (_setup) {
        if (!_canSetup) {
          setState(() {
            _setup = false;
            _error = 'Quản trị viên đã được thiết lập. Vui lòng đăng nhập.';
          });
          return;
        }
        final user = _store.registerUserAccountWithRole(
          phone: _identity.text.trim(),
          fullName: _name.text.trim(),
          password: _password.text,
          role: SubsystemRole.admin,
          activateSession: false,
        );
        if (user == null) {
          setState(
            () => _error =
                'Không thể tạo tài khoản. Số điện thoại có thể đã được sử dụng.',
          );
          return;
        }
        _openSession(user);
        return;
      }
      final user = _store.authenticateWithPassword(
        phoneOrEmail: _identity.text.trim(),
        password: _password.text,
        activateSession: false,
      );
      if (user == null || user.role != SubsystemRole.admin) {
        setState(
          () => _error =
              'Thông tin đăng nhập không hợp lệ hoặc tài khoản không có quyền quản trị.',
        );
        return;
      }
      if (_store.isUserTwoFactorEnabled(user.phone)) {
        final destination = EnvConfig.isExternalSmsGatewayConfigured
            ? user.phone
            : (EnvConfig.isEmailOtpConfigured ? user.email : '');
        if (destination.isEmpty) {
          setState(
            () => _error = 'Chưa cấu hình kênh gửi OTP cho tài khoản quản trị.',
          );
          return;
        }
        final receipt = await RealAuthDeliveryService.instance
            .deliverOtpChallenge(
              destination: destination,
              otpCode: _store.generateOtpForPhone(user.phone),
            );
        if (!mounted) return;
        if (!receipt.success || !receipt.deliveredExternally) {
          setState(() => _error = receipt.message);
          return;
        }
        setState(() {
          _pendingAdmin = user;
          _receipt = receipt;
          _password.clear();
        });
        return;
      }
      _openSession(user);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Không thể đăng nhập lúc này. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resetForm({bool setup = false}) {
    setState(() {
      _setup = setup;
      _pendingAdmin = null;
      _receipt = null;
      _error = null;
      _password.clear();
      _otp.clear();
      _formKey.currentState?.reset();
    });
  }

  void _logout() {
    setState(() => _authenticated = false);
    _store.clearAuthenticatedSession();
    _resetForm();
  }

  @override
  Widget build(BuildContext context) {
    if (_authenticated) {
      return Scaffold(
        body: SafeArea(child: AdminSubsystemEntry(onLogout: _logout)),
      );
    }
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087F5B)),
        scaffoldBackgroundColor: const Color(0xFFF4F6F5),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                color: Colors.white,
                child: const Row(
                  children: [
                    Icon(
                      Icons.admin_panel_settings_outlined,
                      color: Color(0xFF087F5B),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'GO-MAU ADMIN',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: AutofillGroup(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _setup
                                    ? 'Thiết lập quản trị viên'
                                    : 'Đăng nhập quản trị',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 28),
                              if (_pendingAdmin == null) ...[
                                if (_setup) ...[
                                  TextFormField(
                                    controller: _name,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Họ và tên',
                                    ),
                                    validator: (value) => value!.trim().isEmpty
                                        ? 'Nhập họ và tên'
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                TextFormField(
                                  controller: _identity,
                                  keyboardType: _setup
                                      ? TextInputType.phone
                                      : TextInputType.emailAddress,
                                  autofillHints: _setup
                                      ? null
                                      : const [AutofillHints.username],
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: _setup
                                        ? 'Số điện thoại'
                                        : 'Số điện thoại hoặc Email',
                                  ),
                                  validator: (value) {
                                    if (value!.trim().isEmpty) {
                                      return 'Nhập tài khoản đăng nhập';
                                    }
                                    if (_setup &&
                                        !RegExp(
                                          r'^0[35789][0-9]{8}$',
                                        ).hasMatch(value.trim())) {
                                      return 'Nhập số điện thoại Việt Nam hợp lệ';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _password,
                                  obscureText: _obscure,
                                  autofillHints: [
                                    _setup
                                        ? AutofillHints.newPassword
                                        : AutofillHints.password,
                                  ],
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Mật khẩu',
                                    suffixIcon: IconButton(
                                      tooltip: _obscure
                                          ? 'Hiện mật khẩu'
                                          : 'Ẩn mật khẩu',
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (value) => value!.trim().length < 6
                                      ? 'Mật khẩu tối thiểu 6 ký tự'
                                      : null,
                                ),
                              ] else ...[
                                Text(
                                  'Mã xác thực đã gửi tới ${_receipt!.destination}',
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _otp,
                                  keyboardType: TextInputType.number,
                                  autofillHints: const [
                                    AutofillHints.oneTimeCode,
                                  ],
                                  maxLength: 6,
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: const InputDecoration(
                                    labelText: 'Mã OTP',
                                  ),
                                  validator: (value) =>
                                      !RegExp(
                                        r'^[0-9]{6}$',
                                      ).hasMatch(value!.trim())
                                      ? 'Nhập mã OTP 6 số'
                                      : null,
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 16),
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Color(0xFFB42318),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              FilledButton(
                                onPressed: _busy ? null : _submit,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 48),
                                ),
                                child: _busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        _pendingAdmin != null
                                            ? 'Xác nhận OTP'
                                            : _setup
                                            ? 'Tạo quản trị viên'
                                            : 'Đăng nhập',
                                      ),
                              ),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => Navigator.of(
                                        context,
                                      ).pushNamed('/admin'),
                                icon: const Icon(Icons.cloud_outlined),
                                label: const Text('Mở Cổng Quản trị'),
                              ),
                              if (_setup || _pendingAdmin != null)
                                TextButton(
                                  onPressed: _busy ? null : () => _resetForm(),
                                  child: const Text(
                                    'Quay lại đăng nhập quản trị',
                                  ),
                                )
                              else if (_canSetup)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _resetForm(setup: true),
                                  child: const Text(
                                    'Thiết lập quản trị viên đầu tiên',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
