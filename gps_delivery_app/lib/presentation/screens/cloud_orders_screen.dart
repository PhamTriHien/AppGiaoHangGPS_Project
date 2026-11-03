import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/integrations/cloud_orders_service.dart';
import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/delivery_api_client.dart';
import '../../core/integrations/push_notification_service.dart';
import '../../core/network/public_json_api.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/repositories/cloud_orders_repository.dart';
import '../widgets/cloud_order_form.dart';
import '../widgets/cloud_pricing_dialog.dart';
import '../widgets/cloud_commerce_dialog.dart';
import '../widgets/cloud_logistics_panels.dart';
import '../widgets/cloud_notification_center.dart';
import '../widgets/cloud_profile_form.dart';
import '../widgets/cloud_membership_panel.dart';
import '../widgets/cloud_membership_decision_dialog.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/cloud_order_labels.dart';
import 'cloud_address_book_screen.dart';
import 'cloud_order_details_screen.dart';
import 'cloud_pickup_screen.dart';
import 'marketplace_view.dart';
import 'market_order_services_screen.dart';

export '../widgets/cloud_order_labels.dart' show cloudStatuses, cloudActions;

const cloudRoles = cloudAccountRoles;

class CloudOrdersScreen extends StatefulWidget {
  const CloudOrdersScreen({
    super.key,
    this.service,
    this.session,
    this.admin = false,
    this.embedded = false,
    this.showAccountsToggle = true,
    this.initialQueue = false,
  });
  final CloudOrdersService? service;
  final CloudAccountSession? session;
  final bool admin;
  final bool embedded;
  final bool showAccountsToggle;
  final bool initialQueue;
  @override
  State<CloudOrdersScreen> createState() => _CloudOrdersScreenState();
}

