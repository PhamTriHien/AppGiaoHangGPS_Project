import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/integrations/cloud_orders_service.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/cloud_order_labels.dart';

/// Màn hình Tra cứu & Theo dõi Hành trình Cloud công khai (/track).
/// Tra cứu trực tiếp từ Cloud bằng liên kết chia sẻ 64 ký tự hex hoặc
/// Mã vận đơn Cloud (CL-...) kèm 4 số cuối SĐT người nhận, bảo mật tuyệt đối dữ liệu cá nhân.
class PublicOrderTrackingScreen extends StatefulWidget {
  final String? initialQuery;
  final CloudOrdersService? cloudService;

  const PublicOrderTrackingScreen({
    super.key,
    this.initialQuery,
    this.cloudService,
  });

  static String? _extractQueryParamRaw(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final regexMatch = RegExp(
      r'[?&](?:code|token)=([^&]+)',
    ).firstMatch(trimmed);
    if (regexMatch != null) {
      final rawVal = regexMatch.group(1)?.trim() ?? '';
      if (rawVal.isNotEmpty) {
        try {
          return Uri.decodeQueryComponent(rawVal).trim();
        } catch (_) {
          return rawVal;
        }
      }
    }
    final parsed = Uri.tryParse(trimmed);
    final code =
        parsed?.queryParameters['code'] ?? parsed?.queryParameters['token'];
    if (code != null && code.trim().isNotEmpty) {
      return code.trim();
    }
    return null;
  }

  static String? extractQueryFromRouteName(String? routeName) {
    if (routeName != null && routeName.trim().isNotEmpty) {
      final fromRoute = _extractQueryParamRaw(routeName);
      if (fromRoute != null && fromRoute.isNotEmpty) {
        return fromRoute;
      }
    }
    final baseCode =
        Uri.base.queryParameters['code'] ?? Uri.base.queryParameters['token'];
    if (baseCode != null && baseCode.trim().isNotEmpty) {
      return baseCode.trim();
    }
    final frag = Uri.base.fragment;
    if (frag.isNotEmpty) {
      final fromFrag = _extractQueryParamRaw(
        frag.startsWith('/') ? frag : '/$frag',
      );
      if (fromFrag != null && fromFrag.isNotEmpty) {
        return fromFrag;
      }
    }
    return null;
  }

  @override
  State<PublicOrderTrackingScreen> createState() =>
      _PublicOrderTrackingScreenState();
}

class _PublicOrderTrackingScreenState extends State<PublicOrderTrackingScreen> {
  late final CloudOrdersService _service =
      widget.cloudService ?? CloudOrdersService();
  late final TextEditingController _searchCtrl;
  final TextEditingController _last4Ctrl = TextEditingController();
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _lookupData;
  Map<String, dynamic>? _shareData;
  String _activeQuery = '';

  bool _isShareToken(String q) => RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(q);

