import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/gps/smart_dispatch_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
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
import '../widgets/delivery_weather_strip.dart';
import '../widgets/photon_address_lookup.dart';
import '../widgets/shipping_label_scanner.dart';
import '../widgets/live_order_connection.dart';
import '../widgets/system_state_screens.dart';
import '../widgets/vietqr_bank_payment_panel.dart';

part 'customer_auth_and_address_views.dart';
part 'customer_order_and_pricing_views.dart';
part 'customer_history_and_profile_views.dart';
part 'customer_grab_food_views.dart';
part 'customer_promo_events_views.dart';
part 'customer_drafts_view.dart';

/// Phân hệ Khách hàng (Customer App) - 14 màn hình chuẩn thiết kế gốc (uc02..uc12, uc41, uc42)
class CustomerSubsystemEntry extends StatefulWidget {
  final int? forcedScreenIndex;
  final int? forcedAuthTabIndex;
  final VoidCallback? onLogout;

  const CustomerSubsystemEntry({
    super.key,
    this.forcedScreenIndex,
    this.forcedAuthTabIndex,
    this.onLogout,
  });

  @override
  State<CustomerSubsystemEntry> createState() => _CustomerSubsystemEntryState();
}

class _CustomerSubsystemEntryState extends State<CustomerSubsystemEntry> {
  final AppStateStore _store = AppStateStore.instance;
  int _selectedScreenIndex = 0; // Mặc định: Trang chủ tổng quan Khách hàng

  // Trạng thái (Tạo đơn hàng, Gói dịch vụ, Thanh toán & Voucher)
  final TextEditingController _pickupCtrl = TextEditingController();
  final TextEditingController _dropoffCtrl = TextEditingController();
  final TextEditingController _recipientNameCtrl = TextEditingController();
  final TextEditingController _recipientPhoneCtrl = TextEditingController();
  final TextEditingController _extraDropoffCtrl = TextEditingController();
  final TextEditingController _extraRecipientNameCtrl = TextEditingController();
  final TextEditingController _extraRecipientPhoneCtrl =
      TextEditingController();
  final List<Map<String, dynamic>> _additionalStops = <Map<String, dynamic>>[];
  String _pkgCategory = 'Quần áo & Thời trang';
  final TextEditingController _pkgDescCtrl = TextEditingController();
  final TextEditingController _weightCtrl = TextEditingController(text: '1.0');
  final TextEditingController _dimCtrl = TextEditingController(
    text: '20 x 15 x 10 cm',
  );
  final TextEditingController _codCtrl = TextEditingController();
  final TextEditingController _declaredValueCtrl = TextEditingController();
  final TextEditingController _voucherCtrl = TextEditingController();
  DeliveryServiceType _selectedService = DeliveryServiceType.express30m;
  bool _isScheduledDelivery = false;
  String _scheduledDeliverySlot = '13:00 - 15:00';
  bool _preferEcoEv = false;
  bool _greenFundContributed = false;
  bool _isRoundTrip = false;
  int? _lastTspSavedMeters;
  String _selectedPaymentMethod = 'Tiền mặt (COD)';
  String _selectedBankBin = '970436';
  String _selectedBankShortName = 'Vietcombank';
  String _foodPaymentMethod = 'Tiền mặt khi nhận món';
  String _cashFeePayer = 'Người gửi trả phí';
  List<GeoPoint>? _osrmPreviewPoints;
  int? _osrmDistMeters;
  int? _osrmDurationSec;
  GeoPoint? _pinnedPickupLocation;
  GeoPoint? _pinnedDropoffLocation;
  bool _mapPinTargetsDropoff = true;
  bool _userEditedPickupManually = false;
  bool? _homeShowActiveOrderRouteOverride;
  String? _editingDraftId;
  bool _savingDraft = false;
  Future<List<Map<String, dynamic>>>? _draftsFuture;
  String? _formOwnerId;
  int _draftFormRevision = 0;

  // Trạng thái Sổ địa chỉ (UC02)
  String _selectedAddressTag = 'Nhà riêng';
  int _selectedSavedAddressIndex = 0;
  GeoPoint? _pinnedSavedAddressLocation;
  final TextEditingController _newAddressCtrl = TextEditingController();

  // Trạng thái Chat nội bộ (UC09)
  final TextEditingController _chatInputCtrl = TextEditingController();

  // Trạng thái Hủy đơn (UC12)
  String _selectedCancelReason = 'Thời gian chờ quá lâu';
  final TextEditingController _cancelDetailCtrl = TextEditingController();

  // Trạng thái Lịch sử đơn hàng
  String _historyFilterTab = 'Tất cả';
  final TextEditingController _historySearchCtrl = TextEditingController();
  int? _historyPeriodDays;
  bool _historyNewestFirst = true;

  // Trạng thái Đánh giá 5 sao & Tiền thưởng Tip
  int _ratingStars = 5;
  int _selectedTipVnd = 0;
  final Set<String> _selectedFeedbackChips = <String>{};
  final TextEditingController _ratingCommentCtrl = TextEditingController();

  // Trạng thái Khiếu nại / Hỗ trợ
  String _complaintType = 'Hàng hư hỏng';
  final List<String> _customerEvidenceFiles = <String>[];
  final TextEditingController _complaintDescCtrl = TextEditingController();

  // Trạng thái Hồ sơ cá nhân
  late final TextEditingController _profileNameCtrl;
  late final TextEditingController _profilePhoneCtrl;
  late final TextEditingController _profileEmailCtrl;
  late final TextEditingController _profileAddressCtrl;
  String _profileGender = 'Nam';
  String? _lastSyncedCustomerProfileKey;
  String? _lastSyncedRatingOrderCode;