class _CloudOrdersScreenState extends State<CloudOrdersScreen>
    with WidgetsBindingObserver {
  late final _api =
      widget.session?.service ?? widget.service ?? CloudOrdersService();
  late final _session = widget.session ?? CloudAccountSession(service: _api);
  late final CloudOrdersRepository _repository;
  Timer? _poll;
  Object? _pushWatcher;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _search = TextEditingController();
  Map<String, dynamic>? get _account => _session.account;
  List<Map<String, dynamic>> get _orders => _repository.orders;
  List<Map<String, dynamic>> get _accounts => _repository.accounts;
  List<Map<String, dynamic>> get _merchants => _repository.merchants;
  bool get _operator => widget.admin && _session.isOperator;
  bool get _loaded => _session.verified;
  bool _busy = false, _register = false;
  late bool _queue = widget.initialQueue;
  bool _accountsView = false;
  bool get _hasMore => _repository.hasMore;
  String? _error, _notice;
  int _generation = 0;
  int _sessionRevision = 0;
  bool _loading = false;
  bool _foreground = true;
  int get _schemaVersion => _session.schemaVersion;
  String _statusFilter = '', _accountFilter = '';

  @override
  void initState() {
    super.initState();
    assert(
      widget.service == null ||
          widget.session == null ||
          identical(widget.service, widget.session!.service),
    );
    WidgetsBinding.instance.addObserver(this);
    _session.start();
    _sessionRevision = _session.revision;
    _repository = CloudOrdersRepository(session: _session, admin: widget.admin);
    _session.addListener(_onSessionChanged);
    if (!widget.embedded) {
      _pushWatcher = PushNotificationService.instance.attachWatcher(_session);
    }
    _load();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted &&
          _foreground &&
          !_busy &&
          _loaded &&
          _orders.length <= 50 &&
          !_accountsView &&
          _api.signedIn &&
          ModalRoute.of(context)?.isCurrent != false) {
        _load(silent: true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant CloudOrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQueue != oldWidget.initialQueue) {
      final targetQueue = widget.initialQueue && _session.hasRole('driver');
      if (_queue != targetQueue) {
        setState(() {
          _queue = targetQueue;
          _repository.clear();
        });
        if (_foreground && _api.signedIn && !_loading && !_busy) {
          unawaited(_load());
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_foreground) return;
      _foreground = true;
      DeliveryApiClient.instance.resetConnectionPool();
      _generation++;
      _loading = false;
      _busy = false;
      _repository.cancelPending();
      unawaited(_load(silent: _loaded));
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (!_foreground) return;
      _foreground = false;
      _generation++;
      _loading = false;
      _busy = false;
      _repository.cancelPending();
    }
  }

  void _onSessionChanged() {
    if (!mounted) return;
    if (_sessionRevision != _session.revision) {
      _sessionRevision = _session.revision;
      _generation++;
      setState(() {
        _repository.clear();
        _busy = false;
        _queue = widget.initialQueue;
        _accountsView = false;
        _search.clear();
        _statusFilter = '';
        _accountFilter = '';
        _password.clear();
        _error = _session.error == null ? null : _message(_session.error!);
        _notice = null;
      });
      if (_foreground && _api.signedIn && _session.error == null && !_loading) {
        scheduleMicrotask(() {
          if (mounted) _load();
        });
      }
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    if (_pushWatcher != null) {
      PushNotificationService.instance.detachWatcher(_pushWatcher!);
    }
    _session.removeListener(_onSessionChanged);
    _repository.dispose();
    if (widget.session == null) _session.dispose();
    _email.dispose();
    _password.dispose();
    _search.dispose();
    super.dispose();
  }

  String _message(Object error) {
    if (!widget.admin &&
        error is PublicApiException &&
        error.statusCode == 503) {
      return 'Dịch vụ đơn hàng tạm thời chưa khả dụng. Vui lòng thử lại sau.';
    }
    if (error is PublicApiException) return error.message;
    if (error is AuthException) return error.message;
    return 'Không hoàn tất được yêu cầu. Kiểm tra kết nối và thử lại.';
  }

  List<Map<String, dynamic>> _rows(dynamic value) => (value as List? ?? [])
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  Future<void> _load({bool silent = false, bool more = false}) async {
    if (!_foreground || !_api.signedIn || _busy || _loading) return;
    _loading = true;
    final generation = _generation;
    final identity = _api.identityScope;
    setState(() {
      _busy = true;
      if (!silent) _error = null;
    });
    try {
      await _session.refresh();
      if (!mounted ||
          generation != _generation ||
          identity != _api.identityScope) {
        return;
      }
      if (_operator || _session.canUseBusiness && !widget.admin) {
        final useQueue = _queue && _session.hasRole('driver');
        if (_queue != useQueue) _queue = useQueue;
        await _repository.load(
          view: _accountsView
              ? CloudOrderView.accounts
              : useQueue
              ? CloudOrderView.queue
              : CloudOrderView.orders,
          more: more,
        );
      } else {
        _repository.clear();
      }
      if (!mounted ||
          generation != _generation ||
          identity != _api.identityScope) {
        return;
      }
      setState(() {
        _error = null;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = _message(error);
        });
      }
    } finally {
      if (generation == _generation) {
        _loading = false;
        if (mounted) setState(() => _busy = false);
      } else if (!_loading && mounted && _session.error == null) {
        _load();
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _loading) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _authenticate() async {
    if (!_email.text.contains('@') ||
        _password.text.length < (_register ? 8 : 6)) {
      setState(
        () => _error =
            'Nhập email và mật khẩu hợp lệ, đăng ký tối thiểu 8 ký tự.',
      );
      return;
    }
    await _run(() async {
      final notice = await _api.authenticate(
        _email.text,
        _password.text,
        register: _register,
      );
      if (mounted) {
        setState(() {
          _notice = notice;
          _password.clear();
        });
      }
    });
    if (mounted && _error == null) await _load();
  }

  Future<void> _create() async {
    final identity = _api.identityScope;
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => CloudSessionBoundary(
          session: _session,
          roles: const {'customer', 'merchant'},
          builder: (_, lease) => CloudOrderForm(
            service: _api,
            merchants: _merchants,
            lease: lease,
          ),
        ),
      ),
    );
    if (mounted && identity == _api.identityScope) await _load();
  }

  Future<void> _profile() async {
    final identity = _api.identityScope;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudSessionBoundary(
          session: _session,
          profile: true,
          builder: (page, lease) => Scaffold(
            appBar: AppBar(title: const Text('Hồ sơ cá nhân')),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: CloudProfileForm(
                    session: _session,
                    lease: lease,
                    onSaved: () => Navigator.of(page).pop(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted && identity == _api.identityScope) await _load();
  }

  Future<void> _transition(Map<String, dynamic> order, String action) async {
    final identity = _api.identityScope;
    final generation = _generation;
    String reason = '';
    if (['cancel', 'fail', 'return'].contains(action)) {
      final controller = TextEditingController();
      final result = await _privateDialog<String>(
        builder: (dialog) => AlertDialog(
          title: Text(cloudActions[action]!),
          content: TextField(
            controller: controller,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Lý do'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Quay lại'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, controller.text.trim()),
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      );
      // A dialog's reverse animation may still retain its text controller.
      Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
      if (result == null || !mounted) return;
      if (result.length < 3) {
        setState(() => _error = 'Lý do cần ít nhất 3 ký tự.');
        return;
      }
      reason = result;
    } else if (action == 'deliver' &&
        (((order['details'] as Map?)?['require_pod'] == true) ||
            ((order['details'] as Map?)?['require_otp'] == true))) {
      final needPod = (order['details'] as Map?)?['require_pod'] == true;
      final needOtp = (order['details'] as Map?)?['require_otp'] == true;
      var podUploaded = (order['pod_photo_path'] as String? ?? '').isNotEmpty;
      var uploading = false;
      String? dialogError;
      final otpCtrl = TextEditingController();
      final otpResult = await _privateDialog<String>(
        builder: (dialog) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Xác thực giao hàng'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (uploading) const LinearProgressIndicator(),
                  if (dialogError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        dialogError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (needPod) ...[
                    OutlinedButton.icon(
                      onPressed: uploading
                          ? null
                          : () async {
                              final file = await openFile(
                                acceptedTypeGroups: const [
                                  XTypeGroup(
                                    label: 'Ảnh POD',
                                    extensions: ['jpg', 'jpeg', 'png', 'webp'],
                                  ),
                                ],
                              );
                              if (file == null) return;
                              if (await file.length() > 5000000) {
                                update(
                                  () => dialogError = 'Ảnh tối đa 5 MB.',
                                );
                                return;
                              }
                              update(() {
                                uploading = true;
                                dialogError = null;
                              });
                              try {
                                await _api.uploadPod(
                                  trackingCode: '${order['tracking_code']}',
                                  bytes: await file.readAsBytes(),
                                );
                                if (dialog.mounted) {
                                  update(() {
                                    uploading = false;
                                    podUploaded = true;
                                  });
                                }
                              } catch (e) {
                                if (dialog.mounted) {
                                  update(() {
                                    uploading = false;
                                    dialogError = _message(e);
                                  });
                                }
                              }
                            },
                      icon: Icon(
                        podUploaded
                            ? Icons.check_circle_outline
                            : Icons.camera_alt_outlined,
                      ),
                      label: Text(
                        podUploaded
                            ? 'Đã tải lên ảnh POD'
                            : 'Tải ảnh bằng chứng giao hàng',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (needOtp)
                    TextField(
                      controller: otpCtrl,
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Mã OTP 6 số từ người nhận',
                        border: OutlineInputBorder(),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Quay lại'),
              ),
              FilledButton(
                onPressed: uploading
                    ? null
                    : () {
                        if (needPod && !podUploaded) {
                          update(
                            () => dialogError =
                                'Cần tải ảnh POD trước khi hoàn tất giao.',
                          );
                          return;
                        }
                        final otp = otpCtrl.text.trim();
                        if (needOtp && !RegExp(r'^[0-9]{6}$').hasMatch(otp)) {
                          update(
                            () => dialogError = 'Nhập đúng 6 chữ số mã OTP.',
                          );
                          return;
                        }
                        Navigator.pop(dialog, needOtp ? otp : '');
                      },
                child: const Text('Đã giao'),
              ),
            ],
          ),
        ),
      );
      Future<void>.delayed(const Duration(seconds: 1), otpCtrl.dispose);
      if (otpResult == null || !mounted) return;
      reason = otpResult;
    } else if (action == 'deliver' || action == 'complete_return') {
      final confirmed = await _privateDialog<bool>(
        builder: (dialog) => AlertDialog(
          title: Text(
            action == 'deliver'
                ? 'Xác nhận giao thành công'
                : 'Xác nhận hoàn hàng',
          ),
          content: Text(
            action == 'deliver'
                ? 'Hàng đã được giao cho người nhận?'
                : 'Hàng đã được trả lại cho người gửi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Quay lại'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(action == 'deliver' ? 'Đã giao' : 'Đã hoàn hàng'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (!mounted ||
        identity != _api.identityScope ||
        generation != _generation) {
      return;
    }
    await _run(() async {
      await _api.command('orders/${order['id']}/transition', {
        'action': action,
        'version': order['version'],
        'reason': reason,
      });
    });
    if (mounted && _error == null) await _load();
  }

  Future<void> _history(Map<String, dynamic> order) async {
    final identity = _api.identityScope;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CloudSessionBoundary(
          session: _session,
          operator: _operator,
          builder: (_, lease) => CloudOrderDetailsScreen(
            lease: lease,
            order: order,
            merchants: _merchants,
          ),
        ),
      ),
    );
    if (mounted && identity == _api.identityScope) await _load();
  }

  Future<void> _pricing() => _run(() async {
    final identity = _api.identityScope;
    final generation = _generation;
    final data = await _api.request('pricing');
    if (!mounted ||
        identity != _api.identityScope ||
        generation != _generation) {
      return;
    }
    await showDialog<bool>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: _session,
        operator: true,
        dialog: true,
        builder: (_, lease) => CloudPricingDialog(
          service: _api,
          pricing: Map<String, dynamic>.from(data['pricing'] as Map),
          lease: lease,
        ),
      ),
    );
  });

  Future<void> _audit() => _run(() async {
    final identity = _api.identityScope;
    final generation = _generation;
    final data = await _api.request('audit');
    if (!mounted ||
        identity != _api.identityScope ||
        generation != _generation) {
      return;
    }
    await _privateDialog<void>(
      operator: true,
      builder: (dialog) => AlertDialog(
        title: const Text('Nhật ký điều hành'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in _rows(data['entries']))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SelectableText(
                      '${entry['action'] == 'pricing' ? 'Cập nhật bảng giá' : 'Đổi quyền / khóa tài khoản'}\n${entry['target_id'] ?? ''}\n${_date(entry['created_at'])}\n${entry['actor_id']}',
                    ),
                  ),
                if (_rows(data['entries']).isEmpty)
                  const Text('Chưa có thay đổi.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  });

  String _date(dynamic value) => cloudDate(value);

  Widget _field(
    TextEditingController controller,
    String label, {
    bool password = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: controller,
      enabled: !_busy,
      obscureText: password,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _authForm() => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.admin
              ? 'Đăng nhập quản trị'
              : (_register ? 'Đăng ký tài khoản' : 'Đăng nhập'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 20),
        _field(_email, 'Email', keyboard: TextInputType.emailAddress),
        _field(_password, 'Mật khẩu', password: true),
        FilledButton(
          onPressed: _busy ? null : _authenticate,
          child: Text(_register ? 'Tạo tài khoản' : 'Đăng nhập'),
        ),
        if (!widget.admin)
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _register = !_register;
                    _error = null;
                  }),
            child: Text(_register ? 'Đã có tài khoản' : 'Đăng ký tài khoản'),
          ),
      ],
    ),
  );

  Widget _profileForm() => CloudProfileForm(
    key: ValueKey('${_api.identityScope}:${_session.revision}'),
    session: _session,
    onSaved: () => unawaited(_load()),
  );

  Widget _order(Map<String, dynamic> order) {
    final details = Map<String, dynamic>.from(order['details'] as Map? ?? {});
    final status = order['status'];
    final isDriver = _session.hasRole('driver');
    final mine = order['driver_id'] == _api.userId;
    final creator =
        order['owner_id'] == _api.userId || order['merchant_id'] == _api.userId;
    final carrier = order['fulfillment_provider'] == 'ghn';
    final actions = <String, String>{
      if (_queue && isDriver && !carrier) 'claim': 'Nhận chuyến',
      if (!_queue &&
          !carrier &&
          status == 'searching' &&
          order['merchant_ready'] != true &&
          (_operator || order['merchant_id'] == _api.userId))
        'ready': 'Sẵn sàng lấy hàng',
      if (!_queue && !carrier && (mine || _operator)) ...{
        if (status == 'accepted') 'arrive': 'Đã đến lấy hàng',
        if (status == 'arrivingPickup') 'pickup': 'Đã lấy hàng',
        if (status == 'inTransit') 'deliver': 'Giao thành công',
        if (status == 'returning' && _schemaVersion >= 2)
          'complete_return': 'Đã trả hàng cho người gửi',
        if (status == 'inTransit') 'fail': 'Giao thất bại',
        if (status == 'failed') 'retry': 'Giao lại',
        if (status == 'failed') 'return': 'Hoàn hàng',
      },
      if (!_queue &&
          !carrier &&
          (creator || _operator) &&
          ['searching', 'accepted', 'arrivingPickup'].contains(status))
        'cancel': 'Hủy đơn',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            '${order['tracking_code']}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            carrier && status == 'searching'
                ? 'Chờ GHN lấy hàng'
                : order['merchant_ready'] == false && status == 'searching'
                ? 'Chờ cửa hàng xác nhận'
                : cloudStatuses[status] ?? '$status',
          ),
          const SizedBox(height: 8),
          if (details['pickup_address'] != null) ...[
            Text('Lấy: ${details['pickup_address']}'),
            Text('Giao: ${details['dropoff_address']}'),
            Text(
              '${details['recipient_name']} · ${details['recipient_phone']}',
            ),
            Text(
              '${details['package_description']} · ${details['weight_kg']} kg',
            ),
          ] else
            Text(
              '${details['weight_kg']} kg · ${cloudServiceTypes[details['service_type']] ?? 'Tiêu chuẩn'}',
            ),
          Text(
            'Phí: ${CurrencyFormatter.formatVnd((order['shipping_fee'] as num).toDouble())} · COD: ${CurrencyFormatter.formatVnd((order['cod_amount'] as num).toDouble())}',
          ),
          if (!_queue && ((order['coin_discount'] as num? ?? 0) > 0))
            Text(
              'Đổi Xu giảm cước: -${CurrencyFormatter.formatVnd((order['coin_discount'] as num).toDouble())} · Cần thanh toán: ${CurrencyFormatter.formatVnd(((order['payable_fee'] ?? order['shipping_fee']) as num).toDouble())}',
              style: TextStyle(
                color: Colors.green.shade800,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (!_queue)
            Text(
              '${details['payment_method'] == 'sender_cash' ? 'Người gửi trả phí' : 'Người nhận trả phí'} · ${order['payment_status'] == 'PAID'
                  ? 'Đã thanh toán cước'
                  : order['payment_status'] == 'REVIEW'
                  ? 'Cần đối soát'
                  : 'Chưa ghi nhận thanh toán cước'}',
            ),
          if (carrier)
            Text(
              'GHN: ${order['carrier_code'] ?? 'Chờ hãng xác nhận'} · ${order['carrier_status'] ?? 'Đang tạo vận đơn'}',
            ),
          Text(
            _date(order['created_at']),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (order['cancel_reason'] != null)
            Text('Lý do hủy: ${order['cancel_reason']}'),
          if ('${order['delivery_instruction'] ?? ''}'.isNotEmpty)
            Text(
              'Chỉ dẫn giao: ${order['delivery_instruction']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!_queue && (creator || _operator))
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _commerce(order),
                  icon: const Icon(Icons.payment),
                  label: const Text('Thanh toán cước'),
                ),
              if (!_queue && (carrier || _operator))
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _commerce(order, shipment: true),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Vận chuyển GHN'),
                ),
              for (final action in actions.entries)
                OutlinedButton(
                  onPressed: _busy || _schemaVersion < 2
                      ? null
                      : () => _transition(order, action.key),
                  child: Text(action.value),
                ),
              if (!_queue)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _history(order),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Chi tiết'),
                ),
              if (!_queue &&
                  !carrier &&
                  order['owner_id'] == _api.userId &&
                  CloudDeliveryInstructionButton.editableStatuses.contains(
                    status,
                  ))
                CloudDeliveryInstructionButton(
                  service: _api,
                  order: order,
                  onUpdated: () => unawaited(_load()),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<T?> _privateDialog<T>({
    required WidgetBuilder builder,
    bool operator = false,
  }) => showDialog<T>(
    context: context,
    builder: (_) => CloudSessionBoundary(
      session: _session,
      operator: operator,
      dialog: true,
      builder: (dialog, _) => builder(dialog),
    ),
  );

  Future<void> _commerce(
    Map<String, dynamic> order, {
    bool shipment = false,
  }) async {
    final identity = _api.identityScope;
    await showDialog<void>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: _session,
        operator: _operator,
        dialog: true,
        builder: (_, lease) => CloudCommerceDialog(
          service: _api,
          order: order,
          shipment: shipment,
          operator: _operator,
          lease: lease,
        ),
      ),
    );
    if (mounted && identity == _api.identityScope) await _load();
  }

  Future<void> _updateAccount(
    Map<String, dynamic> account,
    String role,
    bool blocked,
  ) async {
    final identity = _api.identityScope;
    final generation = _generation;
    final blockChanged = blocked != (account['blocked'] == true);
    final title = blockChanged
        ? (blocked ? 'Khóa tài khoản' : 'Mở khóa tài khoản')
        : (role == account['role'] && account['requested_role'] != null
              ? 'Từ chối yêu cầu vai trò'
              : 'Cấp quyền ${cloudRoles[role]}');
    final confirmed = await _privateDialog<bool>(
      operator: true,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text('${account['full_name']}\n${account['phone']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        identity != _api.identityScope ||
        generation != _generation) {
      return;
    }
    await _run(() async {
      await _api.request(
        'accounts/${account['user_id']}',
        body: {'role': role, 'blocked': blocked},
      );
    });
    if (mounted && _error == null) await _load();
  }

  Widget _accountRow(Map<String, dynamic> account) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${account['full_name']} · ${account['phone']}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        SelectableText(
          '${account['user_id']}',
          style: const TextStyle(fontSize: 12),
        ),
        Text(
          '${_schemaVersion >= 3 ? ['Khách hàng', for (final role in account['approved_roles'] as List? ?? []) cloudRoles[role]].join(' · ') : cloudRoles[account['role']]}${account['blocked'] == true ? ' · Đang khóa' : ''}',
        ),
        if (_schemaVersion >= 3) _membershipControls(account),
        if (_schemaVersion < 3 && account['requested_role'] != null)
          Text('Chờ duyệt: ${cloudRoles[account['requested_role']]}'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_schemaVersion < 3 && account['requested_role'] != null) ...[
              OutlinedButton.icon(
                onPressed: _busy || _schemaVersion < 2
                    ? null
                    : () => _updateAccount(
                        account,
                        '${account['requested_role']}',
                        account['blocked'] == true,
                      ),
                icon: const Icon(Icons.check),
                label: Text('Duyệt ${cloudRoles[account['requested_role']]}'),
              ),
              IconButton(
                tooltip: 'Từ chối yêu cầu vai trò',
                onPressed: _busy || _schemaVersion < 2
                    ? null
                    : () => _updateAccount(
                        account,
                        '${account['role']}',
                        account['blocked'] == true,
                      ),
                icon: const Icon(Icons.close),
              ),
            ],
            if (_schemaVersion < 3)
              PopupMenuButton<String>(
                tooltip: 'Phân quyền tài khoản',
                enabled: !_busy && _schemaVersion >= 2,
                icon: const Icon(Icons.manage_accounts_outlined),
                itemBuilder: (_) => cloudRoles.entries
                    .map(
                      (e) => PopupMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onSelected: (role) =>
                    _updateAccount(account, role, account['blocked'] == true),
              ),
            IconButton(
              tooltip: account['blocked'] == true
                  ? 'Mở khóa tài khoản'
                  : 'Khóa tài khoản',
              icon: Icon(
                account['blocked'] == true
                    ? Icons.lock_open
                    : Icons.lock_outline,
              ),
              onPressed: _busy || _schemaVersion < 2
                  ? null
                  : () => _updateAccount(
                      account,
                      '${account['role']}',
                      account['blocked'] != true,
                    ),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _updateMembership(
    Map<String, dynamic> account,
    Map<String, dynamic> membership,
    String decision,
  ) async {
    final identity = _api.identityScope, generation = _generation;
    final title =
        '${switch (decision) {
          'approve' => 'Duyệt',
          'reject' => 'Từ chối',
          _ => 'Thu hồi',
        }} ${cloudRoles[membership['role']]}';
    final reason = await _privateDialog<String>(
      operator: true,
      builder: (_) => CloudMembershipDecisionDialog(
        title: title,
        accountName: '${account['full_name']}',
        reasonRequired: decision != 'approve',
      ),
    );
    if (reason == null ||
        !mounted ||
        identity != _api.identityScope ||
        generation != _generation) {
      return;
    }
    await _run(() async {
      await _api.request(
        'accounts/${account['user_id']}/memberships/${membership['role']}',
        body: {
          'decision': decision,
          'version': membership['version'],
          'reason': reason,
        },
      );
    });
    if (mounted && _error == null) await _load();
  }

  Widget _membershipControls(Map<String, dynamic> account) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final membership in _rows(account['memberships']))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${cloudRoles[membership['role']]} · ${partnerStateNames[membership['state']]}',
                  ),
                  if (membership['state'] == 'pending') ...[
                    IconButton(
                      tooltip: 'Duyệt ${cloudRoles[membership['role']]}',
                      icon: const Icon(Icons.check),
                      onPressed: _busy || account['blocked'] == true
                          ? null
                          : () => _updateMembership(
                              account,
                              membership,
                              'approve',
                            ),
                    ),
                    IconButton(
                      tooltip: 'Từ chối ${cloudRoles[membership['role']]}',
                      icon: const Icon(Icons.close),
                      onPressed: _busy || account['blocked'] == true
                          ? null
                          : () => _updateMembership(
                              account,
                              membership,
                              'reject',
                            ),
                    ),
                  ],
                  if (membership['state'] == 'active')
                    IconButton(
                      tooltip: 'Thu hồi ${cloudRoles[membership['role']]}',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: _busy || account['blocked'] == true
                          ? null
                          : () => _updateMembership(
                              account,
                              membership,
                              'revoke',
                            ),
                    ),
                ],
              ),
              if ((membership['reason'] as String? ?? '').isNotEmpty)
                Text(membership['reason'] as String),
            ],
          ),
        ),
    ],
  );

  bool _matches(Map<String, dynamic> row, Iterable<String> keys) {
    final query = _search.text.trim().toLowerCase();
    return query.isEmpty ||
        keys.any((key) => '${row[key] ?? ''}'.toLowerCase().contains(query));
  }

  List<Map<String, dynamic>> get _visibleAccounts => _accounts.where((a) {
    final filtered = switch (_accountFilter) {
      'pending' =>
        _schemaVersion >= 3
            ? _rows(a['memberships']).any((m) => m['state'] == 'pending')
            : a['requested_role'] != null,
      'blocked' => a['blocked'] == true,
      '' => true,
      _ =>
        _schemaVersion >= 3
            ? _accountFilter == 'customer' ||
                  (a['approved_roles'] as List? ?? []).contains(_accountFilter)
            : a['role'] == _accountFilter,
    };
    return filtered && _matches(a, ['full_name', 'phone', 'user_id']);
  }).toList();

  List<Map<String, dynamic>> get _visibleOrders => _orders.where((o) {
    if (_statusFilter.isNotEmpty && o['status'] != _statusFilter) return false;
    final details = Map<String, dynamic>.from(o['details'] as Map? ?? {});
    return _matches(
      {...details, 'tracking_code': o['tracking_code']},
      [
        'tracking_code',
        'recipient_name',
        'recipient_phone',
        'pickup_address',
        'dropoff_address',
      ],
    );
  }).toList();

  Widget _filters({required bool accounts}) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: constraints.maxWidth < 600 ? constraints.maxWidth : 360,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: accounts
                  ? 'Tìm tài khoản đã tải'
                  : 'Tìm đơn hàng đã tải',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Xóa tìm kiếm',
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.close),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        SizedBox(
          width: constraints.maxWidth < 600 ? constraints.maxWidth : 240,
          child: DropdownButtonFormField<String>(
            key: ValueKey(accounts),
            initialValue: accounts ? _accountFilter : _statusFilter,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: accounts ? 'Vai trò / duyệt' : 'Trạng thái',
              border: const OutlineInputBorder(),
            ),
            items:
                (accounts
                        ? {
                            '': 'Tất cả',
                            'pending': 'Chờ duyệt',
                            'blocked': 'Đang khóa',
                            ...cloudRoles,
                          }
                        : {'': 'Tất cả', ...cloudStatuses})
                    .entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
            onChanged: (value) => setState(() {
              if (accounts) {
                _accountFilter = value!;
              } else {
                _statusFilter = value!;
              }
            }),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final blocked = _account?['blocked'] == true;
    final visibleAccounts = _visibleAccounts;
    final visibleOrders = _visibleOrders;
    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_api.signedIn && !widget.embedded) ...[
                Text(
                  widget.admin ? '${_api.email} · ${_api.project}' : _api.email,
                ),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_account != null)
                      Text(
                        _session.approvedRoles
                            .map((r) => cloudRoles[r])
                            .join(' · '),
                      ),
                    if (_operator) const Text('Operator'),
                    if (_operator) ...[
                      IconButton(
                        tooltip: 'Đối soát và hậu mãi',
                        onPressed: _busy
                            ? null
                            : () => openMarketOrderServices(
                                context,
                                _session,
                                operator: true,
                              ),
                        icon: const Icon(Icons.account_balance_outlined),
                      ),
                      IconButton(
                        tooltip: 'Duyệt cửa hàng',
                        onPressed: _busy
                            ? null
                            : () => openMarketplaceView(
                                context,
                                _session,
                                MarketView.moderation,
                              ),
                        icon: const Icon(Icons.fact_check_outlined),
                      ),
                      IconButton(
                        tooltip: 'Bảng giá cước',
                        onPressed: _busy || _schemaVersion < 2
                            ? null
                            : _pricing,
                        icon: const Icon(Icons.price_change_outlined),
                      ),
                      IconButton(
                        tooltip: 'Nhật ký điều hành',
                        onPressed: _busy ? null : _audit,
                        icon: const Icon(Icons.history),
                      ),
                    ],
                    IconButton(
                      tooltip: 'Tải lại đơn hàng',
                      onPressed: _busy ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                    if (_account != null && !blocked)
                      IconButton(
                        tooltip: 'Sổ địa chỉ',
                        icon: const Icon(Icons.contact_mail_outlined),
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => CloudSessionBoundary(
                                    session: _session,
                                    builder: (_, lease) =>
                                        CloudAddressBookScreen(
                                          service: _api,
                                          lease: lease,
                                        ),
                                  ),
                                ),
                              ),
                      ),
                    if (_account != null) ...[
                      ListenableBuilder(
                        listenable: PushNotificationService.instance,
                        builder: (context, _) {
                          final unread =
                              PushNotificationService.instance.unreadCount;
                          return IconButton(
                            tooltip: 'Trung tâm thông báo',
                            onPressed: _busy || blocked
                                ? null
                                : () => openCloudNotificationCenter(
                                    context,
                                    _session,
                                    operator: _operator,
                                    onOpenProfile: _profile,
                                  ),
                            icon: Badge.count(
                              count: unread,
                              isLabelVisible: unread > 0,
                              child: const Icon(
                                Icons.notifications_none_rounded,
                              ),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Thông tin tài khoản',
                        icon: const Icon(Icons.person_outline),
                        onPressed: _busy || blocked ? null : _profile,
                      ),
                    ],
                    IconButton(
                      tooltip: 'Đăng xuất',
                      onPressed: _busy ? null : () => _run(_api.signOut),
                      icon: const Icon(Icons.logout),
                    ),
                  ],
                ),
                if (_account?['requested_role'] != null)
                  Text(
                    'Chờ duyệt vai trò ${cloudRoles[_account!['requested_role']]}',
                  ),
                const Divider(),
                if (_loaded && _schemaVersion < 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _operator
                          ? 'Cơ sở dữ liệu cần cập nhật trước khi đổi quyền, bảng giá hoặc trạng thái đơn.'
                          : 'Hệ thống đang bảo trì. Vui lòng thử lại sau.',
                    ),
                  ),
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SelectableText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_notice!),
                ),
              if (!_api.signedIn)
                Align(alignment: Alignment.centerLeft, child: _authForm())
              else if (widget.admin && _loaded && !_operator)
                const Text('Tài khoản chưa có quyền quản trị.')
              else if (blocked && !_operator)
                const Text('Tài khoản đang bị khóa.')
              else if (_loaded && _account == null && !_operator)
                Align(alignment: Alignment.centerLeft, child: _profileForm())
              else if (_loaded) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.embedded)
                      IconButton(
                        tooltip: 'Tải lại đơn hàng',
                        onPressed: _busy ? null : _load,
                        icon: const Icon(Icons.refresh),
                      ),
                    if (_account != null &&
                        _session.canCreateShippingOrder &&
                        !_accountsView)
                      FilledButton.icon(
                        onPressed: _busy ? null : _create,
                        icon: const Icon(Icons.add),
                        label: const Text('Tạo đơn hàng'),
                      ),
                    if (_operator || _session.hasRole('driver'))
                      IconButton(
                        tooltip: 'Lịch xe thu gom',
                        onPressed: _busy
                            ? null
                            : () => openCloudPickups(
                                context,
                                _session,
                                operator: _operator,
                              ),
                        icon: const Icon(Icons.local_shipping_outlined),
                      ),
                    if (!widget.admin && _session.hasRole('driver'))
                      IconButton(
                        tooltip: 'Thống kê giao hàng',
                        onPressed: _busy
                            ? null
                            : () => openCloudDeliveryStats(context, _session),
                        icon: const Icon(Icons.insights_outlined),
                      ),
                    if (_session.hasRole('driver'))
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Chuyến của tôi'),
                          ),
                          ButtonSegment(value: true, label: Text('Chờ nhận')),
                        ],
                        selected: {_queue},
                        onSelectionChanged: _busy
                            ? null
                            : (value) {
                                setState(() {
                                  _queue = value.first;
                                  _repository.clear();
                                });
                                _load();
                              },
                      ),
                    if (_operator && widget.showAccountsToggle)
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Đơn hàng')),
                          ButtonSegment(value: true, label: Text('Tài khoản')),
                        ],
                        selected: {_accountsView},
                        onSelectionChanged: _busy
                            ? null
                            : (value) {
                                setState(() {
                                  _accountsView = value.first;
                                  _repository.clear();
                                  _search.clear();
                                  _statusFilter = '';
                                  _accountFilter = '';
                                });
                                _load();
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_accountsView && _operator) ...[
                  _filters(accounts: true),
                  const SizedBox(height: 12),
                  if (_accounts.isNotEmpty)
                    Text(
                      'Hiển thị ${visibleAccounts.length} / ${_accounts.length} tài khoản đã tải',
                    ),
                  if (_accounts.isEmpty) const Text('Chưa có hồ sơ tài khoản.'),
                  if (_accounts.isNotEmpty && visibleAccounts.isEmpty)
                    const Text('Không có tài khoản phù hợp.'),
                  for (final account in visibleAccounts) ...[
                    _accountRow(account),
                    const Divider(),
                  ],
                ] else ...[
                  if (_orders.isNotEmpty) ...[
                    _filters(accounts: false),
                    const SizedBox(height: 12),
                    Text(
                      'Hiển thị ${visibleOrders.length} / ${_orders.length} đơn đã tải',
                    ),
                    if (visibleOrders.isEmpty)
                      const Text('Không có đơn hàng phù hợp.'),
                  ],
                  if (_orders.isEmpty && !_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Chưa có đơn hàng.'),
                    ),
                  for (final order in visibleOrders) ...[
                    _order(order),
                    const Divider(height: 1),
                  ],
                  if (_hasMore)
                    TextButton(
                      onPressed: _busy ? null : () => _load(more: true),
                      child: const Text('Tải thêm'),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
    if (widget.embedded) return content;
    final screen = Scaffold(
      appBar: AppBar(
        title: Text(widget.admin ? 'Điều hành vận đơn' : 'Đơn hàng'),
      ),
      body: SafeArea(child: content),
    );
    if (!widget.admin) return screen;
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087F5B)),
        scaffoldBackgroundColor: const Color(0xFFF4F6F5),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF12342A),
        ),
      ),
      child: screen,
    );
  }
}
