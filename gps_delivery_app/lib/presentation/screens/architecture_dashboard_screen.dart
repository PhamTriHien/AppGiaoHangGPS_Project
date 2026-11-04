import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/auth/real_auth_delivery_service.dart';
import '../../core/config/env_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/security_and_barcode_utils.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/enums/user_role.dart';
import '../bloc/system_architecture_cubit.dart';
import '../customer/customer_subsystem_views.dart';
import '../driver/driver_subsystem_views.dart';
import '../merchant/merchant_subsystem_views.dart';
import '../widgets/ghst_button_icon.dart';
import '../widgets/in_app_google_oauth_dialog.dart';
import '../widgets/studio_design_widgets.dart';
import '../widgets/studio_user_auth_frame.dart';

class ArchitectureDashboardScreen extends StatefulWidget {
  const ArchitectureDashboardScreen({super.key});

  @override
  State<ArchitectureDashboardScreen> createState() =>
      _ArchitectureDashboardScreenState();
}

class _ArchitectureDashboardScreenState
    extends State<ArchitectureDashboardScreen> {
  final AppStateStore _store = AppStateStore.instance;
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _fullNameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _newPasswordCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();

  Timer? _otpCountdownTimer;

  bool _showStartup3dSplash = false;
  bool _isLoggedIn = false;
  bool _otpSent = false;
  bool _isDeliveringOtp = false;
  OtpDeliveryReceipt? _lastOtpReceipt;
  bool _isRegisterMode = false;
  bool _usePasswordLogin = true;

  bool _isForgotPasswordMode = false;
  bool _obscurePassword = true;
  String? _authErrorMessage;

  bool get _isAutomatedTestBinding {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTest');
  }

  @override
  void initState() {
    super.initState();
    _showStartup3dSplash = false;
    if (!_isAutomatedTestBinding) {
      unawaited(
        _store.startRealTimeDeviceGpsTracking(forcePromptPermission: true),
      );
    }
    _store.addListener(_onStoreUpdated);
  }

  void _onStoreUpdated() {
    if (!mounted) return;
    if (_isLoggedIn && _store.activeAuthenticatedUser?.status == 'LOCKED') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_isLoggedIn && _store.activeAuthenticatedUser?.status == 'LOCKED') {
          _store.clearAuthenticatedSession();
          setState(() {
            _isLoggedIn = false;
            _authErrorMessage =
                'Tài khoản của bạn đã bị Quản trị viên tạm khóa.';
          });
        }
      });
    }
    setState(() {});
  }

  bool _rejectAdminAccount(UserAccountRecord? user) {
    if (user?.role != SubsystemRole.admin) return false;
    setState(() {
      _authErrorMessage =
          'Tài khoản quản trị vui lòng đăng nhập tại cổng /admin.';
    });
    return true;
  }

  void _switchAuthView({bool register = false}) {
    _otpCountdownTimer?.cancel();
    setState(() {
      _isRegisterMode = register;
      _usePasswordLogin = !register;
      _isForgotPasswordMode = false;
      _otpSent = false;
      _authErrorMessage = null;
      _lastOtpReceipt = null;
      _passwordCtrl.clear();
      _otpCtrl.clear();
    });
  }

  void _startOtpCountdownTimer() {
    _otpCountdownTimer?.cancel();
    if (_isAutomatedTestBinding) return;
    _otpCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_otpSent) {
        timer.cancel();
        return;
      }
      final remain = _store.getRemainingOtpSeconds(_phoneCtrl.text);
      setState(() {});
      if (remain <= 0) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _otpCountdownTimer?.cancel();
    RealAuthDeliveryService.instance.stopGoogleOAuthServer();
    RealAuthDeliveryService.instance.stopMobileQrAuthServer();
    _store.removeListener(_onStoreUpdated);
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _fullNameCtrl.dispose();
    _passwordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _handlePasswordLogin(BuildContext context) {
    final rawInput = _phoneCtrl.text.trim();
    final rawPassword = _passwordCtrl.text.trim();
    if (rawInput.isEmpty) {
      setState(() {
        _authErrorMessage = 'Vui lòng nhập Số điện thoại hoặc Email đăng nhập.';
      });
      return;
    }
    if (rawPassword.length < 6) {
      setState(() {
        _authErrorMessage = 'Mật khẩu phải có từ 6 ký tự trở lên.';
      });
      return;
    }
    final existingUser = _store.findUserByPhoneOrEmail(rawInput);
    if (_rejectAdminAccount(existingUser)) return;
    if (existingUser == null) {
      setState(() {
        _authErrorMessage =
            'Tài khoản chưa được đăng ký. Vui lòng chuyển sang tab "Đăng ký".';
      });
      return;
    }
    if (existingUser.status == 'LOCKED') {
      setState(() {
        _authErrorMessage = 'Tài khoản của bạn hiện đang bị khóa tạm thời. Vui lòng liên hệ bộ phận hỗ trợ.';
      });
      return;
    }
    final authenticated = _store.authenticateWithPassword(
      phoneOrEmail: rawInput,
      password: rawPassword,
      activateSession: false,
    );
    if (authenticated == null) {
      setState(() {
        _authErrorMessage = 'Mật khẩu không chính xác. Vui lòng kiểm tra lại.';
      });
      return;
    }
    final canDeliverExternal2fa =
        EnvConfig.isExternalSmsGatewayConfigured ||
        (EnvConfig.isEmailOtpConfigured &&
            authenticated.email.contains('@') &&
            !authenticated.email.endsWith('@giaohanggps.vn')) ||
        _isAutomatedTestBinding;
    if (_store.isUserTwoFactorEnabled(authenticated.phone) &&
        canDeliverExternal2fa) {
      setState(() {
        _usePasswordLogin = false;
        _isForgotPasswordMode = false;
      });
      _handleSendOtp();
      return;
    }
    _store.applyAuthenticatedUserSession(authenticated);
    context.read<SystemArchitectureCubit>().selectRole(authenticated.role);
    setState(() {
      _authErrorMessage = null;
      _isLoggedIn = true;
      _otpSent = false;
      _isForgotPasswordMode = false;
    });
  }

  void _handleSendOtp() {
    if (!_store.isDatabaseReady) {
      setState(
        () => _authErrorMessage = 'Chưa mở được dữ liệu trên thiết bị. Vui lòng khởi động lại ứng dụng.',
      );
      return;
    }
    final rawInput = _phoneCtrl.text.trim();
    final isEmailInput = rawInput.contains('@');

    if (!_isRegisterMode) {
      if (isEmailInput) {
        if (!rawInput.contains('.') || rawInput.length < 5) {
          setState(() {
            _authErrorMessage = 'Vui lòng nhập địa chỉ Email hợp lệ.';
          });
          return;
        }
      } else {
        final digits = rawInput.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length < 9) {
          setState(() {
            _authErrorMessage =
                'Vui lòng nhập Số điện thoại (từ 9 chữ số) hoặc Email hợp lệ.';
          });
          return;
        }
      }

      final existingUser = _store.findUserByPhoneOrEmail(rawInput);
      if (_rejectAdminAccount(existingUser)) return;
      if (existingUser == null) {
        setState(() {
          _authErrorMessage = 'Tài khoản chưa tồn tại trên hệ thống. Vui lòng chuyển sang tab "Đăng ký" để tạo tài khoản mới.';
        });
        return;
      }
      if (existingUser.status == 'LOCKED') {
        setState(() {
          _authErrorMessage = 'Tài khoản của bạn hiện đang bị khóa tạm thời. Vui lòng liên hệ bộ phận hỗ trợ.';
        });
        return;
      }
    } else {
      if (_fullNameCtrl.text.trim().isEmpty) {
        setState(() {
          _authErrorMessage = 'Vui lòng nhập Họ và tên của bạn.';
        });
        return;
      }
      final digits = rawInput.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length < 9) {
        setState(() {
          _authErrorMessage =
              'Vui lòng nhập Số điện thoại hợp lệ (từ 9 chữ số).';
        });
        return;
      }
      final rawEmail = _emailCtrl.text.trim();
      if (rawEmail.isNotEmpty &&
          (!rawEmail.contains('@') || !rawEmail.contains('.'))) {
        setState(() {
          _authErrorMessage = 'Địa chỉ Email không hợp lệ (hoặc để trống nếu nhận OTP qua Số điện thoại).';
        });
        return;
      }
      if (_passwordCtrl.text.trim().length < 6) {
        setState(() {
          _authErrorMessage = 'Vui lòng tạo mật khẩu tối thiểu 6 ký tự.';
        });
        return;
      }
      final existingUser =
          _store.findUserByPhoneOrEmail(rawInput) ??
          (rawEmail.isNotEmpty
              ? _store.findUserByPhoneOrEmail(rawEmail)
              : null);
      if (existingUser != null) {
        setState(() {
          _authErrorMessage = 'Số điện thoại hoặc Email này đã được đăng ký. Vui lòng chuyển sang tab "Đăng nhập".';
        });
        return;
      }
    }

    final registerEmail = _emailCtrl.text.trim();
    if (_isRegisterMode &&
        registerEmail.isEmpty &&
        !EnvConfig.isExternalSmsGatewayConfigured &&
        !_isAutomatedTestBinding) {
      final created = _store.registerUserAccountWithRole(
        phone: rawInput,
        email: registerEmail,
        fullName: _fullNameCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
        role: SubsystemRole.customer,
      );
      if (created == null) {
        setState(() {
          _authErrorMessage = 'Không thể tạo tài khoản. Vui lòng thử lại.';
        });
        return;
      }
      context.read<SystemArchitectureCubit>().selectRole(created.role);
      setState(() {
        _authErrorMessage = null;
        _isLoggedIn = true;
        _otpSent = false;
      });
      return;
    }

    final otp = _store.generateOtpForPhone(rawInput);
    final String deliveryDestination;
    if (isEmailInput) {
      deliveryDestination = rawInput;
    } else if (_isRegisterMode &&
        registerEmail.isNotEmpty &&
        registerEmail.contains('@')) {
      if (EnvConfig.isExternalSmsGatewayConfigured) {
        deliveryDestination = rawInput;
        if (!_isAutomatedTestBinding && EnvConfig.isEmailOtpConfigured) {
          RealAuthDeliveryService.instance.deliverOtpChallenge(
            destination: registerEmail,
            otpCode: otp,
          );
        }
      } else {
        deliveryDestination = registerEmail;
      }
    } else if (!_isRegisterMode && !EnvConfig.isExternalSmsGatewayConfigured) {
      final existingUser = _store.findUserByPhoneOrEmail(rawInput);
      final linkedEmail = existingUser?.email.trim() ?? '';
      if (linkedEmail.contains('@') &&
          !linkedEmail.endsWith('@giaohanggps.vn')) {
        deliveryDestination = linkedEmail;
      } else {
        deliveryDestination = rawInput;
      }
    } else {
      deliveryDestination = rawInput;
    }

    setState(() {
      _authErrorMessage = null;
      _otpSent = true;
      _isDeliveringOtp = true;
      _lastOtpReceipt = null;
      _otpCtrl.clear();
    });
    _startOtpCountdownTimer();

    if (_isAutomatedTestBinding) {
      setState(() {
        _isDeliveringOtp = false;
      });
      return;
    }

    RealAuthDeliveryService.instance
        .deliverOtpChallenge(destination: deliveryDestination, otpCode: otp)
        .then((receipt) {
          if (!mounted) return;
          setState(() {
            _isDeliveringOtp = false;
            _lastOtpReceipt = receipt;
            if (!receipt.success) {
              _otpSent = false;
              _authErrorMessage = receipt.channel == 'SMS_NOT_CONFIGURED'
                  ? 'Chưa cấu hình cổng SMS cho số ${receipt.destination}. Hãy cấu hình SMS Gateway HTTP hoặc dùng mật khẩu.'
                  : receipt.message;
            }
          });
        });
  }

  Future<void> _handleVerifyOtpAndAuthenticate(BuildContext context) async {
    final rawInput = _phoneCtrl.text.trim();
    final inputOtp = _otpCtrl.text.trim();
    final cubit = context.read<SystemArchitectureCubit>();

    if (_rejectAdminAccount(_store.findUserByPhoneOrEmail(rawInput))) return;

    if (!_isAutomatedTestBinding &&
        _lastOtpReceipt?.channel == 'TWILIO_VERIFY_V2' &&
        inputOtp.length == 6) {
      final twilioOk = await RealAuthDeliveryService.instance
          .verifyTwilioVerifyV2Code(phoneNumber: rawInput, otpCode: inputOtp);
      if (twilioOk) {
        final normKey = EnvConfig.formatVietnamPhoneNational(rawInput);
        _store.activeOtpCodesByPhone[normKey] = inputOtp;
        _store.otpExpiryEpochMsByPhone[normKey] =
            DateTime.now().millisecondsSinceEpoch + 60000;
      }
      if (!mounted) return;
    }

    if (_rejectAdminAccount(_store.findUserByPhoneOrEmail(rawInput))) return;

    if (_isForgotPasswordMode) {
      final newPwd = _newPasswordCtrl.text.trim();
      if (newPwd.length < 6) {
        setState(() {
          _authErrorMessage = 'Vui lòng nhập mật khẩu mới tối thiểu 6 ký tự.';
        });
        return;
      }
      final updatedUser = _store.resetPasswordWithOtp(
        phoneOrEmail: rawInput,
        otpCode: inputOtp,
        newPassword: newPwd,
      );
      if (updatedUser == null) {
        setState(() {
          _authErrorMessage =
              'Mã xác thực OTP không chính xác hoặc đã hết hiệu lực (120s).';
        });
        return;
      }
      _otpCountdownTimer?.cancel();
      cubit.selectRole(updatedUser.role);
      setState(() {
        _authErrorMessage = null;
        _isForgotPasswordMode = false;
        _usePasswordLogin = false;
        _isLoggedIn = true;
        _otpSent = false;
      });
      return;
    }

    final verified = _store.verifyOtpCode(rawInput, inputOtp);
    if (!verified) {
      setState(() {
        _authErrorMessage =
            'Mã xác thực OTP không chính xác hoặc đã hết hiệu lực.';
      });
      return;
    }

    UserAccountRecord? user;
    if (_isRegisterMode) {
      final regPassword = _passwordCtrl.text.trim().length >= 6
          ? _passwordCtrl.text.trim()
          : inputOtp;
      user = _store.registerUserAccountWithRole(
        phone: rawInput,
        email: _emailCtrl.text.trim().isNotEmpty
            ? _emailCtrl.text.trim()
            : null,
        fullName: _fullNameCtrl.text.trim(),
        password: regPassword,
        role: SubsystemRole.customer,
      );
    } else {
      user = _store.findUserByPhoneOrEmail(rawInput);
      if (user != null) {
        _store.applyAuthenticatedUserSession(user);
      }
    }

    if (user == null) {
      setState(() {
        _authErrorMessage = 'Không thể xác thực tài khoản. Vui lòng thử lại.';
      });
      return;
    }

    _otpCountdownTimer?.cancel();
    cubit.selectRole(user.role);
    setState(() {
      _authErrorMessage = null;
      _isLoggedIn = true;
      _otpSent = false;
    });
  }

  Future<void> _handleOAuthLogin(
    BuildContext context,
    String providerName,
  ) async {
    if (!EnvConfig.isGoogleOAuthConfigured) {
      setState(() {
        _authErrorMessage = 'Đăng nhập Google chưa được cấu hình trên thiết bị này. Vui lòng liên hệ quản trị viên.';
      });
      return;
    }

    setState(() {
      _authErrorMessage = null;
    });

    final cubit = context.read<SystemArchitectureCubit>();
    bool dialogOpen = false;

    final authUrl = await RealAuthDeliveryService.instance
        .startGoogleOAuth2LoopbackFlow(
          openSystemBrowser: false,
          onAuthenticated: (result) {
            if (!mounted) return;
            if (dialogOpen) {
              dialogOpen = false;
              Navigator.of(context, rootNavigator: true).maybePop();
            }
            if (_rejectAdminAccount(
              _store.findUserByPhoneOrEmail(result.email),
            )) {
              return;
            }
            final user = _store.signInOrRegisterOAuthUser(
              email: result.email,
              fullName: result.fullName,
            );
            if (user == null) {
              setState(() {
                _authErrorMessage =
                    'Không thể đồng bộ tài khoản Google (${result.email}) vào hệ thống.';
              });
              return;
            }
            if (user.status == 'LOCKED') {
              setState(() {
                _authErrorMessage =
                    'Tài khoản ${user.email} hiện đang bị khóa tạm thời.';
              });
              return;
            }
            _store.applyAuthenticatedUserSession(user);
            cubit.selectRole(user.role);
            setState(() {
              _authErrorMessage = null;
              _isLoggedIn = true;
              _otpSent = false;
            });
          },
        );

    if (!mounted || !context.mounted) return;
    if (authUrl == null) {
      setState(() {
        _authErrorMessage = 'Không thể khởi tạo phiên kết nối Google OAuth 2.0. Vui lòng thử lại.';
      });
      return;
    }

    dialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return InAppGoogleOAuthDialog(
          initialAuthUrl: authUrl,
          onCancel: () {
            dialogOpen = false;
            Navigator.of(dialogCtx).pop();
          },
        );
      },
    );
    dialogOpen = false;
    await RealAuthDeliveryService.instance.stopGoogleOAuthServer();
  }

  void _handleLogout() {
    _otpCountdownTimer?.cancel();
    _store.clearAuthenticatedSession();
    setState(() {
      _isLoggedIn = false;
      _otpSent = false;
      _isRegisterMode = false;
      _usePasswordLogin = false;
      _isForgotPasswordMode = false;
      _authErrorMessage = null;
      _lastOtpReceipt = null;
      _phoneCtrl.clear();
      _emailCtrl.clear();
      _fullNameCtrl.clear();
      _passwordCtrl.clear();
      _newPasswordCtrl.clear();
      _otpCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showStartup3dSplash) {
      return Studio3dStartupSplashScreen(
        onCompleted: () {
          if (mounted) {
            setState(() => _showStartup3dSplash = false);
          }
        },
      );
    }

    return BlocBuilder<SystemArchitectureCubit, SystemArchitectureState>(
      builder: (context, state) {
        if (!_isLoggedIn ||
            _store.activeAuthenticatedUser == null ||
            _store.activeAuthenticatedUser?.role == SubsystemRole.admin) {
          return _buildUc01LoginRegisterScreen(context);
        }

        final authUser = _store.activeAuthenticatedUser;
        if (authUser != null && authUser.status == 'LOCKED') {
          return Scaffold(
            backgroundColor: AppColors.paper,
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.line),
                      boxShadow: AppColors.cardShadow,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const GhstButtonIcon(
                          Icons.lock_person_rounded,
                          color: AppColors.danger,
                          size: 46,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Tài khoản đã bị khóa tạm thời',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tài khoản ${authUser.fullName} (${authUser.phone}) hiện đang bị khóa bởi Quản trị viên hệ thống. Mọi thao tác nghiệp vụ đã được tạm dừng.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _handleLogout,
                            icon: const GhstButtonIcon(Icons.logout_rounded, size: 18),
                            label: const Text('Đăng xuất'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final unlockedRoles = authUser != null
            ? _store.unlockedRolesForUser(authUser)
            : <SubsystemRole>[state.selectedRole];
        final activeRole = unlockedRoles.contains(state.selectedRole)
            ? state.selectedRole
            : (authUser?.role ?? unlockedRoles.first);

        final hasUnlockedPartnerRole =
            unlockedRoles.length > 1 &&
            unlockedRoles.any(
              (r) => r == SubsystemRole.driver || r == SubsystemRole.merchant,
            );

        final roleAccent = switch (activeRole) {
          SubsystemRole.customer => AppColors.violet,
          SubsystemRole.driver => AppColors.success,
          SubsystemRole.merchant => AppColors.accent,
          SubsystemRole.admin => AppColors.primary,
        };

        return Scaffold(
          backgroundColor: AppColors.paper,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: Studio3dMainWorkspaceMapPainter(
                        accentColor: roleAccent,
                        lightweightBackdrop: true,
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasUnlockedPartnerRole)
                      _buildPostLoginStudioTopBar(
                        context,
                        unlockedRoles: unlockedRoles,
                        activeRole: activeRole,
                        hasUnlockedPartnerRole: hasUnlockedPartnerRole,
                      ),
                    Expanded(child: _buildActiveSubsystemView(activeRole)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUc01LoginRegisterScreen(BuildContext context) {
    return StudioUserAuthFrame(child: _buildNeoBrutalistAuthCard(context));
  }

  Widget _buildNeoBrutalistAuthCard(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StudioUserAuthBrand(),
        const SizedBox(height: 18),
        StudioAuthTabBar(
          loginSelected: !_isRegisterMode,
          onSelectLogin: () => _switchAuthView(),
          onSelectRegister: () => _switchAuthView(register: true),
        ),
        const SizedBox(height: 20),
        Text(
          _isRegisterMode
              ? 'Tạo tài khoản mới'
              : (_isForgotPasswordMode
                    ? 'Khôi phục mật khẩu bằng OTP'
                    : 'Đăng nhập hệ thống'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isRegisterMode
              ? 'Nhập Số điện thoại, Họ tên và Mật khẩu để tạo tài khoản'
              : (_isForgotPasswordMode
                    ? 'Nhập Số điện thoại hoặc Email để nhận mã OTP đặt lại mật khẩu'
                    : (_usePasswordLogin
                          ? 'Nhập Số điện thoại / Email và mật khẩu đã đăng ký'
                          : 'Nhập Số điện thoại hoặc Email để nhận mã xác thực OTP')),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        if (!_isRegisterMode) ...[
          Row(
            children: [
              Expanded(
                child: ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.glyph(GhstActionKind.key, size: 15, color: (!_usePasswordLogin && !_isForgotPasswordMode) ? const Color(0xFF1E3A8A) : AppColors.textSecondary), label: SizedBox(
                    width: double.infinity,
                    child: Text(
                      'Mã OTP',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: !_usePasswordLogin && !_isForgotPasswordMode
                            ? const Color(0xFF1E3A8A)
                            : AppColors.textSecondary,
                      ),
                    ),
                  ), selected: !_usePasswordLogin && !_isForgotPasswordMode, selectedColor: AppColors.primarySoft, backgroundColor: AppColors.surfaceSubtle, side: BorderSide(
                    color: !_usePasswordLogin && !_isForgotPasswordMode
                        ? AppColors.primaryBorder
                        : AppColors.line,
                  ), shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ), onSelected: (_) => setState(() {
                    _usePasswordLogin = false;
                    _isForgotPasswordMode = false;
                    _authErrorMessage = null;
                  }),),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.glyph(GhstActionKind.lock, size: 15, color: (_usePasswordLogin && !_isForgotPasswordMode) ? const Color(0xFF1E3A8A) : AppColors.textSecondary), label: SizedBox(
                    width: double.infinity,
                    child: Text(
                      'Mật khẩu',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _usePasswordLogin && !_isForgotPasswordMode
                            ? const Color(0xFF1E3A8A)
                            : AppColors.textSecondary,
                      ),
                    ),
                  ), selected: _usePasswordLogin && !_isForgotPasswordMode, selectedColor: AppColors.primarySoft, backgroundColor: AppColors.surfaceSubtle, side: BorderSide(
                    color: _usePasswordLogin && !_isForgotPasswordMode
                        ? AppColors.primaryBorder
                        : AppColors.line,
                  ), shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ), onSelected: (_) => setState(() {
                    _usePasswordLogin = true;
                    _isForgotPasswordMode = false;
                    _otpSent = false;
                    _authErrorMessage = null;
                  }),),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (_isRegisterMode) ...[
          TextField(
            controller: _fullNameCtrl,
            onChanged: (_) => setState(() => _authErrorMessage = null),
            decoration: const InputDecoration(
              hintText: 'Ví dụ: Nguyễn Văn A',
              labelText: 'Họ và tên',
              prefixIcon: GhstButtonIcon(
                Icons.person_outline_rounded,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _phoneCtrl,
          keyboardType: _isRegisterMode
              ? TextInputType.phone
              : TextInputType.emailAddress,
          onChanged: (_) {
            setState(() {
              _authErrorMessage = null;
              if (_otpSent) {
                _otpSent = false;
              }
            });
          },
          decoration: InputDecoration(
            hintText: _isRegisterMode
                ? 'Ví dụ: 0912345678'
                : 'Nhập SĐT (0912...) hoặc Email',
            labelText: _isRegisterMode
                ? 'Số điện thoại'
                : 'Số điện thoại hoặc Email',
            prefixIcon: GhstButtonIcon(
              _phoneCtrl.text.contains('@')
                  ? Icons.alternate_email_rounded
                  : Icons.phone_iphone_rounded,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        if (_isRegisterMode) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) {
              setState(() {
                _authErrorMessage = null;
                if (_otpSent) {
                  _otpSent = false;
                }
              });
            },
            decoration: const InputDecoration(
              hintText: 'Không bắt buộc (Ví dụ: ban@gmail.com)',
              labelText: 'Địa chỉ Email (Tùy chọn)',
              prefixIcon: GhstButtonIcon(
                Icons.email_outlined,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
        if (_isRegisterMode || _usePasswordLogin) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            onChanged: (_) => setState(() => _authErrorMessage = null),
            decoration: InputDecoration(
              hintText: 'Tối thiểu 6 ký tự',
              labelText: _isRegisterMode
                  ? 'Tạo mật khẩu đăng nhập'
                  : 'Mật khẩu',
              prefixIcon: const GhstButtonIcon(
                Icons.lock_outline_rounded,
                color: AppColors.textSecondary,
              ),
              suffixIcon: IconButton(
                icon: GhstButtonIcon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 19,
                  color: AppColors.textSecondary,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
        ],
        if (!_isRegisterMode && _usePasswordLogin) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(44, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => setState(() {
                _isForgotPasswordMode = true;
                _usePasswordLogin = false;
                _otpSent = false;
                _authErrorMessage = null;
              }),
              icon: const GhstButtonIcon.glyph(GhstActionKind.key, size: 16),

              label: const Text(
                'Quên mật khẩu? Lấy mã OTP qua SĐT / Email',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
        if (_otpSent && !_usePasswordLogin) ...[
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final remainSec = _store.getRemainingOtpSeconds(_phoneCtrl.text);
              final isEmailChannel = _lastOtpReceipt != null
                  ? (_lastOtpReceipt!.channel == 'EMAIL_SMTP' ||
                        _lastOtpReceipt!.channel == 'SMTP_TLS')
                  : _phoneCtrl.text.trim().contains('@');

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GhstButtonIcon(
                          isEmailChannel
                              ? Icons.mark_email_read_outlined
                              : Icons.sms_outlined,
                          size: 16,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _isDeliveringOtp
                                ? 'Đang gửi mã xác thực OTP thật...'
                                : (_lastOtpReceipt?.message ??
                                      'Mã xác thực OTP đã được gửi đi.'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: remainSec > 0
                                ? AppColors.success
                                : AppColors.danger,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            remainSec > 0
                                ? 'Hiệu lực: ${remainSec}s'
                                : 'Đã hết hạn (0s)',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _handleSendOtp,
                          child: const Text(
                            'Gửi lại mã',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              hintText: 'Nhập 6 chữ số',
              labelText: 'Mã xác thực OTP (6 chữ số)',
              counterText: '',
              prefixIcon: GhstButtonIcon(
                Icons.verified_user_outlined,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (_isForgotPasswordMode) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _newPasswordCtrl,
              obscureText: _obscurePassword,
              onChanged: (_) => setState(() => _authErrorMessage = null),
              decoration: const InputDecoration(
                hintText: 'Tối thiểu 6 ký tự',
                labelText: 'Mật khẩu mới',
                prefixIcon: GhstButtonIcon(
                  Icons.lock_reset_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
        if (_authErrorMessage != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.32),
              ),
            ),
            child: Text(
              _authErrorMessage!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              if (!_isRegisterMode &&
                  _usePasswordLogin &&
                  !_isForgotPasswordMode) {
                _handlePasswordLogin(context);
              } else if (!_otpSent) {
                _handleSendOtp();
              } else {
                _handleVerifyOtpAndAuthenticate(context);
              }
            },
            icon: GhstButtonIcon.forLabel(((!_isRegisterMode && _usePasswordLogin && !_isForgotPasswordMode)
                  ? 'Đăng nhập'
                  : (_otpSent
                        ? (_isRegisterMode
                              ? 'Xác nhận OTP & Tạo tài khoản'
                              : (_isForgotPasswordMode
                                    ? 'Đổi mật khẩu & Đăng nhập'
                                    : 'Xác nhận OTP & Đăng nhập'))
                        : (_isRegisterMode &&
                                  _emailCtrl.text.trim().isEmpty &&
                                  !EnvConfig.isExternalSmsGatewayConfigured &&
                                  !_isAutomatedTestBinding
                              ? 'Tạo tài khoản'
                              : 'Gửi mã OTP'))), size: 16),

            label: Text(
              ((!_isRegisterMode && _usePasswordLogin && !_isForgotPasswordMode)
                  ? 'Đăng nhập'
                  : (_otpSent
                        ? (_isRegisterMode
                              ? 'Xác nhận OTP & Tạo tài khoản'
                              : (_isForgotPasswordMode
                                    ? 'Đổi mật khẩu & Đăng nhập'
                                    : 'Xác nhận OTP & Đăng nhập'))
                        : (_isRegisterMode &&
                                  _emailCtrl.text.trim().isEmpty &&
                                  !EnvConfig.isExternalSmsGatewayConfigured &&
                                  !_isAutomatedTestBinding
                              ? 'Tạo tài khoản'
                              : 'Gửi mã OTP'))),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Row(
          children: [
            Expanded(child: Divider(color: AppColors.line)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'hoặc',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(child: Divider(color: AppColors.line)),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.ink,
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.controlBorder),
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => _showMobileQrPhoneAuthDialog(context),
            icon: const GhstButtonIcon.glyph(
              GhstActionKind.scanner,
              size: 18,
              color: AppColors.primary,
            ),
            label: const Text(
              'Đăng nhập bằng mã QR',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
        if (EnvConfig.isGoogleOAuthConfigured) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.controlBorder),
                minimumSize: const Size.fromHeight(48),
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => _handleOAuthLogin(context, 'Google'),
              icon: const GhstButtonIcon.glyph(
                GhstActionKind.google,
                size: 19,
              ),
              label: const Text(
                'Tiếp tục với Google',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ],
        if (_isRegisterMode) ...[
          const SizedBox(height: 14),
          const Text(
            'Bạn muốn trở thành Đối tác Tài xế hoặc Cửa hàng? Hãy đăng ký tài khoản rồi gửi hồ sơ tại mục Cá nhân.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showMobileQrPhoneAuthDialog(BuildContext context) async {
    final cubit = context.read<SystemArchitectureCubit>();
    final initialPhone = _phoneCtrl.text.trim();

    if (!mounted) return;
    setState(() {
      _authErrorMessage = null;
    });

    bool isDialogOpen = true;
    String scanStatusText = 'Đang chờ quét mã QR...';
    bool isDeviceConnected = false;
    String? public4gHttpsUrl;
    void Function(void Function())? dialogSetState;

    final session = await RealAuthDeliveryService.instance
        .startMobileQrAuthSession(
          initialPhone: initialPhone,
          onAuthenticateMobileRequest:
              ({
                required String mode,
                required String phoneOrEmail,
                required String password,
                required String deviceToken,
                required String fullName,
              }) {
                final trimmedId = phoneOrEmail.trim();
                if (_store.findUserByPhoneOrEmail(trimmedId)?.role ==
                    SubsystemRole.admin) {
                  return const MobileQrAuthVerificationResult(
                    ok: false,
                    error: 'Tài khoản quản trị vui lòng đăng nhập tại cổng /admin.',
                  );
                }
                if (trimmedId.isEmpty) {
                  return const MobileQrAuthVerificationResult(
                    ok: false,
                    error: 'Vui lòng nhập Số điện thoại hoặc Email.',
                  );
                }

                if (mode == 'TOKEN') {
                  final existing = _store.findUserByPhoneOrEmail(trimmedId);
                  if (existing == null) {
                    return const MobileQrAuthVerificationResult(
                      ok: false,
                      tokenExpired: true,
                      error: 'Tài khoản không tồn tại trên hệ thống.',
                    );
                  }
                  if (existing.status == 'LOCKED') {
                    return const MobileQrAuthVerificationResult(
                      ok: false,
                      error: 'Tài khoản này hiện đang bị khóa tạm thời.',
                    );
                  }
                  final expectedToken =
                      SecurityAndBarcodeUtils.generatePaymentSignature(
                        orderCode: existing.phone,
                        amount: 2026,
                        method: existing.passwordHash,
                      );
                  if (deviceToken.trim() != expectedToken) {
                    return const MobileQrAuthVerificationResult(
                      ok: false,
                      tokenExpired: true,
                      error: 'Phiên đăng nhập đã hết hiệu lực. Vui lòng nhập lại mật khẩu.',
                    );
                  }
                  _store.applyAuthenticatedUserSession(existing);
                  return MobileQrAuthVerificationResult(
                    ok: true,
                    phone: existing.phone,
                    fullName: existing.fullName,
                    roleTitle: existing.role.title,
                    deviceToken: expectedToken,
                  );
                }

                if (mode == 'REGISTER') {
                  final normPhone = EnvConfig.formatVietnamPhoneNational(
                    trimmedId,
                  );
                  if (!RegExp(r'^0(3|5|7|8|9)[0-9]{8}$').hasMatch(normPhone)) {
                    return const MobileQrAuthVerificationResult(
                      ok: false,
                      error: 'Số điện thoại không hợp lệ (cần 10 chữ số).',
                    );
                  }
                  if (fullName.trim().isEmpty) {
                    return const MobileQrAuthVerificationResult(
                      ok: false,
                      error: 'Vui lòng nhập Họ và tên.',
                    );
                  }
                  if (password.trim().length < 6) {
                    return const MobileQrAuthVerificationResult(
                      ok: false,
                      error: 'Mật khẩu phải có từ 6 ký tự trở lên.',
                    );
                  }
                  if (_store.findUserByPhoneOrEmail(normPhone) != null) {
                    return const MobileQrAuthVerificationResult(
                      ok: false,
                      error: 'Số điện thoại này đã được đăng ký.',
                    );
                  }
                  final created = _store.registerUserAccountWithRole(
                    phone: normPhone,
                    fullName: fullName.trim(),
                    password: password.trim(),
                    role: SubsystemRole.customer,
                  );
                  if (created == null) {
                    return const MobileQrAuthVerificationResult(
                      ok: false,
                      error: 'Không thể tạo tài khoản. Vui lòng thử lại.',
                    );
                  }
                  final issuedToken =
                      SecurityAndBarcodeUtils.generatePaymentSignature(
                        orderCode: created.phone,
                        amount: 2026,
                        method: created.passwordHash,
                      );
                  return MobileQrAuthVerificationResult(
                    ok: true,
                    phone: created.phone,
                    fullName: created.fullName,
                    roleTitle: created.role.title,
                    deviceToken: issuedToken,
                  );
                }

                final existing = _store.findUserByPhoneOrEmail(trimmedId);
                if (existing == null) {
                  return const MobileQrAuthVerificationResult(
                    ok: false,
                    error: 'Tài khoản chưa tồn tại.',
                  );
                }
                if (existing.status == 'LOCKED') {
                  return const MobileQrAuthVerificationResult(
                    ok: false,
                    error: 'Tài khoản này hiện đang bị khóa tạm thời.',
                  );
                }
                final authed = _store.authenticateWithPassword(
                  phoneOrEmail: trimmedId,
                  password: password.trim(),
                  activateSession: false,
                );
                if (authed == null) {
                  return const MobileQrAuthVerificationResult(
                    ok: false,
                    error: 'Mật khẩu không chính xác.',
                  );
                }
                final issuedToken =
                    SecurityAndBarcodeUtils.generatePaymentSignature(
                      orderCode: authed.phone,
                      amount: 2026,
                      method: authed.passwordHash,
                    );
                return MobileQrAuthVerificationResult(
                  ok: true,
                  phone: authed.phone,
                  fullName: authed.fullName,
                  roleTitle: authed.role.title,
                  deviceToken: issuedToken,
                );
              },
          onEvent: (event) {
            if (!mounted) return;
            if (event.status == 'TUNNEL_READY') {
              public4gHttpsUrl = event.deviceUserAgent;
              dialogSetState?.call(() {});
              return;
            }
            if (event.status == 'SCANNED') {
              isDeviceConnected = true;
              scanStatusText =
                  'Đã quét mã QR — Vui lòng xác nhận trên điện thoại';
              dialogSetState?.call(() {});
              return;
            }
            if (event.status == 'CONFIRMED') {
              final confirmedPhone = EnvConfig.formatVietnamPhoneNational(
                event.phoneNumber,
              );
              if (isDialogOpen && Navigator.of(context).canPop()) {
                isDialogOpen = false;
                Navigator.of(context).pop();
              }
              RealAuthDeliveryService.instance.stopMobileQrAuthServer();

              final user = _store.findUserByPhoneOrEmail(confirmedPhone);
              if (_rejectAdminAccount(user)) return;
              if (user != null) {
                final needs2fa =
                    _store.isUserTwoFactorEnabled(user.phone) &&
                    (EnvConfig.isExternalSmsGatewayConfigured ||
                        (EnvConfig.isEmailOtpConfigured &&
                            user.email.contains('@') &&
                            !user.email.endsWith('@giaohanggps.vn')));
                if (needs2fa) {
                  final otp = _store.generateOtpForPhone(user.phone);
                  final dest = EnvConfig.isExternalSmsGatewayConfigured
                      ? user.phone
                      : user.email;
                  setState(() {
                    _phoneCtrl.text = user.phone;
                    _usePasswordLogin = false;
                    _isRegisterMode = false;
                    _isForgotPasswordMode = false;
                    _otpSent = true;
                    _isDeliveringOtp = true;
                    _authErrorMessage = null;
                    _otpCtrl.clear();
                  });
                  _startOtpCountdownTimer();
                  RealAuthDeliveryService.instance
                      .deliverOtpChallenge(destination: dest, otpCode: otp)
                      .then((receipt) {
                        if (!mounted) return;
                        setState(() {
                          _isDeliveringOtp = false;
                          _lastOtpReceipt = receipt;
                        });
                      });
                  return;
                }
                _store.applyAuthenticatedUserSession(user);
                _otpCountdownTimer?.cancel();
                cubit.selectRole(user.role);
                setState(() {
                  _phoneCtrl.text = user.phone;
                  _authErrorMessage = null;
                  _isLoggedIn = true;
                  _otpSent = false;
                  _isForgotPasswordMode = false;
                });
              }
            }
          },
        );

    if (!context.mounted) return;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) {
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              dialogSetState = setModalState;
              final activeQrPayload =
                  (public4gHttpsUrl != null && public4gHttpsUrl!.isNotEmpty)
                  ? public4gHttpsUrl!
                  : session.buildVerifyUrl(session.lanIp);

              return AlertDialog(
                backgroundColor: AppColors.surface,
                surfaceTintColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: AppColors.line),
                ),
                title: const Row(
                  children: [
                    GhstButtonIcon(
                      Icons.qr_code_scanner_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Đăng nhập bằng mã QR',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 340,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Mở Camera điện thoại hoặc Zalo để quét mã QR',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.line),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: QrMatrixPainterWidget(
                          payload: activeQrPayload,
                          size: 196,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: isDeviceConnected
                              ? const Color(0xFFECFDF5)
                              : AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Text(
                          scanStatusText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton.icon(
                    onPressed: () {
                      isDialogOpen = false;
                      RealAuthDeliveryService.instance.stopMobileQrAuthServer();
                      Navigator.of(dialogCtx).pop();
                    },
                    icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

                    label: const Text(
                      'Đóng',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      isDialogOpen = false;
      await RealAuthDeliveryService.instance.stopMobileQrAuthServer();
    }
  }

  Widget _buildPostLoginStudioTopBar(
    BuildContext context, {
    required List<SubsystemRole> unlockedRoles,
    required SubsystemRole activeRole,
    required bool hasUnlockedPartnerRole,
  }) {
    final cubit = context.read<SystemArchitectureCubit>();
    final authUser = _store.activeAuthenticatedUser;
    String labelForRole(SubsystemRole r) {
      return switch (r) {
        SubsystemRole.customer => 'Khách hàng',
        SubsystemRole.driver => 'Đối tác Tài xế',
        SubsystemRole.merchant => 'Cửa hàng B2B',
        SubsystemRole.admin => 'Quản trị',
      };
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.techBg,
        border: Border(bottom: BorderSide(color: AppColors.ink, width: 1.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 6,
        children: [
          const StudioMarkWordmark(
            light: true,
            title: 'Giao Hàng Siêu Tốc',
            suffix: '',
            badgeTag: 'GHST',
          ),
          if (hasUnlockedPartnerRole)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                const Text(
                  'Vai trò làm việc:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.techMuted,
                  ),
                ),
                for (final roleOption in unlockedRoles)
                  ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel(labelForRole(roleOption), size: 15, color: (activeRole == roleOption) && roleOption != SubsystemRole.customer ? Colors.white : AppColors.ink), visualDensity: VisualDensity.compact, shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                      side: const BorderSide(color: AppColors.techLine),
                    ), label: Text(
                      labelForRole(roleOption),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color:
                            activeRole == roleOption &&
                                roleOption != SubsystemRole.customer
                            ? Colors.white
                            : AppColors.ink,
                      ),
                    ), selected: activeRole == roleOption, selectedColor: roleOption == SubsystemRole.customer
                        ? AppColors.acid
                        : AppColors.violet, backgroundColor: AppColors.paper, onSelected: (_) {
                      if (authUser != null) {
                        _store.applyAuthenticatedUserSession(
                          authUser,
                          activeWorkspaceRole: roleOption,
                        );
                      }
                      cubit.selectRole(roleOption);
                    },),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildActiveSubsystemView(SubsystemRole role) {
    switch (role) {
      case SubsystemRole.customer:
        return CustomerSubsystemEntry(onLogout: _handleLogout);
      case SubsystemRole.driver:
        return DriverSubsystemEntry(onLogout: _handleLogout);
      case SubsystemRole.merchant:
        return MerchantSubsystemEntry(onLogout: _handleLogout);
      case SubsystemRole.admin:
        return _buildUc01LoginRegisterScreen(context);
    }
  }
}
