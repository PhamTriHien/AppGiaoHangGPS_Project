import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_orders_service.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import 'cloud_order_labels.dart';
import 'cloud_session_boundary.dart';

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
    if (trust == null) {
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
    final tier = trust['tier'];
    final flagged = trust['flagged'] == true;
    final color = switch (tier) {
      'high_risk' => Theme.of(context).colorScheme.error,
      'confirm' => Colors.orange.shade800,
      _ => Colors.green.shade700,
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tín nhiệm người nhận: ${trust['score']}/100 · $tierLabel',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Trong các đơn của bạn: ${trust['delivered']} đơn giao thành công · ${trust['failed_or_returned']} đơn thất bại/hoàn hàng.',
            style: const TextStyle(fontSize: 12.5),
          ),
          Text(advice, style: const TextStyle(fontSize: 12.5)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy || !widget.enabled
                  ? null
                  : () => _load('${trust['phone']}', flagged: !flagged),
              icon: Icon(flagged ? Icons.flag_outlined : Icons.flag, size: 18),
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
          CheckedPopupMenuItem(
            value: note,
            checked: current == note,
            child: Text(note),
          ),
        if (current.isNotEmpty)
          const PopupMenuItem(value: '', child: Text('Xóa chỉ dẫn')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.edit_note_outlined, size: 18),
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
    return Card(
      key: const ValueKey('cloud-delivery-stats'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tải lại thống kê',
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh),
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
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text(label)),
                      Text(
                        value,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              if (services.isNotEmpty) ...[
                const Divider(height: 20),
                const Text(
                  'Theo dịch vụ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final s in services)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '${cloudServiceTypes[s['service_type']] ?? s['service_type']}: '
                      '${s['delivered']}/${s['total']} đơn đã giao · '
                      'TB ${cloudMinutes(s['avg_delivery_minutes'])}',
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
