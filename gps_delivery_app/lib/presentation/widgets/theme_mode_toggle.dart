import 'package:flutter/material.dart';

import '../../core/theme/ghst_theme_tokens.dart';
import '../../core/theme/theme_controller.dart';
import 'animated_3d_ui_icons.dart';
import 'ghst_button_icon.dart';

class ThemeModeIconButton extends StatelessWidget {
  const ThemeModeIconButton({
    super.key,
    this.onDarkHeader = false,
    this.compact = false,
  });

  final bool onDarkHeader;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = ThemeControllerScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tokens = GhstThemeTokens.of(context);
    final size = compact ? 34.0 : 38.0;
    final bgColor = onDarkHeader
        ? Colors.white.withValues(alpha: 0.08)
        : (isDark ? tokens.cardMuted : tokens.sapphire.fill);
    final borderColor = onDarkHeader
        ? Colors.white.withValues(alpha: 0.16)
        : (isDark ? tokens.borderStrong : tokens.sapphire.border);

    final label = isDark
        ? 'Chuyển sang giao diện sáng'
        : 'Chuyển sang giao diện tối';

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Material(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: const Key('theme-mode-icon-toggle'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => controller.cycleThemeMode(context),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              alignment: Alignment.center,
              child: GhstAiIcon(
                style: Icon3dStyle.themeSunMoon,
                size: compact ? 22 : 24,
                circular: true,
                selected: isDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ThemeModeSelectorCard extends StatelessWidget {
  const ThemeModeSelectorCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeControllerScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    final tokens = GhstThemeTokens.of(context);
    final mode = controller.themeMode;

    Widget option({
      required ThemeMode value,
      required GhstActionKind iconKind,
      required String label,
      required Key key,
    }) {
      final selected = mode == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: Material(
            color: selected ? tokens.primary : tokens.cardSubtle,
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(11),
              onTap: () => controller.setThemeMode(value),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: selected ? tokens.primary : tokens.border,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GhstButtonIcon.glyph(
                      iconKind,
                      size: 16,
                      color: selected ? Colors.white : tokens.inkSecondary,
                      selected: selected,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : tokens.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GhstLuminousCard(
      padding: const EdgeInsets.all(14),
      accentGlow: tokens.sapphire.glow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GhstAiIcon(
                style: Icon3dStyle.themeSunMoon,
                size: 36,
                borderRadius: 10,
                selected: tokens.isDark,
                borderColor: tokens.sapphire.border,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chủ đề hiển thị',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: tokens.ink,
                      ),
                    ),
                    Text(
                      'Tự động đồng bộ trên mọi thiết bị của tài khoản',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: tokens.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              option(
                value: ThemeMode.light,
                iconKind: GhstActionKind.sun,
                label: 'Sáng',
                key: const Key('theme-mode-light'),
              ),
              const SizedBox(width: 8),
              option(
                value: ThemeMode.dark,
                iconKind: GhstActionKind.moon,
                label: 'Tối',
                key: const Key('theme-mode-dark'),
              ),
              const SizedBox(width: 8),
              option(
                value: ThemeMode.system,
                iconKind: GhstActionKind.autoTheme,
                label: 'Hệ thống',
                key: const Key('theme-mode-system'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
