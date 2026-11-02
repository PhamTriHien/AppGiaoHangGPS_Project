import 'package:csv/csv.dart';

import '../../domain/entities/geo_point.dart';

const cloudCsvMaxRows = 50;

class CloudCsvRow {
  const CloudCsvRow({
    required this.line,
    required this.details,
    this.point,
    this.error,
  });

  final int line;

  /// Recipient, parcel and service fields; pickup is chosen for the batch.
  final Map<String, dynamic> details;
  final GeoPoint? point;
  final String? error;
}

const _serviceAliases = {
  'standard': 'standard',
  'tieu chuan': 'standard',
  'tiêu chuẩn': 'standard',
  'express': 'express',
  'giao nhanh': 'express',
  'saving': 'saving',
  'tiet kiem': 'saving',
  'tiết kiệm': 'saving',
  'same_day_2h': 'same_day_2h',
  '2h': 'same_day_2h',
  'truck': 'truck',
  'xe tai': 'truck',
  'xe tải': 'truck',
};

/// Column order matches the existing bulk CSV import: recipient name, phone,
/// dropoff address, goods, weight (kg), COD, optional service and optional
/// dropoff latitude/longitude.
List<CloudCsvRow> parseCloudOrderCsv(String content) {
  final rows = Csv(dynamicTyping: false)
      .decode(content.replaceFirst('\uFEFF', ''))
      .map((row) => row.map((field) => field.toString().trim()).toList())
      .toList();
  final result = <CloudCsvRow>[];
  for (var i = 0; i < rows.length; i++) {
    final cols = rows[i];
    if (cols.every((field) => field.isEmpty)) continue;
    if (i == 0 &&
        const {
          'ten_nguoi_nhan',
          'nguoi_nhan',
          'recipient',
          'recipient_name',
          'tên người nhận',
        }.contains(cols.first.toLowerCase())) {
      continue;
    }
    if (result.length >= cloudCsvMaxRows) {
      throw const FormatException(
        'Mỗi lần nhập tối đa $cloudCsvMaxRows đơn. Hãy chia nhỏ tệp CSV.',
      );
    }
    String col(int index) => index < cols.length ? cols[index] : '';
    final name = col(0);
    final phone = col(1).replaceAll(RegExp(r'[\s.]'), '');
    final address = col(2);
    final goods = col(3);
    final weight = double.tryParse(col(4).replaceAll(',', '.'));
    var codText = col(5).replaceAll(RegExp(r'[đ\s]'), '');
    if (RegExp(r'^[0-9]{1,3}([.,][0-9]{3})+$').hasMatch(codText)) {
      codText = codText.replaceAll(RegExp(r'[.,]'), '');
    }
    final cod = codText.isEmpty ? 0 : int.tryParse(codText);
    final serviceRaw = col(6).toLowerCase();
    final service = serviceRaw.isEmpty
        ? 'standard'
        : _serviceAliases[serviceRaw];
    final lat = double.tryParse(col(7));
    final lng = double.tryParse(col(8));
    final point =
        lat != null &&
            lng != null &&
            lat.isFinite &&
            lng.isFinite &&
            lat.abs() <= 90 &&
            lng.abs() <= 180
        ? GeoPoint(latitude: lat, longitude: lng)
        : null;
    final maxWeight = service == 'truck' ? 500 : 30;
    final error = name.isEmpty || name.length > 120
        ? 'Tên người nhận cần 1-120 ký tự'
        : !RegExp(r'^0[35789][0-9]{8}$').hasMatch(phone)
        ? 'Số điện thoại Việt Nam không hợp lệ'
        : address.length < 5 || address.length > 500
        ? 'Địa chỉ giao cần 5-500 ký tự'
        : goods.isEmpty || goods.length > 1000
        ? 'Thiếu mô tả hàng hóa'
        : weight == null ||
              !weight.isFinite ||
              weight <= 0 ||
              weight > maxWeight
        ? 'Khối lượng phải lớn hơn 0 và tối đa $maxWeight kg'
        : cod == null || cod < 0 || cod > 20000000
        ? 'COD từ 0 đến 20.000.000 đồng'
        : service == null
        ? 'Dịch vụ không hỗ trợ'
        : (col(7).isNotEmpty || col(8).isNotEmpty) && point == null
        ? 'Tọa độ giao không hợp lệ'
        : null;
    result.add(
      CloudCsvRow(
        line: i + 1,
        point: point,
        error: error,
        details: {
          'recipient_name': name,
          'recipient_phone': phone,
          'dropoff_address': address,
          'package_description': goods,
          'weight_kg': ?weight,
          'cod_amount': ?cod,
          'service_type': service ?? serviceRaw,
        },
      ),
    );
  }
  return result;
}
