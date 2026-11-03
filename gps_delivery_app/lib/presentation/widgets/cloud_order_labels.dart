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
  'collect_cash': 'Xác nhận thu tiền mặt',
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
  'morning': 'Ca sáng · 09:00 - 11:00',
  'afternoon': 'Ca chiều · 14:00 - 16:00',
  'evening': 'Ca tối · 18:00 - 20:00',
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

int cloudOrderPayableFee(Map order) =>
    ((order['payable_fee'] ?? order['shipping_fee']) as num? ?? 0).toInt();

int cloudOrderPendingCashFee(Map order) {
  if (order['fulfillment_provider'] != null) return 0;
  if ((order['payment_status'] ?? 'UNPAID') != 'UNPAID') return 0;
  if ((order['cash_collected_fee'] as num? ?? 0) > 0) return 0;
  final payable = cloudOrderPayableFee(order);
  if (payable <= 0) return 0;
  final method =
      '${(order['details'] as Map?)?['payment_method'] ?? 'sender_cash'}';
  final status = '${order['status'] ?? ''}';
  if (method == 'sender_cash' &&
      const ['arrivingPickup', 'inTransit', 'delivered'].contains(status)) {
    return payable;
  }
  if (method == 'recipient_cash' &&
      const ['inTransit', 'delivered'].contains(status)) {
    return payable;
  }
  return 0;
}

int cloudOrderPendingCashCod(Map order) {
  if (order['fulfillment_provider'] != null) return 0;
  if (order['payment_status'] == 'REVIEW') return 0;
  final cod = (order['cod_amount'] as num? ?? 0).toInt();
  final collected = (order['cash_collected_cod'] as num? ?? 0).toInt();
  if (cod <= collected) return 0;
  final status = '${order['status'] ?? ''}';
  if (const ['inTransit', 'delivered'].contains(status)) {
    return cod - collected;
  }
  return 0;
}

bool cloudOrderCanCollectCash(Map order) =>
    order['fulfillment_provider'] == null &&
    order['payment_status'] != 'REVIEW' &&
    (cloudOrderPendingCashFee(order) > 0 ||
        cloudOrderPendingCashCod(order) > 0);

String cloudOrderPaymentLabel(Map order, {bool detailedReview = false}) =>
    switch (order['payment_status']) {
      'PAID' =>
        (order['cash_collected_fee'] as num? ?? 0) > 0
            ? 'Đã thu tiền mặt cước'
            : 'Đã thanh toán cước',
      'REVIEW' => detailedReview ? 'Cần đối soát cước' : 'Cần đối soát',
      _ => 'Chưa ghi nhận thanh toán cước',
    };
