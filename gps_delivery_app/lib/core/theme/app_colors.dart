import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  // Bảng màu Maritime Slate & Express Sapphire dịu mắt, chống chói
  static const Color ink = Color(0xFF122033);
  static const Color paper = Color(0xFFEEF3F8);
  static const Color studioDark = Color(0xFF1B2C44);
  static const Color techBg = Color(0xFF162438);
  static const Color techPanel = Color(0xFF1F314B);
  static const Color violet = Color(0xFF1E56C5);
  static const Color pink = Color(0xFFC85A17);
  static const Color acid = Color(0xFFA8E6CF);
  static const Color gold = Color(0xFFEAB344);
  static const Color warmStone = Color(0xFFE3EBF3);
  static const Color line = Color(0xFFD7E0EC);
  static const Color controlBorder = Color(0xFF78899F);
  static const Color techLine = Color(0x24E2E8F0);
  static const Color techMuted = Color(0xFF9EB0C7);

  // Bề mặt ngữ nghĩa phụ trợ (tint dịu mắt)
  static const Color primarySoft = Color(0xFFE8EFFC);
  static const Color primaryBorder = Color(0xFFC2D4F8);
  static const Color primaryInk = Color(0xFF163E91);
  static const Color teal = Color(0xFF0E7C66);
  static const Color tealSoft = Color(0xFFE4F5F0);
  static const Color accentSoft = Color(0xFFFDF0E7);
  static const Color warningSoft = Color(0xFFFEF6E4);
  static const Color warningInk = Color(0xFF734806);
  static const Color dangerSoft = Color(0xFFFCECEC);

  // Ánh xạ ngữ nghĩa toàn hệ thống
  static const Color primary = Color(0xFF1E56C5);
  static const Color accent = Color(0xFFC85A17);
  static const Color success = Color(0xFF0F7B55);
  static const Color warning = Color(0xFFEAB344);
  static const Color danger = Color(0xFFC43232);

  // Bảng màu trung tính & bề mặt
  static const Color background = Color(0xFFEEF3F8);
  static const Color surface = Color(0xFFFCFDFE);
  static const Color surfaceSubtle = Color(0xFFF5F8FC);
  static const Color darkSidebar = Color(0xFF162438);
  static const Color textPrimary = Color(0xFF122033);
  static const Color textSecondary = Color(0xFF516278);
  static const Color divider = Color(0xFFD7E0EC);
  static const Color shimmerBase = Color(0xFFE3EBF3);
  static const Color shimmerHighlight = Color(0xFFF4F7FB);

  // Bảng màu Bản đồ 3D & Dải lộ trình điều hướng
  static const Color routeRibbonFill = Color(0xFF1E56C5);
  static const Color routeRibbonCasing = Color(0xFF163A82);
  static const Color buildingExtrusion = Color(0xFFD5DFEC);

  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0E0F172A),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Color(0x060F172A),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> elevatedShadow = [
    BoxShadow(
      color: Color(0x140F172A),
      blurRadius: 28,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x080F172A),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];
}
