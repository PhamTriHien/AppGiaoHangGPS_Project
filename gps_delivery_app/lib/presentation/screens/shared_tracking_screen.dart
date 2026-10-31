import 'package:flutter/material.dart';

import '../../core/integrations/cloud_orders_service.dart';
import '../widgets/cloud_order_labels.dart';

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

  @override
  Widget build(BuildContext context) {
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
      appBar: AppBar(title: const Text('Theo dõi giao hàng')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _token,
                    maxLength: 64,
                    decoration: const InputDecoration(
                      labelText: 'Mã theo dõi được chia sẻ',
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.search),
                    label: const Text('Tra cứu'),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  const SizedBox(height: 24),
                  if (_error != null) Text(_error!),
                  if (_data != null) ...[
                    Text(
                      '${_data!['shop_name'] ?? 'GHST Express'}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      legacyDelivery[_data!['delivery_status']] ??
                          cloudStatuses[_data!['delivery_status']] ??
                          legacyDelivery[_data!['state']] ??
                          cloudStatuses[_data!['state']] ??
                          states[_data!['state']] ??
                          'Đang cập nhật',
                    ),
                    Text(
                      'Cập nhật: ${cloudDate(_data!['updated_at']).isEmpty ? _data!['updated_at'] : cloudDate(_data!['updated_at'])}',
                    ),
                    Text(
                      'Liên kết hết hạn: ${cloudDate(_data!['expires_at']).isEmpty ? _data!['expires_at'] : cloudDate(_data!['expires_at'])}',
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
}
