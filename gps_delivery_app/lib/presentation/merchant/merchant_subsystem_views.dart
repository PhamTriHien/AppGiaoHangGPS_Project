import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/gps/smart_dispatch_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/geo_math.dart';
import '../../core/utils/security_and_barcode_utils.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import '../../domain/entities/pricing_estimate.dart';
import '../../domain/enums/order_status.dart';
import '../../domain/enums/service_type.dart';
import '../screens/public_order_tracking_screen.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/bank_directory_field.dart';
import '../widgets/photon_address_lookup.dart';
import '../widgets/shipping_label_scanner.dart';
import '../widgets/live_order_connection.dart';
import '../widgets/system_state_screens.dart';

part 'merchant_store_and_order_views.dart';
part 'merchant_tracking_and_finance_views.dart';

/// Phân hệ Cửa hàng / Đối tác B2B (Merchant Web Portal) - 11 màn hình
/// Giao diện phân hệ nghiệp vụ.
class MerchantSubsystemEntry extends StatefulWidget {
  final int? forcedScreenIndex;
  final VoidCallback? onLogout;

  const MerchantSubsystemEntry({
    super.key,
    this.forcedScreenIndex,
    this.onLogout,
  });

  @override
  State<MerchantSubsystemEntry> createState() => _MerchantSubsystemEntryState();
}

class _MerchantSubsystemEntryState extends State<MerchantSubsystemEntry> {
  final AppStateStore _store = AppStateStore.instance;
  int _selectedScreenIndex = 2; // Mặc định: Tạo đơn gửi hàng (UC32)

  // Thông tin cửa hàng
  late final TextEditingController _storeNameCtrl;
  late final TextEditingController _taxCodeCtrl;
  late final TextEditingController _bankAccountCtrl;
  final TextEditingController _repNameCtrl = TextEditingController();
  final TextEditingController _shopPhoneCtrl = TextEditingController();
  final TextEditingController _shopEmailCtrl = TextEditingController();
  final TextEditingController _shopAddressCtrl = TextEditingController();
  String _businessCategory = '';
  String _selectedBankName = '';

  // Tạo đơn gửi hàng lẻ & Cấu hình Kho
  final TextEditingController _warehouseNameCtrl = TextEditingController();
  final TextEditingController _warehouseContactCtrl = TextEditingController();
  final TextEditingController _warehousePhoneCtrl = TextEditingController();
  final TextEditingController _warehouseOpenHoursCtrl = TextEditingController(
    text: '08:00 - 21:00',
  );
  final TextEditingController _webhookUrlCtrl = TextEditingController();
  bool _warehouseIsPrimary = true;
  bool _isTestingWebhook = false;
  GeoPoint? _pinnedWarehouseLocation;
  bool _isReverseGeocodingWarehouse = false;
  final TextEditingController _singleNameCtrl = TextEditingController();
  final TextEditingController _singlePhoneCtrl = TextEditingController();
  final TextEditingController _singleAddrCtrl = TextEditingController();
  GeoPoint? _pinnedSingleDropoffLocation;
  bool _isReverseGeocodingSingleDropoff = false;
  List<GeoPoint>? _singleLiveOsrmPolyline;
  final Map<String, List<GeoPoint>> _merchantSyncedPolylines =
      <String, List<GeoPoint>>{};
  String _singlePkgCategory = 'Quần áo, Điện tử';
  final TextEditingController _singleWeightCtrl = TextEditingController(
    text: '1.0',
  );
  final TextEditingController _singleDimCtrl = TextEditingController(
    text: '30 x 20 x 10 cm',
  );
  final TextEditingController _singleCodCtrl = TextEditingController(text: '0');
  final TextEditingController _singleDeclaredValueCtrl = TextEditingController(
    text: '0',
  );
  final TextEditingController _singleNoteCtrl = TextEditingController();
  String _feePayer = 'Người gửi trả phí';
  String _batchFeePayer = 'Người gửi trả phí';
  DeliveryServiceType _merchantServiceType = DeliveryServiceType.express30m;
  bool _isFragile = false;
  bool _isKeepCold = false;
  bool _merchantPreferEcoEv = false;
  bool _merchantIsRoundTrip = false;
  int _selectedWaybillOrderIndex = 0;
  int _selectedWarehouseIndex = 0;

