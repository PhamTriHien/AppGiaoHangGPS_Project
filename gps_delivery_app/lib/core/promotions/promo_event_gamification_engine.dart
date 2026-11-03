import 'dart:math' as math;

import '../../data/models/app_state_records.dart';

enum PromoRarityTier {
  common('R', 'Phổ thông'),
  rare('SR', 'Hiếm'),
  legendary('SSR', 'Siêu hiếm');

  final String code;
  final String displayName;
  const PromoRarityTier(this.code, this.displayName);

  static PromoRarityTier fromCode(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'SSR':
        return PromoRarityTier.legendary;
      case 'SR':
        return PromoRarityTier.rare;
      default:
        return PromoRarityTier.common;
    }
  }
}

enum PromoRewardType {
  voucher,
  coins,
  blindBoxTicket,
  spinTicket,
}

class FlashPromoCampaign {
  final String id;
  final String platformStyle;
  final String timeSlotBadge;
  final String codePrefix;
  final String title;
  final String subtitle;
  final double discountValue;
  final bool isPercentage;
  final double maxDiscount;
  final double minOrderValue;
  final double baseClaimedRatio;
  final int bonusCoins;
  final String targetChannel; // 'ALL' | 'GRABFOOD' | 'DELIVERY'

  const FlashPromoCampaign({
    required this.id,
    required this.platformStyle,
    required this.timeSlotBadge,
    required this.codePrefix,
    required this.title,
    required this.subtitle,
    required this.discountValue,
    required this.isPercentage,
    required this.maxDiscount,
    required this.minOrderValue,
    required this.baseClaimedRatio,
    required this.bonusCoins,
    this.targetChannel = 'ALL',
  });

  String get discountBadgeLabel => isPercentage
      ? 'Giảm ${discountValue.toStringAsFixed(0)}%'
      : 'Giảm ${(discountValue / 1000).toStringAsFixed(0)}k';
}

class SpinWheelSegment {
  final int index;
  final String shortLabel;
  final String fullTitle;
  final int weight;
  final PromoRewardType rewardType;
  final PromoRarityTier rarity;
  final String? voucherCodePrefix;
  final double discountValue;
  final bool isPercentage;
  final double maxDiscount;
  final double minOrderValue;
  final int bonusCoins;
  final int bonusTickets;
  final int sliceHexColor;
  final int textHexColor;

  const SpinWheelSegment({
    required this.index,
    required this.shortLabel,
    required this.fullTitle,
    required this.weight,
    required this.rewardType,
    required this.rarity,
    this.voucherCodePrefix,
    this.discountValue = 0,
    this.isPercentage = false,
    this.maxDiscount = 0,
    this.minOrderValue = 0,
    this.bonusCoins = 0,
    this.bonusTickets = 0,
    required this.sliceHexColor,
    required this.textHexColor,
  });
}

class BlindBoxPrizeSpec {
  final String id;
  final String title;
  final String description;
  final PromoRarityTier rarity;
  final int weight;
  final PromoRewardType rewardType;
  final String? voucherCodePrefix;
  final double discountValue;
  final bool isPercentage;
  final double maxDiscount;
  final double minOrderValue;
  final int bonusCoins;
  final int bonusSpinTickets;

  const BlindBoxPrizeSpec({
    required this.id,
    required this.title,
    required this.description,
    required this.rarity,
    required this.weight,
    required this.rewardType,
    this.voucherCodePrefix,
    this.discountValue = 0,
    this.isPercentage = false,
    this.maxDiscount = 0,
    this.minOrderValue = 0,
    this.bonusCoins = 0,
    this.bonusSpinTickets = 0,
  });
}

class BlindBoxSlotInfo {
  final int boxIndex;
  final String boxCode;
  final String themeTitle;
  final String themeTag;
  final int accentHexColor;

  const BlindBoxSlotInfo({
    required this.boxIndex,
    required this.boxCode,
    required this.themeTitle,
    required this.themeTag,
    required this.accentHexColor,
  });
}

class DailyCheckInRewardSpec {
  final int dayNumber;
  final int coins;
  final int bonusSpinTickets;
  final int bonusBlindBoxTickets;
  final String highlightLabel;