  // Trạng thái Trung tâm thông báo
  String _notiFilter = 'Tất cả';

  // Trạng thái Ăn uống & Gợi ý thông minh (GrabFood)
  final TextEditingController _foodSearchCtrl = TextEditingController();
  final TextEditingController _foodKitchenNoteCtrl = TextEditingController();
  final TextEditingController _foodDropoffCtrl = TextEditingController();
  MealTimeSlot _selectedFoodMealSlot = MealTimeSlot.auto;
  GrabFoodQuickFilter _selectedFoodQuickFilter = GrabFoodQuickFilter.all;
  final List<GrabFoodCartEntry> _grabFoodCart = <GrabFoodCartEntry>[];
  DeliveryServiceType _foodDeliveryService = DeliveryServiceType.express30m;
  bool _foodPreferEcoEv = false;
  bool _foodGreenFund = false;
  String? _selectedFoodVoucherCode;

  // Trạng thái Sự kiện Khuyến mãi, Vòng Xoay & Hộp Mù (Shopee × Grab)
  int _selectedPromoHubTabIndex = 0;

  // Trạng thái thu gọn các mục nâng cao trong biểu mẫu Tạo đơn
  bool _expandMultiStopSection = false;
  bool _expandInsuranceSection = false;

  static const List<String> _screenTitles = [
    'Trang chủ',
    'Sổ địa chỉ nhận hàng',
    'Tạo đơn hàng mới',
    'Chi tiết cước phí & Ưu đãi',
    'Theo dõi hành trình GPS',
    'Trò chuyện với Tài xế',
    'Yêu cầu hủy đơn hàng',
    'Đơn hàng',
    'Đánh giá chuyến giao hàng',
    'Gửi khiếu nại & Hỗ trợ',
    'Hồ sơ cá nhân',
    'Trung tâm thông báo',
    'Ưu đãi & Săn thưởng (Shopee × Grab)',
    'Ăn uống & Gợi ý (GrabFood)',
    '??n nh?p',
  ];

  @override
  void initState() {
    super.initState();
    _formOwnerId = _store.activeAuthenticatedUser?.id;
    if (widget.forcedScreenIndex != null) {
      _selectedScreenIndex = widget.forcedScreenIndex!.clamp(
        0,
        _screenTitles.length - 1,
      );
    }
    _profileNameCtrl = TextEditingController(text: _store.customerFullName);
    _profilePhoneCtrl = TextEditingController(
      text: _store.displayCustomerPhone,
    );
    _profileEmailCtrl = TextEditingController(text: _store.customerEmail);
    _profileAddressCtrl = TextEditingController(
      text: _store.customerDefaultAddress,
    );
    _profileGender = _store.customerGender;
    _lastSyncedCustomerProfileKey =
        '${_store.customerFullName}|${_store.displayCustomerPhone}|${_store.customerEmail}|${_store.customerDefaultAddress}|${_store.customerGender}';
    _syncCustomerControllersFromDb();
    _store.addListener(_onStoreChanged);
  }

  void _syncCustomerControllersFromDb() {
    if (!_userEditedPickupManually && _store.liveDeviceLocation != null) {
      _pinnedPickupLocation = _store.liveDeviceLocation;
      if (_store.liveDeviceAddress.trim().isNotEmpty) {
        _pickupCtrl.text = _store.liveDeviceAddress.trim();
      } else if (_pickupCtrl.text.isEmpty) {
        _pickupCtrl.text =
            '(${_store.liveDeviceLocation!.latitude.toStringAsFixed(5)}, ${_store.liveDeviceLocation!.longitude.toStringAsFixed(5)})';
      }
      return;
    }
    if (_pickupCtrl.text.isEmpty && _store.customerDefaultAddress.isNotEmpty) {
      _pickupCtrl.text = _store.customerDefaultAddress;
    }
  }