  // Sửa thông tin đơn hàng tách biệt khỏi form Tạo đơn
  final TextEditingController _editOrderNameCtrl = TextEditingController();
  final TextEditingController _editOrderPhoneCtrl = TextEditingController();
  final TextEditingController _editOrderAddrCtrl = TextEditingController();
  final TextEditingController _editOrderCodCtrl = TextEditingController();
  String? _lastSyncedEditOrderCode;
  String? _lastSyncedMerchantProfileKey;

  // Batch CSV/Excel Parser
  final TextEditingController _csvInputCtrl = TextEditingController();
  List<CsvBatchRowResult> _parsedRows = [];

  // Rút tiền COD
  final TextEditingController _codWithdrawCtrl = TextEditingController();

  // Trạng thái bộ lọc Theo dõi đơn Shop & Khiếu nại Shop
  String _shopOrderStatusTab = 'Tất cả';
  String _shopComplaintType = 'Hàng hư hỏng / Mất hàng';
  final TextEditingController _shopComplaintOrderCtrl = TextEditingController();
  final TextEditingController _shopComplaintDescCtrl = TextEditingController();
  String _shopCancelReason = 'Khách hàng báo hủy đơn';
  final Set<String> _attachedMerchantDocs = <String>{};
  final List<String> _attachedShopEvidenceFiles = <String>[];

  // Thực đơn Ăn uống Đối tác B2B (GrabFood) - Screen 11
  final TextEditingController _menuDishNameCtrl = TextEditingController();
  final TextEditingController _menuDishPriceCtrl = TextEditingController(
    text: '49000',
  );
  final TextEditingController _menuDishDescCtrl = TextEditingController();
  final TextEditingController _menuDishPrepCtrl = TextEditingController(
    text: '12',
  );
  String _menuDishCategory = 'Cơm • Bún • Phở';
  final Set<String> _menuDishMealSlots = <String>{
    'breakfast',
    'lunch',
    'afternoonTea',
    'dinner',
  };
  bool _menuDishEco = true;
  bool _menuDishCold = false;
  bool _menuDishPromo = false;
  String? _editingMenuItemId;

