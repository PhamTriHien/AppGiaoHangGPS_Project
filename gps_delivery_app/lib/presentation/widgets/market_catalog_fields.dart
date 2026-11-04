import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/integrations/cloud_session_lease.dart';
import '../../core/utils/market_options.dart';
import 'ghst_button_icon.dart';

class MarketOptionEditor extends StatelessWidget {
  const MarketOptionEditor({
    super.key,
    required this.groups,
    required this.enabled,
    required this.onChanged,
  });
  final List<Map<String, dynamic>> groups;
  final bool enabled;
  final VoidCallback onChanged;

  Map<String, dynamic> _option() => {
    'id': const Uuid().v4(),
    'name': '',
    'price': 0,
  };
  Widget _name(Map<String, dynamic> row, String label) => TextFormField(
    initialValue: row['name'] as String,
    enabled: enabled,
    maxLength: 80,
    decoration: InputDecoration(labelText: label, counterText: ''),
    onChanged: (v) => row['name'] = v.trim(),
    validator: (v) => v == null || v.trim().isEmpty ? 'Nhập tên.' : null,
  );
  Widget _number(Map<String, dynamic> row, String key, String label, int max, {String? suffixText}) =>
      TextFormField(
        initialValue: '${row[key]}',
        enabled: enabled,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, suffixText: suffixText),
        onChanged: (v) => row[key] = int.tryParse(v) ?? -1,
        validator: (v) =>
            int.tryParse(v ?? '') == null ||
                int.parse(v!) < 0 ||
                int.parse(v) > max
            ? 'Từ 0 đến $max.'
            : null,
      );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Lựa chọn sản phẩm', style: Theme.of(context).textTheme.titleMedium),
      for (final group in groups)
        KeyedSubtree(
          key: ValueKey(group['id']),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Divider(),
              Row(
                children: [
                  Expanded(child: _name(group, 'Tên nhóm')),
                  IconButton(
                    tooltip: 'Xóa nhóm',
                    onPressed: !enabled
                        ? null
                        : () {
                            groups.remove(group);
                            onChanged();
                          },
                    icon: const GhstButtonIcon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _number(group, 'min', 'Tối thiểu', 12)),
                  const SizedBox(width: 12),
                  Expanded(child: _number(group, 'max', 'Tối đa', 12)),
                ],
              ),
              for (final option in marketRows(group['options']))
                KeyedSubtree(
                  key: ValueKey(option['id']),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _name(
                            _originalOption(group, option),
                            'Lựa chọn',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _number(
                            _originalOption(group, option),
                            'price',
                            'Phụ thu',
                            1000000, suffixText: 'đ',
                          ),
                        ),
                        IconButton(
                          tooltip: 'Xóa lựa chọn',
                          onPressed:
                              !enabled || (group['options'] as List).length <= 1
                              ? null
                              : () {
                                  (group['options'] as List).removeWhere(
                                    (o) => o['id'] == option['id'],
                                  );
                                  onChanged();
                                },
                          icon: const GhstButtonIcon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: !enabled || (group['options'] as List).length >= 12
                      ? null
                      : () {
                          (group['options'] as List).add(_option());
                          onChanged();
                        },
                  icon: const GhstButtonIcon(Icons.add),
                  label: const Text('Thêm lựa chọn'),
                ),
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: !enabled || groups.length >= 6
              ? null
              : () {
                  groups.add({
                    'id': const Uuid().v4(),
                    'name': '',
                    'min': 0,
                    'max': 1,
                    'options': [_option()],
                  });
                  onChanged();
                },
          icon: const GhstButtonIcon(Icons.add),
          label: const Text('Thêm nhóm'),
        ),
      ),
    ],
  );

  Map<String, dynamic> _originalOption(
    Map<String, dynamic> group,
    Map<String, dynamic> option,
  ) =>
      (group['options'] as List).firstWhere((o) => o['id'] == option['id'])
          as Map<String, dynamic>;
}

