const cloudStatuses = {
  'searching': 'Chờ nhận chuyến',
  'accepted': 'Đã nhận chuyến',
  'arrivingPickup': 'Đã đến điểm lấy',
  'inTransit': 'Đang giao',
  'delivered': 'Đã giao',
  'failed': 'Giao thất bại',
  'returning': 'Đang hoàn hàng',
  'returned': 'Đã hoàn hàng',
  'cancelled': 'Đã hủy',
};

const cloudActions = {
  'create': 'Tạo đơn',
  'ready': 'Cửa hàng sẵn sàng',
  'claim': 'Nhận chuyến',
  'arrive': 'Đến điểm lấy',
  'pickup': 'Lấy hàng',
  'deliver': 'Giao thành công',
  'fail': 'Giao thất bại',
  'retry': 'Giao lại',
  'return': 'Hoàn hàng',
  'complete_return': 'Đã trả hàng cho người gửi',
  'cancel': 'Hủy đơn',
};

const cloudServiceTypes = {
  'standard': 'Tiêu chuẩn',
  'express': 'Giao nhanh',
  'saving': 'Tiết kiệm 4h',
  'same_day_2h': 'Ghép đơn 2H',
  'truck': 'Xe tải nhẹ',
};

String cloudDate(dynamic value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '';
  return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
