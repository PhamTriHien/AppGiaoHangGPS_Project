import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/integrations/bank_directory_service.dart';
import 'ghst_button_icon.dart';

class BankDirectoryField extends StatefulWidget {
  const BankDirectoryField({
    super.key,
    this.controller,
    this.initialValue = '',
    required this.label,
    this.onChanged,
    this.service,
  });

  final TextEditingController? controller;
  final String initialValue;
  final String label;
  final ValueChanged<String>? onChanged;
  final BankDirectoryService? service;

  @override
  State<BankDirectoryField> createState() => _BankDirectoryFieldState();
}

class _BankDirectoryFieldState extends State<BankDirectoryField> {
  late TextEditingController _controller;
  bool _choosing = false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant BankDirectoryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller == null) _controller.dispose();
      _controller =
          widget.controller ?? TextEditingController(text: widget.initialValue);
    } else if (widget.controller == null &&
        oldWidget.initialValue != widget.initialValue &&
        _controller.text != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    if (_choosing) return;
    setState(() => _choosing = true);
    final selected = await showDialog<DirectoryBank>(
      context: context,
      builder: (_) => _BankDirectoryDialog(
        service: widget.service ?? BankDirectoryService.instance,
      ),
    );
    if (!mounted) return;
    setState(() => _choosing = false);
    if (selected == null) return;
    _controller.text = selected.label;
    widget.onChanged?.call(selected.label);
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: _controller,
    onChanged: widget.onChanged,
    decoration: InputDecoration(
      labelText: widget.label,
      suffixIcon: IconButton(
        tooltip: 'Chọn ngân hàng',
        onPressed: _choosing ? null : _choose,
        icon: const GhstButtonIcon(Icons.account_balance_outlined),
      ),
    ),
  );
}

class _BankDirectoryDialog extends StatefulWidget {
  const _BankDirectoryDialog({required this.service});
  final BankDirectoryService service;

  @override
  State<_BankDirectoryDialog> createState() => _BankDirectoryDialogState();
}

class _BankDirectoryDialogState extends State<_BankDirectoryDialog> {
  late Future<List<DirectoryBank>> _request;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _request = widget.service.load();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: SizedBox(
      width: 520,
      height: math.min(520, MediaQuery.sizeOf(context).height * 0.8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Chọn ngân hàng',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.pop(context),
                  icon: const GhstButtonIcon(Icons.close),
                ),
              ],
            ),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Tên, mã ngân hàng hoặc BIN',
                prefixIcon: GhstButtonIcon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<DirectoryBank>>(
                future: _request,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Chưa tải được danh sách ngân hàng.',
                            textAlign: TextAlign.center,
                          ),
                          IconButton(
                            tooltip: 'Thử lại',
                            onPressed: () => setState(
                              () => _request = widget.service.load(),
                            ),
                            icon: const GhstButtonIcon(Icons.refresh),
                          ),
                        ],
                      ),
                    );
                  }
                  final banks = snapshot.data!
                      .where((bank) => bank.matches(_query))
                      .toList();
                  if (banks.isEmpty) {
                    return const Center(
                      child: Text('Không tìm thấy ngân hàng phù hợp.'),
                    );
                  }
                  return ListView.separated(
                    itemCount: banks.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final bank = banks[index];
                      return ListTile(
                        title: Text(bank.label),
                        subtitle: Text('${bank.name}\nBIN ${bank.bin}'),
                        isThreeLine: true,
                        onTap: () => Navigator.pop(context, bank),
                      );
                    },
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Nguồn: VietQR / NAPAS',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
