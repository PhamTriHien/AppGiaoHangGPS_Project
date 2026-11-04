import 'package:flutter/material.dart';
import 'ghst_button_icon.dart';

class CloudMembershipDecisionDialog extends StatefulWidget {
  const CloudMembershipDecisionDialog({
    super.key,
    required this.title,
    required this.accountName,
    required this.reasonRequired,
  });
  final String title, accountName;
  final bool reasonRequired;
  @override
  State<CloudMembershipDecisionDialog> createState() =>
      _CloudMembershipDecisionDialogState();
}

class _CloudMembershipDecisionDialogState
    extends State<CloudMembershipDecisionDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.accountName),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: widget.reasonRequired ? 'Lý do' : 'Ghi chú',
              ),
              validator: (value) =>
                  widget.reasonRequired && (value?.trim().length ?? 0) < 3
                  ? 'Nhập lý do ít nhất 3 ký tự.'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const GhstButtonIcon.glyph(GhstActionKind.back, size: 16),

        label: const Text('Quay lại'),
      ),
      FilledButton.icon(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _reason.text.trim());
          }
        },
        icon: const GhstButtonIcon.glyph(GhstActionKind.checkCircle, size: 16),

        label: const Text('Xác nhận'),
      ),
    ],
  );
}
