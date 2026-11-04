import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import '../../core/auth/real_auth_delivery_service.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import 'ghst_button_icon.dart';

class InAppGoogleOAuthDialog extends StatefulWidget {
  final String initialAuthUrl;
  final VoidCallback onCancel;

  const InAppGoogleOAuthDialog({
    super.key,
    required this.initialAuthUrl,
    required this.onCancel,
  });

  @override
  State<InAppGoogleOAuthDialog> createState() => _InAppGoogleOAuthDialogState();
}

class _InAppGoogleOAuthDialogState extends State<InAppGoogleOAuthDialog> {
  WebviewController? _winController;
  WebViewController? _mobileController;
  StreamSubscription<String>? _winUrlSub;
  StreamSubscription<LoadingState>? _winLoadingSub;

  bool _isInitialized = false;
  bool _isLoadingPage = true;
  bool _isCompletingCallback = false;
  String _currentUrl = 'https://accounts.google.com';
  String? _initError;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialAuthUrl;
    _initEmbeddedWebView();
  }

  bool get _isWindowsNative =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get _isMobileNative =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _initEmbeddedWebView() async {
    try {
      if (_isWindowsNative) {
        final ctrl = WebviewController();
        _winController = ctrl;
        await ctrl.initialize();
        if (!mounted) {
          await ctrl.dispose();
          return;
        }
        await ctrl.setBackgroundColor(Colors.white);
        await ctrl.setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
        await ctrl.setUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        );
        if (!mounted) return;

        _winUrlSub = ctrl.url.listen((url) {
          if (!mounted) return;
          final isCallback =
              url.contains('/oauth2callback') && url.contains('code=');
          setState(() {
            _currentUrl = url;
            if (isCallback) {
              _isCompletingCallback = true;
            }
          });
          if (isCallback) {
            RealAuthDeliveryService.instance.tryProcessOAuthCallbackUrl(url);
          }
        });

        _winLoadingSub = ctrl.loadingState.listen((state) {
          if (!mounted) return;
          setState(() {
            _isLoadingPage = state == LoadingState.loading;
          });
        });

        if (!mounted) return;
        await ctrl.loadUrl(widget.initialAuthUrl);
        if (!mounted) return;
        setState(() {
          _isInitialized = true;
        });
      } else if (_isMobileNative) {
        final ctrl = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.white)
          ..setUserAgent(
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
          )
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (url) {
                if (!mounted) return;
                final isCallback =
                    url.contains('/oauth2callback') && url.contains('code=');
                setState(() {
                  _currentUrl = url;
                  _isLoadingPage = true;
                  if (isCallback) {
                    _isCompletingCallback = true;
                  }
                });
                if (isCallback) {
                  RealAuthDeliveryService.instance
                      .tryProcessOAuthCallbackUrl(url);
                }
              },
              onPageFinished: (_) {
                if (!mounted) return;
                setState(() {
                  _isLoadingPage = false;
                });
              },
            ),
          )
          ..loadRequest(Uri.parse(widget.initialAuthUrl));

        _mobileController = ctrl;
        if (!mounted) return;
        setState(() {
          _isInitialized = true;
        });
      } else {
        await RealAuthDeliveryService.instance.launchUrlInSystemBrowser(
          widget.initialAuthUrl,
        );
        if (!mounted) return;
        setState(() {
          _isLoadingPage = false;
          _initError =
              'Đã mở trang xác thực Google OAuth 2.0 trên trình duyệt hệ thống. '
              'Sau khi chọn tài khoản, phiên đăng nhập sẽ tự động đồng bộ về ứng dụng.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPage = false;
        _initError =
            'Không thể khởi tạo trình duyệt nhúng trong ứng dụng: $e. '
            'Bạn có thể tiếp tục xác thực trực tiếp qua trình duyệt hệ thống.';
      });
    }
  }

  @override
  void dispose() {
    _winUrlSub?.cancel();
    _winLoadingSub?.cancel();
    _winController?.dispose();
    super.dispose();
  }

  Future<void> _reloadPage() async {
    setState(() {
      _isLoadingPage = true;
      _initError = null;
    });
    if (_isWindowsNative && _winController != null) {
      await _winController!.reload();
    } else if (_mobileController != null) {
      await _mobileController!.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final displayHost =
        Uri.tryParse(_currentUrl)?.host ?? 'accounts.google.com';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 520,
          maxHeight: 680,
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: tokens.cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: tokens.border),
            boxShadow: tokens.elevatedShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: tokens.cardSubtle,
                  border: Border(
                    bottom: BorderSide(color: tokens.border),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tokens.border),
                      ),
                      child: const Text(
                        'G',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          color: Color(0xFFEA4335),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Đăng nhập bằng Google',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: tokens.ink,
                            ),
                          ),
                          Row(
                            children: [
                              GhstButtonIcon(
                                Icons.lock_rounded,
                                size: 11,
                                color: tokens.emerald.icon,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'https://$displayHost',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'Consolas',
                                    fontWeight: FontWeight.w700,
                                    color: tokens.inkSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tải lại trang',
                      onPressed: _reloadPage,
                      icon: GhstButtonIcon(
                        Icons.refresh_rounded,
                        size: 19,
                        color: tokens.ink,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng',
                      onPressed: () {
                        RealAuthDeliveryService.instance.stopGoogleOAuthServer();
                        widget.onCancel();
                      },
                      icon: GhstButtonIcon(
                        Icons.close_rounded,
                        size: 20,
                        color: tokens.ink,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoadingPage)
                LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: tokens.canvas,
                  color: tokens.primary,
                ),
              Expanded(
                child: _buildWebViewBody(tokens),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebViewBody(GhstThemeTokens tokens) {
    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GhstButtonIcon(
                Icons.open_in_browser_rounded,
                color: tokens.primary,
                size: 42,
              ),
              const SizedBox(height: 12),
              Text(
                _initError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tokens.ink,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  RealAuthDeliveryService.instance.launchUrlInSystemBrowser(
                    widget.initialAuthUrl,
                  );
                },
                icon: const GhstButtonIcon(Icons.launch_rounded, size: 18),
                label: const Text('Mở xác thực trên trình duyệt hệ thống'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: tokens.primary),
            const SizedBox(height: 14),
            Text(
              'Đang kết nối tới accounts.google.com...',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: tokens.ink,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: _isWindowsNative
              ? Webview(_winController!)
              : WebViewWidget(controller: _mobileController!),
        ),
        if (_isCompletingCallback)
          Positioned.fill(
            child: Container(
              color: tokens.cardSurface.withValues(alpha: 0.92),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: tokens.primary),
                  const SizedBox(height: 14),
                  Text(
                    'Đang xác thực tài khoản Google với hệ thống...',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: tokens.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
