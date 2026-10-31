import 'dart:convert';

List<Map<String, dynamic>> marketRows(dynamic value) => value is List
    ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
    : [];

String marketSelectionKey(dynamic value) {
  final rows =
      marketRows(value)
          .map((v) => {'group_id': v['group_id'], 'option_id': v['option_id']})
          .toList()
        ..sort((a, b) {
          final group = '${a['group_id']}'.compareTo('${b['group_id']}');
          return group != 0
              ? group
              : '${a['option_id']}'.compareTo('${b['option_id']}');
        });
  return jsonEncode(rows);
}

String marketOptionNames(dynamic value) =>
    marketRows(value).map((v) => '${v['group_name']}: ${v['name']}').join(', ');
