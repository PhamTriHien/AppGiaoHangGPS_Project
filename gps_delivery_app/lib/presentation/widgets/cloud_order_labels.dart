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
  'instruction': 'Cập nhật chỉ dẫn giao hàng',
};

const cloudPickupVehicles = {
  'tricycle_300kg': 'Xe ba gác 300kg',
  'van_500kg': 'Xe tải van 500kg',
  'box_truck_1500kg': 'Xe tải thùng kín 1.5 tấn',
};

const cloudPickupVehicleCapacityKg = {
  'tricycle_300kg': 300,
  'van_500kg': 500,
  'box_truck_1500kg': 1500,
};

const cloudPickupSlots = {
  'morning': '09:00 - 11:00 (Ca sáng)',
  'afternoon': '14:00 - 16:00 (Ca chiều)',
  'evening': '18:00 - 20:00 (Ca tối)',
};

const cloudPickupStatuses = {
  'requested': 'Chờ điều xe thu gom',
  'assigned': 'Đã điều xe',
};

const cloudQuickInstructions = [
  'Gọi trước 5 phút',
  'Gửi lễ tân tầng trệt',
  'Không bấm chuông',
];

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