  // UC36: Đặt lịch gọi xe thu gom số lượng lớn
  String _pickupVehicleType = 'Xe tải van 500kg';
  String _pickupTimeSlot = '14:00 - 16:00 (Ca chiều)';
  final TextEditingController _pickupQtyCtrl = TextEditingController();
  final TextEditingController _pickupWeightCtrl = TextEditingController();
  final TextEditingController _pickupNoteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.forcedScreenIndex != null) {
      _selectedScreenIndex = widget.forcedScreenIndex!.clamp(0, 11);
    }
    final mer = _store.activeMerchantRecord;
    _storeNameCtrl = TextEditingController(text: mer?.storeName ?? '');
    _taxCodeCtrl = TextEditingController(text: mer?.taxCode ?? '');
    _bankAccountCtrl = TextEditingController(text: mer?.bankAccount ?? '');
    _syncMerchantControllersFromDb();
    _parseCsvBatch();
    _store.addListener(_onStoreChanged);
  }

  void _syncMerchantControllersFromDb() {
    final mer = _store.activeMerchantRecord;
    final authUser = _store.activeAuthenticatedUser;
    final storeName = mer?.storeName ?? '';
    final taxCode = mer?.taxCode ?? '';
    final bankAcc = mer?.bankAccount ?? '';
    final bankName = mer?.bankName ?? '';
    final bizType = mer?.businessType ?? '';
    final repName = mer?.representativeName ?? (authUser?.fullName ?? '');
    final ownerPhone = mer?.ownerPhone.isNotEmpty == true
        ? mer!.ownerPhone
        : (authUser?.phone ?? '');
    final userEmail = authUser?.email ?? '';
    final webhookUrl = mer?.webhookUrl ?? '';
    final personalWhs = _store.merchantPersonalWarehouses;
    final safeWhIdx = personalWhs.isNotEmpty
        ? _selectedWarehouseIndex.clamp(0, personalWhs.length - 1)
        : 0;
    final whKey = personalWhs.isNotEmpty
        ? '${personalWhs[safeWhIdx].id}|${personalWhs[safeWhIdx].name}|${personalWhs[safeWhIdx].address}|${personalWhs[safeWhIdx].isPrimary}|${personalWhs[safeWhIdx].contactPhone}|${personalWhs[safeWhIdx].openHours}'
        : '';
    final docsKey = mer?.attachedKycDocs.join(',') ?? '';
    final profileKey =
        '${mer?.id ?? "NEW"}|$storeName|$taxCode|$bankName|$bankAcc|$bizType|$repName|$ownerPhone|$userEmail|$webhookUrl|$whKey|$docsKey';
    if (_lastSyncedMerchantProfileKey != profileKey) {
      _lastSyncedMerchantProfileKey = profileKey;
      _storeNameCtrl.text = storeName;
      _taxCodeCtrl.text = taxCode;
      _bankAccountCtrl.text = bankAcc;
      _repNameCtrl.text = repName;
      _businessCategory = bizType.trim();
      _selectedBankName = bankName.trim();
      _shopPhoneCtrl.text = ownerPhone;
      _shopEmailCtrl.text = userEmail;
      _webhookUrlCtrl.text = webhookUrl;
      if (mer != null) {
        _attachedMerchantDocs
          ..clear()
          ..addAll(mer.attachedKycDocs);
      } else {
        _attachedMerchantDocs.clear();
      }
      if (personalWhs.isNotEmpty) {
        final wh = personalWhs[safeWhIdx];
        _warehouseNameCtrl.text = wh.name;
        _warehouseContactCtrl.text = wh.contactName.isNotEmpty
            ? wh.contactName
            : repName;
        _warehouseIsPrimary = wh.isPrimary;
        _warehousePhoneCtrl.text = wh.contactPhone.isNotEmpty
            ? wh.contactPhone
            : ownerPhone;
        _warehouseOpenHoursCtrl.text = wh.openHours.isNotEmpty
            ? wh.openHours
            : '08:00 - 21:00';
        _shopAddressCtrl.text = wh.address;
        _pinnedWarehouseLocation = null;
      } else {
        _warehouseNameCtrl.clear();
        _warehouseContactCtrl.text = repName;
        _warehousePhoneCtrl.text = ownerPhone;
        _shopAddressCtrl.clear();
        _pinnedWarehouseLocation = null;
      }
    }
    final shopOrds = _store.merchantPersonalOrders;
    final firstOrd = shopOrds.firstOrNull;
    if (firstOrd != null &&
        (_shopComplaintOrderCtrl.text.isEmpty ||
            !shopOrds.any(
              (o) => o.trackingCode == _shopComplaintOrderCtrl.text.trim(),
            ))) {
      _shopComplaintOrderCtrl.text = firstOrd.trackingCode;
    }
  }

  @override
  void didUpdateWidget(covariant MerchantSubsystemEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forcedScreenIndex != null &&
        widget.forcedScreenIndex != oldWidget.forcedScreenIndex) {
      _selectedScreenIndex = widget.forcedScreenIndex!.clamp(0, 11);
    }
  }

  void _onStoreChanged() {
    if (!mounted) return;
    _syncMerchantControllersFromDb();
    setState(() {});
  }

  String? get _batchPickupAddress {
    final warehouses = _store.merchantPersonalWarehouses;
    if (warehouses.isEmpty) return null;
    return warehouses[_selectedWarehouseIndex.clamp(0, warehouses.length - 1)]
        .address;
  }

  void _parseCsvBatch() {
    _parsedRows = _store
        .parseAndCreateBulkOrdersFromCsv(
          _csvInputCtrl.text,
          customPickupAddress: _batchPickupAddress,
          feePayerMethod: _batchFeePayer,
        )
        .rows;
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _storeNameCtrl.dispose();
    _taxCodeCtrl.dispose();
    _bankAccountCtrl.dispose();
    _repNameCtrl.dispose();
    _shopPhoneCtrl.dispose();
    _shopEmailCtrl.dispose();
    _shopAddressCtrl.dispose();
    _warehouseNameCtrl.dispose();
    _warehouseContactCtrl.dispose();
    _warehousePhoneCtrl.dispose();
    _warehouseOpenHoursCtrl.dispose();
    _webhookUrlCtrl.dispose();
    _singleNameCtrl.dispose();
    _singlePhoneCtrl.dispose();
    _singleAddrCtrl.dispose();
    _singleWeightCtrl.dispose();
    _singleDimCtrl.dispose();
    _singleCodCtrl.dispose();
    _singleDeclaredValueCtrl.dispose();
    _singleNoteCtrl.dispose();
    _editOrderNameCtrl.dispose();
    _editOrderPhoneCtrl.dispose();
    _editOrderAddrCtrl.dispose();
    _editOrderCodCtrl.dispose();
    _csvInputCtrl.dispose();
    _codWithdrawCtrl.dispose();
    _shopComplaintOrderCtrl.dispose();
    _shopComplaintDescCtrl.dispose();
    _menuDishNameCtrl.dispose();
    _menuDishPriceCtrl.dispose();
    _menuDishDescCtrl.dispose();
    _menuDishPrepCtrl.dispose();
    _pickupQtyCtrl.dispose();
    _pickupWeightCtrl.dispose();
    _pickupNoteCtrl.dispose();
    super.dispose();
  }

  Icon3dStyle _merchantScreen3dStyle(int index) {
    switch (index) {
      case 2:
      case 6:
        return Icon3dStyle.scooterExpress;
      case 5:
        return Icon3dStyle.gpsPinRadar;
      case 7:
      case 8:
        return Icon3dStyle.walletVault;
      default:
        return Icon3dStyle.parcelBox;
    }
  }

  int _merchantPillarForScreen(int screenIdx) {
    if (screenIdx == 5 || screenIdx == 4 || screenIdx == 6) return 0;
    if (screenIdx == 2 || screenIdx == 3) return 1;
    if (screenIdx == 11) return 2;
    if (screenIdx == 7 || screenIdx == 8) return 3;
    if (screenIdx == 9 || screenIdx == 10) return 4;
    return 5; // 0, 1
  }

  void _onMerchantPillarSelected(int pillarIdx) {
    setState(() {
      switch (pillarIdx) {
        case 0:
          _selectedScreenIndex = 5;
          break;
        case 1:
          _selectedScreenIndex = 2;
          break;
        case 2:
          _selectedScreenIndex = 11;
          break;
        case 3:
          _selectedScreenIndex = 7;
          break;
        case 4:
          _selectedScreenIndex = 9;
          break;
        case 5:
          _selectedScreenIndex = 1;
          break;
      }
    });
  }

  List<(IconData, String, int)> _subTabsForActivePillar() {
    switch (_merchantPillarForScreen(_selectedScreenIndex)) {
      case 0:
        return const [
          (Icons.location_searching_outlined, 'Theo dõi đơn hàng Shop', 5),
          (Icons.print_outlined, 'Tra cứu & In vận đơn A6', 4),
        ];
      case 1:
        return const [
          (Icons.add_box_outlined, 'Tạo đơn gửi hàng lẻ', 2),
          (Icons.upload_file_outlined, 'Nhập lô Excel / CSV', 3),
        ];
      case 2:
        return const [
          (Icons.restaurant_menu_rounded, 'Thực đơn Ăn uống (GrabFood)', 11),
          (Icons.warehouse_outlined, 'Cấu hình Kho & Điểm lấy bếp', 1),
        ];
      case 3:
        return const [
          (Icons.fact_check_outlined, 'Đối soát công nợ COD', 7),
          (
            Icons.account_balance_wallet_outlined,
            'Rút tiền COD về Ngân hàng',
            8,
          ),
        ];
      case 4:
        return const [
          (Icons.bar_chart_outlined, 'Báo cáo & Thống kê Shop', 9),
          (Icons.support_agent_outlined, 'Gửi khiếu nại & Hỗ trợ', 10),
        ];
      default:
        return const [
          (Icons.warehouse_outlined, 'Điểm lấy hàng & Cấu hình Kho', 1),
          (Icons.storefront_outlined, 'Hồ sơ & Xác thực pháp lý', 0),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        if (isWide) {
          final sidebarWidth = (constraints.maxWidth * 0.185).clamp(
            210.0,
            290.0,
          );
          final contentPadding = (constraints.maxWidth * 0.02).clamp(
            16.0,
            32.0,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMerchantDarkSidebar(sidebarWidth),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMerchantOrangeTopHeader(showLogout: false),
                    _buildMerchantContextualSubTabBar(contentPadding),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(contentPadding),
                        child: _buildActiveMerchantScreen(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        final mobilePadding = (constraints.maxWidth * 0.035).clamp(10.0, 18.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMerchantOrangeTopHeader(),
            if (_subTabsForActivePillar().length >= 2)
              _buildMerchantContextualSubTabBar(mobilePadding),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(mobilePadding),
                child: _buildActiveMerchantScreen(context),
              ),
            ),
            _buildMerchantBottomNavBar(),
          ],
        );
      },
    );
  }

  Widget _buildMerchantDarkSidebar(double sidebarWidth) {
    const pillarGroups =
        <(String, List<(IconData, String, String, int)>)>[
          (
            'VẬN HÀNH ĐƠN HÀNG',
            [
              (
                Icons.inventory_2_outlined,
                'Quản lý Vận đơn',
                'Theo dõi • In A6 • Xử lý đơn',
                0,
              ),
              (
                Icons.add_box_outlined,
                'Tạo đơn gửi hàng',
                'Đơn lẻ & Nhập lô CSV',
                1,
              ),
            ],
          ),
          (
            'ẨM THỰC & TÀI CHÍNH',
            [
              (
                Icons.restaurant_menu_rounded,
                'Thực đơn GrabFood',
                'Đăng món • Giá • Tồn kho B2B',
                2,
              ),
              (
                Icons.account_balance_wallet_outlined,
                'Đối soát & Ví COD',
                'Công nợ & Rút tiền ngân hàng',
                3,
              ),
            ],
          ),
          (
            'CỬA HÀNG & BÁO CÁO',
            [
              (
                Icons.insights_rounded,
                'Báo cáo & Hỗ trợ',
                'Thống kê doanh thu & Khiếu nại',
                4,
              ),
              (
                Icons.storefront_outlined,
                'Cửa hàng & Kho',
                'Kho lấy hàng & Hồ sơ pháp lý',
                5,
              ),
            ],
          ),
        ];
    final activePillar = _merchantPillarForScreen(_selectedScreenIndex);

    return Container(
      width: sidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.techBg,
        border: Border(right: BorderSide(color: AppColors.ink, width: 1.6)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.acid,
                      border: Border.all(color: AppColors.techBg),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: AppColors.techBg,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'GHST MERCHANT • B2B',
                          style: TextStyle(
                            color: AppColors.acid,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Consolas',
                            letterSpacing: 0.9,
                          ),
                        ),
                        const Text(
                          'Shop của tôi',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          _store.activeMerchantRecord?.storeName ??
                              'Chưa đăng ký Cửa hàng',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.techMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.techLine, height: 1),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final group in pillarGroups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 12, 3),
                        child: Text(
                          group.$1,
                          style: const TextStyle(
                            color: AppColors.techMuted,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Consolas',
                            letterSpacing: 0.9,
                          ),
                        ),
                      ),
                      ...group.$2.map((p) {
                        final selected = activePillar == p.$4;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          child: InkWell(
                            onTap: () => _onMerchantPillarSelected(p.$4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.violet.withValues(alpha: 0.26)
                                    : Colors.transparent,
                                border: selected
                                    ? const Border(
                                        left: BorderSide(
                                          color: AppColors.acid,
                                          width: 4,
                                        ),
                                      )
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    p.$1,
                                    color: selected
                                        ? AppColors.acid
                                        : AppColors.techMuted,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.$2,
                                          style: TextStyle(
                                            color: selected
                                                ? Colors.white
                                                : Colors.white70,
                                            fontSize: 12.5,
                                            fontWeight: selected
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          p.$3,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.techMuted,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Divider(color: AppColors.techLine, height: 1),
            ),
            if (widget.onLogout != null)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: const Icon(
                  Icons.logout_rounded,
                  color: AppColors.pink,
                  size: 19,
                ),
                title: const Text(
                  'Đăng xuất',
                  style: TextStyle(
                    color: AppColors.pink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onTap: widget.onLogout,
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildMerchantOrangeTopHeader({bool showLogout = true}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 560;
        final showMenuQuickBtn = constraints.maxWidth >= 720;
        return Container(
          height: 58,
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 24),
          decoration: const BoxDecoration(
            color: AppColors.violet,
            border: Border(
              bottom: BorderSide(color: AppColors.ink, width: 1.6),
            ),
          ),
          child: Row(
            children: [
              Animated3dIconBadge(
                style: _merchantScreen3dStyle(_selectedScreenIndex),
                size: 38,
                showRadarPulse: false,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_store.activeMerchantRecord?.storeName ?? "Đối tác B2B"} • Số dư COD: ${CurrencyFormatter.formatVnd(_store.activeMerchantRecord?.codBalance ?? 0.0)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              if (showMenuQuickBtn) ...[
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: _selectedScreenIndex == 11
                        ? AppColors.techBg
                        : Colors.white,
                    backgroundColor: _selectedScreenIndex == 11
                        ? AppColors.acid
                        : Colors.white.withValues(alpha: 0.16),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                  ),
                  onPressed: () => setState(() => _selectedScreenIndex = 11),
                  icon: const Icon(Icons.restaurant_menu_rounded, size: 15),
                  label: const Text(
                    'Thực đơn B2B',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (!isCompact) ...[
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      tooltip: 'Khiếu nại & Hỗ trợ Shop',
                      onPressed: () =>
                          setState(() => _selectedScreenIndex = 10),
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        color: AppColors.acid,
                        child: Text(
                          '${_store.merchantPersonalComplaints.where((c) => c.status != "Đã giải quyết").length}',
                          style: const TextStyle(
                            color: AppColors.techBg,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    visualDensity: isCompact
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    tooltip: 'Thông báo Cửa hàng B2B',
                    onPressed: () => _showMerchantNotificationsDialog(context),
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  if (_store.merchantNotifications.any((n) => !n.isRead))
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        color: AppColors.pink,
                        child: Text(
                          '${_store.merchantNotifications.where((n) => !n.isRead).length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (!isCompact)
                IconButton(
                  tooltip: 'Tra cứu & In vận đơn A6',
                  onPressed: () => setState(() => _selectedScreenIndex = 4),
                  icon: const Icon(
                    Icons.search_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              if (showLogout && widget.onLogout != null) ...[
                const SizedBox(width: 6),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.techBg,
                    backgroundColor: AppColors.acid,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 8 : 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                  ),
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded, size: 15),
                  label: Text(
                    isCompact ? 'Thoát' : 'Đăng xuất',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMerchantContextualSubTabBar(double hPad) {
    final subTabs = _subTabsForActivePillar();
    if (subTabs.length < 2) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.ink, width: 1.2)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: subTabs.map((tab) {
            final selected =
                _selectedScreenIndex == tab.$3 ||
                (tab.$3 == 5 && _selectedScreenIndex == 6);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => setState(() => _selectedScreenIndex = tab.$3),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.ink : AppColors.paper,
                    border: Border.all(color: AppColors.ink, width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tab.$1,
                        size: 15,
                        color: selected ? AppColors.acid : AppColors.ink,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tab.$2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w900
                              : FontWeight.w600,
                          color: selected ? AppColors.acid : AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMerchantBottomNavBar() {
    final activePillar = _merchantPillarForScreen(_selectedScreenIndex);
    const items = [
      (Icons.inventory_2_outlined, 'Đơn hàng'),
      (Icons.add_box_outlined, 'Tạo đơn'),
      (Icons.restaurant_menu_rounded, 'Thực đơn'),
      (Icons.account_balance_wallet_outlined, 'Ví COD'),
      (Icons.insights_rounded, 'Báo cáo'),
      (Icons.storefront_outlined, 'Cửa hàng'),
    ];
    return Container(
      height: 62,
      decoration: const BoxDecoration(
        color: AppColors.techBg,
        border: Border(top: BorderSide(color: AppColors.ink, width: 1.5)),
      ),
      child: Row(
        children: List.generate(items.length, (idx) {
          final selected = activePillar == idx;
          final color = selected ? AppColors.acid : AppColors.techMuted;
          return Expanded(
            child: InkWell(
              onTap: () => _onMerchantPillarSelected(idx),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  border: selected
                      ? const Border(
                          top: BorderSide(color: AppColors.acid, width: 3),
                        )
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(items[idx].$1, color: color, size: 19),
                    const SizedBox(height: 2),
                    Text(
                      items[idx].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildActiveMerchantScreen(BuildContext context) {
    switch (_selectedScreenIndex) {
      case 0:
        return _buildMerchantRegistrationView();
      case 1:
        return _buildStoreConfigAndWarehousesView();
      case 2:
        return _buildSingleOrderCreateView();
      case 3:
        return _buildBatchCsvUploadAndValidationView();
      case 4:
        return _buildWaybillA6PrintView();
      case 5:
        return _buildMultiOrderTrackingView();
      case 6:
        return _buildScheduledPickupRequestView();
      case 7:
        return _buildCodReconciliationView();
      case 8:
        return _buildCodWithdrawalView();
      case 9:
        return _buildReturnAndMonthlyAnalyticsView();
      case 10:
        return _buildMerchantComplaintSupportUc40View();
      case 11:
        return _buildMerchantGrabFoodMenuManagerView(context);
      default:
        return _buildSingleOrderCreateView();
    }
  }

  void _showMerchantNotificationsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final items = _store.merchantNotifications;
            return AlertDialog(
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
                side: BorderSide(color: AppColors.ink, width: 1.8),
              ),
              titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              title: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Text(
                    'Thông báo Cửa hàng B2B (${items.where((n) => !n.isRead).length} chưa đọc)',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _store.markAllNotificationsAsRead(
                        targetGroupScope: 'Cửa hàng B2B',
                      );
                      setDialogState(() {});
                    },
                    child: const Text(
                      'Đánh dấu đã đọc',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                height: 360,
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          'Chưa có thông báo nào dành cho Cửa hàng.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, idx) {
                          final n = items[idx];
                          final orderMatch = RegExp(r'#DH[0-9A-Za-z-]+')
                              .firstMatch(n.title);
                          final orderCode = orderMatch?.group(0);
                          return InkWell(
                            onTap: () {
                              _store.markNotificationAsRead(n.id);
                              setDialogState(() {});
                              if (orderCode != null) {
                                final mIdx = _store.merchantPersonalOrders
                                    .indexWhere(
                                      (o) => o.trackingCode == orderCode,
                                    );
                                Navigator.of(dialogCtx).pop();
                                setState(() {
                                  if (mIdx >= 0) {
                                    _selectedWaybillOrderIndex = mIdx;
                                  }
                                  _selectedScreenIndex = 5;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: n.isRead
                                    ? Colors.white
                                    : const Color(0xFFF0FDF4),
                                border: Border.all(
                                  color: AppColors.ink,
                                  width: n.isRead ? 1.0 : 1.5,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          n.category,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                            color: AppColors.violet,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        n.timeAgo,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          color: AppColors.textSecondary,
                                          fontFamily: 'Consolas',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    n.title,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: n.isRead
                                          ? FontWeight.w600
                                          : FontWeight.w900,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  if (orderCode != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Nhấn để theo dõi đơn $orderCode trên bản đồ →',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.violet,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Đóng'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _rebuildMerchantUi(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }
}
