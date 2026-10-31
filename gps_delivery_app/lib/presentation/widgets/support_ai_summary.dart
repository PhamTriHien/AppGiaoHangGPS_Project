import 'package:flutter/material.dart';

import '../../core/integrations/delivery_api_client.dart';

class SupportAiSummary extends StatefulWidget {
  const SupportAiSummary({
    super.key,
    required this.text,
    required this.onApply,
  });
  final String text;
  final ValueChanged<String> onApply;
  @override
  State<SupportAiSummary> createState() => _SupportAiSummaryState();
}

class _SupportAiSummaryState extends State<SupportAiSummary> {
  bool _busy = false;
  String? _error;
  Future<void> _summarize() async {
    final masked = widget.text
        .replaceAll(RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}'), '[email]')
        .replaceAll(RegExp(r'(?:\+84|0)[\d .-]{8,15}'), '[số điện thoại]');
    final input = TextEditingController(text: masked);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kiểm tra nội dung gửi AI'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: input,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Nội dung đã ẩn tên, địa chỉ và thông tin cá nhân',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gửi bản đã ẩn thông tin'),
          ),
        ],
      ),
    );
    final text = input.text;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await DeliveryApiClient.instance.request(
        'support-summary',
        body: {'text': text, 'redacted': true},
      );
      if (!mounted) return;
      final summary = result['summary'] as String;
      final apply = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Gợi ý xử lý'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(child: SelectableText(summary)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Đóng'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Dùng làm bản nháp'),
            ),
          ],
        ),
      );
      if (apply == true && mounted) widget.onApply(summary);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'AI chưa khả dụng. Kiểm tra cấu hình dịch vụ.');
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
        onPressed: _busy ? null : _summarize,
        icon: const Icon(Icons.auto_awesome_outlined),
        label: Text(_busy ? 'Đang phân tích...' : 'Gợi ý xử lý'),
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
