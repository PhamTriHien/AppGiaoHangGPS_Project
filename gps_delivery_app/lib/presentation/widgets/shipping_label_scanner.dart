import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/integrations/delivery_api_client.dart';
import 'ghst_button_icon.dart';

class ShippingLabelScanner extends StatefulWidget {
  const ShippingLabelScanner({super.key, required this.onApply, this.api});
  final ValueChanged<Map<String, String>> onApply;
  final DeliveryApiClient? api;
  @override
  State<ShippingLabelScanner> createState() => _ShippingLabelScannerState();
}

class _ShippingLabelScannerState extends State<ShippingLabelScanner> {
  bool _busy = false;
  String? _error;
  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'PNG / JPEG',
            extensions: ['png', 'jpg', 'jpeg'],
            mimeTypes: ['image/png', 'image/jpeg'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 5000000) {
        throw Exception('Chọn ảnh tối đa 5 MB.');
      }
      final result = await (widget.api ?? DeliveryApiClient.instance)
          .recognizeLabel(await file.readAsBytes());
      if (!mounted) return;
      final name = TextEditingController(
        text: result['recipientName'] as String? ?? '',
      );
      final phone = TextEditingController(
        text: result['recipientPhone'] as String? ?? '',
      );
      final address = TextEditingController(
        text: result['dropoffAddress'] as String? ?? '',
      );
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Kiểm tra nhãn vận đơn'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Người nhận'),
                  ),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại',
                    ),
                  ),
                  TextField(
                    controller: address,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ giao',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    title: const Text('Văn bản nhận dạng'),
                    children: [SelectableText(result['text'] as String? ?? '')],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(context, false),
              icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

              label: const Text('Hủy'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const GhstButtonIcon.glyph(GhstActionKind.checkCircle, size: 16),

              label: const Text('Áp dụng'),
            ),
          ],
        ),
      );
      if (accepted == true && mounted) {
        widget.onApply({
          'recipientName': name.text.trim(),
          'recipientPhone': phone.text.trim(),
          'dropoffAddress': address.text.trim(),
        });
      }
      // Wait for the route's exit animation before releasing its controllers.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      name.dispose();
      phone.dispose();
      address.dispose();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Không đọc được ảnh. Kiểm tra kết nối và chọn ảnh rõ nét tối đa 5 MB.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton.icon(
        onPressed: _busy ? null : _scan,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const GhstButtonIcon(Icons.document_scanner_outlined),
        label: Text(_busy ? 'Đang đọc nhãn...' : 'Quét nhãn vận đơn'),
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
    ],
  );
}
