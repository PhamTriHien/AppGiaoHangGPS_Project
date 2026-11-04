import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/integrations/cloud_orders_service.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/cloud_order_labels.dart';
import '../widgets/theme_mode_toggle.dart';

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
    final tokens = GhstThemeTokens.of(context);
    final typingToken = _isShareToken(_searchCtrl.text.trim());
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        backgroundColor: tokens.cardSurface,
        foregroundColor: tokens.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: tokens.border),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GhstAiIcon(
              style: Icon3dStyle.gpsPinRadar,
              size: 28,
              borderRadius: 9,
              selected: true,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Tra cứu & Theo dõi Hành trình Trực tiếp',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: tokens.ink,
                ),
              ),
            ),
          ],
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: ThemeModeIconButton(compact: true),
          ),
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
              icon: Icon(
                Icons.home_outlined,
                size: 17,
                color: tokens.primary,
              ),
              label: Text(
                'Trang chủ',
                style: TextStyle(
                  color: tokens.primary,
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
                GhstAuroraBanner(
                  gradient: tokens.heroGradient,
                  accentOrbColor: tokens.sapphire.glow,
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Animated3dIconBadge(
                        style: Icon3dStyle.gpsPinRadar,
                        size: 48,
                        showRadarPulse: true,
                      ),
                      const SizedBox(width: 12),
                      const GhstPulseBeacon(
                        color: Color(0xFF6EE7B7),
                        size: 12,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TRA CỨU HÀNH TRÌNH VẬN ĐƠN BẢO MẬT',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: 0.4,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Nhập mã vận đơn kèm 4 số cuối SĐT người nhận, hoặc dán mã chia sẻ 64 ký tự. Địa chỉ, SĐT đầy đủ và mã OTP nhận hàng luôn được bảo mật.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.45,
                                color: Colors.white.withValues(alpha: 0.86),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GhstLuminousCard(
                  padding: const EdgeInsets.all(18),
                  accentGlow: tokens.sapphire.glow,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                              backgroundColor: tokens.primary,
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
                    tokens: tokens,
                    title: 'Không tra cứu được vận đơn',
                    subtitle: _error!,
                    icon: Icons.find_in_page_outlined,
                    tone: tokens.rose,
                  )
                else if (_lookupData != null)
                  _buildCloudLookupDetail(tokens, _lookupData!)
                else if (_shareData != null)
                  _buildShareDetail(tokens, _shareData!)
                else
                  _buildStatusBox(
                    tokens: tokens,
                    title: 'Sẵn sàng tra cứu hành trình trực tiếp',
                    subtitle:
                        'Nhập mã vận đơn và 4 số cuối SĐT người nhận, hoặc mở liên kết chia sẻ từ người gửi để xem tiến độ giao hàng thời gian thực.',
                    icon: Icons.share_location_rounded,
                    icon3d: Icon3dStyle.gpsPinRadar,
                    tone: tokens.sapphire,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBox({
    required GhstThemeTokens tokens,
    required String title,
    required String subtitle,
    required IconData icon,
    Icon3dStyle? icon3d,
    required TonePair tone,
  }) => GhstLuminousCard(
    padding: const EdgeInsets.all(22),
    accentGlow: tone.glow,
    child: Row(
      children: [
        if (icon3d != null)
          GhstAiIcon(
            style: icon3d,
            size: 50,
            borderRadius: 13,
            selected: true,
            borderColor: tone.border,
            glowColor: tone.icon,
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tone.fill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tone.border),
            ),
            child: Icon(icon, size: 28, color: tone.icon),
          ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: tokens.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: tokens.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildCloudLookupDetail(
    GhstThemeTokens tokens,
    Map<String, dynamic> data,
  ) {
    final status = '${data['status'] ?? 'searching'}';
    final service = '${data['service_type'] ?? 'standard'}';
    final meters = (data['distance_meters'] as num? ?? 0).toDouble();
    final timeline = (data['timeline'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final isSearching = status == 'searching';
    final isAccepted = status == 'accepted';
    final isArrivingPickup = status == 'arrivingPickup';
    final isInTransit = status == 'inTransit';
    final isDelivered = status == 'delivered';
    final isCancelled =
        status == 'cancelled' || status == 'failed' || status == 'returned';
    final code = '${data['tracking_code']}';

    return GhstLuminousCard(
      padding: const EdgeInsets.all(20),
      accentGlow: isDelivered ? tokens.emerald.glow : tokens.sapphire.glow,
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: tokens.sapphire.foreground,
                    ),
                  ),
                  Text(
                    '${cloudStatuses[status] ?? status}'
                    '${meters > 0 ? ' • Lộ trình ${(meters / 1000).toStringAsFixed(1)} km' : ''}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: tokens.inkSecondary,
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
              color: tokens.cardSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.border),
            ),
            child: Wrap(
              spacing: 14,
              runSpacing: 8,
              alignment: WrapAlignment.spaceAround,
              children: [
                _buildStepPill(
                  tokens,
                  '1. Đã tạo đơn',
                  done: !isSearching && !isCancelled,
                  active: isSearching,
                ),
                _buildStepPill(
                  tokens,
                  '2. Đã nhận chuyến',
                  done: isArrivingPickup || isInTransit || isDelivered,
                  active: isAccepted,
                ),
                _buildStepPill(
                  tokens,
                  '3. Đến điểm lấy',
                  done: isInTransit || isDelivered,
                  active: isArrivingPickup,
                ),
                _buildStepPill(
                  tokens,
                  '4. Đang giao',
                  done: isDelivered,
                  active: isInTransit,
                ),
                _buildStepPill(
                  tokens,
                  '5. Hoàn thành',
                  done: isDelivered,
                  active: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tạo lúc: ${cloudDate(data['created_at'])} · Cập nhật: ${cloudDate(data['updated_at'])}',
            style: TextStyle(
              fontSize: 12,
              color: tokens.inkSecondary,
            ),
          ),
          Divider(height: 24, color: tokens.border),
          Text(
            'NHẬT KÝ HÀNH TRÌNH XÁC THỰC',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: tokens.ink,
            ),
          ),
          const SizedBox(height: 8),
          if (timeline.isEmpty)
            Text(
              'Chưa có mốc cập nhật hành trình.',
              style: TextStyle(color: tokens.inkSecondary),
            ),
          for (final item in timeline)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: tokens.sapphire.icon,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${cloudActions[item['action']] ?? item['action']} — ${cloudStatuses[item['status']] ?? item['status']}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: tokens.ink,
                      ),
                    ),
                  ),
                  Text(
                    cloudDate(item['created_at']),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: tokens.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShareDetail(
    GhstThemeTokens tokens,
    Map<String, dynamic> data,
  ) {
    const marketStates = {
      'pending': 'Chờ cửa hàng xác nhận',
      'accepted': 'Đang chuẩn bị',
      'ready': 'Đang vận chuyển',
      'cancelled': 'Đã hủy',
    };
    final rawStatus = '${data['delivery_status'] ?? data['state'] ?? ''}';
    final statusLabel =
        cloudStatuses[data['delivery_status']] ??
        cloudStatuses[data['state']] ??
        marketStates[data['state']] ??
        'Đang cập nhật';
    final stage = _shareStageIndex(rawStatus);
    return GhstLuminousCard(
      padding: const EdgeInsets.all(20),
      accentGlow: stage >= 4 ? tokens.emerald.glow : tokens.sapphire.glow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${data['shop_name'] ?? 'GHST Express'}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: tokens.sapphire.foreground,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Trạng thái: $statusLabel',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: tokens.ink,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: tokens.cardSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.border),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceAround,
              children: [
                _buildStepPill(
                  tokens,
                  '1. Đặt đơn',
                  done: stage > 0,
                  active: stage == 0,
                ),
                _buildStepPill(
                  tokens,
                  '2. Xác nhận',
                  done: stage > 1,
                  active: stage == 1,
                ),
                _buildStepPill(
                  tokens,
                  '3. Lấy hàng',
                  done: stage > 2,
                  active: stage == 2,
                ),
                _buildStepPill(
                  tokens,
                  '4. Đang giao',
                  done: stage > 3,
                  active: stage == 3,
                ),
                _buildStepPill(
                  tokens,
                  '5. Hoàn tất',
                  done: stage >= 4,
                  active: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Cập nhật: ${cloudDate(data['updated_at'])} · Hết hạn liên kết: ${cloudDate(data['expires_at'])}',
            style: TextStyle(
              fontSize: 12,
              color: tokens.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }

  int _shareStageIndex(String raw) => switch (raw) {
    'delivered' => 4,
    'inTransit' || 'delivering' || 'ready' => 3,
    'arrivingPickup' || 'picking_up' => 2,
    'accepted' => 1,
    _ => 0,
  };

  Widget _buildStepPill(
    GhstThemeTokens tokens,
    String label, {
    required bool done,
    required bool active,
  }) {
    final color = done
        ? tokens.emerald.foreground
        : active
        ? tokens.sapphire.foreground
        : tokens.inkMuted;
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