  @override
  void didUpdateWidget(covariant CustomerSubsystemEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forcedScreenIndex != null &&
        widget.forcedScreenIndex != oldWidget.forcedScreenIndex) {
      _selectedScreenIndex = widget.forcedScreenIndex!.clamp(
        0,
        _screenTitles.length - 1,
      );
    }
  }

  void _onStoreChanged() {
    if (!mounted) return;
    final ownerId = _store.activeAuthenticatedUser?.id;
    if (_formOwnerId != ownerId) {
      _formOwnerId = ownerId;
      _resetCustomerOrderForm();
      _draftsFuture = null;
      _historySearchCtrl.clear();
      _historyFilterTab = 'Tất cả';
      _historyPeriodDays = null;
      _chatInputCtrl.clear();
      _customerEvidenceFiles.clear();
      _complaintDescCtrl.clear();
    }
    final profileKey =
        '${_store.customerFullName}|${_store.displayCustomerPhone}|${_store.customerEmail}|${_store.customerDefaultAddress}|${_store.customerGender}';
    if (_lastSyncedCustomerProfileKey != profileKey) {
      _lastSyncedCustomerProfileKey = profileKey;
      _profileNameCtrl.text = _store.customerFullName;
      _profilePhoneCtrl.text = _store.displayCustomerPhone;
      _profileEmailCtrl.text = _store.customerEmail;
      _profileAddressCtrl.text = _store.customerDefaultAddress;
      _profileGender = _store.customerGender;
    }
    _syncCustomerControllersFromDb();
    setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    _recipientNameCtrl.dispose();
    _recipientPhoneCtrl.dispose();
    _extraDropoffCtrl.dispose();
    _extraRecipientNameCtrl.dispose();
    _extraRecipientPhoneCtrl.dispose();
    _pkgDescCtrl.dispose();
    _weightCtrl.dispose();
    _dimCtrl.dispose();
    _codCtrl.dispose();
    _declaredValueCtrl.dispose();
    _voucherCtrl.dispose();
    _newAddressCtrl.dispose();
    _chatInputCtrl.dispose();
    _cancelDetailCtrl.dispose();
    _historySearchCtrl.dispose();
    _ratingCommentCtrl.dispose();
    _complaintDescCtrl.dispose();
    _profileNameCtrl.dispose();
    _profilePhoneCtrl.dispose();
    _profileEmailCtrl.dispose();
    _profileAddressCtrl.dispose();
    _foodSearchCtrl.dispose();
    _foodKitchenNoteCtrl.dispose();
    _foodDropoffCtrl.dispose();
    super.dispose();
  }

  // Thanh điều hướng đáy 5 tab phong cách Super-App (Grab / Be / Xanh SM):
  // 0: Trang chủ | 1: Giao hàng | 2: Ăn uống | 3: Đơn hàng | 4: Hồ sơ
  int _bottomNavIndexForScreen(int screenIdx) {
    if (screenIdx == 0) return 0;
    if (screenIdx == 2 || screenIdx == 3) return 1;
    if (screenIdx == 13) return 2;
    if (screenIdx == 4 ||
        screenIdx == 5 ||
        screenIdx == 6 ||
        screenIdx == 7 ||
        screenIdx == 8 ||
        screenIdx == 9) {
      return 3;
    }
    return 4; // Hồ sơ (10), Sổ địa chỉ (1), Thông báo (11), Ưu đãi (12)
  }

  void _onBottomNavTapped(int navIdx) {
    setState(() {
      switch (navIdx) {
        case 0:
          _selectedScreenIndex = 0; // Trang chủ Super-App
          break;
        case 1:
          _selectedScreenIndex = 2; // Đặt giao hàng
          break;
        case 2:
          _selectedScreenIndex = 13; // Ăn uống GrabFood
          break;
        case 3:
          _selectedScreenIndex = 7; // Đơn hàng của tôi
          break;
        case 4:
          _selectedScreenIndex = 10; // Hồ sơ cá nhân
          break;
      }
    });
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
              _buildCustomerStudioSidebar(sidebarWidth),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCustomerWhiteTopBar(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(contentPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OfflineQueueBanner(store: _store),
                            _buildActiveCustomerScreen(context),
                          ],
                        ),
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
            _buildCustomerTopAppBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(mobilePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OfflineQueueBanner(store: _store),
                    _buildActiveCustomerScreen(context),
                  ],
                ),
              ),
            ),
            _buildDesignCustomerBottomBar(),
          ],
        );
      },
    );
  }

  Widget _buildCustomerStudioSidebar(double sidebarWidth) {
    final unreadNotis = _store.customerNotifications
        .where((n) => !n.isRead)
        .length;
    final usableVouchers = _store.vouchers.where((v) => v.isUsable).length;
    final cartQty = _grabFoodCart.fold<int>(0, (s, e) => s + e.quantity);
    final activeOrdersCount = _store.customerOrders
        .where(
          (o) =>
              o.status != OrderStatus.delivered &&
              o.status != OrderStatus.cancelled &&
              o.paymentStatus != 'RETURNED',
        )
        .length;

    final menuGroups =
        <(String, List<(IconData, String, int, String?, Color?)>)>[
          (
            'DỊCH VỤ CHÍNH',
            [
              (Icons.home_outlined, 'Trang chủ', 0, null, null),
              (Icons.add_box_outlined, 'Tạo đơn hàng mới', 2, null, null),
              (Icons.drafts_outlined, 'Đơn nháp', 14, null, null),
              (
                Icons.restaurant_menu_rounded,
                'Ăn uống (GrabFood)',
                13,
                cartQty > 0 ? '$cartQty' : 'MỚI',
                const Color(0xFF00B14F),
              ),
            ],
          ),
          (
            'ĐƠN HÀNG & BẢN ĐỒ',
            [
              (
                Icons.receipt_long_outlined,
                'Đơn hàng',
                7,
                activeOrdersCount > 0 ? '$activeOrdersCount' : null,
                AppColors.acid,
              ),
              (
                Icons.my_location_rounded,
                'Theo dõi hành trình GPS',
                4,
                null,
                null,
              ),
              (Icons.bookmarks_outlined, 'Sổ địa chỉ nhận hàng', 1, null, null),
            ],
          ),
          (
            'ƯU ĐÃI & CÁ NHÂN',
            [
              (
                Icons.redeem_rounded,
                'Săn thưởng & Ưu đãi',
                12,
                usableVouchers > 0 ? '$usableVouchers' : 'HOT',
                const Color(0xFFEE4D2D),
              ),
              (
                Icons.notifications_none_rounded,
                'Trung tâm thông báo',
                11,
                unreadNotis > 0 ? '$unreadNotis' : null,
                AppColors.pink,
              ),
              (Icons.person_outline_rounded, 'Hồ sơ cá nhân', 10, null, null),
            ],
          ),
        ];

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
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.acid,
                      border: Border.all(color: AppColors.techBg),
                    ),
                    child: const Icon(
                      Icons.local_shipping_outlined,
                      color: AppColors.techBg,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GHST EXPRESS',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15.5,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          'SUPER-APP GIAO NHẬN & ẨM THỰC',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.acid,
                            fontSize: 9.0,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Consolas',
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.techLine, height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var gIdx = 0; gIdx < menuGroups.length; gIdx++) ...[
                      if (gIdx > 0) const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 4, 14, 4),
                        child: Text(
                          menuGroups[gIdx].$1,
                          style: const TextStyle(
                            color: AppColors.techMuted,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Consolas',
                            letterSpacing: 0.9,
                          ),
                        ),
                      ),
                      ...menuGroups[gIdx].$2.map((item) {
                        final selected =
                            _selectedScreenIndex == item.$3 ||
                            (item.$3 == 2 && _selectedScreenIndex == 3) ||
                            (item.$3 == 4 &&
                                (_selectedScreenIndex == 5 ||
                                    _selectedScreenIndex == 6 ||
                                    _selectedScreenIndex == 8 ||
                                    _selectedScreenIndex == 9));
                        final badgeText = item.$4;
                        final badgeColor = item.$5 ?? AppColors.acid;
                        final useLightBadgeText = badgeColor != AppColors.acid;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 1.5,
                          ),
                          child: InkWell(
                            onTap: () =>
                                setState(() => _selectedScreenIndex = item.$3),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9.5,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.violet.withValues(alpha: 0.25)
                                    : Colors.transparent,
                                border: selected
                                    ? const Border(
                                        left: BorderSide(
                                          color: AppColors.acid,
                                          width: 4.0,
                                        ),
                                      )
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item.$1,
                                    size: 18,
                                    color: selected
                                        ? AppColors.acid
                                        : AppColors.techMuted,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      item.$2,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : AppColors.techMuted,
                                        fontSize: 12.5,
                                        fontWeight: selected
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (badgeText != null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1.5,
                                      ),
                                      color: badgeColor,
                                      child: Text(
                                        badgeText,
                                        style: TextStyle(
                                          color: useLightBadgeText
                                              ? Colors.white
                                              : AppColors.ink,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                          fontFamily: 'Consolas',
                                        ),
                                      ),
                                    ),
                                  ],
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
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerWhiteTopBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showProfileText = constraints.maxWidth >= 920;
        final isCompactBar = constraints.maxWidth < 600;
        return Container(
          height: 64,
          padding: EdgeInsets.symmetric(horizontal: isCompactBar ? 14 : 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: AppColors.ink, width: 1.5),
            ),
          ),
          child: Row(
            children: [
              const Animated3dIconBadge(
                style: Icon3dStyle.scooterExpress,
                size: 38,
                showRadarPulse: false,
                isSelected: true,
                animateIdle: false,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _screenTitles[_selectedScreenIndex],
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              if (constraints.maxWidth >= 1100 &&
                  _selectedScreenIndex != 12) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEE4D2D),
                    side: const BorderSide(
                      color: Color(0xFFEE4D2D),
                      width: 1.3,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  onPressed: () => setState(() => _selectedScreenIndex = 12),
                  icon: const Icon(
                    Icons.casino_outlined,
                    size: 15,
                    color: Color(0xFFEE4D2D),
                  ),
                  label: const Text(
                    'Săn quà',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (constraints.maxWidth >= 680 &&
                  _selectedScreenIndex != 13) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00853B),
                    side: const BorderSide(
                      color: Color(0xFF00B14F),
                      width: 1.3,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                  ),
                  onPressed: () => setState(() => _selectedScreenIndex = 13),
                  icon: const Icon(
                    Icons.restaurant_menu_rounded,
                    size: 15,
                    color: Color(0xFF00B14F),
                  ),
                  label: Text(
                    _grabFoodCart.isEmpty
                        ? 'Ăn uống'
                        : 'Giỏ (${_grabFoodCart.fold<int>(0, (s, e) => s + e.quantity)})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (_selectedScreenIndex != 0 && _selectedScreenIndex != 2) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.violet,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  onPressed: () => setState(() => _selectedScreenIndex = 2),
                  icon: const Icon(Icons.add_box_outlined, size: 16),
                  label: const Text(
                    'Tạo đơn hàng mới',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Trung tâm thông báo',
                    onPressed: () => setState(() => _selectedScreenIndex = 11),
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      color: AppColors.ink,
                      size: 22,
                    ),
                  ),
                  if (_store.customerNotifications.any((n) => !n.isRead))
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
                          '${_store.customerNotifications.where((n) => !n.isRead).length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _selectedScreenIndex = 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.acid,
                        border: Border.all(color: AppColors.ink, width: 1.2),
                      ),
                      child: Icon(
                        const [
                          Icons.person,
                          Icons.sentiment_very_satisfied_rounded,
                          Icons.verified_user_rounded,
                          Icons.workspace_premium_rounded,
                        ][_store.customerAvatarBadgeIndex % 4],
                        color: AppColors.ink,
                        size: 19,
                      ),
                    ),
                    if (showProfileText) ...[
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _store.customerFullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                                color: AppColors.ink,
                              ),
                            ),
                            Text(
                              (_store.customerEmail.isNotEmpty &&
                                      !_store.customerEmail.endsWith(
                                        '@giaohanggps.vn',
                                      ))
                                  ? _store.customerEmail
                                  : _store.displayCustomerPhone,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontFamily: 'Consolas',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool get _isCustomerSubScreen =>
      _selectedScreenIndex != 0 &&
      _selectedScreenIndex != 2 &&
      _selectedScreenIndex != 13 &&
      _selectedScreenIndex != 7 &&
      _selectedScreenIndex != 10;

  void _navigateBackFromCustomerSubScreen() {
    setState(() {
      if (_selectedScreenIndex == 3) {
        _selectedScreenIndex = 2;
      } else if (_selectedScreenIndex == 5 ||
          _selectedScreenIndex == 6 ||
          _selectedScreenIndex == 8 ||
          _selectedScreenIndex == 9) {
        _selectedScreenIndex = 4;
      } else {
        _selectedScreenIndex = 0;
      }
    });
  }

  Widget _buildCustomerTopAppBar(BuildContext context) {
    final activeOrder = _store.activeCustomerOrderRecord;
    final unreadNotis = _store.customerNotifications
        .where((n) => !n.isRead)
        .length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.techBg,
        border: Border.all(color: AppColors.ink, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: AppColors.violet,
            offset: Offset(0, 3),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          if (_isCustomerSubScreen) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Quay lại',
              onPressed: _navigateBackFromCustomerSubScreen,
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.acid,
                size: 21,
              ),
            ),
            const SizedBox(width: 4),
          ] else ...[
            const Animated3dIconBadge(
              style: Icon3dStyle.scooterExpress,
              size: 36,
              showRadarPulse: false,
              animateIdle: false,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedScreenIndex == 0
                      ? 'VỊ TRÍ • ${_store.customerDefaultAddress.isNotEmpty ? _store.customerDefaultAddress : "Chưa chọn"}'
                      : 'GHST EXPRESS • KHÁCH HÀNG',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.acid,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Consolas',
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _screenTitles[_selectedScreenIndex],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                if (activeOrder != null && _selectedScreenIndex != 0)
                  Text(
                    'Đơn: ${activeOrder.trackingCode} (${activeOrder.status.displayName})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.techMuted,
                      fontSize: 10.0,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Consolas',
                    ),
                  ),
              ],
            ),
          ),
          InkWell(
            onTap: () => setState(() => _selectedScreenIndex = 11),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.notifications_none_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                if (unreadNotis > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      color: AppColors.pink,
                      child: Text(
                        '$unreadNotis',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.onLogout != null) ...[
            const SizedBox(width: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: AppColors.techLine),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                minimumSize: Size.zero,
              ),
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_rounded, size: 13),
              label: const Text(
                'Đăng xuất',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDesignCustomerBottomBar() {
    final activeNav = _bottomNavIndexForScreen(_selectedScreenIndex);
    final cartQty = _grabFoodCart.fold<int>(0, (s, e) => s + e.quantity);
    const items = [
      (Icons.home_rounded, 'Trang chủ'),
      (Icons.local_shipping_outlined, 'Giao hàng'),
      (Icons.restaurant_menu_rounded, 'Ăn uống'),
      (Icons.receipt_long_outlined, 'Đơn hàng'),
      (Icons.person_outline_rounded, 'Hồ sơ'),
    ];

    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: AppColors.techBg,
        border: Border.all(color: AppColors.ink, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: AppColors.violet,
            offset: Offset(0, -2),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: List.generate(items.length, (idx) {
          final selected = activeNav == idx;
          final color = selected ? AppColors.acid : AppColors.techMuted;
          return Expanded(
            child: InkWell(
              onTap: () => _onBottomNavTapped(idx),
              child: Container(
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
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(items[idx].$1, color: color, size: 20),
                        if (idx == 2 && cartQty > 0)
                          Positioned(
                            right: -8,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              color: const Color(0xFF00B14F),
                              child: Text(
                                '$cartQty',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      items[idx].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 10.5,
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

  Widget _buildActiveCustomerScreen(BuildContext context) {
    switch (_selectedScreenIndex) {
      case 0:
        return _buildCustomerHomeDashboardView();
      case 1:
        return _buildSavedAddressesView();
      case 2:
        return _buildCreateOrderView();
      case 3:
        return _buildPricingAndVoucherView();
      case 4:
        return _buildLiveGpsTrackingView();
      case 5:
        return _buildInAppChatView();
      case 6:
        return _buildCancelOrderSheetView();
      case 7:
        return _buildOrderHistoryAndPodView();
      case 8:
        return _buildRateDriverView();
      case 9:
        return _buildSubmitComplaintView();
      case 10:
        return _buildCustomerProfileView();
      case 11:
        return _buildNotificationCenterView();
      case 12:
        return _buildDedicatedVoucherUc11View();
      case 13:
        return _buildGrabFoodDiscoveryAndCartView(context);
      case 14:
        return _buildCustomerDraftsView();
      default:
        return _buildCustomerHomeDashboardView();
    }
  }

  Widget _buildCustomerHomeDashboardView() {
    final myOrders = _store.customerOrders;
    final recentOrders = myOrders.take(3).toList();
    final activeOrders = myOrders
        .where(
          (o) =>
              o.status != OrderStatus.delivered &&
              o.status != OrderStatus.cancelled &&
              o.paymentStatus != 'RETURNED',
        )
        .toList();
    final activeOrdersCount = activeOrders.length;
    final selectedActive = _store.activeCustomerOrderRecord;
    final primaryActiveOrder =
        (selectedActive != null &&
            activeOrders.any(
              (o) => o.trackingCode == selectedActive.trackingCode,
            ))
        ? selectedActive
        : (activeOrders.isNotEmpty ? activeOrders.first : null);
    final usableVoucherCount = _store.vouchers.where((v) => v.isUsable).length;
    final cartTotalItems = _grabFoodCart.fold<int>(
      0,
      (sum, e) => sum + e.quantity,
    );
    final currentPickupSummary = _store.liveDeviceAddress.trim().isNotEmpty
        ? _store.liveDeviceAddress.trim()
        : (_store.customerDefaultAddress.isNotEmpty
              ? _store.customerDefaultAddress
              : 'Chưa chọn điểm lấy hàng');

    Widget buildServiceSuperAppGrid() {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.ink, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: AppColors.ink,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.apps_rounded,
                  size: 17,
                  color: AppColors.violet,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Dịch vụ Giao nhận & Ăn uống nhanh',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                Text(
                  '6 dịch vụ trực tuyến',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'Consolas',
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, gridConstraints) {
                final columns = gridConstraints.maxWidth >= 520 ? 3 : 2;
                final spacing = 10.0;
                final cardWidth =
                    (gridConstraints.maxWidth - (spacing * (columns - 1))) /
                    columns;
                final baseScale = (_store.baseFareConfig / 25000.0).clamp(
                  0.4,
                  5.0,
                );
                double scaledBase(DeliveryServiceType s) =>
                    (s.defaultBaseFare * baseScale).roundToDouble();

                final tiles = <(String, String, IconData, Color, DeliveryServiceType?, bool)>[
                  (
                    'Giao nhanh 30p',
                    'Từ ${CurrencyFormatter.formatVnd(scaledBase(DeliveryServiceType.express30m))}',
                    Icons.bolt_rounded,
                    AppColors.pink,
                    DeliveryServiceType.express30m,
                    false,
                  ),
                  (
                    'Ghép đơn 2H',
                    'Từ ${CurrencyFormatter.formatVnd(scaledBase(DeliveryServiceType.sameDay2h))}',
                    Icons.hub_outlined,
                    const Color(0xFF0EA5E9),
                    DeliveryServiceType.sameDay2h,
                    false,
                  ),
                  (
                    'Tiêu chuẩn 2h',
                    'Từ ${CurrencyFormatter.formatVnd(scaledBase(DeliveryServiceType.standard))}',
                    Icons.inventory_2_outlined,
                    AppColors.violet,
                    DeliveryServiceType.standard,
                    false,
                  ),
                  (
                    'Tiết kiệm 4h',
                    'Từ ${CurrencyFormatter.formatVnd(scaledBase(DeliveryServiceType.saving))}',
                    Icons.savings_outlined,
                    AppColors.success,
                    DeliveryServiceType.saving,
                    false,
                  ),
                  (
                    'Xe tải nhẹ',
                    'Từ ${CurrencyFormatter.formatVnd(scaledBase(DeliveryServiceType.truck))}',
                    Icons.local_shipping_outlined,
                    AppColors.ink,
                    DeliveryServiceType.truck,
                    false,
                  ),
                  (
                    'Ăn uống GrabFood',
                    cartTotalItems > 0
                        ? 'Giỏ: $cartTotalItems món • Đặt ngay'
                        : 'Gợi ý quán ngon gần bạn',
                    Icons.restaurant_menu_rounded,
                    const Color(0xFF00B14F),
                    null,
                    true,
                  ),
                ];

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: tiles.map((item) {
                    final isFoodTile = item.$6;
                    final isCurrentService =
                        !isFoodTile &&
                        _selectedService == item.$5 &&
                        !_isScheduledDelivery;
                    return SizedBox(
                      width: cardWidth,
                      child: InkWell(
                        onTap: () => setState(() {
                          if (isFoodTile) {
                            _selectedScreenIndex = 13;
                          } else {
                            _selectedService = item.$5!;
                            _isScheduledDelivery = false;
                            _selectedScreenIndex = 2;
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isFoodTile
                                ? const Color(0xFFF0FDF4)
                                : Colors.white,
                            border: Border.all(
                              color: (isCurrentService || isFoodTile)
                                  ? item.$4
                                  : AppColors.ink,
                              width: (isCurrentService || isFoodTile)
                                  ? 1.6
                                  : 1.15,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                color: item.$4.withValues(alpha: 0.14),
                                child: Icon(item.$3, color: item.$4, size: 18),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.$1,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.0,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    Text(
                                      item.$2,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: isFoodTile
                                            ? null
                                            : 'Consolas',
                                        color: isFoodTile
                                            ? const Color(0xFF00853B)
                                            : AppColors.textSecondary,
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
                  }).toList(),
                );
              },
            ),
          ],
        ),
      );
    }

    Widget buildCompactHomeMapCard({required double mapHeight}) {
      final realGpsLoc = _store.liveDeviceLocation;
      final homeDefaultLoc =
          realGpsLoc ??
          _store.customerSavedAddresses
              .where(
                (address) =>
                    address.fullAddress == _store.customerDefaultAddress,
              )
              .firstOrNull
              ?.location;
      final hasLiveOrd = primaryActiveOrder != null;
      final autoPreferRealGps =
          realGpsLoc != null &&
          hasLiveOrd &&
          GeoMath.distanceMeters(
                realGpsLoc,
                primaryActiveOrder.pickupLocation,
              ) >
              5000.0;
      final showOrderRouteOnHome =
          hasLiveOrd &&
          (_homeShowActiveOrderRouteOverride ?? !autoPreferRealGps);
      final liveRemMeters = showOrderRouteOnHome
          ? _store.distanceFromDriverToOrderDropoffMeters(primaryActiveOrder)
          : 0.0;
      final liveProgress =
          showOrderRouteOnHome &&
              primaryActiveOrder.distanceMeters > 0 &&
              primaryActiveOrder.status != OrderStatus.searching
          ? (1.0 -
                    (liveRemMeters / primaryActiveOrder.distanceMeters).clamp(
                      0.0,
                      1.0,
                    ))
                .clamp(0.05, 0.98)
          : 0.0;
      final homeAddressSubtitle = realGpsLoc != null
          ? (_store.liveDeviceAddress.trim().isNotEmpty
                ? '${_store.liveDeviceAddress.trim()} • Chạm bản đồ để chọn điểm giao'
                : 'Chạm vào điểm bất kỳ trên bản đồ để chọn nơi giao hàng')
          : 'Chạm vào điểm bất kỳ trên bản đồ để chọn nơi giao hàng';

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.ink, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: AppColors.ink,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        showOrderRouteOnHome
                            ? 'Hành trình trực tiếp • ${primaryActiveOrder.trackingCode}'
                            : 'Bản đồ định vị trực tiếp',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        showOrderRouteOnHome
                            ? '${primaryActiveOrder.pickupAddress} → ${primaryActiveOrder.dropoffAddress}'
                            : homeAddressSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (hasLiveOrd)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                        onPressed: () async {
                          if (showOrderRouteOnHome) {
                            if (_store.liveDeviceLocation == null) {
                              await _store.acquireCustomerDeviceGps();
                            }
                            if (!mounted) return;
                            setState(
                              () => _homeShowActiveOrderRouteOverride = false,
                            );
                          } else {
                            setState(
                              () => _homeShowActiveOrderRouteOverride = true,
                            );
                          }
                        },
                        icon: Icon(
                          showOrderRouteOnHome
                              ? Icons.my_location_rounded
                              : Icons.route_rounded,
                          size: 14,
                        ),
                        label: Text(
                          showOrderRouteOnHome
                              ? 'Vị trí của tôi'
                              : 'Xem đơn ${primaryActiveOrder.trackingCode}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => setState(
                        () =>
                            _selectedScreenIndex = showOrderRouteOnHome ? 4 : 2,
                      ),
                      icon: Icon(
                        showOrderRouteOnHome
                            ? Icons.open_in_full_rounded
                            : Icons.edit_location_alt_outlined,
                        size: 15,
                      ),
                      label: Text(
                        showOrderRouteOnHome ? 'Chi tiết' : 'Mở đặt đơn',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Map3dPerspectiveWidget(
              height: mapHeight,
              showTopBanner: showOrderRouteOnHome,
              mode: showOrderRouteOnHome
                  ? MapViewMode.customerLiveTracking
                  : MapViewMode.customerPreview,
              is3dMode: _store.isMap3dEnabled,
              speedKmh:
                  showOrderRouteOnHome &&
                      primaryActiveOrder.status == OrderStatus.inTransit
                  ? _store.currentSpeedKmh
                  : 0.0,
              onToggle3d: _store.toggleMap3d,
              driverLocation: _store.verifiedLocationForOrder(
                primaryActiveOrder,
              ),
              progressFraction: liveProgress,
              singlePinPoint: showOrderRouteOnHome ? null : homeDefaultLoc,
              singlePinLabel: realGpsLoc != null
                  ? 'Vị trí của bạn'
                  : 'Điểm lấy hàng',
              routePoints: showOrderRouteOnHome
                  ? (_store.activeRoutePolyline.length >= 2 &&
                            (_store.selectedDriverOrderCode ==
                                    primaryActiveOrder.trackingCode ||
                                _store.orders.firstOrNull?.trackingCode ==
                                    primaryActiveOrder.trackingCode)
                        ? _store.activeRoutePolyline
                        : SmartDispatchEngine.generateRoutePolyline(
                            primaryActiveOrder.pickupLocation,
                            primaryActiveOrder.dropoffLocation,
                            segments: 10,
                          ))
                  : const <GeoPoint>[],
              pickupLabel: '[A] Điểm lấy',
              dropoffLabel: '[B] Điểm giao',
              nextTurnInstruction: showOrderRouteOnHome
                  ? '${primaryActiveOrder.status.displayName} • Còn ${(liveRemMeters / 1000).toStringAsFixed(1)} km'
                  : '',
              roadName: showOrderRouteOnHome
                  ? '${primaryActiveOrder.pickupAddress} → ${primaryActiveOrder.dropoffAddress}'
                  : '',
              onTapGeoPoint: showOrderRouteOnHome
                  ? null
                  : (pt) async {
                      final addr =
                          await SmartDispatchEngine.reverseGeocodeCoordinate(
                            pt,
                          );
                      if (!mounted) return;
                      setState(() {
                        _pinnedDropoffLocation = pt;
                        _dropoffCtrl.text = addr;
                        _osrmPreviewPoints = null;
                        _osrmDistMeters = null;
                        _osrmDurationSec = null;
                        _selectedScreenIndex = 2;
                      });
                    },
            ),
          ],
        ),
      );
    }

    Widget? buildRecentOrdersCard() {
      if (recentOrders.isEmpty) return null;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.ink, width: 1.4),
          boxShadow: const [
            BoxShadow(
              color: AppColors.ink,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Đơn gần đây ($activeOrdersCount đang giao)',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => setState(() => _selectedScreenIndex = 7),
                  child: const Text(
                    'Xem tất cả →',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
            ...recentOrders.map((ord) {
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    border: Border.all(color: AppColors.ink, width: 1.0),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  ord.trackingCode,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    fontFamily: 'Consolas',
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  color: AppColors.acid,
                                  child: Text(
                                    ord.status.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${ord.pickupAddress} → ${ord.dropoffAddress}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                        ),
                        onPressed: () {
                          _store.selectCustomerOrder(ord.trackingCode);
                          setState(() => _selectedScreenIndex = 4);
                        },
                        child: const Text(
                          'Xem',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.ink, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: AppColors.ink,
                offset: Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              InkWell(
                onTap: () => setState(() => _selectedScreenIndex = 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      color: AppColors.pink,
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Bạn muốn giao hàng hay đặt món đến đâu?',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: AppColors.ink,
                              ),
                            ),
                            Text(
                              _dropoffCtrl.text.trim().isNotEmpty
                                  ? 'Điểm nhận: ${_dropoffCtrl.text.trim()}'
                                  : 'Vị trí hiện tại: $currentPickupSummary',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppColors.ink,
                      side: const BorderSide(color: AppColors.ink, width: 1.2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () => setState(() => _selectedScreenIndex = 1),
                    icon: const Icon(Icons.bookmarks_outlined, size: 15),
                    label: const Text(
                      'Sổ địa chỉ',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppColors.ink,
                      side: const BorderSide(color: AppColors.ink, width: 1.2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    onPressed: _openCustomerDrafts,
                    icon: const Icon(Icons.drafts_outlined, size: 15),
                    label: const Text(
                      'Đơn nháp',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppColors.ink,
                      side: const BorderSide(color: AppColors.ink, width: 1.2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () => setState(() => _selectedScreenIndex = 12),
                    icon: const Icon(
                      Icons.local_offer_outlined,
                      size: 15,
                      color: AppColors.violet,
                    ),
                    label: Text(
                      'Ưu đãi ($usableVoucherCount)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppColors.ink,
                      foregroundColor: AppColors.acid,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () => setState(() => _selectedScreenIndex = 2),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                    label: const Text(
                      'Đặt đơn',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (primaryActiveOrder != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              border: Border.all(color: AppColors.ink, width: 1.4),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_shipping_rounded,
                      color: Color(0xFF166534),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${primaryActiveOrder.trackingCode} • ${primaryActiveOrder.status.displayName} (${primaryActiveOrder.assignedDriverName ?? "Đang điều phối"})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: AppColors.ink,
                        foregroundColor: AppColors.acid,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () {
                        _store.selectCustomerOrder(
                          primaryActiveOrder.trackingCode,
                        );
                        setState(() => _selectedScreenIndex = 4);
                      },
                      icon: const Icon(Icons.my_location_rounded, size: 14),
                      label: const Text(
                        'Theo dõi',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.ink,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () {
                        _store.selectCustomerOrder(
                          primaryActiveOrder.trackingCode,
                        );
                        setState(() => _selectedScreenIndex = 5);
                      },
                      icon: const Icon(Icons.chat_bubble_outline, size: 13),
                      label: const Text(
                        'Chat',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, homeConstraints) {
            final isTwoColumn = homeConstraints.maxWidth >= 900;
            final recentCard = buildRecentOrdersCard();
            if (isTwoColumn) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        buildServiceSuperAppGrid(),
                        const SizedBox(height: 12),
                        _buildHomePromoEventsBanner(context),
                        const SizedBox(height: 12),
                        _buildHomeGrabFoodDiscoveryStrip(context),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        buildCompactHomeMapCard(mapHeight: 330),
                        if (recentCard != null) ...[
                          const SizedBox(height: 12),
                          recentCard,
                        ],
                      ],
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildServiceSuperAppGrid(),
                const SizedBox(height: 12),
                _buildHomePromoEventsBanner(context),
                const SizedBox(height: 12),
                _buildHomeGrabFoodDiscoveryStrip(context),
                const SizedBox(height: 12),
                buildCompactHomeMapCard(mapHeight: 280),
                if (recentCard != null) ...[
                  const SizedBox(height: 12),
                  recentCard,
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _showLegacyBankQrPaymentDialog(ActiveOrderRecord ord) async {
    if (!mounted) return;
    String pickedBin = _selectedBankBin;
    String pickedShortName = _selectedBankShortName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Thanh toán Ngân hàng · VietQR · ${ord.trackingCode}'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: VietQrBankPaymentPanel(
                amountVnd: ord.totalAmount,
                orderReference: ord.trackingCode,
                selectedPayerBankBin: pickedBin,
                onPayerBankChanged: (bank) {
                  setDialogState(() {
                    pickedBin = bank.bin;
                    pickedShortName = bank.shortName;
                  });
                  _rebuildCustomerUi(() {
                    _selectedBankBin = bank.bin;
                    _selectedBankShortName = bank.shortName;
                  });
                },
                reconciliationNote:
                    'Quét mã QR bằng ứng dụng ngân hàng hoặc sao chép thông tin chuyển khoản nhanh NAPAS 247.',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Thanh toán sau'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Tôi đã chuyển khoản'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      final ok = _store.confirmOrderBankQrPayment(
        trackingCode: ord.trackingCode,
        bankLabel: pickedShortName,
      );
      if (ok && mounted) {
        _rebuildCustomerUi(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã ghi nhận thanh toán đơn ${ord.trackingCode} qua $pickedShortName!',
            ),
          ),
        );
      }
    }
  }

  void _rebuildCustomerUi(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }
}
