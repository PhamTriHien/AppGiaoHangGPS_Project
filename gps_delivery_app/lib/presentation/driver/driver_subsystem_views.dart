import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/gps/smart_dispatch_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/security_and_barcode_utils.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import '../../domain/enums/order_status.dart';
import '../../domain/enums/service_type.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/bank_directory_field.dart';
import '../widgets/delivery_weather_strip.dart';
import '../widgets/live_order_connection.dart';
import '../widgets/system_state_screens.dart';
import '../widgets/ghst_button_icon.dart';

part 'driver_onboarding_and_dispatch_views.dart';
part 'driver_wallet_and_analytics_views.dart';

/// Phân hệ Tài xế (Driver App) - 9 màn hình chuẩn thiết kế gốc (uc13..uc21)
class DriverSubsystemEntry extends StatefulWidget {
  final int? forcedScreenIndex;
  final VoidCallback? onLogout;

  const DriverSubsystemEntry({
    super.key,
    this.forcedScreenIndex,
    this.onLogout,
  });

  @override
  State<DriverSubsystemEntry> createState() => _DriverSubsystemEntryState();
}

class _DriverSubsystemEntryState extends State<DriverSubsystemEntry> {
  final AppStateStore _store = AppStateStore.instance;
  int _selectedScreenIndex =
      1; // Mặc định: Trang chủ Tài xế Online/Offline (UC14)

  // Hồ sơ đăng ký tài xế (UC13)
  final TextEditingController _drvNameCtrl = TextEditingController();
  final TextEditingController _drvPhoneCtrl = TextEditingController();
  final TextEditingController _drvCitizenCtrl = TextEditingController();
  final TextEditingController _drvPlateCtrl = TextEditingController();
  final TextEditingController _drvBankNameCtrl = TextEditingController();
  final TextEditingController _drvBankAccCtrl = TextEditingController();
  String _vehicleType = 'Xe máy';

  // Countdown 28s & Smart Dispatch (UC15)
  int _countdownSeconds = 28;
  Timer? _dispatchCountdownTimer;
  final Set<String> _rejectedDriverIds = {};
  final Set<String> _rejectedOrderCodes = {};

  // POD & OTP 4 số (UC17) & Chat hai chiều với Khách (UC16)
  final TextEditingController _podOtpCtrl = TextEditingController();
  final TextEditingController _podRecipientCtrl = TextEditingController();
  final TextEditingController _podNoteCtrl = TextEditingController();
  final TextEditingController _driverChatInputCtrl = TextEditingController();
  bool _showDriverChatPanel = false;
  String? _lastSyncedDriverOrderCode;
  String? _lastSyncedDriverProfileKey;

  // Rút tiền Ví tài xế (UC18)
  final TextEditingController _withdrawAmountCtrl = TextEditingController();
  String _selectedBank = '';
  String _incomePeriod = 'Tuần';

  // Lịch sử giao hàng (UC19)
  String _driverHistoryPeriod = 'Hôm nay';

  // Báo cáo sự cố (UC20)
  String _incidentType = 'Hàng bị hỏng';
  final TextEditingController _incidentNoteCtrl = TextEditingController();
  final Set<String> _attachedKycDocs = <String>{};
  final List<String> _driverIncidentEvidenceFiles = <String>[];

  // Thống kê hiệu suất (UC21)
  String _statsPeriod = 'Tuần này';

