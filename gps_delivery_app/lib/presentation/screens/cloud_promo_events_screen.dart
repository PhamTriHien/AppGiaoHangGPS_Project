import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/integrations/delivery_api_client.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../../core/utils/currency_formatter.dart';
import '../widgets/cloud_order_labels.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/market_commercial_sheets.dart';
import '../widgets/theme_mode_toggle.dart';

Future<void> openCloudPromoEvents(
  BuildContext context,
  CloudAccountSession session, {
  int initialTab = 0,
  VoidCallback? onOpenCatalog,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CloudSessionBoundary(
      session: session,
      builder: (_, lease) => CloudPromoEventsScreen(
        session: session,
        lease: lease,
        initialTab: initialTab,
        onOpenCatalog: onOpenCatalog,
      ),
    ),
  ),
);

class CloudPromoEventsScreen extends StatefulWidget {
  const CloudPromoEventsScreen({
    super.key,
    required this.session,
    required this.lease,
    this.initialTab = 0,
    this.onOpenCatalog,
  });

  final CloudAccountSession session;
  final CloudSessionLease lease;
  final int initialTab;
  final VoidCallback? onOpenCatalog;

  @override
  State<CloudPromoEventsScreen> createState() => _CloudPromoEventsScreenState();
}

class _CloudPromoEventsScreenState extends State<CloudPromoEventsScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 3),
  );
  late final AnimationController _wheelController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );
  late final AnimationController _boxShakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  Animation<double>? _wheelAnim;
  double _wheelRotation = 0;
  int? _openingBoxIndex;

  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _generation = 0;

  bool get _allowed => mounted && widget.lease.valid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.lease.addListener(_onLeaseChanged);
    unawaited(_load());
  }

  void _onLeaseChanged() {
    if (mounted && !widget.lease.valid) {
      _generation++;
      _wheelController.stop();
      _boxShakeController.stop();
      setState(() {
        _data = null;
        _loading = false;
        _busy = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _allowed && !_busy) {
      DeliveryApiClient.instance.resetConnectionPool();
      unawaited(_load(silent: _data != null));
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    widget.lease.removeListener(_onLeaseChanged);
    _tabController.dispose();
    _wheelController.dispose();
    _boxShakeController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Map<String, dynamic> get _wallet {
    final w = _data?['wallet'];
    return w is Map ? Map<String, dynamic>.from(w) : const {};
  }

  int get _coinBalance =>
      (_data?['coin_balance'] as num? ?? widget.session.coinBalance).toInt();
  int get _spinTickets => (_wallet['spin_tickets'] as num? ?? 0).toInt();
  int get _boxTickets => (_wallet['blind_box_tickets'] as num? ?? 0).toInt();
  bool get _enabled => _data?['enabled'] != false;

  Future<void> _load({bool silent = false}) async {
    if (!_allowed) return;
    final gen = ++_generation;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await widget.session.service.promoEvents('status');
      if (!_allowed || gen != _generation) return;
      setState(() {
        _data = res;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!_allowed ||
          gen != _generation ||
          widget.lease.handleAccessFailure(e)) {
        return;
      }
      setState(() {
        _loading = false;
        _error = e is PublicApiException
            ? e.message
            : 'Chưa tải được trung tâm sự kiện.';
      });
    }
  }

  Future<void> _mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (_busy || !_allowed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.session.service.promoEvents(action, payload);
      if (!_allowed) return;
      setState(() {
        _data = res;
        _busy = false;
      });
      unawaited(widget.session.refresh());
      final reward = res['reward'];
      if (reward is Map && mounted) {
        await _showRewardDialog(Map<String, dynamic>.from(reward));
      }
    } catch (e) {
      if (!_allowed || widget.lease.handleAccessFailure(e)) return;
      final msg = e is PublicApiException
          ? e.message
          : 'Không xử lý được thao tác sự kiện.';
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _spinWheel() async {
    if (_busy || !_allowed) return;
    if (_spinTickets < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bạn chưa có Vé quay. Hãy điểm danh hoặc đổi Xu tại tab Điểm danh!',
          ),
        ),
      );
      _tabController.animateTo(0);
      return;
    }

    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.session.service.promoEvents('spin_wheel');
      if (!_allowed) return;
      final segment = (res['wheel_segment'] as num? ?? 0).toInt().clamp(0, 7);
      final sliceAngle = (2 * math.pi) / 8;
      final targetNormalized =
          (2 * math.pi - (segment * sliceAngle + sliceAngle / 2)) %
          (2 * math.pi);
      final currentNormalized = _wheelRotation % (2 * math.pi);
      var delta = targetNormalized - currentNormalized;
      if (delta <= 0) delta += 2 * math.pi;
      final endRotation = _wheelRotation + 5 * 2 * math.pi + delta;

      if (disableAnimations) {
        _wheelRotation = endRotation;
      } else {
        _wheelAnim = Tween<double>(begin: _wheelRotation, end: endRotation)
            .animate(
              CurvedAnimation(
                parent: _wheelController,
                curve: Curves.easeOutQuart,
              ),
            );
        _wheelController.reset();
        await _wheelController.forward();
        _wheelRotation = endRotation;
      }
      if (!_allowed) return;
      setState(() {
        _data = res;
        _busy = false;
      });
      unawaited(widget.session.refresh());
      final reward = res['reward'];
      if (reward is Map && mounted) {
        await _showRewardDialog(Map<String, dynamic>.from(reward));
      }
    } catch (e) {
      if (!_allowed || widget.lease.handleAccessFailure(e)) return;
      final msg = e is PublicApiException
          ? e.message
          : 'Không quay thưởng được lúc này.';
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _openBlindBox(int index) async {
    if (_busy || !_allowed) return;
    if (_boxTickets < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bạn chưa có Vé Hộp Mù. Hãy điểm danh, quay thưởng hoặc đổi Xu!',
          ),
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _openingBoxIndex = index;
      _error = null;
    });
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!disableAnimations) {
      _boxShakeController.reset();
      unawaited(_boxShakeController.forward());
    }
    try {
      final res = await widget.session.service.promoEvents('open_blind_box', {
        'box_index': index,
      });
      if (!disableAnimations && _boxShakeController.isAnimating) {
        await _boxShakeController.forward();
      }
      if (!_allowed) return;
      setState(() {
        _data = res;
        _busy = false;
        _openingBoxIndex = null;
      });
      unawaited(widget.session.refresh());
      final reward = res['reward'];
      if (reward is Map && mounted) {
        await _showRewardDialog(Map<String, dynamic>.from(reward));
      }
    } catch (e) {
      if (!_allowed || widget.lease.handleAccessFailure(e)) return;
      final msg = e is PublicApiException
          ? e.message
          : 'Không mở được Hộp mù lúc này.';
      setState(() {
        _busy = false;
        _openingBoxIndex = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  void _copyVoucherAndShop(String code, {bool goShop = false}) {
    Clipboard.setData(ClipboardData(text: code)).ignore();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          goShop
              ? 'Đã sao chép mã $code. Áp dụng tại bước thanh toán Giỏ hàng!'
              : 'Đã sao chép mã $code',
        ),
      ),
    );
    if (goShop && widget.onOpenCatalog != null) {
      Navigator.of(context).pop();
      widget.onOpenCatalog!();
    }
  }

  TonePair _rarityTone(GhstThemeTokens tokens, String rarity) =>
      switch (rarity) {
        'Legendary' || 'SSR' => tokens.amber,
        'Epic' || 'SR' => tokens.rose,
        'Rare' || 'R' => tokens.emerald,
        _ => tokens.neutral,
      };

  Future<void> _showRewardDialog(Map<String, dynamic> reward) {
    final rarity = '${reward['rarity'] ?? 'Common'}';
    final voucherCode = reward['voucher_code'] as String?;
    return showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final tokens = GhstThemeTokens.of(dialogCtx);
        final rTone = _rarityTone(tokens, rarity);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          backgroundColor: tokens.cardSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: tokens.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: rTone.fill,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: rTone.border),
                            ),
                            child: Text(
                              'PHẦN THƯỞNG • ${rarity.toUpperCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: rTone.foreground,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(dialogCtx),
                        icon: Icon(Icons.close, color: tokens.ink),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${reward['title'] ?? 'Nhận thưởng thành công'}',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: tokens.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${reward['summary'] ?? ''}',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: tokens.inkSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (voucherCode != null && voucherCode.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: tokens.sapphire.fill,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: tokens.sapphire.border),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.confirmation_num_outlined,
                                color: tokens.sapphire.icon,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: SelectableText(
                                  voucherCode,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: tokens.sapphire.foreground,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          OutlinedButton(
                            onPressed: () => _copyVoucherAndShop(voucherCode),
                            child: const Text('Sao chép'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (voucherCode != null &&
                          voucherCode.isNotEmpty &&
                          widget.onOpenCatalog != null)
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogCtx);
                            _copyVoucherAndShop(voucherCode, goShop: true);
                          },
                          icon: const Icon(Icons.storefront_outlined, size: 16),
                          label: const Text('Dùng đặt món ngay'),
                        ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('Tuyệt vời'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _neoCard({
    required Widget child,
    Color? accentGlow,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    final tokens = GhstThemeTokens.of(context);
    return GhstLuminousCard(
      padding: padding,
      accentGlow: accentGlow ?? tokens.sapphire.glow,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }

  Widget _walletBanner(GhstThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () =>
                    showCoinWalletDialog(context, session: widget.session),
                child: _walletChip(
                  icon: Icons.monetization_on_rounded,
                  tone: tokens.emerald,
                  label: 'Ví Xu: $_coinBalance Xu',
                ),
              ),
              _walletChip(
                icon: Icons.casino_outlined,
                tone: tokens.sapphire,
                label: 'Vé Vòng Xoay: $_spinTickets',
              ),
              _walletChip(
                icon: Icons.card_giftcard,
                tone: tokens.rose,
                label: 'Vé Hộp Mù: $_boxTickets',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _walletChip({
    required IconData icon,
    required TonePair tone,
    required String label,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: tone.fill,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: tone.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: tone.icon),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: tone.foreground,
          ),
        ),
      ],
    ),
  );

  Widget _buildCheckinAndDealsTab() {
    final tokens = GhstThemeTokens.of(context);
    final schedule = _rows(_data?['checkin_schedule']);
    final missions = _rows(_data?['missions']);
    final exchange = _rows(_data?['exchange_catalog']);
    final flashSales = _rows(_data?['flash_sales']);
    final streak = (_wallet['checkin_streak'] as num? ?? 0).toInt();
    final checkedToday = _wallet['checked_in_today'] == true;

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _neoCard(
                  accentGlow: tokens.emerald.glow,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Điểm danh 7 ngày nhận Xu & Vé quay · $streak/7',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: tokens.ink,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: checkedToday
                                  ? tokens.emerald.fill
                                  : tokens.amber.fill,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: checkedToday
                                    ? tokens.emerald.border
                                    : tokens.amber.border,
                              ),
                            ),
                            child: Text(
                              checkedToday
                                  ? 'ĐÃ ĐIỂM DANH HÔM NAY'
                                  : 'CHƯA ĐIỂM DANH',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: checkedToday
                                    ? tokens.emerald.foreground
                                    : tokens.amber.foreground,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final d in schedule)
                            Builder(
                              builder: (_) {
                                final day = (d['day'] as num? ?? 1).toInt();
                                final coins = (d['coins'] as num? ?? 0).toInt();
                                final spins = (d['spin_tickets'] as num? ?? 0)
                                    .toInt();
                                final boxes = (d['box_tickets'] as num? ?? 0)
                                    .toInt();
                                final done = day <= streak;
                                return Container(
                                  width: 112,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: done
                                        ? tokens.emerald.fill
                                        : tokens.cardSubtle,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: done
                                          ? tokens.emerald.border
                                          : tokens.border,
                                      width: done ? 1.4 : 1.0,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Ngày $day ${done ? '✓' : ''}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: done
                                              ? tokens.emerald.foreground
                                              : tokens.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '+$coins Xu',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: tokens.sapphire.foreground,
                                        ),
                                      ),
                                      if (spins > 0 || boxes > 0)
                                        Text(
                                          [
                                            if (spins > 0) '+$spins Vé quay',
                                            if (boxes > 0) '+$boxes Hộp mù',
                                          ].join(' · '),
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: tokens.inkSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const ValueKey('btn-promo-checkin'),
                        onPressed: _busy || !_enabled || checkedToday
                            ? null
                            : () => _mutate('checkin'),
                        icon: Icon(
                          checkedToday
                              ? Icons.check_circle_outline
                              : Icons.bolt_rounded,
                        ),
                        label: Text(
                          checkedToday
                              ? 'Đã nhận thưởng điểm danh hôm nay'
                              : 'Điểm danh nhận Xu & Vé quay ngay',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _neoCard(
                  accentGlow: tokens.rose.glow,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.flash_on_rounded,
                            color: tokens.rose.icon,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Khung giờ Flash Sale đang mở',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: tokens.ink,
                              ),
                            ),
                          ),
                          if (widget.onOpenCatalog != null)
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                widget.onOpenCatalog!();
                              },
                              child: const Text('Vào quán ăn'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (flashSales.isEmpty)
                        Text(
                          'Hiện chưa có khung giờ Flash Sale nào đang diễn ra.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: tokens.inkSecondary,
                          ),
                        )
                      else
                        for (final fs in flashSales) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: tokens.cardSubtle,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: tokens.border),
                            ),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 520,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${fs['product_name']} • ${fs['shop_name']}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13.5,
                                          color: tokens.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Giá Flash Sale: ${CurrencyFormatter.formatVnd(((fs['sale_price'] as num?) ?? 0).toDouble())} '
                                        '· Giá gốc ${CurrencyFormatter.formatVnd(((fs['original_price'] as num?) ?? 0).toDouble())} · '
                                        'Đã bán ${fs['sold_stock']}/${fs['allocated_stock']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: tokens.rose.foreground,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.onOpenCatalog != null)
                                  FilledButton.tonal(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      widget.onOpenCatalog!();
                                    },
                                    child: const Text('Săn ngay'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _neoCard(
                  accentGlow: tokens.violet.glow,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Nhiệm vụ đơn hàng',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: tokens.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tiến độ tự động cập nhật từ các đơn giao hàng và đơn đặt món đã hoàn tất.',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.inkSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final m in missions)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: m['claimed'] == true
                                ? tokens.cardMuted
                                : tokens.cardSubtle,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: tokens.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 520,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${m['title']} · ${m['progress']}/${m['target']}',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w900,
                                            color: tokens.ink,
                                          ),
                                        ),
                                        Text(
                                          '${m['subtitle']}',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: tokens.inkSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          [
                                            '+${m['coins']} Xu',
                                            if (((m['spin_tickets'] as num?) ??
                                                    0) >
                                                0)
                                              '+${m['spin_tickets']} Vé quay',
                                            if (((m['box_tickets'] as num?) ??
                                                    0) >
                                                0)
                                              '+${m['box_tickets']} Vé hộp mù',
                                          ].join(' · '),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                            color: tokens.sapphire.foreground,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed:
                                        _busy ||
                                            !_enabled ||
                                            m['claimable'] != true
                                        ? null
                                        : () => _mutate('claim_mission', {
                                            'mission_id': '${m['id']}',
                                          }),
                                    child: Text(
                                      m['claimed'] == true
                                          ? 'Đã nhận'
                                          : m['claimable'] == true
                                          ? 'Nhận thưởng'
                                          : 'Chưa đạt',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _neoCard(
                  accentGlow: tokens.amber.glow,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Trạm Đổi Xu thưởng',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: tokens.ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final item in exchange)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: tokens.cardSubtle,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: tokens.border),
                          ),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 520,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item['title']}',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w900,
                                        color: tokens.ink,
                                      ),
                                    ),
                                    Text(
                                      '${item['subtitle']}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: tokens.inkSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed:
                                    _busy ||
                                        !_enabled ||
                                        _coinBalance <
                                            ((item['coin_cost'] as num?) ?? 0)
                                                .toInt()
                                    ? null
                                    : () => _mutate('exchange_coins', {
                                        'item_id': '${item['id']}',
                                      }),
                                icon: const Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 16,
                                ),
                                label: Text('Đổi ${item['coin_cost']} Xu'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpinWheelTab() {
    final tokens = GhstThemeTokens.of(context);
    final segments = _rows(_data?['wheel_segments']);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: _neoCard(
            padding: const EdgeInsets.all(18),
            accentGlow: tokens.rose.glow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'VÒNG XOAY MAY MẮN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: tokens.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Quà tặng và mã giảm giá cộng tự động vào tài khoản • Đã quay ${_wallet['total_spins'] ?? 0} lượt',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.inkSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wheelSize = math.min(
                      constraints.maxWidth - 12,
                      310.0,
                    );
                    return SizedBox(
                      width: wheelSize,
                      height: wheelSize + 18,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            top: 14,
                            child: AnimatedBuilder(
                              animation: _wheelController,
                              builder: (_, _) {
                                final angle = _wheelController.isAnimating
                                    ? (_wheelAnim?.value ?? _wheelRotation)
                                    : _wheelRotation;
                                return Transform.rotate(
                                  angle: angle,
                                  child: CustomPaint(
                                    size: Size.square(wheelSize),
                                    painter: _CloudSpinWheelPainter(
                                      segments: segments,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Positioned(
                            top: 0,
                            child: CustomPaint(
                              size: const Size(28, 26),
                              painter: _WheelPointerPainter(
                                outlineColor: tokens.isDark
                                    ? Colors.white
                                    : AppColors.ink,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 14 + (wheelSize - 74) / 2,
                            child: GestureDetector(
                              onTap: _busy || !_enabled ? null : _spinWheel,
                              child: Container(
                                width: 74,
                                height: 74,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: tokens.cardSurface,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: tokens.primary,
                                    width: 3,
                                  ),
                                  boxShadow: tokens.elevatedShadow,
                                ),
                                child: Text(
                                  _busy ? '...' : 'QUAY\n$_spinTickets VÉ',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: tokens.sapphire.foreground,
                                    height: 1.15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('btn-promo-spin'),
                      onPressed: _busy || !_enabled ? null : _spinWheel,
                      icon: const Icon(Icons.autorenew),
                      label: Text(
                        _spinTickets > 0
                            ? 'Quay thưởng ngay · Còn $_spinTickets vé'
                            : 'Chưa có vé quay — Điểm danh nhận vé',
                      ),
                    ),
                    if (_spinTickets == 0)
                      OutlinedButton(
                        onPressed: () => _tabController.animateTo(0),
                        child: const Text('Tới Điểm danh / Đổi Xu'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlindBoxTab() {
    final tokens = GhstThemeTokens.of(context);
    final openedRaw = _wallet['opened_boxes'];
    final opened = openedRaw is Map
        ? Map<String, dynamic>.from(openedRaw)
        : const <String, dynamic>{};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: _neoCard(
            padding: const EdgeInsets.all(16),
            accentGlow: tokens.violet.glow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        Text(
                          'HỘP MÙ BÍ ẨN',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: tokens.ink,
                          ),
                        ),
                        Text(
                          'Còn $_boxTickets vé mở hộp • Đã khui ${_wallet['total_boxes_opened'] ?? 0} hộp',
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                    if (opened.isNotEmpty)
                      OutlinedButton.icon(
                        key: const ValueKey('btn-promo-reset-boxes'),
                        onPressed: _busy || !_enabled
                            ? null
                            : () => _mutate('reset_blind_boxes'),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Làm mới khay 6 hộp'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth >= 560 ? 3 : 2;
                    final itemWidth =
                        (constraints.maxWidth - 12 * (cols - 1)) / cols;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (var i = 0; i < 6; i++)
                          Builder(
                            builder: (_) {
                              final boxData = opened['$i'];
                              final isOpened = boxData is Map;
                              final boxMap = isOpened
                                  ? Map<String, dynamic>.from(boxData)
                                  : const <String, dynamic>{};
                              final rarity = '${boxMap['rarity'] ?? 'R'}';
                              final rTone = _rarityTone(tokens, rarity);
                              final shaking = _openingBoxIndex == i;
                              return AnimatedBuilder(
                                animation: _boxShakeController,
                                builder: (_, child) {
                                  final dx = shaking
                                      ? math.sin(
                                              _boxShakeController.value *
                                                  math.pi *
                                                  6,
                                            ) *
                                            6
                                      : 0.0;
                                  return Transform.translate(
                                    offset: Offset(dx, 0),
                                    child: child,
                                  );
                                },
                                child: SizedBox(
                                  width: itemWidth,
                                  child: InkWell(
                                    key: ValueKey('blind-box-$i'),
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: _busy || !_enabled || isOpened
                                        ? null
                                        : () => _openBlindBox(i),
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        minHeight: 138,
                                      ),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        gradient: isOpened
                                            ? null
                                            : tokens.merchantGradient,
                                        color: isOpened ? rTone.fill : null,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isOpened
                                              ? rTone.border
                                              : tokens.shellBorder,
                                        ),
                                        boxShadow: tokens.cardShadow,
                                      ),
                                      child: isOpened
                                          ? Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: tokens.cardSurface,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    'HẠNG $rarity',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: rTone.foreground,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  '${boxMap['title'] ?? ''}',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: tokens.ink,
                                                  ),
                                                ),
                                                if ((boxMap['voucher_code']
                                                            as String? ??
                                                        '')
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  InkWell(
                                                    onTap: () =>
                                                        _copyVoucherAndShop(
                                                          '${boxMap['voucher_code']}',
                                                        ),
                                                    child: Text(
                                                      'Mã: ${boxMap['voucher_code']} · Sao chép',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: tokens
                                                            .sapphire
                                                            .foreground,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            )
                                          : Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.redeem_rounded,
                                                  color: AppColors.acid,
                                                  size: 32,
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'HỘP MÙ #${i + 1}',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _boxTickets > 0
                                                      ? 'CHẠM ĐỂ KHUI · 1 VÉ'
                                                      : 'CẦN 1 VÉ HỘP MÙ',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white
                                                        .withValues(alpha: 0.8),
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVouchersAndHistoryTab() {
    final tokens = GhstThemeTokens.of(context);
    final vouchers = _rows(_data?['vouchers']);
    final history = _rows(_data?['history']);

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _neoCard(
                  accentGlow: tokens.sapphire.glow,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Kho Voucher khả dụng · ${vouchers.length}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: tokens.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (vouchers.isEmpty)
                        Text(
                          'Chưa có mã giảm giá nào. Hãy quay Vòng xoay, khui Hộp mù hoặc đổi Xu để săn Voucher!',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: tokens.inkSecondary,
                          ),
                        )
                      else
                        for (final v in vouchers)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: v['personal'] == true
                                  ? tokens.sapphire.fill
                                  : tokens.cardSubtle,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: v['personal'] == true
                                    ? tokens.sapphire.border
                                    : tokens.border,
                              ),
                            ),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 560,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: v['personal'] == true
                                                  ? tokens.primary
                                                  : tokens.shellBg,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              v['personal'] == true
                                                  ? 'CÁ NHÂN'
                                                  : (v['shop_name'] == null
                                                        ? 'TOÀN SÀN'
                                                        : '${v['shop_name']}'),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${v['code']} · ${v['title']}',
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w900,
                                              color: tokens.ink,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${v['discount_kind'] == 'percent' ? 'Giảm ${v['discount_value']}% tối đa ${CurrencyFormatter.formatVnd(((v['max_discount'] as num?) ?? 0).toDouble())}' : 'Giảm ${CurrencyFormatter.formatVnd(((v['discount_value'] as num?) ?? 0).toDouble())}'}'
                                        ' · Đơn từ ${CurrencyFormatter.formatVnd(((v['min_subtotal'] as num?) ?? 0).toDouble())}'
                                        ' · HSD ${cloudDate(v['ends_at'])}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: tokens.inkSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    OutlinedButton(
                                      onPressed: () =>
                                          _copyVoucherAndShop('${v['code']}'),
                                      child: const Text('Sao chép'),
                                    ),
                                    if (widget.onOpenCatalog != null)
                                      FilledButton(
                                        onPressed: () => _copyVoucherAndShop(
                                          '${v['code']}',
                                          goShop: true,
                                        ),
                                        child: const Text('Dùng ngay'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _neoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Lịch sử trúng thưởng & đổi quà',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: tokens.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (history.isEmpty)
                        Text(
                          'Chưa có lịch sử nhận thưởng.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: tokens.inkSecondary,
                          ),
                        )
                      else
                        for (final h in history)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${h['title']}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: tokens.ink,
                              ),
                            ),
                            subtitle: Text(
                              '${h['summary']} • ${cloudDate(h['created_at'])}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: tokens.inkSecondary,
                              ),
                            ),
                            trailing:
                                (h['voucher_code'] as String? ?? '').isNotEmpty
                                ? TextButton(
                                    onPressed: () => _copyVoucherAndShop(
                                      '${h['voucher_code']}',
                                    ),
                                    child: const Text('Chép mã'),
                                  )
                                : null,
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.lease.valid) {
      return const Scaffold(
        body: Center(child: Text('Phiên làm việc đã thay đổi.')),
      );
    }
    final tokens = GhstThemeTokens.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 680;
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        backgroundColor: tokens.cardSurface,
        foregroundColor: tokens.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Sự kiện & Vòng xoay',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: ThemeModeIconButton(compact: true),
          ),
          IconButton(
            tooltip: 'Tải lại sự kiện',
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: isCompact,
          tabAlignment: isCompact ? TabAlignment.start : TabAlignment.fill,
          indicatorColor: tokens.primary,
          dividerColor: tokens.border,
          labelColor: tokens.primary,
          unselectedLabelColor: tokens.inkSecondary,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
          tabs: const [
            Tab(text: 'Điểm danh & Săn Deal'),
            Tab(text: 'Vòng Xoay'),
            Tab(text: 'Hộp Mù'),
            Tab(text: 'Kho Voucher'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _walletBanner(tokens),
          if (_loading || _busy) const LinearProgressIndicator(minHeight: 2.5),
          if (!_enabled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: tokens.amber.fill,
                border: Border(bottom: BorderSide(color: tokens.border)),
              ),
              child: Text(
                'Chương trình sự kiện hiện đang tạm dừng. Kho Voucher đã nhận vẫn dùng bình thường.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tokens.amber.foreground,
                ),
              ),
            ),
          if (_error != null && _data == null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCheckinAndDealsTab(),
                  _buildSpinWheelTab(),
                  _buildBlindBoxTab(),
                  _buildVouchersAndHistoryTab(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CloudSpinWheelPainter extends CustomPainter {
  const _CloudSpinWheelPainter({required this.segments});

  final List<Map<String, dynamic>> segments;

  static const _defaultLabels = [
    '+50 Xu',
    'Voucher 15K',
    '+1 Vé Hộp Mù',
    '+150 Xu',
    'Voucher 25K',
    '+30 Xu Lộc',
    'Giảm 50%',
    'Siêu Cấp 50K',
  ];

  static const _sliceColors = [
    AppColors.primary,
    AppColors.primarySoft,
    AppColors.success,
    Color(0xFFECFDF5),
    AppColors.accent,
    Color(0xFFFEF3C7),
    Color(0xFF294163),
    AppColors.surfaceSubtle,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final sliceAngle = (2 * math.pi) / 8;

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (var i = 0; i < 8; i++) {
      final start = -math.pi / 2 + i * sliceAngle;
      final bg = _sliceColors[i % _sliceColors.length];
      final fill = Paint()
        ..color = bg
        ..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sliceAngle,
        true,
        fill,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sliceAngle,
        true,
        borderPaint,
      );

      final label = i < segments.length
          ? '${segments[i]['label'] ?? _defaultLabels[i]}'
          : _defaultLabels[i];
      final darkBg = i == 0 || i == 2 || i == 4 || i == 6;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(start + sliceAngle / 2);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: darkBg ? Colors.white : AppColors.ink,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: radius * 0.56);
      tp.paint(canvas, Offset(radius * 0.34, -tp.height / 2));
      canvas.restore();
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.techBg
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );
  }

  @override
  bool shouldRepaint(covariant _CloudSpinWheelPainter oldDelegate) =>
      oldDelegate.segments != segments;
}

class _WheelPointerPainter extends CustomPainter {
  const _WheelPointerPainter({required this.outlineColor});

  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.pink
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPointerPainter oldDelegate) =>
      oldDelegate.outlineColor != outlineColor;
}