  @override
  void initState() {
    super.initState();
    final initial =
        widget.initialQuery ??
        PublicOrderTrackingScreen.extractQueryFromRouteName(null) ??
        '';
    _activeQuery = initial.trim();
    _searchCtrl = TextEditingController(text: _activeQuery);
    if (_isShareToken(_activeQuery)) {
      _submitSearch();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _last4Ctrl.dispose();
    super.dispose();
  }

  Future<void> _submitSearch() async {
    if (_busy) return;
    final query = _searchCtrl.text.trim();
    final last4 = _last4Ctrl.text.trim();
    setState(() {
      _activeQuery = query;
      _error = null;
      _lookupData = null;
      _shareData = null;
    });
    if (query.isEmpty) return;
    if (_isShareToken(query)) {
      setState(() => _busy = true);
      try {
        final res = await _service.publicTracking(query.toLowerCase());
        if (mounted) setState(() => _shareData = res);
      } catch (e) {
        if (mounted) {
          setState(
            () => _error = e is PublicApiException
                ? e.message
                : 'Liên kết chia sẻ không tồn tại hoặc đã hết hạn.',
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final upper = query.toUpperCase();
    if (!RegExp(r'^CL-[A-F0-9]{32}$').hasMatch(upper) ||
        !RegExp(r'^[0-9]{4}$').hasMatch(last4)) {
      setState(
        () => _error =
            'Nhập đúng mã vận đơn và đủ 4 số cuối SĐT người nhận, hoặc dán mã chia sẻ 64 ký tự.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await _service.publicLookup(upper, last4);
      if (mounted) setState(() => _lookupData = res);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Không tìm thấy vận đơn khớp thông tin xác thực.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typingToken = _isShareToken(_searchCtrl.text.trim());
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.line),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.radar_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Tra cứu & Theo dõi Hành trình Trực tiếp',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  Navigator.of(context).pushReplacementNamed('/');
                }
              },
              icon: const Icon(
                Icons.home_outlined,
                size: 17,
                color: AppColors.primary,
              ),
              label: const Text(
                'Trang chủ',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TRA CỨU HÀNH TRÌNH VẬN ĐƠN BẢO MẬT',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          letterSpacing: 0.3,
                          color: AppColors.primaryInk,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Nhập mã vận đơn kèm 4 số cuối SĐT người nhận, hoặc dán mã chia sẻ 64 ký tự. Địa chỉ, SĐT đầy đủ và mã OTP nhận hàng luôn được bảo mật.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 620;
                          final codeField = TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _submitSearch(),
                            decoration: const InputDecoration(
                              labelText: 'Mã vận đơn hoặc mã chia sẻ',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                          );
                          final phoneField = TextField(
                            controller: _last4Ctrl,
                            enabled: !typingToken && !_busy,
                            maxLength: 4,
                            keyboardType: TextInputType.number,
                            onSubmitted: (_) => _submitSearch(),
                            decoration: const InputDecoration(
                              labelText: '4 số cuối SĐT nhận',
                              counterText: '',
                              prefixIcon: Icon(Icons.pin_outlined),
                            ),
                          );
                          final button = FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _busy ? null : _submitSearch,
                            icon: const Icon(
                              Icons.gps_fixed_rounded,
                              size: 17,
                            ),
                            label: const Text('Tra cứu'),
                          );
                          if (wide) {
                            return Row(
                              children: [
                                Expanded(flex: 5, child: codeField),
                                const SizedBox(width: 10),
                                Expanded(flex: 2, child: phoneField),
                                const SizedBox(width: 10),
                                button,
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              codeField,
                              const SizedBox(height: 10),
                              phoneField,
                              const SizedBox(height: 10),
                              button,
                            ],
                          );
                        },
                      ),
                      if (_busy) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  _buildStatusBox(
                    title: 'Không tra cứu được vận đơn',
                    subtitle: _error!,
                    icon: Icons.find_in_page_outlined,
                  )
                else if (_lookupData != null)
                  _buildCloudLookupDetail(_lookupData!)
                else if (_shareData != null)
                  _buildShareDetail(_shareData!)
                else
                  _buildStatusBox(
                    title: 'Sẵn sàng tra cứu hành trình trực tiếp',
                    subtitle:
                        'Nhập mã vận đơn và 4 số cuối SĐT người nhận, hoặc mở liên kết chia sẻ từ người gửi để xem tiến độ giao hàng thời gian thực.',
                    icon: Icons.share_location_rounded,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBox({
    required String title,
    required String subtitle,
    required IconData icon,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.line),
      boxShadow: AppColors.cardShadow,
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primaryBorder),
          ),
          child: Icon(icon, size: 28, color: AppColors.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildCloudLookupDetail(Map<String, dynamic> data) {
    final status = '${data['status'] ?? 'searching'}';
    final service = '${data['service_type'] ?? 'standard'}';
    final meters = (data['distance_meters'] as num? ?? 0).toDouble();
    final timeline = (data['timeline'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final isSearching = status == 'searching';
    final isAccepted = status == 'accepted' || status == 'arrivingPickup';
    final isInTransit = status == 'inTransit';
    final isDelivered = status == 'delivered';
    final isCancelled = status == 'cancelled';
    final code = '${data['tracking_code']}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    'Vận đơn $code • ${cloudServiceTypes[service] ?? service}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    '${cloudStatuses[status] ?? status}'
                    '${meters > 0 ? ' • Lộ trình ${(meters / 1000).toStringAsFixed(1)} km' : ''}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã sao chép mã vận đơn.')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Sao chép mã'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.spaceAround,
              children: [
                _buildStepPill(
                  '1. Đã tạo đơn',
                  done: !isSearching && !isCancelled,
                  active: isSearching,
                ),
                _buildStepPill(
                  '2. Tài xế nhận',
                  done: isInTransit || isDelivered,
                  active: isAccepted,
                ),
                _buildStepPill(
                  '3. Đang giao',
                  done: isDelivered,
                  active: isInTransit,
                ),
                _buildStepPill(
                  '4. Hoàn thành',
                  done: isDelivered,
                  active: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tạo lúc: ${cloudDate(data['created_at'])} · Cập nhật: ${cloudDate(data['updated_at'])}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const Divider(height: 24),
          const Text(
            'NHẬT KÝ HÀNH TRÌNH XÁC THỰC',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          if (timeline.isEmpty)
            const Text('Chưa có mốc cập nhật hành trình.'),
          for (final item in timeline)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: AppColors.violet,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${cloudActions[item['action']] ?? item['action']} — ${cloudStatuses[item['status']] ?? item['status']}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    cloudDate(item['created_at']),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShareDetail(Map<String, dynamic> data) {
    const marketStates = {
      'pending': 'Chờ cửa hàng xác nhận',
      'accepted': 'Đang chuẩn bị',
      'ready': 'Đang vận chuyển',
      'cancelled': 'Đã hủy',
    };
    final statusLabel =
        cloudStatuses[data['delivery_status']] ??
        cloudStatuses[data['state']] ??
        marketStates[data['state']] ??
        'Đang cập nhật';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${data['shop_name'] ?? 'GHST Express'}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Trạng thái: $statusLabel',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Cập nhật: ${cloudDate(data['updated_at'])} · Hết hạn liên kết: ${cloudDate(data['expires_at'])}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepPill(
    String label, {
    required bool done,
    required bool active,
  }) {
    final color = done
        ? AppColors.success
        : active
        ? AppColors.violet
        : AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done
              ? Icons.check_circle_rounded
              : active
              ? Icons.timelapse_rounded
              : Icons.circle_outlined,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: (done || active) ? FontWeight.w800 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
