import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_orders_service.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import 'animated_3d_ui_icons.dart';
import 'cloud_order_labels.dart';
import 'cloud_session_boundary.dart';
import 'ghst_button_icon.dart';
import 'system_state_screens.dart';

String cloudLogisticsMessage(Object error, String fallback) =>
    error is PublicApiException && error.statusCode != 503
    ? error.message
    : fallback;

String cloudMinutes(dynamic raw) {
  if (raw is! num) return 'Chưa có dữ liệu';
  final minutes = raw.round();
  if (minutes < 60) return '$minutes phút';
  final rest = minutes % 60;
  return rest == 0 ? '${minutes ~/ 60} giờ' : '${minutes ~/ 60} giờ $rest phút';
}

final _vietnamPhone = RegExp(r'^0[35789][0-9]{8}$');

/// Recipient history from the caller's own cloud shipments only.
class CloudRecipientTrust extends StatefulWidget {
  const CloudRecipientTrust({
    super.key,
    required this.service,
    required this.phone,
    this.lease,
    this.enabled = true,
  });

  final CloudOrdersService service;
  final TextEditingController phone;
  final CloudSessionLease? lease;
  final bool enabled;

  @override
  State<CloudRecipientTrust> createState() => _CloudRecipientTrustState();
}

class _CloudRecipientTrustState extends State<CloudRecipientTrust> {
  Timer? _debounce;
  String _requested = '';
  Map<String, dynamic>? _trust;
  bool _busy = false;
  String? _error;
  int _generation = 0;

  bool get _allowed => mounted && (widget.lease?.valid ?? true);