  static const List<String> _screenTitles = [
    'Hồ sơ & hiệu suất',
    'Trang chủ Tài xế & Trạng thái Hoạt động',
    'ĐƠN HÀNG MỚI! (28s)',
    'Chuyến đang giao',
    'Cập nhật tiến độ vận đơn',
    'Xác nhận Giao hàng POD & Mã OTP',
    'Thu nhập và rút tiền',
    'Báo cáo sự cố trên đường',
    'Hồ sơ & hiệu suất',
    'Lịch sử giao hàng',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.forcedScreenIndex != null) {
      _selectedScreenIndex = widget.forcedScreenIndex!.clamp(
        0,
        _screenTitles.length - 1,
      );
    }
    _syncDriverControllersFromDb();
    _syncDispatchCountdownTimer();
    _store.addListener(_onStoreChanged);
    if (!_isAutomatedTestBinding) {
      unawaited(
        _store.startRealTimeDeviceGpsTracking(
          syncDriverLocation: true,
          forcePromptPermission: false,
        ),
      );
    }
  }

  bool get _isAutomatedTestBinding =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  bool _isSearchingOrderCompatibleWithActiveDriver(ActiveOrderRecord o) {
    if (o.status != OrderStatus.searching ||
        _rejectedOrderCodes.contains(o.trackingCode)) {
      return false;
    }
    final activeDrv = _store.activeDriverRecord;
    final vLower = (activeDrv?.vehicleType ?? _vehicleType).toLowerCase();
    final isTruck =
        vLower.contains('tải') ||
        vLower.contains('van') ||
        vLower.contains('truck');
    if (o.serviceType == DeliveryServiceType.truck && !isTruck) {
      return false;
    }
    if (o.serviceType != DeliveryServiceType.truck && isTruck) {
      return false;
    }
    if (activeDrv != null) {
      if (o.preferEcoEv && !activeDrv.isElectricVehicle) {
        return false;
      }
      final routeMeters = o.isRoundTrip
          ? (o.distanceMeters * 2)
          : o.distanceMeters;
      if (!SmartDispatchEngine.hasSufficientEvBatteryForOrder(
        driver: activeDrv,
        pickupLocation: o.pickupLocation,
        orderRouteMeters: routeMeters,
      )) {
        return false;
      }
      final isHighValue = o.declaredValueVnd >= 3000000 || o.codAmount >= 2000000;
      if (isHighValue && activeDrv.rating > 0 && activeDrv.rating < 4.5) {
        return false;
      }
    }
    return true;
  }

  void _syncDispatchCountdownTimer() {
    final activeDrv = _store.activeDriverRecord;
    final canReceiveDispatch =
        _selectedScreenIndex == 2 &&
        _store.isDriverOnline &&
        activeDrv != null &&
        activeDrv.approvalStatus == 'Đã duyệt' &&
        activeDrv.walletBalance >= 200000 &&
        _store.activeDriverInProgressOrder == null &&
        _store.orders.any(_isSearchingOrderCompatibleWithActiveDriver);
    if (!canReceiveDispatch || _isAutomatedTestBinding) {
      _dispatchCountdownTimer?.cancel();
      _dispatchCountdownTimer = null;
      return;
    }
    if (_dispatchCountdownTimer?.isActive ?? false) return;
    _dispatchCountdownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      final drv = _store.activeDriverRecord;
      if (!mounted ||
          _selectedScreenIndex != 2 ||
          !_store.isDriverOnline ||
          drv == null ||
          drv.approvalStatus != 'Đã duyệt' ||
          _store.activeDriverInProgressOrder != null) {
        timer.cancel();
        _dispatchCountdownTimer = null;
        return;
      }
      final currentSearching = _store.orders
          .where(_isSearchingOrderCompatibleWithActiveDriver)
          .firstOrNull;
      if (currentSearching == null) {
        timer.cancel();
        _dispatchCountdownTimer = null;
        return;
      }
      setState(() {
        if (_countdownSeconds > 1) {
          _countdownSeconds -= 1;
        } else {
          _countdownSeconds = 28;
          _rejectedOrderCodes.add(currentSearching.trackingCode);
          _store.recordDriverDispatchRejection(currentSearching.trackingCode);
          _reassignToNextCandidate();
        }
      });
    });
  }

  void _syncDriverControllersFromDb() {
    final d = _store.activeDriverRecord;
    final authUser = _store.activeAuthenticatedUser;
    if (d != null) {
      final docsKey = d.attachedKycDocs.join(',');
      final profileKey =
          '${d.id}|${d.fullName}|${d.phone}|${d.citizenId}|${d.licensePlate}|${d.vehicleType}|${d.bankName}|${d.bankAccount}|$docsKey';
      if (_lastSyncedDriverProfileKey != profileKey) {
        _lastSyncedDriverProfileKey = profileKey;
        _drvNameCtrl.text = d.fullName;
        _drvPhoneCtrl.text = d.phone;
        _drvCitizenCtrl.text = d.citizenId;
        _drvPlateCtrl.text = d.licensePlate;
        _drvBankNameCtrl.text = d.bankName;
        _drvBankAccCtrl.text = d.bankAccount;
        _selectedBank = '${d.bankName} - ${d.bankAccount}';
        _attachedKycDocs
          ..clear()
          ..addAll(d.attachedKycDocs);
        if (d.vehicleType.trim().isNotEmpty) {
          _vehicleType = d.vehicleType.trim();
        }
      }
    } else if (authUser != null) {
      final profileKey = 'UNREGISTERED|${authUser.id}|${authUser.phone}';
      if (_lastSyncedDriverProfileKey != profileKey) {
        _lastSyncedDriverProfileKey = profileKey;
        _drvNameCtrl.text = authUser.fullName;
        _drvPhoneCtrl.text = authUser.phone;
        _drvCitizenCtrl.clear();
        _drvPlateCtrl.clear();
        _drvBankNameCtrl.clear();
        _drvBankAccCtrl.clear();
        _selectedBank = '';
        _vehicleType = 'Xe máy';
        _attachedKycDocs.clear();
      }
    }
    final activeOrd = _store.activeDriverPersonalOrderRecord;
    if (activeOrd != null) {
      if (_lastSyncedDriverOrderCode != activeOrd.trackingCode) {
        _lastSyncedDriverOrderCode = activeOrd.trackingCode;
        _podRecipientCtrl.text = activeOrd.recipientName;
        if (activeOrd.status == OrderStatus.delivered) {
          _podOtpCtrl.text = SecurityAndBarcodeUtils.generateOrderDeliveryOtp4(
            activeOrd.trackingCode,
          );
        } else {
          _podOtpCtrl.clear();
        }
      } else if (_podRecipientCtrl.text.trim().isEmpty) {
        _podRecipientCtrl.text = activeOrd.recipientName;
      }
      if (activeOrd.podImageNote != null &&
          activeOrd.podImageNote!.isNotEmpty &&
          _podNoteCtrl.text.trim().isEmpty) {
        _podNoteCtrl.text = activeOrd.podImageNote!;
      }
    }
  }

  @override
  void didUpdateWidget(covariant DriverSubsystemEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forcedScreenIndex != null &&
        widget.forcedScreenIndex != oldWidget.forcedScreenIndex) {
      _selectedScreenIndex = widget.forcedScreenIndex!.clamp(
        0,
        _screenTitles.length - 1,
      );
      _syncDispatchCountdownTimer();
    }
  }

  void _onStoreChanged() {
    if (!mounted) return;
    _syncDriverControllersFromDb();
    _syncDispatchCountdownTimer();
    setState(() {});
  }

  void _reassignToNextCandidate() {
    final targetOrder = _store.orders
        .where(_isSearchingOrderCompatibleWithActiveDriver)
        .firstOrNull;
    if (targetOrder == null) return;
    final ranked = SmartDispatchEngine.rankDriversForPickup(
      pickupLocation: targetOrder.pickupLocation,
      drivers: _store.drivers,
      excludedDriverIds: _rejectedDriverIds,
      requireElectricVehicle: targetOrder.preferEcoEv,
      preferElectricVehicle: targetOrder.preferEcoEv,
      totalOrderRouteMeters: targetOrder.isRoundTrip
          ? (targetOrder.distanceMeters * 2)
          : targetOrder.distanceMeters,
      declaredValueVnd: targetOrder.declaredValueVnd,
      codAmount: targetOrder.codAmount,
      serviceType: targetOrder.serviceType,
    );
    if (ranked.isNotEmpty) {
      _rejectedDriverIds.add(ranked.first.driver.id);
    }
  }

  @override
  void dispose() {
    _dispatchCountdownTimer?.cancel();
    _store.removeListener(_onStoreChanged);
    _drvNameCtrl.dispose();
    _drvPhoneCtrl.dispose();
    _drvCitizenCtrl.dispose();
    _drvPlateCtrl.dispose();
    _drvBankNameCtrl.dispose();
    _drvBankAccCtrl.dispose();
    _podOtpCtrl.dispose();
    _podRecipientCtrl.dispose();
    _podNoteCtrl.dispose();
    _driverChatInputCtrl.dispose();
    _withdrawAmountCtrl.dispose();
    _incidentNoteCtrl.dispose();
    super.dispose();
  }

  // Thanh điều hướng đáy 4 tab màu xanh đen #0F172A giống hệt uc14, uc18, uc19, uc21:
  // 0: Trang chủ | 1: Đơn hàng | 2: Thu nhập | 3: Hồ sơ
  int _bottomNavIndexForScreen(int screenIdx) {
    if (screenIdx == 1) return 0; // Trang chủ
    if (screenIdx == 2 ||
        screenIdx == 3 ||
        screenIdx == 4 ||
        screenIdx == 5 ||
        screenIdx == 7 ||
        screenIdx == 9) {
      return 1; // Đơn hàng / Nhận đơn / Điều hướng / POD / Lịch sử giao
    }
    if (screenIdx == 6) return 2; // Thu nhập
    return 3; // Hồ sơ & Thống kê (0, 8)
  }

  void _onBottomNavTapped(int navIdx) {
    setState(() {
      switch (navIdx) {
        case 0:
          _selectedScreenIndex = 1; // Trang chủ (UC14)
          break;
        case 1:
          _selectedScreenIndex = _store.activeDriverInProgressOrder != null
              ? 3
              : 9;
          break;
        case 2:
          _selectedScreenIndex = 6; // Thu nhập và rút tiền (UC18)
          break;
        case 3:
          _selectedScreenIndex = 8; // Thống kê hoạt động & Hồ sơ (UC21/UC13)
          break;
      }
    });
  }

  bool get _isDriverSubScreen =>
      _selectedScreenIndex == 0 ||
      _selectedScreenIndex == 3 ||
      _selectedScreenIndex == 4 ||
      _selectedScreenIndex == 5 ||
      _selectedScreenIndex == 7;

  void _navigateBackFromDriverSubScreen() {
    setState(() {
      if (_selectedScreenIndex == 0) {
        _selectedScreenIndex = 8;
      } else if (_selectedScreenIndex == 4 ||
          _selectedScreenIndex == 5 ||
          _selectedScreenIndex == 7) {
        _selectedScreenIndex = 3;
      } else {
        _selectedScreenIndex = 1;
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
            285.0,
          );
          final contentPadding = (constraints.maxWidth * 0.02).clamp(
            16.0,
            32.0,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDriverStudioSidebar(sidebarWidth),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDriverWhiteTopBar(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(contentPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OfflineQueueBanner(store: _store),
                            if (_isDriverSubScreen) ...[
                              _buildDriverSubScreenHeader(),
                              const SizedBox(height: 14),
                            ],
                            _buildActiveDriverScreen(context),
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
            _buildDriverHeaderBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(mobilePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OfflineQueueBanner(store: _store),
                    if (_isDriverSubScreen) ...[
                      _buildDriverSubScreenHeader(),
                      const SizedBox(height: 8),
                    ],
                    _buildActiveDriverScreen(context),
                  ],
                ),
              ),
            ),
            _buildDesignDriverDarkBottomBar(),
          ],
        );
      },
    );
  }

  Widget _buildDriverStudioSidebar(double sidebarWidth) {
    const navGroups = <(String, List<(IconData, String, int)>)>[
      (
        'ĐIỀU PHỐI & LỘ TRÌNH',
        [
          (Icons.radar_rounded, 'Trạng thái & Bản đồ GPS', 1),
          (Icons.history_rounded, 'Lịch sử giao hàng', 9),
        ],
      ),
      (
        'TÀI CHÍNH & HỒ SƠ',
        [
          (Icons.account_balance_wallet_outlined, 'Thu nhập & Ví tài xế', 6),
          (Icons.insights_rounded, 'Hồ sơ & hiệu suất', 8),
        ],
      ),
    ];
    final activeOrd =
        _store.activeDriverInProgressOrder ??
        _store.orders
            .where(_isSearchingOrderCompatibleWithActiveDriver)
            .firstOrNull;
    final hasActiveTrip = _store.isDriverOnline && activeOrd != null;
    final drvRec = _store.activeDriverRecord;
    final isEv = drvRec?.isElectricVehicle ?? false;
    final batPct = drvRec?.batteryPercent ?? 100;

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
              padding: const EdgeInsets.fromLTRB(18, 18, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.acid,
                      border: Border.all(color: AppColors.techBg),
                    ),
                    child: GhstButtonIcon(
                      isEv
                          ? Icons.electric_moped_rounded
                          : Icons.two_wheeler_rounded,
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
                          'GHST DRIVER',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15.5,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          'ĐỐI TÁC TÀI XẾ',
                          style: TextStyle(
                            color: AppColors.acid,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Consolas',
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  border: Border.all(color: AppColors.techLine),
                ),
                child: Row(
                  children: [
                    GhstButtonIcon(
                      isEv ? Icons.battery_charging_full_rounded : Icons.verified_rounded,
                      size: 15,
                      color: isEv ? const Color(0xFF4ADE80) : AppColors.acid,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isEv
                            ? 'Xe điện EV • Pin $batPct% • ★ ${(drvRec?.rating ?? 5.0).toStringAsFixed(1)}'
                            : '${drvRec?.vehicleType ?? "Xe máy"} • ★ ${(drvRec?.rating ?? 5.0).toStringAsFixed(1)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(color: AppColors.techLine, height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasActiveTrip) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        child: InkWell(
                          onTap: () => setState(() {
                            _selectedScreenIndex =
                                activeOrd.status == OrderStatus.searching
                                ? 2
                                : 3;
                          }),
                          child: Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: AppColors.acid.withValues(alpha: 0.14),
                              border: Border.all(
                                color: AppColors.acid,
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: AppColors.acid,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        activeOrd.status ==
                                                OrderStatus.searching
                                            ? 'CUỐC XE MỚI ĐANG CHỜ'
                                            : 'CUỐC XE ĐANG CHẠY',
                                        style: const TextStyle(
                                          color: AppColors.acid,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          fontFamily: 'Consolas',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${activeOrd.trackingCode} • ${activeOrd.status.displayName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  activeOrd.status == OrderStatus.searching
                                      ? 'Chạm để nhận cuốc xe ngay →'
                                      : 'Chạm để mở Điều hướng GPS →',
                                  style: const TextStyle(
                                    color: AppColors.techMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    for (final group in navGroups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
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
                      ...group.$2.map((item) {
                        final selected =
                            _selectedScreenIndex == item.$3 ||
                            (item.$3 == 1 &&
                                (_selectedScreenIndex == 2 ||
                                    _selectedScreenIndex == 3 ||
                                    _selectedScreenIndex == 4 ||
                                    _selectedScreenIndex == 5 ||
                                    _selectedScreenIndex == 7)) ||
                            (item.$3 == 8 && _selectedScreenIndex == 0);
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          child: InkWell(
                            onTap: () =>
                                setState(() => _selectedScreenIndex = item.$3),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
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
                                  GhstButtonIcon(
                                    item.$1,
                                    size: 19,
                                    color: selected
                                        ? AppColors.acid
                                        : AppColors.techMuted,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      item.$2,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : AppColors.techMuted,
                                        fontSize: 13,
                                        fontWeight: selected
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                      ),
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
                leading: const GhstButtonIcon(
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

  Widget _buildDriverWhiteTopBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showPlateBadge = constraints.maxWidth >= 900;
        final isCompactBar = constraints.maxWidth < 680;
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
                style: Icon3dStyle.gpsPinRadar,
                size: 38,
                showRadarPulse: false,
                isSelected: true,
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
              IconButton(
                tooltip: 'Đơn hàng trực tuyến',
                onPressed: () => Navigator.of(context).pushNamed('/cloud'),
                icon: const GhstButtonIcon(Icons.cloud_outlined),
              ),
              if (showPlateBadge) ...[
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      border: Border.all(color: AppColors.ink, width: 1.2),
                    ),
                    child: Text(
                      'Biển số: ${_store.activeDriverRecord?.licensePlate ?? "Chưa đăng ký"} • Ví: ${CurrencyFormatter.formatVnd(_store.activeDriverRecord?.walletBalance ?? 0.0)}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Consolas',
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Thông báo Đối tác Tài xế',
                    onPressed: () => _showDriverNotificationsDialog(context),
                    icon: const GhstButtonIcon(
                      Icons.notifications_none_rounded,
                      color: AppColors.ink,
                      size: 22,
                    ),
                  ),
                  if (_store.driverNotifications.any((n) => !n.isRead))
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
                          '${_store.driverNotifications.where((n) => !n.isRead).length}',
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
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: _store.isDriverOnline
                    ? 'Tắt nhận chuyến'
                    : 'Bật nhận chuyến',
                isSelected: _store.isDriverOnline,
                onPressed: () => _handleHeaderToggleDriverOnline(context),
                icon: const GhstButtonIcon(Icons.power_settings_new_rounded),
                selectedIcon: const GhstButtonIcon(
                  Icons.sensors_rounded,
                  color: Color(0xFF14B866),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDriverHeaderBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.techBg,
        border: Border.all(color: AppColors.ink, width: 1.5),
        boxShadow: const [
          BoxShadow(color: AppColors.pink, offset: Offset(0, 4), blurRadius: 14),
        ],
      ),
      child: Row(
        children: [
          const Animated3dIconBadge(
            style: Icon3dStyle.gpsPinRadar,
            size: 40,
            showRadarPulse: false,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _screenTitles[_selectedScreenIndex],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tài xế: ${_store.activeDriverRecord?.fullName ?? _store.activeAuthenticatedUser?.fullName ?? _store.activeDriverName} • Ví: ${CurrencyFormatter.formatVnd(_store.activeDriverRecord?.walletBalance ?? 0.0)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.acid,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Consolas',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Đơn hàng trực tuyến',
            color: Colors.white,
            onPressed: () => Navigator.of(context).pushNamed('/cloud'),
            icon: const GhstButtonIcon(Icons.cloud_outlined),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _showDriverNotificationsDialog(context),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Padding(
                  padding: EdgeInsets.all(6),
                  child: GhstButtonIcon(
                    Icons.notifications_none_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                if (_store.driverNotifications.any((n) => !n.isRead))
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
                        '${_store.driverNotifications.where((n) => !n.isRead).length}',
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
          const SizedBox(width: 4),
          IconButton(
            tooltip: _store.isDriverOnline
                ? 'Tắt nhận chuyến'
                : 'Bật nhận chuyến',
            isSelected: _store.isDriverOnline,
            onPressed: () => _handleHeaderToggleDriverOnline(context),
            icon: const GhstButtonIcon(
              Icons.power_settings_new_rounded,
              color: Colors.white,
            ),
            selectedIcon: const GhstButtonIcon(
              Icons.sensors_rounded,
              color: Color(0xFF14B866),
            ),
          ),
          if (widget.onLogout != null) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Đăng xuất',
              onPressed: widget.onLogout,
              icon: const GhstButtonIcon(Icons.logout, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDesignDriverDarkBottomBar() {
    final activeNav = _bottomNavIndexForScreen(_selectedScreenIndex);
    const items = [
      (Icons.home_rounded, 'Trang chủ'),
      (Icons.inventory_2_outlined, 'Đơn hàng'),
      (Icons.account_balance_wallet_outlined, 'Thu nhập'),
      (Icons.person_outline_rounded, 'Hồ sơ'),
    ];

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.techBg,
        border: Border.all(color: AppColors.ink, width: 1.5),
        boxShadow: const [
          BoxShadow(color: AppColors.pink, offset: Offset(0, 4), blurRadius: 14),
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
                    GhstButtonIcon(items[idx].$1, color: color, size: 22),
                    const SizedBox(height: 3),
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

  Widget _buildDriverSubScreenHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink, width: 1.4),
        boxShadow: const [
          BoxShadow(color: AppColors.ink, offset: Offset(0, 4), blurRadius: 14),
        ],
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _navigateBackFromDriverSubScreen,
            icon: const GhstButtonIcon(Icons.arrow_back_ios_new_rounded, size: 15),
            label: const Text('Quay lại'),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _screenTitles[_selectedScreenIndex],
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
                color: AppColors.violet,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveDriverScreen(BuildContext context) {
    switch (_selectedScreenIndex) {
      case 0:
        return _buildDriverKycRegistrationView();
      case 1:
        return _buildDriverHomeOnlineView();
      case 2:
        return _buildIncomingOrderPopupView();
      case 3:
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTurnByTurnNavigationView(),
            if (_store.activeDriverPersonalOrderRecord != null) ...[
              const SizedBox(height: 12),
              _buildTripStepProgressView(),
            ],
          ],
        );
      case 5:
        return _buildPodConfirmationView();
      case 6:
        return _buildDriverWalletView();
      case 7:
        return _buildRoadIncidentReportView();
      case 8:
        return _buildDarkModeAnalyticsView();
      case 9:
        return _buildDriverTripHistoryUc19View();
      default:
        return _buildDriverHomeOnlineView();
    }
  }

  void _showDriverNotificationsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final items = _store.driverNotifications;
            return AlertDialog(
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
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
                    'Thông báo Đối tác Tài xế (${items.where((n) => !n.isRead).length} chưa đọc)',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _store.markAllNotificationsAsRead(
                        targetGroupScope: 'Tài xế',
                      );
                      setDialogState(() {});
                    },
                    icon: const GhstButtonIcon.glyph(GhstActionKind.checkCircle, size: 16),

                    label: const Text(
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
                          'Chưa có thông báo nào dành cho Tài xế.',
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
                                _store.selectDriverOrder(orderCode);
                                final ord = _store.orders
                                    .where((o) => o.trackingCode == orderCode)
                                    .firstOrNull;
                                Navigator.of(dialogCtx).pop();
                                setState(() {
                                  _selectedScreenIndex =
                                      ord?.status == OrderStatus.searching
                                      ? 2
                                      : 3;
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
                                      'Nhấn để mở chuyến xe $orderCode →',
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
                TextButton.icon(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),

                  label: const Text('Đóng'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleHeaderToggleDriverOnline(
    BuildContext context, {
    bool? targetOnline,
  }) {
    final nextOnline = targetOnline ?? !_store.isDriverOnline;
    if (!nextOnline) {
      final ongoingOrd = _store.driverPersonalOrders
          .where(
            (o) =>
                o.status == OrderStatus.accepted ||
                o.status == OrderStatus.arrivingPickup ||
                o.status == OrderStatus.inTransit ||
                o.status == OrderStatus.returning,
          )
          .firstOrNull;
      if (ongoingOrd != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text(
              'Không thể tắt Offline khi đang thực hiện cuốc xe ${ongoingOrd.trackingCode} (${ongoingOrd.status.displayName})! Vui lòng hoàn tất giao hàng hoặc báo cáo sự cố trước.',
            ),
          ),
        );
        return;
      }
      _store.setDriverOnlineStatus(false);
      return;
    }
    final activeDrv = _store.activeDriverRecord;
    if (activeDrv == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'Bạn chưa gửi hồ sơ đăng ký Tài xế. Vui lòng hoàn tất KYC trước khi bật trực tuyến!',
          ),
        ),
      );
      setState(() => _selectedScreenIndex = 0);
      return;
    }
    final linkedUser = _store.findUserByPhone(activeDrv.phone);
    if (linkedUser?.status == 'LOCKED') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'Tài khoản Tài xế hiện đang bị tạm khóa bởi Quản trị viên. Không thể bật trực tuyến!',
          ),
        ),
      );
      return;
    }
    if (activeDrv.approvalStatus != 'Đã duyệt') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'Hồ sơ Tài xế đang ở trạng thái "${activeDrv.approvalStatus}". Vui lòng chờ Admin duyệt KYC trước khi bật trực tuyến!',
          ),
        ),
      );
      setState(() => _selectedScreenIndex = 0);
      return;
    }
    if (activeDrv.walletBalance < 200000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.warning,
          content: Text(
            'Số dư ví ký quỹ (${CurrencyFormatter.formatVnd(activeDrv.walletBalance)}) thấp hơn 200.000đ. Đang chuyển tới Ví Thu nhập để nạp ký quỹ!',
          ),
        ),
      );
      setState(() => _selectedScreenIndex = 6);
      return;
    }
    _store.setDriverOnlineStatus(true);
  }

  void _rebuildDriverUi(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _syncDispatchCountdownTimer();
  }
}
