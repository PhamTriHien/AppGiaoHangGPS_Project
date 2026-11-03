import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  // Bảng màu Modern Super-App Daylight & Clean Slate (Minh Nhân 66aeb36)
  static const Color ink = Color(0xFF0F172A);
  static const Color paper = Color(0xFFF4F7FA);
  static const Color studioDark = Color(0xFF0F172A);
  static const Color techBg = Color(0xFF0F172A);
  static const Color techPanel = Color(0xFF1E293B);
  static const Color violet = Color(0xFF2563EB);
  static const Color pink = Color(0xFFF43F5E);
  static const Color acid = Color(0xFF6EE7B7);
  static const Color gold = Color(0xFFF59E0B);
  static const Color warmStone = Color(0xFFEFF3F8);
  static const Color line = Color(0xFFE2E8F0);
  static const Color controlBorder = Color(0xFFCBD5E1);
  static const Color techLine = Color(0x26CBD5E1);
  static const Color techMuted = Color(0xFF94A3B8);

  // Ánh xạ ngữ nghĩa toàn hệ thống
  static const Color primary = Color(0xFF2563EB);
  static const Color primarySoft = Color(0xFFEFF6FF);
  static const Color primaryBorder = Color(0xFFBFDBFE);
  static const Color accent = Color(0xFFF43F5E);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  // Bảng màu trung tính & bề mặt
  static const Color background = Color(0xFFF4F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFF8FAFC);
  static const Color darkSidebar = Color(0xFF0F172A);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color divider = Color(0xFFE2E8F0);
  static const Color shimmerBase = Color(0xFFEFF3F8);
  static const Color shimmerHighlight = Color(0xFFF8FAFC);

  // Bảng màu Bản đồ 3D & Dải lộ trình điều hướng
  static const Color routeRibbonFill = Color(0xFF2563EB);
  static const Color routeRibbonCasing = Color(0xFF1E3A8A);
  static const Color buildingExtrusion = Color(0xFFDAE2EC);

  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0A0F172A),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x050F172A),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> elevatedShadow = [
    BoxShadow(
      color: Color(0x140F172A),
      blurRadius: 28,
      offset: Offset(0, 10),
    ),
    BoxShadow(
      color: Color(0x080F172A),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
}