  @override
  void initState() {
    super.initState();
    widget.phone.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    widget.phone.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final value = widget.phone.text.trim();
    if (!_vietnamPhone.hasMatch(value)) {
      _debounce?.cancel();
      _generation++;
      _requested = '';
      if (_trust != null || _error != null || _busy) {
        setState(() {
          _trust = null;
          _error = null;
          _busy = false;
        });
      }
      return;
    }
    if (value == _requested) return;
    _requested = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _load(value));
  }

  Future<void> _load(String phone, {bool? flagged}) async {
    if (!_allowed) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = flagged == null
          ? await widget.service.logistics('recipient_trust', {'phone': phone})
          : await widget.service.logistics('recipient_flag', {
              'phone': phone,
              'flagged': flagged,
            });
      if (!_allowed ||
          generation != _generation ||
          widget.phone.text.trim() != phone) {
        return;
      }
      setState(() => _trust = result);
    } catch (error) {
      if (!_allowed || generation != _generation) return;
      if (widget.lease?.handleAccessFailure(error) == true) return;
      setState(
        () => _error = cloudLogisticsMessage(
          error,
          'Chưa tra cứu được lịch sử nhận hàng.',
        ),
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trust = _trust;
    if (trust == null || trust['score'] is! num) {
      if (_busy) return const LinearProgressIndicator(minHeight: 2);
      if (_error == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    final tokens = GhstThemeTokens.of(context);
    final tier = trust['tier'];
    final flagged = trust['flagged'] == true;
    final tone = switch (tier) {
      'high_risk' => tokens.rose,
      'confirm' => tokens.amber,
      _ => tokens.emerald,
    };
    final advice = switch (tier) {
      'high_risk' => 'Số điện thoại có lịch sử giao thất bại/hoàn hàng hoặc đã bị gắn cảnh báo. Nên yêu cầu chuyển khoản trước hoặc thu cọc phí ship.',
      'confirm' => 'Nên gọi xác nhận khung giờ nhận hàng trước khi xuất kho.',
      _ => 'Đủ điều kiện giao COD tiêu chuẩn.',
    };
    final tierLabel = switch (tier) {
      'high_risk' => 'Rủi ro hoàn cao',
      'confirm' => 'Cần gọi xác nhận',
      _ => 'Tín nhiệm tốt',
    };
    return Container(
      key: const ValueKey('cloud-recipient-trust'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.fill,
        border: Border.all(color: tone.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tín nhiệm người nhận: ${trust['score']}/100 · $tierLabel',
            style: TextStyle(color: tone.foreground, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Trong các đơn của bạn: ${trust['delivered']} đơn giao thành công · ${trust['failed_or_returned']} đơn thất bại/hoàn hàng.',
            style: TextStyle(fontSize: 12.5, color: tokens.inkSecondary),
          ),
          Text(
            advice,
            style: TextStyle(fontSize: 12.5, color: tokens.inkSecondary),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy || !widget.enabled
                  ? null
                  : () => _load('${trust['phone']}', flagged: !flagged),
              icon: GhstButtonIcon(flagged ? Icons.flag_outlined : Icons.flag, size: 18),
              label: Text(flagged ? 'Gỡ cảnh báo' : 'Cảnh báo bom hàng'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Owner-only one-tap delivery instruction, visible to the assigned driver.
class CloudDeliveryInstructionButton extends StatefulWidget {
  const CloudDeliveryInstructionButton({
    super.key,
    required this.service,
    required this.order,
    required this.onUpdated,
    this.lease,
  });

  final CloudOrdersService service;
  final Map<String, dynamic> order;
  final VoidCallback onUpdated;
  final CloudSessionLease? lease;

  static const editableStatuses = {
    'searching',
    'accepted',
    'arrivingPickup',
    'inTransit',
    'failed',
  };

  @override
  State<CloudDeliveryInstructionButton> createState() =>
      _CloudDeliveryInstructionButtonState();
}

class _CloudDeliveryInstructionButtonState
    extends State<CloudDeliveryInstructionButton> {
  bool _busy = false;

  Future<void> _set(String instruction) async {
    if (_busy || !(widget.lease?.valid ?? true)) return;
    final identity = widget.service.identityScope;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      await widget.service.logistics('instruction_set', {
        'order_id': widget.order['id'],
        'version': widget.order['version'],
        'instruction': instruction,
      });
      if (mounted && identity == widget.service.identityScope) {
        widget.onUpdated();
      }
    } catch (error) {
      if (!mounted || widget.lease?.handleAccessFailure(error) == true) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            cloudLogisticsMessage(
              error,
              'Chưa cập nhật được chỉ dẫn giao hàng.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = '${widget.order['delivery_instruction'] ?? ''}';
    return PopupMenuButton<String>(
      enabled: !_busy,
      tooltip: 'Chỉ dẫn giao nhanh cho tài xế',
      onSelected: _set,
      itemBuilder: (_) => [
        for (final note in cloudQuickInstructions)
          PopupMenuItem(
            value: note,
            child: Row(
              children: [
                GhstButtonIcon.glyph(
                  current == note
                      ? GhstActionKind.checkCircle
                      : GhstActionKind.chat,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(note)),
              ],
            ),
          ),
        if (current.isNotEmpty)
          const PopupMenuItem(
            value: '',
            child: Row(
              children: [
                GhstButtonIcon.glyph(GhstActionKind.delete, size: 16),
                SizedBox(width: 8),
                Text('Xóa chỉ dẫn'),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GhstButtonIcon(Icons.edit_note_outlined, size: 18),
            const SizedBox(width: 6),
            Text(_busy ? 'Đang lưu...' : 'Chỉ dẫn giao'),
          ],
        ),
      ),
    );
  }
}

Future<void> openCloudDeliveryStats(
  BuildContext context,
  CloudAccountSession session,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CloudSessionBoundary(
      session: session,
      builder: (_, lease) => Scaffold(
        appBar: AppBar(title: const Text('Thống kê giao hàng')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CloudDeliveryStatsCard(service: session.service, lease: lease),
              if (session.hasRole('driver')) ...[
                const SizedBox(height: 12),
                DriverReviewsPanel(service: session.service, lease: lease),
              ],
            ],
          ),
        ),
      ),
    ),
  ),
);

/// Delivery metrics computed by the server from cloud orders and history.
class CloudDeliveryStatsCard extends StatefulWidget {
  const CloudDeliveryStatsCard({super.key, required this.service, this.lease});

  final CloudOrdersService service;
  final CloudSessionLease? lease;

  @override
  State<CloudDeliveryStatsCard> createState() => _CloudDeliveryStatsCardState();
}

class _CloudDeliveryStatsCardState extends State<CloudDeliveryStatsCard> {
  Map<String, dynamic>? _stats;
  bool _busy = false;
  String? _error;
  int _generation = 0;

  bool get _allowed => mounted && (widget.lease?.valid ?? true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    if (!_allowed) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final stats = await widget.service.logistics('stats');
      if (_allowed && generation == _generation) {
        setState(() => _stats = stats);
      }
    } catch (error) {
      if (!_allowed || generation != _generation) return;
      if (widget.lease?.handleAccessFailure(error) == true) return;
      setState(
        () => _error = cloudLogisticsMessage(
          error,
          'Chưa tải được thống kê giao hàng.',
        ),
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final stats = _stats;
    final summary = Map<String, dynamic>.from(stats?['summary'] as Map? ?? {});
    final delivered = (summary['delivered'] as num? ?? 0).toInt();
    final failed = (summary['failed_or_returned'] as num? ?? 0).toInt();
    final finished = delivered + failed;
    final pickups = stats?['pickups'] as Map?;
    final drivers = stats?['drivers'] as Map?;
    final services = (summary['by_service'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final rows = <(String, String)>[
      ('Tổng đơn', '${summary['total'] ?? 0}'),
      ('Đã giao', '$delivered'),
      ('Thất bại / hoàn hàng', '$failed'),
      ('Đã hủy', '${summary['cancelled'] ?? 0}'),
      ('Đang xử lý', '${summary['active'] ?? 0}'),
      (
        'Tỷ lệ giao thành công',
        finished == 0
            ? 'Chưa có dữ liệu'
            : '${(delivered * 100 / finished).toStringAsFixed(1)}%',
      ),
      (
        'Thời gian trung bình từ tạo đơn đến giao',
        cloudMinutes(summary['avg_delivery_minutes']),
      ),
      (
        'Thời gian trung bình từ lấy hàng đến giao',
        cloudMinutes(summary['avg_transit_minutes']),
      ),
      if (pickups != null)
        (
          'Phiếu thu gom chờ điều xe / đã điều xe',
          '${pickups['requested'] ?? 0} / ${pickups['assigned'] ?? 0}',
        ),
      if (drivers != null)
        (
          'Tài xế đã duyệt / đang có chuyến',
          '${drivers['approved'] ?? 0} / ${drivers['on_trip'] ?? 0}',
        ),
    ];
    return GhstLuminousCard(
      key: const ValueKey('cloud-delivery-stats'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      accentGlow: tokens.sapphire.glow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stats?['scope'] == 'network'
                      ? 'Thống kê giao hàng toàn mạng · 30 ngày'
                      : 'Thống kê giao hàng của bạn · 30 ngày',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: tokens.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Tải lại thống kê',
                onPressed: _busy ? null : _load,
                icon: const GhstButtonIcon(Icons.refresh),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (stats != null) ...[
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(color: tokens.inkSecondary),
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: tokens.ink,
                      ),
                    ),
                  ],
                ),
              ),
            if (services.isNotEmpty) ...[
              Divider(height: 20, color: tokens.border),
              Text(
                'Theo dịch vụ',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: tokens.ink,
                ),
              ),
              for (final s in services)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '${cloudServiceTypes[s['service_type']] ?? s['service_type']}: '
                    '${s['delivered']}/${s['total']} đơn đã giao · '
                    'TB ${cloudMinutes(s['avg_delivery_minutes'])}',
                    style: TextStyle(color: tokens.inkSecondary),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class DriverReviewsPanel extends StatefulWidget {
  const DriverReviewsPanel({super.key, required this.service, this.lease});

  final CloudOrdersService service;
  final CloudSessionLease? lease;

  @override
  State<DriverReviewsPanel> createState() => _DriverReviewsPanelState();
}

class _DriverReviewsPanelState extends State<DriverReviewsPanel> {
  Map<String, dynamic>? _payload;
  bool _busy = false;
  String? _error;
  String? _replyingId;
  int _generation = 0;
  final Map<String, TextEditingController> _replyControllers = {};
  final Set<String> _editingIds = <String>{};

  bool get _allowed => mounted && (widget.lease?.valid ?? true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    for (final ctrl in _replyControllers.values) {
      ctrl.dispose();
    }
    _replyControllers.clear();
    super.dispose();
  }

  TextEditingController _controllerFor(String id, String initial) {
    return _replyControllers.putIfAbsent(
      id,
      () => TextEditingController(text: initial),
    );
  }

  Future<void> _load() async {
    if (!_allowed) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.service.fetchDriverReviews();
      if (_allowed && generation == _generation) {
        setState(() => _payload = result);
      }
    } catch (error) {
      if (!_allowed || generation != _generation) return;
      if (widget.lease?.handleAccessFailure(error) == true) return;
      setState(
        () => _error = cloudLogisticsMessage(
          error,
          'Chưa tải được đánh giá tài xế.',
        ),
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _submitReply(String reviewId) async {
    if (!_allowed || _replyingId != null) return;
    final text = (_replyControllers[reviewId]?.text ?? '').trim();
    if (text.length < 2) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Phản hồi cần tối thiểu 2 ký tự.'),
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _replyingId = reviewId);
    try {
      await widget.service.market('review_reply', {
        'review_kind': 'partner',
        'id': reviewId,
        'reply': text,
      });
      if (!_allowed) return;
      setState(() => _editingIds.remove(reviewId));
      messenger?.showSnackBar(
        const SnackBar(content: Text('Đã gửi phản hồi đánh giá.')),
      );
      await _load();
    } catch (error) {
      if (!_allowed) return;
      if (widget.lease?.handleAccessFailure(error) == true) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            cloudLogisticsMessage(error, 'Chưa gửi được phản hồi đánh giá.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _replyingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final payload = _payload;
    final ratingAvg = (payload?['rating_avg'] as num? ?? 0).toDouble();
    final ratingCount = (payload?['rating_count'] as num? ?? 0).toInt();
    final reviews = (payload?['reviews'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    return GhstLuminousCard(
      key: const ValueKey('driver-reviews-panel'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      accentGlow: tokens.amber.glow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tokens.amber.fill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tokens.amber.border),
                ),
                child: GhstButtonIcon(
                  Icons.star_rounded,
                  color: tokens.amber.icon,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đánh giá từ khách hàng',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: tokens.ink,
                      ),
                    ),
                    Text(
                      ratingCount == 0
                          ? 'Chưa có lượt đánh giá nào'
                          : '${ratingAvg.toStringAsFixed(1)} / 5.0 sao · $ratingCount lượt đánh giá',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: tokens.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Tải lại đánh giá',
                onPressed: _busy ? null : _load,
                icon: const GhstButtonIcon(Icons.refresh),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (payload != null && reviews.isEmpty && !_busy) ...[
            const SizedBox(height: 12),
            Text(
              'Các đánh giá sau khi hoàn tất chuyến giao sẽ hiển thị tại đây để bạn theo dõi và phản hồi trực tiếp.',
              style: TextStyle(fontSize: 13, color: tokens.inkSecondary),
            ),
          ],
          for (final review in reviews) ...[
            const SizedBox(height: 12),
            _buildReviewItem(context, tokens, review),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewItem(
    BuildContext context,
    GhstThemeTokens tokens,
    Map<String, dynamic> review,
  ) {
    final id = '${review['id'] ?? ''}';
    final stars = (review['rating'] as num? ?? 5).toInt().clamp(1, 5);
    final comment = '${review['body'] ?? review['comment'] ?? ''}'.trim();
    final existingReply =
        '${review['reply'] ?? review['driver_reply'] ?? ''}'.trim();
    final showEditor = existingReply.isEmpty || _editingIds.contains(id);
    final ctrl = _controllerFor(id, existingReply);
    final isSubmitting = _replyingId == id;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.cardSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 5; i++)
                    GhstButtonIcon(
                      i < stars
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 16,
                      color: tokens.amber.icon,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    '${review['tracking_code'] ?? 'Chuyến giao'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: tokens.ink,
                    ),
                  ),
                ],
              ),
              Text(
                cloudDate(review['created_at']),
                style: TextStyle(fontSize: 11.5, color: tokens.inkMuted),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              comment,
              style: TextStyle(fontSize: 13.5, color: tokens.ink),
            ),
          ],
          const SizedBox(height: 8),
          if (!showEditor)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tokens.emerald.fill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.emerald.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Phản hồi của tài xế',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: tokens.emerald.foreground,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          ctrl.text = existingReply;
                          setState(() => _editingIds.add(id));
                        },
                        icon: const GhstButtonIcon.glyph(GhstActionKind.reply, size: 16),

                        label: const Text('Sửa phản hồi'),
                      ),
                    ],
                  ),
                  Text(
                    existingReply,
                    style: TextStyle(fontSize: 13, color: tokens.ink),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: ValueKey('driver-review-reply-input-$id'),
                  controller: ctrl,
                  enabled: !isSubmitting,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Phản hồi khách hàng',
                    hintText: 'Nhập lời cảm ơn hoặc phản hồi về chuyến giao...',
                    isDense: true,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (existingReply.isNotEmpty)
                      TextButton.icon(
                        onPressed: isSubmitting
                            ? null
                            : () => setState(() => _editingIds.remove(id)),
                        icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

                        label: const Text('Hủy'),
                      ),
                    FilledButton.tonalIcon(
                      key: ValueKey('driver-review-reply-submit-$id'),
                      onPressed: isSubmitting ? null : () => _submitReply(id),
                      icon: const GhstButtonIcon(Icons.reply_rounded, size: 18),
                      label: Text(
                        isSubmitting ? 'Đang gửi...' : 'Gửi phản hồi',
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class DriverLiveCockpitPanel extends StatefulWidget {
  const DriverLiveCockpitPanel({
    super.key,
    required this.session,
    this.lease,
    this.onOpenQueue,
    this.onOpenOrderDetails,
  });

  final CloudAccountSession session;
  final CloudSessionLease? lease;
  final VoidCallback? onOpenQueue;
  final ValueChanged<Map<String, dynamic>>? onOpenOrderDetails;

  @override
  State<DriverLiveCockpitPanel> createState() => _DriverLiveCockpitPanelState();
}

class _DriverLiveCockpitPanelState extends State<DriverLiveCockpitPanel> {
  static const _activeStatuses = {
    'accepted',
    'arrivingPickup',
    'inTransit',
    'returning',
    'failed',
  };

  List<Map<String, dynamic>> _activeTrips = const [];
  String? _selectedOrderId;
  GeoPoint? _pushedGps;
  bool _busy = false;
  bool _acting = false;
  String? _error;
  Timer? _poll;
  int _generation = 0;

  CloudOrdersService get _api => widget.session.service;
  bool get _allowed => mounted && (widget.lease?.valid ?? true);

  bool get _isAutomatedTestBinding {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTest');
  }

  @override
  void initState() {
    super.initState();
    _load();
    if (!_isAutomatedTestBinding) {
      _poll = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_allowed && !_busy && !_acting) {
          _load(silent: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!_allowed || !_api.signedIn) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      if (!silent) _error = null;
    });
    try {
      final response = await _api.request(
        'orders',
        query: {'queue': 'false', 'limit': '25'},
      );
      if (!_allowed || generation != _generation) return;
      final rows = (response['orders'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where(
            (item) =>
                item['driver_id'] == _api.userId &&
                _activeStatuses.contains('${item['status'] ?? ''}'),
          )
          .toList();
      setState(() {
        _activeTrips = rows;
        if (rows.isEmpty) {
          _selectedOrderId = null;
        } else if (!rows.any((row) => '${row['id']}' == _selectedOrderId)) {
          _selectedOrderId = '${rows.first['id']}';
        }
      });
    } catch (error) {
      if (!_allowed || generation != _generation) return;
      if (widget.lease?.handleAccessFailure(error) == true) return;
      if (!silent) {
        setState(
          () => _error = cloudLogisticsMessage(
            error,
            'Chưa tải được hành trình trực tuyến.',
          ),
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Map<String, dynamic>? get _selectedTrip {
    if (_activeTrips.isEmpty) return null;
    for (final trip in _activeTrips) {
      if ('${trip['id']}' == _selectedOrderId) return trip;
    }
    return _activeTrips.first;
  }

  GeoPoint? _pointFrom(dynamic latRaw, dynamic lngRaw) {
    final lat = latRaw is num ? latRaw.toDouble() : double.tryParse('$latRaw');
    final lng = lngRaw is num ? lngRaw.toDouble() : double.tryParse('$lngRaw');
    if (lat == null ||
        lng == null ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180 ||
        (lat == 0 && lng == 0)) {
      return null;
    }
    return GeoPoint(latitude: lat, longitude: lng);
  }

  Future<void> _quickTransition(Map<String, dynamic> trip, String action) async {
    if (!_allowed || _acting) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _acting = true);
    try {
      await _api.command('orders/${trip['id']}/transition', {
        'action': action,
        'version': trip['version'],
        'reason': '',
      });
      if (!_allowed) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Đã cập nhật: ${cloudActions[action] ?? action}'),
        ),
      );
      await _load();
    } catch (error) {
      if (!_allowed) return;
      if (widget.lease?.handleAccessFailure(error) == true) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            cloudLogisticsMessage(error, 'Chưa cập nhật được trạng thái chuyến.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _broadcastRealGps(Map<String, dynamic> trip) async {
    if (!_allowed || _acting) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _acting = true);
    try {
      final store = AppStateStore.instance;
      final pos = await store.startRealTimeDeviceGpsTracking(
        syncDriverLocation: true,
        forcePromptPermission: true,
      );
      if (pos == null) {
        if (mounted) {
          messenger?.showSnackBar(
            SnackBar(content: Text(store.liveGpsStatusMessage)),
          );
        }
        return;
      }
      await _api.orderLive('push_gps', {
        'order_id': '${trip['id']}',
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'heading': store.activeDriverBearing,
      });
      if (!_allowed) return;
      setState(() => _pushedGps = pos);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Đã phát tọa độ GPS thực của tài xế lên hành trình.'),
        ),
      );
      await _load(silent: true);
    } catch (error) {
      if (!_allowed) return;
      if (widget.lease?.handleAccessFailure(error) == true) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            cloudLogisticsMessage(error, 'Chưa phát được định vị GPS.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _markCheckpoint(
    Map<String, dynamic> trip,
    String checkpointKey,
    String note,
  ) async {
    if (!_allowed || _acting) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _acting = true);
    try {
      await _api.orderLive('mark_checkpoint', {
        'order_id': '${trip['id']}',
        'checkpoint_key': checkpointKey,
        'note': note,
      });
      if (!_allowed) return;
      messenger?.showSnackBar(SnackBar(content: Text('Đã ghi nhận: $note')));
      await _load(silent: true);
    } catch (error) {
      if (!_allowed) return;
      if (widget.lease?.handleAccessFailure(error) == true) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            cloudLogisticsMessage(error, 'Chưa ghi nhận được điểm dừng.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _openGoogleDirections(List<GeoPoint> waypoints) async {
    if (waypoints.length < 2) return;
    final origin = '${waypoints.first.latitude},${waypoints.first.longitude}';
    final destination =
        '${waypoints.last.latitude},${waypoints.last.longitude}';
    final mids = waypoints.length > 2
        ? waypoints
              .sublist(1, waypoints.length - 1)
              .map((p) => '${p.latitude},${p.longitude}')
              .join('|')
        : '';
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'origin': origin,
      'destination': destination,
      if (mids.isNotEmpty) 'waypoints': mids,
      'travelmode': 'driving',
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final selected = _selectedTrip;

    return ListView(
      key: const ValueKey('driver-live-cockpit-panel'),
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GhstAuroraBanner(
                  gradient: tokens.driverGradient,
                  accentOrbColor: const Color(0x5538BDF8),
                  child: Row(
                    children: [
                      const Animated3dIconBadge(
                        style: Icon3dStyle.driverPartner,
                        size: 46,
                        showRadarPulse: false,
                      ),
                      const SizedBox(width: 12),
                      const GhstPulseBeacon(
                        color: Color(0xFF34D399),
                        size: 10,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Buồng lái dẫn đường trực tuyến',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              selected == null
                                  ? 'Sẵn sàng nhận chuyến mới · Radar khu vực đang hoạt động'
                                  : 'Đang điều phối ${_activeTrips.length} chuyến giao · Đồng bộ GPS & điểm dừng thời gian thực',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Làm mới hành trình',
                        onPressed: _busy ? null : _load,
                        icon: const GhstButtonIcon(Icons.refresh, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (selected == null)
                  GhstLuminousCard(
                    accentGlow: tokens.cyan.glow,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Chưa có chuyến đang thực hiện',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: tokens.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Mở sàn chuyến chờ nhận để xem lộ trình dự kiến, khu vực lấy - giao và nhận đơn ngay.',
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.inkSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                          child: Map3dPerspectiveWidget(
                            mode: MapViewMode.driverRadar,
                            height: 260,
                          ),
                        ),
                        if (widget.onOpenQueue != null) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                              key: const ValueKey('driver-cockpit-open-queue'),
                              onPressed: widget.onOpenQueue,
                              icon: const GhstButtonIcon(Icons.bolt_rounded),
                              label: const Text('Mở sàn chuyến chờ nhận'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  _buildActiveTripCockpit(context, tokens, selected),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveTripCockpit(
    BuildContext context,
    GhstThemeTokens tokens,
    Map<String, dynamic> trip,
  ) {
    final details = Map<String, dynamic>.from(trip['details'] as Map? ?? {});
    final status = '${trip['status'] ?? ''}';
    final pickup = _pointFrom(details['pickup_lat'], details['pickup_lng']);
    final dropoff = _pointFrom(details['dropoff_lat'], details['dropoff_lng']);
    final rawStops =
        ((details['extra_stops'] as List?) ??
                (details['stops'] as List?) ??
                const [])
            .whereType<Map>()
            .map((s) => Map<String, dynamic>.from(s))
            .toList();
    final extraStopPoints = <GeoPoint>[];
    final extraStopLabels = <String>[];
    for (var i = 0; i < rawStops.length; i++) {
      final pt = _pointFrom(rawStops[i]['lat'], rawStops[i]['lng']);
      if (pt != null) {
        extraStopPoints.add(pt);
        final addr = '${rawStops[i]['address'] ?? ''}'.trim();
        extraStopLabels.add(
          addr.isEmpty ? 'Điểm dừng ${i + 1}' : 'Đ${i + 1}: $addr',
        );
      }
    }
    final roundTrip =
        details['is_round_trip'] == true || details['round_trip'] == true;
    final waypoints = <GeoPoint>[
      ?pickup,
      ...extraStopPoints,
      ?dropoff,
      if (roundTrip && pickup != null && dropoff != null) pickup,
    ];
    final latestGpsMap = trip['latest_gps'] as Map?;
    final driverPoint =
        _pushedGps ??
        _pointFrom(
          latestGpsMap?['latitude'] ?? latestGpsMap?['lat'],
          latestGpsMap?['longitude'] ?? latestGpsMap?['lng'],
        );
    final completedRaw =
        (trip['completed_checkpoints'] as List?) ??
        (details['completed_checkpoints'] as List?) ??
        const [];
    final completedCheckpoints = <String>{
      for (final item in completedRaw)
        if (item is Map && item['key'] != null)
          '${item['key']}'
        else if (item is String && item.trim().isNotEmpty)
          item.trim(),
    };
    final recipientPhone = '${details['recipient_phone'] ?? ''}'.trim();
    final recipientName = '${details['recipient_name'] ?? ''}'.trim();
    final codAmount = (trip['cod_amount'] as num? ?? 0).toDouble();
    final payableFee =
        ((trip['payable_fee'] ?? trip['shipping_fee']) as num? ?? 0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_activeTrips.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in _activeTrips)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(showCheckmark: false, avatar: const GhstButtonIcon.glyph(GhstActionKind.receipt, size: 15), label: Text(
                        '${item['tracking_code']} · ${cloudStatuses[item['status']] ?? item['status']}',
                      ), selected: '${item['id']}' == '${trip['id']}', onSelected: (_) => setState(() {
                        _selectedOrderId = '${item['id']}';
                        _pushedGps = null;
                      }),),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        GhstLuminousCard(
          accentGlow: tokens.emerald.glow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GhstPulseBeacon(color: tokens.emerald.icon, size: 9),
                      const SizedBox(width: 8),
                      SelectableText(
                        '${trip['tracking_code']}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: tokens.ink,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.sapphire.fill,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: tokens.sapphire.border),
                        ),
                        child: Text(
                          cloudStatuses[status] ?? status,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: tokens.sapphire.foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.onOpenOrderDetails != null)
                    OutlinedButton.icon(
                      key: const ValueKey('driver-cockpit-open-details'),
                      onPressed: () => widget.onOpenOrderDetails!(trip),
                      icon: const GhstButtonIcon(Icons.open_in_new_rounded, size: 17),
                      label: const Text('Mở chi tiết chuyến'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Map3dPerspectiveWidget(
                  key: const ValueKey('driver-cockpit-map'),
                  mode: MapViewMode.driverTurnByTurn,
                  height: 290,
                  routePoints: waypoints.length >= 2 ? waypoints : const [],
                  explicitDropoffPoint: dropoff,
                  extraStopPoints: extraStopPoints,
                  extraStopLabels: extraStopLabels,
                  driverLocation: driverPoint,
                  driverLabel: 'Vị trí tài xế',
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.cardSubtle,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lấy hàng: ${details['pickup_address'] ?? 'Chưa cập nhật'}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: tokens.ink,
                      ),
                    ),
                    for (var i = 0; i < rawStops.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Điểm dừng ${i + 1}: ${rawStops[i]['address'] ?? ''}'
                          '${completedCheckpoints.contains('stop:$i') ? ' (Đã qua)' : ''}',
                          style: TextStyle(
                            color: completedCheckpoints.contains('stop:$i')
                                ? tokens.emerald.foreground
                                : tokens.inkSecondary,
                            fontWeight: completedCheckpoints.contains('stop:$i')
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Giao hàng: ${details['dropoff_address'] ?? 'Chưa cập nhật'}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: tokens.ink,
                      ),
                    ),
                    if (roundTrip)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          completedCheckpoints.contains('return_leg')
                              ? 'Khứ hồi về điểm lấy: Đã hoàn tất'
                              : 'Khứ hồi: Quay lại điểm lấy sau khi giao',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: tokens.violet.foreground,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      'Người nhận: $recipientName · $recipientPhone · Cước: ${CurrencyFormatter.formatVnd(payableFee)} · COD: ${CurrencyFormatter.formatVnd(codAmount)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: tokens.inkSecondary,
                      ),
                    ),
                    if ('${trip['delivery_instruction'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Chỉ dẫn giao: ${trip['delivery_instruction']}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: tokens.amber.foreground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (status == 'accepted')
                    FilledButton.icon(
                      onPressed: _acting
                          ? null
                          : () => _quickTransition(trip, 'arrive'),
                      icon: const GhstButtonIcon(Icons.storefront_outlined, size: 18),
                      label: const Text('Báo đã đến điểm lấy'),
                    ),
                  if (status == 'arrivingPickup')
                    FilledButton.icon(
                      onPressed: _acting
                          ? null
                          : () => _quickTransition(trip, 'pickup'),
                      icon: const GhstButtonIcon(Icons.inventory_2_outlined, size: 18),
                      label: const Text('Xác nhận đã lấy hàng'),
                    ),
                  if (status == 'inTransit' &&
                      widget.onOpenOrderDetails != null)
                    FilledButton.icon(
                      onPressed: _acting
                          ? null
                          : () => widget.onOpenOrderDetails!(trip),
                      icon: const GhstButtonIcon(Icons.task_alt_rounded, size: 18),
                      label: const Text('Xác nhận giao & đối soát'),
                    ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('driver-cockpit-push-gps'),
                    onPressed: _acting ? null : () => _broadcastRealGps(trip),
                    icon: const GhstButtonIcon(Icons.my_location_rounded, size: 18),
                    label: const Text('Phát định vị GPS'),
                  ),
                  if (waypoints.length >= 2)
                    OutlinedButton.icon(
                      onPressed: () => _openGoogleDirections(waypoints),
                      icon: const GhstButtonIcon(Icons.directions_outlined, size: 18),
                      label: const Text('Chỉ đường Google Maps'),
                    ),
                  if (recipientPhone.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(
                        Uri(scheme: 'tel', path: recipientPhone),
                      ),
                      icon: const GhstButtonIcon(Icons.call_outlined, size: 18),
                      label: const Text('Gọi người nhận'),
                    ),
                  if (const {'inTransit', 'returning'}.contains(status)) ...[
                    for (var i = 0; i < rawStops.length; i++)
                      if (!completedCheckpoints.contains('stop:$i'))
                        ActionChip(
                          key: ValueKey('driver-cockpit-checkpoint-$i'),
                          avatar: const GhstButtonIcon(Icons.place_outlined, size: 16),
                          label: Text('Đã qua điểm dừng ${i + 1}'),
                          onPressed: _acting
                              ? null
                              : () => _markCheckpoint(
                                  trip,
                                  'stop:$i',
                                  'Đã hoàn thành điểm dừng ${i + 1}',
                                ),
                        ),
                    if (roundTrip &&
                        !completedCheckpoints.contains('return_leg'))
                      ActionChip(
                        key: const ValueKey('driver-cockpit-checkpoint-return'),
                        avatar: const GhstButtonIcon(Icons.sync_alt, size: 16),
                        label: const Text('Hoàn tất khứ hồi'),
                        onPressed: _acting
                            ? null
                            : () => _markCheckpoint(
                                trip,
                                'return_leg',
                                'Đã hoàn tất chặng khứ hồi về điểm lấy',
                              ),
                      ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