class MarketScheduleEditor extends StatelessWidget {
  const MarketScheduleEditor({
    super.key,
    required this.title,
    required this.slots,
    required this.enabled,
    required this.lease,
    required this.onChanged,
  });
  final String title;
  final List<Map<String, dynamic>> slots;
  final bool enabled;
  final CloudSessionLease lease;
  final VoidCallback onChanged;
  static const days = [
    'Thứ hai',
    'Thứ ba',
    'Thứ tư',
    'Thứ năm',
    'Thứ sáu',
    'Thứ bảy',
    'Chủ nhật',
  ];
  static String time(int value) =>
      '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
  static int? minute(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]), min = int.tryParse(parts[1]);
    if (hour == null ||
        min == null ||
        hour < 0 ||
        hour > 24 ||
        min < 0 ||
        min > 59 ||
        hour == 24 && min != 0) {
      return null;
    }
    return hour * 60 + min;
  }

  Future<void> _edit(BuildContext context, [int? index]) async {
    final old = index == null ? null : slots[index];
    int day = old?['day'] as int? ?? 1;
    final open = TextEditingController(text: time(old?['open'] as int? ?? 480));
    final close = TextEditingController(
      text: time(old?['close'] as int? ?? 1020),
    );
    final form = GlobalKey<FormState>();
    try {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialog) => AnimatedBuilder(
          animation: lease,
          builder: (_, _) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: Text(
                lease.valid ? 'Khung giờ' : 'Phiên làm việc đã thay đổi',
              ),
              content: !lease.valid
                  ? null
                  : SizedBox(
                      width: 360,
                      child: Form(
                        key: form,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DropdownButtonFormField<int>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), initialValue: day, decoration: const InputDecoration(
                                  labelText: 'Ngày',
                                ), items: [
                                  for (var d = 1; d <= 7; d++)
                                    DropdownMenuItem(
                                      value: d,
                                      child: Text(days[d - 1]),
                                    ),
                                ], onChanged: (v) {
                                  if (v != null) update(() => day = v);
                                },),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: open,
                                decoration: const InputDecoration(
                                  labelText: 'Giờ bắt đầu', hintText: '08:00',
                                ),
                                keyboardType: TextInputType.datetime,
                                validator: (v) =>
                                    minute(v ?? '') == null ||
                                        minute(v!)! >= 1440
                                    ? 'Nhập giờ 00:00–23:59.'
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: close,
                                decoration: const InputDecoration(
                                  labelText: 'Giờ kết thúc', hintText: '17:00',
                                ),
                                keyboardType: TextInputType.datetime,
                                validator: (v) {
                                  final start = minute(open.text),
                                      end = minute(v ?? '');
                                  if (start == null ||
                                      end == null ||
                                      end <= start) {
                                    return 'Giờ kết thúc phải sau giờ bắt đầu.';
                                  }
                                  for (var i = 0; i < slots.length; i++) {
                                    final s = slots[i];
                                    if (i != index &&
                                        s['day'] == day &&
                                        start < (s['close'] as int) &&
                                        end > (s['open'] as int)) {
                                      return 'Khung giờ bị trùng.';
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              actions: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(dialog),
                  icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

                  label: const Text('Đóng'),
                ),
                if (lease.valid)
                  FilledButton.icon(
                    onPressed: () {
                      if (form.currentState!.validate() && lease.valid) {
                        Navigator.pop(dialog, {
                          'day': day,
                          'open': minute(open.text),
                          'close': minute(close.text),
                        });
                      }
                    },
                    icon: const GhstButtonIcon.glyph(GhstActionKind.save, size: 16),

                    label: const Text('Lưu'),
                  ),
              ],
            ),
          ),
        ),
      );
      if (result != null && lease.valid) {
        if (index == null) {
          slots.add(result);
        } else {
          slots[index] = result;
        }
        onChanged();
      }
    } finally {
      // The dialog route keeps its text fields during its closing animation.
      Future<void>.delayed(const Duration(seconds: 1), () {
        open.dispose();
        close.dispose();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      if (slots.isEmpty) const Text('Không giới hạn khung giờ'),
      for (var i = 0; i < slots.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(days[(slots[i]['day'] as int) - 1]),
          subtitle: Text(
            '${time(slots[i]['open'] as int)}–${time(slots[i]['close'] as int)}',
          ),
          onTap: enabled ? () => _edit(context, i) : null,
          trailing: IconButton(
            tooltip: 'Xóa khung giờ',
            onPressed: !enabled
                ? null
                : () {
                    slots.removeAt(i);
                    onChanged();
                  },
            icon: const GhstButtonIcon(Icons.delete_outline),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: !enabled || slots.length >= 28
              ? null
              : () => _edit(context),
          icon: const GhstButtonIcon(Icons.add),
          label: const Text('Thêm khung giờ'),
        ),
      ),
    ],
  );
}
