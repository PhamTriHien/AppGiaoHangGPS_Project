import 'package:flutter/material.dart';

import '../../core/integrations/cloud_orders_service.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';

class CloudPricingDialog extends StatefulWidget {
  const CloudPricingDialog({
    super.key,
    required this.service,
    required this.pricing,
    this.lease,
  });
  final CloudOrdersService service;
  final Map<String, dynamic> pricing;
  final CloudSessionLease? lease;
  @override
  State<CloudPricingDialog> createState() => _CloudPricingDialogState();
}

class _CloudPricingDialogState extends State<CloudPricingDialog> {
  static const _labels = {
    'base_fee': 'Phí 2 km đầu',
    'per_km': 'Mỗi km tiếp theo',
    'express_fee': 'Phụ phí giao nhanh',
    'extra_kg': 'Mỗi kg vượt 5 kg',
  };
  final _form = GlobalKey<FormState>();
  late final _fields = {
    for (final key in _labels.keys)
      key: TextEditingController(text: '${widget.pricing[key]}'),
  };
  late final _identity = widget.service.identityScope;
  bool get _sameAccount =>
      widget.service.signedIn &&
      _identity == widget.service.identityScope &&
      (widget.lease?.valid ?? true);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_sameAccount || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.request(
        'pricing',
        body: {
          for (final entry in _fields.entries)
            entry.key: int.parse(entry.value.text.trim()),
          'version': widget.pricing['version'],
        },
      );
      if (mounted && _sameAccount) Navigator.pop(context, true);
    } catch (error) {
      if (mounted && _sameAccount) {
        setState(
          () => _error = error is PublicApiException
              ? error.message
              : 'Không lưu được bảng giá.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Bảng giá cước'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in _fields.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                    controller: entry.value,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _labels[entry.key], suffixText: 'đ',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (raw) {
                      final number = int.tryParse(raw?.trim() ?? '');
                      final max = ['per_km', 'extra_kg'].contains(entry.key)
                          ? 100000
                          : 1000000;
                      return number == null || number < 0 || number > max
                          ? 'Giá trị từ 0 đến $max'
                          : null;
                    },
                  ),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Đóng'),
      ),
      FilledButton.icon(
        onPressed: _busy ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: const Text('Lưu bảng giá'),
      ),
    ],
  );
}
