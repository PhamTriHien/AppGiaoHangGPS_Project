import 'package:flutter/material.dart';

import '../../core/integrations/cloud_orders_service.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../widgets/cloud_order_labels.dart';
import '../widgets/theme_mode_toggle.dart';
import '../widgets/ghst_button_icon.dart';

class SharedTrackingScreen extends StatefulWidget {
  const SharedTrackingScreen({
    super.key,
    this.token = '',
    this.lookup,
    this.cloudService,
  });
  final String token;
  final Future<Map<String, dynamic>> Function(String)? lookup;
  final CloudOrdersService? cloudService;

  @override
  State<SharedTrackingScreen> createState() => _SharedTrackingScreenState();
}

class _SharedTrackingScreenState extends State<SharedTrackingScreen> {
  late final _service = widget.cloudService ?? CloudOrdersService();
  late final _token = TextEditingController(text: widget.token);
  Map<String, dynamic>? _data;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.token.isNotEmpty) _load();
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    final token = _token.text.trim();
    setState(() {
      _busy = true;
      _data = null;
      _error = null;
    });
    try {
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
        throw const FormatException();
      }
      final data = widget.lookup != null
          ? await widget.lookup!(token)
          : await _service.publicTracking(token);
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Chưa tra cứu được. Liên kết có thể đã hết hạn hoặc bị thu hồi.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _stageFor(Map<String, dynamic> data) {
    final raw = '${data['delivery_status'] ?? data['state'] ?? ''}';
    return switch (raw) {
      'delivered' => 4,
      'inTransit' || 'delivering' || 'ready' => 3,
      'arrivingPickup' || 'picking_up' => 2,
      'accepted' => 1,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    const states = {
      'pending': 'Chờ cửa hàng xác nhận',
      'accepted': 'Đang chuẩn bị',
      'ready': 'Đang vận chuyển',
      'cancelled': 'Đã hủy',
    };
    const legacyDelivery = {
      'picking_up': 'Đang lấy hàng',
      'delivering': 'Đang giao hàng',
      'delivered': 'Đã giao hàng',
    };

    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        backgroundColor: tokens.cardSurface,
        foregroundColor: tokens.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Theo dõi giao hàng'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: ThemeModeIconButton(compact: true),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GhstLuminousCard(
                    padding: const EdgeInsets.all(18),
                    accentGlow: tokens.sapphire.glow,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _token,
                          maxLength: 64,
                          decoration: const InputDecoration(
                            labelText: 'Mã theo dõi được chia sẻ',
                            prefixIcon: GhstButtonIcon(Icons.qr_code_scanner_rounded),
                          ),
                          onSubmitted: (_) => _load(),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _busy ? null : _load,
                          icon: const GhstButtonIcon(Icons.search),
                          label: const Text('Tra cứu'),
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
                    GhstLuminousCard(
                      padding: const EdgeInsets.all(16),
                      accentGlow: tokens.rose.glow,
                      child: Row(
                        children: [
                          GhstButtonIcon(
                            Icons.error_outline_rounded,
                            color: tokens.rose.icon,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: tokens.rose.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_data != null) ...[
                    Builder(
                      builder: (_) {
                        final stage = _stageFor(_data!);
                        final statusLabel =
                            legacyDelivery[_data!['delivery_status']] ??
                            cloudStatuses[_data!['delivery_status']] ??
                            legacyDelivery[_data!['state']] ??
                            cloudStatuses[_data!['state']] ??
                            states[_data!['state']] ??
                            'Đang cập nhật';
                        final cancelled =
                            _data!['state'] == 'cancelled' ||
                            _data!['delivery_status'] == 'cancelled';
                        final tone = cancelled
                            ? tokens.rose
                            : stage >= 4
                            ? tokens.emerald
                            : tokens.sapphire;
                        return GhstLuminousCard(
                          padding: const EdgeInsets.all(20),
                          accentGlow: tone.glow,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  GhstPulseBeacon(
                                    color: tone.icon,
                                    size: 10,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${_data!['shop_name'] ?? 'GHST Express'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: tokens.ink,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: tone.fill,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: tone.border),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: tone.foreground,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
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
                                    _stepItem(
                                      tokens,
                                      '1. Đặt đơn',
                                      done: !cancelled && stage > 0,
                                      active: !cancelled && stage == 0,
                                    ),
                                    _stepItem(
                                      tokens,
                                      '2. Đã nhận',
                                      done: !cancelled && stage > 1,
                                      active: !cancelled && stage == 1,
                                    ),
                                    _stepItem(
                                      tokens,
                                      '3. Lấy hàng',
                                      done: !cancelled && stage > 2,
                                      active: !cancelled && stage == 2,
                                    ),
                                    _stepItem(
                                      tokens,
                                      '4. Vận chuyển',
                                      done: !cancelled && stage > 3,
                                      active: !cancelled && stage == 3,
                                    ),
                                    _stepItem(
                                      tokens,
                                      '5. Hoàn tất',
                                      done: !cancelled && stage >= 4,
                                      active: false,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Cập nhật: ${cloudDate(_data!['updated_at']).isEmpty ? _data!['updated_at'] : cloudDate(_data!['updated_at'])}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: tokens.inkSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Liên kết hết hạn: ${cloudDate(_data!['expires_at']).isEmpty ? _data!['expires_at'] : cloudDate(_data!['expires_at'])}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: tokens.inkSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepItem(
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
        GhstButtonIcon(
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