  const DailyCheckInRewardSpec({
    required this.dayNumber,
    required this.coins,
    this.bonusSpinTickets = 0,
    this.bonusBlindBoxTickets = 0,
    required this.highlightLabel,
  });
}

class PromoMissionProgress {
  final String id;
  final String title;
  final String description;
  final int currentCount;
  final int targetCount;
  final int rewardCoins;
  final int rewardSpinTickets;
  final int rewardBlindBoxTickets;
  final bool isClaimed;

  const PromoMissionProgress({
    required this.id,
    required this.title,
    required this.description,
    required this.currentCount,
    required this.targetCount,
    required this.rewardCoins,
    required this.rewardSpinTickets,
    required this.rewardBlindBoxTickets,
    required this.isClaimed,
  });

  bool get isCompleted => currentCount >= targetCount;
  bool get canClaim => isCompleted && !isClaimed;
  double get progressRatio =>
      targetCount <= 0 ? 1.0 : (currentCount / targetCount).clamp(0.0, 1.0);
}

class PromoRewardHistoryEntry {
  final String id;
  final String source;
  final String title;
  final String summary;
  final String rarityCode;
  final String? voucherCode;
  final String timestampLabel;

  const PromoRewardHistoryEntry({
    required this.id,
    required this.source,
    required this.title,
    required this.summary,
    required this.rarityCode,
    this.voucherCode,
    required this.timestampLabel,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'title': title,
    'summary': summary,
    'rarityCode': rarityCode,
    if (voucherCode != null) 'voucherCode': voucherCode,
    'timestampLabel': timestampLabel,
  };

  factory PromoRewardHistoryEntry.fromJson(Map<String, dynamic> json) {
    return PromoRewardHistoryEntry(
      id: (json['id'] ?? '').toString(),
      source: (json['source'] ?? 'EVENT').toString(),
      title: (json['title'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      rarityCode: (json['rarityCode'] ?? 'R').toString(),
      voucherCode: json['voucherCode']?.toString(),
      timestampLabel: (json['timestampLabel'] ?? '').toString(),
    );
  }
}

class OpenedBlindBoxRecord {
  final int boxIndex;
  final String title;
  final String summary;
  final String rarityCode;
  final String? voucherCode;

  const OpenedBlindBoxRecord({
    required this.boxIndex,
    required this.title,
    required this.summary,
    required this.rarityCode,
    this.voucherCode,
  });

  Map<String, dynamic> toJson() => {
    'boxIndex': boxIndex,
    'title': title,
    'summary': summary,
    'rarityCode': rarityCode,
    if (voucherCode != null) 'voucherCode': voucherCode,
  };

  factory OpenedBlindBoxRecord.fromJson(Map<String, dynamic> json) {
    return OpenedBlindBoxRecord(
      boxIndex: (json['boxIndex'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      rarityCode: (json['rarityCode'] ?? 'R').toString(),
      voucherCode: json['voucherCode']?.toString(),
    );
  }
}

class CustomerPromoWalletState {
  static const int starterCoins = 120;
  static const int starterSpinTickets = 2;
  static const int starterBlindBoxTickets = 1;

  final int ghstCoins;
  final int spinTickets;
  final int blindBoxTickets;
  final int checkInStreak;
  final String lastCheckInDate;
  final Set<String> claimedCampaignIds;
  final Set<String> claimedMissionIds;
  final Map<int, OpenedBlindBoxRecord> openedBlindBoxes;
  final List<PromoRewardHistoryEntry> history;
  final int totalSpinsCount;
  final int totalBlindBoxesOpened;

  const CustomerPromoWalletState({
    this.ghstCoins = starterCoins,
    this.spinTickets = starterSpinTickets,
    this.blindBoxTickets = starterBlindBoxTickets,
    this.checkInStreak = 0,
    this.lastCheckInDate = '',
    this.claimedCampaignIds = const <String>{},
    this.claimedMissionIds = const <String>{},
    this.openedBlindBoxes = const <int, OpenedBlindBoxRecord>{},
    this.history = const <PromoRewardHistoryEntry>[],
    this.totalSpinsCount = 0,
    this.totalBlindBoxesOpened = 0,
  });

  bool hasCheckedInOn(DateTime date) =>
      lastCheckInDate == PromoEventGamificationEngine.formatDateKey(date);

  Map<String, dynamic> toJson() => {
    'ghstCoins': ghstCoins,
    'spinTickets': spinTickets,
    'blindBoxTickets': blindBoxTickets,
    'checkInStreak': checkInStreak,
    'lastCheckInDate': lastCheckInDate,
    'claimedCampaignIds': claimedCampaignIds.toList(),
    'claimedMissionIds': claimedMissionIds.toList(),
    'openedBlindBoxes': openedBlindBoxes.map(
      (k, v) => MapEntry(k.toString(), v.toJson()),
    ),
    'history': history.take(30).map((e) => e.toJson()).toList(),
    'totalSpinsCount': totalSpinsCount,
    'totalBlindBoxesOpened': totalBlindBoxesOpened,
  };

  factory CustomerPromoWalletState.fromJson(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) {
      return const CustomerPromoWalletState();
    }
    final openedMap = <int, OpenedBlindBoxRecord>{};
    final rawOpened = raw['openedBlindBoxes'];
    if (rawOpened is Map) {
      rawOpened.forEach((k, v) {
        final idx = int.tryParse(k.toString());
        if (idx != null && v is Map) {
          openedMap[idx] = OpenedBlindBoxRecord.fromJson(
            Map<String, dynamic>.from(v),
          );
        }
      });
    }
    final parsedHistory = <PromoRewardHistoryEntry>[];
    final rawHist = raw['history'];
    if (rawHist is List) {
      for (final item in rawHist) {
        if (item is Map) {
          parsedHistory.add(
            PromoRewardHistoryEntry.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return CustomerPromoWalletState(
      ghstCoins: (raw['ghstCoins'] as num?)?.toInt() ?? starterCoins,
      spinTickets: (raw['spinTickets'] as num?)?.toInt() ?? starterSpinTickets,
      blindBoxTickets:
          (raw['blindBoxTickets'] as num?)?.toInt() ?? starterBlindBoxTickets,
      checkInStreak: (raw['checkInStreak'] as num?)?.toInt() ?? 0,
      lastCheckInDate: (raw['lastCheckInDate'] ?? '').toString(),
      claimedCampaignIds: (raw['claimedCampaignIds'] is List)
          ? (raw['claimedCampaignIds'] as List)
                .map((e) => e.toString())
                .toSet()
          : const <String>{},
      claimedMissionIds: (raw['claimedMissionIds'] is List)
          ? (raw['claimedMissionIds'] as List).map((e) => e.toString()).toSet()
          : const <String>{},
      openedBlindBoxes: openedMap,
      history: parsedHistory,
      totalSpinsCount: (raw['totalSpinsCount'] as num?)?.toInt() ?? 0,
      totalBlindBoxesOpened:
          (raw['totalBlindBoxesOpened'] as num?)?.toInt() ?? 0,
    );
  }
}

class PromoActionOutcome {
  final bool success;
  final String message;
  final String rewardTitle;
  final PromoRarityTier rarity;
  final int? wheelSegmentIndex;
  final int? blindBoxIndex;
  final String? mintedVoucherCode;
  final int coinsDelta;
  final int spinTicketsDelta;
  final int blindBoxTicketsDelta;

  const PromoActionOutcome({
    required this.success,
    required this.message,
    this.rewardTitle = '',
    this.rarity = PromoRarityTier.common,
    this.wheelSegmentIndex,
    this.blindBoxIndex,
    this.mintedVoucherCode,
    this.coinsDelta = 0,
    this.spinTicketsDelta = 0,
    this.blindBoxTicketsDelta = 0,
  });
}

/// Động cơ Sự kiện Khuyến mãi Gamification kiểu Shopee × Grab:
/// - Khung Giờ Vàng Flash Sale (0H • 12H • 18H • 20H)
/// - Điểm danh 7 ngày tích GHST Xu & Nhiệm vụ GrabChallenges
/// - Vòng Xoay May Mắn 8 ô có trọng số xác suất (Lucky Spin Wheel)
/// - Hộp Mù Bí Ẩn 6 ô phân bậc độ hiếm R / SR / SSR (Mystery Blind Box Gacha)
class PromoEventGamificationEngine {
  const PromoEventGamificationEngine._();

  static const int coinsPerSpinTicket = 150;
  static const int coinsPerBlindBoxTicket = 250;
  static const int coinsPerDirectVoucher25k = 400;

  static const List<DailyCheckInRewardSpec> dailyCheckInSchedule = [
    DailyCheckInRewardSpec(
      dayNumber: 1,
      coins: 50,
      highlightLabel: '+50 Xu',
    ),
    DailyCheckInRewardSpec(
      dayNumber: 2,
      coins: 100,
      highlightLabel: '+100 Xu',
    ),
    DailyCheckInRewardSpec(
      dayNumber: 3,
      coins: 120,
      bonusSpinTickets: 1,
      highlightLabel: '+120 Xu & 1 Quay',
    ),
    DailyCheckInRewardSpec(
      dayNumber: 4,
      coins: 150,
      highlightLabel: '+150 Xu',
    ),
    DailyCheckInRewardSpec(
      dayNumber: 5,
      coins: 180,
      bonusBlindBoxTickets: 1,
      highlightLabel: '+180 Xu & 1 Hộp Mù',
    ),
    DailyCheckInRewardSpec(
      dayNumber: 6,
      coins: 220,
      highlightLabel: '+220 Xu',
    ),
    DailyCheckInRewardSpec(
      dayNumber: 7,
      coins: 350,
      bonusSpinTickets: 1,
      bonusBlindBoxTickets: 1,
      highlightLabel: 'Quà Lớn: +350 Xu, 1 Quay, 1 Hộp',
    ),
  ];

  static const List<FlashPromoCampaign> flashSaleCampaigns = [
    FlashPromoCampaign(
      id: 'CAMP_FLASH_0H_50P',
      platformStyle: 'Shopee Flash Sale 0H',
      timeSlotBadge: '00:00 • GIỜ VÀNG',
      codePrefix: 'FLASH50P',
      title: 'Siêu Sale Freeship Giảm 50% (Tối đa 35k)',
      subtitle: 'Áp dụng mọi chuyến Giao hàng GPS & Đặt món GrabFood từ 40.000đ',
      discountValue: 50,
      isPercentage: true,
      maxDiscount: 35000,
      minOrderValue: 40000,
      baseClaimedRatio: 0.78,
      bonusCoins: 20,
      targetChannel: 'ALL',
    ),
    FlashPromoCampaign(
      id: 'CAMP_GRABFOOD_TRUA_30K',
      platformStyle: 'GrabFood Bữa Ngon',
      timeSlotBadge: '11:00 - 14:00',
      codePrefix: 'GRABFOOD30K',
      title: 'Trợ Giá Giao Món Ăn Trưa & Trà Chiều 30.000đ',
      subtitle: 'Giảm thẳng 30.000đ phí ship món nóng & túi giữ lạnh từ 60.000đ',
      discountValue: 30000,
      isPercentage: false,
      maxDiscount: 30000,
      minOrderValue: 60000,
      baseClaimedRatio: 0.66,
      bonusCoins: 25,
      targetChannel: 'GRABFOOD',
    ),
    FlashPromoCampaign(
      id: 'CAMP_XANH_EV_25K',
      platformStyle: 'Xanh SM × GrabEco',
      timeSlotBadge: 'CẢ NGÀY • SỐNG XANH',
      codePrefix: 'XANHEV25K',
      title: 'Ưu Đãi Chuyến Giao Xe Máy Điện Không Khói 25.000đ',
      subtitle: 'Giảm 25.000đ khi bật tùy chọn Giao Xanh EV (đơn tối thiểu 30.000đ)',
      discountValue: 25000,
      isPercentage: false,
      maxDiscount: 25000,
      minOrderValue: 30000,
      baseClaimedRatio: 0.54,
      bonusCoins: 30,
      targetChannel: 'DELIVERY',
    ),
    FlashPromoCampaign(
      id: 'CAMP_SHOPEE_GHEP2H_20K',
      platformStyle: 'Shopee Freeship Xtra',
      timeSlotBadge: '16:00 - 19:00',
      codePrefix: 'GHEP2H20K',
      title: 'Freeship Đơn 0Đ • Tuyến Ghép Đơn Thông Minh 2H',
      subtitle: 'Giảm ngay 20.000đ không cần giá trị tối thiểu cho mọi kiện hàng',
      discountValue: 20000,
      isPercentage: false,
      maxDiscount: 20000,
      minOrderValue: 0,
      baseClaimedRatio: 0.84,
      bonusCoins: 15,
      targetChannel: 'ALL',
    ),
    FlashPromoCampaign(
      id: 'CAMP_NIGHT_EXPRESS_45K',
      platformStyle: 'GrabExpress Siêu Tốc',
      timeSlotBadge: '20:00 - 23:59',
      codePrefix: 'SIEUTOC45K',
      title: 'Săn Deal Đêm • Giảm 45.000đ Hỏa Tốc & Ăn Đêm',
      subtitle: 'Ưu đãi đặc quyền đơn hỏa tốc 30 phút hoặc ăn khuya từ 90.000đ',
      discountValue: 45000,
      isPercentage: false,
      maxDiscount: 45000,
      minOrderValue: 90000,
      baseClaimedRatio: 0.71,
      bonusCoins: 30,
      targetChannel: 'ALL',
    ),
  ];

  /// 8 ô Vòng Xoay May Mắn (tổng trọng số = 100)
  static const List<SpinWheelSegment> spinWheelSegments = [
    SpinWheelSegment(
      index: 0,
      shortLabel: 'SHIP -15K',
      fullTitle: 'Voucher Freeship 15.000đ (Đơn 0đ)',
      weight: 20,
      rewardType: PromoRewardType.voucher,
      rarity: PromoRarityTier.common,
      voucherCodePrefix: 'SPIN15K',
      discountValue: 15000,
      isPercentage: false,
      maxDiscount: 15000,
      minOrderValue: 0,
      bonusCoins: 10,
      sliceHexColor: 0xFFC8FF32,
      textHexColor: 0xFF122033,
    ),
    SpinWheelSegment(
      index: 1,
      shortLabel: '+150 XU',
      fullTitle: 'Túi Thưởng +150 GHST Xu',
      weight: 22,
      rewardType: PromoRewardType.coins,
      rarity: PromoRarityTier.common,
      bonusCoins: 150,
      sliceHexColor: 0xFFFDE68A,
      textHexColor: 0xFF122033,
    ),
    SpinWheelSegment(
      index: 2,
      shortLabel: 'FOOD -50%',
      fullTitle: 'Voucher GrabFood & Ship Giảm 50% (Tối đa 35k)',
      weight: 12,
      rewardType: PromoRewardType.voucher,
      rarity: PromoRarityTier.rare,
      voucherCodePrefix: 'SPINFOOD50',
      discountValue: 50,
      isPercentage: true,
      maxDiscount: 35000,
      minOrderValue: 35000,
      bonusCoins: 20,
      sliceHexColor: 0xFF00B14F,
      textHexColor: 0xFFFFFFFF,
    ),
    SpinWheelSegment(
      index: 3,
      shortLabel: '+1 HỘP MÙ',
      fullTitle: 'Vé Vàng Mở 1 Hộp Mù Bí Ẩn + 50 Xu',
      weight: 10,
      rewardType: PromoRewardType.blindBoxTicket,
      rarity: PromoRarityTier.rare,
      bonusTickets: 1,
      bonusCoins: 50,
      sliceHexColor: 0xFF1E56C5,
      textHexColor: 0xFFFFFFFF,
    ),
    SpinWheelSegment(
      index: 4,
      shortLabel: 'XANH -25K',
      fullTitle: 'Voucher Giao Hàng & Xe Điện Xanh 25.000đ',
      weight: 12,
      rewardType: PromoRewardType.voucher,
      rarity: PromoRarityTier.rare,
      voucherCodePrefix: 'SPINEV25K',
      discountValue: 25000,
      isPercentage: false,
      maxDiscount: 25000,
      minOrderValue: 30000,
      bonusCoins: 15,
      sliceHexColor: 0xFF38BDF8,
      textHexColor: 0xFF122033,
    ),
    SpinWheelSegment(
      index: 5,
      shortLabel: '+80 XU',
      fullTitle: 'Xu May Mắn +80 GHST Xu',
      weight: 14,
      rewardType: PromoRewardType.coins,
      rarity: PromoRarityTier.common,
      bonusCoins: 80,
      sliceHexColor: 0xFFEEF3F8,
      textHexColor: 0xFF122033,
    ),
    SpinWheelSegment(
      index: 6,
      shortLabel: 'JACKPOT 45K',
      fullTitle: 'Độc Đắc! Voucher Siêu Tốc 45.000đ + 100 Xu',
      weight: 4,
      rewardType: PromoRewardType.voucher,
      rarity: PromoRarityTier.legendary,
      voucherCodePrefix: 'SPINJP45K',
      discountValue: 45000,
      isPercentage: false,
      maxDiscount: 45000,
      minOrderValue: 45000,
      bonusCoins: 100,
      sliceHexColor: 0xFFC85A17,
      textHexColor: 0xFFFFFFFF,
    ),
    SpinWheelSegment(
      index: 7,
      shortLabel: '+300 XU',
      fullTitle: 'Kho Báu +300 GHST Xu Đổi Quà',
      weight: 6,
      rewardType: PromoRewardType.coins,
      rarity: PromoRarityTier.rare,
      bonusCoins: 300,
      sliceHexColor: 0xFFF59E0B,
      textHexColor: 0xFF122033,
    ),
  ];

  /// 6 chiếc Hộp Mù Bí Ẩn trên bàn Gacha
  static const List<BlindBoxSlotInfo> blindBoxBoardSlots = [
    BlindBoxSlotInfo(
      boxIndex: 0,
      boxCode: 'BOX #01',
      themeTitle: 'Hộp Tia Chớp Đỏ',
      themeTag: 'Chủ đề Hỏa tốc 30p',
      accentHexColor: 0xFFC85A17,
    ),
    BlindBoxSlotInfo(
      boxIndex: 1,
      boxCode: 'BOX #02',
      themeTitle: 'Hộp Bếp Xanh Grab',
      themeTag: 'Chủ đề Ẩm thực nóng',
      accentHexColor: 0xFF00B14F,
    ),
    BlindBoxSlotInfo(
      boxIndex: 2,
      boxCode: 'BOX #03',
      themeTitle: 'Hộp Năng Lượng EV',
      themeTag: 'Chủ đề Xanh SM Eco',
      accentHexColor: 0xFF0EA5E9,
    ),
    BlindBoxSlotInfo(
      boxIndex: 3,
      boxCode: 'BOX #04',
      themeTitle: 'Hộp Kho Báu Vàng',
      themeTag: 'Chủ đề Săn Xu Khủng',
      accentHexColor: 0xFFF59E0B,
    ),
    BlindBoxSlotInfo(
      boxIndex: 4,
      boxCode: 'BOX #05',
      themeTitle: 'Hộp Kiện Hàng Tím',
      themeTag: 'Chủ đề Đa điểm 2-Opt',
      accentHexColor: 0xFF1E56C5,
    ),
    BlindBoxSlotInfo(
      boxIndex: 5,
      boxCode: 'BOX #06',
      themeTitle: 'Hộp Bí Ẩn Nửa Đêm',
      themeTag: 'Chủ đề Jackpot SSR',
      accentHexColor: 0xFF122033,
    ),
  ];

  /// Bể phần thưởng Hộp Mù Gacha (tổng trọng số = 100)
  static const List<BlindBoxPrizeSpec> blindBoxPrizePool = [
    BlindBoxPrizeSpec(
      id: 'BB_SSR_60K',
      title: '[SSR] Thẻ Kim Cương Freeship 60.000đ',
      description: 'Giảm thẳng 60.000đ cho đơn Giao hàng hoặc GrabFood từ 50.000đ + 150 Xu',
      rarity: PromoRarityTier.legendary,
      weight: 10,
      rewardType: PromoRewardType.voucher,
      voucherCodePrefix: 'BOXSSR60K',
      discountValue: 60000,
      isPercentage: false,
      maxDiscount: 60000,
      minOrderValue: 50000,
      bonusCoins: 150,
    ),
    BlindBoxPrizeSpec(
      id: 'BB_SSR_80P',
      title: '[SSR] Hộp Hoàng Kim Giảm 80% (Tối đa 50k)',
      description: 'Siêu voucher giảm 80% cước vận chuyển tối đa 50.000đ (đơn từ 35.000đ)',
      rarity: PromoRarityTier.legendary,
      weight: 8,
      rewardType: PromoRewardType.voucher,
      voucherCodePrefix: 'BOXSSR80P',
      discountValue: 80,
      isPercentage: true,
      maxDiscount: 50000,
      minOrderValue: 35000,
      bonusCoins: 100,
    ),
    BlindBoxPrizeSpec(
      id: 'BB_SR_35K',
      title: '[SR] Hộp Bạc Ưu Đãi Toàn Sàn 35.000đ',
      description: 'Giảm 35.000đ áp dụng mọi khung giờ Giao hàng & Đặt đồ ăn từ 40.000đ',
      rarity: PromoRarityTier.rare,
      weight: 22,
      rewardType: PromoRewardType.voucher,
      voucherCodePrefix: 'BOXSR35K',
      discountValue: 35000,
      isPercentage: false,
      maxDiscount: 35000,
      minOrderValue: 40000,
      bonusCoins: 50,
    ),
    BlindBoxPrizeSpec(
      id: 'BB_SR_50P_SPIN',
      title: '[SR] Hộp Ngọc Bích Giảm 50% (Tối đa 30k) + 1 Vé Quay',
      description: 'Tặng kèm mã giảm 50% tối đa 30.000đ và thêm 1 lượt Vòng Xoay May Mắn',
      rarity: PromoRarityTier.rare,
      weight: 20,
      rewardType: PromoRewardType.voucher,
      voucherCodePrefix: 'BOXSR50P',
      discountValue: 50,
      isPercentage: true,
      maxDiscount: 30000,
      minOrderValue: 25000,
      bonusCoins: 40,
      bonusSpinTickets: 1,
    ),
    BlindBoxPrizeSpec(
      id: 'BB_R_20K',
      title: '[R] Hộp Đồng Freeship 20.000đ Đơn 0Đ',
      description: 'Giảm ngay 20.000đ không yêu cầu giá trị đơn tối thiểu',
      rarity: PromoRarityTier.common,
      weight: 22,
      rewardType: PromoRewardType.voucher,
      voucherCodePrefix: 'BOXR20K',
      discountValue: 20000,
      isPercentage: false,
      maxDiscount: 20000,
      minOrderValue: 0,
      bonusCoins: 30,
    ),
    BlindBoxPrizeSpec(
      id: 'BB_R_COINS_SPIN',
      title: '[R] Rương Xu Bí Ẩn +350 GHST Xu & +1 Vé Quay',
      description: 'Cộng 350 GHST Xu tích lũy đổi quà và tặng ngay 1 lượt Vòng Xoay',
      rarity: PromoRarityTier.common,
      weight: 18,
      rewardType: PromoRewardType.coins,
      bonusCoins: 350,
      bonusSpinTickets: 1,
    ),
  ];

  static String formatDateKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static String formatTimeShort(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// Tính khung giờ Flash Sale kế tiếp kiểu Shopee (00:00, 09:00, 12:00, 18:00, 21:00)
  static ({String activeWindowLabel, Duration remaining}) resolveFlashCountdown(
    DateTime now,
  ) {
    const anchors = [0, 9, 12, 18, 21, 24];
    int nextHour = 24;
    int currentStart = 0;
    for (var i = 0; i < anchors.length - 1; i++) {
      if (now.hour >= anchors[i] && now.hour < anchors[i + 1]) {
        currentStart = anchors[i];
        nextHour = anchors[i + 1];
        break;
      }
    }
    final nextDt = nextHour == 24
        ? DateTime(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day, nextHour);
    final diff = nextDt.difference(now);
    final label =
        'Khung ${currentStart.toString().padLeft(2, '0')}:00 • Đang mở săn';
    return (
      activeWindowLabel: label,
      remaining: diff.isNegative ? const Duration(minutes: 45) : diff,
    );
  }

  /// Chọn ngẫu nhiên có trọng số 1 ô trên Vòng Xoay May Mắn
  static SpinWheelSegment rollWeightedSpinSegment({math.Random? random}) {
    final rng = random ?? math.Random();
    final totalWeight = spinWheelSegments.fold<int>(0, (s, e) => s + e.weight);
    var pick = rng.nextInt(totalWeight);
    for (final seg in spinWheelSegments) {
      if (pick < seg.weight) {
        return seg;
      }
      pick -= seg.weight;
    }
    return spinWheelSegments.first;
  }

  /// Chọn ngẫu nhiên có trọng số 1 phần thưởng trong Hộp Mù Bí Ẩn
  static BlindBoxPrizeSpec rollWeightedBlindBoxPrize({math.Random? random}) {
    final rng = random ?? math.Random();
    final totalWeight = blindBoxPrizePool.fold<int>(0, (s, e) => s + e.weight);
    var pick = rng.nextInt(totalWeight);
    for (final prize in blindBoxPrizePool) {
      if (pick < prize.weight) {
        return prize;
      }
      pick -= prize.weight;
    }
    return blindBoxPrizePool.first;
  }

  /// Tổng hợp tiến độ Nhiệm vụ Săn Lượt & Xu dựa trên hoạt động đơn hàng thực tế của khách
  static List<PromoMissionProgress> evaluateCustomerMissions({
    required List<ActiveOrderRecord> customerOrders,
    required Set<String> claimedMissionIds,
  }) {
    final validOrders = customerOrders
        .where((o) => o.paymentStatus != 'RETURNED')
        .toList();
    final totalOrdersCount = validOrders.length;
    final grabFoodCount = validOrders
        .where((o) => o.packageDescription.contains('[GrabFood'))
        .length;
    final ecoGreenCount = validOrders
        .where((o) => o.preferEcoEv || o.greenFundContributed)
        .length;

    return [
      PromoMissionProgress(
        id: 'MIS_FIRST_SHIP',
        title: 'Khởi hành siêu tốc đầu tiên',
        description: 'Đặt 1 đơn giao hàng GPS hoặc đặt món bất kỳ trên ứng dụng',
        currentCount: totalOrdersCount.clamp(0, 1),
        targetCount: 1,
        rewardCoins: 100,
        rewardSpinTickets: 1,
        rewardBlindBoxTickets: 0,
        isClaimed: claimedMissionIds.contains('MIS_FIRST_SHIP'),
      ),
      PromoMissionProgress(
        id: 'MIS_GRABFOOD_FAN',
        title: 'Tín đồ Ẩm thực GrabFood',
        description: 'Đặt thành công 1 đơn món ngon tại mục Ăn uống (GrabFood)',
        currentCount: grabFoodCount.clamp(0, 1),
        targetCount: 1,
        rewardCoins: 150,
        rewardSpinTickets: 0,
        rewardBlindBoxTickets: 1,
        isClaimed: claimedMissionIds.contains('MIS_GRABFOOD_FAN'),
      ),
      PromoMissionProgress(
        id: 'MIS_XANH_ECO_HERO',
        title: 'Đại sứ Giao Xanh Không Khói',
        description: 'Có 1 chuyến bật Xe máy điện EV hoặc đóng góp Quỹ Xanh',
        currentCount: ecoGreenCount.clamp(0, 1),
        targetCount: 1,
        rewardCoins: 200,
        rewardSpinTickets: 1,
        rewardBlindBoxTickets: 1,
        isClaimed: claimedMissionIds.contains('MIS_XANH_ECO_HERO'),
      ),
      PromoMissionProgress(
        id: 'MIS_SUPER_USER_3',
        title: 'Thợ Săn Đơn Hàng Thân Thiết',
        description: 'Tích lũy đủ 3 đơn hàng trên siêu ứng dụng GHST Express',
        currentCount: totalOrdersCount.clamp(0, 3),
        targetCount: 3,
        rewardCoins: 300,
        rewardSpinTickets: 1,
        rewardBlindBoxTickets: 2,
        isClaimed: claimedMissionIds.contains('MIS_SUPER_USER_3'),
      ),
    ];
  }
}
