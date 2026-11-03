import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  // Daylight Sapphire & Luminous Mint + Obsidian Aurora Dark System
  static const Color ink = Color(0xFF0B1324);
  static const Color paper = Color(0xFFEEF3FA);
  static const Color studioDark = Color(0xFF0B1324);
  static const Color techBg = Color(0xFF0B1324);
  static const Color techPanel = Color(0xFF16233B);
  static const Color violet = Color(0xFF2563EB);
  static const Color pink = Color(0xFFF43F5E);
  static const Color acid = Color(0xFF6EE7B7);
  static const Color gold = Color(0xFFF59E0B);
  static const Color warmStone = Color(0xFFE7EFFA);
  static const Color line = Color(0xFFD8E2F0);
  static const Color controlBorder = Color(0xFFC4D2E6);
  static const Color techLine = Color(0x29CBD5E1);
  static const Color techMuted = Color(0xFF94A3B8);

  // Semantic accents
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF3B82F6);
  static const Color primarySoft = Color(0xFFEAF2FF);
  static const Color primaryBorder = Color(0xFFBFDBFE);
  static const Color accent = Color(0xFFF43F5E);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  // Light surfaces & ink
  static const Color background = Color(0xFFEEF3FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFF6F9FE);
  static const Color darkSidebar = Color(0xFF0B1324);
  static const Color textPrimary = Color(0xFF0B1324);
  static const Color textSecondary = Color(0xFF3E4E68);
  static const Color divider = Color(0xFFD8E2F0);
  static const Color shimmerBase = Color(0xFFE7EFFA);
  static const Color shimmerHighlight = Color(0xFFF6F9FE);

  // Dark Obsidian Aurora surfaces & ink
  static const Color darkCanvas = Color(0xFF070D19);
  static const Color darkSurface = Color(0xFF111C30);
  static const Color darkSurfaceSubtle = Color(0xFF16233B);
  static const Color darkSurfaceMuted = Color(0xFF1D2D49);
  static const Color darkBorder = Color(0xFF22324F);
  static const Color darkControlBorder = Color(0xFF31476E);
  static const Color darkTextPrimary = Color(0xFFF1F5FB);
  static const Color darkTextSecondary = Color(0xFFB4C3D9);

  // 3D Map & Route Ribbon
  static const Color routeRibbonFill = Color(0xFF2563EB);
  static const Color routeRibbonCasing = Color(0xFF1E3A8A);
  static const Color buildingExtrusion = Color(0xFFD6E0EE);

  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0E0F172A),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Color(0x062563EB),
      blurRadius: 6,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> elevatedShadow = [
    BoxShadow(
      color: Color(0x1A0F172A),
      blurRadius: 30,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x0C2563EB),
      blurRadius: 10,
      offset: Offset(0, 3),
    ),
  ];
}
